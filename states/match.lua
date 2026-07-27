--------------------------------------------------------------------------
-- states/match.lua
-- The multiplayer table (ranked AND casual share it). Entered from a
-- lobby with ctx = { client, server (host only), mode }. The server rolls
-- on its bet-lock countdown; this state just mirrors authoritative state,
-- animates the broadcast dice, and shows standings at the end.
--------------------------------------------------------------------------

local Gamestate   = require("lib.hump.gamestate")
local config      = require("src.core.config")
local save        = require("src.core.save")
local pvpmode     = require("src.modes.pvp")
local hudmod      = require("src.ui.hud")
local screen      = require("src.ui.screen")
local widgets     = require("src.ui.widgets")
local results_ui  = require("src.ui.results_ui")
local lobby_ui    = require("src.ui.lobby_ui")
local juice       = require("src.fx.juice")
local particles   = require("src.fx.particles")
local dice_render = require("src.fx.dice_render")
local sfx         = require("src.audio.sfx")
local steam       = require("src.steam.steam")

local state = {}

local ctx            -- { client, server, mode }
local hud, dieViews
local myBets = {}    -- betId -> amount (mirror for HUD display)
local phase, point = "comeout", nil
local pool = 0
local rollHistory = {}
local standings, ratingChange = nil, nil
local errorToast, errorTime = nil, 0

local function syncDiceLayout()
  if not hud or not dieViews then return end
  local tray = hud:getDiceTray()
  local content = tray.content
  for i, die in ipairs(dieViews) do
    die.size = tray.dieSize
    die.x = tray.centerX + (i == 1 and -tray.dieGap or tray.dieGap)
    die.y = tray.centerY
    die:setArena(content.x, content.y, content.w, content.h)
  end
end

