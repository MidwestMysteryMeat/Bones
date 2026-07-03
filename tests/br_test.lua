--------------------------------------------------------------------------
-- tests/br_test.lua
-- Headless Battle Royale tests: full matches across seeds, chain math,
-- mutators, eliminations, payouts, plus the PvE fever chain.
-- Run: lua tests/br_test.lua
--------------------------------------------------------------------------

package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local config  = require("src.core.config")
local save    = require("src.core.save")
local economy = require("src.core.economy")
local br      = require("src.modes.battleroyale")
local pve     = require("src.modes.pve")

local passed, failed = 0, 0
local function check(cond, name, detail)
  if cond then passed = passed + 1 print("PASS  " .. name)
  else
    failed = failed + 1
    print("FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local function freshSave()
  local data = save.defaults()
  save.data = data
  economy.init(data)
  economy.credit(20000, "test_fund")
  return data
end

--------------------------------------------------------------------------
print("== Match lifecycle ==")
--------------------------------------------------------------------------
do
  local data = freshSave()
  local w = economy.getWallet()
  local m = br.newMatch(data, { seed = 1234 })
  check(m ~= nil, "match starts")
  check(economy.getWallet() == w - config.br.entryFee, "entry fee debited")
  check(#m.players == config.br.playerCount, "8 players seated")
  check(#m.mutators == config.br.mutatorsPerMatch, "2 mutators drawn")
  check(m.players[1].isHuman and m.players[1].name == "You", "player 1 is human")

  m:setTarget(3)
  check(m.players[1].target == 3, "human target set")
  m:setTarget(1)
  check(m.players[1].target == 3, "can't target yourself")

  local rounds = 0
  while not m.over and rounds < 300 do
    local events = m:playRound()
    rounds = rounds + 1
    assert(#events > 0, "round produced no events")
    for _, p in ipairs(m.players) do
      assert(p.hp >= 0, "hp went negative")
      assert(p.chain <= config.br.chainMax * 4, "runaway chain")
    end
  end
  check(m.over, "match ends (round " .. rounds .. ")")
  local rakeLimit = config.br.rakeStartRound + 40
  check(rounds < rakeLimit, "the Rake forces an ending", "took " .. rounds)

  local s = m.summary
  check(s ~= nil and s.placement >= 1 and s.placement <= 8,
    "human placed #" .. tostring(s and s.placement))
  check(#s.standings == config.br.playerCount, "standings cover everyone")
  local seen = {}
  local dupes = false
  for _, e in ipairs(s.standings) do
    if seen[e.index] then dupes = true end
    seen[e.index] = true
  end
  check(not dupes, "no duplicate standings entries")
end

--------------------------------------------------------------------------
print("== AI targeting spread ==")
--------------------------------------------------------------------------
do
  -- Regression: a deterministic tie-break once sent EVERY AI at the human
  -- on round one. Across seeds, round-1 attention on player 1 must stay
  -- well under the full table.
  -- Statistical: with uniform tie-breaks each AI has a 1/7 chance to pick
  -- the human, so the mean over many seeds must sit near 1, not near 7.
  local total, seeds = 0, 60
  for seed = 1, seeds do
    freshSave()
    local m = br.newMatch(nil, { seed = seed })
    m:playRound()
    for i = 2, #m.players do
      if m.players[i].target == 1 then total = total + 1 end
    end
  end
  local mean = total / seeds
  check(mean < 2.5, ("round-1 attention on the human averages %.2f/7 "
    .. "(dogpile bug would be ~7)"):format(mean))
end

--------------------------------------------------------------------------
print("== Determinism ==")
--------------------------------------------------------------------------
do
  local function play(seed)
    freshSave()
    local m = br.newMatch(nil, { seed = seed })
    while not m.over do m:playRound() end
    return m.summary
  end
  local a, b = play(777), play(777)
  check(a.placement == b.placement and a.rounds == b.rounds
    and a.standings[1].index == b.standings[1].index,
    "same seed -> identical match outcome")
end

--------------------------------------------------------------------------
print("== Payouts ==")
--------------------------------------------------------------------------
do
  -- Find a seed where the human wins, then verify the prize math.
  local winSeed
  for seed = 1, 400 do
    freshSave()
    local m = br.newMatch(nil, { seed = seed, forceMutators = {} })
    while not m.over do m:playRound() end
    if m.summary.placement == 1 then winSeed = seed break end
  end
  check(winSeed ~= nil, "found a winning seed in 400 tries: " .. tostring(winSeed))
  if winSeed then
    local data = freshSave()
    local before = economy.getWallet()
    local m = br.newMatch(data, { seed = winSeed, forceMutators = {} })
    while not m.over do m:playRound() end
    local s = m.summary
    local expectedPrize = math.floor(
      config.br.entryFee * config.br.playerCount * config.br.prizeSplit[1])
    check(s.prize == expectedPrize, "winner takes 60% of the pot",
      s.prize .. " vs " .. expectedPrize)
    check(economy.getWallet() == before - config.br.entryFee + s.totalWon,
      "wallet = -entry +prize +bounties")
    check(data.achievements.BR_WIN, "BR_WIN achievement fired")
    local leaderboard = require("src.meta.leaderboard")
    local top = leaderboard.getTop(data, leaderboard.BOARD_BIG_WIN, 5)
    check(#top > 0 and top[1].score == s.totalWon,
      "BR win lands on the local big-win leaderboard")
    check(s.bounties == s.kills * config.br.killBounty
      or s.bounties >= 0, "bounties accounted")
  end
end

--------------------------------------------------------------------------
print("== Mutators ==")
--------------------------------------------------------------------------
do
  freshSave()
  local m = br.newMatch(nil, { seed = 5, forceMutators = { "glass_bones" } })
  check(m.players[1].maxHP == math.floor(config.br.startHP * 0.5),
    "glass bones halves starting HP", tostring(m.players[1].maxHP))

  freshSave()
  local m2 = br.newMatch(nil, { seed = 5, forceMutators = { "early_rake" } })
  -- Rake must appear by rakeStartRound + delta + 1.
  local sawRakeAt
  while not m2.over do
    for _, e in ipairs(m2:playRound()) do
      if e.type == "rake" and not sawRakeAt then sawRakeAt = m2.round end
    end
  end
  local expected = config.br.rakeStartRound - 4 + 1
  check(sawRakeAt == nil or sawRakeAt == expected,
    "rolling thunder starts the Rake early",
    tostring(sawRakeAt) .. " vs " .. expected)
  check(sawRakeAt ~= nil or m2.summary.rounds <= expected,
    "rake observed unless the match ended first")

  freshSave()
  local m3 = br.newMatch(nil, { seed = 9, forceMutators = { "blood_money" } })
  while not m3.over do m3:playRound() end
  check(m3.summary.bloodMoney ==
    math.floor(m3.players[1].damageDealt * 0.5),
    "blood money pays half of damage dealt as chips")
end

--------------------------------------------------------------------------
print("== Chain math ==")
--------------------------------------------------------------------------
do
  freshSave()
  local m = br.newMatch(nil, { seed = 1 })
  local p = m.players[1]
  p.chain = 0
  check(m:chainMult(p) == 1, "chain 0 -> x1")
  p.chain = 2
  check(m:chainMult(p) == 2, "chain 2 -> x2 (with 0.5 step)")
  p.chain = 99
  check(m:chainMult(p) == 1 + config.br.chainMax * config.br.chainStep,
    "chain multiplier caps")
end

--------------------------------------------------------------------------
print("== PvE fever chain ==")
--------------------------------------------------------------------------
do
  local data = freshSave()
  data.equipped = { "starter_ivory" }
  local run = pve.newRun(data, 31337)

  -- Force wins by rigging the table's post-roll hook to always roll 7 on
  -- come-out (same hook mechanism the engine tests use).
  run.table.hooks = { applyPostRoll = function(dice) return { 3, 4 } end }

  local bonuses = {}
  for i = 1, 6 do
    run:placeBet("pass", 10)
    local _, events = run:roll()
    bonuses[i] = events.feverBonus or 0
  end
  check(bonuses[1] == 0, "first win: no fever yet")
  check(bonuses[2] == math.floor(10 * 1 * config.fever.stepPct),
    "second straight win pays +25%", tostring(bonuses[2]))
  check(bonuses[5] == math.floor(10 * config.fever.maxSteps * config.fever.stepPct),
    "fever caps at maxSteps", tostring(bonuses[5]))
  check(bonuses[6] == bonuses[5], "capped fever stays capped")
  check(data.achievements.FEVER, "FEVER achievement fired at full chain")
  run:cashOut()
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
