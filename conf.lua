-- conf.lua -- window, title, identity, modules
-- Title/identity come from src/core/config.lua so renaming the game is a
-- one-constant change.

local config = require("src.core.config")

function love.conf(t)
  t.identity = config.IDENTITY
  t.version = "11.5"
  t.console = false

  t.window.title = config.TITLE
  t.window.width = config.window.width
  t.window.height = config.window.height
  t.window.minwidth = config.window.minWidth
  t.window.minheight = config.window.minHeight
  t.window.resizable = true
  t.window.vsync = config.window.vsync

  -- Trim modules we never use.
  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
end
