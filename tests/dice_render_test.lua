--------------------------------------------------------------------------
-- tests/dice_render_test.lua
-- Headless contract test for the programmatic dice renderer.
-- Run from the project root: lua tests/dice_render_test.lua
--------------------------------------------------------------------------

package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local randomValues = { 0.25, 0.75, 0.5, 0.4, 0.6, 0.3 }
local randomIndex = 0
local polygonCalls = 0
local ellipseCalls = 0

love = {
  math = {
    random = function()
      randomIndex = randomIndex % #randomValues + 1
      return randomValues[randomIndex]
    end,
  },
  graphics = {
    getWidth = function() return 1000 end,
    getHeight = function() return 600 end,
    setColor = function() end,
    setLineWidth = function() end,
    polygon = function(mode, points)
      assert(mode == "fill" or mode == "line")
      assert(type(points) == "table" and #points >= 6)
      polygonCalls = polygonCalls + 1
    end,
    ellipse = function(mode)
      assert(mode == "fill" or mode == "line")
      ellipseCalls = ellipseCalls + 1
    end,
  },
}

local diceRender = require("src.fx.dice_render")

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

local die = diceRender.newDie(450, 320, 80)
local landed = 0
die:startTumble(6, 0.1, function()
  landed = landed + 1
end)

check(die:isRolling(), "startTumble enters the rolling state")
check(die.spin ~= 0, "tumble receives a programmatic spin")
local initialTravel = math.abs(die.offsetX)
check(initialTravel >= die.size * 4,
  "full-size die begins hundreds of pixels across the tray")

die:update(0.05)
check(die.state == "tumbling" and die.height > 0,
  "rigid die follows a ballistic arc")
check(math.abs(die.offsetX) < initialTravel and math.abs(die.offsetX) > 0,
  "die translates toward its landing point during the throw")

die:update(0.06)
check(die.state == "settling", "die enters the settle phase")
check(die.face == 6, "animation lands on the supplied result")
check(landed == 0, "landing callback waits for physical stability")

for _ = 1, 360 do
  if not die:isRolling() then break end
  die:update(1 / 120)
end
check(not die:isRolling(), "settle animation returns to idle")
check(landed == 1, "landing callback fires exactly once at rest")
check(die.height == 0 and die.offsetX == 0 and die.offsetY == 0
    and die.spin == 0,
  "idle rigid-body motion is fully reset")
check(die:getUpFace() == 6,
  "settled cube orientation puts the supplied face physically upward")

die:draw()
check(polygonCalls > 10,
  "beveled cube, visible faces, and pips are projected as 3D polygons")
check(ellipseCalls >= 1, "die casts a separate table-contact shadow")

die:startTumble(99, 0.05)
die:update(0.06)
check(die.face == 6, "invalid high results clamp to a d6 face")

local continuity = diceRender.newDie(450, 320, 80)
continuity:startTumble(4, 0.2)
continuity:update(0.199)
local before = continuity.orientation
continuity:update(0.002)
local after = continuity.orientation
local orientationDot = math.abs(before.w * after.w + before.x * after.x
  + before.y * after.y + before.z * after.z)
check(orientationDot > 0.995,
  "tumble-to-settle handoff preserves continuous orientation")

local allFacesLand = true
for face = 1, 6 do
  local probe = diceRender.newDie(0, 0, 60)
  probe:startTumble(face, 0.05)
  probe:update(0.06)
  for _ = 1, 360 do
    if not probe:isRolling() then break end
    probe:update(1 / 120)
  end
  if probe:isRolling() or probe:getUpFace() ~= face then
    allFacesLand = false
    break
  end
end
check(allFacesLand, "all six authoritative results settle face-up")

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
