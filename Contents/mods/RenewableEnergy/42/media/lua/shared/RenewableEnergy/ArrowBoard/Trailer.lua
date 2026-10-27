-- The solar arrow board trailer (scripts/RenewableEnergy/Vehicles.txt): a highway work-zone
-- trailer whose panels charge the batteries in a padlocked box on its tongue, which light an
-- arrow on its lamp board.
--
-- RenewableEnergy.ArrowBoard is spread over three files, by concern: this one has the trailer,
-- its stock, lid, panels and frame, and the one per-frame watch of every loaded trailer; Power.lua
-- its charging, switch and lamps; Crashes.lua what a crash does to it. The vehicle script's part
-- functions are called on every side, so the files are shared; what only the authority may do
-- says so and takes its server modules when it runs, since a server file is empty on a
-- multiplayer client.
--
-- Each panel is a vehicle part holding a Solar Module, whose condition is the part's, shown by
-- its Whole, LightCracked or Cracked model. Nothing in the game reports a part's condition
-- changing, so every change this file makes shows the model at once, and each charge pass shows
-- every loaded trailer's panels again for the changes it didn't make (a failed uninstall, a debug
-- tool).

require "VehicleZoneDefinition"
local Specs = require "RenewableEnergy/Specs"
local StormNotice = require "RenewableEnergy/StormNotice"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local Chance = require "cf_commonlib/Chance"

local ArrowBoard = {}
-- Vehicles.txt names its part functions by Lua path.
RenewableEnergy = RenewableEnergy or {}
RenewableEnergy.ArrowBoard = ArrowBoard

-- Script name without its module, as VehicleDistributions and OnFillContainer name it.
local VEHICLE = "RenewableEnergyArrowBoardTrailer"
ArrowBoard.SCRIPT = "Base." .. VEHICLE
ArrowBoard.BATTERY_BOX = "RenewableEnergyBatteryBox"
-- In stocking order: the second is the one STOCK.secondCrackedChance may crack.
ArrowBoard.PANELS = { "RenewableEnergyPanelLeft", "RenewableEnergyPanelRight" }
-- The lamp board, under vanilla's rear windshield id (scripts/RenewableEnergy/Vehicles.txt says why).
ArrowBoard.BOARD = "WindshieldRear"

-- Its spawnChance among each vehicle zone's vehicles (VehicleZoneDistribution). The traffic jam
-- zones share one vehicle table. A traffic jam rolls a vehicle in most of its slots
-- (IsoChunk.AddVehicles_TrafficJam_*) and a junkyard in far fewer of its stalls, so most of a
-- map's arrow boards stand in the pileups.
local ZONE_WEIGHTS = { junkyard = 4, trafficjamn = 4 }

-- What a found trailer comes with. Its batteries are worn by years on the road (the Finds profile
-- `batteryWear`). Crews padlocked these boxes because batteries are what thieves take from a work
-- zone, so more are locked than vanilla's trunks, and left the boards running where they stood,
-- so most are switched on.
ArrowBoard.STOCK = {
    modules = 2,
    secondCrackedChance = 0.6,
    batteries = { min = 2, max = 4 },
    battery = "RenewableEnergy.DeepCycleBattery",
    batteryWear = "road",
    controllerChance = 0.75,
    lockedChance = 0.75,
    switchedOnChance = 0.9,
}

-- Vehicle modData: its panels have been stocked, at spawn or, on a trailer saved before the panels
-- were parts, at its first load.
ArrowBoard.PANELS_STOCKED_KEY = "RenewableEnergy_panelsStocked"

for zone, weight in pairs(ZONE_WEIGHTS) do
    VehicleZoneDistribution[zone].vehicles[ArrowBoard.SCRIPT] = { index = -1, spawnChance = weight }
end

function ArrowBoard.isTrailer(vehicle)
    return vehicle ~= nil and vehicle:getScriptName() == ArrowBoard.SCRIPT
end

