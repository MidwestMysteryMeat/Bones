--------------------------------------------------------------------------
-- src/core/economy.lua
-- Single source of truth for chips. PvE and PvP feed ONE persistent
-- wallet; Casual is walled off behind session wallets that never touch it.
-- The PvE progressive jackpot pool also lives here (PvP pools are
-- server-held, see src/net/server.lua).
--
-- All mutation goes through debit/credit so lifetime stats, biggest-win
-- tracking and autosave triggers stay consistent.
--------------------------------------------------------------------------

local config = require("src.core.config")

local economy = {}

economy.data = nil          -- bound slice of the save table (see save.lua)
economy.onChanged = nil     -- optional callback(reason) -> autosave / UI
economy.session = {}        -- casual session wallets: playerId -> chips

--- Bind to loaded save data. Must be called before anything else.
function economy.init(saveData)
  economy.data = saveData
  saveData.wallet         = saveData.wallet or config.economy.startingWallet
  saveData.lifetimeEarned = saveData.lifetimeEarned or 0
  saveData.biggestWin     = saveData.biggestWin or { amount = 0, label = "" }
  saveData.jackpotPool    = saveData.jackpotPool or config.jackpot.pveSeedStart
end

local function changed(reason)
  if economy.onChanged then economy.onChanged(reason) end
end

function economy.getWallet()
  return economy.data.wallet
end

function economy.canAfford(amount)
  return economy.data.wallet >= amount
end

--- Take chips out of the wallet. Returns false if it would go negative.
function economy.debit(amount, reason)
  amount = math.floor(amount)
  if amount < 0 or economy.data.wallet < amount then return false end
  economy.data.wallet = economy.data.wallet - amount
  changed(reason or "debit")
  return true
end

--- Add chips to the wallet. `isWinnings` counts toward lifetime earnings
--- (which gate rarity unlocks) and biggest-win tracking.
function economy.credit(amount, reason, isWinnings, winLabel)
  amount = math.floor(amount)
  if amount <= 0 then return end
  economy.data.wallet = economy.data.wallet + amount
  if isWinnings then
    economy.data.lifetimeEarned = economy.data.lifetimeEarned + amount
    if amount > economy.data.biggestWin.amount then
      economy.data.biggestWin = { amount = amount, label = winLabel or reason or "" }
    end
  end
  changed(reason or "credit")
end

-- PvE jackpot pool ---------------------------------------------------------

function economy.getJackpotPool()
  return economy.data.jackpotPool
end

function economy.setJackpotPool(v)
  economy.data.jackpotPool = math.floor(v)
  changed("jackpot")
end

-- Casual session wallets (never persisted, never mix with the real wallet) --

function economy.sessionStart(playerId, chips)
  economy.session[playerId] = chips or config.economy.casualStartChips
end

function economy.sessionGet(playerId)
  return economy.session[playerId] or 0
end

function economy.sessionAdjust(playerId, delta)
  economy.session[playerId] = (economy.session[playerId] or 0) + delta
end

function economy.sessionEnd(playerId)
  economy.session[playerId] = nil
end

return economy
