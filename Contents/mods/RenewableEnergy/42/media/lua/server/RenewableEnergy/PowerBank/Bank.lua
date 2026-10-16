-- One battery bank on the authority (single player or the server): its batteries, inverters,
-- chargers, controllers, panels, wind chargers and backup generator, and the energy that moves
-- between them each pass.
--
-- The table is the bank's global object (SGlobalObject), so every field named in
-- SAVED_FIELDS is saved with the world and kept while the chunk is unloaded. While loaded,
-- the container is the truth about what the bank holds and each battery's own charge is
-- the truth about the charge; while unloaded, the snapshot in `batteries` and `charge`
-- carries on and is written back into the batteries when the chunk loads, and so is the wear
-- the parts took meanwhile.

if isClient() then return end

require "Map/SGlobalObject"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/Wind"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/GasLine/GasKit"
local Loads = require "RenewableEnergy/PowerBank/Loads"

RenewableEnergy = RenewableEnergy or {}
local Specs, Sprites, Sun, Wind = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun, RenewableEnergy.Wind
local Battery, Wear, PowerBank = RenewableEnergy.Battery, RenewableEnergy.Wear, RenewableEnergy.PowerBank

local Bank = SGlobalObject:derive("RenewableEnergy_Bank")
RenewableEnergy.Bank = Bank

-- The fields the Global Object System saves with the world; a field renamed here is lost from
-- existing saves.
Bank.SAVED_FIELDS = {
    "bankType", "name", "on", "overloaded", "indoors", "gridPowered", "charge", "nominalWh", "batteries",
    "inverters", "chargers", "controllers", "sources", "loadW", "averageLoadW", "loadByKind", "chargeSource",
    "generator", "lastHour", "day", "cycleHigh", "cycleDepth", "pendingDepths", "pendingPartWear",
    "solarWhToday", "loadWhToday", "empty", "windWhToday",
}

-- A backup generator a failsafe can start is one plugged in within this many tiles on the
-- bank's floor.
local BACKUP_REACH = 3
-- Snow cover on a panel, as a share of the panel per hour: falling snow adds it, mild air and
-- sun melt it, and a rack sheds it in sun or mild air.
local SNOW_PER_HOUR = 0.5
local SNOW_MELT_PER_HOUR = 0.1
local SNOW_SUN_MELT_PER_HOUR = 0.05
local RACK_SHED_PER_HOUR = 0.5
local RACK_SHEDS_ABOVE_C = -2
-- Snow this deep shows on the panel's tile.
local SNOW_SHOWN = 0.5
-- A panel making less than this share of what it would in clear full sun names the biggest
-- reason in the status.
local LOW_SHARE = 0.7
-- Vanilla bills generators in fuel per hour per unit of power; a unit is this many watts.
local WATTS_PER_FUEL_UNIT = Specs.loads.other.wattsPerConsumption

function Bank:new(luaSystem, globalObject)
    return SGlobalObject.new(self, luaSystem, globalObject)
end

function Bank:initNew()
    self.on = false
    self.overloaded = false
    self.indoors = true
    self.gridPowered = false
    self.charge = 0
    self.nominalWh = 0
    self.batteries = {}
    self.inverters = {}
    self.chargers = {}
    self.controllers = {}
    self.sources = {}
    self.loadW = 0
    self.averageLoadW = 0
    self.loadByKind = {}
    self.chargeSource = false
    self.generator = false
    self.cycleHigh = 0
    self.cycleDepth = 0
    self.pendingDepths = {}
    self.pendingPartWear = { hours = 0, overloads = 0 }
    self.solarWhToday = 0
    self.windWhToday = 0
    self.loadWhToday = 0
    self.empty = false
    self.lastHour = getGameTime():getWorldAgeHours()
end

--- An object the bank system has not seen: a bank just placed, or one from a save whose
--- global objects were lost.
function Bank:stateFromIsoObject(isoObject)
    self:initNew()
    self.bankType = PowerBank.bankOfSprite(Sprites.nameOf(isoObject)).fullType
    self:loaded(isoObject)
end

--- The bank's chunk loaded: hand the charge and wear it kept while unloaded back to its parts.
function Bank:stateToIsoObject(isoObject)
    local container = isoObject:getContainer()
    if container then
        self:writeBatteries(container, true)
        self:applyPendingPartWear(container)
    end
    self:loaded(isoObject)
end

function Bank:loaded(isoObject)
    -- IsoGenerator.update would burn fuel, wear the condition and run an engine sound.
    isoObject:getCell():addToProcessIsoObjectRemove(isoObject)
    self.indoors = PowerBank.canPlaceBank(isoObject:getSquare())
    self:recount()
    self:switchGenerator()
    self:sendStatus()
end

