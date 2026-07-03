--------------------------------------------------------------------------
-- src/fx/particles.lua
-- Coin bursts on wins (escalating with amount), sparks, and the full-
-- screen jackpot coin fountain. Textures are generated at runtime so the
-- game runs with zero art assets.
--------------------------------------------------------------------------

local particles = {}

local systems = {}   -- live one-shot systems: { ps, life }
local fountain = nil -- persistent jackpot fountain
local fountainTime = 0

local coinImg, sparkImg

local function makeCoinImage()
  local size = 12
  local data = love.image.newImageData(size, size)
  local c, r = size / 2, size / 2 - 1
  data:mapPixel(function(x, y)
    local dx, dy = x - c + 0.5, y - c + 0.5
    local d = math.sqrt(dx * dx + dy * dy)
    if d > r then return 0, 0, 0, 0 end
    if d > r - 1.5 then return 0.7, 0.5, 0.1, 1 end -- rim
    return 1.0, 0.84, 0.25, 1                        -- gold face
  end)
  return love.graphics.newImage(data)
end

local function makeSparkImage()
  local data = love.image.newImageData(4, 4)
  data:mapPixel(function() return 1, 1, 1, 1 end)
  return love.graphics.newImage(data)
end

function particles.load()
  coinImg = makeCoinImage()
  sparkImg = makeSparkImage()
end

--- Coin burst at (x, y). `scale` 0..1+ escalates count/speed with payout:
--- pass e.g. win / (tableMin * 20), clamped inside.
function particles.coinBurst(x, y, scale)
  if not coinImg then particles.load() end
  scale = math.min(3, math.max(0.2, scale or 1))
  local ps = love.graphics.newParticleSystem(coinImg, 256)
  ps:setPosition(x, y)
  ps:setParticleLifetime(0.5, 1.1)
  ps:setSpeed(120 * scale, 340 * scale)
  ps:setDirection(-math.pi / 2)
  ps:setSpread(math.pi * 0.9)
  ps:setLinearAcceleration(0, 600, 0, 800) -- gravity
  ps:setRotation(0, math.pi * 2)
  ps:setSpin(-8, 8)
  ps:setSizes(1, 0.7)
  ps:emit(math.floor(20 + 50 * scale))
  systems[#systems + 1] = { ps = ps, life = 1.4 }
end

--- Quick white sparks (dice landing, chip slides).
function particles.sparks(x, y)
  if not sparkImg then particles.load() end
  local ps = love.graphics.newParticleSystem(sparkImg, 64)
  ps:setPosition(x, y)
  ps:setParticleLifetime(0.15, 0.4)
  ps:setSpeed(60, 220)
  ps:setSpread(math.pi * 2)
  ps:setSizes(1, 0)
  ps:emit(14)
  systems[#systems + 1] = { ps = ps, life = 0.5 }
end

--- Full-screen jackpot fountain for `dur` seconds from the bottom center.
function particles.jackpotFountain(w, h, dur)
  if not coinImg then particles.load() end
  fountain = love.graphics.newParticleSystem(coinImg, 2048)
  fountain:setPosition(w / 2, h + 10)
  fountain:setEmissionRate(400)
  fountain:setParticleLifetime(1.2, 2.2)
  fountain:setSpeed(500, 900)
  fountain:setDirection(-math.pi / 2)
  fountain:setSpread(math.pi * 0.45)
  fountain:setLinearAcceleration(0, 700, 0, 900)
  fountain:setRotation(0, math.pi * 2)
  fountain:setSpin(-10, 10)
  fountain:setSizes(1.4, 1)
  fountainTime = dur or 3.0
end

function particles.update(dt)
  for i = #systems, 1, -1 do
    local s = systems[i]
    s.ps:update(dt)
    s.life = s.life - dt
    if s.life <= 0 and s.ps:getCount() == 0 then table.remove(systems, i) end
  end
  if fountain then
    fountain:update(dt)
    fountainTime = fountainTime - dt
    if fountainTime <= 0 then fountain:setEmissionRate(0) end
    if fountainTime <= 0 and fountain:getCount() == 0 then fountain = nil end
  end
end

function particles.draw()
  love.graphics.setColor(1, 1, 1, 1)
  for _, s in ipairs(systems) do love.graphics.draw(s.ps) end
  if fountain then love.graphics.draw(fountain) end
end

return particles
