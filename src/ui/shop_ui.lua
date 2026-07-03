--------------------------------------------------------------------------
-- src/ui/shop_ui.lua
-- Cosmetic dice shop: browse by rarity, live rolling preview, direct buy
-- at a listed price, equip to the loadout. Locked rarities show the
-- "almost unlocked" progress bars. Featured daily rotation banner on top.
--------------------------------------------------------------------------

local config      = require("src.core.config")
local catalog     = require("src.meta.dice_catalog")
local shop        = require("src.meta.shop")
local unlocks     = require("src.meta.unlocks")
local economy     = require("src.core.economy")
local widgets     = require("src.ui.widgets")
local screen      = require("src.ui.screen")
local dice_render = require("src.fx.dice_render")
local sfx         = require("src.audio.sfx")

local shop_ui = {}

local ShopUI = {}
ShopUI.__index = ShopUI

function shop_ui.new(saveData)
  local self = setmetatable({}, ShopUI)
  self.saveData = saveData
  self.selectedId = saveData.equipped[1]
  self.previewDie = dice_render.newDie(0, 0, 110)
  self.previewClock = 0
  self.message = nil
  self.featured = shop.featuredToday()
  return self
end

function ShopUI:select(id)
  self.selectedId = id
  local d = catalog.byId[id]
  self.previewDie.cosmetic = d.cosmetic
  self.previewDie:startTumble(math.floor(love.math.random() * 6) + 1, 0.8)
  sfx.play("ui_click")
end

function ShopUI:update(dt)
  -- The preview die keeps rolling so you see it "live".
  self.previewClock = self.previewClock + dt
  if self.previewClock > 2.2 and not self.previewDie:isRolling() then
    self.previewClock = 0
    self.previewDie:startTumble(math.floor(love.math.random() * 6) + 1, 0.7)
  end
  self.previewDie:update(dt)
end

function ShopUI:drawDieCard(d, x, y, w, h)
  local g = love.graphics
  local owned = shop.owns(self.saveData, d.id)
  local rarityColor = catalog.rarityColors[d.rarity]
  local sel = self.selectedId == d.id

  g.setColor(0.05, 0.05, 0.07, 0.9)
  g.rectangle("fill", x, y, w, h, 8)
  g.setColor(rarityColor[1], rarityColor[2], rarityColor[3], sel and 1 or 0.5)
  g.setLineWidth(sel and 3 or 1)
  g.rectangle("line", x, y, w, h, 8)
  g.setLineWidth(1)

  -- mini die swatch
  g.setColor(d.cosmetic.body)
  g.rectangle("fill", x + 10, y + 10, 30, 30, 6)
  g.setColor(d.cosmetic.pip)
  g.circle("fill", x + 25, y + 25, 4)

  g.setFont(screen.fonts.small)
  g.setColor(1, 1, 1, 0.95)
  g.print(d.name, x + 50, y + 8)
  g.setColor(rarityColor)
  g.print(d.rarity:upper(), x + 50, y + 26)
  g.setColor(1, 0.84, 0.3)
  if owned then
    g.print(shop.isEquipped(self.saveData, d.id) and "EQUIPPED" or "OWNED",
      x + w - 80, y + 8)
  elseif d.price and d.price > 0 then
    g.print(d.price .. " chips", x + w - 90, y + 8)
  end
  g.setColor(1, 1, 1, 1)

  if widgets.hot(x, y, w, h) and love.mouse.isDown(1) == false then end
  return x, y, w, h
end

