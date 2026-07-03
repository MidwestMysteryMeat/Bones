--------------------------------------------------------------------------
-- src/core/diceengine.lua
-- Simplified craps engine: phases, bet resolution, payouts, jackpot.
--
-- The engine is pure logic: no LÖVE, no globals, no drawing. It is the
-- single source of truth for roll outcomes in every mode. PvE skill dice
-- plug in through `ruleset.hooks`; PvP creates tables with NO hooks so
-- every player resolves against the same fair RNG.
--
-- Money contract: placeBet does NOT touch wallets - the caller debits the
-- stake when the bet is accepted. settle() then returns, per player, the
-- full amount to credit back (stake + winnings on a win, stake on a push,
-- nothing on a loss).
--------------------------------------------------------------------------

local config = require("src.core.config")
local rngmod = require("src.core.rng")

local engine = {}

local Table = {}
Table.__index = Table

--- Create a craps table.
--- seedOrRng: numeric seed, an rng instance, or nil (time-seeded).
--- ruleset (all optional):
---   limits       = { min, max }        bet limits
---   allowedBets  = { passline = true } whitelist; nil allows every bet
---   jackpot      = false               disable the progressive pool
---   jackpotPool  = number              starting pool (PvE carries it in)
---   hooks        = { applyPreRoll, applyPostRoll, modifyPayout }  PvE ONLY
function engine.newTable(seedOrRng, ruleset)
  ruleset = ruleset or {}
  local self = setmetatable({}, Table)
  if type(seedOrRng) == "table" then
    self.rng = seedOrRng
  else
    self.rng = rngmod.new(seedOrRng)
  end
  self.phase          = "comeout"
  self.point          = nil
  self.bets           = {}   -- pending bets: { playerId, betId, amount, def }
  self.rollHistory    = {}
  self.rollNumber     = 0
  self.limits         = ruleset.limits or {
    min = config.table.defaultMinBet, max = config.table.defaultMaxBet,
  }
  self.allowedBets    = ruleset.allowedBets  -- nil = all bets allowed
  self.jackpotEnabled = ruleset.jackpot ~= false
  self.jackpotPool    = ruleset.jackpotPool or config.jackpot.seedFloor
  self.boxcarStreak   = 0
  self.hooks          = ruleset.hooks or {}
  self.diceCount      = ruleset.diceCount or 2
  return self
end

--- Place a bet. Returns true, or false + reason. Caller debits the stake
--- only after this returns true.
function Table:placeBet(playerId, betId, amount)
  local def = config.betsById[betId]
  if not def then return false, "unknown bet: " .. tostring(betId) end
  if self.allowedBets and not self.allowedBets[betId] then
    return false, "bet not allowed at this table"
  end
  if def.comeoutOnly and self.phase ~= "comeout" then
    return false, "line bets only before the come-out roll"
  end
  amount = math.floor(amount or 0)
  if amount < self.limits.min then return false, "below table minimum" end
  if amount > self.limits.max then return false, "above table maximum" end
  self.bets[#self.bets + 1] = {
    playerId = playerId, betId = betId, amount = amount, def = def,
  }
  return true
end

--- Total chips a player currently has riding on the table.
function Table:playerExposure(playerId)
  local total = 0
  for _, b in ipairs(self.bets) do
    if b.playerId == playerId then total = total + b.amount end
  end
  return total
end

