-- rotere
-- lob atoms into a spinning box
--
-- test build: polyperc and/or
-- midi out (see params)
-- harder hits play louder
--
-- play a midi keyboard to
-- drop that note in
--
-- K2 drop a ball (random
-- note from the scale)
-- K3 empty
-- K1+K2 drop 8 (cpu testing)
--
-- E1 spin speed / direction
-- E2 gravity
-- E3 mass (heavier =
--    less bounce)
-- K1+E2 sides
-- K1+E3 open
--
-- bottom line: balls,
-- physics ms, draw ms

engine.name = "PolyPerc"

local Physics = include("lib/physics")
local Voice = include("lib/voice")
local Input = include("lib/input")

local PHYS_HZ = 60
local FPS = 30
local CX, CY, SCALE = 64, 34, 29 -- screen centre + world-to-pixel scale (corner radius = 29 px)

local world
local phys_metro, draw_metro
local shift = false

-- timing (smoothed, ms)
local phys_ms, draw_ms = 0, 0
local function smooth(avg, v) return avg + (v - avg) * 0.05 end

-- knob curves (0..1 -> physics). measured off-device, see PLAN.md "tuning".
-- gravity: exponential, so each click is the same *ratio* change. that keeps it even at
-- any spin, since what you hear is gravity vs spin (tumbling vs riding the walls).
local G_MIN, G_MAX = 0.5, 160
local function gravity_from(p)
  if p <= 0 then return 0 end -- 0% = zero gravity, floaty
  return G_MIN * (G_MAX / G_MIN) ^ p
end
-- mass: heavier = less bounce. liveliness depends on energy lost per hit (1 - bounce),
-- so spread that exponentially from 2% lost (light, very lively) to 60% lost (heavy, dead)
local LOSS_MAX, LOSS_MIN = 0.6, 0.02
local function bounce_from_mass(m)
  return 1 - LOSS_MIN * (LOSS_MAX / LOSS_MIN) ^ m
end

local function to_screen(x, y)
  return CX + x * SCALE, CY - y * SCALE -- physics y is up, screen y is down
end

local function drop(n)
  for _ = 1, n do
    if not world:add_ball(Voice.random_note()) then break end
  end
end

function init()
  world = Physics.new{
    sides = 6,
    circum = 1.0,
    ball_r = 0.07,
    max_balls = 24, -- measured on norns: ~5 ms physics at 24, and more is just noise musically
    ball_hits = false,
    -- pan follows where the ball is when it hits: left wall = left, right wall = right
    on_hit = function(b, impulse) Voice.play(b.note, Physics.velocity(impulse), b.x / world.circum) end,
  }

  Input.add_params(
    function(note) world:add_ball(note) end, -- full tombola: extra notes are just ignored
    function(note)
      -- only an echo if it's coming back in on the same port we send out on
      return params:get("midi_in_device") == params:get("midi_device") and Voice.is_sounding(note)
    end
  )
  Voice.add_params()
  params:add_separator("rotere_physics", "physics")
  params:add_control("gravity", "gravity", controlspec.new(0, 100, "lin", 1, 55, "%", 0.01))
  params:set_action("gravity", function(x) world.gravity = gravity_from(x / 100) end)
  params:add_control("mass", "mass", controlspec.new(0, 100, "lin", 1, 65, "%", 0.01))
  params:set_action("mass", function(x) world.restitution = bounce_from_mass(x / 100) end)
  params:add_option("ball_hits", "ball-on-ball notes", {"off", "on"}, 1)
  params:set_action("ball_hits", function(x) world.ball_hits = x == 2 end)
  params:bang()

  phys_metro = metro.init()
  phys_metro.time = 1 / PHYS_HZ
  phys_metro.event = function()
    local t0 = util.time()
    Voice.tick()
    world:step(1 / PHYS_HZ)
    phys_ms = smooth(phys_ms, (util.time() - t0) * 1000)
  end
  phys_metro:start()

  draw_metro = metro.init()
  draw_metro.time = 1 / FPS
  draw_metro.event = function() redraw() end
  draw_metro:start()
end

function key(n, z)
  if n == 1 then
    shift = z == 1
  elseif n == 2 and z == 1 then
    drop(shift and 8 or 1)
  elseif n == 3 and z == 1 then
    world:clear()
  end
end

function enc(n, d)
  if n == 1 then
    world.omega = util.clamp(world.omega + d * 0.1, -12, 12)
  elseif n == 2 then
    if shift then
      world:set_sides(util.clamp(world.sides + d, 3, 8))
    else
      params:delta("gravity", d)
    end
  elseif n == 3 then
    if shift then
      world.open = util.clamp(world.open + d * 0.01, 0, 1)
    else
      params:delta("mass", d)
    end
  end
end

function redraw()
  local t0 = util.time()
  screen.clear()
  screen.aa(0)
  screen.line_width(1)

  -- walls
  screen.level(8)
  for _, wl in ipairs(world.walls) do
    local ax, ay = to_screen(wl.ax, wl.ay)
    local bx, by = to_screen(wl.bx, wl.by)
    screen.move(ax, ay)
    screen.line(bx, by)
    screen.stroke()
  end

  -- balls (brighter + bigger for a moment after a hit)
  for _, b in ipairs(world.balls) do
    local x, y = to_screen(b.x, b.y)
    screen.level(b.flash > 0 and 15 or 6)
    screen.circle(x, y, b.flash > 0.5 and 2.5 or 1.8)
    screen.fill()
  end

  -- params, top
  screen.font_face(1)
  screen.font_size(8)
  -- normal layer bright, K1 layer bright while held
  screen.level(shift and 3 or 10)
  screen.move(0, 7)
  screen.text(string.format("spin %.1f", world.omega))
  screen.move(128, 7)
  screen.text_right(string.format("grav %d%%", math.floor(params:get("gravity") + 0.5)))
  screen.move(128, 15)
  screen.text_right(string.format("mass %d%%", math.floor(params:get("mass") + 0.5)))
  screen.level(shift and 10 or 3)
  screen.move(0, 15)
  screen.text(string.format("%d side", world.sides))
  screen.move(0, 23)
  screen.text(string.format("open %d%%", math.floor(world.open * 100 + 0.5)))

  -- timing, bottom
  screen.level(4)
  screen.move(0, 63)
  screen.text(string.format("%d", #world.balls))
  screen.move(128, 63)
  screen.text_right(string.format("p%.2f d%.2f", phys_ms, draw_ms))

  screen.update()
  draw_ms = smooth(draw_ms, (util.time() - t0) * 1000)
end

function cleanup()
  if phys_metro then phys_metro:stop() end
  if draw_metro then draw_metro:stop() end
  Voice.cleanup() -- no stuck notes on external gear
  Input.cleanup()
end
