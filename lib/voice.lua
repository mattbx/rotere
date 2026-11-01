-- rotere voice output
-- one place where hits become sound: polyperc and/or midi out.
-- nb players slot in here later without touching physics or ui.

local musicutil = require "musicutil"

local Voice = {}

local scale_notes = {}
local MAX_NOTES_PER_TICK = 6 -- guards against a burst flooding the engine / midi
local notes_this_tick = 0

local OUTPUTS = {"engine", "midi", "engine + midi"}
local midi_out = nil
local active = {} -- midi notes currently on: note -> {t = off time, ch = channel}

-- octave ranges a hit can land in, around the base note (arp order = listed order)
local OCTAVE_NAMES = {"off", "+1", "+2", "-1", "-2", "+/-1", "+/-2"}
local OCTAVE_SETS = {
  {0}, {0, 1}, {0, 1, 2}, {0, -1}, {0, -1, -2}, {-1, 0, 1}, {-2, -1, 0, 1, 2},
}

local function build_scale()
  scale_notes = musicutil.generate_scale(
    params:get("root") - 1, params:get("scale"), 10)
end

local function engine_on() local o = params:get("output"); return o == 1 or o == 3 end
local function midi_on() local o = params:get("output"); return o == 2 or o == 3 end

-- send note-off for everything still sounding (device / channel / output change, quit)
local function all_midi_off()
  if midi_out then
    for n, a in pairs(active) do midi_out:note_off(n, 0, a.ch) end
  end
  active = {}
end

function Voice.add_params()
  params:add_separator("rotere_output", "output")
  params:add_option("output", "output", OUTPUTS, 1)
  params:set_action("output", function() all_midi_off() end)

  local devs = {}
  for i = 1, #midi.vports do
    devs[i] = i .. ": " .. (midi.vports[i].name or "none")
  end
  params:add_option("midi_device", "midi device", devs, 1)
  params:set_action("midi_device", function(i)
    all_midi_off()
    midi_out = midi.connect(i)
  end)
  params:add_number("midi_ch", "midi channel", 1, 16, 1)
  params:set_action("midi_ch", function() all_midi_off() end)
  params:add_control("note_len", "midi note length",
    controlspec.new(10, 2000, "exp", 1, 150, "ms"))

  params:add_separator("rotere_notes", "notes")
  params:add_option("root", "root", musicutil.NOTE_NAMES, 1)
  params:set_action("root", build_scale)

  local names = {}
  for i, s in ipairs(musicutil.SCALES) do names[i] = s.name end
  params:add_option("scale", "scale", names, 1)
  params:set_action("scale", build_scale)

  params:add_option("octaves", "octaves", OCTAVE_NAMES, 1)
  params:add_option("octave_pick", "octave pick", {"arp", "random", "by wall"}, 1)
  params:add_number("transpose", "transpose", -24, 24, 0, function(p)
    local v = p:get()
    return (v > 0 and "+" or "") .. v .. " st"
  end)
  params:add_control("probability", "probability", controlspec.new(0, 100, "lin", 1, 100, "%", 0.01))

  params:add_number("dyn_floor", "quietest hit", 1, 127, 20)
  params:add_control("pan_width", "pan width", controlspec.new(0, 1, "lin", 0.01, 0.7))

  params:add_separator("rotere_polyperc", "polyperc")
  params:add_control("pp_amp", "amp", controlspec.new(0, 1, "lin", 0, 0.5))
  params:add_control("pp_release", "release", controlspec.new(0.05, 4, "exp", 0, 0.6, "s"))
  params:set_action("pp_release", function(x) engine.release(x) end)
  params:add_control("pp_cutoff", "cutoff", controlspec.new(50, 8000, "exp", 0, 1200, "hz"))
  params:set_action("pp_cutoff", function(x) engine.cutoff(x) end)
  params:add_control("pp_pw", "pw", controlspec.new(0.05, 0.95, "lin", 0, 0.5))
  params:set_action("pp_pw", function(x) engine.pw(x) end)
  params:add_control("pp_gain", "gain", controlspec.new(0, 4, "lin", 0, 1))
  params:set_action("pp_gain", function(x) engine.gain(x) end)

  build_scale()
