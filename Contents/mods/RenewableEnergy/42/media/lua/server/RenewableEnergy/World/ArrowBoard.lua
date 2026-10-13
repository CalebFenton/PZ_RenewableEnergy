require "Vehicles/VehicleDistributions"
require "VehicleZoneDefinition"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sun"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/Bank"
require "RenewableEnergy/World/WorldSpawns"

-- The solar arrow board trailer (scripts/RenewableEnergy/Vehicles.txt): a highway work-zone
-- trailer with a lamp board and two panels, its batteries in a lockable box on the tongue. It
-- turns up among junkyard and traffic jam wrecks and with tradesmen's vans, and at the road
-- works of SolarSites.lua. Its battery box is stocked the first time the trailer spawns, from
-- Distributions' OnFillContainer. Its panels charge the batteries in the box in daylight, wherever
-- it stands or is towed (GadgetCharging runs it).
--
-- Each panel is a vehicle part holding a Solar Module, whose condition is the part's: storms and
-- hard crashes crack it, Repair Cracked Panel mends it on the trailer, and the mechanics window
-- takes it off and puts any module on. The part shows its Whole or its Cracked model by that
-- condition. Nothing in the game reports a part's condition changing, so every change this file
-- makes shows it at once, and each charge pass shows every loaded trailer's panels again for the
-- changes it didn't make (a failed uninstall, a debug tool).
--
-- Its frame dents in crashes as a car's body does, and Repair Frame welds it (Frame, below).

RenewableEnergy = RenewableEnergy or {}
local ArrowBoard = {}
RenewableEnergy.ArrowBoard = ArrowBoard

local Specs = RenewableEnergy.Specs

-- Script name without its module, as VehicleDistributions and OnFillContainer name it.
ArrowBoard.VEHICLE = "RenewableEnergyArrowBoardTrailer"
ArrowBoard.SCRIPT = "Base." .. ArrowBoard.VEHICLE
ArrowBoard.BATTERY_BOX = "RenewableEnergyBatteryBox"
-- The panel parts, left then right.
ArrowBoard.PANELS = { "RenewableEnergyPanelLeft", "RenewableEnergyPanelRight" }

-- Its spawn weight among each vehicle zone's vehicles (VehicleZoneDistribution spawnChance).
-- The four traffic jam zones share one vehicle table. About 5 a map, with the road works.
ArrowBoard.ZONE_WEIGHTS = { junkyard = 4, trafficjamn = 4, trades = 2 }

-- What it comes with: modules on its panels, the second often cracked; in its battery box deep
-- cycle batteries, charged by Distributions.chargeFoundBatteries, and a charge controller.
ArrowBoard.STOCK = {
    modules = 2,
    secondCrackedChance = 0.6,
    batteries = { min = 4, max = 6 },
    battery = "RenewableEnergy.DeepCycleBattery",
    controllerChance = 1,
}

-- A hard crash: the trailer's velocity changing by at least `kmh` within `ms` milliseconds of real
-- time. A car stopping dead against a wall from that speed does it; braking hard sheds about 3 km/h
-- in that time and running over a zombie or a kerb a few, so minor bumps never crack a panel.
-- `quietMs` keeps one crash, which the physics spreads over several frames, from counting twice.
-- `unhitchedMs` and `unhitchedSquares` cover a crash that snaps the hitch (Crashes, below).
ArrowBoard.CRASH = { kmh = 20, ms = 250, quietMs = 1000, unhitchedMs = 1000, unhitchedSquares = 8 }

-- Vehicle modData: its panels have been put on, at spawn or, for a trailer from a save made
-- before they were parts, on its first load since.
local PANELS_STOCKED = "RenewableEnergy_panelsStocked"
-- The client command a driver sends when the trailer they tow crashes.
local COMMAND_MODULE, CRASH_COMMAND = "RenewableEnergyArrowBoard", "crashed"