--- Look at the container again, whatever filled or emptied it: the parts it holds, whether the
--- bank runs, the batteries on its tile and the status the clients see.
function Bank:refresh()
    self:recount()
    self:switchGenerator()
    self:showBatteries()
    self:sendStatus()
end

function Bank:spec()
    return Specs.banks[self.bankType]
end

-- Parts ----------------------------------------------------------------------------------

local function partEntry(item)
    return { id = item:getID(), type = item:getFullType(), condition = item:getCondition() }
end

--- Read what the container holds into the bank's snapshot. Does nothing without one: a
--- bank whose container hasn't arrived isn't a bank holding nothing.
function Bank:recount()
    local isoObject = self:getIsoObject()
    local container = isoObject and isoObject:getContainer()
    if not container then return end
    local parts = { battery = {}, inverter = {}, charger = {}, controller = {} }
    local nominalWh, storedWh = 0, 0
    local items = container:getItems()
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        local kind = PowerBank.partKind(item:getFullType())
        if kind == "battery" then
            local wh = Battery.nominalWh(item)
            nominalWh = nominalWh + wh
            storedWh = storedWh + wh * Battery.getCharge(item)
            local entry = partEntry(item)
            entry.nominalWh = wh
            table.insert(parts.battery, entry)
        elseif kind then
            table.insert(parts[kind], partEntry(item))
        end
    end
    self.batteries = parts.battery
    self.inverters = parts.inverter
    self.chargers = parts.charger
    self.controllers = parts.controller
    self.nominalWh = nominalWh
    self.charge = nominalWh > 0 and storedWh / nominalWh or 0
end

--- Put the bank's charge into every battery it holds: the batteries are wired in parallel,
--- so they share one state of charge. Pending wear from days spent unloaded lands too.
function Bank:writeBatteries(container, applyPending)
    local scale = applyPending and Battery.wearScale()
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local spec = Battery.spec(item)
        if spec and item:getCondition() > 0 then
            -- As the arrow board and the maintainer do: clients hear of the charge once it shows
            -- at two decimals.
            local changed = VehicleUtils.compareFloats(Battery.getCharge(item), self.charge, 2)
            Battery.setCharge(item, self.charge)
            if applyPending then
                for _, depth in ipairs(self.pendingDepths) do
                    changed = Battery.wear(item, Battery.cycleWear(spec, depth) * scale) or changed
                end
            end
            if changed then
                sendItemStats(item)
            end
        end
    end
    if applyPending then
        self.pendingDepths = {}
    end
end

-- Wear every battery by one discharge `depth` deep.
function Bank:wearBatteries(container, depth)
    local scale = Battery.wearScale()
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local spec = Battery.spec(item)
        if spec and Battery.wear(item, Battery.cycleWear(spec, depth) * scale) then
            sendItemStats(item)
        end
    end
end

local function working(part)
    return part.condition > 0
end

-- The sum of Specs.inverters[type][field] over the bank's working inverters.
local function sumInverters(bank, field)
    local total = 0
    for _, inverter in ipairs(bank.inverters) do
        if working(inverter) then
            total = total + Specs.inverters[inverter.type][field]
        end
    end
    return total
end

--- The watts the bank's working inverters carry together.
function Bank:limitW()
    return sumInverters(self, "watts")
end

--- The watts the bank's working chargers, and the chargers built into its inverters, put in
--- while grid or generator power reaches it.
function Bank:chargerW()
    local watts = sumInverters(self, "chargerWatts")
    for _, charger in ipairs(self.chargers) do
        if working(charger) then
            watts = watts + Specs.chargerWatts
        end
    end
    return watts
end

--- How many input slots the bank has: a few on their own, and more for each working controller.
function Bank:inputSlots()
    local slots = Specs.freeSlots
    for _, controller in ipairs(self.controllers) do
        if working(controller) then
            slots = slots + Specs.slotsPerController
        end
    end
    return slots
end

--- The input slots its sources take.
function Bank:slotsUsed()
    local used = 0
    for _, source in ipairs(self.sources) do
        used = used + PowerBank.slotsOf(source.kind)
    end
    return used
end

-- Inverters and controllers wear while they work, and an overload strains the inverters.
function Bank:wearParts(container, hours, overloads)
    local wear = Specs.partWear
    local inverterPoints = wear.inverterPerHour * hours + wear.overload * overloads
    local controllerPoints = wear.controllerPerHour * hours
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local kind = PowerBank.partKind(item:getFullType())
        local points = (kind == "inverter" and inverterPoints) or (kind == "controller" and controllerPoints) or 0
        if Wear.take(item, points) then
            sendItemStats(item)
        end
    end
end

