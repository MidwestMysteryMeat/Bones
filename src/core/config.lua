--------------------------------------------------------------------------
-- src/core/config.lua
-- Every tunable knob in the game lives here. No magic numbers in logic.
-- This file must stay loadable under plain Lua (no LÖVE calls) so the
-- headless engine tests can require it.
--------------------------------------------------------------------------

local config = {}

-- Identity ----------------------------------------------------------------
config.TITLE        = "Bones"   -- working title; rename the game here only
config.IDENTITY     = "bones"   -- love.filesystem save directory name
config.VERSION      = "0.1.0"
config.SAVE_VERSION = 1         -- bump when the save format changes

-- Window / display ----------------------------------------------------------
config.window = {
  width = 1280, height = 720,
  minWidth = 960, minHeight = 540,
  vsync = 1,
}

-- Table rules ---------------------------------------------------------------
config.table = {
  defaultMinBet     = 5,
  defaultMaxBet     = 500,
  chipDenominations = { 5, 25, 100, 500 },
  betLockCountdown  = 3.0,  -- seconds bets stay open before a networked roll
}

-- Economy ---------------------------------------------------------------------
config.economy = {
  startingWallet  = 500,   -- chips on a brand new save
  pveRunBankroll  = 200,   -- chips staked from the wallet into a new solo run
  bustMetaCut     = 0.25,  -- on bust: keep this cut of (peak bankroll - stake)
  casualStartChips = 1000, -- session-only chips in casual (never touch wallet)
}

-- Progressive jackpot ---------------------------------------------------------
config.jackpot = {
  rakePct         = 0.02,   -- share of each LOSING bet that feeds the pool
  seedFloor       = 5000,   -- pool resets to this after a hit
  pveSeedStart    = 12500,  -- PvE local pool starts high so it feels alive
  -- Trigger: this many consecutive 6-6 (hard twelve / "boxcars") rolls.
  -- P(6-6) = 1/36, so 2 in a row = 1/1296 rolls -> rare but reachable.
  triggerBoxcars  = 2,
}

-- PvE run structure -------------------------------------------------------------
-- Advance a tier by growing the run bankroll past `target`. House table
-- limits scale up so stakes escalate. Bust (bankroll < table min) ends the run.
config.pve = {
  tiers = {
    { name = "Back Alley",      target =   400, minBet =   5, maxBet =   100 },
    { name = "Corner Bar",      target =   800, minBet =  10, maxBet =   200 },
    { name = "Riverboat",       target =  1600, minBet =  25, maxBet =   400 },
    { name = "Downtown Floor",  target =  3200, minBet =  50, maxBet =   800 },
    { name = "High Roller Den", target =  6400, minBet = 100, maxBet =  1600 },
    { name = "Velvet Room",     target = 12800, minBet = 200, maxBet =  3200 },
    { name = "Penthouse",       target = 25600, minBet = 400, maxBet =  6400 },
    { name = "The Vault",       target = 51200, minBet = 800, maxBet = 12800 },
    { name = "Bone Palace",     target = 102400, minBet = 1600, maxBet = 25600 },
    { name = "House of Bones",  target = 204800, minBet = 3200, maxBet = 51200 },
  },
  loadoutSize = 3,  -- max equipped dice
}

-- Skill-modifier strengths per rarity (PvE ONLY) --------------------------------
-- Each value is the "power" knob the modifier implementations read.
config.modifiers = {
  weighted     = { common = 0.05, uncommon = 0.09, rare = 0.14, epic = 0.20, legendary = 0.28 }, -- chance per die to snap to the chosen face
  rerollLowest = { common = 1,    uncommon = 2,    rare = 3,    epic = 4,    legendary = 6    }, -- charges per PvE round
  loaded7      = { common = 0.04, uncommon = 0.07, rare = 0.11, epic = 0.16, legendary = 0.22 }, -- extra chance of a 7 on come-out
  pointGuard   = { common = 0.06, uncommon = 0.10, rare = 0.15, epic = 0.21, legendary = 0.30 }, -- chance to reroll a seven-out
  goldenTouch  = { common = 0.05, uncommon = 0.10, rare = 0.15, epic = 0.25, legendary = 0.40 }, -- bonus multiplier on Pass Line wins
  streakbreaker= { common = 6,    uncommon = 5,    rare = 4,    epic = 3,    legendary = 2    }, -- max losses in a row before pity kicks in
}