-- Loaded trailers
--
-- Every loaded trailer this game has seen, by vehicle, with what each concern watches of it each
-- frame: the lid (`lid` and what it last showed), the lamps (`box`, while this game draws them,
-- Power.lua) and crashes (`crash`, while this game runs its physics, Crashes.lua). Its part inits
-- fill an entry as the trailer loads; it goes when the trailer leaves the world.
local trailers = {}

--- This game's entry for the loaded trailer `vehicle` (see above), made on first ask.
function ArrowBoard.trailerEntry(vehicle)
    local entry = trailers[vehicle]
    if not entry then
        entry = {}
        trailers[vehicle] = entry
    end
    return entry
end

-- Stock

--- Stocks the battery box of a freshly spawned arrow board, scaled by the loot rarity options,
--- every find readied (Finds). Authority only.
---@param container ItemContainer
function ArrowBoard.stockBatteryBox(container)
    local Finds = require "RenewableEnergy/Items/Finds"
    local stock = ArrowBoard.STOCK
    local batteries = Chance.between(stock.batteries.min, stock.batteries.max)
    for _ = 1, Finds.scaled(batteries, "LRMBatteries") do
        Finds.add(container, stock.battery, stock.batteryWear)
    end
    if Chance.hit(stock.controllerChance * Finds.placedRarity("LRMMisc")) then
        Finds.add(container, Specs.controller)
    end
end

-- OnFillContainer, which only the authority fires: stocks the container if it is an arrow board's
-- battery box, and sets the switch in it.
local function stockIfBatteryBox(roomName, containerType, container)
    local part = roomName == VEHICLE and instanceof(container, "ItemContainer") and container:getVehiclePart()
    if part and part:getId() == ArrowBoard.BATTERY_BOX then
        ArrowBoard.stockBatteryBox(container)
        ArrowBoard.rollSwitch(part:getVehicle())
    end
end

--- Spawns an arrow board on the square, its tongue pointing `facing` ("N", "E", "S" or "W").
--- Its panels go on and its battery box is stocked as it enters the world. Returns it, or nil
--- when the game kept it out of the world. Authority only.
---@return BaseVehicle?
function ArrowBoard.spawn(square, facing)
    local vehicle = addVehicleDebug(ArrowBoard.SCRIPT, IsoDirections[facing], nil, square)
    -- addVehicleDebug returns a vehicle even where it would hit another vehicle or stand indoors
    -- outside a vehicle zone, but leaves it without a square (IsoChunk.doSpawnedVehiclesInInvalidPosition).
    return vehicle and vehicle:getSquare() and vehicle or nil
end

-- Lid
--
-- The box's lid is a trunk lid under vanilla's TrunkDoor id. Vanilla lets the mechanics window
-- take a locked trunk's lid off when the key isn't needed (VehicleUtils.RequiredKeyNotFound),
-- which this lid never is, so no key spawns and a padlocked box opens only by force: unbolting
-- the lid, which goes back on unlocked (Vehicles.InstallComplete.Door), or Cut Padlock, which
-- breaks the lock so vanilla never locks it again (BaseVehicle.canLockDoor).
--
-- Vanilla swings a door only in the opener's game (ISOpenVehicleDoor:start); everyone else's copy
-- keeps its held pose forever. So every game that draws the trailer swings the lid itself when it
-- sees the door's state change (watchLid).
--
-- Nothing reports a door's lock changing, and installing the lid shows all its models
-- (VehiclePart.setInventoryItem), so every side, the server included, watches the lid and shows
-- the padlock again when any of that changes.

ArrowBoard.LID = "TrunkDoor"
local PADLOCK = "Padlock"

--- Whether the lid's padlock holds: the lid is on, locked, and its lock isn't cut.
function ArrowBoard.isPadlocked(part)
    local door = part:getDoor()
    return part:getInventoryItem() ~= nil and door:isLocked() and not door:isLockBroken()
end

