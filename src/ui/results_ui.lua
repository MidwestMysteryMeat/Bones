--------------------------------------------------------------------------
-- src/ui/results_ui.lua
-- Post-run / post-match summary overlay. Always highlights the single
-- most exciting moment ("Your biggest win: 4,200 chips on a Hardway 8").
--------------------------------------------------------------------------

local widgets = require("src.ui.widgets")
local screen  = require("src.ui.screen")
local catalog = require("src.meta.dice_catalog")

local results_ui = {}

--- Draw a PvE run summary. Returns true when Continue is clicked.
--- summary comes from Run:finish() (see src/modes/pve.lua).
function results_ui.drawRunSummary(summary)
  local g = love.graphics
  local w, h = g.getDimensions()
  local pw, ph = math.min(560, w * 0.6), 420
  local px, py = w / 2 - pw / 2, h / 2 - ph / 2

  g.setColor(0, 0, 0, 0.75)
  g.rectangle("fill", 0, 0, w, h)
  g.setColor(0.08, 0.1, 0.09)
  g.rectangle("fill", px, py, pw, ph, 12)
  g.setColor(1, 0.84, 0.3)
  g.rectangle("line", px, py, pw, ph, 12)

  g.setFont(screen.fonts.header)
  g.setColor(summary.bust and { 1, 0.4, 0.35 } or { 0.5, 1, 0.6 })
  g.printf(summary.bust and "BUSTED" or "CASHED OUT", px, py + 24, pw, "center")

  g.setFont(screen.fonts.body)
  g.setColor(1, 1, 1, 0.9)
  local lines = {
    ("Reached Tier %d - %s"):format(summary.tierReached, summary.tierName),
    ("Rolls thrown: %d"):format(summary.rolls),
    ("Peak bankroll: %d"):format(summary.peak),
    ("Banked to wallet: %d chips"):format(summary.banked),
  }
  for i, line in ipairs(lines) do
    g.printf(line, px, py + 80 + (i - 1) * 30, pw, "center")
  end

  -- The most exciting moment, front and center.
  if summary.biggestWin and summary.biggestWin.amount > 0 then
    g.setFont(screen.fonts.body)
    g.setColor(1, 0.84, 0.3)
    g.printf(("Your biggest win: %s chips"):format(summary.biggestWin.label),
      px, py + 210, pw, "center")
  end

  -- Freshly unlocked rarities get their reveal.
  if summary.unlockedRarities and #summary.unlockedRarities > 0 then
    g.setFont(screen.fonts.body)
    for i, rarity in ipairs(summary.unlockedRarities) do
      local rc = catalog.rarityColors[rarity]
      g.setColor(rc)
      g.printf(("NEW RARITY UNLOCKED: %s DICE!"):format(rarity:upper()),
        px, py + 245 + (i - 1) * 26, pw, "center")
    end
  end

  g.setColor(1, 1, 1, 1)
  return widgets.button(px + pw / 2 - 90, py + ph - 70, 180, 46, "CONTINUE")
end

--- Draw multiplayer standings. Returns true when Continue is clicked.
--- standings from MATCH_END: { { name, chips, netChips, position, disconnected } }
function results_ui.drawStandings(standings, myId, ratingChange)
  local g = love.graphics
  local w, h = g.getDimensions()
  local pw, ph = math.min(620, w * 0.65), 150 + #standings * 34 + 80
  local px, py = w / 2 - pw / 2, h / 2 - ph / 2

  g.setColor(0, 0, 0, 0.75)
  g.rectangle("fill", 0, 0, w, h)
  g.setColor(0.08, 0.1, 0.09)
  g.rectangle("fill", px, py, pw, ph, 12)
  g.setColor(1, 0.84, 0.3)
  g.rectangle("line", px, py, pw, ph, 12)

  g.setFont(screen.fonts.header)
  g.setColor(1, 0.92, 0.7)
  g.printf("MATCH RESULTS", px, py + 20, pw, "center")

  g.setFont(screen.fonts.body)
  for i, s in ipairs(standings) do
    local y = py + 80 + (i - 1) * 34
    local me = s.id == myId
    g.setColor(me and { 1, 0.84, 0.3 } or { 1, 1, 1, 0.9 })
    g.print(("#%d  %s%s"):format(s.position, s.name,
      s.disconnected and "  (disconnected)" or ""), px + 40, y)
    local net = s.netChips or 0
    g.setColor(net >= 0 and { 0.5, 1, 0.6 } or { 1, 0.45, 0.4 })
    g.printf((net >= 0 and "+%d" or "%d"):format(net), px, y, pw - 40, "right")
  end

  if ratingChange then
    g.setFont(screen.fonts.body)
    g.setColor(ratingChange.delta >= 0 and { 0.5, 1, 0.6 } or { 1, 0.45, 0.4 })
    g.printf(("Rating: %d -> %d (%+d)"):format(ratingChange.oldRating,
      ratingChange.newRating, ratingChange.delta),
      px, py + ph - 110, pw, "center")
  end

  g.setColor(1, 1, 1, 1)
  return widgets.button(px + pw / 2 - 90, py + ph - 66, 180, 46, "CONTINUE")
end

return results_ui
