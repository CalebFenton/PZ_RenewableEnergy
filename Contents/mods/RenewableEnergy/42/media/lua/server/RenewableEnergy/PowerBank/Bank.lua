-- One battery bank on the authority (single player or the server): its batteries, inverters,
-- chargers, controllers, sources (panels, wind chargers and treadmills, each family run by its
-- <Family>Source.lua) and backup generator, and the energy that moves between them each pass.
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
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/PanelSource"
require "RenewableEnergy/PowerBank/WindSource"
require "RenewableEnergy/PowerBank/TreadmillSource"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/GasLine/GasKit"
local Loads = require "RenewableEnergy/PowerBank/Loads"

RenewableEnergy = RenewableEnergy or {}
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local Battery, Wear, PowerBank, Sources = RenewableEnergy.Battery, RenewableEnergy.Wear, RenewableEnergy.PowerBank,
    RenewableEnergy.Sources

local Bank = SGlobalObject:derive("RenewableEnergy_Bank")
RenewableEnergy.Bank = Bank

-- The fields the Global Object System saves with the world; a field renamed here is lost from
-- existing saves.
Bank.SAVED_FIELDS = {
    "bankType", "name", "on", "overloaded", "indoors", "gridPowered", "charge", "nominalWh", "batteries",
    "inverters", "chargers", "controllers", "sources", "loadW", "averageLoadW", "loadByKind", "chargeSource",
    "generator", "lastHour", "day", "cycleHigh", "cycleDepth", "pendingDepths", "pendingPartWear",
    "solarWhToday", "loadWhToday", "empty", "windWhToday", "runWhToday",
}

-- A backup generator a failsafe can start is one plugged in within this many tiles on the
-- bank's floor.
local BACKUP_REACH = 3
-- Vanilla bills generators in fuel per hour per unit of power; a unit is this many watts.
local WATTS_PER_FUEL_UNIT = Specs.loads.other.wattsPerConsumption

-- How the bank runs each family of source (RenewableEnergy.Sources): init(source, isoObject,
-- facing, material) fills a new record, update(source, object, inSlot, hours, context) sets its
-- watts and reason for a pass, and status(entry, source), if any, adds to its status entry.
local FAMILY = {
    panel = RenewableEnergy.PanelSource,
    wind = RenewableEnergy.WindSource,
    treadmill = RenewableEnergy.TreadmillSource,
}
-- Each family's watts now in the status, and its watt-hours today, saved; solarWhToday is Release
-- 1's and keeps its name.
local TOTALS = {
    panel = { now = "solarW", today = "solarWhToday" },
    wind = { now = "windW", today = "windWhToday" },
    treadmill = { now = "runW", today = "runWhToday" },
}

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
    for _, total in pairs(TOTALS) do
        self[total.today] = 0
    end
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
        used = used + Sources.slotsOf(source.kind)
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

-- Sources ---------------------------------------------------------------------------------

function Bank:findSource(x, y, z)
    for i, source in ipairs(self.sources) do
        if source.x == x and source.y == y and source.z == z then
            return source, i
        end
    end
    return nil
end

function Bank:addSource(isoObject)
    local kind, facing, material = Sources.kindOf(isoObject)
    local source = { x = isoObject:getX(), y = isoObject:getY(), z = isoObject:getZ(), kind = kind, watts = 0 }
    FAMILY[Sources.familyOf(kind)].init(source, isoObject, facing, material)
    table.insert(self.sources, source)
end

function Bank:removeSource(x, y, z)
    local _, index = self:findSource(x, y, z)
    if index then
        table.remove(self.sources, index)
        return true
    end
    return false
end

