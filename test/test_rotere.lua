-- rotere behaviour tests, run off-device from the repo root:
--   lua5.3 test/test_rotere.lua
-- every check here was first done by hand while building rotere; this keeps them repeatable.

local N = dofile("test/norns_offline.lua")
local check = N.check

local function fresh(opts)
  math.randomseed(1)
  opts = opts or {}
  opts.root, opts.script = ".", "rotere.lua"
  opts.engine_commands = opts.engine_commands or {"pan"}
  local sim = N.load(opts)
  return sim, sim.local_of(redraw, "world")
end

local function count(t, f) local n = 0; for _, v in ipairs(t) do if f(v) then n = n + 1 end end; return n end

print("-- keys and balls")
do
  local sim, world = fresh()
  sim.press(2)
  check("K2 drops one ball", #world.balls == 1)
  sim.key(1, 1); sim.press(2); sim.key(1, 0)
  check("K1 + K2 still drops one ball", #world.balls == 2)
  sim.press(3)
  check("K3 empties", #world.balls == 0)
  for n = 30, 90 do sim.midi_in(1, {0x90, n, 100}) end
  check("24 ball cap holds against a midi flood", #world.balls == 24, #world.balls .. " balls")
end

print("-- shape")
do
  local sim, world = fresh()
  for _ = 1, 12 do sim.press(2) end
  sim.enc(1, 20); sim.run(3)
  sim.key(1, 1); sim.enc(2, -3); sim.key(1, 0); sim.run(1)
  check("changing to 3 sides keeps the balls", #world.balls == 12, #world.balls .. " of 12")
  check("sides param clamps at 3", world.sides == 3)
end

print("-- opening")
do
  -- triangle, knob turned up slowly at slow spin: balls must get out (they used to be trapped)
  local sim, world = fresh()
  sim.key(1, 1); sim.enc(2, -3); sim.key(1, 0)
  for _ = 1, 6 do sim.press(2) end
  sim.enc(1, 4); sim.run(2)
  sim.key(1, 1)
  for _ = 1, 60 do sim.enc(3, 1); sim.run(0.05) end
  sim.key(1, 0); sim.run(15)
  check("triangle opened to 60% releases balls", #world.balls < 6, (6 - #world.balls) .. " of 6 out")
  -- 5+ sides: the minimum-gap rule must never change the walls (inner end = full half length)
  local P = dofile("lib/physics.lua")
  local untouched = true
  for n = 5, 8 do
    local w = P.new{sides = n}
    for k = 0, 100 do
      w.open = k / 100; w:_update_walls()
      local half = w.radius * math.tan(math.pi / n)
      for _, wl in ipairs(w.walls) do
        local inner = math.sqrt((wl.bx - wl.mx) ^ 2 + (wl.by - wl.my) ^ 2)
        if math.abs(inner - half) > 1e-9 then untouched = false end
      end
    end
  end
  check("5+ sided shapes open exactly as before", untouched)
end

print("-- knob curves")
do
  local sim, world = fresh()
  local p = sim.params()
  params:set("gravity", 0); check("gravity 0% = zero gravity", world.gravity == 0)
  params:set("gravity", 100); check("gravity 100% = 160", math.abs(world.gravity - 160) < 1e-6)
  params:set("mass", 0); check("mass 0% = very bouncy (0.98)", math.abs(world.restitution - 0.98) < 1e-6)
  params:set("mass", 100); check("mass 100% = dead (0.40)", math.abs(world.restitution - 0.40) < 1e-6)
  params:set("gravity", 50); sim.enc(2, 1)
  check("E2 moves gravity 1% per click", p.gravity == 51)
end

print("-- sound out")
do
  local sim, world = fresh()
  for _ = 1, 8 do sim.press(2) end
  sim.enc(1, 10); sim.run(10)
  local notes = sim.engine_notes()
  check("hits play the engine", #notes > 20, #notes .. " notes in 10 s")
  local pans = count(sim.engine.calls, function(c) return c[1] == "pan" end)
  check("engine notes are panned", pans > 0)
  check("no midi when output = engine", #sim.midi.sent == 0)
end

do -- older polyperc without pan must not error
  local sim, world = fresh{engine_commands = {}}
  for _ = 1, 8 do sim.press(2) end
  sim.enc(1, 10); sim.run(5)
  check("no pan calls on an engine without pan", count(sim.engine.calls, function(c) return c[1] == "pan" end) == 0)
end

print("-- midi out")
do
  local sim, world = fresh()
  params:set("output", 2)
  for _ = 1, 8 do sim.press(2) end
  sim.enc(1, 10); sim.run(10)
  local ons = count(sim.midi.sent, function(m) return m.kind == "note_on" end)
  check("midi output sends notes", ons > 20, ons .. " note-ons")
  check("no engine notes when output = midi", #sim.engine_notes() == 0)
  params:set("midi_ch", 5)
  local held = {}
  for _, m in ipairs(sim.midi.sent) do
    local k = m.ch .. ":" .. m.note
    held[k] = (held[k] or 0) + (m.kind == "note_on" and 1 or m.kind == "note_off" and -1 or 0)
  end
  local stuck = 0; for _, v in pairs(held) do if v > 0 then stuck = stuck + v end end
  check("channel change leaves nothing hanging", stuck == 0, stuck .. " stuck")
  sim.run(5); cleanup()
  held = {}
  for _, m in ipairs(sim.midi.sent) do
    local k = m.ch .. ":" .. m.note
    held[k] = (held[k] or 0) + (m.kind == "note_on" and 1 or m.kind == "note_off" and -1 or 0)
  end
  stuck = 0; for _, v in pairs(held) do if v > 0 then stuck = stuck + v end end
  check("quitting leaves nothing hanging", stuck == 0, stuck .. " stuck")
end

print("-- midi in")
do
  local sim, world = fresh()
  sim.midi_in(1, {0x90, 64, 100})
  check("a key drops that note", #world.balls == 1 and world.balls[1].note == 64)
  sim.midi_in(1, {0x90, 65, 0})
  check("note-on with velocity 0 is ignored", #world.balls == 1)
  params:set("midi_in_ch", 3) -- listen on channel 2
  sim.midi_in(1, {0x90, 66, 100})
  check("other channels are ignored", #world.balls == 1)
  sim.midi_in(1, {0x91, 66, 100})
  check("the chosen channel gets through", #world.balls == 2)
end
do
  local sim, world = fresh{echo = true}
  params:set("output", 3)
  for _, n in ipairs{60, 62, 64, 65, 67, 69} do sim.midi_in(1, {0x90, n, 100}) end
  sim.enc(1, 30); sim.run(10)
  check("midi thru echo on the same port can't snowball", #world.balls == 6, #world.balls .. " balls")
end

print("-- octaves, transpose, probability")
local function track(sim, world, seconds)
  -- per-hit log of {ball, note} using the script's own on_hit
  local log, orig = {}, world.on_hit
  world.on_hit = function(b, j, kind, wall)
    local before = #sim.engine.calls
    local r = orig(b, j, kind, wall)
    for i = before + 1, #sim.engine.calls do
      local c = sim.engine.calls[i]
      if c[1] == "hz" then log[#log + 1] = {b = b, n = math.floor(69 + 12 * math.log(c[2] / 440, 2) + 0.5), wall = wall} end
    end
    return r
  end
  sim.run(seconds)
  world.on_hit = orig
  return log
end
do
  local sim, world = fresh()
  for _, n in ipairs{60, 64, 67, 72} do world:add_ball(n) end
  sim.enc(1, 10)
  params:set("transpose", 5)
  local log = track(sim, world, 8)
  check("transpose +5 shifts every note", #log > 0 and count(log, function(e) return e.n - e.b.note ~= 5 end) == 0)
  params:set("transpose", 0)
  params:set("octaves", 3); params:set("octave_pick", 1)
  log = track(sim, world, 10)
  local b1, seq = world.balls[1], {}
  for _, e in ipairs(log) do if e.b == b1 then seq[#seq + 1] = e.n - b1.note end end
  local climbs = #seq >= 6
  for i = 2, #seq do if (seq[i] - seq[i - 1]) % 36 ~= 12 then climbs = false end end
  check("arp +2 climbs 0, 12, 24 and wraps", climbs, table.concat(seq, " ", 1, math.min(6, #seq)))
  params:set("octaves", 2); params:set("octave_pick", 3)
  log = track(sim, world, 20)
  local per_wall, consistent = {}, true
  for _, e in ipairs(log) do
    if e.wall then
      local off = e.n - e.b.note
      if per_wall[e.wall] and per_wall[e.wall] ~= off then consistent = false end
      per_wall[e.wall] = off
    end
  end
  check("by wall: each wall keeps one octave", consistent)
end
do
  local sim, world = fresh()
  for _ = 1, 8 do sim.press(2) end
  sim.enc(1, 10)
  params:set("probability", 0)
  local lit = 0
  for _ = 1, 600 do sim.run(1 / 60); for _, b in ipairs(world.balls) do if b.flash > 0 then lit = lit + 1 end end end
  check("probability 0% plays nothing", #sim.engine_notes() == 0)
  check("skipped hits don't flash", lit == 0)
  params:set("probability", 60)
  local hits, orig = 0, world.on_hit
  world.on_hit = function(...) hits = hits + 1; return orig(...) end
  local before = #sim.engine_notes()
  sim.run(30)
  world.on_hit = orig
  local played = #sim.engine_notes() - before
  local pct = hits > 0 and played / hits * 100 or 0
  check("probability 60% plays about 60% of hits", pct > 45 and pct < 75, string.format("%.0f%%", pct))
end

print("-- screen")
do
  local sim, world = fresh()
  for _ = 1, 6 do sim.press(2) end
  sim.run(1)
  local frame = sim.draw()
  local texts = {}
  for _, op in ipairs(frame) do if op[1] == "text" or op[1] == "text_right" then texts[#texts + 1] = op[2] end end
  local joined = table.concat(texts, "|")
  check("normal view shows spin, G and M", joined:find("G") and joined:find("M") and joined:find("%d") ~= nil, joined)
  check("normal view hides sides/open", not joined:find("side"))
  sim.key(1, 1)
  frame = sim.draw()
  texts = {}
  for _, op in ipairs(frame) do if op[1] == "text" then texts[#texts + 1] = op[2] end end
  joined = table.concat(texts, "|")
  check("holding K1 shows sides and open", joined:find("side") and joined:find("open"), joined)
end

N.summary()
