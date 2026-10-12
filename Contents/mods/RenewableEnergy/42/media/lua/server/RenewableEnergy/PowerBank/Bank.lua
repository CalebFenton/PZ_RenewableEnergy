-- One battery bank on the authority (single player or the server): its batteries, inverters,
-- chargers, controllers, panels and backup generator, and the energy that moves between them
-- each pass.
--
-- The table is the bank's global object (SGlobalObject), so every field named in
-- SAVED_FIELDS is saved with the world and kept while the chunk is unloaded. While loaded,
-- the container is the truth about what the bank holds and each battery's own charge is
-- the truth about the charge; while unloaded, the snapshot in `batteries` and `charge`
-- carries on and is written back into the batteries when the chunk loads, and so is the wear
-- the parts took meanwhile.

if isClient() then return end

require "Map/SGlobalObject"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/PowerBank"
local Loads = require "RenewableEnergy/PowerBank/Loads"

local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local Battery, Wear, PowerBank = RenewableEnergy.Battery, RenewableEnergy.Wear, RenewableEnergy.PowerBank

local Bank = SGlobalObject:derive("RenewableEnergy_Bank")

Bank.SAVED_FIELDS = {
    "bankType", "name", "on", "overloaded", "indoors", "gridPowered", "charge", "nominalWh", "batteries",
    "inverters", "chargers", "controllers", "sources", "loadW", "averageLoadW", "loadByKind", "chargeSource",
    "generator", "lastHour", "day", "cycleHigh", "cycleDepth", "pendingDepths", "pendingPartWear",
    "solarWhToday", "loadWhToday", "empty", "status",
}

-- A 1993 modified-sine inverter turns about this much of the battery's power into AC.
local INVERTER_EFFICIENCY = 0.9
-- A backup generator a failsafe can start is one plugged in within this many tiles on the
-- bank's floor.
local BACKUP_REACH = 3
-- Snow on panels, per hour: falling snow covers a panel at full intensity in about two
-- hours; it melts above freezing and slides off in sun; a rack sheds it in about two hours
-- of sun or mild air (design §5.6).
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
-- Vanilla bills generators in fuel per hour per unit of power; a unit is this many watts
-- (Specs.loads.other).
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
    self.loadWhToday = 0
    self.empty = false
    self.lastHour = getGameTime():getWorldAgeHours()
end

--- An object the bank system has not seen: a bank just placed, or one from a save whose
--- global objects were lost.
function Bank:stateFromIsoObject(isoObject)
    self:initNew()
    self.bankType = PowerBank.bankOfSprite(isoObject:getSprite():getName()).fullType
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

function Bank:spec()
    return Specs.banks[self.bankType]
end

-- Parts ----------------------------------------------------------------------------------

local function eachItem(container, fn)
    local items = container:getItems()
    for i = items:size() - 1, 0, -1 do
        fn(items:get(i))
    end
end

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
    eachItem(container, function(item)
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
    end)
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
    eachItem(container, function(item)
        local spec = Battery.spec(item)
        if spec and item:getCondition() > 0 then
            local changed = math.abs(Battery.getCharge(item) - self.charge) >= 0.001
            Battery.setCharge(item, self.charge)
            if applyPending then
                for _, depth in ipairs(self.pendingDepths) do
                    changed = Battery.wear(item, Battery.cycleWear(spec, depth) * self:wearScale()) or changed
                end
            end
            if changed then
                sendItemStats(item)
            end
        end
    end)
    if applyPending then
        self.pendingDepths = {}
    end
end

function Bank:wearScale()
    return SandboxVars.RenewableEnergy.BatteryWear / 100
end

-- Wear every battery by a fraction of its life.
function Bank:wearBatteries(container, fractionFor)
    eachItem(container, function(item)
        local spec = Battery.spec(item)
        if spec and Battery.wear(item, fractionFor(spec) * self:wearScale()) then
            sendItemStats(item)
        end
    end)
end

local function working(part)
    return part.condition > 0
end

--- The watts the bank's working inverters carry together.
function Bank:limitW()
    local watts = 0
    for _, inverter in ipairs(self.inverters) do
        if working(inverter) then
            watts = watts + Specs.inverters[inverter.type].watts
        end
    end
    return watts
