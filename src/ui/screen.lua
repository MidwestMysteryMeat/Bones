--------------------------------------------------------------------------
-- src/ui/screen.lua
-- Shared screen scaffolding: fonts, the casino-felt background, headers.
-- Every state draws through these so the look stays consistent and
-- readable at 1080p (fonts scale off the window height).
--------------------------------------------------------------------------

local widgets = require("src.ui.widgets")

local screen = {}

screen.fonts = {}

function screen.load()
  local h = love.graphics.getHeight()
  local scale = h / 720
  screen.fonts = {
    title  = love.graphics.newFont(math.floor(52 * scale)),
    header = love.graphics.newFont(math.floor(30 * scale)),
    body   = love.graphics.newFont(math.floor(18 * scale)),
    small  = love.graphics.newFont(math.floor(14 * scale)),
    huge   = love.graphics.newFont(math.floor(72 * scale)),
  }
  widgets.fonts = screen.fonts
end

--- Casino felt: deep green with a vignette and a subtle rail.
function screen.drawFelt()
  local g = love.graphics
  local w, h = g.getDimensions()
  g.setColor(0.05, 0.25, 0.13)
  g.rectangle("fill", 0, 0, w, h)
  -- vignette (four soft rects, cheap and effective)
  g.setColor(0, 0, 0, 0.35)
  g.rectangle("fill", 0, 0, w, h * 0.12)
  g.rectangle("fill", 0, h * 0.88, w, h * 0.12)
  g.setColor(0, 0, 0, 0.2)
  g.rectangle("fill", 0, 0, w * 0.06, h)
  g.rectangle("fill", w * 0.94, 0, w * 0.06, h)
  -- wooden rail hint
  g.setColor(0.28, 0.16, 0.08)
  g.rectangle("fill", 0, 0, w, 10)
  g.rectangle("fill", 0, h - 10, w, 10)
  g.setColor(1, 1, 1, 1)
end

function screen.header(text)
  local g = love.graphics
  g.setFont(screen.fonts.header)
  g.setColor(1, 0.92, 0.7)
  g.print(text, 40, 28)
  g.setColor(1, 1, 1, 1)
end

--- Gold-on-dark label, e.g. wallet displays.
function screen.chipLabel(x, y, label, amount)
  local g = love.graphics
  g.setFont(screen.fonts.body)
  g.setColor(1, 1, 1, 0.7)
  g.print(label, x, y)
  g.setFont(screen.fonts.header)
  g.setColor(1, 0.84, 0.3)
  g.print(tostring(math.floor(amount)), x, y + 22)
  g.setColor(1, 1, 1, 1)
end

return screen
