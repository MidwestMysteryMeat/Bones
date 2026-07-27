--------------------------------------------------------------------------
-- src/fx/dice_render.lua
-- Native 3D dice for LÖVE, inspired by @3d-dice/dice-box and physical
-- rigid-body rollers. A beveled cube is built from polygons, rotated with
-- quaternions, perspective-projected, lit, and marked with face-bound pips.
-- Ballistic lift, angular velocity, restitution, friction, and a final
-- quaternion settle sell the throw while the engine-supplied result remains
-- authoritative. No images, models, browser canvas, or 3D library required.
--------------------------------------------------------------------------

local dice_render = {}

local PI = math.pi
local TAU = PI * 2
local STABLE_DURATION = 0.08
local BEVEL = 0.84

local function vec(x, y, z)
  return { x = x, y = y, z = z }
end

local function vadd(a, b)
  return vec(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function vsub(a, b)
  return vec(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function vscale(a, amount)
  return vec(a.x * amount, a.y * amount, a.z * amount)
end

local function vdot(a, b)
  return a.x * b.x + a.y * b.y + a.z * b.z
end

local function vcross(a, b)
  return vec(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x
  )
end

local function vlength(a)
  return math.sqrt(vdot(a, a))
end

local function vnormalize(a)
  local length = vlength(a)
  if length < 0.000001 then return vec(0, 0, 0) end
  return vscale(a, 1 / length)
end

local function qnormalize(q)
  local length = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
  if length < 0.000001 then
    return { w = 1, x = 0, y = 0, z = 0 }
  end
  return {
    w = q.w / length,
    x = q.x / length,
    y = q.y / length,
    z = q.z / length,
  }
end

local function qmultiply(a, b)
  return {
    w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
  }
end

local function qconjugate(q)
  return { w = q.w, x = -q.x, y = -q.y, z = -q.z }
end

local function qaxisAngle(axis, angle)
  local normalized = vnormalize(axis)
  local half = angle * 0.5
  local sine = math.sin(half)
  return qnormalize({
    w = math.cos(half),
    x = normalized.x * sine,
    y = normalized.y * sine,
    z = normalized.z * sine,
  })
end

local function qrotate(q, point)
  -- Optimized q * point * inverse(q).
  local qv = vec(q.x, q.y, q.z)
  local twiceCross = vscale(vcross(qv, point), 2)
  return vadd(point, vadd(vscale(twiceCross, q.w), vcross(qv, twiceCross)))
end

local function qfromTo(from, to)
  local a, b = vnormalize(from), vnormalize(to)
  local dot = vdot(a, b)
  if dot > 0.999999 then
    return { w = 1, x = 0, y = 0, z = 0 }
  end
  if dot < -0.999999 then
    local axis = vcross(a, vec(1, 0, 0))
    if vlength(axis) < 0.000001 then axis = vcross(a, vec(0, 0, 1)) end
    return qaxisAngle(axis, PI)
  end
  local cross = vcross(a, b)
  return qnormalize({ w = 1 + dot, x = cross.x, y = cross.y, z = cross.z })
end

local function randomUnit()
  if love and love.math and love.math.random then
    return love.math.random()
  end
  return math.random()
end

local function randomSigned()
  return randomUnit() * 2 - 1
end

local function clampFace(face)
  return math.max(1, math.min(6, math.floor(tonumber(face) or 1)))
end

local function clamp01(value)
  return math.max(0, math.min(1, value))
end

local function shade(color, amount, specular)
  specular = specular or 0
  return clamp01(color[1] * amount + specular),
    clamp01(color[2] * amount + specular),
    clamp01(color[3] * amount + specular)
end

local WORLD_UP = vec(0, 1, 0)
local CAMERA = vec(0, 3.8, 6.5)
local CAMERA_DISTANCE = vlength(CAMERA)
local VIEW_FORWARD = vnormalize(vscale(CAMERA, -1))
local VIEW_RIGHT = vnormalize(vcross(VIEW_FORWARD, WORLD_UP))
local VIEW_UP = vnormalize(vcross(VIEW_RIGHT, VIEW_FORWARD))
local LIGHT = vnormalize(vec(-0.65, 1.0, 0.85))

local FACE_DEFS = {}
local FACE_BY_VALUE = {}
local SURFACES = {}

local function pointOnFace(normal, u, vaxis, uAmount, vAmount)
  return vadd(normal, vadd(vscale(u, uAmount), vscale(vaxis, vAmount)))
end

local function addFace(value, normal, u, vaxis)
  local face = {
    kind = "face",
    value = value,
    normal = normal,
    u = u,
    v = vaxis,
    points = {
      pointOnFace(normal, u, vaxis, -BEVEL, -BEVEL),
      pointOnFace(normal, u, vaxis,  BEVEL, -BEVEL),
      pointOnFace(normal, u, vaxis,  BEVEL,  BEVEL),
      pointOnFace(normal, u, vaxis, -BEVEL,  BEVEL),
    },
  }
  FACE_DEFS[#FACE_DEFS + 1] = face
  FACE_BY_VALUE[value] = face
  SURFACES[#SURFACES + 1] = face
end

-- Standard d6 opposites sum to seven. At identity: 1 up, 2 toward the
-- camera, and 3 right.
addFace(1, vec( 0,  1,  0), vec( 1, 0,  0), vec( 0, 0, -1))
addFace(6, vec( 0, -1,  0), vec( 1, 0,  0), vec( 0, 0,  1))
addFace(2, vec( 0,  0,  1), vec( 1, 0,  0), vec( 0, 1,  0))
addFace(5, vec( 0,  0, -1), vec(-1, 0,  0), vec( 0, 1,  0))
addFace(3, vec( 1,  0,  0), vec( 0, 0, -1), vec( 0, 1,  0))
addFace(4, vec(-1,  0,  0), vec( 0, 0,  1), vec( 0, 1,  0))

local SIGNS = { -1, 1 }

local function addSurface(kind, normal, points)
  SURFACES[#SURFACES + 1] = {
    kind = kind,
    normal = vnormalize(normal),
    points = points,
  }
end

-- Twelve chamfered edges.
for _, sx in ipairs(SIGNS) do
  for _, sy in ipairs(SIGNS) do
    addSurface("edge", vec(sx, sy, 0), {
      vec(sx, sy * BEVEL, -BEVEL),
      vec(sx, sy * BEVEL,  BEVEL),
      vec(sx * BEVEL, sy,  BEVEL),
      vec(sx * BEVEL, sy, -BEVEL),
    })
  end
end
for _, sx in ipairs(SIGNS) do
  for _, sz in ipairs(SIGNS) do
    addSurface("edge", vec(sx, 0, sz), {
      vec(sx, -BEVEL, sz * BEVEL),
      vec(sx,  BEVEL, sz * BEVEL),
      vec(sx * BEVEL,  BEVEL, sz),
      vec(sx * BEVEL, -BEVEL, sz),
    })
  end
end
for _, sy in ipairs(SIGNS) do
  for _, sz in ipairs(SIGNS) do
    addSurface("edge", vec(0, sy, sz), {
      vec(-BEVEL, sy, sz * BEVEL),
      vec( BEVEL, sy, sz * BEVEL),
      vec( BEVEL, sy * BEVEL, sz),
      vec(-BEVEL, sy * BEVEL, sz),
    })
  end
end

-- Eight triangular corner bevels complete the rounded-cube silhouette.
for _, sx in ipairs(SIGNS) do
  for _, sy in ipairs(SIGNS) do
    for _, sz in ipairs(SIGNS) do
      addSurface("corner", vec(sx, sy, sz), {
        vec(sx, sy * BEVEL, sz * BEVEL),
        vec(sx * BEVEL, sy, sz * BEVEL),
        vec(sx * BEVEL, sy * BEVEL, sz),
      })
    end
  end
end

local PIP_LAYOUTS = {
  [1] = { { 0, 0 } },
  [2] = { { -1, -1 }, { 1, 1 } },
  [3] = { { -1, -1 }, { 0, 0 }, { 1, 1 } },
  [4] = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } },
  [5] = { { -1, -1 }, { 1, -1 }, { 0, 0 }, { -1, 1 }, { 1, 1 } },
  [6] = {
    { -1, -1 }, { -1, 0 }, { -1, 1 },
    {  1, -1 }, {  1, 0 }, {  1, 1 },
  },
}

local defaultCosmetic = {
  body = { 0.95, 0.93, 0.88 },
  pip = { 0.15, 0.15, 0.18 },
}

local function landingOrientation(face, yaw)
  local normal = FACE_BY_VALUE[clampFace(face)].normal
  local align = qfromTo(normal, WORLD_UP)
  local turn = qaxisAngle(WORLD_UP, yaw or 0)
  return qnormalize(qmultiply(turn, align))
end

local function orientationError(current, target)
  local error = qnormalize(qmultiply(target, qconjugate(current)))
  if error.w < 0 then
    error.w, error.x, error.y, error.z =
      -error.w, -error.x, -error.y, -error.z
  end
  local halfCosine = math.max(-1, math.min(1, error.w))
  local angle = 2 * math.acos(halfCosine)
  local halfSine = math.sqrt(math.max(0, 1 - halfCosine * halfCosine))
  if halfSine < 0.00001 or angle < 0.00001 then
    return vec(0, 0, 0), 0
  end
  return vec(error.x / halfSine, error.y / halfSine, error.z / halfSine),
    angle
end

local function project(point, scale)
  local relative = vsub(point, CAMERA)
  local depth = vdot(relative, VIEW_FORWARD)
  local perspective = CAMERA_DISTANCE / math.max(2.5, depth)
  return vdot(relative, VIEW_RIGHT) * perspective * scale,
    -vdot(relative, VIEW_UP) * perspective * scale,
    depth
end

local function projectPolygon(points, orientation, scale, originX, originY)
  local projected = {}
  local depth = 0
  for _, point in ipairs(points) do
    local rotated = qrotate(orientation, point)
    local x, y, pointDepth = project(rotated, scale)
    projected[#projected + 1] = originX + x
    projected[#projected + 1] = originY + y
    depth = depth + pointDepth
  end
  return projected, depth / #points
end

local function surfaceItem(surface, orientation, scale, originX, originY)
  local normal = qrotate(orientation, surface.normal)
  local center = vec(0, 0, 0)
  for _, point in ipairs(surface.points) do center = vadd(center, point) end
  center = qrotate(orientation, vscale(center, 1 / #surface.points))
  local toCamera = vnormalize(vsub(CAMERA, center))
  if vdot(normal, toCamera) <= 0.005 then return nil end

  local points, depth = projectPolygon(
    surface.points, orientation, scale, originX, originY)
  local diffuse = 0.30 + math.max(0, vdot(normal, LIGHT)) * 0.70
  if surface.kind == "edge" then diffuse = diffuse * 0.82 end
  if surface.kind == "corner" then diffuse = diffuse * 0.68 end

  local halfVector = vnormalize(vadd(LIGHT, toCamera))
  local specular = math.max(0, vdot(normal, halfVector)) ^ 18
  specular = specular * (surface.kind == "face" and 0.34 or 0.18)

  return {
    surface = surface,
    normal = normal,
    points = points,
    depth = depth,
    diffuse = diffuse,
    specular = specular,
  }
end

local function pipPolygon(face, gridX, gridY, radius, orientation, scale,
    originX, originY)
  local center = vadd(
    vscale(face.normal, 1.012),
    vadd(vscale(face.u, gridX * 0.43), vscale(face.v, gridY * 0.43))
  )
  local points = {}
  for index = 0, 11 do
    local angle = index / 12 * TAU
    points[#points + 1] = vadd(center, vadd(
      vscale(face.u, math.cos(angle) * radius),
      vscale(face.v, math.sin(angle) * radius)
    ))
  end
  return projectPolygon(points, orientation, scale, originX, originY)
end

local Die = {}
Die.__index = Die

function dice_render.newDie(x, y, size, cosmetic)
  return setmetatable({
    x = x,
    y = y,
    size = size or 72,
    cosmetic = cosmetic or defaultCosmetic,
    face = 1,
    finalFace = 1,
    state = "idle", -- idle | tumbling | settling
    t = 0,
    duration = 0,
    orientation = landingOrientation(1, 0.32),
    settleTarget = nil,
    stableTime = 0,
    angularVelocity = vec(0, 0, 0),
    spin = 0,
    height = 0,
    verticalVelocity = 0,
    gravity = 0,
    offsetX = 0,
    offsetY = 0,
    throwOffsetX = 0,
    throwOffsetY = 0,
    onLand = nil,
  }, Die)
end

--- Kick off a physical-looking throw that is guaranteed to settle on the
--- authoritative finalFace. The simulated cube never decides gameplay.
function Die:startTumble(finalFace, duration, onLand)
  self.state = "tumbling"
  self.t = 0
  self.duration = math.max(0.05, duration or 0.9)
  self.finalFace = clampFace(finalFace)
  self.settleTarget = landingOrientation(
    self.finalFace, randomUnit() * TAU)
  self.stableTime = 0
  self.angularVelocity = vec(
    randomSigned() * 11,
    randomSigned() * 13,
    randomSigned() * 11
  )
  if vlength(self.angularVelocity) < 8 then
    self.angularVelocity = vadd(self.angularVelocity, vec(8, 6, -7))
  end
  self.spin = vlength(self.angularVelocity)
  self.height = 0
  self.verticalVelocity = self.size * (2.8 + randomUnit() * 0.9)
  self.gravity = self.size * (8.8 + randomUnit() * 1.4)

  local viewportWidth = love and love.graphics and love.graphics.getWidth
    and love.graphics.getWidth() or 1280
  local viewportHeight = love and love.graphics and love.graphics.getHeight
    and love.graphics.getHeight() or 720
  local throwSide
  if self.size <= 36 then
    throwSide = randomUnit() < 0.5 and -1 or 1
  elseif self.x < viewportWidth * 0.48 then
    throwSide = -1
  elseif self.x > viewportWidth * 0.52 then
    throwSide = 1
  else
    throwSide = randomUnit() < 0.5 and -1 or 1
  end

  local edgeRoom
  if throwSide < 0 then
    edgeRoom = math.max(self.size * 1.5, self.x - self.size * 0.72)
  else
    edgeRoom = math.max(
      self.size * 1.5, viewportWidth - self.x - self.size * 0.72)
  end
  local maxTravel = self.size <= 36
    and self.size * 2.0
    or math.min(viewportWidth * 0.44, self.size * 6.5)
  self.throwOffsetX = throwSide * math.min(edgeRoom, maxTravel)

  local downRoom = math.max(0, viewportHeight - self.y - self.size * 0.72)
  local desiredDown = self.size <= 36
    and self.size * 0.55
    or self.size * (1.15 + randomUnit() * 0.55)
  self.throwOffsetY = math.min(downRoom, desiredDown)
  self.offsetX = self.throwOffsetX
  self.offsetY = self.throwOffsetY
  self.onLand = onLand
end

function Die:extend(extra)
  if self.state == "tumbling" then
    self.duration = math.max(self.t + 0.05, self.duration + extra)
  end
end

function Die:isRolling()
  return self.state ~= "idle"
end

--- Determine the physically uppermost face from the current orientation.
--- This is the same result-reading principle used by rigid-body dice rollers.
function Die:getUpFace()
  local bestFace, bestHeight = 1, -math.huge
  for _, face in ipairs(FACE_DEFS) do
    local height = qrotate(self.orientation, face.normal).y
    if height > bestHeight then
      bestFace, bestHeight = face.value, height
    end
  end
  return bestFace
end

local function advanceAngular(die, dt, stiffness, damping)
  local axis, angle = orientationError(die.orientation, die.settleTarget)
  if stiffness > 0 and angle > 0 then
    die.angularVelocity = vadd(die.angularVelocity,
      vscale(axis, angle * stiffness * dt))
  end
  die.angularVelocity = vscale(
    die.angularVelocity, math.exp(-damping * dt))
  local speed = vlength(die.angularVelocity)
  if speed > 0.00001 then
    local delta = qaxisAngle(die.angularVelocity, speed * dt)
    die.orientation = qnormalize(qmultiply(delta, die.orientation))
  end
  die.spin = speed
  return angle, speed
end

local function advanceVertical(die, dt, restitution)
  if die.height <= 0 and die.verticalVelocity == 0 then return end
  die.height = die.height + die.verticalVelocity * dt
  die.verticalVelocity = die.verticalVelocity - die.gravity * dt
  if die.height <= 0 then
    local impactSpeed = -die.verticalVelocity
    die.height = 0
    if impactSpeed > die.size * 0.55 then
      die.verticalVelocity = impactSpeed * restitution
      die.angularVelocity = vscale(die.angularVelocity, 0.80)
    else
      die.verticalVelocity = 0
    end
  end
end

local function finishLanding(die)
  die.state = "idle"
  die.orientation = die.settleTarget
  die.angularVelocity = vec(0, 0, 0)
  die.spin = 0
  die.height = 0
  die.verticalVelocity = 0
  die.offsetX = 0
  die.offsetY = 0
  if die.onLand then
    local callback = die.onLand
    die.onLand = nil
    callback(die)
  end
end

local function stepTumble(die, dt)
  die.t = die.t + dt
  local progress = math.min(1, die.t / die.duration)

  -- Begin a soft restoring torque well before contact. It grows continuously,
  -- so there is no animation-to-settle handoff and therefore no visible snap.
  local steer = clamp01((progress - 0.34) / 0.66)
  steer = steer * steer * (3 - 2 * steer)
  advanceAngular(die, dt, 34 * steer * steer, 0.22 + 7.5 * steer * steer)
  advanceVertical(die, dt, 0.30)

  -- Translate through the tray instead of spinning in place. The smoothstep
  -- path starts at a screen edge with zero jerk and converges on the fixed
  -- result location as the physical bounce loses energy.
  local travelEase = progress * progress * (3 - 2 * progress)
  local remaining = 1 - travelEase
  local skid = math.sin(progress * TAU) * die.size * 0.10 * (1 - progress)
  die.offsetX = die.throwOffsetX * remaining + skid
  die.offsetY = die.throwOffsetY * remaining

  if die.t >= die.duration then
    die.state = "settling"
    die.t = 0
    die.face = die.finalFace
    die.offsetX = 0
    die.offsetY = 0
    die.stableTime = 0
  end
end

local function stepSettle(die, dt)
  die.t = die.t + dt
  local ramp = math.min(1, die.t / 0.35)
  local angle, speed = advanceAngular(
    die, dt, 52 + 34 * ramp, 13 + 5 * ramp)
  advanceVertical(die, dt, 0.20)

  local grounded = die.height <= 0 and die.verticalVelocity == 0
  if grounded and angle < 0.018 and speed < 0.10 then
    die.stableTime = die.stableTime + dt
  else
    die.stableTime = 0
  end
  if die.stableTime >= STABLE_DURATION then finishLanding(die) end
end

function Die:update(dt)
  -- Fixed-size substeps keep the quaternion spring and impacts stable after
  -- pauses or hitstop, just as a deterministic physics loop would.
  local remaining = math.max(0, dt)
  while remaining > 0 and self.state ~= "idle" do
    local step = math.min(remaining, 1 / 90)
    if self.state == "tumbling" then
      stepTumble(self, step)
    elseif self.state == "settling" then
      stepSettle(self, step)
    end
    remaining = remaining - step
  end
end

function Die:draw()
  local graphics = love.graphics
  local size = self.size
  local body = self.cosmetic.body or defaultCosmetic.body
  local pip = self.cosmetic.pip or defaultCosmetic.pip
  local glow = self.cosmetic.glow
  local originX = self.x + self.offsetX
  local originY = self.y + self.offsetY - self.height
  local scale = size * 0.46

  -- Contact shadow remains on the table while the cube rises above it.
  local altitude = self.height / math.max(1, size)
  local shadowAlpha = 0.34 / (1 + altitude * 1.8)
  local shadowWidth = size * (0.47 + math.min(0.20, altitude * 0.08))
  graphics.setColor(0, 0, 0, shadowAlpha)
  graphics.ellipse("fill", self.x + self.offsetX,
    self.y + self.offsetY + size * 0.48, shadowWidth, size * 0.14)
  if glow then
    graphics.setColor(glow[1], glow[2], glow[3], 0.10 / (1 + altitude))
    graphics.ellipse("line", self.x + self.offsetX,
      self.y + self.offsetY + size * 0.48,
      shadowWidth * 1.15, size * 0.18)
  end

  local items = {}
  for _, surface in ipairs(SURFACES) do
    local item = surfaceItem(
      surface, self.orientation, scale, originX, originY)
    if item then items[#items + 1] = item end
  end
  table.sort(items, function(a, b) return a.depth > b.depth end)

  for _, item in ipairs(items) do
    local red, green, blue = shade(body, item.diffuse, item.specular)
    graphics.setColor(red, green, blue, 1)
    graphics.polygon("fill", item.points)

    if glow and item.surface.kind == "face" then
      graphics.setLineWidth(math.max(1.5, size * 0.028))
      graphics.setColor(glow[1], glow[2], glow[3], 0.35)
      graphics.polygon("line", item.points)
    elseif item.surface.kind == "face" then
      graphics.setLineWidth(math.max(1, size * 0.012))
      graphics.setColor(0.025, 0.03, 0.04, 0.58)
      graphics.polygon("line", item.points)
    else
      -- Seal antialiasing gaps without outlining every chamfer; the bevels
      -- should read as one rounded solid, not as separate UI panels.
      graphics.setLineWidth(1)
      graphics.setColor(red, green, blue, 1)
      graphics.polygon("line", item.points)
    end

    if item.surface.value then
      local face = item.surface
      local pipLight = 0.56 + item.diffuse * 0.44
      local pipRed, pipGreen, pipBlue = shade(pip, pipLight, item.specular * 0.16)
      for _, position in ipairs(PIP_LAYOUTS[face.value]) do
        local socket = pipPolygon(face, position[1], position[2], 0.145,
          self.orientation, scale, originX, originY)
        graphics.setColor(0.015, 0.018, 0.022, 0.72)
        graphics.polygon("fill", socket)

        local mark = pipPolygon(face, position[1], position[2], 0.098,
          self.orientation, scale, originX, originY)
        graphics.setColor(pipRed, pipGreen, pipBlue, 1)
        graphics.polygon("fill", mark)
      end
    end
  end

  graphics.setLineWidth(1)
  graphics.setColor(1, 1, 1, 1)
end

return dice_render
