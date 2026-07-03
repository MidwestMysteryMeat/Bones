--------------------------------------------------------------------------
-- states/casual_lobby.lua
-- Casual custom match: host a private lobby (rules editor + join code) or
-- join by IP/code. Session chips only - the real wallet is never touched.
--------------------------------------------------------------------------

local Gamestate = require("lib.hump.gamestate")
local config    = require("src.core.config")
local casual    = require("src.modes.casual")
local netserver = require("src.net.server")
local netclient = require("src.net.client")
local screen    = require("src.ui.screen")
local widgets   = require("src.ui.widgets")
local lobby_ui  = require("src.ui.lobby_ui")
local steam     = require("src.steam.steam")

local state = {}

local mode = "pick"        -- pick | hosting | joining
local rules
local server, client
local errorMsg

function state:enter()
  mode = "pick"
  rules = casual.defaultRules()
  server, client, errorMsg = nil, nil, nil
  steam.presence("Setting up a Casual Match")
end

local function startHosting()
  local ok, err = pcall(function()
    server = netserver.new({ mode = "casual", rules = rules })
    client = netclient.new("localhost", server.port, "Host", {})
  end)
  if ok then
    mode = "hosting"
    -- TODO(steam-lobby): when steam.available, also steam.createLobby()
    -- and publish the join info so friends can join via invite instead of
    -- typing an IP.
  else
    errorMsg = "hosting failed: " .. tostring(err)
    server, client = nil, nil
  end
end

local function join(address)
  local ok, err = pcall(function()
    client = netclient.new(address, config.net.defaultPort, "Guest", {})
  end)
  if ok then
    mode = "joining"
  else
    errorMsg = "join failed: " .. tostring(err)
  end
end

function state:update(dt)
  widgets.beginFrame()
  if server then server:update(dt) end
  if client then
    client:update(dt)
    if client.state == "playing" then
      Gamestate.switch(require("states.match"),
        { client = client, server = server, mode = "casual" })
      -- match state owns them now; forget so leave() doesn't destroy them
      server, client = nil, nil
      return
    end
  end
end

function state:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  screen.drawFelt()
  screen.header("CASUAL MATCH")

  if mode == "pick" then
    g.setFont(screen.fonts.body)
    g.setColor(1, 1, 1, 0.8)
    g.print("Private table with friends. Session chips only - no ranked impact.",
      40, 90)

    lobby_ui.drawHostSettings(rules, 40, 140)
    if widgets.button(40, h - 130, 220, 50, "HOST TABLE") then
      casual.sanitize(rules)
      startHosting()
    end

    g.setFont(screen.fonts.body)
    g.setColor(1, 0.92, 0.7)
    g.print("JOIN A TABLE", w * 0.62, 140)
    local addr = widgets.textInput("joinAddr", w * 0.62, 180, 260,
      "host IP (e.g. REDACTED_HOST)")
    if widgets.button(w * 0.62, 224, 140, 40, "JOIN", { small = true })
      and addr ~= "" then
      join(addr)
    end
    g.setFont(screen.fonts.small)
    g.setColor(1, 1, 1, 0.5)
    g.printf("Steam invites use the overlay when Steam is running; over "
      .. "LAN/direct, share your IP and the join code shows on the host "
      .. "screen.", w * 0.62, 280, w * 0.3)

  elseif mode == "hosting" or mode == "joining" then
    g.setFont(screen.fonts.body)
    g.setColor(1, 1, 1, 0.85)
    if mode == "hosting" and server then
      g.print(("Hosting on port %d  -  JOIN CODE: %s")
        :format(server.port, server.joinCode), 40, 90)
      if steam.available then
        if widgets.button(w - 260, 84, 220, 40, "INVITE FRIENDS",
          { small = true }) then
          steam.inviteFriend(0)
        end
      end
    else
      g.print("Connected. Waiting for the host to start...", 40, 90)
    end

    lobby_ui.drawPlayers(client and client.lobby, 40, 150)
    if client then
      local msg = lobby_ui.drawChat(client.chatLog, 40, h - 280, w * 0.4)
      if msg then client:chat(msg) end
    end

    if mode == "hosting" and server then
      if widgets.button(w - 260, h - 130, 220, 50, "START MATCH") then
        local ok, err = server:startMatch()
        if not ok then errorMsg = err end
      end
    end
  end

  if errorMsg then
    g.setFont(screen.fonts.body)
    g.setColor(1, 0.5, 0.4)
    g.print(errorMsg, 40, h - 180)
  end

  g.setColor(1, 1, 1, 1)
  if widgets.button(40, h - 70, 150, 44, "BACK") then
    state.cleanup()
    Gamestate.switch(require("states.menu"))
  end
  widgets.endFrame()
end

function state.cleanup()
  if client then client:destroy() client = nil end
  if server then server:destroy() server = nil end
end

function state:mousepressed(x, y, b) widgets.pressed(x, y, b) end

function state:textinput(t) widgets.textinput(t) end

function state:keypressed(key)
  if widgets.keypressed(key) then return end
  if key == "escape" then
    state.cleanup()
    Gamestate.switch(require("states.menu"))
  end
end

function state:leave() state.cleanup() end

return state
