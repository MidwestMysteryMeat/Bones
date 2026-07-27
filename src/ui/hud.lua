--------------------------------------------------------------------------
-- src/ui/hud.lua
-- Responsive in-match table HUD. One layout owns every table region so the
-- betting grid, status rail, dice lane, messages, chips, and actions cannot
-- overlap at any supported window size.
--
-- Adapter interface:
--   wallet() -> chips available to bet
--   betOn(betId) -> player's chips riding on that bet
--   placeBet(betId, amount) -> ok, reason
--   requestRoll()                    (nil to hide the roll button, e.g. MP)
--   canBet() -> bool
--   info() -> { phase, point, headline, jackpot, streak, messages = {},
--               rollHistory = {}, minBet, maxBet, lockClock (optional) }
--------------------------------------------------------------------------

local config  = require("src.core.config")
local widgets = require("src.ui.widgets")
local screen  = require("src.ui.screen")

local hud = {}

local Hud = {}
Hud.__index = Hud

local COLORS = {
  gold       = { 0.93, 0.73, 0.29 },
  cream      = { 1.00, 0.94, 0.78 },
  panel      = { 0.018, 0.105, 0.066 },
  panelLight = { 0.035, 0.20, 0.115 },
  place      = { 0.10, 0.31, 0.19 },
  field      = { 0.12, 0.27, 0.22 },
  pass       = { 0.08, 0.36, 0.20 },
  dontpass   = { 0.29, 0.12, 0.13 },
  prop       = { 0.25, 0.16, 0.10 },
  red        = { 0.68, 0.15, 0.14 },
}

