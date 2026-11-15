-- render a few rotere screens for review, from the real drawing code:
--   lua5.3 test/render_screens.lua > /tmp/frames.txt
--   python3 test/screen_png.py /tmp/frames.txt screens.png
-- edit the scenes below to preview whatever state you're working on.

local N = dofile("test/norns_offline.lua")
math.randomseed(4)
local sim = N.load{root = ".", script = "rotere.lua", engine_commands = {"pan"}}

local function frame(name)
  io.write("FRAME\t", name, "\n")
  for _, op in ipairs(sim.draw()) do
    local parts = {}
    for i = 1, #op do parts[i] = tostring(op[i]) end
    io.write(table.concat(parts, "\t"), "\n")
  end
end

for _ = 1, 6 do sim.press(2) end
sim.enc(1, 30); sim.run(3)
frame("normal view, spin 3")

sim.key(1, 1)
frame("K1 held")

sim.enc(2, -3)
for _ = 1, 30 do sim.enc(3, 1); sim.run(0.03) end
sim.run(1)
frame("K1 held: triangle opening")
sim.key(1, 0)

sim.enc(1, -50); sim.run(1)
params:set("show_cpu", 2)
frame("spinning backwards, show cpu on")
