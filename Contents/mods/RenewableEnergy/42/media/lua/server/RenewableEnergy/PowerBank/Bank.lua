-- One battery bank on the authority (single player or the server): its batteries, inverter,
-- controllers, panels, vehicle and backup generator, and the energy that moves between them
-- each pass (design §2-§6).
--
-- The table is the bank's global object (SGlobalObject), so every field named in
-- SAVED_FIELDS is saved with the world and kept while the chunk is unloaded. While loaded,
-- the container is the truth about what the bank holds and each battery's own charge is
-- the truth about the charge; while unloaded, the snapshot in `batteries` and `charge`
-- carries on and is written back into the batteries when the chunk loads.

if isClient() then return end

require "Map/SGlobalObject"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/PowerBank"
local Loads = require "RenewableEnergy/PowerBank/Loads"

local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local Battery, PowerBank = RenewableEnergy.Battery, RenewableEnergy.PowerBank

local Bank = SGlobalObject:derive("RenewableEnergy_Bank")

Bank.SAVED_FIELDS = {
    "bankType", "on", "trip", "tripW", "charge", "nominalWh", "batteries", "inverter", "controllers",
    "sources", "loadW", "vehicle", "generator", "tempC", "lastHour", "day", "cycleHigh", "cycleDepth",
    "pendingDepths", "solarWhToday", "loadWhToday", "empty", "status",
}

-- A 1993 modified-sine inverter turns about this much of the battery's power into AC.
local INVERTER_EFFICIENCY = 0.9
-- Overcharging boils a flooded battery dry: life lost per day full and still charging
-- without a controller (design §5.4: -0.5% a day).
local OVERCHARGE_WEAR_PER_DAY = 0.005
-- A battery below this charge freezes below this air temperature, cracking with this
-- chance per hour (design §5.1).
local FREEZE_BELOW_CHARGE = 0.25
local FREEZE_BELOW_C = -10
local FREEZE_CHANCE_PER_HOUR = 0.05
-- A backup generator is one plugged in within this many tiles on the bank's floor.
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
-- Vanilla bills generators in fuel per hour per unit of power; a unit is this many watts
-- (Specs.loads.other).
local WATTS_PER_FUEL_UNIT = Specs.loads.other.wattsPerConsumption

function Bank:new(luaSystem, globalObject)
    return SGlobalObject.new(self, luaSystem, globalObject)
end

function Bank:initNew()
    self.on = false
    self.trip = false
    self.tripW = 0
    self.charge = 0
    self.nominalWh = 0
    self.batteries = {}
    self.inverter = false
    self.controllers = 0
    self.sources = {}
    self.loadW = 0
    self.vehicle = false
    self.generator = false
    self.cycleHigh = 0
    self.cycleDepth = 0
    self.pendingDepths = {}
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

--- The bank's chunk loaded: hand the charge it kept while unloaded back to its batteries.
function Bank:stateToIsoObject(isoObject)
    local container = isoObject:getContainer()
    if container then
        self:writeBatteries(container, true)
    end
    self:loaded(isoObject)
end

function Bank:loaded(isoObject)
    -- IsoGenerator.update would burn fuel, wear the condition and run an engine sound.
    isoObject:getCell():addToProcessIsoObjectRemove(isoObject)
    self:updateTemperature()
    self:recount()
    self:switchGenerator()
    self:sendStatus()
end

function Bank:spec()
    return Specs.banks[self.bankType]
end

function Bank:position()
    return { x = self.x, y = self.y, z = self.z }
end

-- Batteries, inverter and controllers --------------------------------------------------------

local function eachItem(container, fn)
    local items = container:getItems()
    for i = items:size() - 1, 0, -1 do
        fn(items:get(i))
    end
end

--- Read what the container holds into the bank's snapshot. Does nothing without one: a
--- bank whose container hasn't arrived isn't a bank holding nothing.
function Bank:recount()
    local isoObject = self:getIsoObject()
    local container = isoObject and isoObject:getContainer()
    if not container then return end
    local batteries, nominalWh, storedWh = {}, 0, 0
    local inverter, controllers = false, 0
    eachItem(container, function(item)
        local fullType = item:getFullType()
        if Battery.isBattery(item) then
            local wh = Battery.nominalWh(item)
            nominalWh = nominalWh + wh
            storedWh = storedWh + wh * Battery.getCharge(item)
            table.insert(batteries, { fullType = fullType, nominalWh = wh, condition = item:getCondition() })
        elseif Specs.inverters[fullType] then
            inverter = fullType
        elseif Specs.controllers[fullType] then
            controllers = controllers + 1
        end
    end)
    self.batteries = batteries
    self.nominalWh = nominalWh
    self.charge = nominalWh > 0 and storedWh / nominalWh or 0
    self.inverter = inverter
    self.controllers = controllers
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

