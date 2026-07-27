--------------------------------------------------------------------------
-- src/fx/dice_render.lua
-- Greyledger-style programmatic dice: a shaded numeric face, luminous
-- accent border, upright result over a spinning body, and a hop-and-settle
-- landing. Everything is drawn with LÖVE primitives, so cosmetics remain
-- colors from the dice catalog and no image assets are required.
--------------------------------------------------------------------------

local dice_render = {}

local PI = math.pi
local TAU = PI * 2
local SETTLE_DURATION = 0.42

local Die = {}
Die.__index = Die

local defaultCosmetic = {
  body = { 0.95, 0.93, 0.88 }, pip = { 0.15, 0.15, 0.18 },
}

local function randomUnit()
  if love and love.math and love.math.random then
    return love.math.random()
  end
  return math.random()
end

local function clampFace(face)
  return math.max(1, math.min(6, math.floor(tonumber(face) or 1)))
end

local function shade(color, amount)
  return color[1] * amount, color[2] * amount, color[3] * amount
end

local function tint(color, amount)
  return color[1] + (1 - color[1]) * amount,
    color[2] + (1 - color[2]) * amount,
    color[3] + (1 - color[3]) * amount
end

function dice_render.newDie(x, y, size, cosmetic)
  return setmetatable({
    x = x, y = y, size = size or 72,
    cosmetic = cosmetic or defaultCosmetic,
    face = 1,
    state = "idle",       -- idle | tumbling | settling
    t = 0, duration = 0,
    finalFace = 1,
    cycleClock = 0,
    rot = 0, spin = 0, settleRot = 0,
    lift = 0, squash = 1,
    onLand = nil,
  }, Die)
end

--- Kick off a tumble that lands on finalFace after `duration` seconds.
--- onLand fires exactly once, at the landing moment (hook hitstop/SFX).
function Die:startTumble(finalFace, duration, onLand)
  self.state = "tumbling"
  self.t = 0
  self.duration = math.max(0.01, duration or 0.72)
  self.finalFace = clampFace(finalFace)
  self.cycleClock = 0
  self.rot = (randomUnit() - 0.5) * 6
  self.spin = (randomUnit() < 0.5 and -1 or 1) * (7 + randomUnit() * 5)
  self.settleRot = 0
  self.lift = 0
  self.squash = 1
  self.onLand = onLand
end

--- Extend the tumble (near-miss slow-mo stretches the reveal).
function Die:extend(extra)
  if self.state == "tumbling" then self.duration = self.duration + extra end
end

function Die:isRolling() return self.state ~= "idle" end

function Die:update(dt)
  if self.state == "tumbling" then
    self.t = self.t + dt
    local progress = math.min(1, self.t / self.duration)
    -- Face cycling decelerates: fast flicker early, long holds late.
    -- Interval grows from 40ms to ~250ms with an ease-in curve.
    local interval = 0.04 + 0.22 * (progress * progress)
    self.cycleClock = self.cycleClock + dt
    if self.cycleClock >= interval then
      self.cycleClock = 0
      local nextFace = math.floor(randomUnit() * 6) + 1
      if nextFace == self.face then nextFace = (nextFace % 6) + 1 end
      self.face = nextFace
    end

    -- The Greyledger render spins the body through an airborne arc while
    -- keeping the numeric value readable. Ease the spin as it approaches
    -- the table, but never let the animation decide the actual result.
    self.rot = self.rot + self.spin * dt * (1 - progress * 0.6)
    self.lift = math.sin(progress * PI) * self.size * 0.38

    if progress >= 1 then
      self.face = self.finalFace
      self.state = "settling"
      self.t = 0
      self.rot = ((self.rot + PI) % TAU) - PI
      self.settleRot = self.rot
      self.lift = 0
      self.squash = 0.82
      if self.onLand then
        local cb = self.onLand
        self.onLand = nil
        cb(self)
      end
    end
  elseif self.state == "settling" then
    self.t = self.t + dt
    local progress = math.min(1, self.t / SETTLE_DURATION)
    local ease = 1 - (1 - progress) ^ 3
    self.rot = self.settleRot * (1 - ease)
    self.lift = -math.sin(progress * PI) * self.size * 0.06 * (1 - progress)
    self.squash = 1 + (0.82 - 1) * (1 - ease)

    if progress >= 1 then
      self.state = "idle"
      self.squash, self.rot, self.lift = 1, 0, 0
    end
  end