for zone, weight in pairs(ArrowBoard.ZONE_WEIGHTS) do
    VehicleZoneDistribution[zone].vehicles[ArrowBoard.SCRIPT] = { index = -1, spawnChance = weight }
end

-- An empty table for the box, so that randomizeContainers fills it and fires OnFillContainer.
VehicleDistributions[1][ArrowBoard.VEHICLE] = {
    Normal = { [ArrowBoard.BATTERY_BOX] = { rolls = 0, items = {} } },
}

function ArrowBoard.isTrailer(vehicle)
    return vehicle ~= nil and vehicle:getScriptName() == ArrowBoard.SCRIPT
end

--- Stocks the battery box of a freshly spawned arrow board, scaled by the loot rarity options.
--- Authority only.
---@param container ItemContainer
function ArrowBoard.stockBatteryBox(container)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local options = SandboxVars.RenewableEnergy
    local stock = ArrowBoard.STOCK
    local batteries = WorldSpawns.rollBetween(stock.batteries)
    for _ = 1, WorldSpawns.scaled(batteries, options.LRMBatteries) do
        container:AddItem(stock.battery)
    end
    if ZombRandFloat(0, 1) < stock.controllerChance * options.LRMMisc then
        container:AddItem(Specs.controller)
    end
end

--- OnFillContainer: stocks the container if it is an arrow board's battery box.
function ArrowBoard.stockIfBatteryBox(roomName, container)
    local part = roomName == ArrowBoard.VEHICLE and container:getVehiclePart()
    if part and part:getId() == ArrowBoard.BATTERY_BOX then
        ArrowBoard.stockBatteryBox(container)
    end
end

--- Spawns an arrow board on the square, its tongue pointing `facing` ("N", "E", "S" or "W").
--- Its panels go on and its battery box is stocked as it enters the world. Authority only.
---@return BaseVehicle?
function ArrowBoard.spawn(square, facing)
    return addVehicleDebug(ArrowBoard.SCRIPT, IsoDirections[facing], nil, square)
end

-- Panels ---------------------------------------------------------------------------------------

function ArrowBoard.isPanel(part)
    local id = part and part:getId()
    return id == ArrowBoard.PANELS[1] or id == ArrowBoard.PANELS[2]
end

--- Whether a module at this condition has a cracked cover glass.
function ArrowBoard.isCracked(condition)
    return condition < Specs.crackedBelow
end

--- Shows the panel's Whole or Cracked model by its module's condition, or neither without one.
--- Showing a model that already shows costs nothing, so callers needn't know what changed. On
--- the server the game sends the models to every client (VehiclePartModels).
function ArrowBoard.showPanel(part)
    local installed = part:getInventoryItem() ~= nil
    local cracked = installed and ArrowBoard.isCracked(part:getCondition())
    part:setModelVisible("Whole", installed and not cracked)
    part:setModelVisible("Cracked", cracked)
end

function ArrowBoard.showPanels(vehicle)
    for _, id in ipairs(ArrowBoard.PANELS) do
        local part = vehicle:getPartById(id)
        if part then
            ArrowBoard.showPanel(part)
        end
    end
end

-- The trailers stocked this tick, each { vehicle, panels = { { part, item, condition } } }: the
-- modules on their panels and the conditions they got. addVehicleDebug and the world's vehicle
-- stories set every part's condition after the parts were made (BaseVehicle.setGeneralPartCondition,
-- RandomizedWorldBase.addVehicle), over the stock ones, so the next tick puts them back.
local justStocked = {}

