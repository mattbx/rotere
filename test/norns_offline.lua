-- norns_offline: run a norns script in plain Lua 5.3, off the device
--
-- stubs the norns globals a typical script touches (screen, params, controlspec,
-- metro, util, midi, engine, musicutil) so you can load a script, press keys, turn
-- encoders, advance time and inspect what it did: engine calls, midi sent, screen
-- drawing. no audio, no real screen, no clock - just behaviour.
--
--   local N = dofile("test/norns_offline.lua")
--   local sim = N.load{ root = ".", script = "rotere.lua" }
--   sim.key(2, 1); sim.key(2, 0)        -- press K2
--   sim.enc(1, 5)                       -- turn E1
--   sim.run(2.0)                        -- advance 2 s, firing metros in time order
--   print(#sim.engine.calls, #sim.midi.sent)
--   local frame = sim.draw()            -- screen ops from one redraw()
--
-- run from the script's folder with: lua5.3 test/<your test>.lua
-- (debian/ubuntu: apt install lua5.3, mac: brew install lua@5.3)

local N = {}

-- small musicutil subset (the parts scripts commonly use)
local function musicutil_stub()
  local MU = {}
  MU.NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
  MU.SCALES = {
    {name = "Major", intervals = {0, 2, 4, 5, 7, 9, 11, 12}},
    {name = "Natural Minor", intervals = {0, 2, 3, 5, 7, 8, 10, 12}},
    {name = "Major Pentatonic", intervals = {0, 2, 4, 7, 9, 12}},
    {name = "Minor Pentatonic", intervals = {0, 3, 5, 7, 10, 12}},
    {name = "Chromatic", intervals = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}},
  }
  function MU.generate_scale(root, scale, octaves)
    local s = type(scale) == "number" and MU.SCALES[scale] or MU.SCALES[1]
    local out = {}
    for o = 0, (octaves or 1) - 1 do
      for i = 1, #s.intervals - 1 do out[#out + 1] = root + o * 12 + s.intervals[i] end
    end
    return out
  end
  function MU.snap_note_to_array(n, arr)
    local best, bd = arr[1], math.huge
    for _, v in ipairs(arr) do
      local d = math.abs(v - n)
      if d < bd then best, bd = v, d end
    end
    return best
  end
  function MU.note_num_to_freq(n) return 440 * 2 ^ ((n - 69) / 12) end
  function MU.freq_to_note_num(f) return math.floor(69 + 12 * math.log(f / 440, 2) + 0.5) end
  function MU.note_num_to_name(n) return MU.NOTE_NAMES[n % 12 + 1] end
  return MU
end