-- Shows the lid's padlock if it holds. On the server the game sends the models to every client.
local function showPadlock(part)
    part:setModelVisible(PADLOCK, ArrowBoard.isPadlocked(part))
end

--- Part `create` of the lid: runs once, when the trailer first enters the world. Shut, and
--- padlocked by STOCK.lockedChance unless the Easy Use option leaves vehicles unlocked, as it
--- does vanilla's trunks.
function ArrowBoard.createLid(vehicle, part)
    VehicleUtils.createPartInventoryItem(part)
    local door = part:getDoor()
    door:setOpen(false)
    door:setLocked(not SandboxVars.VehicleEasyUse and Chance.hit(ArrowBoard.STOCK.lockedChance))
    door:setLockBroken(false)
end

--- Part `init` of the lid: runs on every side each time the trailer loads.
function ArrowBoard.initLid(vehicle, part)
    showPadlock(part)
    local entry = ArrowBoard.trailerEntry(vehicle)
    entry.lid = entry.lid or part
end

--- Cut Padlock: unlocks the lid and breaks its lock, everywhere. Vanilla saves and sends a broken
--- lock with the door and keeps it on the lid's item while the lid is off
--- (Vehicles.UninstallComplete.Door). Authority only; returns whether the trailer has a lid.
function ArrowBoard.cutPadlock(vehicle)
    local lid = vehicle:getPartById(ArrowBoard.LID)
    local door = lid and lid:getDoor()
    if not door then
        return false
    end
    door:setLocked(false)
    door:setLockBroken(true)
    vehicle:transmitPartDoor(lid)
    showPadlock(lid)
    return true
end

local SWINGS_LIDS = not isServer()

-- Shows the padlock again if the lid or its lock changed since this game last looked and, except
-- on a dedicated server, swings a lid seen opening or shutting. A lid seen for the first time
-- isn't swung: the game already holds its pose by the door's state.
local function watchLid(vehicle, entry)
    local lid = entry.lid
    local door = lid:getDoor()
    local item, locked, broken = lid:getInventoryItem(), door:isLocked(), door:isLockBroken()
    if item ~= entry.item or locked ~= entry.locked or broken ~= entry.broken then
        showPadlock(lid)
        entry.item, entry.locked, entry.broken = item, locked, broken
    end
    local open = door:isOpen()
    if SWINGS_LIDS and entry.open ~= nil and open ~= entry.open then
        vehicle:playPartAnim(lid, open and "SwingOpen" or "SwingClose")
    end
    entry.open = open
end

-- Panels

local function isPanel(part)
    local id = part and part:getId()
    return id == ArrowBoard.PANELS[1] or id == ArrowBoard.PANELS[2]
end

-- The panel model that shows each look of ModuleRepair.crackLookOf, and the whole one.
local MODEL_OF_LOOK = { light = "LightCracked", heavy = "Cracked" }
local PANEL_MODELS = { "Whole", "LightCracked", "Cracked" }

--- How the glass of the module on the panel `part` looks (ModuleRepair.crackLookOf): nil whole
--- or without a module, else "light" or "heavy".
function ArrowBoard.crackLookOf(part)
    local item = part:getInventoryItem()
    return item and ModuleRepair.crackLookOf(item:getFullType(), part:getCondition())
end

-- Shows the model `shown` of the panel `part` and hides the others; nil hides every one.
local function showModel(part, shown)
    for _, model in ipairs(PANEL_MODELS) do
        part:setModelVisible(model, model == shown)
    end
end

--- Shows exactly one of the panel's Whole, LightCracked or Cracked models by its module's look, or
--- none without one. Showing a model that already shows costs nothing, so callers needn't know
--- what changed. On the server the game sends the models to every client (VehiclePartModels).
function ArrowBoard.showPanel(part)
    local shown = nil
    if part:getInventoryItem() then
        local look = ArrowBoard.crackLookOf(part)
        shown = look and MODEL_OF_LOOK[look] or "Whole"
    end
    showModel(part, shown)
