--------------------------------------------------------------------------
-- tests/engine_test.lua
-- Headless dice engine tests. Run from the project root:
--     lua tests/engine_test.lua      (any Lua 5.1 - 5.4 / LuaJIT)
-- No LÖVE required: rng.lua falls back to its portable LCG.
--
-- Strategy: for payout correctness we inject exact dice through the
-- engine's applyPostRoll hook (the same hook PvE skill dice use), so
-- every craps rule is tested deterministically. A final statistical test
-- uses the real seeded RNG to confirm the Pass Line house edge.
--------------------------------------------------------------------------

package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local config = require("src.core.config")
local engine = require("src.core.diceengine")

local passed, failed = 0, 0
local function check(cond, name, detail)
  if cond then
    passed = passed + 1
    print(("PASS  %s"):format(name))
  else
    failed = failed + 1
    print(("FAIL  %s%s"):format(name, detail and ("  -- " .. detail) or ""))
  end
end

-- Build a table whose rolls come from a fixed queue of dice pairs.
local function riggedTable(queue, ruleset)
  ruleset = ruleset or {}
  local i = 0
  ruleset.hooks = {
    applyPostRoll = function(dice)
      i = i + 1
      assert(queue[i], "rigged dice queue exhausted")
      return { queue[i][1], queue[i][2] }
    end,
  }
  return engine.newTable(1, ruleset)
end

--------------------------------------------------------------------------
print("== Determinism ==")
--------------------------------------------------------------------------
do
  local a, b = engine.newTable(12345), engine.newTable(12345)
  local same = true
  for _ = 1, 200 do
    local ra, rb = a:roll(), b:roll()
    if ra.sum ~= rb.sum or ra.dice[1] ~= rb.dice[1] or ra.dice[2] ~= rb.dice[2] then
      same = false
      break
    end
  end
  check(same, "same seed -> identical 200-roll sequence")

  local c = engine.newTable(54321)
  local differs = false
  for _ = 1, 200 do
    local ra = engine.newTable(12345) -- fresh table, first roll
    local rc = c:roll()
    if ra:roll().sum ~= rc.sum then differs = true break end
  end
  check(differs, "different seed -> different sequence")
end

--------------------------------------------------------------------------
print("== Pass Line ==")
--------------------------------------------------------------------------
do -- natural 7 on come-out pays 1:1
  local t = riggedTable({ { 3, 4 } })
  assert(t:placeBet("p1", "pass", 100))
  local _, s = t:rollAndSettle()
  check(s.payouts.p1 == 200, "come-out 7: pass wins 1:1 (100 -> 200)",
    "got " .. tostring(s.payouts.p1))
end

do -- craps 2 on come-out loses; house takes stake minus jackpot rake
  local t = riggedTable({ { 1, 1 } })
  assert(t:placeBet("p1", "pass", 100))
  local _, s = t:rollAndSettle()
  check((s.payouts.p1 or 0) == 0, "come-out 2: pass loses")
  check(s.jackpotContribution == 2, "2% rake of losing 100 feeds jackpot",
    "got " .. tostring(s.jackpotContribution))
  check(s.houseTake == 98, "house keeps the remaining 98")
end

do -- point established then hit
  local t = riggedTable({ { 2, 2 }, { 1, 3 } })
  assert(t:placeBet("p1", "pass", 50))
  local r1 = t:roll(); t:settle()
  check(r1.phase == "point" and r1.point == 4, "come-out 4 establishes the point")
  local _, s2 = t:rollAndSettle()
  check(s2.payouts.p1 == 100, "hitting the point pays the pass line",
    "got " .. tostring(s2.payouts.p1))
end

do -- seven-out
  local t = riggedTable({ { 2, 3 }, { 3, 4 } })
  assert(t:placeBet("p1", "pass", 50))
  t:roll(); t:settle() -- point = 5
  local r2, s2 = t:rollAndSettle()
  check((s2.payouts.p1 or 0) == 0 and r2.phase == "comeout",
    "seven-out: pass loses, back to come-out")
end

do -- line bets locked once the point is on
  local t = riggedTable({ { 2, 3 } })
  t:roll(); t:settle()
  local ok, err = t:placeBet("p1", "pass", 50)
  check(not ok, "pass line rejected during point phase", err)
end