-- opts: root (folder holding the script + lib/), script (file name),
--       engine_commands (list of command names the engine reports, e.g. {"pan"}),
--       midi_names (port names, index = port), echo (true: midi out on a port loops back in)
function N.load(opts)
  opts = opts or {}
  local root = opts.root or "."
  local sim = {t = 0}

  -- time
  util = {
    time = function() return sim.t end,
    clamp = function(x, a, b) return math.max(a, math.min(b, x)) end,
    linlin = function(a, b, c, d, x) return c + (x - a) / (b - a) * (d - c) end,
    round = function(x, q) q = q or 1; return math.floor(x / q + 0.5) * q end,
  }

  -- screen: every call is recorded as {name, args...}
  local ops = {}
  screen = setmetatable({}, {__index = function(_, k)
    return function(...) ops[#ops + 1] = {k, ...} end
  end})

  -- params
  local P, actions, order, specs = {}, {}, {}, {}
  controlspec = {new = function(min, max, warp, step, default, units, quantum)
    return {minval = min, maxval = max, warp = warp, step = step, default = default, units = units, quantum = quantum or 0.01}
  end}
  local function add(id, value, spec) P[id] = value; specs[id] = spec; order[#order + 1] = id end
  params = {
    add_separator = function() end,
    add_group = function() end,
    add_option = function(_, id, _, options, default) add(id, default or 1, {kind = "option", n = #options}) end,
    add_number = function(_, id, _, min, max, default) add(id, default or min, {kind = "number", min = min, max = max}) end,
    add_control = function(_, id, _, cs) add(id, cs.default, {kind = "control", cs = cs}) end,
    add_binary = function(_, id, _, _, default) add(id, default or 0, {kind = "number", min = 0, max = 1}) end,
    set_action = function(_, id, f) actions[id] = f end,
    get = function(_, id) return P[id] end,
    set = function(self, id, v) P[id] = v; if actions[id] then actions[id](v) end end,
    delta = function(self, id, d)
      local s, v = specs[id], P[id]
      if s.kind == "option" then v = math.max(1, math.min(s.n, v + d))
      elseif s.kind == "number" then v = math.max(s.min, math.min(s.max, v + d))
      else
        local cs = s.cs
        v = math.max(cs.minval, math.min(cs.maxval, v + d * cs.quantum * (cs.maxval - cs.minval)))
      end
      self:set(id, v)
    end,
    bang = function() for _, id in ipairs(order) do if actions[id] then actions[id](P[id]) end end end,
  }

  -- metros: fired in time order by sim.run
  sim.metros = {}
  metro = {init = function()
    local m = {time = 1, count = -1, running = false}
    function m:start() self.running = true; self.next = sim.t + self.time end
    function m:stop() self.running = false end
    sim.metros[#sim.metros + 1] = m
    return m
  end}

  -- engine: every command recorded as {name, args...}
  sim.engine = {calls = {}}
  local cmds = {}
  for _, c in ipairs(opts.engine_commands or {}) do cmds[c] = {} end
  engine = setmetatable({commands = cmds}, {__index = function(_, k)
    return function(...) sim.engine.calls[#sim.engine.calls + 1] = {k, ...} end
  end})

  -- midi: ports are cached per index like on norns. sent messages are logged.
  sim.midi = {sent = {}}
  local ports = {}
  midi = {vports = {}}
  for i = 1, 16 do midi.vports[i] = {name = (opts.midi_names or {})[i] or "none"} end
  function midi.connect(i)
    i = i or 1
    if ports[i] then return ports[i] end
    local p = {}
    local function log(kind, n, v, ch)
      sim.midi.sent[#sim.midi.sent + 1] = {kind = kind, note = n, vel = v, ch = ch or 1, port = i, t = sim.t}
    end
    function p:note_on(n, v, ch)
      log("note_on", n, v, ch)
      if sim.echo and self.event then self.event({0x90 + (ch or 1) - 1, n, v}) end -- midi thru
    end
    function p:note_off(n, v, ch) log("note_off", n, v, ch) end
    function p:cc(c, v, ch) log("cc", c, v, ch) end
    ports[i] = p
    return p
  end
  function midi.to_msg(d)
    local st = d[1] & 0xF0
    local types = {[0x90] = "note_on", [0x80] = "note_off", [0xB0] = "cc"}
    return {type = types[st] or "other", ch = (d[1] & 0x0F) + 1, note = d[2], vel = d[3], cc = d[2], val = d[3]}
  end
  sim.echo = opts.echo or false

  package.preload.musicutil = musicutil_stub
  function include(p) return dofile(root .. "/" .. p .. ".lua") end

  dofile(root .. "/" .. (opts.script or "main.lua"))
  if init then init() end

  -- helpers ---------------------------------------------------------------
  function sim.key(n, z) key(n, z) end
  function sim.press(n) key(n, 1); key(n, 0) end
  function sim.enc(n, d)
    local step = d > 0 and 1 or -1
    for _ = 1, math.abs(d) do enc(n, step) end
  end
  -- incoming midi bytes on a port, e.g. sim.midi_in(1, {0x90, 60, 100})
  function sim.midi_in(port, bytes)
    local p = midi.connect(port)
    if p.event then p.event(bytes) end
  end
  -- advance time, firing each running metro at its own interval, in time order
  function sim.run(seconds)
    local stop = sim.t + seconds
    while true do
      local nextm
      for _, m in ipairs(sim.metros) do
        if m.running and (not nextm or m.next < nextm.next) then nextm = m end
      end
      if not nextm or nextm.next > stop then break end
      sim.t = nextm.next
      nextm.next = nextm.next + nextm.time
      nextm.event()
    end
    sim.t = stop
  end
  -- screen ops from one redraw()
  function sim.draw()
    ops = {}
    redraw()
    return ops
  end
  -- read a script-local variable that a global function closes over, e.g. sim.local_of(redraw, "world")
  function sim.local_of(fn, name)
    for i = 1, 200 do
      local n, v = debug.getupvalue(fn, i)
      if n == nil then return nil end
      if n == name then return v end
    end
  end
  -- notes the engine was asked to play (via engine.hz), as midi note numbers
  function sim.engine_notes()
    local out = {}
    for _, c in ipairs(sim.engine.calls) do
      if c[1] == "hz" then out[#out + 1] = math.floor(69 + 12 * math.log(c[2] / 440, 2) + 0.5) end
    end
    return out
  end
  function sim.params() return P end
  return sim
end

-- tiny assert helper for test files: N.check(name, ok, detail)
N.passed, N.failed = 0, 0
function N.check(name, ok, detail)
  if ok then N.passed = N.passed + 1 else N.failed = N.failed + 1 end
  print(string.format("%s  %s%s", ok and "pass" or "FAIL", name, detail and ("  (" .. detail .. ")") or ""))
end
function N.summary()
  print(string.format("\n%d passed, %d failed", N.passed, N.failed))
  if N.failed > 0 then os.exit(1) end
end

return N
