--------------------------------------------------------------------------
-- src/steam/steam.lua
-- luasteam abstraction. EVERY Steam call in the game goes through here,
-- and every function no-ops safely (with a one-time log line) when Steam
-- isn't running, so `love .` works in dev and the game ships offline-safe.
--
-- Requires luasteam (https://github.com/uspgamedev/luasteam): drop
-- luasteam.dll / steam_api64.dll next to the exe for the Steam build.
--------------------------------------------------------------------------

local steam = {}

local okLib, luasteam = pcall(require, "luasteam")
steam.available = false
local warned = {}

local function warnOnce(what)
  if not warned[what] then
    warned[what] = true
    print("[steam] " .. what .. " skipped (Steam not available)")
  end
end

function steam.init()
  if not okLib then
    warnOnce("init: luasteam not found")
    return false
  end
  local ok = pcall(function() return luasteam.init() end)
  steam.available = ok and luasteam.init and true or false
  if steam.available then
    print("[steam] initialized")
  else
    warnOnce("init failed (client not running?)")
  end
  return steam.available
end

--- Call once per frame: pumps Steam callbacks.
function steam.update()
  if not steam.available then return end
  pcall(luasteam.runCallbacks)
end

function steam.shutdown()
  if not steam.available then return end
  pcall(luasteam.shutdown)
end

-- Achievements + stats ------------------------------------------------------

function steam.unlockAchievement(id)
  if not steam.available then return warnOnce("achievement " .. id) end
  pcall(function()
    luasteam.userStats.setAchievement(id)
    luasteam.userStats.storeStats()
  end)
end

function steam.setStat(name, value)
  if not steam.available then return warnOnce("stat " .. name) end
  pcall(function()
    luasteam.userStats.setStatInt(name, value)
    luasteam.userStats.storeStats()
  end)
end

-- Leaderboards -----------------------------------------------------------------

function steam.uploadLeaderboardScore(boardName, score)
  if not steam.available then return warnOnce("leaderboard " .. boardName) end
  pcall(function()
    luasteam.userStats.findLeaderboard(boardName, function(data, err)
      if not err and data and data.steamLeaderboard then
        luasteam.userStats.uploadLeaderboardScore(
          data.steamLeaderboard, "KeepBest", score)
      end
    end)
  end)
end

-- Rich presence -------------------------------------------------------------------

function steam.setRichPresence(key, value)
  if not steam.available then return end
  pcall(function() luasteam.friends.setRichPresence(key, value) end)
end

--- Convenience used by the states: "At a Ranked Table", "Solo Run - Tier 4"...
function steam.presence(text)
  steam.setRichPresence("status", text)
end

-- Lobbies ---------------------------------------------------------------------------
-- TODO(steam-p2p): when Steam is present, prefer Steam lobbies + P2P as the
-- transport instead of raw enet. protocol.lua is transport-agnostic (plain
-- serialized packets), so the swap is: create/join lobby here, then bridge
-- sendP2P/readP2P into the same handler tables sock.lua feeds. Fallback to
-- enet IP:port + join code (already implemented) when Steam is absent.

function steam.createLobby(maxPlayers, callback)
  if not steam.available then
    warnOnce("createLobby")
    if callback then callback(nil, "steam unavailable") end
    return
  end
  pcall(function()
    luasteam.matchmaking.createLobby("public", maxPlayers, function(data, err)
      if callback then callback(err == nil and data.lobbyID or nil, err) end
    end)
  end)
end

function steam.joinLobby(lobbyID, callback)
  if not steam.available then
    warnOnce("joinLobby")
    if callback then callback(false, "steam unavailable") end
    return
  end
  pcall(function()
    luasteam.matchmaking.joinLobby(lobbyID, function(data, err)
      if callback then callback(err == nil, err) end
    end)
  end)
end

function steam.inviteFriend(lobbyID)
  if not steam.available then return warnOnce("inviteFriend") end
  pcall(function() luasteam.friends.activateGameOverlayInviteDialog(lobbyID) end)
end

-- Cloud -----------------------------------------------------------------------------
-- LÖVE's save directory is synced by Steam Auto-Cloud (configure the save
-- path in the Steamworks partner site). Nothing to do at runtime, but the
-- hook exists in case manual RemoteStorage writes are wanted later.
function steam.cloudSync()
  if not steam.available then return end
  -- TODO(cloud): manual ISteamRemoteStorage.fileWrite of bones_save.dat if
  -- Auto-Cloud turns out to be insufficient.
end

return steam
