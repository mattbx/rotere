-- rotere physics core
-- 2D circles inside a spinning n-sided polygon of "louvre" walls.
-- Plain Lua 5.3, no norns deps, so it can be tested off-device.
--
-- Walls rotate about the centre (spin) and each wall can also twist
-- about its own midpoint (open 0..1). At open=1 every wall is turned
-- 90 degrees, like the M4L device's "shape" control, so balls fall out.

local P = {}
P.__index = P

local sin, cos, sqrt, abs, pi = math.sin, math.cos, math.sqrt, math.abs, math.pi
local TAU = 2 * pi

function P.new(opts)
  opts = opts or {}
  local w = setmetatable({}, P)
  w.sides = opts.sides or 6
  w.circum = opts.circum or 1.0       -- centre to corner (world units) - fixed so every shape fits the screen
  w.radius = w.circum * cos(pi / w.sides) -- centre to wall midpoint, derived
  w.ball_r = opts.ball_r or 0.06
  w.angle = 0                          -- tombola rotation (rad)
  w.omega = 0                          -- angular velocity (rad/s)
  w.open = 0                           -- 0 closed .. 1 fully open
  w.gravity = opts.gravity or 9.8      -- world units / s^2 (scaled below)
  w.g_scale = opts.g_scale or 0.25     -- so gravity 9.8 feels right at radius 1
  w.restitution = opts.restitution or 0.8
  w.damping = opts.damping or 0.1      -- linear damping per second
  w.max_balls = opts.max_balls or 32
  w.substeps = opts.substeps or 4
  w.hit_threshold = opts.hit_threshold or 0.15 -- min impulse that makes a note
  w.ball_hits = opts.ball_hits ~= false   -- ball-on-ball collisions make notes too (M4L does)
  w.retrigger = opts.retrigger or 0.06     -- min seconds between notes from one ball
  w.time = 0
  w.balls = {}
  w.walls = {}
  for i = 1, w.sides do w.walls[i] = {ax=0, ay=0, bx=0, by=0, nx=0, ny=0} end
  w.on_hit = opts.on_hit or function(ball, impulse, kind) end
  w.on_escape = opts.on_escape or function(ball) end
  w:_update_walls()
  return w
end

function P:set_sides(n)
  n = math.max(3, math.floor(n))
  self.sides = n
  self.radius = self.circum * cos(pi / n)
  self.walls = {}
  for i = 1, n do self.walls[i] = {ax=0, ay=0, bx=0, by=0, nx=0, ny=0} end
  self:_update_walls()
  -- pull any ball that is now outside the new shape back inside its inner circle
  local lim = self.radius - self.ball_r * 1.5
  for _, b in ipairs(self.balls) do
    b.contact = {}
    local d = sqrt(b.x * b.x + b.y * b.y)
    if d > lim then b.x, b.y = b.x * lim / d, b.y * lim / d end
  end
end

-- distance from centre beyond which a ball has definitely left the shape
function P:escape_radius()
  return self.radius / cos(pi / self.sides) + self.ball_r * 3
end

-- recompute wall segment endpoints from angle / open
function P:_update_walls()
  local n, R = self.sides, self.radius
  local half = R * math.tan(pi / n)            -- half side length of the polygon
  local twist = self.open * (pi / 2)
  for i = 1, n do
    local a = self.angle + (i - 1) * TAU / n   -- direction to wall midpoint
    local mx, my = R * cos(a), R * sin(a)
    local ta = a + pi / 2 + twist              -- wall tangent, twisted when open
    local tx, ty = cos(ta), sin(ta)
    local wl = self.walls[i]
    wl.mx, wl.my = mx, my
    wl.ax, wl.ay = mx - tx * half, my - ty * half
    wl.bx, wl.by = mx + tx * half, my + ty * half
  end
end

function P:add_ball(note)
  if #self.balls >= self.max_balls then return nil end
  -- spread drops a little so a burst of balls doesn't start fully overlapped
  local a, d = math.random() * TAU, math.random() * self.radius * 0.35
  local b = {
    x = cos(a) * d, y = sin(a) * d,
    vx = 0, vy = 0, note = note,
    last_hit = -1,    -- time of last note, for retrigger cooldown
    contact = {},     -- per wall / per ball: true while touching (stops retrigger chatter)
    flash = 0,        -- for drawing hits
  }
  table.insert(self.balls, b)
  return b
end

function P:clear() self.balls = {} end