function state:enter(_, enterCtx)
  ctx = enterCtx
  standings, ratingChange = nil, nil
  myBets = {}
  rollHistory = {}
  phase, point, pool = "comeout", nil, 0
  steam.presence(ctx.mode == "ranked" and "At a Ranked Table" or "Casual Table")

  local w, h = love.graphics.getDimensions()
  dieViews = {
    dice_render.newDie(0, 0, 84),
    dice_render.newDie(0, 0, 84),
  }

  local c = ctx.client
  c.cb.onBetsOpen = function() myBets = {} end
  c.cb.onBetAccepted = function(data)
    if data.playerId == c.myId then
      myBets[data.betId] = (myBets[data.betId] or 0) + data.amount
      sfx.play("chip_place")
    end
  end
  c.cb.onRoll = function(roll)
    sfx.play("dice_rattle")
    local diceSpeed = math.max(0.5, save.data.settings.diceSpeed or 1)
    syncDiceLayout()
    local landed = 0
    for i, dv in ipairs(dieViews) do
      dv:startTumble(roll.dice[i] or 1,
        0.9 / diceSpeed + (i - 1) * (0.12 / diceSpeed), function()
        landed = landed + 1
        sfx.play("dice_land")
        particles.sparks(dv.x, dv.y + dv.size / 2)
        juice.hitstop(0.05)
        if landed == #dieViews then
          phase, point = roll.phase, roll.point
          rollHistory[#rollHistory + 1] = roll
          if #rollHistory > 20 then table.remove(rollHistory, 1) end
        end
      end)
    end
  end
  c.cb.onSettle = function(data)
    pool = data.pool or pool
    local mine = data.payouts and data.payouts[c.myId]
    if mine and mine > 0 then
      juice.shake(6)
      local tray = hud:getDiceTray()
      particles.coinBurst(tray.centerX, tray.centerY, mine / 200)
      sfx.play("win_chime")
    end
  end
  c.cb.onJackpot = function(data)
    juice.flash({ 1, 0.85, 0.2 }, 0.4)
    particles.jackpotFountain(w, h, 3)
    sfx.play("jackpot")
  end
  c.cb.onMatchEnd = function(data)
    standings = data.standings
    if ctx.mode == "ranked" then
      -- Build the rating update from the authoritative standings.
      local players = {}
      local myNet, myPos = 0, #standings
      for _, s in ipairs(data.standings) do
        players[#players + 1] = {
          id = s.id, position = s.position, netChips = s.netChips,
          -- Only our own true rating is known locally; assume base for
          -- others. TODO(ranked): server should relay each player's rating
          -- in MATCH_END so deltas are exact on every client.
          rating = s.id == c.myId and (save.data.rating or config.ranked.baseRating)
            or config.ranked.baseRating,
        }
        if s.id == c.myId then myNet, myPos = s.netChips, s.position end
      end
      ratingChange = pvpmode.applyMatchResult(save.data, "You", {
        myId = c.myId, players = players,
        position = myPos, netChips = myNet, disconnected = false,
      })
      save.autosave("match_end")
    end
  end
  c.cb.onError = function(msg)
    errorToast, errorTime = msg, 3
  end

  hud = hudmod.new({
    wallet = function() return c.myChips end,
    betOn = function(betId) return myBets[betId] or 0 end,
    placeBet = function(betId, amount)
      c:placeBet(betId, amount) -- intent; server echoes BET_ACCEPTED
      return true
    end,
    canBet = function() return c.betClock > 0 and not standings end,
    requestRoll = nil, -- server rolls on its own clock
    info = function()
      return {
        phase = phase, point = point,
        headline = ("%s TABLE  -  ROUND %d")
          :format(ctx.mode:upper(), c.round or 0),
        jackpot = pool, streak = 0,
        messages = nil,
        rollHistory = rollHistory,
        lockClock = c.betClock > 0 and c.betClock or nil,
      }
    end,
  })
  syncDiceLayout()
end

function state:update(dt)
  local sdt = juice.update(dt)
  sfx.update(dt)
  widgets.beginFrame()
  if ctx.server then ctx.server:update(dt) end
  ctx.client:update(dt)
  hud:update(dt)
  syncDiceLayout()
  for _, dv in ipairs(dieViews) do dv:update(sdt) end
  particles.update(sdt)
  if errorTime > 0 then
    errorTime = errorTime - dt
    if errorTime <= 0 then errorToast = nil end
  end
end

function state:draw()
  local g = love.graphics
  local w, h = g.getDimensions()

  screen.drawFelt()
  hud:draw()

  juice.attach()
  local tray = hud:getDiceTray()
  g.setScissor(tray.content.x, tray.content.y, tray.content.w, tray.content.h)
  for _, dv in ipairs(dieViews) do dv:draw() end
  g.setScissor()
  particles.draw()
  juice.detach()
  hud:drawOverlay()
  juice.drawOverlay(w, h)

  -- Verification badge: every broadcast roll re-derived from its seed.
  local c = ctx.client
  if c.lastRoll then
    g.setFont(screen.fonts.small)
    if c.lastRoll.verified then
      g.setColor(0.5, 1, 0.6, 0.7)
      g.print("ROLL VERIFIED (seed " .. tostring(c.lastRoll.seed) .. ")", 24, 60)
    else
      g.setColor(1, 0.3, 0.3)
      g.print("!! ROLL FAILED VERIFICATION !!", 24, 60)
    end
  end

  -- Chat, bottom center.
  local msg = lobby_ui.drawChat(c.chatLog, w * 0.33, h - 240, w * 0.34)
  if msg then c:chat(msg) end

  if errorToast then
    g.setFont(screen.fonts.body)
    g.setColor(1, 0.5, 0.4)
    g.printf(errorToast, 0, h * 0.5, w, "center")
  end

  if standings then
    if results_ui.drawStandings(standings, c.myId, ratingChange) then
      state.shutdown()
      Gamestate.switch(require("states.menu"))
    end
  end

  widgets.endFrame()
  g.setColor(1, 1, 1, 1)
end

function state.shutdown()
  if ctx then
    if ctx.client then ctx.client:destroy() end
    if ctx.server then ctx.server:destroy() end
    ctx = nil
  end
end

function state:mousepressed(x, y, button)
  widgets.pressed(x, y, button)
  if hud and not standings then hud:mousepressed(x, y, button) end
end

function state:keypressed(key)
  if widgets.keypressed(key) then return end
  if hud and hud:keypressed(key) then return end
  if key == "escape" then
    -- Leaving mid-match: the server folds our bets (ranked forfeits them).
    state.shutdown()
    Gamestate.switch(require("states.menu"))
  end
end

function state:leave()
  state.shutdown()
end

return state