-- Puts modules on its panels as the box once held them: the first weathered, the second weathered
-- or cracked, as many as the panel rarity option gives. Once per trailer. Authority only.
local function stockPanels(vehicle)
    local modData = vehicle:getModData()
    if modData[PANELS_STOCKED] then
        return
    end
    modData[PANELS_STOCKED] = true
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local stock = ArrowBoard.STOCK
    local count = WorldSpawns.scaled(stock.modules, SandboxVars.RenewableEnergy.LRMSolarPanels)
    local panels = {}
    for i, id in ipairs(ArrowBoard.PANELS) do
        local part = vehicle:getPartById(id)
        if part and i <= count and not part:getInventoryItem() then
            local cracked = i == 2 and ZombRandFloat(0, 1) < stock.secondCrackedChance
            local item = instanceItem(Specs.factoryModule)
            RenewableEnergy.Wear.setCondition(item, cracked and WorldSpawns.crackedCondition() or WorldSpawns.weatheredCondition())
            part:setInventoryItem(item)
            vehicle:transmitPartItem(part)
            table.insert(panels, { part = part, item = item, condition = item:getCondition() })
        end
    end
    if #panels > 0 then
        table.insert(justStocked, { vehicle = vehicle, panels = panels })
    end
end

-- Sets a panel's condition, which is its module's, everywhere, and shows it. Authority only.
local function setPanelCondition(vehicle, part, condition)
    part:setCondition(condition)
    vehicle:transmitPartCondition(part)
    ArrowBoard.showPanel(part)
end

--- OnTick: gives the modules stocked last tick their stock conditions back where something has
--- set them since. Authority only.
function ArrowBoard.keepStockConditions()
    if #justStocked == 0 then
        return
    end
    local trailers = justStocked
    justStocked = {}
    for _, trailer in ipairs(trailers) do
        for _, panel in ipairs(trailer.panels) do
            local part = panel.part
            if part:getInventoryItem() == panel.item and part:getCondition() ~= panel.condition then
                -- A client may have got the trailer already and shown the panel by the condition
                -- it had then, and the server sends a part's models only when they change
                -- (BaseVehicle.setModelVisible), so they change twice.
                part:setModelVisible("Whole", false)
                part:setModelVisible("Cracked", false)
                setPanelCondition(trailer.vehicle, part, panel.condition)
            end
        end
    end
end

--- Part `create` of the panels: runs once for each when the trailer first enters the world.
function ArrowBoard.createPanel(vehicle, part)
    if not isClient() then
        stockPanels(vehicle)
    end
end

--- Part `init` of the panels: runs on every side each time the trailer loads.
function ArrowBoard.initPanel(vehicle, part)
    if not isClient() then
        stockPanels(vehicle)
    end
    ArrowBoard.showPanel(part)
    ArrowBoard.track(vehicle)
end

--- Install and uninstall `complete` of the panels, on the authority.
function ArrowBoard.panelChanged(vehicle, part)
    ArrowBoard.showPanel(part)
end

--- Cracks the panel's module as a storm cracks a module: by Specs.storm.crack. Authority only.
function ArrowBoard.crackPanel(vehicle, part)
    setPanelCondition(vehicle, part, math.max(0, part:getCondition() - Specs.storm.crack))
end

-- The installed panels.
local function installedPanels(vehicle)
    local panels = {}
    for _, id in ipairs(ArrowBoard.PANELS) do
        local part = vehicle:getPartById(id)
        if part and part:getInventoryItem() then
            table.insert(panels, part)
        end
    end
    return panels
end

--- A thunderstorm may crack each panel as it would a flat panel's module (Bank.stormCrack), over
--- `stormHours` of storm. Authority only. Returns how many cracked.
function ArrowBoard.stormCrack(vehicle, stormHours)
    local cracked = 0
    for _, part in ipairs(installedPanels(vehicle)) do
        local source = { kind = "flat", modules = { { condition = part:getCondition() } } }
        if RenewableEnergy.Bank.stormCrack(source, stormHours) then
            setPanelCondition(vehicle, part, source.modules[1].condition)
            cracked = cracked + 1
        end
    end
    return cracked
end

