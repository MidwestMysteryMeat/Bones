--------------------------------------------------------------------------
-- states/battleroyale.lua
-- The Boneyard arena. Everyone's dice roll face-up every round: opponents
-- in panels across the top (HP bar, dice, point badge, chain), you at the
-- bottom with big dice. Click an opponent to target them, ROLL to fight.
-- Damage popups, kill feed, mutator banner, Rake warning, final standings.
--------------------------------------------------------------------------

local Gamestate   = require("lib.hump.gamestate")
local config      = require("src.core.config")
local br          = require("src.modes.battleroyale")
local save        = require("src.core.save")
local catalog     = require("src.meta.dice_catalog")
local screen      = require("src.ui.screen")
local widgets     = require("src.ui.widgets")
local juice       = require("src.fx.juice")
local particles   = require("src.fx.particles")
local dice_render = require("src.fx.dice_render")
local sfx         = require("src.audio.sfx")
local steam       = require("src.steam.steam")

local state = {}

local match
local failReason
local phase          -- targeting | rolling | resolving | over
local panels = {}    -- per player: { x, y, w, h, dice = {Die, Die} }
local popups = {}    -- floating damage text { x, y, text, color, t }
local pendingEvents
local resolveClock = 0
local rakeFlash = 0

local function panelCenter(idx)
  local p = panels[idx]
  return p.x + p.w / 2, p.y + p.h / 2
end

local function addPopup(idx, text, color)
  local x, y = panelCenter(idx)
  popups[#popups + 1] = {
    x = x + love.math.random(-20, 20), y = y - 10,
    text = text, color = color, t = 1.3,
  }
end

local function layoutPanels()
  local w, h = love.graphics.getDimensions()
  panels = {}
  -- Opponents (2..8): a row of 4 and a row of 3 across the top.
  local pw, ph = math.min(200, w * 0.16), 118
  local rows = { { 2, 3, 4, 5 }, { 6, 7, 8 } }
  for r, row in ipairs(rows) do
    local totalW = #row * (pw + 12) - 12
    for c, idx in ipairs(row) do
      if idx <= #match.players then
        panels[idx] = {
          x = w / 2 - totalW / 2 + (c - 1) * (pw + 12),
          y = 92 + (r - 1) * (ph + 10),
          w = pw, h = ph,
        }
      end
    end
  end
  -- You: wide panel bottom center.
  panels[1] = { x = w / 2 - 190, y = h - 218, w = 380, h = 148 }

  -- Dice objects per panel.
  for idx, pn in pairs(panels) do
    local player = match.players[idx]
    local size = player.isHuman and 56 or 30
    local cos
    if player.isHuman then
      local d = catalog.byId[save.data.equipped[1]]
      cos = d and d.cosmetic or nil
    end
    pn.dice = {
      dice_render.newDie(pn.x + pn.w / 2 - size * 0.7, pn.y + pn.h - size * 0.72, size, cos),
      dice_render.newDie(pn.x + pn.w / 2 + size * 0.7, pn.y + pn.h - size * 0.72, size, cos),
    }
  end
end

function state:enter()
  failReason, match = nil, nil
  local m, reason = br.newMatch(save.data)
  if not m then
    failReason = reason
    return
  end
  match = m
  phase = "targeting"
  popups, pendingEvents = {}, nil
  rakeFlash = 0
  steam.presence("In the Boneyard")
  layoutPanels()
end

