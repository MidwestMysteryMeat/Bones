--------------------------------------------------------------------------
-- src/net/client.lua
-- sock.lua client: keeps a local mirror of the authoritative match state
-- and verifies every broadcast roll against its seed (fair-dice check).
-- UI states subscribe through the callbacks table.
--------------------------------------------------------------------------

local config   = require("src.core.config")
local protocol = require("src.net.protocol")
local pvp      = require("src.modes.pvp")
local PKT = protocol.PKT

local netclient = {}

local Client = {}
Client.__index = Client

--- Connect to a host. callbacks (all optional):
---   onLobby(lobby), onStart(data), onBetsOpen(data), onBetAccepted(data),
---   onRoll(roll), onSettle(data), onWallet(data), onChat(msg),
---   onPlayerLeft(data), onJackpot(data), onMatchEnd(data), onError(msg)
function netclient.new(host, port, playerName, callbacks)
  local sock = require("lib.sock")
  local self = setmetatable({}, Client)
  self.cb = callbacks or {}
  self.name = playerName or "Player"

  self.lobby = nil       -- last LOBBY_STATE snapshot
  self.myId = nil
  self.myChips = 0
  self.wallets = {}      -- playerId -> chips
  self.lastRoll = nil    -- includes .verified flag
  self.chatLog = {}
  self.betClock = 0
  self.round = 0
  self.state = "connecting"

  self.sock = sock.newClient(host, port or config.net.defaultPort)
  protocol.setupSerialization(self.sock)
  self:installHandlers()
  self.sock:connect()
  return self
end

local function fire(self, name, ...)
  if self.cb[name] then self.cb[name](...) end
end

function Client:installHandlers()
  local s = self.sock

  s:on("connect", function()
    self.state = "lobby"
    s:send(PKT.JOIN, { name = self.name })
  end)

  s:on("disconnect", function()
    self.state = "disconnected"
    fire(self, "onError", "disconnected from host")
  end)

  s:on(PKT.LOBBY_STATE, function(data)
    self.lobby = data
    fire(self, "onLobby", data)
  end)

  s:on(PKT.SYNC_WALLET, function(data)
    if data.you then self.myId = data.playerId end
    self.wallets[data.playerId] = data.chips
    if data.playerId == self.myId then self.myChips = data.chips end
    fire(self, "onWallet", data)
  end)

  s:on(PKT.START, function(data)
    self.state = "playing"
    fire(self, "onStart", data)
  end)

  s:on(PKT.BETS_OPEN, function(data)
    self.betClock = data.lockIn
    self.round = data.round
    fire(self, "onBetsOpen", data)
  end)

  s:on(PKT.BET_ACCEPTED, function(data)
    self.wallets[data.playerId] = data.chips
    if data.playerId == self.myId then self.myChips = data.chips end
    fire(self, "onBetAccepted", data)
  end)

  s:on(PKT.ROLL_RESULT, function(data)
    -- Fair-dice guarantee: re-derive the roll from the broadcast seed.
    -- A mismatch means the host is lying about its dice.
    data.verified = pvp.verifyRoll(data.seed, data.dice)
    if not data.verified then
      fire(self, "onError", "ROLL FAILED VERIFICATION - host may be cheating")
    end
    self.lastRoll = data
    fire(self, "onRoll", data)
  end)

  s:on(PKT.SETTLE, function(data) fire(self, "onSettle", data) end)

  s:on(PKT.JACKPOT_HIT, function(data) fire(self, "onJackpot", data) end)

  s:on(PKT.CHAT, function(data)
    self.chatLog[#self.chatLog + 1] = data
    if #self.chatLog > 30 then table.remove(self.chatLog, 1) end
    fire(self, "onChat", data)
  end)

  s:on(PKT.PLAYER_LEFT, function(data) fire(self, "onPlayerLeft", data) end)

  s:on(PKT.MATCH_END, function(data)
    self.state = "ended"
    fire(self, "onMatchEnd", data)
  end)

  s:on(PKT.ERROR, function(data)
    fire(self, "onError", data and data.message or "server error")
  end)
end

-- Intents (server validates everything) --------------------------------------

function Client:placeBet(betId, amount)
  self.sock:send(PKT.PLACE_BET, { betId = betId, amount = amount })
end

function Client:chat(text)
  self.sock:send(PKT.CHAT, { text = text })
end

function Client:update(dt)
  self.sock:update()
  if self.betClock > 0 then self.betClock = math.max(0, self.betClock - dt) end
end

function Client:destroy()
  if self.sock then self.sock:disconnectNow() end
end

return netclient
