-- off-device sanity + speed check for lib/physics.lua
-- run from repo root:  lua5.3 test/bench.lua
package.path = "./lib/?.lua;" .. package.path
local P = require "physics"

local function run(nballs, omega, open, seconds, substeps, extra)
  local hits, escaped, vels = 0, 0, {}
  local o = {
    substeps = substeps,
    max_balls = 64,
    on_hit = function(b, j) hits = hits + 1; vels[#vels + 1] = P.velocity(j) end,
    on_escape = function() escaped = escaped + 1 end,
  }
  for k, v in pairs(extra or {}) do o[k] = v end
  local w = P.new(o)
  math.randomseed(1)
  for i = 1, nballs do
    local b = w:add_ball(60 + i)
    b.x, b.y = (math.random() - 0.5) * 0.8, (math.random() - 0.5) * 0.8
  end
  w.omega, w.open = omega, open
  local dt, steps = 1 / 60, math.floor(seconds * 60)
  local t0 = os.clock()
  for _ = 1, steps do w:step(dt) end
  local ms = (os.clock() - t0) * 1000 / steps
  table.sort(vels)
  local med = vels[math.max(1, #vels // 2)] or 0
  return ms, hits / seconds, escaped, #w.balls, med
end

print("balls  omega  open  sub   ms/frame  hits/s  escaped  left  medVel")
for _, c in ipairs{
  {8, 1, 0, 4}, {16, 2, 0, 4}, {32, 2, 0, 4}, {64, 2, 0, 4},
  {16, 12, 0, 4},   -- fast spin: does anything tunnel out while closed?
  {16, 12, 0, 8},
  {16, 2, 1, 4},    -- fully open: everything should fall out
  {16, 2, 0.35, 4}, -- part open
} do
  local ms, hps, esc, left, med = run(c[1], c[2], c[3], 20, c[4])
  print(string.format("%5d  %5.1f  %4.2f  %3d   %8.3f  %6.1f  %7d  %4d  %6d",
    c[1], c[2], c[3], c[4], ms, hps, esc, left, med))
end

print("\nnote-flood fixes, 32 balls omega 2 closed:")
for _, c in ipairs{
  {"default (ball hits on, 60ms cooldown)", {}},
  {"wall hits only", {ball_hits = false}},
  {"wall only + 120ms + higher threshold", {ball_hits = false, retrigger = 0.12, hit_threshold = 0.3}},
} do
  local ms, hps = run(32, 2, 0, 20, 4, c[2])
  print(string.format("  %-40s %6.1f hits/s", c[1], hps))
end
