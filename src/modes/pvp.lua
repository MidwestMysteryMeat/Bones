--------------------------------------------------------------------------
-- src/modes/pvp.lua
-- Ranked table logic, CLIENT side. The server (src/net/server.lua) is
-- authoritative: it rolls, settles, and broadcasts. This module:
--   * verifies fair dice (re-derives every roll from the broadcast seed)
--   * applies rating changes at match end
--   * feeds ranked results into wallet + leaderboards
-- Fair dice only: no hooks, no skill dice, cosmetics are visual-only here.
--------------------------------------------------------------------------

local config      = require("src.core.config")
local rngmod      = require("src.core.rng")
local economy     = require("src.core.economy")
local leaderboard = require("src.meta.leaderboard")
local steam       = require("src.steam.steam")

local pvp = {}

--- Fair-dice verification: the server broadcasts { seed, dice } for every
--- roll. Any client can re-derive the dice from the seed with the exact
--- same generator the server used. Returns true if the roll is honest.
function pvp.verifyRoll(seed, dice)
  local rng = rngmod.new(seed)
  for i = 1, #dice do
    if rng:rollDie(6) ~= dice[i] then return false end
  end
  return true
end

--- Ranked table ruleset: fair RNG, all bets, ranked limits, no hooks EVER.
function pvp.ruleset()
  return {
    limits = { min = config.table.defaultMinBet, max = config.table.defaultMaxBet },
    jackpot = true,
    -- hooks deliberately absent: rule 2, skill dice never touch PvP
  }
end

--- Apply a finished ranked match to the local save.
--- result = { position, players = {{id, name, rating, position, netChips}...},
---            myId, netChips, disconnected }
--- Returns { oldRating, newRating, delta }.
function pvp.applyMatchResult(saveData, playerName, result)
  local old = saveData.rating or config.ranked.baseRating

  local newRatings = leaderboard.updateRatings(result.players)
  local newRating = newRatings[result.myId] or old
  if result.disconnected then
    newRating = leaderboard.disconnectPenalty(newRating)
  end
  saveData.rating = newRating

  -- Ranked chips feed the one persistent wallet (rule: PvE + PvP share it).
  if result.netChips > 0 then
    economy.credit(result.netChips, "ranked_win", true,
      ("ranked table, position %d"):format(result.position))
  end
  -- Losses were already debited when the ante/bets were placed.

  leaderboard.submit(saveData, leaderboard.BOARD_RATING, playerName, newRating)
  if result.netChips > 0 then
    leaderboard.submit(saveData, leaderboard.BOARD_BIG_WIN, playerName, result.netChips)
  end
  steam.presence("In the Lobby")

  return { oldRating = old, newRating = newRating, delta = newRating - old }
end

--- Can this save afford to sit at a ranked table?
function pvp.canQueue(saveData)
  if not economy.canAfford(config.ranked.ante) then
    return false, ("ranked ante is %d chips"):format(config.ranked.ante)
  end
  return true
end

return pvp