--- Remove (refund) all pending bets for a player, e.g. on disconnect.
--- Returns the refunded amount. In ranked PvP the server calls this with
--- refund=false so a rage-quitter forfeits everything on the felt.
function Table:foldPlayer(playerId, refund)
  local kept, refunded = {}, 0
  for _, b in ipairs(self.bets) do
    if b.playerId == playerId then
      if refund ~= false then refunded = refunded + b.amount end
    else
      kept[#kept + 1] = b
    end
  end
  self.bets = kept
  return refunded
end

--- Roll the dice, resolve every pending bet, advance the phase.
--- Returns { dice, sum, phase, prevPhase, point, resolved, jackpotHit, isDouble }.
--- `resolved` entries: { bet, status = "win"|"lose"|"push", multiplier }.
function Table:roll()
  self.rollNumber = self.rollNumber + 1

  -- PvE hook: change the number of dice before the roll (never in PvP).
  local n = self.diceCount
  if self.hooks.applyPreRoll then
    n = self.hooks.applyPreRoll(n, self) or n
  end

  local dice = {}
  for i = 1, n do dice[i] = self.rng:rollDie(6) end

  -- PvE hook: nudge faces after the roll (weighted dice, rerolls, pity).
  if self.hooks.applyPostRoll then
    dice = self.hooks.applyPostRoll(dice, self) or dice
  end

  local sum = 0
  for _, d in ipairs(dice) do sum = sum + d end
  local isDouble = (#dice == 2 and dice[1] == dice[2])

  -- Snapshot handed to bet resolvers: state AS OF this roll.
  local rollState = {
    dice = dice, sum = sum, isDouble = isDouble,
    phase = self.phase, point = self.point,
    history = self.rollHistory,
  }

  -- Resolve bets; unresolved bets stay on the felt.
  local resolvedList, keep = {}, {}
  for _, bet in ipairs(self.bets) do
    local status, multOverride = bet.def.resolve(rollState)
    if status then
      resolvedList[#resolvedList + 1] = {
        bet = bet, status = status,
        multiplier = multOverride or bet.def.payout or 1,
      }
    else
      keep[#keep + 1] = bet
    end
  end
  self.bets = keep

  -- Phase transitions.
  local prevPhase, prevPoint = self.phase, self.point
  if self.phase == "comeout" then
    if sum ~= 7 and sum ~= 11 and sum ~= 2 and sum ~= 3 and sum ~= 12 then
      self.point = sum
      self.phase = "point"
    end
  else
    if sum == self.point or sum == 7 then
      self.point = nil
      self.phase = "comeout"
    end
  end

  -- Progressive jackpot trigger: consecutive boxcars (6-6).
  local jackpotHit = false
  if #dice == 2 and dice[1] == 6 and dice[2] == 6 then
    self.boxcarStreak = self.boxcarStreak + 1
  else
    self.boxcarStreak = 0
  end
  if self.jackpotEnabled and self.boxcarStreak >= config.jackpot.triggerBoxcars then
    jackpotHit = true
    self.boxcarStreak = 0
  end

  local result = {
    dice = dice, sum = sum, isDouble = isDouble,
    phase = self.phase, prevPhase = prevPhase,
    point = self.point, prevPoint = prevPoint,
    resolved = resolvedList, jackpotHit = jackpotHit,
    rollNumber = self.rollNumber,
  }
  self.rollHistory[#self.rollHistory + 1] = result
  self.lastRoll = result
  return result
end

--- Settle the last roll. Returns:
---   payouts             playerId -> chips to credit (stake already spent)
---   houseTake           chips the house collected from losing bets
---   jackpotContribution rake skimmed off losing bets into the pool
---   jackpotPayout       full pool if the jackpot hit this roll, else 0
---   pool                pool size after settling
--- Safe to call once per roll; repeat calls return an empty settle.
function Table:settle()
  local empty = {
    payouts = {}, houseTake = 0, jackpotContribution = 0,
    jackpotPayout = 0, pool = self.jackpotPool,
  }
  local roll = self.lastRoll
  if not roll or roll.settled then return empty end
  roll.settled = true

  local payouts, houseTake, rakeTotal = {}, 0, 0
  for _, r in ipairs(roll.resolved) do
    local pid = r.bet.playerId
    payouts[pid] = payouts[pid] or 0
    if r.status == "win" then
      -- Winnings are floored to whole chips (matters for 7:6 place bets).
      local winnings = math.floor(r.bet.amount * r.multiplier + 1e-9)
      if self.hooks.modifyPayout then
        winnings = self.hooks.modifyPayout(r.bet, winnings) or winnings
      end
      payouts[pid] = payouts[pid] + r.bet.amount + winnings
    elseif r.status == "push" then
      payouts[pid] = payouts[pid] + r.bet.amount
    else -- lose: rake feeds the jackpot, the rest is the house's
      local rake = 0
      if self.jackpotEnabled then
        rake = math.floor(r.bet.amount * config.jackpot.rakePct + 0.5)
      end
      rakeTotal = rakeTotal + rake
      houseTake = houseTake + (r.bet.amount - rake)
    end
  end

  self.jackpotPool = self.jackpotPool + rakeTotal
  local jackpotPayout = 0
  if roll.jackpotHit then
    jackpotPayout = self.jackpotPool
    self.jackpotPool = config.jackpot.seedFloor
  end

  return {
    payouts = payouts, houseTake = houseTake,
    jackpotContribution = rakeTotal,
    jackpotPayout = jackpotPayout, pool = self.jackpotPool,
  }
end

--- Convenience: roll + settle in one step (PvE uses this).
function Table:rollAndSettle()
  local roll = self:roll()
  local settle = self:settle()
  return roll, settle
end

return engine
