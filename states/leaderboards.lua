--------------------------------------------------------------------------
-- states/leaderboards.lua
-- Local leaderboards (ranked rating + biggest single win). Steam boards
-- upload through steam.lua; showing global Steam entries is a TODO below.
--------------------------------------------------------------------------

local Gamestate   = require("lib.hump.gamestate")
local save        = require("src.core.save")
local leaderboard = require("src.meta.leaderboard")
local rewards     = require("src.meta.rewards")
local screen      = require("src.ui.screen")
local widgets     = require("src.ui.widgets")

local state = {}
local tab = 1 -- 1 rating, 2 big win, 3 achievements

function state:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  screen.drawFelt()
  screen.header("LEADERBOARDS")

  local tabs = { "RANKED RATING", "BIGGEST WIN", "ACHIEVEMENTS" }
  for i, label in ipairs(tabs) do
    if widgets.button(40 + (i - 1) * 220, 90, 210, 40, label,
      { small = true, color = tab == i and { 0.8, 0.65, 0.2 } or nil }) then
      tab = i
    end
  end

  local y = 160
  g.setFont(screen.fonts.body)
  if tab == 3 then
    for _, a in ipairs(rewards.achievements) do
      local got = save.data.achievements[a.id]
      g.setColor(got and { 0.6, 1, 0.7 } or { 1, 1, 1, 0.35 })
      g.print((got and "[x] " or "[ ] ") .. a.label, 60, y)
      g.setFont(screen.fonts.small)
      g.setColor(1, 1, 1, got and 0.7 or 0.3)
      g.print(a.desc, 320, y + 4)
      g.setFont(screen.fonts.body)
      y = y + 32
    end
  else
    local boardName = tab == 1 and leaderboard.BOARD_RATING
      or leaderboard.BOARD_BIG_WIN
    local top = leaderboard.getTop(save.data, boardName, 15)
    if #top == 0 then
      g.setColor(1, 1, 1, 0.5)
      g.print("no scores yet - go play!", 60, y)
    end
    for i, e in ipairs(top) do
      g.setColor(1, 1, 1, 0.9)
      g.print(("%2d.  %s"):format(i, e.name), 60, y)
      g.setColor(1, 0.84, 0.3)
      g.print(tostring(e.score), 380, y)
      g.setColor(1, 1, 1, 0.4)
      g.setFont(screen.fonts.small)
      g.print(e.date or "", 500, y + 4)
      g.setFont(screen.fonts.body)
      y = y + 30
    end
    -- TODO(steam): when Steam is available, fetch and interleave global
    -- entries via luasteam.userStats.downloadLeaderboardEntries.
  end

  g.setColor(1, 1, 1, 1)
  if widgets.button(40, h - 70, 150, 44, "BACK") then
    Gamestate.switch(require("states.menu"))
  end
  widgets.endFrame()
end

function state:update(dt) widgets.beginFrame() end
function state:mousepressed(x, y, b) widgets.pressed(x, y, b) end
function state:keypressed(key)
  if key == "escape" then Gamestate.switch(require("states.menu")) end
end

return state