end

-- snap any midi note to the current scale (so scale changes retune the balls live)
function Voice.quantise(note)
  return musicutil.snap_note_to_array(note, scale_notes)
end

-- a random scale note in a playable range, until midi / grid input goes in
function Voice.random_note()
  local lo, hi = 48, 72
  local pool = {}
  for _, n in ipairs(scale_notes) do
    if n >= lo and n <= hi then pool[#pool + 1] = n end
  end
  return pool[math.random(#pool)]
end

-- roll for whether a hit sounds at all (probability param)
function Voice.chance()
  local p = params:get("probability")
  return p >= 100 or math.random() * 100 < p
end

-- which octave a hit plays in.
-- arp: each ball steps through the range on successive hits, then wraps.
-- random: any octave in the range. by wall: each wall has its own octave, so the
-- mapping turns with the shape (ball-on-ball hits fall back to random).
function Voice.octave_for(ball, wall)
  local set = OCTAVE_SETS[params:get("octaves")]
  if #set == 1 then return 0 end
  local pick = params:get("octave_pick")
  if pick == 1 then
    local i = (ball.oct_step or 0) % #set + 1
    ball.oct_step = i
    return set[i]
  elseif pick == 3 and wall then
    return set[(wall - 1) % #set + 1]
  end
  return set[math.random(#set)]
end

-- call once per physics tick before hits are played: resets the burst guard
-- and sends any midi note-offs that are due
function Voice.tick()
  notes_this_tick = 0
  if next(active) ~= nil then
    local now = util.time()
    for n, a in pairs(active) do
      if now >= a.t then
        if midi_out then midi_out:note_off(n, 0, a.ch) end
        active[n] = nil
      end
    end
  end
end

-- polyperc only has pan on newer norns updates - check once so older ones don't error
local has_pan = nil
local function engine_has_pan()
  if has_pan == nil then
    has_pan = engine.commands ~= nil and engine.commands.pan ~= nil
  end
  return has_pan
end

-- note: midi note number, vel: 1-127, pos: -1 (left) .. 1 (right), where the hit happened,
-- octave: octave offset for this hit (from Voice.octave_for)
function Voice.play(note, vel, pos, octave)
  if notes_this_tick >= MAX_NOTES_PER_TICK then return end
  notes_this_tick = notes_this_tick + 1

  -- scale first, then octave and transpose shift the result (transpose moves the key too)
  local n = Voice.quantise(note) + (octave or 0) * 12 + params:get("transpose")
  n = util.clamp(n, 0, 127)
  local floor = params:get("dyn_floor")
  local v = floor + (vel - 1) * (127 - floor) / 126 -- lift soft hits so they're still audible

  if engine_on() then
    if pos and engine_has_pan() then
      engine.pan(util.clamp(pos, -1, 1) * params:get("pan_width"))
    end
    engine.amp(params:get("pp_amp") * v / 127)
    engine.hz(musicutil.note_num_to_freq(n))
  end

  if midi_on() and midi_out then
    local ch = params:get("midi_ch")
    local a = active[n]
    if a then midi_out:note_off(n, 0, a.ch) end -- same note still on: cut it so it retriggers cleanly
    -- mark it sounding *before* sending, so an instant midi-thru echo is already recognised
    active[n] = {t = util.time() + params:get("note_len") / 1000, ch = ch}
    midi_out:note_on(n, util.clamp(math.floor(v + 0.5), 1, 127), ch)
  end
end

-- true if rotere is currently sending this note out over midi (used to ignore midi thru echoes)
function Voice.is_sounding(note)
  return midi_on() and active[note] ~= nil
end

function Voice.cleanup()
  all_midi_off()
end

return Voice