function Bank:inverterSpec()
    return self.inverter and Specs.inverters[self.inverter]
end

-- Panels ---------------------------------------------------------------------------------

function Bank:findSource(x, y, z)
    for i, source in ipairs(self.sources) do
        if source.x == x and source.y == y and source.z == z then
            return source, i
        end
    end
    return nil
end

function Bank:addSource(isoObject)
    local kind, facing = PowerBank.sourceKind(isoObject)
    table.insert(self.sources, {
        x = isoObject:getX(), y = isoObject:getY(), z = isoObject:getZ(),
        kind = kind, facing = facing, snow = 0, watts = 0,
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
    local sun = context.irradiance(source.kind, source.facing) / 1000
    snow = snow - SNOW_SUN_MELT_PER_HOUR * sun * hours
    if source.kind == "rack" and (context.airC > RACK_SHEDS_ABOVE_C or sun > 0) then
        snow = snow - RACK_SHED_PER_HOUR * hours
    end
    source.snow = math.max(0, math.min(1, snow))
end

local function showSnow(object, source)
    local overlay = source.kind == "flat" and Sprites.snow.flat or Sprites.snow.rack[source.facing]
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

--- Panel output over the pass. A panel whose square is loaded is checked for still being
--- there and outdoors; one that is gone is dropped.
function Bank:updateSources(hours, context)
    local solarW, panelWatts = 0, 0
    for i = #self.sources, 1, -1 do
        local source = self.sources[i]
        local square = getSquare(source.x, source.y, source.z)
        local object = square and sourceObjectAt(square)
        if square and not (object and square:isOutside() and PowerBank.isInReach(self, source.x, source.y, source.z)) then
            table.remove(self.sources, i)
        else
            updateSnow(source, hours, context)
            if object then
                showSnow(object, source)
            end
            local rated = Specs.moduleWatts * Specs.mounts[source.kind].modules
            source.watts = Sun.wattsFrom(rated, context.irradiance(source.kind, source.facing), context.airC, source.snow)
            solarW = solarW + source.watts
            panelWatts = panelWatts + rated
        end
    end
    return solarW, panelWatts
end

--- Watts of panels the bank can take without a controller overcharging it, and how many
--- it has beyond that.
function Bank:controllerHeadroom(panelWatts)
    local allowance = self.controllers * Specs.controllers["RenewableEnergy.ChargeController"].watts
        + self:spec().uncontrolledModules * Specs.moduleWatts
    return allowance, math.max(0, panelWatts - allowance)
end

-- Vehicle --------------------------------------------------------------------------------

--- A vehicle around the bank that `matches`. Vehicles are looked for on the squares
--- because getVehicleById finds none in single player (VehicleManager registers vehicles
--- only on a server; BaseVehicle.createPhysics).
function Bank:findVehicle(matches)
    local reach = Specs.vehicleReach + 3
    for x = self.x - reach, self.x + reach do
        for y = self.y - reach, self.y + reach do
            local square = getSquare(x, y, self.z)
            local vehicle = square and square:getVehicleContainer()
            if vehicle and matches(vehicle) then
                return vehicle
            end
        end
    end
    return nil
end

--- The wire comes off when the vehicle leaves: it lands on the bank's square.
function Bank:dropVehicleWire()
    local square = self:getSquare()
    if square then
        for _ = 1, PowerBank.VEHICLE_WIRE_COUNT do
            square:AddWorldInventoryItem(PowerBank.VEHICLE_WIRE, 0.5, 0.5, 0, false, false)
        end
    end
    self.vehicle = false
end

function Bank:updateVehicle()
    if not self.vehicle then return 0, nil end
    if not self:getSquare() then
        return 0, nil
    end
    -- The database id, unlike getId(), survives a reload.
    local sqlId = self.vehicle.sqlId
    local vehicle = self:findVehicle(function(candidate) return candidate:getSqlId() == sqlId end)
    if not (vehicle and PowerBank.vehicleInReach(self:position(), vehicle)) then
        self:dropVehicleWire()
        return 0, nil
    end
    self.vehicle.id = vehicle:getId()
    return vehicle:isEngineRunning() and Specs.vehicleWatts or 0, vehicle
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

--- The backup generator's state after the failsafe acted, and the watts its charger puts
--- in. While the bank is unloaded, the generator's last known state holds.
function Bank:updateGenerator(hours)
    if not self:getSquare() then
        return 0
    end
    local generator, failsafe = self:findGenerator()
    if not generator then
        self.generator = false
        return 0
    end
    if failsafe then
        runFailsafe(generator, self.on, self.charge)
    end
    self.generator = {
        x = generator:getX(), y = generator:getY(), z = generator:getZ(),
        running = generator:isActivated(), failsafe = failsafe, chargeW = 0,
    }
    local inverter = self:inverterSpec()
    if not (self.generator.running and inverter and inverter.chargerWatts > 0 and self.charge < 1) then
        return 0
    end
    -- The charger is a big load on the generator, so it burns fuel faster.
    local fuel = inverter.chargerWatts / WATTS_PER_FUEL_UNIT * SandboxVars.GeneratorFuelConsumption * hours
    generator:setFuel(generator:getFuel() - fuel)
    self.generator.chargeW = inverter.chargerWatts
    return inverter.chargerWatts
end

function Bank:backupCarriesLoad()
    return self.generator and self.generator.running
end

-- Inverter and load ----------------------------------------------------------------------

--- Measure what the bank powers. Unloaded, the last measurement stands.
function Bank:measureLoad()
    local square = self:getSquare()
    if not square then
        return nil
    end
    local load = Loads.scan(square)
    self.loadW = load.watts
    return load
end

function Bank:tripInverter(reason, watts)
    self.trip = reason
    self.tripW = watts
end

--- Trip the inverter if the load is beyond it. `starting` means the power has just come
--- on, so every motor starts at once; otherwise one compressor may cycle on.
function Bank:checkInverter(load, starting)
    local inverter = self:inverterSpec()
    if not (inverter and load) or self:backupCarriesLoad() then return end
    if load.volts240 then
        self:tripInverter("volts240", load.watts)
    elseif load.watts > inverter.watts then
        self:tripInverter("overload", load.watts)
    else
        local surge = Loads.surgeWatts(load, starting)
        if surge > inverter.surge then
            self:tripInverter("surge", surge)
        end
    end
end

--- Whether the bank should power its squares now.
function Bank:shouldPower()
    return self.on and self:inverterSpec() ~= nil and not self.trip and not self.empty
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

--- The player's switch, or a reset after a trip: the power comes on and every motor
--- starts at once.
function Bank:powerUp()
    self.trip = false
    self.tripW = 0
    self.empty = false
    self:recount()
    if self.on then
        self:checkInverter(self:measureLoad(), true)
    end
    self:switchGenerator()
end

-- Charge ---------------------------------------------------------------------------------

function Bank:coldFactor()
    return Battery.coldFactor(self.tempC)
end

function Bank:capacityWh()
    return self.nominalWh * self:coldFactor()
end

function Bank:updateTemperature()
    local square = self:getSquare()
    if square then
        self.tempC = getClimateManager():getAirTemperatureForSquare(square)
    elseif not self.tempC then
        self.tempC = getClimateManager():getTemperature()
    end
end

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

function Bank:freeze(container, hours)
    if not (container and self.tempC < FREEZE_BELOW_C and self.charge < FREEZE_BELOW_CHARGE) then return end
    local chance = 1 - (1 - FREEZE_CHANCE_PER_HOUR) ^ hours
    eachItem(container, function(item)
        if Battery.isBattery(item) and item:getCondition() > 0 and ZombRandFloat(0, 1) < chance then
            Battery.crack(item)
            sendItemStats(item)
        end
    end)
end

local function today()
    local time = getGameTime()
    return time:getYear() * 1000 + Sun.dayOfYear(time:getMonth(), time:getDay())
end

--- One pass: `hours` of sun, load and charging up to now.
---@param context table see BankSystem.passContext
function Bank:update(hours, context)
    local isoObject = self:getIsoObject()
    local container = isoObject and isoObject:getContainer()
    self:recount()
    self:updateTemperature()

    local solarW, panelWatts = self:updateSources(hours, context)
    local vehicleW = self:updateVehicle()
    local generatorW = self:updateGenerator(hours)
    local inW = solarW + vehicleW + generatorW

    if self:shouldPower() then
        self:checkInverter(self:measureLoad(), false)
    end
    local inverter = self:inverterSpec()
    local demandW = inverter and (self.loadW / INVERTER_EFFICIENCY + inverter.idle) or 0
    local drawW = 0
    if self:shouldPower() and not self:backupCarriesLoad() then
        drawW = demandW
    end

    local capacity = self:capacityWh()
    local stored = self.charge * capacity + (inW - drawW) * hours
    local spilled = math.max(0, stored - capacity)
    stored = math.max(0, math.min(capacity, stored))
    self.charge = capacity > 0 and stored / capacity or 0
    -- An empty bank's inverter cuts out, and comes back once a pass of load is stored, so
    -- a bank that barely charges doesn't stop and start every pass.
    if drawW > 0 and stored <= 0 then
        self.empty = true
    elseif self.empty and stored > 0 and stored >= demandW * hours then
        self.empty = false
    end

    local allowance, uncontrolled = self:controllerHeadroom(panelWatts)
    self.overcharging = spilled > 0 and uncontrolled > 0 and solarW > drawW
    if self.overcharging and container then
        self:wearBatteries(container, function() return OVERCHARGE_WEAR_PER_DAY * hours / 24 end)
    end

    self.solarWhToday = self.solarWhToday + solarW * hours
    self.loadWhToday = self.loadWhToday + (self:shouldPower() and self.loadW or 0) * hours
    self:trackCycle()
    self:newDay(container, today())
    self:freeze(container, hours)
    if container then
        self:writeBatteries(container, false)
        self:recount()
    end
    self:switchGenerator()
    self:showBatteries()

    self.now = { solarW = solarW, vehicleW = vehicleW, generatorW = generatorW, drawW = drawW,
        panelWatts = panelWatts, allowance = allowance, uncontrolled = uncontrolled,
        irradiance = context.irradiance("flat"), elevation = context.elevation, airC = context.airC }
    self:sendStatus()
end

-- The bank's tile shows its batteries and charge.
function Bank:showBatteries()
    local isoObject = self:getIsoObject()
    if not isoObject then return end
    local wanted = Sprites.bankOverlays(isoObject:getSprite():getName(), #self.batteries, self.charge)
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

function Bank:inverterState()
    if not self.inverter then return "none" end
    if self.trip then return "tripped" end
    if not self.on then return "off" end
    if self.empty then return "empty" end
    return "on"
end

function Bank:buildStatus()
    local now = self.now or {}
    local inverter = self:inverterSpec() or { watts = 0, surge = 0, idle = 0, chargerWatts = 0 }
    local capacity = self:capacityWh()
    local batteries = {}
    for _, battery in ipairs(self.batteries) do
        table.insert(batteries, {
            fullType = battery.fullType, nominalWh = battery.nominalWh, wh = battery.nominalWh * self:coldFactor(),
            condition = battery.condition, charge = self.charge,
        })
    end
    local sources = {}
    for _, source in ipairs(self.sources) do
        table.insert(sources, {
            x = source.x, y = source.y, z = source.z, kind = source.kind, facing = source.facing,
            modules = Specs.mounts[source.kind].modules, watts = source.watts or 0, snow = source.snow or 0,
        })
    end
    local panelWatts = 0
    for _, source in ipairs(sources) do
        panelWatts = panelWatts + Specs.moduleWatts * source.modules
    end
    local allowance, uncontrolled = self:controllerHeadroom(panelWatts)
    local generator = self:getIsoObject()
    local drawW = now.drawW or 0
    local inW = (now.solarW or 0) + (now.vehicleW or 0) + (now.generatorW or 0)
    local stored = self.charge * capacity
    return {
        kind = self:spec().sprite,
        on = self.on,
        powered = generator ~= nil and generator:isActivated() or (generator == nil and self:shouldPower()),
        hour = getGameTime():getWorldAgeHours(),
        sunElevation = now.elevation or 0,
        irradiance = now.irradiance or 0,
        solarW = now.solarW or 0, vehicleW = now.vehicleW or 0, generatorW = now.generatorW or 0, inW = inW,
        solarWhToday = self.solarWhToday, loadWhToday = self.loadWhToday,
        loadW = self.loadW, drawW = drawW,
        storedWh = stored, capacityWh = capacity, nominalWh = self.nominalWh, charge = self.charge,
        tempC = self.tempC or 0, coldFactor = self:coldFactor(),
        panelTempFactor = Sun.temperatureFactor(now.airC or 25, now.irradiance or 0),
        hoursLeft = drawW > inW and (stored / (drawW - inW)) or nil,
        cycleDepth = self.cycleDepth,
        inverter = {
            fullType = self.inverter or nil, watts = inverter.watts, surge = inverter.surge, idle = inverter.idle,
            chargerWatts = inverter.chargerWatts, state = self:inverterState(),
            trip = self.trip or nil, tripW = self.trip and self.tripW or nil,
        },
        controllers = {
            count = self.controllers,
            ratedWatts = self.controllers * Specs.controllers["RenewableEnergy.ChargeController"].watts,
            panelWatts = panelWatts, allowanceWatts = allowance, uncontrolledWatts = uncontrolled,
            overcharging = self.overcharging == true,
        },
        batteries = batteries,
        sources = sources,
        vehicle = self.vehicle and {
            id = self.vehicle.id, name = self.vehicle.name, running = (now.vehicleW or 0) > 0, watts = now.vehicleW or 0,
        } or nil,
        generator = self.generator and {
            x = self.generator.x, y = self.generator.y, z = self.generator.z, running = self.generator.running,
            failsafe = self.generator.failsafe, connected = true, chargeW = self.generator.chargeW or 0,
        } or nil,
    }
end

--- Rebuild the status and send it to every client.
function Bank:sendStatus()
    self.status = self:buildStatus()
    self:updateOnClient()
end

return Bank