end

function Die:draw()
  local g = love.graphics
  local s = self.size
  local body = self.cosmetic.body or defaultCosmetic.body
  local ink = self.cosmetic.pip or defaultCosmetic.pip
  local glow = self.cosmetic.glow
  local accent = glow or ink
  local radius = s * 0.16
  local xScale = 2 - self.squash

  -- Draw the animated body independently from the number. This is the
  -- canvas renderer's counter-rotation trick in LÖVE form: the body can
  -- tumble freely while the server/engine-provided result stays upright.
  g.push()
  g.translate(self.x, self.y - self.lift)
  g.rotate(self.rot)
  g.scale(xScale, self.squash)

  -- Soft shadow under the die.
  g.setColor(0, 0, 0, 0.35)
  g.rectangle("fill", -s / 2 + 4, -s / 2 + 7, s, s, radius)

  -- Canvas shadowBlur has no direct LÖVE equivalent; layered translucent
  -- outlines produce the same luminous accent without a texture asset.
  for i = 3, 1, -1 do
    local spread = i * s * 0.045
    g.setLineWidth(math.max(2, i * s * 0.025))
    g.setColor(accent[1], accent[2], accent[3],
      (glow and 0.055 or 0.025) * (4 - i))
    g.rectangle("line", -s / 2 - spread, -s / 2 - spread,
      s + spread * 2, s + spread * 2, radius + spread * 0.5)
  end

  -- Dark-to-light body treatment from Greyledger's canvas prototype.
  g.setColor(shade(body, 0.54))
  g.rectangle("fill", -s / 2, -s / 2, s, s, radius)
  g.setColor(body[1], body[2], body[3], 0.72)
  g.rectangle("fill", -s / 2 + 2, -s / 2 + 2, s - 4, s * 0.54, radius - 2)
  g.setColor(tint(body, 0.34))
  g.rectangle("fill", -s * 0.35, -s * 0.36, s * 0.7, s * 0.075, s * 0.035)

  -- Crisp accent border and subtle facet marks.
  g.setColor(accent[1], accent[2], accent[3], glow and 0.95 or 0.72)
  g.setLineWidth(2)
  g.rectangle("line", -s / 2, -s / 2, s, s, radius)
  g.setColor(accent[1], accent[2], accent[3], 0.13)
  g.setLineWidth(1)
  g.line(-s * 0.38, -s * 0.38, 0, 0, s * 0.38, -s * 0.38)
  g.line(-s * 0.38, s * 0.38, 0, 0, s * 0.38, s * 0.38)
  g.pop()

  -- Numeric face: scaled from the active UI font and intentionally upright.
  g.push()
  g.translate(self.x, self.y - self.lift)
  local font = g.getFont()
  local text = tostring(self.face)
  local fontHeight = math.max(1, font:getHeight())
  local textScale = (s * 0.52) / fontHeight
  local textWidth = font:getWidth(text) * textScale
  local textHeight = fontHeight * textScale
  g.setColor(0, 0, 0, 0.45)
  g.print(text, -textWidth / 2 + s * 0.025, -textHeight / 2 + s * 0.04,
    0, textScale, textScale)
  g.setColor(ink[1], ink[2], ink[3], 1)
  g.print(text, -textWidth / 2, -textHeight / 2, 0, textScale, textScale)
  g.pop()

  g.setLineWidth(1)
  g.setColor(1, 1, 1, 1)
end

return dice_render