--- Every source's output over the pass, as watts by family (TOTALS). A source whose square is
--- loaded is checked for still being there, where its kind works and in reach; one that is gone
--- is dropped. Each source takes its slots if they fit in what the sources before it in the
--- list left free; one that doesn't fit stays wired and makes nothing.
function Bank:updateSources(hours, context)
    local watts, slots, used = {}, self:inputSlots(), 0
    for family in pairs(TOTALS) do
        watts[family] = 0
    end
    -- A dropped source gives its place in the list, and so its slots, to the next one.
    local i = 1
    while i <= #self.sources do
        local source = self.sources[i]
        local square = getSquare(source.x, source.y, source.z)
        local object = Sources.on(square)
        if square and not (object and Sources.squareOk(square, source.kind)
            and PowerBank.isInReach(self, source.x, source.y, source.z)) then
            table.remove(self.sources, i)
        else
            local size = Sources.slotsOf(source.kind)
            local inSlot = used + size <= slots
            if inSlot then
                used = used + size
            end
            local family = Sources.familyOf(source.kind)
            FAMILY[family].update(source, object, inSlot, hours, context)
            watts[family] = watts[family] + source.watts
            i = i + 1
        end
    end
    return watts
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
        for _, total in pairs(TOTALS) do
            self[total.today] = 0
        end
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

    local watts = self:updateSources(hours, context)
    local sourcesW = 0
    for _, w in pairs(watts) do
        sourcesW = sourcesW + w
    end
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

    for family, total in pairs(TOTALS) do
        self[total.today] = (self[total.today] or 0) + watts[family] * hours
    end
    self.loadWhToday = self.loadWhToday + (powering and self.averageLoadW or 0) * hours
    self:trackCycle()
    self:newDay(container, today())
    if container then
        self:writeBatteries(container, false)
        self:recount()
    end
    self:switchGenerator()
    self:showBatteries()

    self.now = { chargerW = chargerW, drawW = drawW, irradiance = context.irradiance("flat"), elevation = context.elevation,
        windKph = context.windKph }
    for family, total in pairs(TOTALS) do
        self.now[total.now] = watts[family]
    end
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
    RenewableEnergy.showOverlays(isoObject, Sprites.isOverlay, Sprites.bankOverlays(self:spec().sprite, types, self.charge))
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
        local status = FAMILY[Sources.familyOf(source.kind)].status
        if status then
            status(entry, source)
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
    local inW = now.chargerW or 0
    for _, total in pairs(TOTALS) do
        inW = inW + (now[total.now] or 0)
    end
    local drawW = now.drawW or 0
    local batteries = partStatus(self.batteries, function(entry, part)
        entry.fullType, entry.nominalWh, entry.charge = part.type, part.nominalWh, self.charge
    end)
    local chargeSource = self.chargeSource
    local chargers = partStatus(self.chargers, function(entry)
        entry.charging = entry.working and (now.chargerW or 0) > 0 and chargeSource or nil
    end)
    local generator = self:getIsoObject()
    local status = {
        kind = self:spec().sprite,
        bankType = self.bankType,
        name = self.name,
        on = self.on,
        state = self:state(),
        powered = generator ~= nil and generator:isActivated() or (generator == nil and self:shouldPower()),
        hour = getGameTime():getWorldAgeHours(),
        sunElevation = now.elevation or 0,
        irradiance = now.irradiance or 0,
        windKph = now.windKph or 0,
        chargerW = now.chargerW or 0, chargeSource = chargeSource or nil, inW = inW,
        loadWhToday = self.loadWhToday,
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
    for _, total in pairs(TOTALS) do
        status[total.now] = now[total.now] or 0
        status[total.today] = self[total.today] or 0
    end
    return status
end

--- What every client keeps of the bank wherever it stands: what the menus of the bank and its
--- sources show and check. The Global Object System sends it to every client each time it
--- changes, so it holds nothing that moves with every pass.
function Bank:buildSummary()
    local sources = {}
    for _, source in ipairs(self.sources) do
        table.insert(sources, { x = source.x, y = source.y, z = source.z, snowy = (source.snow or 0) > 0 or nil })
    end
    return { bankType = self.bankType, name = self.name, on = self.on, limitW = self:limitW(), sources = sources }
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
    if not RenewableEnergy.sameValue(summary, self.summary) then
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
