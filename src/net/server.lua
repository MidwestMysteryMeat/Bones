--------------------------------------------------------------------------
-- src/net/server.lua
-- Authoritative host logic for PvP (ranked) and Casual custom matches.
-- Runs inside the hosting player's process today ("host-authoritative"),
-- but touches no love.graphics and takes all input via packets, so it can
-- be lifted into a dedicated headless process unchanged.
--
-- Authority rules:
--   * Clients only ever send INTENT (PLACE_BET, CHAT). The server
--     validates against wallets + table limits and echoes authoritative
--     state; illegal bets are rejected with ERROR.
--   * The server generates a fresh seed per roll and broadcasts
--     (seed, dice) so every client can re-derive and verify the roll.
--   * Fixed-step tick; deltas after the initial LOBBY_STATE snapshot.
--------------------------------------------------------------------------

local config   = require("src.core.config")
local engine   = require("src.core.diceengine")
local rngmod   = require("src.core.rng")
local casual   = require("src.modes.casual")
local protocol = require("src.net.protocol")
local PKT = protocol.PKT

local netserver = {}

local Server = {}
Server.__index = Server

--- opts = { port, mode = "ranked"|"casual", rules (casual only), maxPlayers }
function netserver.new(opts)
  local sock = require("lib.sock") -- lazy: needs lua-enet (present in LÖVE)
  opts = opts or {}
  local self = setmetatable({}, Server)
  self.mode = opts.mode or "casual"
  self.rules = casual.sanitize(opts.rules or casual.defaultRules())
  self.maxPlayers = opts.maxPlayers or config.ranked.maxPlayers
  self.port = opts.port or config.net.defaultPort

  self.sock = sock.newServer("*", self.port, self.maxPlayers)
  protocol.setupSerialization(self.sock)

  self.players = {}        -- playerId -> { id, name, chips, client, connected, netStart }
  self.playerOrder = {}    -- join order, for standings ties
  self.nextId = 1
  self.state = "lobby"     -- lobby -> betting -> rolling -> ended
  self.round = 0
  self.betClock = 0
  self.tickAccum = 0
  self.masterRng = rngmod.new()  -- seeds the per-roll RNGs
  self.joinCode = casual.makeJoinCode(self.port + os.time())
  self.table = nil

  self:installHandlers()
  print(("[server] %s table on port %d, join code %s")
    :format(self.mode, self.port, self.joinCode))
  return self
end

function Server:broadcast(pkt, data)
  self.sock:sendToAll(pkt, data)
end

function Server:playerFor(client)
  for _, p in pairs(self.players) do
    if p.client == client then return p end
  end
end

