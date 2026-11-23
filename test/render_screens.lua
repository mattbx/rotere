-- quick screen previews without Weft, from the same scenes as test/screens.lua:
--   lua5.3 test/render_screens.lua > /tmp/frames.txt
--   mkdir -p screens
--   python3 test/screen_png.py /tmp/frames.txt screens/quick.png
-- rects are exact, lines and text are close but not exact (see screen_png.py).
-- for exact pixels use Weft's screens.py (test/README.md). to preview another
-- state, add a shot to test/screens.lua - both tools pick it up.

local N = dofile("test/norns_offline.lua")
local cfg = dofile("test/screens.lua")
math.randomseed(cfg.seed or 0)
-- options first, then root and script, as Weft's screens.lua does
local opts = {}
for k, v in pairs(cfg.options or {}) do opts[k] = v end
opts.root, opts.script = ".", cfg.script
local sim = N.load(opts)

local function shot(name)
  io.write("FRAME\t", name, "\n")
  for _, op in ipairs(sim.draw()) do
    local parts = {}
    for i = 1, #op do parts[i] = tostring(op[i]) end
    io.write(table.concat(parts, "\t"), "\n")
  end
end

cfg.scenes(sim, shot)