-- closest point on segment a-b to p
local function closest(ax, ay, bx, by, px, py)
  local dx, dy = bx - ax, by - ay
  local len2 = dx * dx + dy * dy
  local t = ((px - ax) * dx + (py - ay) * dy) / len2
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return ax + dx * t, ay + dy * t
end

function P:step(dt, crank_omega)
  -- crank: caller drives omega directly from encoder deltas
  if crank_omega then self.omega = crank_omega end
  local n = self.substeps
  local h = dt / n
  local g = self.gravity * self.g_scale
  local e = self.restitution
  local r = self.ball_r
  local damp = 1 - self.damping * h
  local thr = self.hit_threshold
  local balls, walls = self.balls, self.walls
  local escape_r = self:escape_radius()

  for _ = 1, n do
    self.time = self.time + h
    self.angle = (self.angle + self.omega * h) % TAU
    self:_update_walls()
    local om = self.omega

    -- integrate
    for i = 1, #balls do
      local b = balls[i]
      b.vy = (b.vy - g * h) * damp
      b.vx = b.vx * damp
      b.x = b.x + b.vx * h
      b.y = b.y + b.vy * h
    end

    -- ball vs wall
    for i = 1, #balls do
      local b = balls[i]
      for k = 1, #walls do
        local wl = walls[k]
        local cx, cy = closest(wl.ax, wl.ay, wl.bx, wl.by, b.x, b.y)
        local dx, dy = b.x - cx, b.y - cy
        local d2 = dx * dx + dy * dy
        if d2 < r * r and d2 > 1e-12 then
          local d = sqrt(d2)
          local nx, ny = dx / d, dy / d
          -- wall surface velocity at contact point (rigid rotation about origin)
          local wvx, wvy = -om * cy, om * cx
          local rvx, rvy = b.vx - wvx, b.vy - wvy
          local vn = rvx * nx + rvy * ny
          -- push out of the wall
          local pen = r - d
          b.x, b.y = b.x + nx * pen, b.y + ny * pen
          if vn < 0 then
            local j = -(1 + e) * vn
            b.vx, b.vy = b.vx + j * nx, b.vy + j * ny
            if not b.contact[k] and j > thr and self.time - b.last_hit > self.retrigger then
              self.on_hit(b, j, "wall")
              b.flash, b.last_hit = 1, self.time
            end
          end
          b.contact[k] = true
        elseif d2 > (r * 1.5) ^ 2 then
          b.contact[k] = nil
        end
      end
    end

    -- ball vs ball (equal mass)
    local d0 = 2 * r
    for i = 1, #balls - 1 do
      local a = balls[i]
      for k = i + 1, #balls do
        local b = balls[k]
        local dx, dy = b.x - a.x, b.y - a.y
        local d2 = dx * dx + dy * dy
        if d2 < d0 * d0 and d2 > 1e-12 then
          local d = sqrt(d2)
          local nx, ny = dx / d, dy / d
          local pen = (d0 - d) * 0.5
          a.x, a.y = a.x - nx * pen, a.y - ny * pen
          b.x, b.y = b.x + nx * pen, b.y + ny * pen
          local vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
          if vn < 0 then
            local j = -(1 + e) * vn * 0.5
            a.vx, a.vy = a.vx - j * nx, a.vy - j * ny
            b.vx, b.vy = b.vx + j * nx, b.vy + j * ny
            local key = -k -- negative keys = ball contacts, keeps wall keys clean
            if self.ball_hits and not a.contact[key] and j > thr then
              local t = self.time
              if t - a.last_hit > self.retrigger then self.on_hit(a, j, "ball"); a.flash, a.last_hit = 1, t end
              if t - b.last_hit > self.retrigger then self.on_hit(b, j, "ball"); b.flash, b.last_hit = 1, t end
            end
            a.contact[key] = true
          end
        elseif d2 > (d0 * 1.5) ^ 2 then
          a.contact[-k] = nil
        end
      end
    end

    -- escape: anything that fell out of the open tombola
    for i = #balls, 1, -1 do
      local b = balls[i]
      if b.x * b.x + b.y * b.y > escape_r * escape_r then
        table.remove(balls, i)
        self.on_escape(b)
      end
    end
  end

  for i = 1, #balls do
    local b = balls[i]
    if b.flash > 0 then b.flash = math.max(0, b.flash - dt * 6) end
  end
end

-- impulse -> MIDI-ish velocity (same curve shape as the M4L device)
function P.velocity(impulse, scale)
  scale = scale or 1.5
  return math.floor((1 - math.exp(-impulse / scale)) * 126 + 1 + 0.5)
end

return P
