--------------------------------------------------------------------------
-- src/ui/hud.lua
-- The in-match table HUD: felt betting layout with clickable bet spots,
-- chip-denomination selector, roll button, wallet, point puck, house
-- chat/messages, streak meter, jackpot ticker. Mode-agnostic: it talks to
-- the match through an adapter so PvE and multiplayer share one HUD.
--
-- Adapter interface:
--   wallet() -> chips available to bet
--   betOn(betId) -> player's chips riding on that bet
--   placeBet(betId, amount) -> ok, reason
--   requestRoll()                    (nil to hide the roll button, e.g. MP)
--   canBet() -> bool
--   info() -> { phase, point, headline, jackpot, streak, messages = {},
--               minBet, maxBet, lockClock (optional, MP countdown) }
--------------------------------------------------------------------------

local config  = require("src.core.config")
local widgets = require("src.ui.widgets")
local screen  = require("src.ui.screen")

local hud = {}

local Hud = {}
Hud.__index = Hud

function hud.new(adapter)
  local self = setmetatable({}, Hud)
  self.adapter = adapter
  self.denomIndex = 1
  self.toast = nil
  self.toastTime = 0
  self:layout()
  return self
end

--- Betting layout, recomputed on resize. Coordinates are the felt spots.
function Hud:layout()
  local w, h = love.graphics.getDimensions()
  local cx = w / 2
  local top = h * 0.16
  local spots = {}
  local function spot(betId, label, x, y, sw, sh)
    spots[#spots + 1] = { betId = betId, label = label, x = x, y = y, w = sw, h = sh }
  end

  -- Place numbers across the top (craps-style number boxes).
  local nums = { 4, 5, 6, 8, 9, 10 }
  local bw = math.min(110, w * 0.085)
  local totalW = #nums * (bw + 8) - 8
  for i, n in ipairs(nums) do
    spot("place" .. n, tostring(n), cx - totalW / 2 + (i - 1) * (bw + 8), top, bw, 64)
  end

  -- Field bar under the numbers.
  spot("field", "FIELD  2,3,4,9,10,11,12", cx - totalW / 2, top + 76, totalW, 46)

  -- Pass / Don't Pass arcs (bottom band).
  spot("pass", "PASS LINE", cx - totalW / 2, top + 130, totalW * 0.62, 46)
  spot("dontpass", "DON'T PASS", cx - totalW / 2 + totalW * 0.65, top + 130,
    totalW * 0.35, 46)

  -- Proposition boxes on the right column.
  local px = cx + totalW / 2 + 20
  spot("hard4", "HARD 4 (7:1)", px, top, 130, 34)
  spot("hard6", "HARD 6 (9:1)", px, top + 40, 130, 34)
  spot("hard8", "HARD 8 (9:1)", px, top + 80, 130, 34)
  spot("hard10", "HARD 10 (7:1)", px, top + 120, 130, 34)
  spot("any7", "ANY 7 (4:1)", px, top + 162, 130, 34)
  spot("anycraps", "ANY CRAPS (7:1)", px, top + 202, 130, 34)

  self.spots = spots
  self.w, self.h = w, h
end

function Hud:say(text)
  self.toast = text
  self.toastTime = 2.2
end

function Hud:update(dt)
  if self.toastTime > 0 then
    self.toastTime = self.toastTime - dt
    if self.toastTime <= 0 then self.toast = nil end
  end
  if love.graphics.getWidth() ~= self.w then self:layout() end
end

function Hud:denom()
  return config.table.chipDenominations[self.denomIndex]
end

--- Feed clicks BEFORE widgets consume them elsewhere in the state.
function Hud:mousepressed(x, y, button)
  if button ~= 1 or not self.adapter.canBet() then return end
  for _, s in ipairs(self.spots) do
    if x >= s.x and x <= s.x + s.w and y >= s.y and y <= s.y + s.h then
      local ok, reason = self.adapter.placeBet(s.betId, self:denom())
      if ok then
        require("src.audio.sfx").play("chip_place")
      else
        self:say(reason or "can't bet there")
      end
      return true
    end
  end
end

function Hud:draw()
  local g = love.graphics
  local info = self.adapter.info()
  local w, h = g.getDimensions()

  -- Bet spots.
  g.setFont(screen.fonts.small)
  for _, s in ipairs(self.spots) do
    local riding = self.adapter.betOn(s.betId)
    local hover = widgets.hot(s.x, s.y, s.w, s.h) and self.adapter.canBet()
    g.setColor(1, 1, 1, hover and 0.16 or 0.07)
    g.rectangle("fill", s.x, s.y, s.w, s.h, 6)
    g.setColor(1, 0.92, 0.7, 0.8)
    g.rectangle("line", s.x, s.y, s.w, s.h, 6)
    g.setColor(1, 1, 1, 0.85)
    g.printf(s.label, s.x, s.y + 4, s.w, "center")
    if riding > 0 then
      widgets.chipStack(s.x + s.w / 2, s.y + s.h - 8, riding)
      g.setFont(screen.fonts.small)
      g.setColor(1, 0.84, 0.3)
      g.printf(tostring(riding), s.x, s.y + s.h - 18, s.w - 6, "right")
    end
  end

  -- Point puck (ON/OFF like a real table).
  do
    local puckX, puckY = w / 2, h * 0.16 - 26
    if info.point then
      g.setColor(0.95, 0.95, 0.95)
      g.circle("fill", puckX, puckY, 16)
      g.setColor(0, 0, 0)
      g.setFont(screen.fonts.small)
      g.printf("ON " .. info.point, puckX - 30, puckY - 8, 60, "center")
    else
      g.setColor(0.1, 0.1, 0.1)
      g.circle("fill", puckX, puckY, 16)
      g.setColor(1, 1, 1, 0.7)
      g.setFont(screen.fonts.small)
      g.printf("OFF", puckX - 30, puckY - 8, 60, "center")
    end
  end

  -- Left column: wallet, headline (tier/round), jackpot ticker, streak.
  screen.chipLabel(24, h * 0.16, "BANKROLL", self.adapter.wallet())
  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.8)
  if info.headline then g.print(info.headline, 24, h * 0.16 + 64) end
  g.setColor(1, 0.84, 0.3)
  g.print(("JACKPOT  %d"):format(info.jackpot or 0), 24, h * 0.16 + 86)
  if (info.streak or 0) >= 2 then
    g.setColor(1, 0.5, 0.15)
    local streakText = ("STREAK x%d"):format(info.streak)
    if (info.feverPct or 0) > 0 then
      streakText = streakText .. ("   FEVER +%d%%"):format(info.feverPct)
    end
    g.print(streakText, 24, h * 0.16 + 108)
    g.setColor(1, 0.5, 0.15, 0.5)
    g.rectangle("fill", 24, h * 0.16 + 128, math.min(10, info.streak) * 14, 8, 3)
  end

  -- House / chat messages, bottom-left.
  g.setFont(screen.fonts.small)
  local msgs = info.messages or {}
  for i, m in ipairs(msgs) do
    g.setColor(1, 1, 1, 0.25 + 0.75 * (i / #msgs))
    g.print(m, 24, h - 30 - (#msgs - i) * 18)
  end

  -- Denomination selector + roll button, bottom-right.
  local bx = w - 220
  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.7)
  g.print("CHIP", bx, h - 150)
  for i, d in ipairs(config.table.chipDenominations) do
    local sel = i == self.denomIndex
    if widgets.button(bx + (i - 1) * 48, h - 130, 44, 30, tostring(d),
      { small = true, color = sel and { 0.8, 0.65, 0.2 } or { 0.2, 0.2, 0.24 } }) then
      self.denomIndex = i
    end
  end
  if self.adapter.requestRoll then
    local can = self.adapter.canBet()
    if widgets.button(bx, h - 90, 188, 54, "ROLL",
      { color = { 0.65, 0.15, 0.15 }, disabled = not can }) and can then
      self.adapter.requestRoll()
    end
  elseif info.lockClock then
    g.setFont(screen.fonts.header)
    g.setColor(1, 0.9, 0.6)
    g.print(("ROLL IN %.1f"):format(info.lockClock), bx, h - 90)
  end

  -- Toast (bet rejections etc.)
  if self.toast then
    g.setFont(screen.fonts.body)
    g.setColor(0, 0, 0, 0.7)
    local tw = screen.fonts.body:getWidth(self.toast) + 24
    g.rectangle("fill", w / 2 - tw / 2, h * 0.55, tw, 34, 8)
    g.setColor(1, 0.8, 0.6)
    g.printf(self.toast, 0, h * 0.55 + 6, w, "center")
  end
  g.setColor(1, 1, 1, 1)
end

return hud
