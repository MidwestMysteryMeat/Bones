--------------------------------------------------------------------------
-- tests/hud_layout_test.lua
-- Headless responsive-layout contracts for the in-match table HUD.
--------------------------------------------------------------------------

package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local hud = require("src.ui.hud")

local passed, failed = 0, 0
local function check(condition, name)
  if condition then
    passed = passed + 1
    print("PASS  " .. name)
  else
    failed = failed + 1
    print("FAIL  " .. name)
  end
end

local function inside(inner, outer)
  return inner.x >= outer.x and inner.y >= outer.y
    and inner.x + inner.w <= outer.x + outer.w + 0.001
    and inner.y + inner.h <= outer.y + outer.h + 0.001
end

local function separated(upper, lower)
  return upper.y + upper.h <= lower.y
end

local sizes = {
  { 960, 540 },
  { 1020, 510 }, -- the smallest user screenshot
  { 1180, 650 }, -- default window, including taskbar-safe sizing
  { 1224, 696 }, -- the larger user screenshot
  { 1280, 720 },
  { 1920, 1080 },
}

local allRegionsFit = true
local allZonesSeparated = true
local allSpotsFit = true
local allControlsFit = true
local allDiceFit = true
local allSpotCountsCorrect = true

for _, size in ipairs(sizes) do
  local width, height = size[1], size[2]
  local layout = hud.layoutFor(width, height)
  local viewport = { x = 0, y = 0, w = width, h = height }

  allRegionsFit = allRegionsFit
    and inside(layout.status, viewport)
    and inside(layout.board, viewport)
    and inside(layout.tray, viewport)
    and inside(layout.dock, viewport)
  allZonesSeparated = allZonesSeparated
    and separated(layout.status, layout.board)
    and separated(layout.board, layout.tray)
    and separated(layout.tray, layout.dock)

  local placeCount, propCount = 0, 0
  for _, spot in ipairs(layout.spots) do
    allSpotsFit = allSpotsFit and inside(spot, layout.board)
    if spot.category == "place" then placeCount = placeCount + 1 end
    if spot.category == "prop" then propCount = propCount + 1 end
  end
  allSpotCountsCorrect = allSpotCountsCorrect
    and placeCount == 6 and propCount == 6 and #layout.spots == 15

  allControlsFit = allControlsFit
    and inside(layout.cashOut, layout.dock)
    and inside(layout.roll, layout.dock)
    and inside(layout.message, layout.dock)
  for _, chip in ipairs(layout.chips) do
    allControlsFit = allControlsFit and inside(chip, layout.dock)
  end

  local tray = layout.tray
  local half = tray.dieSize * 0.55
  local leftX = tray.centerX - tray.dieGap
  local rightX = tray.centerX + tray.dieGap
  allDiceFit = allDiceFit
    and inside(tray.content, tray)
    and leftX - half >= tray.content.x
    and rightX + half <= tray.content.x + tray.content.w
    and tray.centerY - half >= tray.content.y
    and tray.centerY + half <= tray.content.y + tray.content.h
end

check(allRegionsFit, "major HUD regions stay inside every tested viewport")
check(allZonesSeparated, "status, betting board, dice lane, and dock never overlap")
check(allSpotsFit, "all betting spots stay inside the responsive board")
check(allSpotCountsCorrect, "responsive board retains all fifteen betting spots")
check(allControlsFit, "cash-out, help, chip, and roll controls stay inside the dock")
check(allDiceFit, "both resting dice fit completely inside the reserved lane")

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
