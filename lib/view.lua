-- rotere screen
-- calm by default: spin top-left, gravity + mass bars on the right, the shape in the middle.
-- hold K1 and the main readouts dim while sides + open appear bottom-left.

local View = {}

local CX, CY, SCALE = 64, 34, 29 -- screen centre + world-to-pixel scale (corner radius = 29 px)

local BRIGHT, DIM = 15, 4
local SEG_OFF_BRIGHT, SEG_OFF_DIM = 2, 1

-- 7x7 spin icon, clockwise (arrowhead top-right). mirrored for counter-clockwise.
local SPIN_CW = {
  "..###.#",
  ".#...##",
  "#...###",
  "#......",
  "#.....#",
  ".#...#.",
  "..###..",
}
local SPIN_CCW = {}
for i, row in ipairs(SPIN_CW) do SPIN_CCW[i] = row:reverse() end

local function to_screen(x, y)
  return CX + x * SCALE, CY - y * SCALE -- physics y is up, screen y is down
end

local function bitmap(rows, x, y)
  for j = 1, #rows do
    local row = rows[j]
    for i = 1, #row do
      if row:sub(i, i) == "#" then screen.rect(x + i - 1, y + j - 1, 1, 1) end
    end
  end
  screen.fill()
end

-- 12 x 1px segments, 1px apart: 23px wide, 5px tall. value 0..1
local function seg_bar(x, y, value, lv, off_lv)
  local filled = math.floor(value * 12 + 0.5)
  for i = 0, 11 do
    screen.level(i < filled and lv or off_lv)
    screen.rect(x + i * 2, y, 1, 5)
    screen.fill()
  end
end

local function tombola(world)
  screen.level(8)
  for _, wl in ipairs(world.walls) do
    local ax, ay = to_screen(wl.ax, wl.ay)
    local bx, by = to_screen(wl.bx, wl.by)
    screen.move(ax, ay)
    screen.line(bx, by)
    screen.stroke()
  end
  -- balls: brighter and bigger for a moment after a hit
  for _, b in ipairs(world.balls) do
    local x, y = to_screen(b.x, b.y)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if b.flash > 0.5 then
      screen.level(15)
      screen.rect(x - 1, y - 2, 3, 5)
      screen.rect(x - 2, y - 1, 5, 3)
    else
      screen.level(b.flash > 0 and 15 or 6)
      screen.rect(x - 1, y - 1, 3, 3)
    end
    screen.fill()
  end
end

-- s: {spin, gravity (0-1), mass (0-1), sides, open (0-1), shift, show_cpu, balls, phys_ms, draw_ms}
function View.draw(world, s)
  screen.aa(0)
  screen.line_width(1)
  screen.font_face(1)
  screen.font_size(8)

  tombola(world)

  local main = s.shift and DIM or BRIGHT
  local off = s.shift and SEG_OFF_DIM or SEG_OFF_BRIGHT

  -- top-left: spin (E1)
  screen.level(main)
  bitmap(s.spin >= 0 and SPIN_CW or SPIN_CCW, 3, 2)
  screen.move(13, 8)
  local spin = math.abs(s.spin)
  screen.text(spin < 10 and string.format("%.1f", spin) or string.format("%d", math.floor(spin + 0.5)))

  -- right: gravity (E2) top, mass (E3) bottom
  seg_bar(94, 3, s.gravity, main, off)
  screen.level(main)
  screen.move(124, 8)
  screen.text_right("G")
  seg_bar(94, 56, s.mass, main, off)
  screen.level(main)
  screen.move(124, 61)
  screen.text_right("M")

  -- bottom-left: K1 layer, only while K1 is held
  if s.shift then
    screen.level(BRIGHT)
    screen.move(3, 53)
    screen.text(string.format("%d side", s.sides))
    screen.move(3, 61)
    screen.text(string.format("open %d%%", math.floor(s.open * 100 + 0.5)))
  elseif s.show_cpu then
    -- optional readout (params > physics > show cpu): balls, physics ms, draw ms
    screen.level(3)
    screen.move(3, 53)
    screen.text(string.format("%d balls", s.balls))
    screen.move(3, 61)
    screen.text(string.format("p%.1f d%.1f", s.phys_ms, s.draw_ms))
  end
end

return View