-- Wear now if the parts are at hand, else when the chunk next loads.
function Bank:addPartWear(container, hours, overloads)
    if container then
        self:wearParts(container, hours, overloads)
    else
        self.pendingPartWear.hours = self.pendingPartWear.hours + hours
        self.pendingPartWear.overloads = self.pendingPartWear.overloads + overloads
    end
end

function Bank:applyPendingPartWear(container)
    local pending = self.pendingPartWear
    self:wearParts(container, pending.hours, pending.overloads)
    self.pendingPartWear = { hours = 0, overloads = 0 }
end

-- Panels ---------------------------------------------------------------------------------

local CONDITION_MAX = {}

-- A module type's ConditionMax, from its item script.
local function conditionMax(fullType)
    if not CONDITION_MAX[fullType] then
        local script = getScriptManager():FindItem(fullType)
        CONDITION_MAX[fullType] = script and script:getConditionMax() or 100
    end
    return CONDITION_MAX[fullType]
end

--- The watts a panel's modules are rated for as they are now, and at their best.
local function sourceWatts(source)
    local now, best = 0, 0
    for _, module in ipairs(source.modules) do
        now = now + PowerBank.moduleWatts(module.type, module.condition)
        best = best + PowerBank.moduleWatts(module.type, conditionMax(module.type))
    end
    return now, best
end

function Bank:findSource(x, y, z)
    for i, source in ipairs(self.sources) do
        if source.x == x and source.y == y and source.z == z then
            return source, i
        end
    end
    return nil
end

function Bank:addSource(isoObject)
    local kind, facing, material = PowerBank.sourceKind(isoObject)
    local source = { x = isoObject:getX(), y = isoObject:getY(), z = isoObject:getZ(), kind = kind, watts = 0 }
    if PowerBank.isWind(kind) then
        source.braked = PowerBank.isBraked(isoObject)
        source.shelter = Wind.shelterAt(source.x, source.y, source.z)
    else
        source.facing, source.material, source.snow = facing, material, 0
        source.modules = PowerBank.modulesOf(isoObject, kind)
    end
    table.insert(self.sources, source)
end

--- Brakes the wind charger `source` (on `object` when loaded) or lets it go.
function Bank:setBrake(source, braked, object)
    source.braked = braked
    if object then
        PowerBank.setBraked(object, braked)
    end
end

function Bank:removeSource(x, y, z)
    local _, index = self:findSource(x, y, z)
    if index then
        table.remove(self.sources, index)
        return true
    end
    return false
end

-- Snow cover after `hours` of the weather in `context`.
local function updateSnow(source, hours, context)
    if source.kind == "wall" then
        source.snow = 0
        return
    end
    local snow = source.snow or 0
    if context.weather.snowing then
        snow = snow + SNOW_PER_HOUR * context.precipitation * hours
    end
    if context.airC > 0 then
        snow = snow - SNOW_MELT_PER_HOUR * hours
    end
    local sun = context.irradiance(source.kind, source.facing) / Sun.FULL_SUN
    snow = snow - SNOW_SUN_MELT_PER_HOUR * sun * hours
    if source.kind == "rack" and (context.airC > RACK_SHEDS_ABOVE_C or sun > 0) then
        snow = snow - RACK_SHED_PER_HOUR * hours
    end
    source.snow = math.max(0, math.min(1, snow))
end

local function snowOverlay(source)
    if source.kind == "flat" then
        return Sprites.snow.flat
    end
    local rack = source.kind == "rack" and Sprites.snow.rack[source.material]
    return rack and rack[source.facing]
end

local function showSnow(object, source)
    local overlay = snowOverlay(source)
    if not overlay then return end
    local wanted = source.snow >= SNOW_SHOWN
    local attached = object:getAttachedAnimSprite()
    local index
    for i = 0, (attached and attached:size() or 0) - 1 do
        if attached:get(i):getName() == overlay then
            index = i
        end
    end
    if wanted == (index ~= nil) then return end
    if wanted then
        object:addAttachedAnimSpriteByName(overlay)
    else
        object:RemoveAttachedAnim(index)
    end
    object:transmitUpdatedSpriteToClients()
end

--- Someone swept the panel.
function Bank:clearSnow(source, object)
    source.snow = 0
    if object then
        showSnow(object, source)
    end
end

--- How likely a storm is to crack a module of a mount, relative to Specs.storm.chancePerHour.
local function stormFactor(mount, material)
    local materialSpec = material and Specs.materials[material]
    return Specs.mounts[mount].stormFactor * (materialSpec and materialSpec.stormFactor or 1)
end

--- The hours of a pass of `hours`, ending now, in which a thunderstorm can crack modules: all
--- of them while one blows hard enough, else none.
function Bank.stormHours(hours)
    local climate = getClimateManager()
    local storming = climate:getIsThunderStorming() and climate:getWindspeedKph() >= Specs.storm.windMin
    return storming and hours or 0