local BET_HELP = {
  pass = "Come-out: 7/11 wins, 2/3/12 loses. Then hit the Point before a 7.",
  dontpass = "Come-out: 2/3 wins, 12 pushes. Then a 7 must arrive before the Point.",
  field = "One roll. Wins on 2, 3, 4, 9, 10, 11 or 12.",
  place4 = "The 4 must roll before a 7 while the Point is on.",
  place5 = "The 5 must roll before a 7 while the Point is on.",
  place6 = "The 6 must roll before a 7 while the Point is on.",
  place8 = "The 8 must roll before a 7 while the Point is on.",
  place9 = "The 9 must roll before a 7 while the Point is on.",
  place10 = "The 10 must roll before a 7 while the Point is on.",
  hard4 = "Roll 2+2 before a 7 or an easy 4.",
  hard6 = "Roll 3+3 before a 7 or an easy 6.",
  hard8 = "Roll 4+4 before a 7 or an easy 8.",
  hard10 = "Roll 5+5 before a 7 or an easy 10.",
  any7 = "One roll. Wins if the total is 7.",
  anycraps = "One roll. Wins if the total is 2, 3 or 12.",
}

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function rect(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

local function contains(r, x, y)
  return x >= r.x and x <= r.x + r.w
    and y >= r.y and y <= r.y + r.h
end

local function payoutLabel(def)
  local payout = def and def.payout or 0
  if payout == math.floor(payout) then
    return ("%d:1"):format(payout)
  end
  for _, denominator in ipairs({ 5, 6 }) do
    local numerator = payout * denominator
    if math.abs(numerator - math.floor(numerator + 0.5)) < 1e-9 then
      return ("%d:%d"):format(math.floor(numerator + 0.5), denominator)
    end
  end
  return ("%.2f:1"):format(payout)
end

local function addSpot(spots, betId, label, category, bounds, detail)
  spots[#spots + 1] = {
    betId = betId,
    label = label,
    category = category,
    detail = detail,
    x = bounds.x,
    y = bounds.y,
    w = bounds.w,
    h = bounds.h,
  }
end

--- Pure layout helper, deliberately independent of LÖVE for headless tests.
function hud.layoutFor(w, h)
  local margin = clamp(math.floor(math.min(w, h) * 0.026), 14, 22)
  local gap = clamp(math.floor(h * 0.016), 8, 12)
  local statusH = clamp(math.floor(h * 0.10), 58, 72)
  local dockH = clamp(math.floor(h * 0.105), 62, 78)
  local status = rect(margin, margin, w - margin * 2, statusH)
  local dock = rect(margin, h - margin - dockH, w - margin * 2, dockH)

  local boardY = status.y + status.h + gap
  local boardH = clamp(math.floor(h * 0.27), 156, 190)
  local maximumBoardH = dock.y - boardY - 126
  boardH = math.max(140, math.min(boardH, maximumBoardH))
  local boardW = math.min(w - margin * 2, 1180)
  local board = rect((w - boardW) / 2, boardY, boardW, boardH)

  local trayY = board.y + board.h + gap
  local trayInset = clamp(math.floor(board.w * 0.055), 34, 72)
  local tray = rect(
    board.x + trayInset,
    trayY,
    board.w - trayInset * 2,
    math.max(104, dock.y - trayY - gap)
  )
  tray.headerH = clamp(math.floor(tray.h * 0.18), 26, 34)
  tray.content = rect(
    tray.x + 8,
    tray.y + tray.headerH,
    tray.w - 16,
    math.max(64, tray.h - tray.headerH - 8)
  )
  tray.dieSize = clamp(math.floor(tray.content.h * 0.50), 58, 90)
  tray.centerX = tray.x + tray.w / 2
  tray.centerY = tray.content.y + tray.content.h * 0.54
  tray.dieGap = tray.dieSize * 0.72

  local boardPad = 8
  local columnGap = 9
  local propW = clamp(math.floor(board.w * 0.225), 204, 252)
  local primaryW = board.w - boardPad * 2 - columnGap - propW
  local primary = rect(board.x + boardPad, board.y + boardPad,
    primaryW, board.h - boardPad * 2)
  local props = rect(primary.x + primary.w + columnGap, primary.y,
    propW, primary.h)

  local rowGap = 7
  local usableH = primary.h - rowGap * 2
  local numberH = math.floor(usableH * 0.37)
  local fieldH = math.floor(usableH * 0.28)
  local lineH = usableH - numberH - fieldH
  local numberY = primary.y
  local fieldY = numberY + numberH + rowGap
  local lineY = fieldY + fieldH + rowGap
  local numberGap = 7
  local numberW = (primary.w - numberGap * 5) / 6

  local spots = {}
  local numbers = { 4, 5, 6, 8, 9, 10 }
  for i, number in ipairs(numbers) do
    local def = config.betsById["place" .. number]
    addSpot(spots, "place" .. number, tostring(number), "place",
      rect(primary.x + (i - 1) * (numberW + numberGap),
        numberY, numberW, numberH),
      payoutLabel(def))
  end
  addSpot(spots, "field", "FIELD", "field",
    rect(primary.x, fieldY, primary.w, fieldH),
    "2 · 3 · 4 · 9 · 10 · 11 · 12")

  local passGap = 9
  local passW = math.floor((primary.w - passGap) * 0.63)
  addSpot(spots, "pass", "PASS LINE", "pass",
    rect(primary.x, lineY, passW, lineH), "1:1")
  addSpot(spots, "dontpass", "DON'T PASS", "dontpass",
    rect(primary.x + passW + passGap, lineY,
      primary.w - passW - passGap, lineH), "1:1")

  local propGap = 7
  local propCellW = (props.w - propGap) / 2
  local propCellH = (props.h - propGap * 2) / 3
  local propDefs = {
    { "hard4", "HARD 4" }, { "hard6", "HARD 6" },
    { "hard8", "HARD 8" }, { "hard10", "HARD 10" },
    { "any7", "ANY 7" }, { "anycraps", "ANY CRAPS" },
  }
  for index, item in ipairs(propDefs) do
    local column = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    addSpot(spots, item[1], item[2], "prop",
      rect(props.x + column * (propCellW + propGap),
        props.y + row * (propCellH + propGap),
        propCellW, propCellH),
      payoutLabel(config.betsById[item[1]]))
  end

  local dockPad = 10
  local actionH = dock.h - dockPad * 2
  local rollW = clamp(math.floor(dock.w * 0.15), 148, 190)
  local roll = rect(dock.x + dock.w - dockPad - rollW,
    dock.y + dockPad, rollW, actionH)
  local chipButtonW = clamp(math.floor((dock.w - 600) / 10 + 36), 38, 46)
  local chipGap = 5
  local chipTotalW = chipButtonW * #config.table.chipDenominations
    + chipGap * (#config.table.chipDenominations - 1)
  local chipLabelW = 42
  local chipGroupW = chipLabelW + chipTotalW
  local chipGroupX = roll.x - gap - chipGroupW
  local chips = {}
  for i = 1, #config.table.chipDenominations do
    chips[i] = rect(
      chipGroupX + chipLabelW + (i - 1) * (chipButtonW + chipGap),
      dock.y + dockPad, chipButtonW, actionH)
  end
  local cashOut = rect(dock.x + dockPad, dock.y + dockPad,
    clamp(math.floor(dock.w * 0.125), 118, 148), actionH)
  local messageX = cashOut.x + cashOut.w + gap
  local message = rect(messageX, dock.y + dockPad,
    math.max(80, chipGroupX - gap - messageX), actionH)

  return {
    width = w,
    height = h,
    status = status,
    board = board,
    primary = primary,
    props = props,
    tray = tray,
    dock = dock,
    spots = spots,
    cashOut = cashOut,
    roll = roll,
    chips = chips,
    chipLabelX = chipGroupX,
    message = message,
  }
end

function hud.new(adapter)
  local self = setmetatable({}, Hud)
  self.adapter = adapter
  self.denomIndex = 1
  self.toast = nil
  self.toastTime = 0
  self.geometry = nil
  self.hoveredSpot = nil
  self:layout()
  return self
end

function Hud:layout()
  local w, h = love.graphics.getDimensions()
  self.geometry = hud.layoutFor(w, h)
  self.spots = self.geometry.spots
  self.w, self.h = w, h
end

function Hud:getDiceTray()
  return self.geometry.tray
end

function Hud:getAuxButtonRect()
  return self.geometry.cashOut
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
  local w, h = love.graphics.getDimensions()
  if w ~= self.w or h ~= self.h then self:layout() end
end

function Hud:denom()
  return config.table.chipDenominations[self.denomIndex]
end

function Hud:keypressed(key)
  local index = tonumber(key)
  if index and index >= 1 and index <= #config.table.chipDenominations then
    self.denomIndex = index
    return true
  end
  return false
end

--- Feed clicks BEFORE widgets consume them elsewhere in the state.
function Hud:mousepressed(x, y, button)
  if button ~= 1 or not self.adapter.canBet() then return end
  for _, spot in ipairs(self.spots) do
    if contains(spot, x, y) then
      local ok, reason = self.adapter.placeBet(spot.betId, self:denom())
      if ok then
        require("src.audio.sfx").play("chip_place")
      else
        self:say(reason or "can't bet there")
      end
      return true
    end
  end
end

local function drawPanel(bounds, alpha, radius)
  local g = love.graphics
  g.setColor(COLORS.panel[1], COLORS.panel[2], COLORS.panel[3], alpha or 0.9)
  g.rectangle("fill", bounds.x, bounds.y, bounds.w, bounds.h, radius or 10)
  g.setLineWidth(1.5)
  g.setColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.42)
  g.rectangle("line", bounds.x, bounds.y, bounds.w, bounds.h, radius or 10)
end

local function drawPuck(info, bounds)
  local g = love.graphics
  local radius = math.min(16, bounds.h * 0.29)
  local x = bounds.x + radius + 10
  local y = bounds.y + bounds.h / 2
  if info.point then
    g.setColor(0.94, 0.94, 0.90)
  else
    g.setColor(0.07, 0.075, 0.075)
  end
  g.circle("fill", x, y, radius)
  g.setColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.65)
  g.setLineWidth(1.5)
  g.circle("line", x, y, radius)
  g.setFont(screen.fonts.small)
  g.setColor(info.point and 0.05 or 0.9, info.point and 0.05 or 0.9,
    info.point and 0.05 or 0.9, 0.95)
  g.printf(info.point and tostring(info.point) or "OFF",
    x - radius, y - screen.fonts.small:getHeight() / 2,
    radius * 2, "center")
