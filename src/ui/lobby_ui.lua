--------------------------------------------------------------------------
-- src/ui/lobby_ui.lua
-- Lobby drawing helpers shared by the Casual and Ranked lobby state:
-- host settings panel (checkboxes over the config bet table, sliders for
-- chips/limits/rounds), player list, join code, chat box.
--------------------------------------------------------------------------

local config  = require("src.core.config")
local widgets = require("src.ui.widgets")
local screen  = require("src.ui.screen")

local lobby_ui = {}

--- Host settings editor (mutates `rules` in place). Casual only; ranked
--- rules are fixed. Draws at (x, y), returns height used.
function lobby_ui.drawHostSettings(rules, x, y)
  local g = love.graphics
  g.setFont(screen.fonts.body)
  g.setColor(1, 0.92, 0.7)
  g.print("HOST SETTINGS", x, y)
  y = y + 40

  rules.startChips = math.floor(widgets.slider("startChips", x, y, 220,
    rules.startChips, 100, 10000, "Starting chips"))
  y = y + 40
  rules.minBet = math.floor(widgets.slider("minBet", x, y, 220,
    rules.minBet, 1, 100, "Min bet"))
  y = y + 40
  rules.maxBet = math.floor(widgets.slider("maxBet", x, y, 220,
    math.max(rules.maxBet, rules.minBet), rules.minBet, 5000, "Max bet"))
  y = y + 40
  rules.rounds = math.floor(widgets.slider("rounds", x, y, 220,
    rules.rounds, 1, 50, "Rounds"))
  y = y + 34

  rules.jackpot = widgets.checkbox(x, y, "Progressive jackpot", rules.jackpot)
  y = y + 28
  rules.chaos = widgets.checkbox(x, y,
    "CHAOS MODE (silly unfair dice, for laughs)", rules.chaos)
  y = y + 36

  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.7)
  g.print("Allowed bets:", x, y)
  y = y + 24
  local col, colW = 0, 150
  for _, def in ipairs(config.bets) do
    rules.allowedBets[def.id] = widgets.checkbox(
      x + col * colW, y, def.label, rules.allowedBets[def.id])
    col = col + 1
    if col >= 3 then col = 0 y = y + 26 end
  end
  if col > 0 then y = y + 26 end
  return y
end

--- Player list with chips.
function lobby_ui.drawPlayers(lobby, x, y)
  local g = love.graphics
  g.setFont(screen.fonts.body)
  g.setColor(1, 0.92, 0.7)
  g.print("PLAYERS", x, y)
  g.setFont(screen.fonts.small)
  if not lobby or not lobby.players or #lobby.players == 0 then
    g.setColor(1, 1, 1, 0.5)
    g.print("waiting for players...", x, y + 30)
    return
  end
  for i, p in ipairs(lobby.players) do
    g.setColor(1, 1, 1, 0.9)
    g.print(("%d. %s"):format(i, p.name), x, y + 6 + i * 24)
    g.setColor(1, 0.84, 0.3)
    g.print(tostring(p.chips), x + 180, y + 6 + i * 24)
  end
end

--- Chat log + input. Returns the message to send (once) or nil.
function lobby_ui.drawChat(chatLog, x, y, w)
  local g = love.graphics
  g.setFont(screen.fonts.small)
  local shown = math.min(8, #chatLog)
  for i = 1, shown do
    local m = chatLog[#chatLog - shown + i]
    g.setColor(1, 0.84, 0.3, 0.9)
    g.print(m.name .. ":", x, y + (i - 1) * 20)
    g.setColor(1, 1, 1, 0.9)
    g.print(m.text, x + 8 + screen.fonts.small:getWidth(m.name .. ":"),
      y + (i - 1) * 20)
  end
  local text = widgets.textInput("chat", x, y + shown * 20 + 6, w - 90, "say something...")
  local send = widgets.button(x + w - 80, y + shown * 20 + 6, 80, 32, "SEND",
    { small = true })
  if send and text ~= "" then
    widgets.setInputText("chat", "")
    return text
  end
  return nil
end

return lobby_ui