--------------------------------------------------------------------------
print("== Don't Pass ==")
--------------------------------------------------------------------------
do -- bar 12: push, stake returned
  local t = riggedTable({ { 6, 6 } })
  assert(t:placeBet("p1", "dontpass", 80))
  local r, s = t:rollAndSettle()
  check(s.payouts.p1 == 80, "come-out 12 pushes don't pass (bar 12)",
    "got " .. tostring(s.payouts.p1))
  check(not r.jackpotHit, "single boxcars does not trip the jackpot")
end

do -- don't pass wins the seven-out
  local t = riggedTable({ { 4, 4 }, { 5, 2 } })
  assert(t:placeBet("p1", "dontpass", 40))
  t:roll(); t:settle() -- point = 8
  local _, s = t:rollAndSettle()
  check(s.payouts.p1 == 80, "seven-out pays don't pass 1:1")
end

--------------------------------------------------------------------------
print("== Field (one-roll) ==")
--------------------------------------------------------------------------
do
  local cases = {
    { dice = { 1, 1 }, bet = 50, want = 150, name = "field 2 pays 2:1" },
    { dice = { 6, 6 }, bet = 50, want = 200, name = "field 12 pays 3:1" },
    { dice = { 5, 6 }, bet = 50, want = 100, name = "field 11 pays 1:1" },
    { dice = { 2, 3 }, bet = 50, want = 0,   name = "field 5 loses" },
  }
  for _, c in ipairs(cases) do
    local t = riggedTable({ c.dice })
    assert(t:placeBet("p1", "field", c.bet))
    local _, s = t:rollAndSettle()
    check((s.payouts.p1 or 0) == c.want, c.name, "got " .. tostring(s.payouts.p1))
  end
end

--------------------------------------------------------------------------
print("== Place bets ==")
--------------------------------------------------------------------------
do -- place 6 pays 7:6 (floored to whole chips), only with the point on
  local t = riggedTable({ { 2, 3 }, { 4, 2 } })
  t:roll(); t:settle() -- point = 5, place bets now working
  assert(t:placeBet("p1", "place6", 60))
  local _, s = t:rollAndSettle()
  check(s.payouts.p1 == 130, "place 6 for 60 pays 70 (7:6)",
    "got " .. tostring(s.payouts.p1))
end

do -- place bet is OFF during come-out: no action either way
  local t = riggedTable({ { 3, 4 } }) -- 7 on the come-out
  assert(t:placeBet("p1", "place8", 30))
  local _, s = t:rollAndSettle()
  check(s.payouts.p1 == nil and s.houseTake == 0,
    "place 8 has no action on the come-out 7")
end

do -- seven-out kills working place bets
  local t = riggedTable({ { 2, 2 }, { 3, 4 } })
  t:roll(); t:settle() -- point = 4
  assert(t:placeBet("p1", "place9", 100))
  local _, s = t:rollAndSettle()
  check((s.payouts.p1 or 0) == 0 and s.houseTake > 0, "place 9 loses to the seven")
end

--------------------------------------------------------------------------
print("== Hardways ==")
--------------------------------------------------------------------------
do
  local cases = {
    { rolls = { { 4, 4 } }, bet = "hard8",  amt = 10, want = 100, name = "hard 8 (4-4) pays 9:1" },
    { rolls = { { 2, 2 } }, bet = "hard4",  amt = 10, want = 80,  name = "hard 4 (2-2) pays 7:1" },
    { rolls = { { 6, 2 } }, bet = "hard8",  amt = 10, want = 0,   name = "easy 8 (6-2) loses hard 8" },
    { rolls = { { 3, 4 } }, bet = "hard10", amt = 10, want = 0,   name = "seven kills hard 10" },
  }
  for _, c in ipairs(cases) do
    local t = riggedTable(c.rolls)
    assert(t:placeBet("p1", c.bet, c.amt))
    local _, s = t:rollAndSettle()
    check((s.payouts.p1 or 0) == c.want, c.name, "got " .. tostring(s.payouts.p1))
  end
end

do -- hardway rides through unrelated rolls
  local t = riggedTable({ { 2, 3 }, { 1, 2 }, { 3, 3 } })
  assert(t:placeBet("p1", "hard6", 20))
  t:roll(); t:settle() -- 5: no action on hard 6
  t:roll(); t:settle() -- 3: still riding
  local _, s = t:rollAndSettle() -- 3-3: hard six!
  check(s.payouts.p1 == 200, "hard 6 rides two rolls then pays 9:1",
    "got " .. tostring(s.payouts.p1))