end

function Hud:drawStatus(info)
  local g = love.graphics
  local status = self.geometry.status
  drawPanel(status, 0.91, 11)

  local leftW = clamp(status.w * 0.19, 155, 220)
  local rightW = clamp(status.w * 0.22, 190, 255)
  local center = rect(status.x + leftW, status.y,
    status.w - leftW - rightW, status.h)
  local rightX = status.x + status.w - rightW

  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.58)
  g.print("BANKROLL", status.x + 14, status.y + 8)
  g.setFont(screen.fonts.header)
  g.setColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
  g.print(tostring(math.floor(self.adapter.wallet())),
    status.x + 14, status.y + status.h - screen.fonts.header:getHeight() - 6)

  g.setFont(screen.fonts.body)
  g.setColor(COLORS.cream[1], COLORS.cream[2], COLORS.cream[3], 0.95)
  g.printf(info.headline or "TABLE OPEN", center.x, center.y + 8,
    center.w, "center")
  g.setFont(screen.fonts.small)
  g.setColor(0.62, 0.86, 0.72, 0.9)
  local objective
  if info.point then
    objective = ("POINT %d  ·  HIT %d BEFORE 7"):format(info.point, info.point)
  else
    objective = "COME-OUT  ·  7 OR 11 WINS THE PASS LINE"
  end
  g.printf(objective, center.x, center.y + center.h - 22,
    center.w, "center")
  drawPuck(info, center)

  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.58)
  g.print("PROGRESSIVE", rightX + 12, status.y + 8)
  g.setFont(screen.fonts.body)
  g.setColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
  g.print(("JACKPOT  %d"):format(info.jackpot or 0),
    rightX + 12, status.y + 26)
  if (info.streak or 0) >= 2 then
    g.setFont(screen.fonts.small)
    g.setColor(1, 0.52, 0.18)
    local streak = ("STREAK x%d"):format(info.streak)
    if (info.feverPct or 0) > 0 then
      streak = streak .. ("  ·  FEVER +%d%%"):format(info.feverPct)
    end
    g.print(streak, rightX + 12, status.y + status.h - 20)
  end
