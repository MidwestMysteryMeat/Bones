--------------------------------------------------------------------------
-- states/pve.lua
-- The Solo Run screen: the full playable PvE loop with all the juice -
-- dice tumble, hitstop, screenshake, win particles, near-miss slow-mo,
-- streak riser, jackpot fountain, and the run summary at the end.
--------------------------------------------------------------------------

local Gamestate   = require("lib.hump.gamestate")
local config      = require("src.core.config")
local pve         = require("src.modes.pve")
local save        = require("src.core.save")
local economy     = require("src.core.economy")
local catalog     = require("src.meta.dice_catalog")
local hudmod      = require("src.ui.hud")
local screen      = require("src.ui.screen")
local widgets     = require("src.ui.widgets")
local results_ui  = require("src.ui.results_ui")
local juice       = require("src.fx.juice")
local particles   = require("src.fx.particles")
local dice_render = require("src.fx.dice_render")
local sfx         = require("src.audio.sfx")
local steam       = require("src.steam.steam")

local state = {}

local run, hud
local dieViews = {}
local rolling = false
local pendingRoll, pendingEvents = nil, nil
local achToasts = {}   -- { text, time }
local failReason = nil

local function diceCosmetics()
  -- Visuals follow the equipped loadout; fall back to starter ivory.
  local cosmetics = {}
  for i = 1, 2 do
    local id = save.data.equipped[((i - 1) % #save.data.equipped) + 1]
    local d = catalog.byId[id]
    cosmetics[i] = d and d.cosmetic or nil
  end
  return cosmetics
end

function state:enter()
  failReason = nil
  run = nil
  local r, reason = pve.newRun(save.data)
  if not r then
    failReason = reason
    return
  end
  run = r
  steam.presence("Solo Run - Tier 1")

  local w, h = love.graphics.getDimensions()
  local cosmetics = diceCosmetics()
  dieViews = {
    dice_render.newDie(w / 2 - 55, h * 0.62, 84, cosmetics[1]),
    dice_render.newDie(w / 2 + 55, h * 0.62, 84, cosmetics[2]),
  }
  rolling = false
  achToasts = {}

  hud = hudmod.new({
    wallet = function() return run.bankroll end,
    betOn = function(betId)
      local total = 0
      for _, b in ipairs(run.table.bets) do
        if b.betId == betId then total = total + b.amount end
      end
      return total
    end,
    placeBet = function(betId, amount) return run:placeBet(betId, amount) end,
    canBet = function() return not rolling and not run.over end,
    requestRoll = function() state.doRoll() end,
    info = function()
      local tier = run:tier()
      return {
        phase = run.table.phase, point = run.table.point,
        headline = ("TIER %d  -  %s   (advance at %d)")
          :format(run.tierIndex, tier.name, tier.target),
        jackpot = run.table.jackpotPool,
        streak = run.winStreak,
        feverPct = math.min(math.max(run.winStreak - 1, 0),
          config.fever.maxSteps) * config.fever.stepPct * 100,
        messages = run.messages,
        minBet = tier.minBet, maxBet = tier.maxBet,
      }
    end,
  })
end

function state.doRoll()
  if rolling or run.over then return end
  if run.table:playerExposure("player") == 0 then
    hud:say("place a bet first")
    return
  end
  rolling = true
  sfx.play("dice_rattle")

  -- Resolve the outcome NOW; the animation reveals it. This is what makes
  -- the near-miss slow-mo possible: we know the result before the reveal.
  pendingRoll, pendingEvents = run:roll()

  local exposure = 0
  for _, r in ipairs(pendingRoll.resolved) do
    exposure = exposure + r.bet.amount
  end
  local nearMiss = pve.isNearMiss(pendingRoll, exposure, run.table.limits.min)

  local dur = 0.9
  if nearMiss then
    -- The single most important "one more roll" hook: stretch the reveal,
    -- slow the world, duck the music, zoom in slightly.
    dur = 1.6
    juice.slowmo(0.35, 1.2, 1.14)
    sfx.duck(1.3)
  end

  local landed = 0
  for i, dv in ipairs(dieViews) do
    local face = pendingRoll.dice[i] or 1
    dv:startTumble(face, dur + (i - 1) * 0.12, function()
      landed = landed + 1
      sfx.play("dice_land", { pitch = 0.95 + i * 0.05 })
      particles.sparks(dv.x, dv.y + dv.size / 2)
      if landed == #dieViews then state.reveal() end
    end)
  end
end

function state.reveal()
  rolling = false
  local roll, events = pendingRoll, pendingEvents
  if not roll then return end
  pendingRoll, pendingEvents = nil, nil

  juice.hitstop(0.07)
  local w, h = love.graphics.getDimensions()

  if events.net > 0 then
    local scale = events.net / (run.table.limits.min * 20)
    juice.shake(4 + math.min(18, scale * 16))
    particles.coinBurst(w / 2, h * 0.62, scale)
    sfx.play("win_chime")
    if run.winStreak >= 2 then sfx.streakRiser(run.winStreak) end
  elseif events.net < 0 then
    juice.shake(3)
    sfx.play("lose_thud")
  end

  if events.jackpotPayout then
    juice.flash({ 1, 0.85, 0.2 }, 0.4)
    juice.shake(22)
    particles.jackpotFountain(w, h, 3.5)
    sfx.play("jackpot")
    state.jackpotTicker = { amount = events.jackpotPayout, shown = 0, t = 0 }
  end

  for _, a in ipairs(events.achievements or {}) do
    achToasts[#achToasts + 1] = { text = "ACHIEVEMENT: " .. a.label, time = 4 }
  end
  if events.tierAdvanced then
    juice.flash({ 0.6, 1, 0.7 }, 0.25)
    steam.presence(("Solo Run - Tier %d"):format(events.tierAdvanced))
  end
  if events.bust then
    save.autosave("run_end")
  end
end

function state:update(dt)
  if failReason then return end
  local sdt = juice.update(dt) -- hitstop/slow-mo scaled dt for the world
  sfx.update(dt)
  widgets.beginFrame()
  hud:update(dt)
  for _, dv in ipairs(dieViews) do dv:update(sdt) end
  particles.update(sdt)

  -- Jackpot payout ticker counts up (real time - it should feel long).
  local jt = state.jackpotTicker
  if jt then
    jt.t = jt.t + dt
    jt.shown = math.min(jt.amount, math.floor(jt.amount * (jt.t / 2.5)))
    if jt.t > 3.5 then state.jackpotTicker = nil end
  end

  for i = #achToasts, 1, -1 do
    achToasts[i].time = achToasts[i].time - dt
    if achToasts[i].time <= 0 then table.remove(achToasts, i) end
  end
end

function state:draw()
  local g = love.graphics
  local w, h = g.getDimensions()

  if failReason then
    screen.drawFelt()
    g.setFont(screen.fonts.body)
    g.setColor(1, 0.7, 0.6)
    g.printf("Can't start a run: " .. failReason, 0, h * 0.4, w, "center")
    if widgets.button(w / 2 - 90, h * 0.5, 180, 46, "BACK") then
      Gamestate.switch(require("states.menu"))
    end
    return
  end

  juice.attach()
  screen.drawFelt()
  hud:draw()
  for _, dv in ipairs(dieViews) do dv:draw() end
  particles.draw()
  juice.detach()
  juice.drawOverlay(w, h)

  -- Jackpot ticker front and center.
  local jt = state.jackpotTicker
  if jt then
    g.setFont(screen.fonts.huge)
    g.setColor(1, 0.84, 0.2)
    g.printf("JACKPOT!", 0, h * 0.28, w, "center")
    g.printf(tostring(jt.shown), 0, h * 0.28 + 80, w, "center")
  end

  -- Achievement toasts, top right.
  g.setFont(screen.fonts.small)
  for i, t in ipairs(achToasts) do
    g.setColor(0, 0, 0, 0.7)
    local tw = screen.fonts.small:getWidth(t.text) + 20
    g.rectangle("fill", w - tw - 20, 90 + (i - 1) * 36, tw, 28, 6)
    g.setColor(0.6, 1, 0.7)
    g.print(t.text, w - tw - 10, 96 + (i - 1) * 36)
  end

  -- Cash out / leave.
  if not run.over then
    if widgets.button(24, h - 100, 150, 40, "CASH OUT",
      { small = true, color = { 0.5, 0.4, 0.1 }, disabled = rolling }) then
      run:cashOut()
      save.autosave("run_end")
    end
  else
    if results_ui.drawRunSummary(run.summary) then
      Gamestate.switch(require("states.menu"))
    end
  end

  widgets.endFrame()
  g.setColor(1, 1, 1, 1)
end

function state:mousepressed(x, y, button)
  widgets.pressed(x, y, button)
  if run and not run.over and hud then hud:mousepressed(x, y, button) end
end

function state:keypressed(key)
  if key == "space" and run and not run.over then state.doRoll() end
  if key == "escape" then
    if run and not run.over then
      run:cashOut()
      save.autosave("run_end")
    else
      Gamestate.switch(require("states.menu"))
    end
  end
end

function state:leave()
  -- Abandoning the screen mid-run banks the bankroll (never lose chips to
  -- a misclick; quitting is the same as cashing out).
  if run and not run.over then
    run:cashOut()
    save.autosave("run_end")
  end
end

return state
