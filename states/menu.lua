--------------------------------------------------------------------------
-- states/menu.lua
-- Main menu: Solo Run / Ranked / Casual / Shop / Leaderboards / Settings.
-- Also claims the daily login reward with a toast on entry.
--------------------------------------------------------------------------

local Gamestate = require("lib.hump.gamestate")
local config    = require("src.core.config")
local economy   = require("src.core.economy")
local save      = require("src.core.save")
local rewards   = require("src.meta.rewards")
local screen    = require("src.ui.screen")
local widgets   = require("src.ui.widgets")
local steam     = require("src.steam.steam")
local dice_render = require("src.fx.dice_render")

local menu = {}

local decoDice = {}
local dailyToast, dailyToastTime = nil, 0

function menu:enter()
  steam.presence("In the Menu")
  -- Decorative tumbling dice behind the title.
  decoDice = {}
  local w = love.graphics.getWidth()
  for i = 1, 2 do
    local d = dice_render.newDie(w * 0.78 + (i - 1) * 90, 180 + (i - 1) * 40, 80)
    d:startTumble(math.floor(love.math.random() * 6) + 1, 1.2 + i * 0.3)
    decoDice[i] = d
  end
  local daily = rewards.claimDaily(save.data)
  if daily then
    dailyToast = ("DAILY REWARD  +%d chips  (day %d streak)")
      :format(daily.chips, daily.day)
    dailyToastTime = 5
    save.autosave("daily")
  end
end

function menu:update(dt)
  for _, d in ipairs(decoDice) do
    d:update(dt)
    if not d:isRolling() and love.math.random() < dt * 0.3 then
      d:startTumble(math.floor(love.math.random() * 6) + 1, 1.0)
    end
  end
  if dailyToastTime > 0 then dailyToastTime = dailyToastTime - dt end
end

function menu:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  screen.drawFelt()

  for _, d in ipairs(decoDice) do d:draw() end

  g.setFont(screen.fonts.title)
  g.setColor(1, 0.92, 0.7)
  g.print(config.TITLE:upper(), 60, 70)
  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.5)
  g.print("v" .. config.VERSION .. "  -  play-money dice, no real gambling", 62, 130)

  screen.chipLabel(w - 220, 30, "WALLET", economy.getWallet())

  local bw, bh, gap = 320, 44, 10
  local x, y = 60, 180
  local entries = {
    { "SOLO RUN",       "pve" },
    { "BONEYARD  (BATTLE ROYALE)", "battleroyale" },
    { "RANKED",         "ranked_lobby" },
    { "CASUAL MATCH",   "casual_lobby" },
    { "SHOP",           "shop" },
    { "HOW TO PLAY",    "tutorial" },
    { "LEADERBOARDS",   "leaderboards" },
    { "SETTINGS",       "settings" },
  }
  for i, e in ipairs(entries) do
    if widgets.button(x, y + (i - 1) * (bh + gap), bw, bh, e[1]) then
      Gamestate.switch(require("states." .. e[2]))
    end
  end
  if widgets.button(x, y + #entries * (bh + gap), bw, bh, "QUIT",
    { color = { 0.35, 0.12, 0.12 } }) then
    love.event.quit()
  end

  if dailyToastTime > 0 and dailyToast then
    g.setFont(screen.fonts.body)
    g.setColor(0, 0, 0, 0.7)
    local tw = screen.fonts.body:getWidth(dailyToast) + 30
    g.rectangle("fill", w / 2 - tw / 2, h - 70, tw, 40, 10)
    g.setColor(1, 0.84, 0.3)
    g.printf(dailyToast, 0, h - 62, w, "center")
  end
  g.setColor(1, 1, 1, 1)
end

function menu:mousepressed(x, y, button)
  widgets.pressed(x, y, button)
end

return menu
