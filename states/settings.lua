--------------------------------------------------------------------------
-- states/settings.lua -- volumes, screenshake, fullscreen.
--------------------------------------------------------------------------

local Gamestate = require("lib.hump.gamestate")
local save      = require("src.core.save")
local screen    = require("src.ui.screen")
local widgets   = require("src.ui.widgets")
local juice     = require("src.fx.juice")
local sfx       = require("src.audio.sfx")

local state = {}

function state:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  screen.drawFelt()
  screen.header("SETTINGS")

  local s = save.data.settings
  local x, y = 80, 180

  local mv, mch = widgets.slider("musicVol", x, y, 300, s.musicVol, 0, 1,
    "Music volume", "%.2f")
  y = y + 50
  local sv, sch = widgets.slider("sfxVol", x, y, 300, s.sfxVol, 0, 1,
    "SFX volume", "%.2f")
  y = y + 50
  if mch or sch then
    s.musicVol, s.sfxVol = mv, sv
    sfx.setVolumes(mv, sv)
  end

  local shake, shch = widgets.checkbox(x, y, "Screenshake", s.screenshake)
  if shch then
    s.screenshake = shake
    juice.enabled = shake
  end
  y = y + 40

  local fs, fsch = widgets.checkbox(x, y, "Fullscreen", s.fullscreen)
  if fsch then
    s.fullscreen = fs
    love.window.setFullscreen(fs, "desktop")
    screen.load() -- refit fonts to the new resolution
  end
  y = y + 60

  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.5)
  g.print("Controls: mouse to bet, SPACE to roll, ESC to leave a table", x, y)

  if widgets.button(40, h - 70, 150, 44, "BACK") then
    save.autosave("settings")
    Gamestate.switch(require("states.menu"))
  end
  widgets.endFrame()
end

function state:update(dt) widgets.beginFrame() end
function state:mousepressed(x, y, b) widgets.pressed(x, y, b) end
function state:keypressed(key)
  if key == "escape" then
    save.autosave("settings")
    Gamestate.switch(require("states.menu"))
  end
end

return state
