--------------------------------------------------------------------------
-- src/meta/shop.lua
-- Purchase + equip logic. Purchases are deterministic direct buys at a
-- listed price - no gacha, no loot boxes, no real money.
--------------------------------------------------------------------------

local config  = require("src.core.config")
local catalog = require("src.meta.dice_catalog")
local unlocks = require("src.meta.unlocks")
local economy = require("src.core.economy")

local shop = {}

function shop.owns(saveData, dieId)
  return saveData.ownedDice[dieId] == true
end

--- Can the player buy this die right now? Returns ok, reason.
function shop.canBuy(saveData, dieId)
  local d = catalog.byId[dieId]
  if not d then return false, "unknown die" end
  if shop.owns(saveData, dieId) then return false, "already owned" end
  if not unlocks.rarityUnlocked(saveData, d.rarity) then
    return false, d.rarity .. " is still locked"
  end
  if not economy.canAfford(d.price) then return false, "not enough chips" end
  return true
end

--- Buy a die. Returns ok, reason.
function shop.buy(saveData, dieId)
  local ok, reason = shop.canBuy(saveData, dieId)
  if not ok then return false, reason end
  local d = catalog.byId[dieId]
  economy.debit(d.price, "shop:" .. dieId)
  saveData.ownedDice[dieId] = true
  return true
end

--- Equip a die into the loadout (up to config.pve.loadoutSize).
function shop.equip(saveData, dieId)
  if not shop.owns(saveData, dieId) then return false, "not owned" end
  for _, id in ipairs(saveData.equipped) do
    if id == dieId then return false, "already equipped" end
  end
  if #saveData.equipped >= config.pve.loadoutSize then
    return false, "loadout full (unequip something first)"
  end
  saveData.equipped[#saveData.equipped + 1] = dieId
  return true
end

function shop.unequip(saveData, dieId)
  for i, id in ipairs(saveData.equipped) do
    if id == dieId then
      if #saveData.equipped == 1 then
        return false, "keep at least one die equipped"
      end
      table.remove(saveData.equipped, i)
      return true
    end
  end
  return false, "not equipped"
end

function shop.isEquipped(saveData, dieId)
  for _, id in ipairs(saveData.equipped) do
    if id == dieId then return true end
  end
  return false
end

--- Daily featured rotation: a deterministic, date-seeded pick so every
--- player sees the same rotation and it changes at midnight.
function shop.featuredToday()
  local dayNumber = math.floor(os.time() / 86400)
  -- Simple LCG stepped from the day number; stable across platforms.
  local state = (dayNumber * 16807) % 2147483647
  local pool = {}
  for _, d in ipairs(catalog.dice) do
    if d.price and d.price > 0 then pool[#pool + 1] = d end
  end
  local featured = {}
  for _ = 1, math.min(config.shop.featuredCount, #pool) do
    state = (state * 16807) % 2147483647
    local idx = (state % #pool) + 1
    featured[#featured + 1] = table.remove(pool, idx)
  end
  return featured
end

return shop
