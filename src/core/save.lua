--------------------------------------------------------------------------
-- src/core/save.lua
-- Persistence: bitser + love.filesystem, versioned with a migration stub.
-- Autosave on meaningful events (purchase, run end, match end) and quit.
-- Backed up to Steam Cloud through steam.lua when available.
--
-- bitser needs LuaJIT's FFI (always present under LÖVE). When it's not
-- available (headless dev under plain Lua) we fall back to a tiny plain
-- text serializer so the module still loads.
--------------------------------------------------------------------------

local config = require("src.core.config")

local hasLove = type(love) == "table" and love.filesystem ~= nil
local okBitser, bitser = pcall(require, "lib.bitser")

local save = {}
save.FILENAME = "bones_save.dat"
save.data = nil

-- Fallback serializer (dev only): serializes plain tables of
-- numbers/strings/booleans. Not fast, not safe for untrusted input.
local function plainSerialize(t, out, indent)
  out[#out + 1] = "{\n"
  for k, v in pairs(t) do
    out[#out + 1] = string.rep(" ", indent + 2) .. "[" .. string.format("%q", tostring(k)) .. "]="
    if type(k) == "number" then out[#out] = string.rep(" ", indent + 2) .. "[" .. k .. "]=" end
    local tv = type(v)
    if tv == "table" then
      plainSerialize(v, out, indent + 2)
    elseif tv == "string" then
      out[#out + 1] = string.format("%q", v)
    else
      out[#out + 1] = tostring(v)
    end
    out[#out + 1] = ",\n"
  end
  out[#out + 1] = string.rep(" ", indent) .. "}"
end

local function dumps(t)
  if okBitser then return bitser.dumps(t) end
  local out = { "return " }
  plainSerialize(t, out, 0)
  return table.concat(out)
end

local function loads(s)
  if okBitser then return bitser.loads(s) end
  local chunk = assert((loadstring or load)(s))
  return chunk()
end

--- A brand-new save.
function save.defaults()
  return {
    saveVersion    = config.SAVE_VERSION,
    wallet         = config.economy.startingWallet,
    lifetimeEarned = 0,
    biggestWin     = { amount = 0, label = "" },
    jackpotPool    = config.jackpot.pveSeedStart,
    ownedDice      = { starter_ivory = true },  -- everyone owns the starter die
    equipped       = { "starter_ivory" },       -- loadout, up to pve.loadoutSize
    bestTier       = 0,
    runsPlayed     = 0,
    achievements   = {},                        -- id -> true
    dailyStreak    = 0,
    lastDailyStamp = 0,                         -- day number of last claim
    winStreakBest  = 0,
    rating         = config.ranked.baseRating,
    leaderboard    = {},                        -- local scores, see leaderboard.lua
    settings       = { musicVol = 0.7, sfxVol = 1.0, screenshake = true, fullscreen = false },
  }
end

--- Migrate an old save forward one version at a time.
local function migrate(data)
  local v = data.saveVersion or 0
  -- TODO: when SAVE_VERSION bumps to 2, add:
  --   if v < 2 then data.newField = default; v = 2 end
  -- Each step mutates `data` in place and advances v; never skip versions.
  data.saveVersion = config.SAVE_VERSION
  return data
end

--- Load (or create) the save. Returns the live data table.
function save.load()
  if hasLove and love.filesystem.getInfo(save.FILENAME) then
    local raw = love.filesystem.read(save.FILENAME)
    local ok, data = pcall(loads, raw)
    if ok and type(data) == "table" then
      save.data = migrate(data)
    else
      print("[save] corrupt save, starting fresh: " .. tostring(data))
      save.data = save.defaults()
    end
  else
    save.data = save.defaults()
  end
  -- Fill any fields added since this save was written.
  for k, v in pairs(save.defaults()) do
    if save.data[k] == nil then save.data[k] = v end
  end
  return save.data
end

--- Write to disk (and nudge Steam Cloud, which syncs the save directory).
function save.write()
  if not save.data then return end
  if not hasLove then return end -- headless tests never persist
  local ok, err = pcall(function()
    love.filesystem.write(save.FILENAME, dumps(save.data))
  end)
  if not ok then print("[save] write failed: " .. tostring(err)) end
end

--- Autosave entry point: cheap enough to call on every meaningful event.
function save.autosave(reason)
  save.write()
end

return save
