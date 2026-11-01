-- rotere
-- lob atoms into a spinning box
--
-- polyperc and/or midi out
-- harder hits play louder
--
-- play a midi keyboard to
-- drop that note in
--
-- K2 drop a ball (random
-- note from the scale)
-- K3 empty
--
-- E1 spin speed / direction
-- E2 gravity
-- E3 mass (heavier =
--    less bounce)
-- hold K1 to see:
-- K1+E2 sides
-- K1+E3 open

engine.name = "PolyPerc"

local Physics = include("lib/physics")
local Voice = include("lib/voice")
local Input = include("lib/input")
local View = include("lib/view")

local PHYS_HZ = 60
local FPS = 30

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
    on_hit = function(b, impulse, kind, wall)
      if not Voice.chance() then return false end -- skipped: no sound, no flash, arp doesn't step
      Voice.play(b.note, Physics.velocity(impulse), b.x / world.circum, Voice.octave_for(b, wall))
    end,
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
  params:add_option("show_cpu", "show cpu", {"off", "on"}, 1)
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
    drop(1) -- one ball per press, K1 or not
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

-- reused every frame so drawing makes no garbage
local view_state = {}

function redraw()
  local t0 = util.time()
  screen.clear()
  local v = view_state
  v.spin = world.omega
  v.gravity = params:get("gravity") / 100
  v.mass = params:get("mass") / 100
  v.sides = world.sides
  v.open = world.open
  v.shift = shift
  v.show_cpu = params:get("show_cpu") == 2
  v.balls = #world.balls
  v.phys_ms, v.draw_ms = phys_ms, draw_ms
  View.draw(world, v)
  screen.update()
  draw_ms = smooth(draw_ms, (util.time() - t0) * 1000)
end

function cleanup()
  if phys_metro then phys_metro:stop() end
  if draw_metro then draw_metro:stop() end
  Voice.cleanup() -- no stuck notes on external gear
  Input.cleanup()
end