local function applyEvents(events)
  local w, h = love.graphics.getDimensions()
  local humanInvolved = false
  for _, e in ipairs(events) do
    if e.type == "hit" then
      addPopup(e.victim, "-" .. e.dmg, { 1, 0.45, 0.35 })
      if e.attacker == 1 or e.victim == 1 then humanInvolved = true end
      if e.attacker == 1 then
        sfx.play("win_chime")
        particles.sparks(panelCenter(e.victim))
      end
    elseif e.type == "break" then
      addPopup(e.victim, ("-%d BREAK!"):format(e.dmg), { 1, 0.75, 0.2 })
      particles.coinBurst(select(1, panelCenter(e.victim)),
        select(2, panelCenter(e.victim)), e.dmg / 60)
      if e.attacker == 1 then
        juice.shake(8)
        sfx.streakRiser(match.players[1].chain)
      end
    elseif e.type == "backfire" then
      addPopup(e.attacker, ("-%d CRAPS"):format(e.dmg), { 0.8, 0.4, 1 })
      if e.attacker == 1 then juice.shake(5) sfx.play("lose_thud") end
    elseif e.type == "sevenout" then
      addPopup(e.attacker, ("-%d SEVEN-OUT"):format(e.dmg), { 0.8, 0.4, 1 })
      if e.attacker == 1 then juice.shake(6) sfx.play("lose_thud") end
    elseif e.type == "pressure" then
      addPopup(e.victim, "-" .. e.dmg, { 1, 0.7, 0.6 })
    elseif e.type == "armed" then
      addPopup(e.attacker, "PT " .. e.point, { 0.6, 0.85, 1 })
    elseif e.type == "rake" then
      rakeFlash = 0.8
      juice.shake(4)
    elseif e.type == "kill" then
      local vx, vy = panelCenter(e.victim)
      particles.coinBurst(vx, vy, 1.2)
      juice.hitstop(0.08)
      if e.attacker == 1 then
        juice.flash({ 1, 0.85, 0.2 }, 0.25)
        sfx.play("jackpot")
      elseif e.victim == 1 then
        juice.flash({ 1, 0.2, 0.2 }, 0.4)
        juice.shake(14)
        sfx.play("lose_thud")
      end
    elseif e.type == "win" and e.attacker == 1 then
      particles.jackpotFountain(w, h, 3)
      sfx.play("jackpot")
    end
  end
  if humanInvolved then juice.hitstop(0.04) end
end

local function startRoll()
  if phase ~= "targeting" or match.over then return end
  phase = "rolling"
  sfx.play("dice_rattle")
  pendingEvents = match:playRound()

  -- Tumble everyone's dice to their broadcast faces.
  local settled, needed = 0, 0
  for idx, pn in pairs(panels) do
    local player = match.players[idx]
    if player.lastRoll and (player.alive or match.over) then
      for i, die in ipairs(pn.dice) do
        needed = needed + 1
        die:startTumble(player.lastRoll[i],
          (player.isHuman and 0.85 or 0.55) + love.math.random() * 0.2,
          function()
            settled = settled + 1
            if player.isHuman then sfx.play("dice_land") end
            if settled >= needed then
              applyEvents(pendingEvents)
              pendingEvents = nil
              phase = match.over and "over" or "resolving"
              resolveClock = 0.9
            end
          end)
      end
    end
  end
  if needed == 0 then -- everyone somehow dead; failsafe
    applyEvents(pendingEvents)
    pendingEvents = nil
    phase = "over"
  end
end

function state:update(dt)
  if failReason then return end
  local sdt = juice.update(dt)
  sfx.update(dt)
  widgets.beginFrame()
  for _, pn in pairs(panels) do
    for _, die in ipairs(pn.dice) do die:update(sdt) end
  end
  particles.update(sdt)
  for i = #popups, 1, -1 do
    local p = popups[i]
    p.t = p.t - dt
    p.y = p.y - dt * 34
    if p.t <= 0 then table.remove(popups, i) end
  end
  if rakeFlash > 0 then rakeFlash = rakeFlash - dt end
  if phase == "resolving" then
    resolveClock = resolveClock - dt
    if resolveClock <= 0 then
      -- If we died but the match runs on, resolve it so standings exist.
      if not match.players[1].alive and not match.over then
        match:fastForward()
        phase = "over"
      else
        phase = match.over and "over" or "targeting"
      end
    end
  end
end

