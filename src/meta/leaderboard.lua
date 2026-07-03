--------------------------------------------------------------------------
-- src/meta/leaderboard.lua
-- Local leaderboard (persisted in the save) + Steam leaderboard glue.
-- Two boards: ranked rating and biggest single win.
--------------------------------------------------------------------------

local config = require("src.core.config")
local steam  = require("src.steam.steam")

local leaderboard = {}

leaderboard.BOARD_RATING   = "ranked_rating"
leaderboard.BOARD_BIG_WIN  = "biggest_single_win"
local MAX_LOCAL_ENTRIES = 20

local function board(saveData, name)
  saveData.leaderboard[name] = saveData.leaderboard[name] or {}
  return saveData.leaderboard[name]
end

--- Submit a score. Keeps the local board sorted desc and trimmed, and
--- pushes to the matching Steam leaderboard when available.
function leaderboard.submit(saveData, boardName, playerName, score)
  local b = board(saveData, boardName)
  b[#b + 1] = { name = playerName, score = math.floor(score), date = os.date("%Y-%m-%d") }
  table.sort(b, function(x, y) return x.score > y.score end)
  while #b > MAX_LOCAL_ENTRIES do table.remove(b) end
  steam.uploadLeaderboardScore(boardName, math.floor(score)) -- no-op offline
end

function leaderboard.getTop(saveData, boardName, n)
  local b = board(saveData, boardName)
  local out = {}
  for i = 1, math.min(n or 10, #b) do out[i] = b[i] end
  return out
end

--- ELO-ish rating update after a ranked match.
--- players: array of { id, rating, position, netChips } (position 1 = winner).
--- Returns id -> newRating. Pairwise ELO: every player "plays" every other
--- player; beating someone above you pays more. K is split across the
--- (n-1) pairings so total volatility stays ~one K regardless of table size.
function leaderboard.updateRatings(players)
  local K = config.ranked.kFactor
  local n = #players
  local deltas = {}
  for _, p in ipairs(players) do deltas[p.id] = 0 end
  for i = 1, n do
    for j = 1, n do
      if i ~= j then
        local a, b = players[i], players[j]
        -- expected score of a vs b from the logistic curve
        local expected = 1 / (1 + 10 ^ ((b.rating - a.rating) / 400))
        local actual
        if a.position < b.position then actual = 1
        elseif a.position > b.position then actual = 0
        else actual = 0.5 end
        deltas[a.id] = deltas[a.id] + (K / (n - 1)) * (actual - expected)
      end
    end
  end
  local newRatings = {}
  for _, p in ipairs(players) do
    newRatings[p.id] = math.floor(p.rating + deltas[p.id] + 0.5)
  end
  return newRatings
end

--- Rating penalty for disconnecting mid-match. Applied ON TOP of being
--- scored last, so rage-quitting is strictly worse than losing.
function leaderboard.disconnectPenalty(rating)
  return rating - config.ranked.disconnectPenalty
end

return leaderboard
