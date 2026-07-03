--------------------------------------------------------------------------
-- src/modes/battleroyale.lua
-- "The Boneyard" - craps battle royale vs AI rollers. Pure logic, no LÖVE.
--
-- Every player has HP and rolls 2d6 each round, all dice face-up. The
-- craps loop IS the combat system:
--   * Come-out (no point armed):
--       7 / 11        -> clean hit on your chosen target for the sum
--       2 / 3 / 12    -> craps BACKFIRE: self damage (sum x crapsSelfMult)
--       anything else -> ARMS that number as your point; arming with a
--                        hard-way double also chips your target for the sum
--   * Point armed:
--       your point    -> POINT BREAK: point x pointBreakMult to your target
--       7             -> SEVEN-OUT: (7 + point) self damage, chain resets
--       other doubles -> pressure chip: sum/2 to your target
-- Chains: every hit raises your damage multiplier (+chainStep per level,
-- capped at chainMax). Only craps and seven-outs reset it.
-- Kills pay a chip bounty and heal the killer. After rakeStartRound, "The
-- Rake" bleeds every survivor harder each round so matches always end.
-- Last player standing takes the top prize split of the pot.
--
-- This is PvE-family: the human's equipped skill dice apply (hooks get a
-- shim table with rng + phase). AI rollers always use fair dice.
--------------------------------------------------------------------------

local config  = require("src.core.config")
local rngmod  = require("src.core.rng")
local economy = require("src.core.economy")
local catalog = require("src.meta.dice_catalog")
local rewards = require("src.meta.rewards")

local br = {}

local Match = {}
Match.__index = Match

local AI_NAMES = {
  "Lucky Lou", "Snake-Eyes Sal", "Bones Malone", "The Duchess",
  "Eightball Eddie", "Vera Velvet", "Two-Pip Tony", "Marrow Mae",
  "Cold Roll Cole", "Boxcar Bess",
}

