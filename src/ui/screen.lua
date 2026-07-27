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
  local w, h = love.graphics.getDimensions()
  -- Scale against both axes so a short/wide window does not produce fonts
  -- that collide vertically. Keep a readable floor at the supported minimum
  -- window size instead of shrinking labels into single-digit pixels.
  local scale = math.min(w / 1280, h / 720)
  scale = math.max(0.82, math.min(1.5, scale))
  screen.fonts = {
    title  = love.graphics.newFont(math.max(38, math.floor(52 * scale))),
    header = love.graphics.newFont(math.max(24, math.floor(30 * scale))),
    body   = love.graphics.newFont(math.max(15, math.floor(18 * scale))),
    small  = love.graphics.newFont(math.max(12, math.floor(14 * scale))),
    huge   = love.graphics.newFont(math.max(52, math.floor(72 * scale))),
  }
  widgets.fonts = screen.fonts
end

--- Casino felt: deep green with a vignette and a subtle rail.
function screen.drawFelt()
  local g = love.graphics
  local w, h = g.getDimensions()
  g.setColor(0.025, 0.19, 0.105)
  g.rectangle("fill", 0, 0, w, h)

  -- A quiet woven-felt pattern gives the table depth without a bitmap asset.
  g.setLineWidth(1)
  for x = -h, w, 44 do
    g.setColor(0.22, 0.54, 0.34, 0.035)
    g.line(x, 0, x + h, h)
  end
  for x = 0, w + h, 44 do
    g.setColor(0, 0, 0, 0.025)
    g.line(x, 0, x - h, h)
  end

  -- Layered vignette and a warmer, dimensional wooden rail.
  g.setColor(0, 0, 0, 0.28)
  g.rectangle("fill", 0, 0, w, h * 0.10)
  g.rectangle("fill", 0, h * 0.90, w, h * 0.10)
  g.setColor(0, 0, 0, 0.18)
  g.rectangle("fill", 0, 0, w * 0.035, h)
  g.rectangle("fill", w * 0.965, 0, w * 0.035, h)

  g.setColor(0.16, 0.075, 0.035)
  g.rectangle("fill", 0, 0, w, 12)
  g.rectangle("fill", 0, h - 12, w, 12)
  g.setColor(0.47, 0.27, 0.11)
  g.rectangle("fill", 0, 2, w, 4)
  g.rectangle("fill", 0, h - 8, w, 4)
  g.setColor(0.9, 0.63, 0.25, 0.20)
  g.line(0, 11, w, 11)
  g.line(0, h - 12, w, h - 12)
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
