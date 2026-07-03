--------------------------------------------------------------------------
-- src/fx/dice_render.lua
-- Fake-3D dice tumble: rapid face cycling that decelerates into the final
-- value, with rotation wobble while airborne and a satisfying squash-and-
-- settle bounce on landing. Pure vector drawing (rounded rect + pips), so
-- cosmetics are just colors from the dice catalog.
--------------------------------------------------------------------------

local dice_render = {}

-- Pip layouts on a 3x3 grid (positions 1..9, row-major).
local pipLayout = {
  [1] = { 5 },
  [2] = { 1, 9 },
  [3] = { 1, 5, 9 },
  [4] = { 1, 3, 7, 9 },
  [5] = { 1, 3, 5, 7, 9 },
  [6] = { 1, 3, 4, 6, 7, 9 },
}

local Die = {}
Die.__index = Die

local defaultCosmetic = {
  body = { 0.95, 0.93, 0.88 }, pip = { 0.15, 0.15, 0.18 },
}

function dice_render.newDie(x, y, size, cosmetic)
  return setmetatable({
    x = x, y = y, size = size or 72,
    cosmetic = cosmetic or defaultCosmetic,
    face = 1,
    state = "idle",       -- idle | tumbling | settling
    t = 0, duration = 0,
    finalFace = 1,
    cycleClock = 0,
    rot = 0, squash = 1,
    onLand = nil,
  }, Die)
end

--- Kick off a tumble that lands on finalFace after `duration` seconds.
--- onLand fires exactly once, at the landing moment (hook hitstop/SFX).
function Die:startTumble(finalFace, duration, onLand)
  self.state = "tumbling"
  self.t = 0
  self.duration = duration or 1.0
  self.finalFace = finalFace
  self.cycleClock = 0
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
      local nextFace = math.floor(love.math.random() * 6) + 1
      if nextFace == self.face then nextFace = (nextFace % 6) + 1 end
      self.face = nextFace
    end
    -- Airborne wobble eases out as it lands.
    self.rot = math.sin(self.t * 22) * 0.35 * (1 - progress)
    if progress >= 1 then
      self.face = self.finalFace
      self.state = "settling"
      self.t = 0
      self.squash = 0.72 -- landing squash, springs back below
      if self.onLand then
        local cb = self.onLand
        self.onLand = nil
        cb(self)
      end
    end
  elseif self.state == "settling" then
    self.t = self.t + dt
    -- Damped spring back to scale 1: the "settle bounce".
    local k = self.t * 12
    self.squash = 1 + (0.72 - 1) * math.exp(-k) * math.cos(k * 1.8)
    self.rot = self.rot * math.max(0, 1 - self.t * 6)
    if self.t > 0.6 then
      self.state = "idle"
      self.squash, self.rot = 1, 0
    end
  end
end

function Die:draw()
  local g = love.graphics
  local s = self.size
  local body, pip = self.cosmetic.body, self.cosmetic.pip
  local glow = self.cosmetic.glow

  g.push()
  g.translate(self.x, self.y)
  g.rotate(self.rot)
  -- Squash on Y, stretch on X (volume-ish preserving) sells the bounce.
  g.scale(2 - self.squash, self.squash)

  -- Drop shadow
  g.setColor(0, 0, 0, 0.35)
  g.rectangle("fill", -s / 2 + 4, -s / 2 + 6, s, s, s * 0.18)

  -- Rarity glow ring
  if glow then
    g.setColor(glow[1], glow[2], glow[3], 0.45)
    g.rectangle("fill", -s / 2 - 4, -s / 2 - 4, s + 8, s + 8, s * 0.22)
  end

  -- Body with a simple top-lit gradient (two rects) for fake depth.
  g.setColor(body[1], body[2], body[3])
  g.rectangle("fill", -s / 2, -s / 2, s, s, s * 0.18)
  g.setColor(1, 1, 1, 0.18)
  g.rectangle("fill", -s / 2, -s / 2, s, s * 0.45, s * 0.18)
  g.setColor(0, 0, 0, 0.25)
  g.setLineWidth(2)
  g.rectangle("line", -s / 2, -s / 2, s, s, s * 0.18)

  -- Pips
  g.setColor(pip[1], pip[2], pip[3])
  local cell = s / 4
  for _, pos in ipairs(pipLayout[self.face]) do
    local col = (pos - 1) % 3
    local row = math.floor((pos - 1) / 3)
    local px = (col - 1) * cell
    local py = (row - 1) * cell
    g.circle("fill", px, py, s * 0.085)
  end

  g.pop()
  g.setColor(1, 1, 1, 1)
end

return dice_render
