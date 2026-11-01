-- rotere note input
-- play a key on a midi keyboard -> a ball with that note drops in, like the op-1.
-- grid as a keyboard slots in here later.

local Input = {}

local in_dev = nil
local drop_fn = nil       -- function(note) supplied by the main script
local is_echo_fn = nil    -- function(note) -> true if we just sent this note out ourselves

local function handle(data)
  local msg = midi.to_msg(data)
  if msg.type ~= "note_on" or msg.vel == 0 then return end
  local ch = params:get("midi_in_ch") -- 1 = omni, 2..17 = channel 1..16
  if ch > 1 and msg.ch ~= ch - 1 then return end
  -- if the keyboard / synth echoes our own midi out back in (midi thru),
  -- ignore it, or every hit would drop a new ball and run away
  if is_echo_fn and is_echo_fn(msg.note) then return end
  drop_fn(msg.note)
end

local function connect(i)
  if in_dev then in_dev.event = nil end
  in_dev = midi.connect(i)
  in_dev.event = handle
end

function Input.add_params(drop, is_echo)
  drop_fn, is_echo_fn = drop, is_echo

  params:add_separator("rotere_input", "input")
  local devs = {}
  for i = 1, #midi.vports do
    devs[i] = i .. ": " .. (midi.vports[i].name or "none")
  end
  params:add_option("midi_in_device", "midi in device", devs, 1)
  params:set_action("midi_in_device", connect)

  local chans = {"omni"}
  for c = 1, 16 do chans[c + 1] = tostring(c) end
  params:add_option("midi_in_ch", "midi in channel", chans, 1)
end

function Input.cleanup()
  if in_dev then in_dev.event = nil end
end

return Input
