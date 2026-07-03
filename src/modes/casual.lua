--------------------------------------------------------------------------
-- src/modes/casual.lua
-- Custom Match: private lobby, host sets the rules, zero ranked impact.
-- Chips here are session-only (economy.session*) and never touch the
-- persistent wallet.
--------------------------------------------------------------------------

local config = require("src.core.config")

local casual = {}

--- Default host-configurable rules (edited by lobby_ui checkboxes/sliders).
function casual.defaultRules()
  local allowed = {}
  for _, def in ipairs(config.bets) do allowed[def.id] = true end
  return {
    startChips = config.economy.casualStartChips,
    minBet     = config.table.defaultMinBet,
    maxBet     = config.table.defaultMaxBet,
    allowedBets = allowed,     -- checkbox per bet type in the lobby UI
    rounds     = 10,           -- come-out-to-resolution cycles per match
    jackpot    = true,
    chaos      = false,        -- allows silly non-fair dice, clearly labeled
  }
end

--- Turn host rules into an engine ruleset. Chaos mode is the ONLY
--- multiplayer path that ever gets hooks, and the lobby UI labels it
--- loudly; it can never be ranked.
function casual.toRuleset(rules, chaosHooks)
  return {
    limits = { min = rules.minBet, max = rules.maxBet },
    allowedBets = rules.allowedBets,
    jackpot = rules.jackpot,
    hooks = (rules.chaos and chaosHooks) or nil,
  }
end

--- Validate host-entered rules (clamps rather than rejects).
function casual.sanitize(rules)
  rules.startChips = math.max(100, math.floor(rules.startChips or 1000))
  rules.minBet = math.max(1, math.floor(rules.minBet or 5))
  rules.maxBet = math.max(rules.minBet, math.floor(rules.maxBet or 500))
  rules.rounds = math.min(50, math.max(1, math.floor(rules.rounds or 10)))
  local any = false
  for _, on in pairs(rules.allowedBets) do any = any or on end
  if not any then rules.allowedBets.pass = true end -- never zero bets
  return rules
end

--- 6-character join code from a lobby port+address hash (also what we'd
--- print next to a Steam invite).
function casual.makeJoinCode(seedNumber)
  local chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789" -- no 0/O/1/I/L ambiguity
  local code, state = "", (seedNumber % 2147483647) + 7
  for _ = 1, 6 do
    state = (state * 16807) % 2147483647
    local idx = (state % #chars) + 1
    code = code .. chars:sub(idx, idx)
  end
  return code
end

return casual