local function drawPanel(idx)
  local g = love.graphics
  local pn = panels[idx]
  local p = match.players[idx]
  local isTarget = match.players[1].target == idx
  local human = p.isHuman

  -- Frame; targeted opponent gets a red ring, you get gold.
  g.setColor(0.04, 0.06, 0.05, 0.92)
  g.rectangle("fill", pn.x, pn.y, pn.w, pn.h, 10)
  if not p.alive then
    g.setColor(0.3, 0.3, 0.3, 0.8)
  elseif human then
    g.setColor(1, 0.84, 0.3)
  elseif isTarget then
    g.setColor(1, 0.3, 0.25)
  else
    g.setColor(1, 1, 1, 0.25)
  end
  g.setLineWidth(isTarget and 3 or 2)
  g.rectangle("line", pn.x, pn.y, pn.w, pn.h, 10)
  g.setLineWidth(1)

  -- Name + kills.
  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, p.alive and 0.95 or 0.4)
  g.print(p.name, pn.x + 8, pn.y + 5)
  if p.kills > 0 then
    g.setColor(1, 0.5, 0.3)
    g.print(("%d KO"):format(p.kills), pn.x + pn.w - 44, pn.y + 5)
  end

  -- HP bar.
  local frac = p.hp / p.maxHP
  g.setColor(0.15, 0.05, 0.05)
  g.rectangle("fill", pn.x + 8, pn.y + 24, pn.w - 16, 10, 4)
  g.setColor(frac > 0.5 and { 0.35, 0.9, 0.4 } or frac > 0.25
    and { 0.95, 0.75, 0.2 } or { 0.95, 0.25, 0.2 })
  if frac > 0 then
    g.rectangle("fill", pn.x + 8, pn.y + 24, (pn.w - 16) * frac, 10, 4)
  end
  g.setColor(1, 1, 1, 0.8)
  g.print(("%d/%d"):format(p.hp, p.maxHP), pn.x + 8, pn.y + 36)

  if not p.alive then
    g.setFont(screen.fonts.body)
    g.setColor(1, 0.4, 0.35, 0.9)
    g.printf("BUSTED", pn.x, pn.y + pn.h / 2 - 8, pn.w, "center")
    return
  end

  -- Point badge + chain.
  if p.point then
    g.setColor(0.6, 0.85, 1)
    g.print("PT " .. p.point, pn.x + pn.w - 44, pn.y + 24)
  end
  if p.chain > 0 then
    g.setColor(1, 0.5, 0.15)
    g.print(("CHAIN x%.1f"):format(match:chainMult(p)), pn.x + pn.w - 78, pn.y + 36)
  end

  -- Their target, so you can watch alliances of violence unfold.
  if p.target and match.players[p.target] then
    g.setColor(1, 1, 1, 0.45)
    g.print("-> " .. match.players[p.target].name, pn.x + 8, pn.y + 50)
  end

  -- Dice.
  for _, die in ipairs(pn.dice) do die:draw() end
end

