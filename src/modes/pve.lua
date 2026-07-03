--------------------------------------------------------------------------
-- src/modes/pve.lua
-- Solo Run: play against the AI House. Roguelike-ish structure - stake a
-- bankroll from your wallet, climb escalating tiers by growing it, bust
-- and the run ends (you keep a cut of your peak profit as meta chips).
-- This is the ONLY mode where skill-modifier dice touch the RNG.
--------------------------------------------------------------------------

local config   = require("src.core.config")
local engine   = require("src.core.diceengine")
local economy  = require("src.core.economy")
local catalog  = require("src.meta.dice_catalog")
local unlocks  = require("src.meta.unlocks")
local rewards  = require("src.meta.rewards")

local pve = {}

local Run = {}
Run.__index = Run

local PLAYER = "player"

-- House personality -----------------------------------------------------------

local houseLines = {
  greeting = {
    "The House always wins. Prove me wrong.",
    "Fresh bones on the felt. Let's see what you've got.",
    "Table's open. Your funeral.",
  },
  playerLoses = {
    "Ha! The felt eats another one.",
    "Seven out. Music to my ears.",
    "Your chips look better on my side.",
    "That's the sound of the House winning.",
  },
  playerWinsBig = {
    "...Well rolled. I'll allow it.",
    "Hm. Respect. Don't get used to it.",
    "Take it. You earned that one.",
  },
  playerWinsSmall = {
    "Pocket change.",
    "Enjoy it while it lasts.",
    "I've lost bigger under the couch.",
  },
  tierUp = {
    "Moving up? Bigger stakes, bigger falls.",
    "Welcome to my %s. Mind the minimums.",
    "You climb fast. They always do, right before the drop.",
  },
  jackpot = {
    "IMPOSSIBLE. Count it and get out of my sight.",
  },
}