--- Start a match. Debits the entry fee from the wallet.
--- opts (all optional): seed, playerCount, forceMutators = {id, id} (tests),
--- saveData (for skill dice + achievements; defaults to none).
--- Returns match, or nil + reason.
function br.newMatch(saveData, opts)
  opts = opts or {}
  local fee = config.br.entryFee
  if not economy.canAfford(fee) then
    return nil, ("entry fee is %d chips"):format(fee)
  end
  economy.debit(fee, "br_entry")

  local self = setmetatable({}, Match)
  self.saveData = saveData
  self.rng = rngmod.new(opts.seed)
  self.round = 0
  self.over = false
  self.eliminationOrder = {}   -- first entry = first player out
  self.feed = {}               -- kill-feed strings, newest last
  self.playerCount = opts.playerCount or config.br.playerCount
  self.pot = fee * self.playerCount

  -- Draw mutators.
  self.mutators = {}
  if opts.forceMutators then
    for _, id in ipairs(opts.forceMutators) do
      for _, m in ipairs(config.br.mutators) do
        if m.id == id then self.mutators[#self.mutators + 1] = m end
      end
    end
  else
    local pool = {}
    for i, m in ipairs(config.br.mutators) do pool[i] = m end
    for _ = 1, math.min(config.br.mutatorsPerMatch, #pool) do
      self.mutators[#self.mutators + 1] =
        table.remove(pool, self.rng:random(#pool))
    end
  end

  -- Merged mutator knobs with defaults.
  local knobs = {
    hpMult = 1, damageMult = 1, lifesteal = 0, chipsPerDamage = 0,
    chainGain = 1, bountyMult = 1, rakeStartDelta = 0, rakeMult = 1,
  }
  for _, m in ipairs(self.mutators) do
    for k, v in pairs(m) do
      if knobs[k] ~= nil then knobs[k] = v end
    end
  end
  self.knobs = knobs

  -- Players. Index 1 is the human.
  local hp = math.floor(config.br.startHP * knobs.hpMult)
  self.players = {}
  local names = {}
  for i, n in ipairs(AI_NAMES) do names[i] = n end
  for i = 1, self.playerCount do
    local isHuman = (i == 1)
    self.players[i] = {
      index = i,
      name = isHuman and "You" or table.remove(names, self.rng:random(#names)),
      isHuman = isHuman,
      hp = hp, maxHP = hp,
      point = nil,
      chain = 0,
      kills = 0,
      damageDealt = 0,
      bounties = 0,
      alive = true,
      target = nil,          -- player index
      lastRoll = nil,        -- { d1, d2 } for the UI
      lastHitBy = nil,       -- revenge memory for AI targeting
    }
  end

  -- Human skill dice: PvE-family mode, so equipped modifiers apply.
  self.ctx = { lossStreak = 0, rerollCharges = 0 }
  if saveData then
    self.hooks = catalog.buildHooks(saveData.equipped, self.ctx)
    for _, id in ipairs(saveData.equipped or {}) do
      local d = catalog.byId[id]
      if d and d.modifier and d.modifier.type == "rerollLowest" then
        self.ctx.rerollCharges = self.ctx.rerollCharges
          + config.modifiers.rerollLowest[d.rarity]
      end
    end
  end

  return self
end

function Match:say(line)
  self.feed[#self.feed + 1] = line
  if #self.feed > 8 then table.remove(self.feed, 1) end
end

function Match:aliveCount()
  local n = 0
  for _, p in ipairs(self.players) do
    if p.alive then n = n + 1 end
  end
  return n
end

function Match:alivePlayers()
  local out = {}
  for _, p in ipairs(self.players) do
    if p.alive then out[#out + 1] = p end
  end
  return out
end

--- Human picks a target by player index. Ignored if invalid.
function Match:setTarget(idx)
  local t = self.players[idx]
  if t and t.alive and idx ~= 1 then self.players[1].target = idx end
end

function Match:chainMult(p)
  return 1 + math.min(p.chain, config.br.chainMax) * config.br.chainStep
end

-- AI targeting: sometimes revenge, sometimes chaos, otherwise vulture the
-- weakest - with RANDOM tie-breaks. (A deterministic tie-break made every
-- AI dogpile player 1 on round one; the human melted before their second
-- roll. Spread the violence.)
local function pickAITarget(self, p)
  if p.lastHitBy and self.players[p.lastHitBy].alive
    and p.lastHitBy ~= p.index and self.rng:chance(0.35) then
    return p.lastHitBy
  end
  local others = {}
  for _, q in ipairs(self.players) do
    if q.alive and q.index ~= p.index then others[#others + 1] = q end
  end
  if #others == 0 then return nil end
  if self.rng:chance(0.35) then -- chaos pick keeps tables unpredictable
    return others[self.rng:random(#others)].index
  end
  local minHP = math.huge
  for _, q in ipairs(others) do minHP = math.min(minHP, q.hp) end
  local weakest = {}
  for _, q in ipairs(others) do
    if q.hp == minHP then weakest[#weakest + 1] = q end
  end
  return weakest[self.rng:random(#weakest)].index
end

-- Roll 2d6 for a player; the human's skill-dice hooks apply via a shim
-- that quacks like an engine table ({ rng, phase }).
local function rollFor(self, p)
  local dice = { self.rng:rollDie(6), self.rng:rollDie(6) }
  if p.isHuman and self.hooks and self.hooks.applyPostRoll then
    local shim = { rng = self.rng, phase = p.point and "point" or "comeout" }
    dice = self.hooks.applyPostRoll(dice, shim) or dice
  end
  return dice
end

--- Play one simultaneous round. Returns an array of event tables for the
--- UI, each { type, attacker, victim, dmg, dice, ... } (indices, not refs).
--- Types: roll, hit, backfire, armed, break, sevenout, pressure, rake,
--- kill, win.
function Match:playRound()
  if self.over then return {} end
  self.round = self.round + 1
  local K = config.br
  local events = {}
  local pendingDamage = {}   -- victimIdx -> { total, biggest, biggestFrom }

  local function queueDamage(fromIdx, toIdx, amount, kind)
    amount = math.floor(amount)
    if amount <= 0 then return 0 end
    local d = pendingDamage[toIdx]
    if not d then
      d = { total = 0, biggest = 0, biggestFrom = nil }
      pendingDamage[toIdx] = d
    end
    d.total = d.total + amount
    if fromIdx ~= toIdx and amount > d.biggest then
      d.biggest, d.biggestFrom = amount, fromIdx
    end
    if fromIdx ~= toIdx then
      local from = self.players[fromIdx]
      from.damageDealt = from.damageDealt + amount
      self.players[toIdx].lastHitBy = fromIdx
      if self.knobs.lifesteal > 0 then
        from.hp = math.min(from.maxHP,
          from.hp + math.floor(amount * self.knobs.lifesteal))
      end
    end
    return amount
  end

  -- Pick targets (AI every round; human keeps their pick, defaulting to
  -- a random living opponent).
  for _, p in ipairs(self:alivePlayers()) do
    if p.isHuman then
      if not p.target or not self.players[p.target]
        or not self.players[p.target].alive then
        local pool = {}
        for _, q in ipairs(self:alivePlayers()) do
          if q.index ~= p.index then pool[#pool + 1] = q.index end
        end
        p.target = pool[self.rng:random(#pool)]
      end
    else
      p.target = pickAITarget(self, p)
    end
  end

  -- Everyone rolls simultaneously; damage lands after all dice settle.
  for _, p in ipairs(self:alivePlayers()) do
    local dice = rollFor(self, p)
    local sum = dice[1] + dice[2]
    local isDouble = dice[1] == dice[2]
    p.lastRoll = dice
    events[#events + 1] = { type = "roll", attacker = p.index, dice = dice }

    local dmgMult = self.knobs.damageMult
    if not p.point then -- come-out
      if sum == 7 or sum == 11 then
        local dmg = queueDamage(p.index, p.target,
          sum * self:chainMult(p) * dmgMult, "natural")
        p.chain = p.chain + self.knobs.chainGain
        p.peakChain = math.max(p.peakChain or 0, p.chain)
        events[#events + 1] = { type = "hit", attacker = p.index,
          victim = p.target, dmg = dmg, natural = sum }
      elseif sum == 2 or sum == 3 or sum == 12 then
        local dmg = queueDamage(p.index, p.index,
          sum * K.crapsSelfMult * dmgMult, "backfire")
        p.chain = 0
        events[#events + 1] = { type = "backfire", attacker = p.index,
          dmg = dmg, craps = sum }
      else
        p.point = sum
        events[#events + 1] = { type = "armed", attacker = p.index, point = sum }
        if isDouble and K.hardSetChip then
          local dmg = queueDamage(p.index, p.target, sum * dmgMult, "hardset")
          events[#events + 1] = { type = "pressure", attacker = p.index,
            victim = p.target, dmg = dmg, hard = true }
        end
      end
    else -- point armed
      if sum == p.point then
        local dmg = queueDamage(p.index, p.target,
          p.point * K.pointBreakMult * self:chainMult(p) * dmgMult, "break")
        events[#events + 1] = { type = "break", attacker = p.index,
          victim = p.target, dmg = dmg, point = p.point }
        p.chain = p.chain + self.knobs.chainGain
        p.peakChain = math.max(p.peakChain or 0, p.chain)
        p.point = nil
      elseif sum == 7 then
        local dmg = queueDamage(p.index, p.index,
          (7 + p.point) * dmgMult, "sevenout")
        events[#events + 1] = { type = "sevenout", attacker = p.index,
          dmg = dmg, point = p.point }
        p.chain = 0
        p.point = nil
      elseif isDouble and K.pressureDoubles then
        local dmg = queueDamage(p.index, p.target, (sum / 2) * dmgMult, "pressure")
        events[#events + 1] = { type = "pressure", attacker = p.index,
          victim = p.target, dmg = dmg }
      end
    end
  end

  -- The Rake: unavoidable table bleed that guarantees an ending.
  local rakeStart = K.rakeStartRound + self.knobs.rakeStartDelta
  if self.round > rakeStart then
    local rake = math.floor(
      (K.rakeBase + (self.round - rakeStart - 1) * K.rakeStep)
      * self.knobs.rakeMult)
    for _, p in ipairs(self:alivePlayers()) do
      queueDamage(p.index, p.index, rake, "rake")
    end
    events[#events + 1] = { type = "rake", dmg = rake }
    self:say(("The Rake collects %d from everyone"):format(rake))
  end

  -- Apply damage, resolve deaths. Kill credit: biggest damager this round.
  local died = {}
  for idx, d in pairs(pendingDamage) do
    local p = self.players[idx]
    p.hp = math.max(0, p.hp - d.total)
    if p.alive and p.hp <= 0 then
      died[#died + 1] = { p = p, killerIdx = d.biggestFrom }
    end
  end
  -- Deterministic order when several die the same round.
  table.sort(died, function(a, b) return a.p.index > b.p.index end)
  for _, death in ipairs(died) do
    local p = death.p
    p.alive = false
    p.point = nil
    self.eliminationOrder[#self.eliminationOrder + 1] = p.index
    local killer = death.killerIdx and self.players[death.killerIdx]
    if killer and killer.alive then
      killer.kills = killer.kills + 1
      local bounty = math.floor(K.killBounty * self.knobs.bountyMult)
      killer.bounties = killer.bounties + bounty
      killer.hp = math.min(killer.maxHP,
        killer.hp + math.floor(K.killHeal * self.knobs.bountyMult))
      events[#events + 1] = { type = "kill", attacker = killer.index,
        victim = p.index, bounty = bounty }
      self:say(("%s picked off %s  (+%d)"):format(killer.name, p.name, bounty))
    else
      events[#events + 1] = { type = "kill", victim = p.index }
      self:say(("%s crapped out"):format(p.name))
    end
  end

  if self:aliveCount() <= 1 then
    self:finish()
    local winner = self:alivePlayers()[1]
    if winner then
      events[#events + 1] = { type = "win", attacker = winner.index }
    end
  end
  return events
end

--- Instantly resolve the rest of the match (used when the human is out
--- so the final standings exist). Human rolls keep applying hooks-free
--- fair dice? - human is dead, so only AI roll; safe either way.
function Match:fastForward()
  local guard = 0
  while not self.over and guard < 500 do
    self:playRound()
    guard = guard + 1
  end
end

--- Final standings: winner first, then reverse elimination order.
function Match:standings()
  local order = {}
  for _, p in ipairs(self.players) do
    if p.alive then order[#order + 1] = p.index end
  end
  for i = #self.eliminationOrder, 1, -1 do
    order[#order + 1] = self.eliminationOrder[i]
  end
  local out = {}
  for pos, idx in ipairs(order) do
    local p = self.players[idx]
    out[pos] = {
      position = pos, index = idx, name = p.name, isHuman = p.isHuman,
      kills = p.kills, damageDealt = p.damageDealt, bounties = p.bounties,
    }
  end
  return out
end

--- Settle with the wallet. Human prize = pot split by placement, plus
--- bounties, plus Blood Money chips. Only called once.
function Match:finish()
  if self.over then return self.summary end
  self.over = true

  local standings = self:standings()
  local human, humanPos
  for _, s in ipairs(standings) do
    if s.isHuman then human, humanPos = s, s.position break end
  end

  local p1 = self.players[1]
  local prize = 0
  local split = config.br.prizeSplit[humanPos]
  if split then prize = math.floor(self.pot * split) end
  local bloodMoney = math.floor(p1.damageDealt * self.knobs.chipsPerDamage)
  local total = prize + p1.bounties + bloodMoney

  if total > 0 then
    economy.credit(total, "br_winnings", true,
      ("Boneyard #%d, %d kills"):format(humanPos, p1.kills))
    if self.saveData then
      local leaderboard = require("src.meta.leaderboard")
      leaderboard.submit(self.saveData, leaderboard.BOARD_BIG_WIN, "You", total)
    end
  end

  -- Achievements (idempotent; save may be absent in bare tests).
  local toasts = {}
  if self.saveData then
    local function ach(id)
      local a = rewards.unlock(self.saveData, id)
      if a then toasts[#toasts + 1] = a end
    end
    if humanPos == 1 then ach("BR_WIN") end
    if p1.kills >= 3 then ach("BR_REAPER") end
    if (p1.peakChain or 0) >= config.br.chainMax then ach("CHAIN_MAX") end
  end

  self.summary = {
    placement = humanPos, standings = standings,
    kills = p1.kills, damageDealt = p1.damageDealt,
    prize = prize, bounties = p1.bounties, bloodMoney = bloodMoney,
    totalWon = total, rounds = self.round,
    achievements = toasts,
  }
  return self.summary
end

return br
