--------------------------------------------------------------------------
-- src/meta/dice_catalog.lua
-- Every die in the game: id, rarity, cosmetic look, and (optionally) a
-- PvE-only skill modifier. Also builds the engine hook table from an
-- equipped loadout.
--
-- HARD RULE: hooks built here are ONLY ever passed to PvE engine tables
-- (and clearly-labeled "chaos" casual lobbies). Ranked PvP tables are
-- created with no hooks - see src/net/server.lua.
--------------------------------------------------------------------------

local config = require("src.core.config")

local catalog = {}

-- Cosmetic = body color, pip color, optional glow color for the renderer.
local function die(id, name, rarity, body, pip, modifier, glow)
  return {
    id = id, name = name, rarity = rarity,
    cosmetic = { body = body, pip = pip, glow = glow },
    modifier = modifier, -- { type = ..., plus type-specific params } or nil
    price = config.shop.prices[rarity],
  }
end

catalog.dice = {
  -- Starter (free, no modifier)
  die("starter_ivory", "Ivory Starter", "common",
    { 0.95, 0.93, 0.88 }, { 0.15, 0.15, 0.18 }),

  -- Common ---------------------------------------------------------------
  die("cherry_red", "Cherry Red", "common",
    { 0.85, 0.15, 0.18 }, { 0.98, 0.96, 0.92 },
    { type = "weighted", face = 6 }),
  die("night_blue", "Night Blue", "common",
    { 0.12, 0.20, 0.45 }, { 0.95, 0.95, 1.0 },
    { type = "rerollLowest" }),
  die("bar_brass", "Bar Brass", "common",
    { 0.62, 0.50, 0.22 }, { 0.10, 0.08, 0.05 },
    { type = "loaded7" }),

  -- Uncommon -------------------------------------------------------------
  die("jade_luck", "Jade Luck", "uncommon",
    { 0.10, 0.55, 0.35 }, { 0.95, 1.0, 0.95 },
    { type = "pointGuard" }),
  die("smoke_quartz", "Smoke Quartz", "uncommon",
    { 0.30, 0.28, 0.33 }, { 0.90, 0.85, 1.0 },
    { type = "weighted", face = 5 }),
  die("copper_top", "Copper Top", "uncommon",
    { 0.72, 0.40, 0.20 }, { 0.15, 0.10, 0.08 },
    { type = "goldenTouch" }),

  -- Rare -----------------------------------------------------------------
  die("royal_violet", "Royal Violet", "rare",
    { 0.42, 0.15, 0.60 }, { 1.0, 0.92, 0.55 },
    { type = "loaded7" }, { 0.6, 0.3, 0.9 }),
  die("blood_bone", "Blood Bone", "rare",
    { 0.90, 0.88, 0.84 }, { 0.65, 0.08, 0.08 },
    { type = "streakbreaker" }),
  die("deep_current", "Deep Current", "rare",
    { 0.05, 0.35, 0.55 }, { 0.70, 0.95, 1.0 },
    { type = "pointGuard" }, { 0.2, 0.7, 1.0 }),

  -- Epic -------------------------------------------------------------------
  die("gilded_skull", "Gilded Skull", "epic",
    { 0.90, 0.75, 0.25 }, { 0.20, 0.15, 0.05 },
    { type = "goldenTouch" }, { 1.0, 0.85, 0.3 }),
  die("void_walker", "Void Walker", "epic",
    { 0.08, 0.06, 0.12 }, { 0.85, 0.30, 1.0 },
    { type = "weighted", face = 6 }, { 0.6, 0.2, 1.0 }),

  -- Legendary --------------------------------------------------------------
  die("the_house_cut", "The House Cut", "legendary",
    { 0.05, 0.05, 0.06 }, { 1.0, 0.84, 0.0 },
    { type = "loaded7" }, { 1.0, 0.84, 0.0 }),
  die("phoenix_pip", "Phoenix Pip", "legendary",
    { 0.85, 0.30, 0.05 }, { 1.0, 0.95, 0.70 },
    { type = "streakbreaker" }, { 1.0, 0.5, 0.1 }),
}

catalog.byId = {}
for _, d in ipairs(catalog.dice) do catalog.byId[d.id] = d end

catalog.rarities = { "common", "uncommon", "rare", "epic", "legendary" }
catalog.rarityColors = {
  common    = { 0.75, 0.75, 0.75 },
  uncommon  = { 0.30, 0.80, 0.35 },
  rare      = { 0.25, 0.55, 1.00 },
  epic      = { 0.70, 0.30, 0.95 },
  legendary = { 1.00, 0.70, 0.10 },
}

--------------------------------------------------------------------------
-- Modifier implementations. Each returns partial hooks that read their
-- strength from config.modifiers[type][rarity]. `ctx` is the PvE run
-- context: { rng, lossStreak, rerollCharges } maintained by src/modes/pve.lua.
--------------------------------------------------------------------------

local sevenCombos = { { 1, 6 }, { 2, 5 }, { 3, 4 }, { 4, 3 }, { 5, 2 }, { 6, 1 } }