local function pickLine(rng, category, ...)
  local t = houseLines[category]
  local line = t[rng:random(#t)]
  if select("#", ...) > 0 then line = line:format(...) end
  return line
end

-- Run --------------------------------------------------------------------------

--- Start a new solo run. Debits the bankroll stake from the wallet.
--- Returns the run, or nil + reason if the player can't afford the stake.
function pve.newRun(saveData, seed)
  local stake = config.economy.pveRunBankroll
  if not economy.canAfford(stake) then
    return nil, ("need %d chips to stake a run"):format(stake)
  end
  economy.debit(stake, "pve_run_stake")

  local self = setmetatable({}, Run)
  self.saveData  = saveData
  self.stake     = stake
  self.bankroll  = stake
  self.peak      = stake
  self.tierIndex = 1
  self.winStreak = 0
  self.rolls     = 0
  self.over      = false
  self.messages  = {}
  self.biggestWin = { amount = 0, label = "" }

  -- Shared context the skill-dice hooks read/write (see dice_catalog.lua).
  self.ctx = { lossStreak = 0, rerollCharges = 0 }
  self:restockCharges()

  local tier = self:tier()
  self.table = engine.newTable(seed, {
    limits = { min = tier.minBet, max = tier.maxBet },
    jackpotPool = economy.getJackpotPool(), -- PvE pool persists across runs
    hooks = catalog.buildHooks(saveData.equipped, self.ctx),
  })

  self:say(pickLine(self.table.rng, "greeting"))
  saveData.runsPlayed = (saveData.runsPlayed or 0) + 1
  return self
end

function Run:tier() return config.pve.tiers[self.tierIndex] end

function Run:say(line)
  self.messages[#self.messages + 1] = line
  if #self.messages > 6 then table.remove(self.messages, 1) end
end

--- Restock "Reroll Lowest" charges: sum across equipped dice, per tier.
function Run:restockCharges()
  local charges = 0
  for _, id in ipairs(self.saveData.equipped) do
    local d = catalog.byId[id]
    if d and d.modifier and d.modifier.type == "rerollLowest" then
      charges = charges + config.modifiers.rerollLowest[d.rarity]
    end
  end
  self.ctx.rerollCharges = charges
end

--- Place a bet from the run bankroll. Returns ok, reason.
function Run:placeBet(betId, amount)
  if self.over then return false, "run is over" end
  if amount > self.bankroll then return false, "not enough bankroll" end
  local ok, reason = self.table:placeBet(PLAYER, betId, amount)
  if not ok then return false, reason end
  self.bankroll = self.bankroll - amount
  return true
end

--- Roll and settle one throw. Returns roll, events where events =
--- { net, payout, streakBonus, jackpotPayout, tierAdvanced, bust,
---   achievements = {..}, unlockedRarities = {..}, houseLine }
function Run:roll()
  if self.over then return nil, { bust = true } end
  self.rolls = self.rolls + 1

  local roll, settle = self.table:rollAndSettle()
  local payout = settle.payouts[PLAYER] or 0

  -- Chips the player had riding on bets that resolved this roll.
  local resolvedStake = 0
  for _, r in ipairs(roll.resolved) do
    if r.bet.playerId == PLAYER then resolvedStake = resolvedStake + r.bet.amount end
  end
  local net = payout - resolvedStake

  local events = { net = net, payout = payout, achievements = {}, streakBonus = 0 }
  local ach = function(id)
    local a = rewards.unlock(self.saveData, id)
    if a then events.achievements[#events.achievements + 1] = a end
  end
  ach("FIRST_ROLL")

  self.bankroll = self.bankroll + payout

  -- Jackpot: the PvE pool lives in the persistent economy and pays into
  -- the run bankroll (winning it should feel like winning the run).
  if settle.jackpotPayout > 0 then
    self.bankroll = self.bankroll + settle.jackpotPayout
    events.jackpotPayout = settle.jackpotPayout
    ach("FIRST_JACKPOT")
    self:say(pickLine(self.table.rng, "jackpot"))
  end
  economy.setJackpotPool(self.table.jackpotPool)

  -- Streak bookkeeping (fuels the streak riser SFX + pity dice).
  if resolvedStake > 0 then
    if net > 0 then
      self.winStreak = self.winStreak + 1
      self.ctx.lossStreak = 0
      events.streakBonus = rewards.streakBonus(self.winStreak)
      self.bankroll = self.bankroll + events.streakBonus
      -- Fever chain: consecutive winning rolls multiply the NEXT wins.
      -- streak 2 pays +25%, 3 +50%... capped by config.fever.maxSteps.
      local feverSteps = math.min(self.winStreak - 1, config.fever.maxSteps)
      if feverSteps > 0 then
        events.feverBonus = math.floor(net * feverSteps * config.fever.stepPct)
        events.feverPct = feverSteps * config.fever.stepPct * 100
        self.bankroll = self.bankroll + events.feverBonus
        if feverSteps >= config.fever.maxSteps then ach("FEVER") end
      end
      if self.winStreak >= 5 then ach("STREAK_5") end
      if self.winStreak > (self.saveData.winStreakBest or 0) then
        self.saveData.winStreakBest = self.winStreak
      end
      if net >= 1000 then ach("BIG_WIN") end
      for _, a in ipairs(rewards.unlockRarityWins(self.saveData, self.saveData.equipped)) do
        events.achievements[#events.achievements + 1] = a
      end
      if net > self.biggestWin.amount then
        local label = roll.resolved[1] and roll.resolved[1].bet.def.label or "a roll"
        self.biggestWin = {
          amount = net,
          label = ("%s on %s"):format(tostring(net), label),
        }
      end
      self:say(pickLine(self.table.rng,
        net >= self:tier().minBet * 10 and "playerWinsBig" or "playerWinsSmall"))
    elseif net < 0 then
      self.winStreak = 0
      self.ctx.lossStreak = self.ctx.lossStreak + 1
      self:say(pickLine(self.table.rng, "playerLoses"))
    end
  end

  if self.bankroll > self.peak then self.peak = self.bankroll end
  self.wasNearBust = self.wasNearBust
    or (self.bankroll > 0 and self.bankroll < self:tier().target * 0.1)

  -- Tier advancement: grow the bankroll past the target.
  if self.bankroll >= self:tier().target and self.tierIndex < #config.pve.tiers then
    self.tierIndex = self.tierIndex + 1
    local tier = self:tier()
    self.table.limits = { min = tier.minBet, max = tier.maxBet }
    self:restockCharges()
    events.tierAdvanced = self.tierIndex
    if self.wasNearBust then ach("COMEBACK") end
    self.wasNearBust = false
    if self.tierIndex >= 10 then ach("TIER_10") end
    self:say(pickLine(self.table.rng, "tierUp", tier.name))
  end

  -- Bust: can't cover the table minimum and nothing left on the felt.
  if self.bankroll < self.table.limits.min
    and self.table:playerExposure(PLAYER) == 0 then
    events.bust = true
    self:finish(true)
  end

  events.houseLine = self.messages[#self.messages]
  return roll, events
end

--- Voluntary cash-out between rolls (banks the whole bankroll).
function Run:cashOut()
  if self.over then return end
  return self:finish(false)
end

--- Ends the run and settles with the persistent wallet.
--- Bust: keep bustMetaCut of (peak - stake) as meta currency.
--- Cash out: bank the entire remaining bankroll.
function Run:finish(bust)
  if self.over then return self.summary end
  self.over = true

  local banked
  if bust then
    banked = math.floor(math.max(0, self.peak - self.stake)
      * config.economy.bustMetaCut)
  else
    banked = self.bankroll
  end
  local profit = math.max(0, banked - (bust and 0 or self.stake))
  if banked > 0 then
    -- Only the profit portion counts as "winnings" for unlock gating.
    economy.credit(banked - profit, "pve_run_return")
    economy.credit(profit, "pve_run_winnings", true, self.biggestWin.label)
  end

  local newlyUnlocked = unlocks.recordTier(self.saveData, self.tierIndex)

  -- Solo wins feed the local big-win leaderboard too (ranked submits its
  -- own on match end); without this the board stays empty for solo players.
  if self.biggestWin.amount > 0 then
    local leaderboard = require("src.meta.leaderboard")
    leaderboard.submit(self.saveData, leaderboard.BOARD_BIG_WIN, "You",
      self.biggestWin.amount)
  end

  self.summary = {
    bust = bust,
    tierReached = self.tierIndex,
    tierName = self:tier().name,
    rolls = self.rolls,
    peak = self.peak,
    banked = banked,
    biggestWin = self.biggestWin,
    unlockedRarities = newlyUnlocked,
  }
  return self.summary
end

-- Near-miss detection for the slow-mo hook (used by the PvE state to
-- choreograph the reveal). A roll is a near-miss when the point was on and
-- the sum landed one pip from the point (so close!) or one pip from a
-- seven-out with real chips exposed.
function pve.isNearMiss(roll, exposure, tableMin)
  if roll.prevPhase ~= "point" or not roll.prevPoint then return false end
  local big = exposure >= (tableMin * 3)
  if math.abs(roll.sum - roll.prevPoint) == 1 then return true end
  if big and (roll.sum == 6 or roll.sum == 8) and roll.prevPoint ~= roll.sum then
    return true -- one pip from the seven with a loaded felt
  end
  return false
end

return pve