--- A hard crash cracks every panel with any glass left. Authority only.
function ArrowBoard.crashCrack(vehicle)
    for _, part in ipairs(installedPanels(vehicle)) do
        if part:getCondition() > 0 then
            ArrowBoard.crackPanel(vehicle, part)
        end
    end
end

-- Frame ----------------------------------------------------------------------------------------
--
-- The frame's front and back are parts under vanilla's EngineDoor and TruckBed ids, the only ids
-- whose condition the game shows as dents on the body (scripts/RenewableEnergy/Vehicles.txt), so
-- crashes and road kills dent them with no help from here. Repair Frame welds them through
-- vanilla's fixing, from the trailer's menu, since the mechanics window doesn't show them.

-- Each frame part and the name the repair menu gives it.
ArrowBoard.FRAME = {
    { id = "EngineDoor", name = "IGUI_RenewableEnergy_FrameFront" },
    { id = "TruckBed", name = "IGUI_RenewableEnergy_FrameBack" },
}

--- Part `init` of the frame parts: runs on every side each time the trailer loads.
function ArrowBoard.initFrame(vehicle, part)
    -- A part added to the script after a trailer spawned is never created on it, so a trailer
    -- from an older save gets its frame here.
    if not isClient() and not part:getInventoryItem() then
        VehicleUtils.createPartInventoryItem(part)
        vehicle:transmitPartItem(part)
    end
    -- The colour is rolled at spawn, so a trailer spawned before the script forced it keeps a
    -- random one, which would tint its dents.
    local script = vehicle:getScript()
    vehicle:setColorHSV(script:getForcedHue(), script:getForcedSat(), script:getForcedVal())
end

--- The trailer's frame parts that are dented: { part, name } for each, front first.
function ArrowBoard.damagedFrame(vehicle)
    local damaged = {}
    for _, frame in ipairs(ArrowBoard.isTrailer(vehicle) and ArrowBoard.FRAME or {}) do
        local part = vehicle:getPartById(frame.id)
        if part and part:getInventoryItem() and part:getCondition() < 100 then
            table.insert(damaged, { part = part, name = frame.name })
        end
    end
    return damaged
end

-- Crashes --------------------------------------------------------------------------------------
--
-- A crash reaches a towed trailer only as damage to vanilla's part ids (BaseVehicle.crash and
-- addDamageFront/Rear), which the panels aren't, and the trailer's own crash durability isn't
-- readable from Lua. So the side running the trailer's physics watches its velocity: single player
-- every loaded trailer, a multiplayer client the trailer behind the car it drives, which then asks
-- the server to crack the panels, as vanilla's own crash command does. A crash hard enough can
-- snap the hitch in the physics step that jolts the trailer (Bullet.onVehicleConstraintImpulse),
-- so that client goes on watching a trailer its car towed for ArrowBoard.CRASH.unhitchedMs, and
-- the server takes the crash from the car's driver while the trailer is within
-- ArrowBoard.CRASH.unhitchedSquares of the car's tow bar.

-- Loaded trailers by vehicle: their recent velocities, { ms, x, y } oldest first, the time of
-- their last crash, and on a multiplayer client the car of this game's player that last towed
-- them and until when that car's crashes still count.
local tracked = {}

function ArrowBoard.track(vehicle)
    if not tracked[vehicle] and not isServer() then
        tracked[vehicle] = { samples = {}, crashedAt = -math.huge }
    end
end

local function drivenHere(car)
    local driver = car:getDriver()
    return driver ~= nil and instanceof(driver, "IsoPlayer") and driver:isLocalPlayer()
end

-- Whether this game runs the trailer's physics: single player, or the client whose player drives
-- the car towing it or towed it a moment ago. Returns true, or that car.
local function runsPhysics(vehicle, entry, now)
    if not isClient() then
        return true
    end
    local tow = vehicle:getVehicleTowedBy()
    if tow and drivenHere(tow) then
        entry.car, entry.carUntil = tow, now + ArrowBoard.CRASH.unhitchedMs
    elseif entry.car and (now > entry.carUntil or tow or not drivenHere(entry.car)) then
        entry.car = nil
    end
    return entry.car
