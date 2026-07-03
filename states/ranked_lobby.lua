--------------------------------------------------------------------------
-- states/ranked_lobby.lua
-- Ranked tables: quickplay-ish host/join with fixed fair rules and an
-- ante debited from the persistent wallet. Host-authoritative today;
-- protocol.lua lets a dedicated server drop in later.
--------------------------------------------------------------------------

local Gamestate = require("lib.hump.gamestate")
local config    = require("src.core.config")
local save      = require("src.core.save")
local economy   = require("src.core.economy")
local pvp       = require("src.modes.pvp")
local netserver = require("src.net.server")
local netclient = require("src.net.client")
local screen    = require("src.ui.screen")
local widgets   = require("src.ui.widgets")
local lobby_ui  = require("src.ui.lobby_ui")
local steam     = require("src.steam.steam")

local state = {}

local mode = "pick"
local server, client
local errorMsg
local anteDebited = false

function state:enter()
  mode = "pick"
  server, client, errorMsg = nil, nil, nil
  anteDebited = false
  steam.presence("Ranked Lobby")
end

local function payAnte()
  if anteDebited then return true end
  local ok, reason = pvp.canQueue(save.data)
  if not ok then
    errorMsg = reason
    return false
  end
  economy.debit(config.ranked.ante, "ranked_ante")
  save.autosave("ranked_ante")
  anteDebited = true
  return true
end

local function host()
  if not payAnte() then return end
  local ok, err = pcall(function()
    server = netserver.new({ mode = "ranked" })
    client = netclient.new("localhost", server.port, "Host", {})
  end)
  if ok then mode = "hosting"
  else
    errorMsg = tostring(err)
    server, client = nil, nil
  end
  -- TODO(matchmaking): lobby-list quickplay. With Steam: matchmaking
  -- lobby search filtered on a "bones_ranked" tag. Without: a tiny HTTP
  -- master server, or direct IP as we do now.
end

local function join(address)
  if not payAnte() then return end
  local ok, err = pcall(function()
    client = netclient.new(address, config.net.defaultPort, "Challenger", {})
  end)
  if ok then mode = "joining" else errorMsg = tostring(err) end
end

function state:update(dt)
  widgets.beginFrame()
  if server then server:update(dt) end
  if client then
    client:update(dt)
    if client.state == "playing" then
      Gamestate.switch(require("states.match"),
        { client = client, server = server, mode = "ranked" })
      server, client = nil, nil
      return
    end
  end
end

function state:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  screen.drawFelt()
  screen.header("RANKED")

  g.setFont(screen.fonts.body)
  g.setColor(1, 1, 1, 0.85)
  g.print(("Rating: %d      Ante: %d chips      Wallet: %d")
    :format(save.data.rating or config.ranked.baseRating,
      config.ranked.ante, economy.getWallet()), 40, 90)
  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.6)
  g.printf("Fair dice only: the table rolls on a broadcast seed every "
    .. "client verifies. Skill dice never apply here. Disconnecting "
    .. "forfeits your bets and costs extra rating.", 40, 120, w * 0.55)

  if mode == "pick" then
    if widgets.button(40, 200, 260, 52, "HOST RANKED TABLE") then host() end
    local addr = widgets.textInput("rankedAddr", 40, 280, 260, "host IP to join")
    if widgets.button(40, 324, 140, 40, "JOIN", { small = true })
      and addr ~= "" then
      join(addr)
    end
  else
    if mode == "hosting" and server then
      g.setFont(screen.fonts.body)
      g.setColor(1, 1, 1, 0.85)
      g.print(("Hosting on port %d  -  JOIN CODE: %s")
        :format(server.port, server.joinCode), 40, 200)
    end
    lobby_ui.drawPlayers(client and client.lobby, 40, 250)
    if mode == "hosting" and server then
      -- Enforce the ranked minimum here (the server allows 1 for dev).
      local n = client and client.lobby and #client.lobby.players or 0
      local enough = n >= config.ranked.minPlayers
      if widgets.button(w - 260, h - 130, 220, 50, "START MATCH",
        { disabled = not enough }) and enough then
        local ok, err = server:startMatch()
        if not ok then errorMsg = err end
      end
      if not enough then
        g.setFont(screen.fonts.small)
        g.setColor(1, 1, 1, 0.5)
        g.print(("need %d+ players"):format(config.ranked.minPlayers),
          w - 255, h - 75)
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
    state.cleanup(true)
    Gamestate.switch(require("states.menu"))
  end
  widgets.endFrame()
end

function state.cleanup(refundAnte)
  if client then client:destroy() client = nil end
  if server then server:destroy() server = nil end
  -- Backing out of the lobby BEFORE a match starts refunds the ante.
  if refundAnte and anteDebited then
    economy.credit(config.ranked.ante, "ranked_ante_refund")
    anteDebited = false
    save.autosave("ranked_ante_refund")
  end
end

function state:mousepressed(x, y, b) widgets.pressed(x, y, b) end
function state:textinput(t) widgets.textinput(t) end

function state:keypressed(key)
  if widgets.keypressed(key) then return end
  if key == "escape" then
    state.cleanup(true)
    Gamestate.switch(require("states.menu"))
  end
end

function state:leave() end -- match switch or explicit cleanup handles teardown

return state