end

local function spotColor(category)
  return COLORS[category] or COLORS.place
end

function Hud:drawBoard(info)
  local g = love.graphics
  local geometry = self.geometry
  drawPanel(geometry.board, 0.52, 12)
  self.hoveredSpot = nil

  g.setFont(screen.fonts.small)
  for _, spot in ipairs(self.spots) do
    local riding = self.adapter.betOn(spot.betId)
    local hover = widgets.hot(spot.x, spot.y, spot.w, spot.h)
      and self.adapter.canBet()
    if hover then self.hoveredSpot = spot end
    local color = spotColor(spot.category)
    local multiplier = hover and 1.28 or 1
    g.setColor(
      math.min(1, color[1] * multiplier),
      math.min(1, color[2] * multiplier),
      math.min(1, color[3] * multiplier),
      self.adapter.canBet() and 0.96 or 0.68)
    g.rectangle("fill", spot.x, spot.y, spot.w, spot.h, 7)

    local pointSpot = info.point and spot.betId == "place" .. info.point
    g.setLineWidth(pointSpot and 3 or (hover and 2 or 1.25))
    if pointSpot then
      g.setColor(0.95, 0.95, 0.90, 0.95)
    else
      g.setColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3],
        hover and 0.92 or 0.56)
    end
    g.rectangle("line", spot.x, spot.y, spot.w, spot.h, 7)

    local labelY = spot.y + math.max(4,
      (spot.h - screen.fonts.small:getHeight() * 2) / 2 - 1)
    g.setFont(screen.fonts.small)
    g.setColor(COLORS.cream[1], COLORS.cream[2], COLORS.cream[3], 0.96)
    g.printf(spot.label, spot.x + 3, labelY, spot.w - 6, "center")
    g.setColor(1, 1, 1, 0.54)
    g.printf(spot.detail or "", spot.x + 3,
      labelY + screen.fonts.small:getHeight(), spot.w - 6, "center")

    if riding > 0 then
      local badgeText = tostring(riding)
      local badgeW = math.max(24, screen.fonts.small:getWidth(badgeText) + 12)
      local badgeH = math.min(20, spot.h * 0.36)
      local badgeX = spot.x + spot.w - badgeW - 5
      local badgeY = spot.y + spot.h - badgeH - 4
      g.setColor(0.96, 0.72, 0.18, 0.96)
      g.rectangle("fill", badgeX, badgeY, badgeW, badgeH, badgeH / 2)
      g.setColor(0.08, 0.07, 0.04, 1)
      g.printf(badgeText, badgeX, badgeY + (badgeH
        - screen.fonts.small:getHeight()) / 2, badgeW, "center")
    end
  end
end

local function historyValue(entry)
  if type(entry) == "number" then return entry end
  if type(entry) ~= "table" then return nil end
  return entry.sum or (entry.dice and (entry.dice[1] or 0)
    + (entry.dice[2] or 0))
end

