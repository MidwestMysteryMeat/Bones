--------------------------------------------------------------------------
-- src/meta/unlocks.lua
-- Rarity unlock gating: a rarity opens up once BOTH lifetime chips earned
-- and best PvE tier reached pass the thresholds in config.unlocks.
-- Also feeds the "almost unlocked" progress bars in the shop UI.
--------------------------------------------------------------------------

local config = require("src.core.config")

local unlocks = {}

--- Is this rarity purchasable for the current save?
function unlocks.rarityUnlocked(saveData, rarity)
  local gate = config.unlocks[rarity]
  if not gate then return false end
  return saveData.lifetimeEarned >= gate.chips and saveData.bestTier >= gate.tier
end

--- Progress toward a locked rarity, for UI bars. Returns
--- { unlocked, chipsFrac, tierFrac, overallFrac, gate }.
function unlocks.progress(saveData, rarity)
  local gate = config.unlocks[rarity]
  local chipsFrac = gate.chips == 0 and 1
    or math.min(1, saveData.lifetimeEarned / gate.chips)
  local tierFrac = gate.tier == 0 and 1
    or math.min(1, saveData.bestTier / gate.tier)
  return {
    unlocked = unlocks.rarityUnlocked(saveData, rarity),
    chipsFrac = chipsFrac, tierFrac = tierFrac,
    overallFrac = math.min(chipsFrac, tierFrac),
    gate = gate,
  }
end

--- Called after a run ends: records the best tier reached.
--- Returns a list of rarities that just unlocked (for the reveal moment).
function unlocks.recordTier(saveData, tierReached)
  local newly = {}
  local before = {}
  for rarity in pairs(config.unlocks) do
    before[rarity] = unlocks.rarityUnlocked(saveData, rarity)
  end
  if tierReached > (saveData.bestTier or 0) then
    saveData.bestTier = tierReached
  end
  for rarity in pairs(config.unlocks) do
    if not before[rarity] and unlocks.rarityUnlocked(saveData, rarity) then
      newly[#newly + 1] = rarity
    end
  end
  return newly
end

return unlocks
