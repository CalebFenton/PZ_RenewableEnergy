-- One gasifier on the authority (single player or the server): its fire, the wood it burns, the
-- ash and tar that burning leaves, and the gas it gives the generator it is piped to.
--
-- The table is the gasifier's global object (SGlobalObject), so every field in SAVED_FIELDS is
-- saved with the world. A lit gasifier burns IDLE_KG_PER_HOUR in its own pass; the generator's gas
-- line (GasLines.run) bills the load on top through supply(). The hopper and filter are its
-- containers, so it only takes more wood, and tars more packing, while its chunk is loaded; while
-- unloaded a lit gasifier burns down what is in the firebox (`fireKg`) and goes out.

if isClient() then return end

require "Map/SGlobalObject"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Fumes"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/WoodGas/Gasifier"

RenewableEnergy = RenewableEnergy or {}
local Gasifier, GasKit, Sprites = RenewableEnergy.Gasifier, RenewableEnergy.GasKit, RenewableEnergy.Sprites

local GasifierObject = SGlobalObject:derive("RenewableEnergy_Gasifier")
RenewableEnergy.GasifierObject = GasifierObject

-- The fields the Global Object System saves with the world; a field renamed here is lost from
-- existing saves.
GasifierObject.SAVED_FIELDS = {
    "tier", "lit", "fireKg", "fireCharcoal", "ash", "tarKg", "outSince", "pipe", "lastHour",
}

-- A pass longer than this (a save loaded after the clock jumped) counts as this long.
local LONGEST_PASS = 24 * 7
local EPSILON = 1e-4

function GasifierObject:new(luaSystem, globalObject)
    return SGlobalObject.new(self, luaSystem, globalObject)
end

function GasifierObject:initNew()
    self.lit = false
    self.fireKg = 0
    self.fireCharcoal = false
    self.ash = 0
    self.tarKg = 0
    self.lastHour = getGameTime():getWorldAgeHours()
end

--- An object the system has not seen: a gasifier just built. It gets its filter.
function GasifierObject:stateFromIsoObject(isoObject)
    self:initNew()
    self.tier = Gasifier.tierOf(isoObject)
    if not Gasifier.filterOf(isoObject) then
        local filter = ItemContainer.new(Gasifier.FILTER, isoObject:getSquare(), isoObject)
        filter:setCapacity(Gasifier.TIERS[self.tier].filterCapacity)
        isoObject:addSecondaryContainer(filter)
        if isServer() then
            isoObject:sendObjectChange(IsoObjectChange.CONTAINERS)
        end
    end
    self:loaded(isoObject)
end

function GasifierObject:stateToIsoObject(isoObject)
    self:loaded(isoObject)
end

function GasifierObject:loaded(isoObject)
    local square = isoObject:getSquare()
    self.indoors = square:getBuilding() ~= nil and not square:isOutside()
    Gasifier.adoptContainers(isoObject)
    self:afterChange()
end

function GasifierObject:tierSpec()
    return Gasifier.TIERS[self.tier]
end

function GasifierObject:key()
    return "gasifier:" .. self.x .. "," .. self.y .. "," .. self.z
end

-- Burning ------------------------------------------------------------------------------------

-- Puts the next item of fuel from the hopper into the firebox. Returns whether there was one.
function GasifierObject:stoke(hopper)
    local items = hopper and hopper:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        local item = items:get(i)
        local kg = Gasifier.fuelKg(item)
        if kg then
            hopper:Remove(item)
            sendRemoveItemFromContainer(hopper, item)
            self.fireKg = self.fireKg + kg
            self.fireCharcoal = Gasifier.isCharcoal(item)
            return true
        end
    end
    return false
end

-- Turns one clean packing item in the filter to Tarry Packing. Returns whether there was one.
function GasifierObject:tarOne(filter)
    local items = filter and filter:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        local item = items:get(i)
        if Gasifier.isPacking(item) then
            filter:Remove(item)
            sendRemoveItemFromContainer(filter, item)
            local tarry = filter:AddItem(Gasifier.TARRY)
            if tarry then
                sendAddItemToContainer(filter, tarry)
            end
            return true
        end
    end
    return false
end

--- Burns up to `kg` of fuel, stoking from the hopper as the firebox empties, and leaves its ash
--- and tar. Returns the kilograms burned; short of `kg`, the fire went out.
function GasifierObject:burn(kg)
    local isoObject = self:getIsoObject()
    local hopper = isoObject and Gasifier.hopperOf(isoObject)
    local filter = isoObject and Gasifier.filterOf(isoObject)
    local spec = self:tierSpec()
    local burned = 0
    while burned + EPSILON < kg do
        if self.fireKg <= EPSILON and not self:stoke(hopper) then
            self:goOut()
            break
        end
        local now = math.min(kg - burned, self.fireKg)
        self.fireKg = self.fireKg - now
        burned = burned + now
        local charcoal = self.fireCharcoal
        self.ash = math.min(100, self.ash + now * spec.ashPerKg * (charcoal and Gasifier.CHARCOAL_ASH or 1))
        self.tarKg = self.tarKg + now * (charcoal and Gasifier.CHARCOAL_TAR or 1)
        local perItem = spec.tarKgPerItem
        while self.tarKg >= perItem do
            if not (filter and self:tarOne(filter)) then
                -- Nothing clean left to tar: the tar goes through to the engine.
                self.tarKg = perItem
                break
            end
            self.tarKg = self.tarKg - perItem
        end
    end
    return burned