end

function Bank:idleW()
    local watts = 0
    for _, inverter in ipairs(self.inverters) do
        if working(inverter) then
            watts = watts + Specs.inverters[inverter.type].idle
        end
    end
    return watts
end

--- The watts the bank's working chargers, and the chargers built into its inverters, put in
--- while grid or generator power reaches it.
function Bank:chargerW()
    local watts = 0
    for _, charger in ipairs(self.chargers) do
        if working(charger) then
            watts = watts + Specs.chargerWatts
        end
    end
    for _, inverter in ipairs(self.inverters) do
        if working(inverter) then
            watts = watts + Specs.inverters[inverter.type].chargerWatts
        end
    end
    return watts
end

--- How many panels the bank takes: a few on their own, and more for each working controller.
function Bank:panelSlots()
    local slots = Specs.freePanels
    for _, controller in ipairs(self.controllers) do
        if working(controller) then
            slots = slots + Specs.panelsPerController
        end
    end
    return slots
end

-- Inverters and controllers wear while they work, and an overload strains the inverters.
function Bank:wearParts(container, hours, overloads)
    local wear = Specs.partWear
    eachItem(container, function(item)
        local kind = PowerBank.partKind(item:getFullType())
        local points = 0
        if kind == "inverter" then
            points = wear.inverterPerHour * hours + wear.overload * overloads
        elseif kind == "controller" then
            points = wear.controllerPerHour * hours
        end
        if Wear.take(item, points) then
            sendItemStats(item)
        end
    end)
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

--- The modules a placed mount holds, from its modData; a mount without that record holds
--- whole factory modules.
function Bank.modulesOf(isoObject, kind)
    local modules = {}
    local recorded = isoObject:getModData()[PowerBank.MODULES]
    if type(recorded) == "table" then
        for _, module in ipairs(recorded) do
            table.insert(modules, { type = module.type, condition = module.condition })
        end
    end
    if #modules == 0 then
        for _ = 1, Specs.mounts[kind].modules do
            table.insert(modules, { type = "RenewableEnergy.SolarModule", condition = 100 })
        end
    end
    return modules
end

local function writeModules(isoObject, modules)
    local record = {}
    for i, module in ipairs(modules) do
        record[i] = { type = module.type, condition = module.condition }
    end
    isoObject:getModData()[PowerBank.MODULES] = record
    isoObject:transmitModData()
end

--- The watts a panel's modules are rated for as they are now, and at their best.
local function moduleWatts(source)
    local now, best = 0, 0
    for _, module in ipairs(source.modules) do
        local spec = Specs.modules[module.type]
        if spec then
            now = now + spec.watts * module.condition / 100
            best = best + spec.watts * conditionMax(module.type) / 100
        end
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
    table.insert(self.sources, {
        x = isoObject:getX(), y = isoObject:getY(), z = isoObject:getZ(),
        kind = kind, facing = facing, material = material, snow = 0, watts = 0,
        modules = Bank.modulesOf(isoObject, kind),
    })
end

function Bank:removeSource(x, y, z)
    local _, index = self:findSource(x, y, z)
    if index then
        table.remove(self.sources, index)
        return true
    end
    return false
end