end

local velocity = Vector3f.new()

--- Records the trailer's velocity now and returns whether it changed by a crash's worth within
--- ArrowBoard.CRASH.ms.
function ArrowBoard.sampleCrash(vehicle, entry, now)
    vehicle:getLinearVelocity(velocity)
    local x, y = velocity:x(), velocity:z()
    local samples = entry.samples
    while samples[1] and now - samples[1].ms > ArrowBoard.CRASH.ms do
        table.remove(samples, 1)
    end
    local limit = ArrowBoard.CRASH.kmh / 3.6
    local crashed = false
    for _, sample in ipairs(samples) do
        if (x - sample.x) ^ 2 + (y - sample.y) ^ 2 >= limit * limit then
            crashed = true
        end
    end
    table.insert(samples, { ms = now, x = x, y = y })
    if crashed and now - entry.crashedAt >= ArrowBoard.CRASH.quietMs then
        entry.crashedAt = now
        return true
    end
    return false
end

local cell
function ArrowBoard.watchCrashes()
    local now = getTimestampMs()
    cell = cell or getCell()
    for vehicle, entry in pairs(tracked) do
        if not cell:getVehicles():contains(vehicle) then
            -- Left the cell or the world; a vehicle joins the cell a frame after it spawns, so one
            -- not yet in it waits.
            if vehicle:isRemovedFromWorld() then
                tracked[vehicle] = nil
            end
        else
            local runs = runsPhysics(vehicle, entry, now)
            if runs and ArrowBoard.sampleCrash(vehicle, entry, now) then
                if isClient() then
                    sendClientCommand(getPlayer(), COMMAND_MODULE, CRASH_COMMAND, { vehicle = vehicle:getId(), car = runs:getId() })
                else
                    ArrowBoard.crashCrack(vehicle)
                end
            end
        end
    end
end

-- Whether the trailer, no longer towed, is still close behind the car.
local function justUnhitched(vehicle, car)
    if vehicle:getVehicleTowedBy() then
        return false
    end
    local hitch = car:getTowingWorldPos("trailer", Vector3f.new())
    local coupler = vehicle:getTowedByWorldPos("trailer", Vector3f.new())
    local squares = ArrowBoard.CRASH.unhitchedSquares
    return hitch ~= nil and coupler ~= nil and (hitch:x() - coupler:x()) ^ 2 + (hitch:y() - coupler:y()) ^ 2 <= squares * squares
end

-- The server takes a crash only from the driver of the car towing the trailer, or towing it until
-- a moment ago.
local function onClientCommand(module, command, player, args)
    if module ~= COMMAND_MODULE or command ~= CRASH_COMMAND or type(args) ~= "table" or type(args.vehicle) ~= "number"
        or type(args.car) ~= "number" then
        return
    end
    local vehicle, car = getVehicleById(args.vehicle), getVehicleById(args.car)
    if ArrowBoard.isTrailer(vehicle) and car and car:isDriver(player)
        and (vehicle:getVehicleTowedBy() == car or justUnhitched(vehicle, car)) then
        ArrowBoard.crashCrack(vehicle)
    end
end

if not isServer() then
    Events.OnTick.Add(ArrowBoard.watchCrashes)
end
if not isClient() then
    Events.OnClientCommand.Add(onClientCommand)
    Events.OnTick.Add(ArrowBoard.keepStockConditions)
end

-- Repair on the trailer ------------------------------------------------------------------------

--- The trailer's panel `partId` if it holds a module that Repair Cracked Panel can mend, else nil.
function ArrowBoard.repairablePanel(vehicle, partId)
    local part = ArrowBoard.isTrailer(vehicle) and vehicle:getPartById(partId)
    local item = part and ArrowBoard.isPanel(part) and part:getInventoryItem()
    if item and ArrowBoard.isCracked(part:getCondition()) and RenewableEnergy.Recipes.isModuleBelowRepairCap(item) then
        return part
    end
    return nil
