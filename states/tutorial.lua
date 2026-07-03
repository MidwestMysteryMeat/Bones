--------------------------------------------------------------------------
-- states/tutorial.lua
-- HOW TO PLAY: tabbed pages covering craps basics, every bet (generated
-- from the live config so it never drifts from the engine), Solo Run,
-- the Boneyard battle royale, and multiplayer fairness. Includes a live
-- practice pair of dice with a plain-English readout of each roll.
--------------------------------------------------------------------------

local Gamestate   = require("lib.hump.gamestate")
local config      = require("src.core.config")
local screen      = require("src.ui.screen")
local widgets     = require("src.ui.widgets")
local dice_render = require("src.fx.dice_render")
local rngmod      = require("src.core.rng")
local sfx         = require("src.audio.sfx")

local state = {}

local tab = 1
local demoDice, demoRng
local demoPoint = nil
local demoText = "Press PRACTICE ROLL to throw the dice."
local demoRolling = false

-- Plain-English blurbs per bet id (payout numbers pulled live from config).
local betBlurbs = {
  pass     = "The classic. Wins on 7/11 on the come-out, loses on 2/3/12. Any other number becomes the Point - hit it again before a 7 to win.",
  dontpass = "Betting against the shooter. Wins on 2/3 (12 pushes), then wins if the 7 arrives before the Point repeats.",
  field    = "One roll: wins on 2,3,4,9,10,11,12. The 2 pays double and the 12 triple. Loses on 5,6,7,8.",
  place4   = "The 4 rolls before a 7 (only while a Point is on).",
  place5   = "The 5 rolls before a 7 (only while a Point is on).",
  place6   = "The 6 rolls before a 7 (only while a Point is on).",
  place8   = "The 8 rolls before a 7 (only while a Point is on).",
  place9   = "The 9 rolls before a 7 (only while a Point is on).",
  place10  = "The 10 rolls before a 7 (only while a Point is on).",
  hard4    = "2+2 exactly, before a 7 or an 'easy' 4 (3+1).",
  hard6    = "3+3 exactly, before a 7 or an easy 6.",
  hard8    = "4+4 exactly, before a 7 or an easy 8.",
  hard10   = "5+5 exactly, before a 7 or an easy 10.",
  any7     = "One roll: any 7.",
  anycraps = "One roll: 2, 3 or 12.",
}

local function payoutLabel(def)
  -- Show fractions as true odds (9/5 -> "9:5").
  local p = def.payout
  if p == math.floor(p) then return ("%d:1"):format(p) end
  for _, denom in ipairs({ 5, 6 }) do
    local num = p * denom
    if math.abs(num - math.floor(num + 0.5)) < 1e-9 then
      return ("%d:%d"):format(math.floor(num + 0.5), denom)
    end
  end
  return ("%.2f:1"):format(p)
end

local tabs = {
  "CRAPS 101", "THE BETS", "SOLO RUN", "BONEYARD (BR)", "MULTIPLAYER",
}

local pages = {}

