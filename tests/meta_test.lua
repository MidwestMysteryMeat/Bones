--------------------------------------------------------------------------
-- tests/meta_test.lua
-- Headless integration test of the meta layer: plays full PvE runs with
-- the real engine + skill-dice hooks, exercises economy, shop, unlocks,
-- rewards, and rating math. Run: lua tests/meta_test.lua
--------------------------------------------------------------------------

package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local config      = require("src.core.config")
local save        = require("src.core.save")
local economy     = require("src.core.economy")
local pve         = require("src.modes.pve")
local shop        = require("src.meta.shop")
local unlocks     = require("src.meta.unlocks")
local rewards     = require("src.meta.rewards")
local leaderboard = require("src.meta.leaderboard")
local catalog     = require("src.meta.dice_catalog")

local passed, failed = 0, 0
local function check(cond, name, detail)
  if cond then passed = passed + 1 print("PASS  " .. name)
  else
    failed = failed + 1
    print("FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

-- Fresh save, no disk.
local data = save.defaults()
save.data = data
economy.init(data)

--------------------------------------------------------------------------
print("== Economy basics ==")
--------------------------------------------------------------------------
check(economy.getWallet() == config.economy.startingWallet,
  "new save starts with the configured wallet")
check(not economy.debit(economy.getWallet() + 1),
  "overdraft rejected")
economy.credit(100, "test", true, "test win")
check(data.lifetimeEarned == 100 and data.biggestWin.amount == 100,
  "winnings feed lifetime earnings + biggest win")

--------------------------------------------------------------------------
print("== Full PvE run (real RNG, real hooks) ==")
--------------------------------------------------------------------------
do
  -- Give the save a modifier-heavy loadout to exercise every hook path.
  data.ownedDice.cherry_red = true    -- weighted
  data.ownedDice.night_blue = true    -- rerollLowest
  data.ownedDice.bar_brass = true     -- loaded7
  data.equipped = { "cherry_red", "night_blue", "bar_brass" }

  local walletBefore = economy.getWallet()
  local run, err = pve.newRun(data, 42)
  check(run ~= nil, "run starts", err)
  check(economy.getWallet() == walletBefore - config.economy.pveRunBankroll,
    "run stake debited from the wallet")

  -- Play until the run ends or 3000 rolls pass: bet pass line every
  -- come-out, field occasionally.
  local rolls = 0
  while not run.over and rolls < 3000 do
    if run.table.phase == "comeout"
      and run.table:playerExposure("player") == 0 then
      local amt = math.min(run.table.limits.max,
        math.max(run.table.limits.min, math.floor(run.bankroll * 0.1)))
      if amt > run.bankroll then break end
      run:placeBet("pass", amt)
    end
    local roll, events = run:roll()
    rolls = rolls + 1
    assert(#roll.dice >= 2, "roll returned fewer than 2 dice")
    if events.bust then break end
  end
  if not run.over then run:cashOut() end
  check(run.summary ~= nil, "run produced a summary after " .. rolls .. " rolls")
  check(run.summary.tierReached >= 1, "tier recorded: " .. run.summary.tierReached)
  check(data.achievements.FIRST_ROLL, "FIRST_ROLL achievement fired")
  check(economy.getWallet() >= 0, "wallet never negative")
  check(data.bestTier >= 1, "bestTier persisted to save")
end

--------------------------------------------------------------------------
print("== Streakbreaker pity hook ==")
--------------------------------------------------------------------------
do
  data.ownedDice.phoenix_pip = true
  data.equipped = { "phoenix_pip" } -- legendary: max 2 losses in a row
  economy.credit(10000, "test_fund")
  local run = pve.newRun(data, 777)
  local maxLossStreak, lossStreak = 0, 0
  local rolls = 0
  while not run.over and rolls < 2000 do
    if run.table.phase == "comeout"
      and run.table:playerExposure("player") == 0 then
      local amt = run.table.limits.min
      if amt > run.bankroll then break end
      run:placeBet("pass", amt)
    end
    local _, events = run:roll()
    rolls = rolls + 1
    if events.net and events.net < 0 then
      lossStreak = lossStreak + 1
      maxLossStreak = math.max(maxLossStreak, lossStreak)
    elseif events.net and events.net > 0 then
      lossStreak = 0
    end
    if events.bust then break end
  end
  if not run.over then run:cashOut() end
  -- Pity threshold 2 forces a natural on the NEXT come-out; pass-line
  -- resolutions in between (point phase losses) mean streaks of 3 can
  -- appear, but long streaks must be gone.
  check(maxLossStreak <= 4,
    "legendary streakbreaker caps loss streaks (max seen: " .. maxLossStreak .. ")")
end

--------------------------------------------------------------------------
print("== Shop + unlocks ==")
--------------------------------------------------------------------------
do
  data.equipped = { "starter_ivory" }
  economy.credit(50000, "test_fund")
  data.lifetimeEarned = 0
  data.bestTier = 0

  local ok, reason = shop.canBuy(data, "jade_luck") -- uncommon
  check(not ok and reason:find("locked"), "locked rarity blocks purchase", reason)

  data.lifetimeEarned = config.unlocks.uncommon.chips
  data.bestTier = config.unlocks.uncommon.tier
  check(unlocks.rarityUnlocked(data, "uncommon"), "uncommon unlocks at its gates")

  local w = economy.getWallet()
  check(shop.buy(data, "jade_luck"), "purchase succeeds once unlocked")
  check(economy.getWallet() == w - catalog.byId.jade_luck.price,
    "price debited exactly")
  check(not shop.buy(data, "jade_luck"), "double-purchase rejected")

  check(shop.equip(data, "jade_luck"), "equip works")
  local full = { "starter_ivory", "jade_luck" }
  data.equipped = full
  data.ownedDice.night_blue = true
  shop.equip(data, "night_blue")
  local ok2 = shop.equip(data, "cherry_red")
  check(not ok2, "loadout size enforced at " .. config.pve.loadoutSize)

  local newly = unlocks.recordTier(data, 3)
  local hasRare = false
  for _, r in ipairs(newly) do hasRare = hasRare or r == "rare" end
  check(data.bestTier == 3, "recordTier tracks best tier")

  local featA = shop.featuredToday()
  local featB = shop.featuredToday()
  check(#featA == config.shop.featuredCount and featA[1].id == featB[1].id,
    "featured rotation is deterministic for the day")
end

--------------------------------------------------------------------------
print("== Rewards ==")
--------------------------------------------------------------------------
do
  data.lastDailyStamp = 0
  data.dailyStreak = 0
  local w = economy.getWallet()
  local r1 = rewards.claimDaily(data)
  check(r1 and r1.day == 1 and economy.getWallet() == w + config.rewards.daily[1],
    "first daily claim pays day 1")
  check(rewards.claimDaily(data) == nil, "second claim same day rejected")

  check(rewards.streakBonus(1) == 0, "no bonus below streak 2")
  check(rewards.streakBonus(3) == 3 * config.rewards.winStreakBonusPerWin,
    "streak bonus scales")
  check(rewards.streakBonus(1000) == config.rewards.winStreakBonusCap,
    "streak bonus caps")

  -- COMEBACK can't fire from the scripted runs above, so it's fresh here.
  local a = rewards.unlock(data, "COMEBACK")
  check(a and a.id == "COMEBACK", "achievement unlocks once")
  check(rewards.unlock(data, "COMEBACK") == nil, "achievement idempotent")
end

--------------------------------------------------------------------------
print("== Ranked rating math ==")
--------------------------------------------------------------------------
do
  local players = {
    { id = "a", rating = 1000, position = 1 },
    { id = "b", rating = 1000, position = 2 },
  }
  local nr = leaderboard.updateRatings(players)
  check(nr.a == 1016 and nr.b == 984,
    "even 1v1: winner +K/2, loser -K/2", nr.a .. "/" .. nr.b)

  local upset = leaderboard.updateRatings({
    { id = "low", rating = 800, position = 1 },
    { id = "high", rating = 1200, position = 2 },
  })
  check(upset.low - 800 > 16, "upset win pays more than an even win")
  check((upset.low - 800) == (1200 - upset.high), "zero-sum rating exchange")

  local four = leaderboard.updateRatings({
    { id = "p1", rating = 1000, position = 1 },
    { id = "p2", rating = 1000, position = 2 },
    { id = "p3", rating = 1000, position = 3 },
    { id = "p4", rating = 1000, position = 4 },
  })
  check(four.p1 > four.p2 and four.p2 > four.p3 and four.p3 > four.p4,
    "4-player table orders rating deltas by position")
  check(leaderboard.disconnectPenalty(1000)
    == 1000 - config.ranked.disconnectPenalty, "disconnect penalty applies")
end

--------------------------------------------------------------------------
print("== PvP fair-dice verification ==")
--------------------------------------------------------------------------
do
  local rngmod = require("src.core.rng")
  local pvpmode = require("src.modes.pvp")
  local rng = rngmod.new(987654)
  local dice = { rng:rollDie(6), rng:rollDie(6) }
  check(pvpmode.verifyRoll(987654, dice), "honest roll verifies")
  check(not pvpmode.verifyRoll(987654, { 6, 6 })
    or (dice[1] == 6 and dice[2] == 6), "tampered roll fails verification")
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
