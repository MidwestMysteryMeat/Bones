--------------------------------------------------------------------------
-- states/shop.lua -- thin state wrapper around src/ui/shop_ui.lua
--------------------------------------------------------------------------

local Gamestate = require("lib.hump.gamestate")
local save      = require("src.core.save")
local screen    = require("src.ui.screen")
local widgets   = require("src.ui.widgets")
local shop_ui   = require("src.ui.shop_ui")
local steam     = require("src.steam.steam")

local state = {}
local ui

function state:enter()
  ui = shop_ui.new(save.data)
  steam.presence("Browsing the Shop")
end

function state:update(dt)
  widgets.beginFrame()
  ui:update(dt)
end

function state:draw()
  screen.drawFelt()
  ui:draw()
  local h = love.graphics.getHeight()
  if widgets.button(40, h - 70, 150, 44, "BACK") then
    Gamestate.switch(require("states.menu"))
  end
  widgets.endFrame()
end

function state:mousepressed(x, y, button)
  widgets.pressed(x, y, button)
  ui:mousepressed(x, y, button)
end

function state:keypressed(key)
  if key == "escape" then Gamestate.switch(require("states.menu")) end
end

return state