local function sourceObjectAt(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if PowerBank.sourceKind(object) then
            return object
        end
    end
    return nil
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

--- A thunderstorm may crack one of a panel's modules. Returns whether it did.
function Bank.stormCrack(source, stormHours)
    local options = SandboxVars.RenewableEnergy
    if not options.StormDamage or stormHours <= 0 then
        return false
    end
    local perHour = Specs.storm.chancePerHour * PowerBank.stormFactor(source.kind, source.material) * options.StormDamageRate / 100
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
-- is the truth.
local function syncModules(source, object)
    if source.modulesChanged then
        writeModules(object, source.modules)
        source.modulesChanged = nil
    else
        source.modules = Bank.modulesOf(object, source.kind)
    end
end

-- Why a panel makes less than it would at its best in clear full sun: the biggest loss, if it
-- is big enough to matter.
local function lowReason(source, inSlot, light, clearLight, condition, context)
    if not inSlot then
        return "noController"
    elseif context.elevation <= 0 or clearLight <= 0 then
        return "night"
    end
    local shares = {
        snow = 1 - source.snow,
        cloud = light / clearLight,
        angle = clearLight / Sun.FULL_SUN,
        cracked = condition,
    }
    local reason, lowest = nil, LOW_SHARE
    for name, share in pairs(shares) do
        if share < lowest then
            reason, lowest = name, share
        end
    end
    return reason
end

--- Panel output over the pass. A panel whose square is loaded is checked for still being
--- there and outdoors; one that is gone is dropped. Panels past the bank's slots stay wired
--- and make nothing.
function Bank:updateSources(hours, context)
    for i = #self.sources, 1, -1 do
        local source = self.sources[i]
        local square = getSquare(source.x, source.y, source.z)
        local object = square and sourceObjectAt(square)
        if square and not (object and square:isOutside() and PowerBank.isInReach(self, source.x, source.y, source.z)) then
            table.remove(self.sources, i)
        end
    end
    local solarW, slots = 0, self:panelSlots()
    for i, source in ipairs(self.sources) do
        local square = getSquare(source.x, source.y, source.z)
        local object = square and sourceObjectAt(square)
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
        local now, best = moduleWatts(source)
        local inSlot = i <= slots
        source.watts = inSlot and Sun.wattsFrom(now, light, source.snow) or 0
        source.fullSunPct = math.floor(100 * light * (1 - source.snow) / Sun.FULL_SUN + 0.5)
        source.reason = lowReason(source, inSlot, light, clearLight, best > 0 and now / best or 0, context)
        solarW = solarW + source.watts
    end
    return solarW
end

-- Backup generator -----------------------------------------------------------------------

local function hasFailsafe(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        if sprite and Sprites.kindOf(sprite:getName()) == "failsafe" then
            return true
        end
    end
    return false
end

--- The nearest plugged-in generator, one with a failsafe on its square first.
function Bank:findGenerator()
    local best, bestFailsafe, bestDistance
    for x = self.x - BACKUP_REACH, self.x + BACKUP_REACH do
        for y = self.y - BACKUP_REACH, self.y + BACKUP_REACH do
            local square = getSquare(x, y, self.z)
            local generator = square and square:getGenerator()
            if generator and generator:isConnected() and not PowerBank.isBank(generator) then
                local failsafe = hasFailsafe(square)
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
--- auto-start relay does.
local function runFailsafe(generator, on, charge)
    local options = SandboxVars.RenewableEnergy
    if generator:isActivated() then
        if not on or charge * 100 >= options.FailsafeStopCharge then
            generator:setActivated(false)
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
--- put in. Unloaded, only the grid carries on: the generator and its fuel are out of reach.
function Bank:chargeFrom(generators, hours)
    local watts = self:chargerW()
    if self:getSquare() then
        local generator = not self.gridPowered and fueled(generators)
        self.chargeSource = (self.gridPowered and "grid") or (generator and "generator") or false
        if watts > 0 and generator and self.charge < 1 then
            local fuel = watts / WATTS_PER_FUEL_UNIT * SandboxVars.GeneratorFuelConsumption * hours
            generator:setFuel(math.max(0, generator:getFuel() - fuel))
        end
    elseif self.chargeSource == "generator" then
        self.chargeSource = false
    end
    if not self.chargeSource or self.charge >= 1 then
        return 0
    end
    return watts
end

--- Whether the bank would carry its load now: switched on, indoors, with a working inverter,
--- and neither the grid nor a backup generator doing it instead.
function Bank:carriesLoad()
    return self.on and self.indoors and self:limitW() > 0 and not self.gridPowered and not self:backupCarriesLoad()
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
    return self.on and self.indoors and self:limitW() > 0 and not self.gridPowered
        and not self.overloaded and not self.empty
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
            self:wearBatteries(container, function(spec) return Battery.cycleWear(spec, depth) end)
        elseif depth > 0 then
            table.insert(self.pendingDepths, depth)
        end
        self.cycleHigh = self.charge
        self.cycleDepth = 0
        self.solarWhToday = 0
        self.loadWhToday = 0
    end
    self.day = day
end

local function today()
    local time = getGameTime()
    return time:getYear() * 1000 + Sun.dayOfYear(time:getMonth(), time:getDay())
end

--- The watts the batteries give the inverters now.
function Bank:drawW()
    if not self:shouldPower() or self:backupCarriesLoad() then
        return 0
    end
    return self.averageLoadW / INVERTER_EFFICIENCY + self:idleW()
end

--- One pass: `hours` of sun, load and charging up to now.
---@param context table see BankSystem.passContext
function Bank:update(hours, context)
    local isoObject = self:getIsoObject()
    local container = isoObject and isoObject:getContainer()
    self:recount()

    local solarW = self:updateSources(hours, context)
    self:updateGenerator()
    local generators = self:measure()
    local chargerW = self:chargeFrom(generators, hours)
    local inW = solarW + chargerW
    if self:checkOverload() then
        self:addPartWear(container, 0, 1)
    end

    local drawW = self:drawW()
    local capacity = self.nominalWh
    local stored = math.max(0, math.min(capacity, self.charge * capacity + (inW - drawW) * hours))
    self.charge = capacity > 0 and stored / capacity or 0
    -- An empty bank's inverters cut out, and come back once a pass of load is stored, so
    -- a bank that barely charges doesn't stop and start every pass.
    if drawW > 0 and stored <= 0 then
        self.empty = true
    elseif self.empty and stored > 0 and stored >= (self.averageLoadW / INVERTER_EFFICIENCY + self:idleW()) * hours then
        self.empty = false
    end
    if self:shouldPower() then
        self:addPartWear(container, hours, 0)
    end

    self.solarWhToday = self.solarWhToday + solarW * hours
    self.loadWhToday = self.loadWhToday + (self:shouldPower() and self.averageLoadW or 0) * hours
    self:trackCycle()
    self:newDay(container, today())
    if container then
        self:writeBatteries(container, false)
        self:recount()
    end
    self:switchGenerator()
    self:showBatteries()

    self.now = { solarW = solarW, chargerW = chargerW, drawW = drawW,
        irradiance = context.irradiance("flat"), elevation = context.elevation }
    self:sendStatus()
end

-- The bank's tile shows its batteries and charge.
function Bank:showBatteries()
    local isoObject = self:getIsoObject()
    if not isoObject then return end
    local wanted = Sprites.bankOverlays(self:spec().sprite, #self.batteries, self.charge)
    local attached = isoObject:getAttachedAnimSprite()
    local shown = {}
    for i = 0, (attached and attached:size() or 0) - 1 do
        local name = attached:get(i):getName()
        if Sprites.isOverlay(name) then
            table.insert(shown, name)
        end
    end
    if table.concat(shown, ",") == table.concat(wanted, ",") then return end
    for i = (attached and attached:size() or 0) - 1, 0, -1 do
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

--- What the bank is doing, for the status window: "outdoors", "noInverter", "off", "grid",
--- "overloaded", "empty" or "on".
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
        local modules = {}
        for _, module in ipairs(source.modules) do
            table.insert(modules, { type = module.type, condition = module.condition })
        end
        table.insert(sources, {
            x = source.x, y = source.y, z = source.z, kind = source.kind, material = source.material,
            facing = source.facing, watts = source.watts or 0, fullSunPct = source.fullSunPct or 0,
            reason = source.reason, snow = source.snow or 0, modules = modules,
        })
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
    local inW = (now.solarW or 0) + (now.chargerW or 0)
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
        solarW = now.solarW or 0, chargerW = now.chargerW or 0, chargeSource = chargeSource or nil, inW = inW,
        solarWhToday = self.solarWhToday, loadWhToday = self.loadWhToday,
        loadW = self.loadW, drawW = drawW, limitW = self:limitW(), overloaded = self.overloaded,
        loadByKind = self.loadByKind,
        storedWh = stored, capacityWh = capacity, charge = self.charge,
        charging = chargingStatus(inW - drawW, stored, capacity),
        cycleDepth = self.cycleDepth,
        panelSlots = { used = #self.sources, total = self:panelSlots() },
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

--- Rebuild the status and send it to every client.
function Bank:sendStatus()
    self.status = self:buildStatus()
    self:updateOnClient()
end

return Bank
