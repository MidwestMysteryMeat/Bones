--------------------------------------------------------------------------
-- tests/dice_render_test.lua
-- Headless contract test for the programmatic dice renderer.
-- Run from the project root: lua tests/dice_render_test.lua
--------------------------------------------------------------------------

package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local randomValues = { 0.25, 0.75, 0.5, 0.4, 0.6, 0.3 }
local randomIndex = 0
local printed = {}

local font = {
  getHeight = function() return 16 end,
  getWidth = function(_, text) return #text * 9 end,
}

love = {
  math = {
    random = function()
      randomIndex = randomIndex % #randomValues + 1
      return randomValues[randomIndex]
    end,
  },
  graphics = {
    push = function() end,
    pop = function() end,
    translate = function() end,
    rotate = function() end,
    scale = function() end,
    setColor = function() end,
    setLineWidth = function() end,
    rectangle = function() end,
    line = function() end,
    getFont = function() return font end,
    print = function(text)
      printed[#printed + 1] = text
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

local die = diceRender.newDie(100, 120, 80)
local landed = 0
die:startTumble(6, 0.1, function()
  landed = landed + 1
end)

check(die:isRolling(), "startTumble enters the rolling state")
check(die.spin ~= 0, "tumble receives a programmatic spin")

die:update(0.05)
check(die.state == "tumbling" and die.lift > 0,
  "tumbling die follows an airborne arc")

die:update(0.06)
check(die.state == "settling", "die enters the settle phase")
check(die.face == 6, "animation lands on the supplied result")
check(landed == 1, "landing callback fires exactly once")

die:update(0.5)
check(not die:isRolling(), "settle animation returns to idle")
check(die.rot == 0 and die.lift == 0 and die.squash == 1,
  "idle transform is fully reset")

die:draw()
check(printed[#printed] == "6", "numeric result is drawn programmatically")

die:startTumble(99, 0.01)
die:update(0.02)
check(die.face == 6, "invalid high results clamp to a d6 face")

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