pages[1] = function(x, y, w)
  local g = love.graphics
  g.setFont(screen.fonts.body)
  g.setColor(1, 0.92, 0.7)
  g.print("The come-out roll", x, y)
  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.85)
  g.printf([[
Every round of craps starts with a COME-OUT roll of two dice.

  - 7 or 11: "natural" - the Pass Line wins instantly.
  - 2, 3 or 12: "craps" - the Pass Line loses instantly.
  - Anything else (4,5,6,8,9,10): that number becomes the POINT.

Once a Point is set, the dice keep rolling:

  - Roll the Point again -> Pass Line wins.
  - Roll a 7 first -> "seven-out", Pass Line loses, round over.

That tension - the 7 that saves you on the come-out kills you once a
Point is on - is the heart of the whole game, including the Boneyard.

The puck on the table shows OFF (come-out) or ON <number> (point phase).
]], x, y + 30, w)

  -- Live practice dice.
  g.setFont(screen.fonts.body)
  g.setColor(1, 0.92, 0.7)
  g.print("Try it:", x, y + 300)
  demoDice[1].x, demoDice[1].y = x + 60, y + 380
  demoDice[2].x, demoDice[2].y = x + 150, y + 380
  demoDice[1]:draw()
  demoDice[2]:draw()
  if widgets.button(x + 230, y + 350, 190, 44, "PRACTICE ROLL",
    { small = true, disabled = demoRolling }) then
    demoRolling = true
    sfx.play("dice_rattle")
    local d1, d2 = demoRng:rollDie(6), demoRng:rollDie(6)
    local settled = 0
    for i, die in ipairs(demoDice) do
      die:startTumble(i == 1 and d1 or d2, 0.7 + i * 0.1, function()
        settled = settled + 1
        if settled == 2 then
          demoRolling = false
          sfx.play("dice_land")
          local sum = d1 + d2
          if not demoPoint then
            if sum == 7 or sum == 11 then
              demoText = ("%d - NATURAL! Pass Line wins."):format(sum)
            elseif sum == 2 or sum == 3 or sum == 12 then
              demoText = ("%d - CRAPS. Pass Line loses."):format(sum)
            else
              demoPoint = sum
              demoText = ("%d - the Point is now ON %d. Roll it again before a 7!"):format(sum, sum)
            end
          else
            if sum == demoPoint then
              demoText = ("%d - POINT HIT! Pass Line wins. Back to the come-out."):format(sum)
              demoPoint = nil
            elseif sum == 7 then
              demoText = "7 - SEVEN-OUT. Pass Line loses. Back to the come-out."
              demoPoint = nil
            else
              demoText = ("%d - no action. Still chasing the %d."):format(sum, demoPoint)
            end
          end
        end
      end)
    end
  end
  g.setFont(screen.fonts.small)
  g.setColor(0.6, 0.85, 1)
  g.print(demoPoint and ("POINT: ON %d"):format(demoPoint) or "COME-OUT (puck OFF)",
    x + 230, y + 402)
  g.setColor(1, 1, 1, 0.9)
  g.printf(demoText, x + 230, y + 424, w - 240)
end

pages[2] = function(x, y, w)
  local g = love.graphics
  g.setFont(screen.fonts.small)
  local col2 = x + w * 0.55
  local yy, count = y, 0
  local perCol = math.ceil(#config.bets / 2)
  for _, def in ipairs(config.bets) do
    local cx = count < perCol and x or col2
    if count == perCol then yy = y end
    g.setColor(1, 0.84, 0.3)
    g.print(("%s  (%s)"):format(def.label, payoutLabel(def)), cx, yy)
    g.setColor(1, 1, 1, 0.75)
    g.printf(betBlurbs[def.id] or "", cx, yy + 18, w * 0.42)
    local _, lines = (betBlurbs[def.id] or ""):gsub("%S+", "")
    yy = yy + 18 + math.ceil(screen.fonts.small:getWidth(betBlurbs[def.id] or "")
      / (w * 0.42)) * 16 + 14
    count = count + 1
  end
  g.setColor(0.6, 0.85, 1)
  g.printf("Every losing bet feeds 2% into the PROGRESSIVE JACKPOT. "
    .. "Roll boxcars (6-6) twice in a row and the whole pool is yours.",
    x, y + 430, w)
end

pages[3] = function(x, y, w)
  local g = love.graphics
  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.85)
  g.printf(([[
SOLO RUN is a gauntlet against the House.

  - You stake %d chips from your wallet as a starting bankroll.
  - Grow it past each tier's target to advance. %d tiers, escalating
    stakes, from %s to %s.
  - CASH OUT anytime to bank everything. BUST and the run ends - but you
    keep %d%% of your peak profit.

SKILL DICE (Solo Run only):
  - Buy dice in the shop and equip up to %d. Each carries a modifier:
    weighted faces, rerolls, seven-out protection, payout boosts, pity
    streakbreakers. Higher rarities are stronger.
  - Rarities unlock as you earn lifetime chips and reach new tiers.

STREAKS AND FEVER:
  - Consecutive winning rolls pay a chip bonus AND build a FEVER chain:
    your 2nd straight win pays +%d%%, stacking to +%d%% payouts. One loss
    resets it. Ride the hot hand.

The jackpot pool persists between runs and keeps growing. Somebody's
going to hit it. Might as well be you.]])
    :format(config.economy.pveRunBankroll, #config.pve.tiers,
      config.pve.tiers[1].name, config.pve.tiers[#config.pve.tiers].name,
      config.economy.bustMetaCut * 100, config.pve.loadoutSize,
      config.fever.stepPct * 100,
      config.fever.maxSteps * config.fever.stepPct * 100),
    x, y, w)
end

pages[4] = function(x, y, w)
  local g = love.graphics
  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.85)
  g.printf(([[
THE BONEYARD is craps as a battle royale: %d rollers, everyone's dice
face-up, last bones standing takes the pot.

Everyone has %d HP and rolls at once. Click an opponent to TARGET them.

YOUR ROLL, NO POINT ARMED (come-out):
  - 7 or 11: clean HIT - your target takes the sum as damage.
  - 2, 3 or 12: CRAPS BACKFIRE - you take the damage instead.
  - Anything else ARMS that number as your point. Arming with a double
    (hard way) also chips your target.

YOUR ROLL, POINT ARMED:
  - Roll your point: POINT BREAK - your target takes point x %d damage.
  - Roll a 7: SEVEN-OUT - you take (7 + point) damage yourself.
  - Doubles: pressure chip damage to your target.

CHAINS: every hit stacks +%d%% damage (max +%d%%). Only craps and
seven-outs break your chain - arm points fearlessly.

KILLS pay a %d chip bounty and heal you %d HP. Placing top 3 splits the
pot %d/%d/%d. After round %d THE RAKE bleeds every survivor, harder each
round - nobody waits out the clock.

MUTATORS: every match draws %d twists (Glass Bones, Vampiric, Blood
Money, Hot Hands...) shown on the banner. Read them - they change how
you should play.

Your equipped skill dice work here. It's you against the bots - cheat
away.]])
    :format(config.br.playerCount, config.br.startHP,
      config.br.pointBreakMult,
      config.br.chainStep * 100, config.br.chainMax * config.br.chainStep * 100,
      config.br.killBounty, config.br.killHeal,
      config.br.prizeSplit[1] * 100, config.br.prizeSplit[2] * 100,
      config.br.prizeSplit[3] * 100, config.br.rakeStartRound,
      config.br.mutatorsPerMatch),
    x, y, w)
