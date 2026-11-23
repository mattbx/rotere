-- rotere's screens, for Weft's preview tool (tools/norns-harness/screens.py in
-- mattbx/weft). It runs the real redraw() in each state below and renders every
-- shot with the same Cairo replay Weft's references come from, with the norns
-- font, so text is exact. From a Weft checkout:
--
--   python3 tools/norns-harness/screens.py ~/Github/audio-apps/rotere
--
-- Output goes to screens/ (git-ignored): one PNG per shot plus sheet.png.
--
-- The states are reached with the keys and encoders a player would use. Balls
-- drop at random notes, so the seed is fixed, and time only moves when sim.run
-- says so: every run draws the same pixels on any machine.
-- Add a shot here for whatever state you're working on.

return {
  script = "rotere.lua",
  options = {engine_commands = {"pan"}},
  seed = 4,
  scenes = function(sim, shot)
    -- six balls in, spun up and left to tumble
    for _ = 1, 6 do sim.press(2) end
    sim.enc(1, 30); sim.run(3)
    shot("normal view, spin 3")

    -- K1 shows sides and open bottom left
    sim.key(1, 1)
    shot("K1 held")

    -- down to a triangle, then twisted open a click at a time
    sim.enc(2, -3)
    for _ = 1, 30 do sim.enc(3, 1); sim.run(0.03) end
    sim.run(1)
    shot("K1 held: triangle opening")
    sim.key(1, 0)

    -- spin through zero to reverse, with the cpu readout on
    sim.enc(1, -50); sim.run(1)
    params:set("show_cpu", 2)
    shot("spinning backwards, show cpu on")
  end,
}