function ShopUI:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  screen.header("SHOP")
  screen.chipLabel(w - 220, 24, "WALLET", economy.getWallet())

  -- Featured banner.
  g.setFont(screen.fonts.small)
  g.setColor(1, 0.84, 0.3)
  local names = {}
  for _, d in ipairs(self.featured) do names[#names + 1] = d.name end
  g.print("TODAY'S FEATURED: " .. table.concat(names, "  /  "), 40, 76)

  -- Left: dice list grouped by rarity, with progress bars on locked tiers.
  local y = 108
  local cardW, cardH = w * 0.42, 48
  for _, rarity in ipairs(catalog.rarities) do
    local prog = unlocks.progress(self.saveData, rarity)
    g.setFont(screen.fonts.small)
    local rc = catalog.rarityColors[rarity]
    g.setColor(rc[1], rc[2], rc[3])
    g.print(rarity:upper(), 40, y)
    if not prog.unlocked then
      -- "Almost unlocked" bar: the binding constraint of chips/tier gates.
      g.setColor(1, 1, 1, 0.25)
      g.rectangle("fill", 150, y + 4, 220, 10, 4)
      g.setColor(rc[1], rc[2], rc[3], 0.9)
      g.rectangle("fill", 150, y + 4, 220 * prog.overallFrac, 10, 4)
      g.setColor(1, 1, 1, 0.6)
      g.print(("earn %d chips / reach tier %d"):format(
        prog.gate.chips, prog.gate.tier), 380, y)
    end
    y = y + 22
    for _, d in ipairs(catalog.dice) do
      if d.rarity == rarity then
        local x = 40
        self:drawDieCard(d, x, y, cardW, cardH)
        if widgets.hot(x, y, cardW, cardH) then
          -- click select handled via widgets click queue below
        end
        if self.clickX and self.clickX >= x and self.clickX <= x + cardW
          and self.clickY >= y and self.clickY <= y + cardH then
          self:select(d.id)
          self.clickX = nil
        end
        y = y + cardH + 6
      end
    end
    y = y + 8
  end

  -- Right: live preview + buy/equip actions for the selected die.
  local px = w * 0.68
  local d = catalog.byId[self.selectedId]
  if d then
    self.previewDie.x, self.previewDie.y = px + 80, 220
    self.previewDie:draw()
    g.setFont(screen.fonts.header)
    g.setColor(1, 1, 1)
    g.print(d.name, px, 300)
    local rc = catalog.rarityColors[d.rarity]
    g.setFont(screen.fonts.body)
    g.setColor(rc)
    g.print(d.rarity:upper(), px, 334)
    g.setColor(1, 1, 1, 0.85)
    g.setFont(screen.fonts.small)
    g.printf(catalog.describeModifier(d), px, 360, w - px - 40)
    g.printf("Skill modifiers apply in Solo Runs only. In Ranked and "
      .. "Casual this die is purely cosmetic.", px, 400, w - px - 40)

    local owned = shop.owns(self.saveData, d.id)
    if not owned then
      local can = shop.canBuy(self.saveData, d.id)
      if widgets.button(px, 450, 200, 44,
        ("BUY  -  %d"):format(d.price), { disabled = not can }) then
        local ok, reason = shop.buy(self.saveData, d.id)
        if ok then
          sfx.play("unlock")
          self.message = "Purchased " .. d.name .. "!"
          require("src.core.save").autosave("purchase")
        else
          self.message = reason
        end
      end
      local _, reason = shop.canBuy(self.saveData, d.id)
      if reason and not can then
        g.setColor(1, 0.6, 0.5)
        g.print(reason, px, 500)
      end
    elseif shop.isEquipped(self.saveData, d.id) then
      if widgets.button(px, 450, 200, 44, "UNEQUIP",
        { color = { 0.4, 0.3, 0.15 } }) then
        local ok, reason = shop.unequip(self.saveData, d.id)
        self.message = ok and (d.name .. " unequipped") or reason
        if ok then require("src.core.save").autosave("loadout") end
      end
    else
      if widgets.button(px, 450, 200, 44, "EQUIP") then
        local ok, reason = shop.equip(self.saveData, d.id)
        self.message = ok and (d.name .. " equipped") or reason
        if ok then require("src.core.save").autosave("loadout") end
      end
    end
    g.setFont(screen.fonts.small)
    g.setColor(1, 1, 1, 0.7)
    g.print(("Loadout %d/%d"):format(#self.saveData.equipped,
      config.pve.loadoutSize), px, 510)
    if self.message then
      g.setColor(1, 0.9, 0.6)
      g.print(self.message, px, 534)
    end
  end
  g.setColor(1, 1, 1, 1)
end

--- Track raw clicks for card selection (widgets consumes button clicks).
function ShopUI:mousepressed(x, y, button)
  if button == 1 then self.clickX, self.clickY = x, y end
end

return shop_ui