end

--- A thunderstorm may crack one of a panel's modules. Returns whether it did.
function Bank.stormCrack(source, stormHours)
    local options = SandboxVars.RenewableEnergy
    if not options.StormDamage or stormHours <= 0 then
        return false
    end
    local perHour = Specs.storm.chancePerHour * stormFactor(source.kind, source.material) * options.StormDamageRate / 100
    local chance = 1 - (1 - math.min(1, perHour)) ^ stormHours
    local whole = {}
    for _, module in ipairs(source.modules) do
        if module.condition > 0 then
            table.insert(whole, module)
        end
    end
    if #whole == 0 or ZombRandFloat(0, 1) >= chance then
        return false
    end
    local module = whole[ZombRand(#whole) + 1]
    module.condition = math.max(0, module.condition - Specs.storm.crack)
    return true
end

-- Keep a panel's module record and the bank's copy the same: a crack while the panel's square
-- was unloaded goes to the object, otherwise the object (which unmounting and repairs change)
-- is the truth. Either way the tile shows the cracks the record now holds.
local function syncModules(source, object)
    if source.modulesChanged then
        PowerBank.writeModules(object, source.modules)
        source.modulesChanged = nil
    else
        source.modules = PowerBank.modulesOf(object, source.kind)
    end
    PowerBank.showCracks(object)
end

-- Why a panel makes less than it would at its best in clear full sun: the biggest loss, if it
-- is big enough to matter. On a tie the first reason checked wins.
local function lowReason(source, inSlot, light, clearLight, condition, context)
    if not inSlot then
        return "noController"
    elseif context.elevation <= 0 or clearLight <= 0 then
        return "night"
    end
    local reason, lowest = nil, LOW_SHARE
    local share = 1 - source.snow
    if share < lowest then reason, lowest = "snow", share end
    share = light / clearLight
    if share < lowest then reason, lowest = "cloud", share end
    share = clearLight / Sun.FULL_SUN
    if share < lowest then reason, lowest = "angle", share end
    if condition < lowest then reason = "cracked" end
    return reason
end

-- A panel's output over the pass, and why it is low.
local function panelWatts(source, object, inSlot, hours, context)
    if Bank.stormCrack(source, context.stormHours) then
        source.modulesChanged = true
    end
    if object then
        syncModules(source, object)
    end
    updateSnow(source, hours, context)
    if object then
        showSnow(object, source)
    end
    local light = context.irradiance(source.kind, source.facing)
    local clearLight = context.clearIrradiance(source.kind, source.facing)
    local now, best = sourceWatts(source)
    source.watts = inSlot and Sun.wattsFrom(now, light, source.snow) or 0
    source.fullSunPct = math.floor(100 * light * (1 - source.snow) / Sun.FULL_SUN + 0.5)
    source.reason = lowReason(source, inSlot, light, clearLight, best > 0 and now / best or 0, context)
end

-- A wind charger's output over the pass, and why it makes nothing or little: braked, calm, or
-- sheltered. Its brake is the object's while it is loaded (the menu sets both), and its shelter is
-- counted again then, since the trees and buildings around it change.
local function windWatts(source, object, inSlot, context)
    if object then
        source.braked = PowerBank.isBraked(object)
        source.shelter = Wind.shelterAt(source.x, source.y, source.z)
    end
    local spec = Specs.wind.turbines[source.kind]
    local watts = Wind.watts(spec, context.windKph, source.z, source.shelter or 0)
    source.windKph = math.floor(context.windKph + 0.5)
    source.watts = (inSlot and not source.braked) and watts or 0
    if not inSlot then
        source.reason = "noController"
    elseif source.braked then
        source.reason = "braked"
    elseif context.windKph <= spec.cutInKph then
        source.reason = "calm"
    elseif (source.shelter or 0) * Specs.wind.shelterLoss > 1 - LOW_SHARE then
        source.reason = "sheltered"
    else
        source.reason = nil
    end
end

--- Panel and wind charger output over the pass, as solar and wind watts. A source whose square is
--- loaded is checked for still being there and outdoors; one that is gone is dropped. Sources
--- past the bank's input slots stay wired and make nothing.
function Bank:updateSources(hours, context)
    local solarW, windW, slots, used = 0, 0, self:inputSlots(), 0
    -- A dropped source gives its place in the list, and so its slots, to the next one.
    local i = 1
    while i <= #self.sources do
        local source = self.sources[i]
        local square = getSquare(source.x, source.y, source.z)
        local object = PowerBank.sourceOn(square)
        if square and not (object and square:isOutside() and PowerBank.isInReach(self, source.x, source.y, source.z)) then
            table.remove(self.sources, i)
        else
            used = used + PowerBank.slotsOf(source.kind)
            local inSlot = used <= slots
            if PowerBank.isWind(source.kind) then
                windWatts(source, object, inSlot, context)
                windW = windW + source.watts
            else
                panelWatts(source, object, inSlot, hours, context)
                solarW = solarW + source.watts
            end
            i = i + 1
        end
    end
    return solarW, windW
end

-- Backup generator -----------------------------------------------------------------------

local function isFailsafe(object)
    return Sprites.kindOf(Sprites.nameOf(object)) == "failsafe"
end

--- The nearest plugged-in generator, one with a failsafe on its square first.
function Bank:findGenerator()
    local best, bestFailsafe, bestDistance
    for x = self.x - BACKUP_REACH, self.x + BACKUP_REACH do
        for y = self.y - BACKUP_REACH, self.y + BACKUP_REACH do
            local square = getSquare(x, y, self.z)
            local generator = square and square:getGenerator()
            if generator and generator:isConnected() and not PowerBank.isBank(generator) then
                local failsafe = RenewableEnergy.findObjectOn(square, isFailsafe) ~= nil
                local distance = IsoUtils.DistanceToSquared(x, y, self.x, self.y)
                if not best or (failsafe and not bestFailsafe) or (failsafe == bestFailsafe and distance < bestDistance) then
                    best, bestFailsafe, bestDistance = generator, failsafe, distance
                end
            end
        end
    end
    return best, bestFailsafe
end

--- Start or stop a backup generator with a failsafe by the charge, as a generator
--- auto-start relay does. A generator stalled on gas starts again by itself once its load fits
--- (GasLines), so the relay leaves it be, and only calls that off when it would stop it.
local function runFailsafe(generator, on, charge)
    local options = SandboxVars.RenewableEnergy
    local gas = RenewableEnergy.GasKit.stateOf(generator)
    local wantsOff = not on or charge * 100 >= options.FailsafeStopCharge
    if generator:isActivated() then
        if wantsOff then
            generator:setActivated(false)
        end
    elseif gas and gas.stalled then
        if wantsOff then
            gas.stalled = false
            if isServer() then
                generator:transmitModData()
            end
        end
    elseif on and charge * 100 < options.FailsafeStartCharge and generator:getFuel() > 0 and generator:getCondition() > 20 then
        generator:setActivated(true)
    end
end

--- The backup generator's state after the failsafe acted. While the bank is unloaded, the
--- generator's last known state holds.
function Bank:updateGenerator()
    if not self:getSquare() then return end
    local generator, failsafe = self:findGenerator()
    if not generator then
        self.generator = false
        return
    end
    if failsafe then
        runFailsafe(generator, self.on, self.charge)
    end
    self.generator = {
        x = generator:getX(), y = generator:getY(), z = generator:getZ(),
        running = generator:isActivated(), failsafe = failsafe,
    }
end

function Bank:backupCarriesLoad()
    return self.generator and self.generator.running
end

-- Load, chargers and power ----------------------------------------------------------------

--- Measure what the bank powers, and what powers the bank's square besides it. Unloaded, the
--- last measurement stands, until the grid shuts down. A bank that is off and has no charger
--- needs neither, and skips the scan of its whole reach. Returns the running generators that
--- reach the bank.
function Bank:measure()
    local square = self:getSquare()
    if not square then
        self.gridPowered = self.gridPowered and getSandboxOptions():doesPowerGridExist()
        return {}
    end
    self.gridPowered = square:hasGridPower()
    local load = (self.on or self:chargerW() > 0) and Loads.scan(square) or Loads.new()
    self.loadW = load.watts
    self.averageLoadW = load.averageWatts
    self.loadByKind = Loads.byKind(load)
    return load.generators
end

local function fueled(generators)
    for _, generator in ipairs(generators) do
        if generator:getFuel() > 0 then
            return generator
        end
    end
    return nil
end

--- What the chargers charge from: "grid", "generator" (a running generator other than a bank
--- whose reach covers the bank, which burns fuel for them), or false. Returns the watts they
--- put in over the pass's `hours`: no more than `roomWh`, what the batteries can still take
--- after the sun and the load, and from a generator no more than its fuel pays for, which is
--- all the fuel it burns. Unloaded, only the grid carries on: the generator and its fuel are
--- out of reach.
function Bank:chargeFrom(generators, hours, roomWh)
    local generator
    if self:getSquare() then
        generator = not self.gridPowered and fueled(generators)
        self.chargeSource = (self.gridPowered and "grid") or (generator and "generator") or false
    elseif self.chargeSource == "generator" then
        self.chargeSource = false
    end
    if not self.chargeSource or hours <= 0 or roomWh <= 0 then
        return 0
    end
    local watts = math.min(self:chargerW(), roomWh / hours)
    local fuelPerWh = SandboxVars.GeneratorFuelConsumption / WATTS_PER_FUEL_UNIT
    if generator and fuelPerWh > 0 then
        local fuel = generator:getFuel()
        watts = math.min(watts, fuel / fuelPerWh / hours)
        generator:setFuel(math.max(0, fuel - watts * hours * fuelPerWh))
    end
    return watts
end

-- Switched on, indoors, with a working inverter, and off the grid.
local function canCarryLoad(bank)
    return bank.on and bank.indoors and bank:limitW() > 0 and not bank.gridPowered
end

--- Whether the bank would carry its load now: it can, and no backup generator does it instead.
function Bank:carriesLoad()
    return canCarryLoad(self) and not self:backupCarriesLoad()
end

--- Cut the power while the load is beyond the inverters, and bring it back once it fits.
--- Returns whether an overload began.
function Bank:checkOverload()
    local wasOverloaded = self.overloaded
    if not self:carriesLoad() then
        self.overloaded = false
    else
        self.overloaded = self.loadW > self:limitW()
    end
    return self.overloaded and not wasOverloaded
end

--- Whether the bank should power its squares now.
function Bank:shouldPower()
    return canCarryLoad(self) and not self.overloaded and not self.empty
end

--- Run the bank's generator, which is what powers the squares, while the bank should.
function Bank:switchGenerator()
    local generator = self:getIsoObject()
    if not generator then return end
    local run = self:shouldPower()
    if generator:isActivated() ~= run then
        -- setActivated sets the building toxic as a fuel generator's exhaust would
        -- (IsoGenerator.setActivated); a bank has no exhaust, so the building keeps its state.
        local building = generator:getSquare():getBuilding()
        local wasToxic = building and building:isToxic()
        generator:setActivated(run)
        if building and building:isToxic() ~= wasToxic then
            building:setToxic(wasToxic)
        end
    elseif run then
        -- Chunks that loaded in reach since the last pass get their power here, which
        -- IsoGenerator.update does for generators it still processes.
        generator:setSurroundingElectricity()
    end
end

--- The player's switch, or parts wired in or out: look at the load again now.
function Bank:powerUp()
    self.empty = false
    self:recount()
    self:measure()
    self:checkOverload()
    self:switchGenerator()
end

-- Charge ---------------------------------------------------------------------------------

-- The deepest the bank has been drawn down from its highest point today.
function Bank:trackCycle()
    self.cycleHigh = math.max(self.cycleHigh, self.charge)
    self.cycleDepth = math.max(self.cycleDepth, self.cycleHigh - self.charge)
end

--- A new day wears the batteries by the depth of yesterday's deepest discharge.
function Bank:newDay(container, day)
    if self.day and self.day ~= day then
        local depth = self.cycleDepth
        if container then
            self:wearBatteries(container, depth)
        elseif depth > 0 then
            table.insert(self.pendingDepths, depth)
        end
        self.cycleHigh = self.charge
        self.cycleDepth = 0
        self.solarWhToday = 0
        self.windWhToday = 0
        self.loadWhToday = 0
    end
    self.day = day
end

local function today()
    local time = getGameTime()
    return time:getYear() * 1000 + Sun.dayOfYear(time:getMonth(), time:getDay())
end

-- The watts the inverters take from the batteries to carry the load and run themselves.
local function inverterDrawW(bank)
    return bank.averageLoadW / Specs.inverterEfficiency + sumInverters(bank, "idle")
end

--- The watts the batteries give the inverters now.
function Bank:drawW()
    if not self:shouldPower() or self:backupCarriesLoad() then
        return 0
    end
    return inverterDrawW(self)
end

--- One pass: `hours` of sun, load and charging up to now.
---@param context table see BankSystem.passContext
function Bank:update(hours, context)
    local isoObject = self:getIsoObject()
    local container = isoObject and isoObject:getContainer()
    self:recount()

    local solarW, windW = self:updateSources(hours, context)
    local sourcesW = solarW + windW
    self:updateGenerator()
    local generators = self:measure()
    if self:checkOverload() then
        self:addPartWear(container, 0, 1)
    end

    local drawW = self:drawW()
    local capacity = self.nominalWh
    local before = self.charge * capacity
    -- The chargers fill what the sources and the load leave; with no batteries there is nothing to fill.
    local roomWh = capacity > 0 and capacity - before - (sourcesW - drawW) * hours or 0
    local chargerW = self:chargeFrom(generators, hours, roomWh)
    local inW = sourcesW + chargerW
    local stored = math.max(0, math.min(capacity, before + (inW - drawW) * hours))
    self.charge = capacity > 0 and stored / capacity or 0
    -- An empty bank's inverters cut out, and come back once a pass of load is stored, so
    -- a bank that barely charges doesn't stop and start every pass.
    if drawW > 0 and stored <= 0 then
        self.empty = true
    elseif self.empty and stored > 0 and stored >= inverterDrawW(self) * hours then
        self.empty = false
    end
    local powering = self:shouldPower()
    if powering then
        self:addPartWear(container, hours, 0)
    end

    self.solarWhToday = self.solarWhToday + solarW * hours
    self.windWhToday = (self.windWhToday or 0) + windW * hours
    self.loadWhToday = self.loadWhToday + (powering and self.averageLoadW or 0) * hours
    self:trackCycle()
    self:newDay(container, today())
    if container then
        self:writeBatteries(container, false)
        self:recount()
    end
    self:switchGenerator()
    self:showBatteries()

    self.now = { solarW = solarW, windW = windW, chargerW = chargerW, drawW = drawW,
        irradiance = context.irradiance("flat"), elevation = context.elevation, windKph = context.windKph }
    self:sendStatus()
end

-- The bank's tile shows its batteries, each as its type, and its charge.
function Bank:showBatteries()
    local isoObject = self:getIsoObject()
    if not isoObject then return end
    -- recount reads the container from its last item, so this is the order they went in.
    local types = {}
    for i = #self.batteries, 1, -1 do
        table.insert(types, self.batteries[i].type)
    end
    local wanted = Sprites.bankOverlays(self:spec().sprite, types, self.charge)
    local attached = isoObject:getAttachedAnimSprite()
    local count = attached and attached:size() or 0
    local shown, matches = 0, true
    for i = 0, count - 1 do
        local name = attached:get(i):getName()
        if Sprites.isOverlay(name) then
            shown = shown + 1
            matches = matches and wanted[shown] == name
        end
    end
    if matches and shown == #wanted then return end
    for i = count - 1, 0, -1 do
        if Sprites.isOverlay(attached:get(i):getName()) then
            isoObject:RemoveAttachedAnim(i)
        end
    end
    for _, name in ipairs(wanted) do
        isoObject:addAttachedAnimSpriteByName(name)
    end
    isoObject:transmitUpdatedSpriteToClients()
end

-- Status ---------------------------------------------------------------------------------

--- What the bank is doing, for the status window.
function Bank:state()
    if not self.indoors then return "outdoors" end
    if self:limitW() <= 0 then return "noInverter" end
    if not self.on then return "off" end
    if self.gridPowered then return "grid" end
    if self.overloaded then return "overloaded" end
    if self.empty then return "empty" end
    return "on"
end

local function partStatus(parts, extra)
    local list = {}
    for _, part in ipairs(parts) do
        local entry = { id = part.id, type = part.type, condition = part.condition, working = working(part) }
        if extra then
            extra(entry, part)
        end
        table.insert(list, entry)
    end
    return list
end

function Bank:sourceStatus()
    local sources = {}
    for _, source in ipairs(self.sources) do
        local entry = {
            x = source.x, y = source.y, z = source.z, kind = source.kind, watts = source.watts or 0,
            reason = source.reason,
        }
        if PowerBank.isWind(source.kind) then
            entry.braked, entry.windKph = source.braked == true, source.windKph or 0
            entry.shelterPct = math.floor(100 * (source.shelter or 0) + 0.5)
        else
            local modules = {}
            for _, module in ipairs(source.modules) do
                table.insert(modules, { type = module.type, condition = module.condition })
            end
            entry.material, entry.facing, entry.fullSunPct = source.material, source.facing, source.fullSunPct or 0
            entry.snow, entry.modules = source.snow or 0, modules
        end
        table.insert(sources, entry)
    end
    return sources
end

-- Net watts into the batteries, and the hours until they are full (charging) or empty
-- (draining); hours is nil when nothing changes.
local function chargingStatus(netW, stored, capacity)
    local hours
    if netW > 0 and capacity > stored then
        hours = (capacity - stored) / netW
    elseif netW < 0 and stored > 0 then
        hours = stored / -netW
    end
    return { watts = netW, hours = hours }
end

function Bank:buildStatus()
    local now = self.now or {}
    local capacity = self.nominalWh
    local stored = self.charge * capacity
    local inW = (now.solarW or 0) + (now.windW or 0) + (now.chargerW or 0)
    local drawW = now.drawW or 0
    local batteries = partStatus(self.batteries, function(entry, part)
        entry.fullType, entry.nominalWh, entry.charge = part.type, part.nominalWh, self.charge
    end)
    local chargeSource = self.chargeSource
    local chargers = partStatus(self.chargers, function(entry)
        entry.charging = entry.working and (now.chargerW or 0) > 0 and chargeSource or nil
    end)
    local generator = self:getIsoObject()
    return {
        kind = self:spec().sprite,
        bankType = self.bankType,
        name = self.name,
        on = self.on,
        state = self:state(),
        powered = generator ~= nil and generator:isActivated() or (generator == nil and self:shouldPower()),
        hour = getGameTime():getWorldAgeHours(),
        sunElevation = now.elevation or 0,
        irradiance = now.irradiance or 0,
        solarW = now.solarW or 0, windW = now.windW or 0, windKph = now.windKph or 0,
        chargerW = now.chargerW or 0, chargeSource = chargeSource or nil, inW = inW,
        solarWhToday = self.solarWhToday, windWhToday = self.windWhToday or 0, loadWhToday = self.loadWhToday,
        loadW = self.loadW, drawW = drawW, limitW = self:limitW(), overloaded = self.overloaded,
        loadByKind = self.loadByKind,
        storedWh = stored, capacityWh = capacity, charge = self.charge,
        charging = chargingStatus(inW - drawW, stored, capacity),
        cycleDepth = self.cycleDepth,
        inputSlots = { used = self:slotsUsed(), total = self:inputSlots() },
        inverters = partStatus(self.inverters),
        controllers = partStatus(self.controllers),
        chargers = chargers,
        batteries = batteries,
        sources = self:sourceStatus(),
        generator = self.generator and {
            x = self.generator.x, y = self.generator.y, z = self.generator.z, running = self.generator.running,
            failsafe = self.generator.failsafe,
        } or nil,
    }
end

--- What every client keeps of the bank wherever it stands: what the menus of the bank and its
--- panels show and check. The Global Object System sends it to every client each time it
--- changes, so it holds nothing that moves with every pass.
function Bank:buildSummary()
    local sources = {}
    for _, source in ipairs(self.sources) do
        table.insert(sources, { x = source.x, y = source.y, z = source.z, kind = source.kind,
            snowy = (source.snow or 0) > 0 or nil, braked = source.braked or nil })
    end
    return { bankType = self.bankType, name = self.name, on = self.on, limitW = self:limitW(), sources = sources }
end

-- Whether two values are the same, tables by what they hold.
local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not same(value, b[key]) then
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

-- A client loads at most this many squares each way around its player (the widest chunk grid a
-- server lets a client connect with, GameServer.receivePlayerConnect), so a bank farther away
-- can't be in its view.
local VIEW_REACH = 80

--- Whether the bank can be in `player`'s view: they are alive, still connected, and near enough
--- for their client to have the bank loaded.
function Bank:inViewOf(player)
    if player:isDead() then
        return false
    end
    -- The server forgets a player who leaves, and one who comes back is a new object.
    if isServer() and getPlayerByOnlineID(player:getOnlineID()) ~= player then
        return false
    end
    return math.abs(player:getX() - self.x) <= VIEW_REACH and math.abs(player:getY() - self.y) <= VIEW_REACH
end

-- The players watching the bank's status, once those who can no longer see the bank are dropped:
-- the server hears of no disconnect, and a client that died or walked away never closes its window.
local function watchersOf(bank)
    local players, gone = {}, {}
    for player in pairs(bank.watchers or {}) do
        table.insert(bank:inViewOf(player) and players or gone, player)
    end
    for _, player in ipairs(gone) do
        bank.watchers[player] = nil
    end
    return players
end

local function sendTo(bank, player)
    sendServerCommand(player, PowerBank.STATUS_MODULE, "status", { x = bank.x, y = bank.y, z = bank.z, status = bank.status })
end

--- Tell the clients what changed: every client the summary, when it changed, and the players
--- watching the bank its whole status. Single player has no network to send on; its status
--- window reads the status the bank keeps while someone watches.
function Bank:sendStatus()
    local summary = self:buildSummary()
    if not same(summary, self.summary) then
        self.summary = summary
        self:updateOnClient()
    end
    local players = watchersOf(self)
    self.status = #players > 0 and self:buildStatus() or nil
    for _, player in ipairs(players) do
        sendTo(self, player)
    end
end

--- `player` opened the bank's status window, and gets the status after every change until they
--- close it. Returns whether they weren't watching already.
function Bank:watch(player)
    self.watchers = self.watchers or {}
    local new = not self.watchers[player]
    self.watchers[player] = true
    return new
end

--- Send the status as the other watchers last had it to `player` alone.
function Bank:sendStatusTo(player)
    self.status = self.status or self:buildStatus()
    sendTo(self, player)
end

--- `player` closed the bank's status window. With nobody watching, the bank keeps no status.
function Bank:unwatch(player)
    local watchers = self.watchers
    if not watchers then return end
    watchers[player] = nil
    for _ in pairs(watchers) do
        return
    end
    self.watchers = nil
    self.status = nil
end

return Bank