-- Shop ---------------------------------------------------------------------------
config.shop = {
  prices = { common = 250, uncommon = 750, rare = 2000, epic = 6000, legendary = 15000 },
  featuredCount = 3,  -- dice on the daily featured rotation
}

-- Rarity unlock gates (lifetime chips earned AND best PvE tier reached) ------------
config.unlocks = {
  common    = { chips = 0,      tier = 0 },
  uncommon  = { chips = 1000,   tier = 1 },
  rare      = { chips = 5000,   tier = 3 },
  epic      = { chips = 20000,  tier = 5 },
  legendary = { chips = 75000,  tier = 8 },
}

-- Daily / streak rewards ------------------------------------------------------------
config.rewards = {
  daily = { 50, 75, 100, 150, 200, 300, 500 }, -- consecutive-day curve, caps at last
  winStreakBonusPerWin = 10,   -- bonus chips = streak * this
  winStreakBonusCap    = 200,
}

-- PvE fever chain: consecutive winning rolls boost payouts -------------------------
-- 2nd straight win pays +stepPct, 3rd +2*stepPct... up to maxSteps.
config.fever = {
  stepPct  = 0.25,
  maxSteps = 4,     -- caps at +100% (payouts doubled) on a hot hand
}

-- Battle Royale ("Boneyard") --------------------------------------------------------
-- Craps-combat: every player rolls 2d6 each round, all dice visible.
--   Come-out (no point armed): 7/11 = clean hit on your target for the sum;
--   2/3/12 = craps backfire (self damage); anything else ARMS that number
--   as your point (a hard-way double arms it AND chips your target).
--   Armed: roll your point = POINT BREAK (point x pointBreakMult to target);
--   roll a 7 = SEVEN-OUT (7 + point self damage, chain resets).
-- Chains: consecutive hits raise your damage multiplier; misses don't reset
-- it, only craps/seven-outs do. The Rake (storm) forces matches to end.
config.br = {
  playerCount     = 8,
  startHP         = 100,
  entryFee        = 100,
  crapsSelfMult   = 2,     -- self damage = sum * this on a come-out craps
  pointBreakMult  = 3,     -- point break damage = point * this
  hardSetChip     = true,  -- arming a point with a double chips the target for the sum
  pressureDoubles = true,  -- doubles during the point phase chip for sum/2
  chainStep       = 0.5,   -- +50% damage per chain level
  chainMax        = 5,     -- caps at x3.5
  killBounty      = 50,    -- chips per elimination you land
  killHeal        = 20,    -- HP restored on a kill
  rakeStartRound  = 10,    -- the Rake starts collecting after this round
  rakeBase        = 4,     -- Rake damage on its first round...
  rakeStep        = 3,     -- ...growing by this every round after
  prizeSplit      = { 0.60, 0.25, 0.15 }, -- of the pot, for 1st/2nd/3rd
  mutatorsPerMatch = 2,
}

-- BR mutators: 2 are drawn at match start and shown on a banner. All are
-- read by src/modes/battleroyale.lua; keep them data-only here.
config.br.mutators = {
  { id = "glass_bones",  name = "Glass Bones",
    desc = "Everyone starts at half HP and all damage is x1.5.",
    hpMult = 0.5, damageMult = 1.5 },
  { id = "vampiric",     name = "Vampiric",
    desc = "Heal 30% of the damage you deal.",
    lifesteal = 0.3 },
  { id = "blood_money",  name = "Blood Money",
    desc = "Every 2 damage you deal pays 1 chip at match end.",
    chipsPerDamage = 0.5 },
  { id = "hot_hands",    name = "Hot Hands",
    desc = "Chains build twice as fast.",
    chainGain = 2 },
  { id = "big_bounty",   name = "Big Bounty",
    desc = "Kill bounties and kill heals are doubled.",
    bountyMult = 2 },
  { id = "early_rake",   name = "Rolling Thunder",
    desc = "The Rake arrives 4 rounds early and hits harder.",
    rakeStartDelta = -4, rakeMult = 1.5 },
}

-- Ranked rating (ELO-ish) --------------------------------------------------------------
config.ranked = {
  baseRating = 1000,
  kFactor    = 32,
  disconnectPenalty = 25, -- flat rating loss on rage-quit, on top of the loss itself
  minPlayers = 2,
  maxPlayers = 8,
  ante       = 100,
}