end

pages[5] = function(x, y, w)
  local g = love.graphics
  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.85)
  g.printf(([[
RANKED: 2-8 players at one table, everyone resolves against the SAME
roll. The host generates each roll from a fresh seed and broadcasts
both - your game re-derives the roll from the seed and flags any
mismatch. Fair dice, always: skill dice never work here, cosmetics are
just cosmetics.

  - Ante: %d chips. Winnings feed your real wallet.
  - ELO-style rating; leaving mid-match forfeits your bets AND costs
    extra rating. Losing is cheaper than rage-quitting.

CASUAL: private table with friends, join by IP + code. The host picks
starting chips, bet types, round count - even CHAOS MODE with silly
unfair dice (clearly labeled, never ranked). Casual chips are
session-only: your real wallet never notices.

EVERYTHING IS PLAY MONEY. There is nothing to buy with real currency,
no loot boxes, and the shop sells everything at a listed price.]])
    :format(config.ranked.ante), x, y, w)
end

function state:enter()
  demoRng = rngmod.new()
  demoDice = {
    dice_render.newDie(0, 0, 64),
    dice_render.newDie(0, 0, 64),
  }
  demoPoint = nil
  demoText = "Press PRACTICE ROLL to throw the dice."
  demoRolling = false
end

function state:update(dt)
  widgets.beginFrame()
  for _, d in ipairs(demoDice) do d:update(dt) end
end

function state:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  screen.drawFelt()
  screen.header("HOW TO PLAY")

  for i, label in ipairs(tabs) do
    if widgets.button(40 + (i - 1) * 200, 84, 190, 38, label,
      { small = true, color = tab == i and { 0.8, 0.65, 0.2 } or nil }) then
      tab = i
    end
  end

  pages[tab](40, 150, w - 80)

  g.setColor(1, 1, 1, 1)
  if widgets.button(40, h - 70, 150, 44, "BACK") then
    Gamestate.switch(require("states.menu"))
  end
  widgets.endFrame()
end

function state:mousepressed(x, y, b) widgets.pressed(x, y, b) end
function state:keypressed(key)
  if key == "escape" then Gamestate.switch(require("states.menu")) end
end

return state