end

--- Repair Cracked Panel: Repair Cracked Module's inputs, skill, XP and effect on a module still
--- on the trailer. Authority only; returns whether it repaired.
function ArrowBoard.repairPanel(character, vehicle, partId)
    local Recipes = RenewableEnergy.Recipes
    local part = ArrowBoard.repairablePanel(vehicle, partId)
    local inputs = part and Recipes.panelRepairRefusal(character) == nil and Recipes.panelRepairInputs(character)
    if not inputs then
        return false
    end
    Recipes.useInputs(inputs, character)
    local item = part:getInventoryItem()
    setPanelCondition(vehicle, part, Recipes.repairedCondition(item))
    Recipes.moduleRepairRecipe():addXP(character)
    return true
end

-- Charging -------------------------------------------------------------------------------------

--- The watts its panels would make in full sun: each installed module's rating times its
--- condition / 100, as a module on a mount makes.
function ArrowBoard.panelWatts(vehicle)
    local watts = 0
    for _, part in ipairs(installedPanels(vehicle)) do
        local module = Specs.modules[part:getInventoryItem():getFullType()]
        watts = watts + (module and module.watts or 0) * part:getCondition() / 100
    end
    return watts
end

-- The battery in the box with the lowest charge that isn't full, or nil.
local function emptiestBattery(container)
    local Battery = RenewableEnergy.Battery
    local emptiest
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if Battery.nominalWh(item) > 0 and Battery.getCharge(item) < 1
            and (not emptiest or Battery.getCharge(item) < Battery.getCharge(emptiest)) then
            emptiest = item
        end
    end
    return emptiest
end

--- Adds `hours` of its panels' current output to the batteries in its battery box, the emptiest
--- first, so that a mixed set fills evenly. The panels count as flat, since the trailer may face
--- any way, and make nothing under a roof. Authority only. Returns the watt-hours stored.
---@param vehicle BaseVehicle
function ArrowBoard.charge(vehicle, hours)
    if not ArrowBoard.isTrailer(vehicle) then
        return 0
    end
    local square = vehicle:getSquare()
    local part = vehicle:getPartById(ArrowBoard.BATTERY_BOX)
    local container = part and part:getItemContainer()
    if not (container and square and square:isOutside()) then
        return 0
    end
    local Battery = RenewableEnergy.Battery
    local wh = RenewableEnergy.Sun.panelWatts(ArrowBoard.panelWatts(vehicle), "flat") * hours
    local stored = 0
    local battery = wh > 0 and emptiestBattery(container)
    while battery do
        local before = Battery.getCharge(battery)
        local room = (1 - before) * Battery.nominalWh(battery)
        local added = math.min(wh, room)
        -- Exactly full when it fills, so the loop moves on to the next battery.
        Battery.setCharge(battery, added == room and 1 or before + added / Battery.nominalWh(battery))
        -- As the maintainer does: clients hear of the charge once it shows at two decimals.
        if VehicleUtils.compareFloats(before, Battery.getCharge(battery), 2) then
            sendItemStats(battery)
        end
        wh, stored = wh - added, stored + added
        battery = wh > 0 and emptiestBattery(container)
    end
    return stored
end

--- The charge pass for one loaded vehicle: if it is an arrow board, storms may crack its panels,
--- its panels show what they hold, and they charge its box. Authority only.
function ArrowBoard.update(vehicle, hours)
    if not ArrowBoard.isTrailer(vehicle) then
        return 0
    end
    ArrowBoard.stormCrack(vehicle, RenewableEnergy.Bank.stormHours(hours))
    ArrowBoard.showPanels(vehicle)
    return ArrowBoard.charge(vehicle, hours)
end

return ArrowBoard
