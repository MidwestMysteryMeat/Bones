--------------------------------------------------------------------------
-- src/ui/widgets.lua
-- Tiny custom immediate-mode UI: buttons, checkboxes, sliders, text
-- inputs, chip stacks. No retained state beyond focus/drag bookkeeping;
-- states feed events in via widgets.pressed / widgets.textinput /
-- widgets.keypressed and call widgets.beginFrame each frame.
--------------------------------------------------------------------------

local widgets = {}

widgets.fonts = nil -- set by screen.load()

local mx, my = 0, 0
local clickX, clickY = nil, nil
local activeSlider = nil
local focusInput = nil

function widgets.beginFrame()
  mx, my = love.mouse.getPosition()
  if not love.mouse.isDown(1) then activeSlider = nil end
end

function widgets.endFrame()
  clickX, clickY = nil, nil
end

--- Feed from love.mousepressed.
function widgets.pressed(x, y, button)
  if button == 1 then
    clickX, clickY = x, y
    focusInput = nil -- clicking anywhere clears input focus; inputs re-grab
  end
end

local function hot(x, y, w, h)
  return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function clicked(x, y, w, h)
  if clickX and clickX >= x and clickX <= x + w
    and clickY >= y and clickY <= y + h then
    clickX, clickY = nil, nil -- consume
    return true
  end
  return false
end

widgets.hot = hot

-- Button ------------------------------------------------------------------

--- opts = { color, disabled, small }
function widgets.button(x, y, w, h, label, opts)
  opts = opts or {}
  local g = love.graphics
  local hover = hot(x, y, w, h) and not opts.disabled
  local c = opts.color or { 0.16, 0.42, 0.24 }
  local mul = opts.disabled and 0.4 or (hover and 1.3 or 1.0)
  g.setColor(c[1] * mul, c[2] * mul, c[3] * mul)
  g.rectangle("fill", x, y, w, h, 8)
  g.setColor(0, 0, 0, 0.4)
  g.rectangle("line", x, y, w, h, 8)
  g.setColor(1, 1, 1, opts.disabled and 0.4 or 1)
  local font = opts.small and widgets.fonts.small or widgets.fonts.body
  g.setFont(font)
  g.printf(label, x, y + h / 2 - font:getHeight() / 2, w, "center")
  g.setColor(1, 1, 1, 1)
  if opts.disabled then return false end
  return clicked(x, y, w, h)
end

-- Checkbox ------------------------------------------------------------------

function widgets.checkbox(x, y, label, value)
  local g = love.graphics
  local s = 20
  g.setColor(0.1, 0.1, 0.12)
  g.rectangle("fill", x, y, s, s, 4)
  g.setColor(1, 1, 1, 0.6)
  g.rectangle("line", x, y, s, s, 4)
  if value then
    g.setColor(0.35, 0.9, 0.45)
    g.rectangle("fill", x + 4, y + 4, s - 8, s - 8, 2)
  end
  g.setColor(1, 1, 1, 1)
  g.setFont(widgets.fonts.small)
  g.print(label, x + s + 8, y + 2)
  local w = s + 12 + widgets.fonts.small:getWidth(label)
  if clicked(x, y, w, s) then return not value, true end
  return value, false
end

-- Slider ------------------------------------------------------------------------

function widgets.slider(id, x, y, w, value, min, max, label, fmt)
  local g = love.graphics
  local h = 8
  local frac = (value - min) / (max - min)
  g.setFont(widgets.fonts.small)
  g.setColor(1, 1, 1, 0.9)
  g.print(("%s: %s"):format(label, (fmt or "%.0f"):format(value)), x, y - 18)
  g.setColor(0.1, 0.1, 0.12)
  g.rectangle("fill", x, y, w, h, 4)
  g.setColor(0.9, 0.75, 0.3)
  g.rectangle("fill", x, y, w * frac, h, 4)
  g.circle("fill", x + w * frac, y + h / 2, 9)
  g.setColor(1, 1, 1, 1)

  if clicked(x - 10, y - 8, w + 20, h + 16) then activeSlider = id end
  if activeSlider == id and love.mouse.isDown(1) then
    local f = math.min(1, math.max(0, (mx - x) / w))
    return min + f * (max - min), true
  end
  return value, false
end

-- Text input --------------------------------------------------------------------------

local inputs = {} -- id -> text

function widgets.inputText(id) return inputs[id] or "" end
function widgets.setInputText(id, text) inputs[id] = text end

function widgets.textInput(id, x, y, w, placeholder)
  local g = love.graphics
  local h = 32
  local text = inputs[id] or ""
  if clicked(x, y, w, h) then focusInput = id end
  local focused = focusInput == id
  g.setColor(0.08, 0.08, 0.1)
  g.rectangle("fill", x, y, w, h, 6)
  g.setColor(1, 1, 1, focused and 0.9 or 0.35)
  g.rectangle("line", x, y, w, h, 6)
  g.setFont(widgets.fonts.body)
  if text == "" and not focused then
    g.setColor(1, 1, 1, 0.3)
    g.print(placeholder or "", x + 8, y + 6)
  else
    g.setColor(1, 1, 1, 1)
    g.print(text .. (focused and "|" or ""), x + 8, y + 6)
  end
  g.setColor(1, 1, 1, 1)
  return text
end

--- Feed from love.textinput.
function widgets.textinput(t)
  if focusInput then
    inputs[focusInput] = (inputs[focusInput] or "") .. t
  end
end

--- Feed from love.keypressed. Returns true if the key was eaten.
function widgets.keypressed(key)
  if focusInput and key == "backspace" then
    local t = inputs[focusInput] or ""
    inputs[focusInput] = t:sub(1, -2)
    return true
  end
  return focusInput ~= nil and key ~= "escape"
end

-- Chip stack ------------------------------------------------------------------------------

local chipColors = {
  { 500, { 0.55, 0.25, 0.7 } },  -- purple
  { 100, { 0.15, 0.15, 0.15 } }, -- black
  { 25,  { 0.15, 0.5, 0.2 } },   -- green
  { 5,   { 0.75, 0.2, 0.2 } },   -- red
}

--- Draw a physical-looking stack representing `amount` at (x, y baseline).
function widgets.chipStack(x, y, amount)
  local g = love.graphics
  local level = 0
  for _, entry in ipairs(chipColors) do
    local denom, color = entry[1], entry[2]
    local n = math.min(8, math.floor(amount / denom))
    amount = amount - n * denom
    for _ = 1, n do
      local cy = y - level * 5
      g.setColor(0, 0, 0, 0.3)
      g.ellipse("fill", x, cy + 2, 14, 6)
      g.setColor(color[1], color[2], color[3])
      g.ellipse("fill", x, cy, 14, 6)
      g.setColor(1, 1, 1, 0.5)
      g.ellipse("line", x, cy, 14, 6)
      level = level + 1
    end
  end
  g.setColor(1, 1, 1, 1)
end

return widgets
