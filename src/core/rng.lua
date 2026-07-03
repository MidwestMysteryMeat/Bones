--------------------------------------------------------------------------
-- src/core/rng.lua
-- Seedable PRNG + dice roll primitives.
--
-- NEVER use bare math.random for game-affecting rolls. Every roll goes
-- through an rng instance created here so:
--   * PvP rolls are verifiable: the server broadcasts (seed, rollIndex)
--     and any client can re-derive the exact dice.
--   * Replays and tests are reproducible.
--
-- Under LÖVE we use love.math.newRandomGenerator (xoshiro, high quality).
-- Under plain Lua (headless tests) we fall back to a Park-Miller LCG,
-- portable across Lua 5.1-5.4 (pure arithmetic, no bit ops, no overflow:
-- 16807 * 2^31 < 2^53 so doubles stay exact).
--
-- NOTE: the two backends produce DIFFERENT sequences for the same seed.
-- That's fine: all networked peers run LÖVE, and tests only need
-- self-consistency, not cross-backend equality.
--------------------------------------------------------------------------

local rng = {}

local RNG = {}
RNG.__index = RNG

local hasLove = type(love) == "table" and love.math ~= nil

--- Create a new generator. seed defaults to a time-based value.
function rng.new(seed)
  seed = seed or (os.time() + math.floor((os.clock() * 100000) % 100000))
  local self = setmetatable({ seed = seed, count = 0 }, RNG)
  if hasLove then
    self.gen = love.math.newRandomGenerator(seed)
  else
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    self.state = s
  end
  return self
end

--- Same contract as math.random: (), (m), (m, n)
function RNG:random(m, n)
  self.count = self.count + 1
  if self.gen then
    if m == nil then return self.gen:random() end
    if n == nil then return self.gen:random(m) end
    return self.gen:random(m, n)
  end
  -- Park-Miller "minimal standard": state = state * 16807 mod (2^31 - 1)
  self.state = (self.state * 16807) % 2147483647
  local r = (self.state - 1) / 2147483646
  if m == nil then return r end
  if n == nil then return math.floor(r * m) + 1 end
  return math.floor(r * (n - m + 1)) + m
end

--- Roll one die (default d6).
function RNG:rollDie(sides)
  return self:random(sides or 6)
end

--- Roll n dice, returns an array plus the sum.
function RNG:rollDice(n, sides)
  local dice, sum = {}, 0
  for i = 1, n do
    dice[i] = self:rollDie(sides)
    sum = sum + dice[i]
  end
  return dice, sum
end

--- Chance helper: returns true with probability p (0..1).
function RNG:chance(p)
  return self:random() < p
end

--- Pick a random element from an array.
function RNG:pick(t)
  return t[self:random(#t)]
end

function RNG:getSeed() return self.seed end

--- How many values have been drawn; with the seed this fully identifies
--- the generator state for verification/replay.
function RNG:getCount() return self.count end

return rng