function Hud:drawTray(info)
  local g = love.graphics
  local tray = self.geometry.tray
  drawPanel(tray, 0.34, 18)
  g.setColor(0, 0, 0, 0.16)
  g.rectangle("fill", tray.content.x, tray.content.y,
    tray.content.w, tray.content.h, 12)
  g.setColor(0.45, 0.72, 0.54, 0.16)
  g.rectangle("line", tray.content.x, tray.content.y,
    tray.content.w, tray.content.h, 12)

  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.48)
  g.print("DICE LANE", tray.x + 14,
    tray.y + (tray.headerH - screen.fonts.small:getHeight()) / 2)

  local history = info.rollHistory or {}
  local count = math.min(6, #history)
  if count > 0 then
    local badge = math.min(22, tray.headerH - 6)
    local gap = 5
    local startX = tray.x + tray.w - 14 - count * badge - (count - 1) * gap
    g.setColor(1, 1, 1, 0.42)
    g.print("RECENT", startX - screen.fonts.small:getWidth("RECENT") - 9,
      tray.y + (tray.headerH - screen.fonts.small:getHeight()) / 2)
    for i = 1, count do
      local entry = history[#history - count + i]
      local value = historyValue(entry) or 0
      local x = startX + (i - 1) * (badge + gap)
      if value == 7 then
        g.setColor(0.67, 0.16, 0.15, 0.95)
      elseif type(entry) == "table" and entry.isDouble then
        g.setColor(0.78, 0.59, 0.16, 0.95)
      else
        g.setColor(0.12, 0.29, 0.20, 0.95)
      end
      g.circle("fill", x + badge / 2, tray.y + tray.headerH / 2, badge / 2)
      g.setColor(1, 1, 1, 0.82)
      g.circle("line", x + badge / 2, tray.y + tray.headerH / 2, badge / 2)
      g.printf(tostring(value), x,
        tray.y + (tray.headerH - screen.fonts.small:getHeight()) / 2,
        badge, "center")
    end
  end
end

function Hud:drawDock(info)
  local g = love.graphics
  local geometry = self.geometry
  drawPanel(geometry.dock, 0.94, 11)

  local message = geometry.message
  local newest = info.messages and info.messages[#info.messages]
  local helperTitle = "TABLE TALK"
  local helperText = newest or "Place chips on the felt, then roll."
  if self.hoveredSpot then
    helperTitle = self.hoveredSpot.label .. "  ·  "
      .. (self.hoveredSpot.detail or "")
    helperText = BET_HELP[self.hoveredSpot.betId] or helperText
  end
  g.setFont(screen.fonts.small)
  g.setColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.82)
  g.print(helperTitle, message.x, message.y + 1)
  g.setColor(1, 1, 1, 0.62)
  g.printf(helperText, message.x, message.y + 18, message.w,
    "left")

  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.48)
  g.printf("CHIP\n1–4", geometry.chipLabelX,
    geometry.dock.y + 11, 38, "center")
  for i, denomination in ipairs(config.table.chipDenominations) do
    local selected = i == self.denomIndex
    if widgets.button(geometry.chips[i].x, geometry.chips[i].y,
      geometry.chips[i].w, geometry.chips[i].h, tostring(denomination), {
        small = true,
        color = selected and { 0.78, 0.56, 0.13 } or { 0.14, 0.18, 0.18 },
      }) then
      self.denomIndex = i
    end
  end

  if self.adapter.requestRoll then
    local canRoll = self.adapter.canBet()
    if widgets.button(geometry.roll.x, geometry.roll.y,
      geometry.roll.w, geometry.roll.h, "ROLL  [SPACE]", {
        color = COLORS.red,
        disabled = not canRoll,
      }) and canRoll then
      self.adapter.requestRoll()
    end
  elseif info.lockClock then
    g.setFont(screen.fonts.body)
    g.setColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
    g.printf(("ROLL IN %.1f"):format(info.lockClock),
      geometry.roll.x, geometry.roll.y
        + (geometry.roll.h - screen.fonts.body:getHeight()) / 2,
      geometry.roll.w, "center")
  end
end

function Hud:draw()
  local info = self.adapter.info()
  self:drawStatus(info)
  self:drawBoard(info)
  self:drawTray(info)
  self:drawDock(info)
  love.graphics.setColor(1, 1, 1, 1)
end

--- Transient messaging is drawn after the dice so a rejection can never be
--- hidden by a die passing underneath it.
function Hud:drawOverlay()
  if not self.toast then return end
  local g = love.graphics
  local tray = self.geometry.tray
  g.setFont(screen.fonts.body)
  local width = math.min(tray.w - 30,
    screen.fonts.body:getWidth(self.toast) + 30)
  local x = tray.x + (tray.w - width) / 2
  local y = tray.y + tray.headerH + 10
  g.setColor(0.025, 0.025, 0.025, 0.88)
  g.rectangle("fill", x, y, width, 36, 9)
  g.setColor(1, 0.76, 0.48)
  g.printf(self.toast, x, y + (36 - screen.fonts.body:getHeight()) / 2,
    width, "center")
  g.setColor(1, 1, 1, 1)
end

return hud