-- Networking -----------------------------------------------------------------------------
config.net = {
  defaultPort = 22122,
  tickRate    = 20,     -- server fixed steps per second
  timeout     = 8,      -- seconds before a silent peer is dropped
}

--------------------------------------------------------------------------------------------
-- Bet definitions (data-driven). Each entry:
--   { id, label, payout, resolve(rollState) -> "win"|"lose"|"push"|nil [, multiplier] }
-- resolve returning nil means the bet stays on the table (still pending).
-- rollState = { dice, sum, isDouble, phase, point } where phase/point are the
-- table state at the moment of the roll (before transitions).
--------------------------------------------------------------------------------------------

config.bets = {}
local function addBet(def) config.bets[#config.bets + 1] = def end

addBet{
  id = "pass", label = "Pass Line", payout = 1, category = "line", comeoutOnly = true,
  resolve = function(rs)
    if rs.phase == "comeout" then
      if rs.sum == 7 or rs.sum == 11 then return "win" end
      if rs.sum == 2 or rs.sum == 3 or rs.sum == 12 then return "lose" end
      return nil -- point established, bet rides
    end
    if rs.sum == rs.point then return "win" end
    if rs.sum == 7 then return "lose" end -- seven-out
    return nil
  end,
}

addBet{
  id = "dontpass", label = "Don't Pass", payout = 1, category = "line", comeoutOnly = true,
  resolve = function(rs)
    if rs.phase == "comeout" then
      if rs.sum == 2 or rs.sum == 3 then return "win" end
      if rs.sum == 7 or rs.sum == 11 then return "lose" end
      if rs.sum == 12 then return "push" end -- "bar 12": push keeps the house edge
      return nil
    end
    if rs.sum == 7 then return "win" end
    if rs.sum == rs.point then return "lose" end
    return nil
  end,
}

addBet{
  id = "field", label = "Field", payout = 1, category = "oneroll",
  resolve = function(rs)
    if rs.sum == 2  then return "win", 2 end -- 2 pays double
    if rs.sum == 12 then return "win", 3 end -- 12 pays triple
    if rs.sum == 3 or rs.sum == 4 or rs.sum == 9 or rs.sum == 10 or rs.sum == 11 then
      return "win", 1
    end
    return "lose" -- 5, 6, 7, 8
  end,
}

-- Place bets: pay true-odds-minus-vig house numbers.
-- 4/10 -> 9:5, 5/9 -> 7:5, 6/8 -> 7:6. Off (no action) during the come-out.
local placePayouts = { [4] = 9/5, [5] = 7/5, [6] = 7/6, [8] = 7/6, [9] = 7/5, [10] = 9/5 }
for _, n in ipairs({ 4, 5, 6, 8, 9, 10 }) do
  addBet{
    id = "place" .. n, label = "Place " .. n, payout = placePayouts[n], category = "place",
    resolve = function(rs)
      if rs.phase ~= "point" then return nil end -- place bets are OFF on come-out
      if rs.sum == n then return "win" end
      if rs.sum == 7 then return "lose" end
      return nil
    end,
  }
end

-- Hardways: the number must roll as a double before a 7 or the "easy" way.
-- Hard 4/10 pay 7:1, hard 6/8 pay 9:1 (more easy combos exist for 6/8).
local hardPayouts = { [4] = 7, [6] = 9, [8] = 9, [10] = 7 }
for _, n in ipairs({ 4, 6, 8, 10 }) do
  addBet{
    id = "hard" .. n, label = "Hard " .. n, payout = hardPayouts[n], category = "hardway",
    resolve = function(rs)
      if rs.sum == n then
        if rs.isDouble then return "win" end
        return "lose" -- rolled it the easy way
      end
      if rs.sum == 7 then return "lose" end
      return nil
    end,
  }
end

addBet{
  id = "any7", label = "Any Seven", payout = 4, category = "oneroll",
  resolve = function(rs)
    if rs.sum == 7 then return "win" end
    return "lose"
  end,
}

addBet{
  id = "anycraps", label = "Any Craps", payout = 7, category = "oneroll",
  resolve = function(rs)
    if rs.sum == 2 or rs.sum == 3 or rs.sum == 12 then return "win" end
    return "lose"
  end,
}

-- Fast lookup by id
config.betsById = {}
for _, def in ipairs(config.bets) do config.betsById[def.id] = def end

return config
