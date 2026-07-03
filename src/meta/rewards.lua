--------------------------------------------------------------------------
-- src/meta/rewards.lua
-- Daily login rewards, win-streak bonuses, achievements.
-- Play-money engagement only: the daily streak resets on a missed day but
-- nothing punishes you while you're away, and there are no timers.
--------------------------------------------------------------------------

local config  = require("src.core.config")
local economy = require("src.core.economy")
local steam   = require("src.steam.steam")

local rewards = {}

-- Daily login ---------------------------------------------------------------

local function today()
  return math.floor(os.time() / 86400)
end

--- Check the daily reward. Returns nil if already claimed today, else
--- { day = streakDay, chips = amount } after granting it.
function rewards.claimDaily(saveData)
  local t = today()
  if saveData.lastDailyStamp == t then return nil end
  if saveData.lastDailyStamp == t - 1 then
    saveData.dailyStreak = saveData.dailyStreak + 1  -- consecutive day
  else
    saveData.dailyStreak = 1                          -- missed a day: reset
  end
  saveData.lastDailyStamp = t
  local curve = config.rewards.daily
  local chips = curve[math.min(saveData.dailyStreak, #curve)]
  economy.credit(chips, "daily_reward")
  return { day = saveData.dailyStreak, chips = chips }
end

-- Win streak bonuses ------------------------------------------------------------

--- Bonus chips for the current win streak (0 if streak < 2).
function rewards.streakBonus(streak)
  if streak < 2 then return 0 end
  return math.min(streak * config.rewards.winStreakBonusPerWin,
    config.rewards.winStreakBonusCap)
end

-- Achievements ----------------------------------------------------------------------
-- Each achievement has an id (mirrored in Steamworks), a label, and a
-- description shown in the results/summary UI.

rewards.achievements = {
  { id = "FIRST_ROLL",     label = "Bones Rattle",     desc = "Roll the dice for the first time." },
  { id = "FIRST_JACKPOT",  label = "Boxcars Baby",     desc = "Hit the progressive jackpot." },
  { id = "TIER_10",        label = "House of Bones",   desc = "Survive to PvE Tier 10." },
  { id = "COMEBACK",       label = "Dead Man's Bounce", desc = "Advance a tier after dropping under 10% bankroll." },
  { id = "BIG_WIN",        label = "High Roller",      desc = "Win 1,000+ chips on a single roll." },
  { id = "STREAK_5",       label = "Hot Hand",         desc = "Win 5 rolls in a row." },
  { id = "WIN_COMMON",     label = "Chalk It Up",      desc = "Win a run round with a Common die equipped." },
  { id = "WIN_UNCOMMON",   label = "Green Means Go",   desc = "Win a run round with an Uncommon die equipped." },
  { id = "WIN_RARE",       label = "Blue Bloods",      desc = "Win a run round with a Rare die equipped." },
  { id = "WIN_EPIC",       label = "Purple Reign",     desc = "Win a run round with an Epic die equipped." },
  { id = "WIN_LEGENDARY",  label = "Golden Bones",     desc = "Win a run round with a Legendary die equipped." },
  { id = "BR_WIN",         label = "Last Bones Standing", desc = "Win a Boneyard battle royale." },
  { id = "BR_REAPER",      label = "The Reaper",       desc = "Pick off 3 players in one Boneyard match." },
  { id = "CHAIN_MAX",      label = "Chain Lightning",  desc = "Max out your damage chain in the Boneyard." },
  { id = "FEVER",          label = "Dice Fever",       desc = "Reach a full fever chain in a Solo Run." },
}

rewards.achievementsById = {}
for _, a in ipairs(rewards.achievements) do rewards.achievementsById[a.id] = a end

--- Unlock an achievement (idempotent). Returns the achievement table the
--- first time so the UI can toast it, nil after that.
function rewards.unlock(saveData, id)
  if saveData.achievements[id] then return nil end
  local a = rewards.achievementsById[id]
  if not a then return nil end
  saveData.achievements[id] = true
  steam.unlockAchievement(id) -- no-op offline
  return a
end

--- Convenience: rarity-win achievements from an equipped loadout.
function rewards.unlockRarityWins(saveData, equippedIds)
  local catalog = require("src.meta.dice_catalog")
  local toasts = {}
  for _, id in ipairs(equippedIds or {}) do
    local d = catalog.byId[id]
    if d then
      local a = rewards.unlock(saveData, "WIN_" .. d.rarity:upper())
      if a then toasts[#toasts + 1] = a end
    end
  end
  return toasts
end

return rewards