end

function GasifierObject:goOut()
    if self.lit then
        self.lit = false
        self.outSince = getGameTime():getWorldAgeHours()
    end
end

--- Whether lighting it takes bellows: out long enough to have gone cold, or never lit.
function GasifierObject:isCold()
    return not self.lit and (self.outSince == nil
        or getGameTime():getWorldAgeHours() - self.outSince > Gasifier.COLD_HOURS)
end

-- The gas line's source ------------------------------------------------------------------------

function GasifierObject:filterCounts()
    local isoObject = self:getIsoObject()
    return Gasifier.filterCounts(isoObject and Gasifier.filterOf(isoObject))
end

--- What it carries, as a share of what a generator carries on gas: a full ash pit or a spent
--- filter halves it.
function GasifierObject:outputShare()
    local clean = self:filterCounts()
    local share = 1
    if self.ash >= 100 then
        share = share * Gasifier.DIRTY_OUTPUT
    end
    if clean == 0 then
        share = share * Gasifier.DIRTY_OUTPUT
    end
    return share
end

function GasifierObject:canSupply()
    return self.lit and self:getIsoObject() ~= nil
end

function GasifierObject:capW()
    return GasKit.CAP_W * self:outputShare()
end

--- How much faster the generator wears on this gas: with the tar the filter lets through.
function GasifierObject:wearFactor()
    local clean, tarry = self:filterCounts()
    if clean == 0 then
        return Gasifier.WEAR_DIRTY
    end
    return 1 + (Gasifier.WEAR_DIRTY - 1) * tarry / (clean + tarry)
end

--- Burns the wood a generator delivering `watts` for `hours` takes beyond the idle burn, which
--- the gasifier's own pass bills. Returns whether it kept up.
function GasifierObject:supply(watts, hours)
    local kg = Gasifier.KG_PER_KWH * watts / 1000 * hours
    return self:burn(kg) + EPSILON >= kg and self.lit
end

-- The pass --------------------------------------------------------------------------------------

--- Brings the gasifier up to now: a lit one burns its idle wood.
function GasifierObject:update()
    local now = getGameTime():getWorldAgeHours()
    local hours = math.min(LONGEST_PASS, now - (self.lastHour or now))
    self.lastHour = now
    if hours > 0 and self.lit then
        self:burn(Gasifier.IDLE_KG_PER_HOUR * hours)
    end
    self:afterChange()
end

--- Shows and tells what changed, after a pass or a job.
function GasifierObject:afterChange()
    local isoObject = self:getIsoObject()
    RenewableEnergy.Fumes.set(self:key(), isoObject and isoObject:getSquare():getBuilding(), self.lit and self.indoors)
    self:showLit()
    self:showPipe()
    self:sendSummary()
end

local showOverlay = RenewableEnergy.showOverlay

function GasifierObject:showLit()
    local isoObject = self:getIsoObject()
    if not isoObject then return end
    showOverlay(isoObject, Gasifier.isLitOverlay, self.lit and Sprites.gasifierLit[self.tier] or nil)
end

-- The pipe toward the generator it feeds (`pipe`, the generator's side of it), set by the gas line.
function GasifierObject:showPipe()
    local isoObject = self:getIsoObject()
    if not isoObject then return end
    showOverlay(isoObject, Gasifier.isPipeOverlay, self.pipe and Sprites.gasifierPipe[self.pipe] or nil)
end

-- Summary --------------------------------------------------------------------------------------

local function round(value, places)
    local scale = 10 ^ places
    return math.floor(value * scale + 0.5) / scale
end

--- What every client keeps of the gasifier: what its menu checks and its status window shows.
function GasifierObject:buildSummary()
    local isoObject = self:getIsoObject()
    local clean, tarry = self:filterCounts()
    return {
        tier = self.tier, lit = self.lit == true, cold = self:isCold(),
        fireKg = round(self.fireKg, 1),
        hopperKg = round(Gasifier.hopperKg(isoObject and Gasifier.hopperOf(isoObject)) + self.fireKg, 1),
        ash = math.floor(self.ash),
        clean = clean, tarry = tarry,
        output = round(self:outputShare(), 2), wear = round(self:wearFactor(), 1),
        piped = self.pipe ~= nil,
    }
end

local function same(a, b)
    for key, value in pairs(a) do
        if b[key] ~= value then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

function GasifierObject:sendSummary()
    local summary = self:buildSummary()
    if not (self.summary and same(summary, self.summary)) then
        self.summary = summary
        self:updateOnClient()
    end
end

return GasifierObject