local builders = {
  -- Shift probability toward a chosen face: each die independently snaps
  -- to the target face with probability p.
  weighted = function(mod, rarity, ctx)
    local p = config.modifiers.weighted[rarity]
    return {
      applyPostRoll = function(dice, tbl)
        for i = 1, #dice do
          if tbl.rng:chance(p) then dice[i] = mod.face end
        end
        return dice
      end,
    }
  end,

  -- Once per roll, auto-reroll the lowest die if it's dragging the sum
  -- down. Limited charges per tier (restocked by pve.lua).
  rerollLowest = function(mod, rarity, ctx)
    return {
      applyPostRoll = function(dice, tbl)
        if (ctx.rerollCharges or 0) <= 0 then return dice end
        local lo = 1
        for i = 2, #dice do if dice[i] < dice[lo] then lo = i end end
        if dice[lo] <= 2 then
          ctx.rerollCharges = ctx.rerollCharges - 1
          dice[lo] = tbl.rng:rollDie(6)
        end
        return dice
      end,
    }
  end,

  -- Boost the odds of a 7 during the come-out only (helps Pass Line).
  loaded7 = function(mod, rarity, ctx)
    local p = config.modifiers.loaded7[rarity]
    return {
      applyPostRoll = function(dice, tbl)
        if tbl.phase == "comeout" and #dice == 2 and tbl.rng:chance(p) then
          local combo = tbl.rng:pick(sevenCombos)
          dice[1], dice[2] = combo[1], combo[2]
        end
        return dice
      end,
    }
  end,

  -- Reduce the chance of a seven-out: when a 7 lands during the point
  -- phase, chance p to reroll the pair once (it can still be a 7).
  pointGuard = function(mod, rarity, ctx)
    local p = config.modifiers.pointGuard[rarity]
    return {
      applyPostRoll = function(dice, tbl)
        if tbl.phase == "point" and #dice == 2
          and dice[1] + dice[2] == 7 and tbl.rng:chance(p) then
          dice[1], dice[2] = tbl.rng:rollDie(6), tbl.rng:rollDie(6)
        end
        return dice
      end,
    }
  end,

  -- Flat bonus multiplier on Pass Line winnings.
  goldenTouch = function(mod, rarity, ctx)
    local bonus = config.modifiers.goldenTouch[rarity]
    return {
      modifyPayout = function(bet, winnings)
        if bet.betId == "pass" then
          return math.floor(winnings * (1 + bonus))
        end
        return winnings
      end,
    }
  end,

  -- Pity mechanic: after N pass-line losses in a row, force the next
  -- come-out to be a natural 7. pve.lua maintains ctx.lossStreak.
  streakbreaker = function(mod, rarity, ctx)
    local maxLosses = config.modifiers.streakbreaker[rarity]
    return {
      applyPostRoll = function(dice, tbl)
        if tbl.phase == "comeout" and #dice == 2
          and (ctx.lossStreak or 0) >= maxLosses then
          local combo = tbl.rng:pick(sevenCombos)
          dice[1], dice[2] = combo[1], combo[2]
          ctx.lossStreak = 0
        end
        return dice
      end,
    }
  end,
}

--- Build a combined engine hook table from an equipped loadout.
--- equippedIds: array of die ids. ctx: PvE run context table.
--- Post-roll hooks chain in loadout order; payout hooks compose.
function catalog.buildHooks(equippedIds, ctx)
  local posts, payouts = {}, {}
  for _, id in ipairs(equippedIds or {}) do
    local d = catalog.byId[id]
    if d and d.modifier then
      local hooks = builders[d.modifier.type](d.modifier, d.rarity, ctx)
      if hooks.applyPostRoll then posts[#posts + 1] = hooks.applyPostRoll end
      if hooks.modifyPayout then payouts[#payouts + 1] = hooks.modifyPayout end
    end
  end
  if #posts == 0 and #payouts == 0 then return nil end
  return {
    applyPostRoll = function(dice, tbl)
      for _, fn in ipairs(posts) do dice = fn(dice, tbl) or dice end
      return dice
    end,
    modifyPayout = function(bet, winnings)
      for _, fn in ipairs(payouts) do winnings = fn(bet, winnings) or winnings end
      return winnings
    end,
  }
end

--- Human-readable modifier description for the shop / loadout UI.
function catalog.describeModifier(d)
  if not d.modifier then return "Cosmetic only" end
  local m, r = d.modifier, d.rarity
  local t = m.type
  if t == "weighted" then
    return ("Weighted: %d%% chance per die to land on %d (PvE)"):format(
      config.modifiers.weighted[r] * 100, m.face)
  elseif t == "rerollLowest" then
    return ("Reroll Lowest: %d charges per tier (PvE)"):format(
      config.modifiers.rerollLowest[r])
  elseif t == "loaded7" then
    return ("Loaded 7: +%d%% seven odds on the come-out (PvE)"):format(
      config.modifiers.loaded7[r] * 100)
  elseif t == "pointGuard" then
    return ("Point Guard: %d%% chance to shrug off a seven-out (PvE)"):format(
      config.modifiers.pointGuard[r] * 100)
  elseif t == "goldenTouch" then
    return ("Golden Touch: +%d%% on Pass Line wins (PvE)"):format(
      config.modifiers.goldenTouch[r] * 100)
  elseif t == "streakbreaker" then
    return ("Streakbreaker: never lose more than %d in a row (PvE)"):format(
      config.modifiers.streakbreaker[r])
  end
  return "???"
end

return catalog