end

function ArrowBoard.showPanels(vehicle)
    for _, id in ipairs(ArrowBoard.PANELS) do
        local part = vehicle:getPartById(id)
        if part then
            ArrowBoard.showPanel(part)
        end
    end
end

-- The trailers stocked this tick, with their modules and the conditions they got. addVehicleDebug
-- and the world's vehicle stories set every part's condition after the parts were made
-- (BaseVehicle.setGeneralPartCondition, RandomizedWorldBase.addVehicle), over the stock ones, so
-- the next tick puts them back.
local justStocked = {}

-- Puts modules on its panels, as many as the panel rarity option gives, the second maybe cracked.
-- Once per trailer. Authority only.
local function stockPanels(vehicle)
    local modData = vehicle:getModData()
    if modData[ArrowBoard.PANELS_STOCKED_KEY] then
        return
    end
    modData[ArrowBoard.PANELS_STOCKED_KEY] = true
    local Finds = require "RenewableEnergy/Items/Finds"
    local stock = ArrowBoard.STOCK
    local count = Finds.scaled(stock.modules, "LRMSolarPanels")
    local panels = {}
    for i, id in ipairs(ArrowBoard.PANELS) do
        local part = vehicle:getPartById(id)
        if part and i <= count and not part:getInventoryItem() then
            local cracked = i == 2 and Chance.hit(stock.secondCrackedChance)
            local item = Finds.newModule(cracked and Finds.crackedCondition() or Finds.weatheredCondition())
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

-- Gives the modules stocked last tick their stock conditions back where something has set them
-- since. Authority only. No event follows the game's setting the conditions, so the next tick is
-- the first moment after it.
local function keepStockConditions()
    local stocked = justStocked
    justStocked = {}
    for _, trailer in ipairs(stocked) do
        for _, panel in ipairs(trailer.panels) do
            local part = panel.part
            if part:getInventoryItem() == panel.item and part:getCondition() ~= panel.condition then
                -- A client may have got the trailer already and shown the panel by the condition
                -- it had then, and the server sends a part's models only when they change
                -- (BaseVehicle.setModelVisible), so they change twice.
                showModel(part, nil)
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

--- Part `init` of the panels: runs on every side each time the trailer loads. The trailer's
--- crashes are watched from then on (Crashes.lua).
function ArrowBoard.initPanel(vehicle, part)
    if not isClient() then
        stockPanels(vehicle)
    end
    ArrowBoard.showPanel(part)
    ArrowBoard.watchCrashes(vehicle)
end

--- Install and uninstall `complete` of the panels, on the authority.
function ArrowBoard.panelChanged(vehicle, part)
    ArrowBoard.showPanel(part)
end

--- Cracks the panel's module as a storm cracks a module. Authority only.
function ArrowBoard.crackPanel(vehicle, part)
    setPanelCondition(vehicle, part, math.max(0, part:getCondition() - Specs.storm.crack))
end

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

--- A thunderstorm may crack each panel as it would a flat panel's module (PanelStorms.stormCrack),
--- over `stormHours` of storm, telling the players in earshot (StormNotice). Authority only.
--- Returns how many cracked.
function ArrowBoard.stormCrack(vehicle, stormHours)
    local PanelStorms = require "RenewableEnergy/PowerBank/PanelStorms"
    local cracked = 0
    for _, part in ipairs(installedPanels(vehicle)) do
        local source = { kind = "flat", modules = { { condition = part:getCondition() } } }
        if PanelStorms.stormCrack(source, stormHours) then
            setPanelCondition(vehicle, part, source.modules[1].condition)
            cracked = cracked + 1
        end
    end
    if cracked > 0 then
        StormNotice.tell(StormNotice.CRACKED_MODULE, math.floor(vehicle:getX()), math.floor(vehicle:getY()), math.floor(vehicle:getZ()))
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

