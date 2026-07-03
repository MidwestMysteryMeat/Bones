--------------------------------------------------------------------------
-- src/fx/juice.lua
-- Screenshake, hitstop, flash, near-miss slow-mo + camera zoom.
-- Usage per frame in a state:
--   local sdt = juice.update(dt)     -- scaled dt for gameplay/animation
--   juice.attach()                   -- push shake/zoom transform
--   ...draw the world...
--   juice.detach(); juice.drawOverlay(w, h)
--------------------------------------------------------------------------

local juice = {}

juice.enabled = true -- mirrors settings.screenshake

local shakeAmount, shakeTime = 0, 0
local hitstopTime = 0
local slowmoScale, slowmoTime = 1, 0
local flashColor, flashTime, flashDur = nil, 0, 0
local zoomTarget, zoom = 1, 1
local ox, oy = 0, 0

--- Shake scaled to payout size: pass chips won / table min, we clamp.
function juice.shake(intensity)
  if not juice.enabled then return end
  shakeAmount = math.min(24, math.max(shakeAmount, intensity))
  shakeTime = 0.35
end

--- Freeze the world for `dur` seconds (the moment dice land).
function juice.hitstop(dur)
  hitstopTime = math.max(hitstopTime, dur or 0.06)
end

--- Near-miss slow-mo: world runs at `scale` for `dur`, camera eases in.
function juice.slowmo(scale, dur, zoomAmount)
  slowmoScale = scale or 0.25
  slowmoTime = dur or 0.9
  zoomTarget = zoomAmount or 1.12
end

function juice.flash(color, dur)
  flashColor = color or { 1, 1, 1 }
  flashDur = dur or 0.15
  flashTime = flashDur
end

function juice.isSlowmo() return slowmoTime > 0 end

--- Returns dt scaled by hitstop/slow-mo. Call once per frame.
function juice.update(dt)
  -- Timers themselves tick in real time.
  if shakeTime > 0 then
    shakeTime = shakeTime - dt
    if shakeTime <= 0 then shakeAmount = 0 end
  end
  if flashTime > 0 then flashTime = flashTime - dt end
  if slowmoTime > 0 then
    slowmoTime = slowmoTime - dt
    if slowmoTime <= 0 then slowmoScale, zoomTarget = 1, 1 end
  end
  zoom = zoom + (zoomTarget - zoom) * math.min(1, dt * 8)

  if hitstopTime > 0 then
    hitstopTime = hitstopTime - dt
    return 0 -- the world freezes completely
  end
  return dt * slowmoScale
end

--- Push the shake/zoom transform. Pair with juice.detach().
function juice.attach()
  local g = love.graphics
  g.push()
  local w, h = g.getDimensions()
  if shakeAmount > 0 then
    ox = (love.math.random() * 2 - 1) * shakeAmount
    oy = (love.math.random() * 2 - 1) * shakeAmount
  else
    ox, oy = 0, 0
  end
  g.translate(w / 2 + ox, h / 2 + oy)
  g.scale(zoom, zoom)
  g.translate(-w / 2, -h / 2)
end

function juice.detach()
  love.graphics.pop()
end

--- Full-screen flash overlay; draw after detach, in screen space.
function juice.drawOverlay(w, h)
  if flashTime > 0 and flashColor then
    local a = (flashTime / flashDur) * 0.6
    love.graphics.setColor(flashColor[1], flashColor[2], flashColor[3], a)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return juice