function state:draw()
  local g = love.graphics
  local w, h = g.getDimensions()

  if failReason then
    screen.drawFelt()
    g.setFont(screen.fonts.body)
    g.setColor(1, 0.7, 0.6)
    g.printf("Can't enter the Boneyard: " .. failReason, 0, h * 0.4, w, "center")
    if widgets.button(w / 2 - 90, h * 0.5, 180, 46, "BACK") then
      Gamestate.switch(require("states.menu"))
    end
    widgets.endFrame()
    return
  end

  juice.attach()
  screen.drawFelt()

  -- Header: round, pot, mutators.
  g.setFont(screen.fonts.body)
  g.setColor(1, 0.92, 0.7)
  g.print(("THE BONEYARD   ROUND %d   POT %d"):format(match.round, match.pot), 24, 16)
  g.setFont(screen.fonts.small)
  local mx = 24
  for _, m in ipairs(match.mutators) do
    g.setColor(0.85, 0.4, 1)
    g.print("[" .. m.name .. "]", mx, 44)
    mx = mx + screen.fonts.small:getWidth("[" .. m.name .. "]") + 12
  end
  -- Rake status.
  local rakeStart = config.br.rakeStartRound + match.knobs.rakeStartDelta
  if match.round > rakeStart then
    g.setColor(1, 0.3, 0.25)
    g.print("THE RAKE IS COLLECTING", mx + 8, 44)
  elseif rakeStart - match.round <= 3 then
    g.setColor(1, 0.6, 0.3)
    g.print(("THE RAKE ARRIVES IN %d"):format(rakeStart - match.round), mx + 8, 44)
  end

  for idx in pairs(panels) do drawPanel(idx) end
  particles.draw()

  -- Kill feed, right edge.
  g.setFont(screen.fonts.small)
  for i, line in ipairs(match.feed) do
    g.setColor(1, 1, 1, 0.25 + 0.75 * (i / #match.feed))
    g.printf(line, w - 340, h - 210 + (i - #match.feed) * 18 + 140, 320, "right")
  end

  -- Your controls.
  local me = match.players[1]
  if phase == "targeting" and me.alive then
    g.setFont(screen.fonts.small)
    g.setColor(1, 1, 1, 0.7)
    local tname = me.target and match.players[me.target]
      and match.players[me.target].name or "?"
    g.print("TARGET: " .. tname .. "   (click an opponent to change)",
      panels[1].x, panels[1].y - 22)
    if widgets.button(w - 220, h - 90, 188, 54, "ROLL",
      { color = { 0.65, 0.15, 0.15 } }) then
      startRoll()
    end
  end

  -- Popups on top.
  g.setFont(screen.fonts.body)
  for _, p in ipairs(popups) do
    g.setColor(p.color[1], p.color[2], p.color[3], math.min(1, p.t))
    g.print(p.text, p.x, p.y)
  end

  juice.detach()
  juice.drawOverlay(w, h)
  if rakeFlash > 0 then
    g.setColor(0.6, 0.05, 0.05, rakeFlash * 0.3)
    g.rectangle("fill", 0, 0, w, h)
  end

  -- Final standings.
  if phase == "over" and match.summary then
    local s = match.summary
    local pw, ph = 520, 300 + 26 * math.min(4, #s.achievements + 1)
    local px, py = w / 2 - pw / 2, h / 2 - ph / 2
    g.setColor(0, 0, 0, 0.8)
    g.rectangle("fill", 0, 0, w, h)
    g.setColor(0.08, 0.1, 0.09)
    g.rectangle("fill", px, py, pw, ph, 12)
    g.setColor(1, 0.84, 0.3)
    g.rectangle("line", px, py, pw, ph, 12)
    g.setFont(screen.fonts.header)
    g.setColor(s.placement == 1 and { 1, 0.84, 0.3 } or { 1, 1, 1, 0.9 })
    g.printf(s.placement == 1 and "LAST BONES STANDING"
      or ("ELIMINATED  -  #%d"):format(s.placement), px, py + 22, pw, "center")
    g.setFont(screen.fonts.body)
    g.setColor(1, 1, 1, 0.9)
    local lines = {
      ("Kills: %d    Damage dealt: %d    Rounds: %d")
        :format(s.kills, s.damageDealt, s.rounds),
      ("Prize: %d    Bounties: %d%s"):format(s.prize, s.bounties,
        s.bloodMoney > 0 and ("    Blood money: " .. s.bloodMoney) or ""),
      ("TOTAL WON: %d chips"):format(s.totalWon),
    }
    for i, line in ipairs(lines) do
      g.printf(line, px, py + 80 + (i - 1) * 30, pw, "center")
    end
    g.setFont(screen.fonts.small)
    for i, a in ipairs(s.achievements) do
      g.setColor(0.6, 1, 0.7)
      g.printf("ACHIEVEMENT: " .. a.label, px, py + 175 + (i - 1) * 22, pw, "center")
    end
    g.setColor(1, 1, 1, 1)
    if widgets.button(px + pw / 2 - 90, py + ph - 66, 180, 46, "CONTINUE") then
      save.autosave("br_end")
      Gamestate.switch(require("states.menu"))
    end
  end

  widgets.endFrame()
  g.setColor(1, 1, 1, 1)
end

function state:mousepressed(x, y, button)
  widgets.pressed(x, y, button)
  if button ~= 1 or not match or phase ~= "targeting" then return end
  for idx, pn in pairs(panels) do
    if idx ~= 1 and x >= pn.x and x <= pn.x + pn.w
      and y >= pn.y and y <= pn.y + pn.h then
      match:setTarget(idx)
      sfx.play("ui_click")
      return
    end
  end
end

function state:keypressed(key)
  if key == "space" then startRoll() end
  if key == "escape" then
    if match and not match.over then
      -- Leaving mid-match forfeits placement: fast-forward without you
      -- (you stop rolling), then settle so the entry fee isn't limbo'd.
      match.players[1].alive = false
      match.eliminationOrder[#match.eliminationOrder + 1] = 1
      match:fastForward()
      save.autosave("br_end")
    end
    Gamestate.switch(require("states.menu"))
  end
end

function state:resize()
  if match then layoutPanels() end
end

return state
