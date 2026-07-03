--------------------------------------------------------------------------
-- src/net/protocol.lua
-- Every packet type in the game, with its payload shape documented, plus
-- the shared serialization setup (bitser over sock.lua/lua-enet).
--
-- Transport-agnostic on purpose: sock.lua carries these today; a Steam
-- P2P bridge or a dedicated server can carry the same packets later.
--------------------------------------------------------------------------

local protocol = {}

-- Packet types. sock.lua dispatches on the event name string; keep them
-- short since they ride in every packet.
protocol.PKT = {
  JOIN         = "join",         -- c->s { name }
  LOBBY_STATE  = "lobby",        -- s->c full snapshot { players = {{id,name,chips,ready}}, rules, joinCode, mode }
  START        = "start",        -- s->c { rules, mode } match begins
  BETS_OPEN    = "betsopen",     -- s->c { lockIn = seconds } betting window opened
  PLACE_BET    = "placebet",     -- c->s intent { betId, amount } (server validates!)
  BET_ACCEPTED = "betok",        -- s->c { playerId, betId, amount, chips } authoritative echo
  ROLL_RESULT  = "roll",         -- s->c { seed, dice, sum, phase, point, rollNumber }
  SETTLE       = "settle",       -- s->c { payouts = {id=amount}, pool, jackpotPayout, round }
  SYNC_WALLET  = "wallet",       -- s->c delta { playerId, chips }
  CHAT         = "chat",         -- both { name, text }
  PLAYER_LEFT  = "left",         -- s->c { playerId, name, forfeited }
  JACKPOT_HIT  = "jackpot",      -- s->c { playerBets..., amount } (celebration cue)
  MATCH_END    = "matchend",     -- s->c { standings = {{id,name,chips,position,netChips,rating}} }
  ERROR        = "err",          -- s->c { message }
}

--- Attach bitser serialization to a sock server or client. Falls back to
--- sock's default (which also uses bitser if present) when require fails.
function protocol.setupSerialization(sockObj)
  local ok, bitser = pcall(require, "lib.bitser")
  if ok then
    sockObj:setSerialization(bitser.dumps, bitser.loads)
  else
    print("[net] bitser unavailable; using sock defaults")
  end
end

--- Register every packet name as a valid event schema (sock supports
--- ordered schemas; we send plain tables so this is just registration).
function protocol.registerAll(sockObj)
  -- sock.lua accepts arbitrary event names by default; nothing to do.
  -- TODO(net-opt): define sock schemas per packet to strip keys from the
  -- wire (sock:setSchema) once the payloads are frozen - saves ~30% bytes.
end

return protocol
