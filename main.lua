--------------------------------------------------------------------------
-- main.lua -- boot, global wiring, love callbacks.
-- All real logic lives in src/; states/ are hump.gamestate screens.
--------------------------------------------------------------------------

local Gamestate = require("lib.hump.gamestate")

local save      = require("src.core.save")
local economy   = require("src.core.economy")
local screen    = require("src.ui.screen")
local widgets   = require("src.ui.widgets")
local particles = require("src.fx.particles")
local juice     = require("src.fx.juice")
local sfx       = require("src.audio.sfx")
local steam     = require("src.steam.steam")

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")

  local data = save.load()
  economy.init(data)
  economy.onChanged = nil -- autosaves are event-driven, not per-mutation

  screen.load()
  particles.load()
  sfx.load(data.settings)
  juice.enabled = data.settings.screenshake
  if data.settings.fullscreen then
    love.window.setFullscreen(true, "desktop")
    screen.load()
  end

  steam.init() -- no-ops with a log line when Steam isn't running

  Gamestate.registerEvents() -- routes love callbacks into the active state
  Gamestate.switch(require("states.menu"))
end

function love.update(dt)
  steam.update() -- pump Steam callbacks every frame
end

function love.resize()
  screen.load() -- refit fonts
end

-- Controller support: map the essentials so a pad can drive the tables.
-- TODO(controller): full focus-based navigation for menus; for now the
-- pad covers roll/back and the mouse handles bet placement.
function love.gamepadpressed(_, button)
  local stateTable = Gamestate.current()
  if button == "a" and stateTable.keypressed then
    stateTable:keypressed("space")
  elseif button == "b" and stateTable.keypressed then
    stateTable:keypressed("escape")
  end
end

function love.quit()
  save.autosave("quit")
  steam.shutdown()
end
