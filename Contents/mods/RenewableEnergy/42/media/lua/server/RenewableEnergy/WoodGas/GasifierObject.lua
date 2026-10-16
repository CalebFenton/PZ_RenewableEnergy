-- One gasifier on the authority (single player or the server): its fire, the wood it burns, the
-- ash and tar that burning leaves, and the gas it gives the generator it is piped to.
--
-- The table is the gasifier's global object (RenewableEnergy.ObjectSystem), so every field in
-- SAVED_FIELDS is saved with the world. A lit gasifier burns IDLE_KG_PER_HOUR in its own pass; the
-- generator's gas line (GasLines.run) bills the load on top through supply(). The hopper and filter
-- are its containers, so it only takes more wood, and tars more packing, while its chunk is
-- loaded; while unloaded a lit gasifier burns down what is in the firebox (`fireKg`) and goes out.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/ObjectSystem"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/WoodGas/Gasifier"

RenewableEnergy = RenewableEnergy or {}
local Gasifier, GasKit, Sprites = RenewableEnergy.Gasifier, RenewableEnergy.GasKit, RenewableEnergy.Sprites

local GasifierObject = RenewableEnergy.ObjectSystem.Object:derive("RenewableEnergy_Gasifier")
RenewableEnergy.GasifierObject = GasifierObject

-- The fields the Global Object System saves with the world; a field renamed here is lost from
-- existing saves.
GasifierObject.SAVED_FIELDS = {
    "tier", "lit", "fireKg", "fireCharcoal", "ash", "tarKg", "condensate", "outSince", "pipe", "lastHour",
}

local EPSILON = 1e-4

function GasifierObject:initNew()
    self.lit = false
    self.fireKg = 0
    self.fireCharcoal = false
    self.ash = 0
    self.tarKg = 0
    self.condensate = 0
    self.lastHour = getGameTime():getWorldAgeHours()
end

--- An object the system has not seen: a gasifier just built. It gets its filter.
function GasifierObject:stateFromIsoObject(isoObject)
    self:initNew()
    self.tier = Gasifier.tierOf(isoObject)
    if not Gasifier.filterOf(isoObject) then
        local filter = ItemContainer.new(Gasifier.FILTER, isoObject:getSquare(), isoObject)
        filter:setCapacity(self:tierSpec().filterCapacity)
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
        self.ash = math.min(Gasifier.ASH_FULL, self.ash + now * spec.ashPerKg * (charcoal and Gasifier.CHARCOAL_ASH or 1))
        -- An undrained filter tars its packing faster.
        local tarFactor = self.condensate >= Gasifier.CONDENSATE_MAX and Gasifier.CONDENSATE_TAR or 1
        self.tarKg = self.tarKg + now * (charcoal and Gasifier.CHARCOAL_TAR or 1) * tarFactor
        self.condensate = math.min(Gasifier.CONDENSATE_MAX, self.condensate + now * Gasifier.CONDENSATE_PER_KG)
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

--- Lights the fire, stoking it first if the firebox is empty. Returns whether there was fuel.
function GasifierObject:light(isoObject)
    if self.fireKg <= EPSILON and not self:stoke(Gasifier.hopperOf(isoObject)) then
        return false
    end
    self.lit = true
    self.outSince = nil
    return true
end

function GasifierObject:goOut()
    if self.lit then
        self.lit = false
        self.outSince = getGameTime():getWorldAgeHours()
    end
end

--- Sets the pipe toward the generator it feeds, by the generator's side of it (Gasifier.sideOf),
--- or nil for none. The gas line lays and cuts it.
function GasifierObject:setPipe(side)
    self.pipe = side
    self:afterChange()
end

-- The gas line's source ------------------------------------------------------------------------

function GasifierObject:filterCounts()
    local isoObject = self:getIsoObject()
    return Gasifier.filterCounts(isoObject and Gasifier.filterOf(isoObject))
end

function GasifierObject:canSupply()
    return self.lit and self:getIsoObject() ~= nil
end

function GasifierObject:capW()
    return GasKit.CAP_W * Gasifier.outputShare(self.ash, (self:filterCounts()))
end

function GasifierObject:wearFactor()
    return Gasifier.wearFactor(self:filterCounts())
end

--- Burns the wood a generator delivering `watts` for `hours` takes beyond the idle burn, which
--- the gasifier's own pass bills. Returns whether it kept up.
function GasifierObject:supply(watts, hours)
    local kg = Gasifier.KG_PER_KWH * watts / 1000 * hours
    return self:burn(kg) + EPSILON >= kg and self.lit
end

-- The pass --------------------------------------------------------------------------------------

--- Burns the idle wood of the `hours` since it last caught up, if lit.
function GasifierObject:advance(hours)
    if hours > 0 and self.lit then
        self:burn(Gasifier.IDLE_KG_PER_HOUR * hours)
    end
end

--- Shows and tells what changed, after a pass or a job.
function GasifierObject:afterChange()
    self:setFuming(self.lit and self.indoors)
    local isoObject = self:getIsoObject()
    if isoObject then
        RenewableEnergy.showOverlay(isoObject, Gasifier.isLitOverlay, self.lit and Sprites.gasifierLit[self.tier] or nil)
        RenewableEnergy.showOverlay(isoObject, Gasifier.isPipeOverlay, self.pipe and Sprites.gasifierPipe[self.pipe] or nil)
    end
    self:sendSummary()
end

-- Summary --------------------------------------------------------------------------------------

--- What every client keeps of the gasifier: what its menu checks and its status window shows.
--- Gasifier's accessors add what its containers hold and what follows from that.
function GasifierObject:buildSummary()
    local round = RenewableEnergy.round
    return {
        tier = self.tier, lit = self.lit == true, outSince = self.outSince,
        fireKg = round(self.fireKg, 1),
        ash = math.floor(self.ash),
        condensate = round(self.condensate, 1),
        piped = self.pipe ~= nil,
    }
end

return GasifierObject