end

--------------------------------------------------------------------------
print("== Any Seven / Any Craps ==")
--------------------------------------------------------------------------
do
  local t = riggedTable({ { 5, 2 } })
  assert(t:placeBet("p1", "any7", 25))
  local _, s = t:rollAndSettle()
  check(s.payouts.p1 == 125, "any seven pays 4:1")
end
do
  local t = riggedTable({ { 1, 2 } })
  assert(t:placeBet("p1", "anycraps", 25))
  local _, s = t:rollAndSettle()
  check(s.payouts.p1 == 200, "any craps pays 7:1")
end

--------------------------------------------------------------------------
print("== Table rules ==")
--------------------------------------------------------------------------
do
  local t = engine.newTable(7, { limits = { min = 10, max = 100 } })
  check(not t:placeBet("p1", "pass", 5),   "bet below table minimum rejected")
  check(not t:placeBet("p1", "pass", 500), "bet above table maximum rejected")
  check(not t:placeBet("p1", "nope", 50),  "unknown bet id rejected")
  local t2 = engine.newTable(7, { allowedBets = { pass = true } })
  check(not t2:placeBet("p1", "field", 50), "bet outside table whitelist rejected")
  check(t2:placeBet("p1", "pass", 50),      "whitelisted bet accepted")
end

do -- fold refunds pending bets (disconnect handling)
  local t = engine.newTable(7)
  t:placeBet("p1", "pass", 50)
  t:placeBet("p1", "field", 25)
  t:placeBet("p2", "pass", 30)
  check(t:foldPlayer("p1") == 75 and t:playerExposure("p2") == 30,
    "foldPlayer refunds only that player's bets")
end

--------------------------------------------------------------------------
print("== Progressive jackpot ==")
--------------------------------------------------------------------------
do -- two consecutive boxcars pays the pool and resets to the seed floor
  local t = riggedTable({ { 6, 6 }, { 6, 6 } }, { jackpotPool = 9000 })
  local r1 = t:roll(); t:settle()
  check(not r1.jackpotHit, "first boxcars arms the jackpot only")
  local r2, s2 = t:rollAndSettle()
  check(r2.jackpotHit, "second consecutive boxcars hits the jackpot")
  check(s2.jackpotPayout == 9000, "full pool paid out",
    "got " .. tostring(s2.jackpotPayout))
  check(s2.pool == config.jackpot.seedFloor, "pool reset to seed floor")
end

do -- a non-boxcars roll breaks the streak
  local t = riggedTable({ { 6, 6 }, { 1, 2 }, { 6, 6 } })
  t:roll() t:settle()
  t:roll() t:settle()
  local r3 = t:roll()
  check(not r3.jackpotHit, "streak broken by an ordinary roll")
end

do -- rake accrues into the pool
  local t = riggedTable({ { 2, 3 } }, { jackpotPool = 1000 })
  assert(t:placeBet("p1", "field", 200)) -- field loses on 5
  local _, s = t:rollAndSettle()
  check(s.pool == 1004, "pool grows by 2% of the losing 200",
    "got " .. tostring(s.pool))
end

--------------------------------------------------------------------------
print("== Statistical: Pass Line house edge ==")
--------------------------------------------------------------------------
do
  -- Theoretical pass line edge is 1.4141%. With 300k resolutions the
  -- standard error is ~0.18%, so +/-0.6% is a safe deterministic band
  -- for this fixed seed.
  local t = engine.newTable(20260701, { jackpot = false,
    limits = { min = 1, max = 1000 } })
  local staked, returned, resolutions = 0, 0, 0
  while resolutions < 300000 do
    if t.phase == "comeout" and t:playerExposure("p1") == 0 then
      assert(t:placeBet("p1", "pass", 10))
      staked = staked + 10
    end
    local _, s = t:rollAndSettle()
    if s.payouts.p1 ~= nil or (s.houseTake > 0) then
      resolutions = resolutions + 1
      returned = returned + (s.payouts.p1 or 0)
    end
  end
  local edge = (staked - returned) / staked
  print(("      measured edge over %d resolutions: %.4f%%"):format(
    resolutions, edge * 100))
  check(math.abs(edge - 0.014141) < 0.006,
    "pass line house edge within 0.6% of the theoretical 1.414%")
end

--------------------------------------------------------------------------
print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