function Server:lobbySnapshot()
  local list = {}
  for _, id in ipairs(self.playerOrder) do
    local p = self.players[id]
    if p and p.connected then
      list[#list + 1] = { id = p.id, name = p.name, chips = p.chips }
    end
  end
  return { players = list, rules = self.rules, joinCode = self.joinCode,
    mode = self.mode }
end

function Server:installHandlers()
  self.sock:on("connect", function(_, client)
    -- Wait for JOIN before creating the player (carries the name).
  end)

  self.sock:on(PKT.JOIN, function(data, client)
    if self.state ~= "lobby" then
      client:send(PKT.ERROR, { message = "match already running" })
      return
    end
    local startChips = self.mode == "ranked"
      and config.ranked.ante or self.rules.startChips
    local p = {
      id = "p" .. self.nextId,
      name = tostring(data and data.name or ("Player " .. self.nextId)):sub(1, 16),
      chips = startChips,
      client = client, connected = true, netStart = startChips,
    }
    self.nextId = self.nextId + 1
    self.players[p.id] = p
    self.playerOrder[#self.playerOrder + 1] = p.id
    client:send(PKT.LOBBY_STATE, self:lobbySnapshot())
    client:send(PKT.SYNC_WALLET, { playerId = p.id, chips = p.chips, you = true })
    self:broadcast(PKT.LOBBY_STATE, self:lobbySnapshot())
  end)

  self.sock:on(PKT.PLACE_BET, function(data, client)
    local p = self:playerFor(client)
    if not p then return end
    if self.state ~= "betting" then
      client:send(PKT.ERROR, { message = "bets are locked" })
      return
    end
    local amount = math.floor(tonumber(data and data.amount) or 0)
    local betId = data and data.betId
    if amount <= 0 or amount > p.chips then
      client:send(PKT.ERROR, { message = "can't cover that bet" })
      return
    end
    local ok, reason = self.table:placeBet(p.id, betId, amount)
    if not ok then
      client:send(PKT.ERROR, { message = reason })
      return
    end
    p.chips = p.chips - amount
    self:broadcast(PKT.BET_ACCEPTED,
      { playerId = p.id, betId = betId, amount = amount, chips = p.chips })
  end)

  self.sock:on(PKT.CHAT, function(data, client)
    local p = self:playerFor(client)
    if not p or type(data) ~= "table" then return end
    self:broadcast(PKT.CHAT,
      { name = p.name, text = tostring(data.text or ""):sub(1, 120) })
  end)

  self.sock:on("disconnect", function(_, client)
    local p = self:playerFor(client)
    if not p then return end
    p.connected = false
    if self.table then
      -- Anti-grief: ranked quitters forfeit chips on the felt; casual
      -- players get them back into their (session) stack for standings.
      local refund = self.table:foldPlayer(p.id, self.mode ~= "ranked")
      p.chips = p.chips + refund
    end
    self:broadcast(PKT.PLAYER_LEFT,
      { playerId = p.id, name = p.name, forfeited = self.mode == "ranked" })
    self:broadcast(PKT.LOBBY_STATE, self:lobbySnapshot())
  end)
end

--- Host presses Start.
function Server:startMatch()
  if self.state ~= "lobby" then return false, "already started" end
  local count = 0
  for _, p in pairs(self.players) do
    if p.connected then count = count + 1 end
  end
  if count < 1 then return false, "no players" end
  -- NOTE: ranked would demand config.ranked.minPlayers; the host UI
  -- enforces that so a solo dev instance can still smoke-test with 1.

  local ruleset = self.mode == "ranked"
    and require("src.modes.pvp").ruleset()
    or casual.toRuleset(self.rules)
  self.table = engine.newTable(self.masterRng:random(1, 2000000000), ruleset)

  self.state = "betting"
  self.round = 1
  self.betClock = config.table.betLockCountdown
  self:broadcast(PKT.START, { rules = self.rules, mode = self.mode })
  self:broadcast(PKT.BETS_OPEN, { lockIn = self.betClock, round = self.round })
  return true
end

--- One authoritative roll: fresh verifiable seed -> engine -> broadcast.
function Server:doRoll()
  -- Per-roll seed so clients can verify: dice == rng.new(seed):rollDie()x2.
  local seed = self.masterRng:random(1, 2000000000)
  self.table.rng = rngmod.new(seed)

  local roll = self.table:roll()
  local settle = self.table:settle()

  self:broadcast(PKT.ROLL_RESULT, {
    seed = seed, dice = roll.dice, sum = roll.sum,
    phase = roll.phase, point = roll.point, rollNumber = roll.rollNumber,
  })

  for pid, amount in pairs(settle.payouts) do
    local p = self.players[pid]
    if p then
      p.chips = p.chips + amount
      self:broadcast(PKT.SYNC_WALLET, { playerId = pid, chips = p.chips })
    end
  end
  if settle.jackpotPayout > 0 then
    self:broadcast(PKT.JACKPOT_HIT, { amount = settle.jackpotPayout })
    -- Jackpot splits between everyone with a live bet this roll (house
    -- rule: shared pots keep the table friendly). TODO(design): winner-
    -- takes-all option in casual rules.
    local live = {}
    for _, r in ipairs(roll.resolved) do live[r.bet.playerId] = true end
    local n = 0
    for _ in pairs(live) do n = n + 1 end
    if n > 0 then
      local share = math.floor(settle.jackpotPayout / n)
      for pid in pairs(live) do
        local p = self.players[pid]
        if p then
          p.chips = p.chips + share
          self:broadcast(PKT.SYNC_WALLET, { playerId = pid, chips = p.chips })
        end
      end
    end
  end
  self:broadcast(PKT.SETTLE, {
    payouts = settle.payouts, pool = settle.pool,
    jackpotPayout = settle.jackpotPayout, round = self.round,
  })

  -- A "round" completes whenever the table returns to the come-out.
  if roll.phase == "comeout" then
    self.round = self.round + 1
    local maxRounds = self.mode == "casual" and self.rules.rounds or 10
    if self.round > maxRounds then
      self:endMatch()
      return
    end
  end
  self.state = "betting"
  self.betClock = config.table.betLockCountdown
  self:broadcast(PKT.BETS_OPEN, { lockIn = self.betClock, round = self.round })
end

function Server:endMatch()
  self.state = "ended"
  local standings = {}
  for _, id in ipairs(self.playerOrder) do
    local p = self.players[id]
    if p then
      standings[#standings + 1] = {
        id = p.id, name = p.name, chips = p.chips,
        netChips = p.chips - p.netStart,
        disconnected = not p.connected,
      }
    end
  end
  table.sort(standings, function(a, b)
    -- Disconnected players always finish below connected ones.
    if a.disconnected ~= b.disconnected then return b.disconnected end
    return a.chips > b.chips
  end)
  for i, s in ipairs(standings) do s.position = i end
  self:broadcast(PKT.MATCH_END, { standings = standings })
end

--- Call every frame from the host process. Fixed-step ticks the betting
--- countdown so late PLACE_BETs are rejected cleanly once it hits zero.
function Server:update(dt)
  self.sock:update()
  self.tickAccum = self.tickAccum + dt
  local step = 1 / config.net.tickRate
  while self.tickAccum >= step do
    self.tickAccum = self.tickAccum - step
    if self.state == "betting" then
      self.betClock = self.betClock - step
      if self.betClock <= 0 then
        self.state = "rolling"
        self:doRoll()
      end
    end
  end
end

function Server:destroy()
  if self.sock then self.sock:destroy() end
end

return netserver