--- The watts its panels would make in full sun, as the same modules on a mount make.
function ArrowBoard.panelWatts(vehicle)
    local watts = 0
    for _, part in ipairs(installedPanels(vehicle)) do
        watts = watts + Panel.moduleWatts(part:getInventoryItem():getFullType(), part:getCondition())
    end
    return watts
end

--- The trailer's panel `partId` if it holds a module that Seal Cracked Panel can seal, else nil.
function ArrowBoard.sealablePanel(vehicle, partId)
    local part = ArrowBoard.isTrailer(vehicle) and vehicle:getPartById(partId)
    local item = part and isPanel(part) and part:getInventoryItem()
    if item and ModuleRepair.sealable(item:getFullType(), part:getCondition(), item:getHaveBeenRepaired()) then
        return part
    end
    return nil
end

--- Seal Cracked Panel's effect on a module still on the trailer (its inputs, skill and XP are the
--- job's materials: ModuleRepair.SEAL). Authority only, once the job was checked (VehicleJobs).
function ArrowBoard.sealPanel(vehicle, partId)
    local part = vehicle:getPartById(partId)
    -- As vanilla's fixPart (VehicleCommands.lua): count the repair on the item, then send it.
    local item = part:getInventoryItem()
    local condition, repaired = ModuleRepair.sealed(item:getFullType(), part:getCondition(), item:getHaveBeenRepaired())
    item:setHaveBeenRepaired(repaired)
    setPanelCondition(vehicle, part, condition)
    vehicle:transmitPartItem(part)
    return true
end

-- Frame
--
-- The frame's front and back are parts under vanilla's EngineDoor and TruckBed ids, the only ids
-- whose condition the game shows as dents on the body, so crashes dent them with no help from
-- here. Repair Frame welds them through vanilla's fixing, from the trailer's menu, since the
-- mechanics window doesn't show them.

-- Each frame part and the name the repair menu gives it.
ArrowBoard.FRAME = {
    { id = "EngineDoor", name = "IGUI_RenewableEnergy_FrameFront" },
    { id = "TruckBed", name = "IGUI_RenewableEnergy_FrameBack" },
    { id = ArrowBoard.BOARD, name = "IGUI_RenewableEnergy_LampBoard" },
}

--- Part `init` of the frame parts and the lamp board: runs on every side each time the trailer
--- loads.
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

-- Every frame

local FLASHES = not isServer()

-- OnTick: puts back the stock conditions of the trailers stocked last tick, and for every loaded
-- trailer watches its lid, flashes its lamps and samples its crashes, each where its entry has
-- that part (see `trailers`). Nothing the game fires reports any of these, so it must poll;
-- allocates nothing unless a lamppost moves.
local function eachFrame()
    if #justStocked > 0 then
        keepStockConditions()
    end
    local now = getTimestampMs()
    local flashLit = FLASHES and ArrowBoard.flashPhase(now)
    for vehicle, entry in pairs(trailers) do
        if vehicle:isRemovedFromWorld() then
            ArrowBoard.forgetLamps(entry)
            trailers[vehicle] = nil
        else
            if entry.lid then
                watchLid(vehicle, entry)
            end
            if entry.box then
                ArrowBoard.flashLamps(vehicle, entry, flashLit)
            end
            if entry.crash then
                ArrowBoard.sampleTrailer(vehicle, entry.crash, now)
            end
        end
    end
end

Events.OnTick.Add(eachFrame)

-- Only the authority fills containers and parses the loot tables.
if not isClient() then
    -- An empty table for the box, so that randomizeContainers fills it and fires OnFillContainer.
    -- VehicleDistributions is server Lua, which loads after this file; the merge comes after both.
    Events.OnPostDistributionMerge.Add(function()
        VehicleDistributions[1][VEHICLE] = {
            Normal = { [ArrowBoard.BATTERY_BOX] = { rolls = 0, items = {} } },
        }
    end)
    Events.OnFillContainer.Add(stockIfBatteryBox)
end

return ArrowBoard
