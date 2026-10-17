require "Vehicles/VehicleDistributions"
require "VehicleZoneDefinition"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/PanelSource"
require "RenewableEnergy/World/WorldSpawns"

-- The solar arrow board trailer (scripts/RenewableEnergy/Vehicles.txt): a highway work-zone
-- trailer whose panels charge the batteries in a padlocked box on its tongue, which light an
-- arrow on its lamp board. It turns up among junkyard and traffic jam wrecks and at SolarSites'
-- road works. Distributions' OnFillContainer stocks its box when it first spawns, and
-- GadgetCharging's pass charges it and runs its lamps wherever it stands or is towed.
--
-- RenewableEnergy.ArrowBoard is spread over three files, by concern: this one has the trailer,
-- its stock, lid, panels and frame; ArrowBoardPower.lua its charging, switch and lamps;
-- ArrowBoardCrashes.lua what a crash does to it. The vehicle script's part functions are called
-- on every side, and a multiplayer client loads server Lua too (GameLoadingState.enter), so these
-- files have no isClient guard; what only the authority may do says so.
--
-- Each panel is a vehicle part holding a Solar Module, whose condition is the part's, shown by
-- its Whole or Cracked model. Nothing in the game reports a part's condition changing, so every
-- change this file makes shows the model at once, and each charge pass shows every loaded
-- trailer's panels again for the changes it didn't make (a failed uninstall, a debug tool).

RenewableEnergy = RenewableEnergy or {}
local ArrowBoard = {}
RenewableEnergy.ArrowBoard = ArrowBoard

local Specs = RenewableEnergy.Specs

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

-- What a found trailer comes with. Its batteries are worn by years on the road, and
-- Distributions.chargeFoundBatteries charges them. Crews padlocked these boxes because batteries
-- are what thieves take from a work zone, so more are locked than vanilla's trunks, and left the
-- boards running where they stood, so most are switched on.
ArrowBoard.STOCK = {
    modules = 2,
    secondCrackedChance = 0.6,
    batteries = { min = 2, max = 4 },
    battery = "RenewableEnergy.DeepCycleBattery",
    batteryCondition = { min = 0, max = 80 },
    controllerChance = 0.75,
    lockedChance = 0.75,
    switchedOnChance = 0.9,
}

-- Vehicle modData: its panels have been stocked, at spawn or, on a trailer saved before the panels
-- were parts, at its first load.
ArrowBoard.PANELS_STOCKED = "RenewableEnergy_panelsStocked"

for zone, weight in pairs(ZONE_WEIGHTS) do
    VehicleZoneDistribution[zone].vehicles[ArrowBoard.SCRIPT] = { index = -1, spawnChance = weight }
end

-- An empty table for the box, so that randomizeContainers fills it and fires OnFillContainer.
VehicleDistributions[1][VEHICLE] = {
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
        local battery = container:AddItem(stock.battery)
        if battery then
            RenewableEnergy.Wear.setCondition(battery, WorldSpawns.rollBetween(stock.batteryCondition))
        end
    end
    if ZombRandFloat(0, 1) < stock.controllerChance * options.LRMMisc then
        container:AddItem(Specs.controller)
    end
end

--- OnFillContainer: stocks the container if it is an arrow board's battery box, and sets the
--- switch in it.
function ArrowBoard.stockIfBatteryBox(roomName, container)
    local part = roomName == VEHICLE and container:getVehiclePart()
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

-- Lid ------------------------------------------------------------------------------------------
--
-- The box's lid is a trunk lid under vanilla's TrunkDoor id (scripts/RenewableEnergy/Vehicles.txt).
-- Vanilla lets the mechanics window take a locked trunk's lid off when the key isn't needed for it
-- (VehicleUtils.RequiredKeyNotFound), which this lid never is, so no key spawns and a padlocked
-- box opens only by force: unbolting the lid, which goes back on unlocked
-- (Vehicles.InstallComplete.Door), or Cut Padlock (ArrowBoard.cutPadlock, offered by
-- UI/BatteryBoxLid.lua), which breaks the lock so vanilla never locks it again
-- (BaseVehicle.canLockDoor).
--
-- Vanilla swings a door only in the opener's game, as the action starts and before the server
-- has said whether it opened (ISOpenVehicleDoor:start); everyone else's copy keeps its held pose,
-- which BaseVehicle.updateAnimationPlayer replaces only once it ends, and it never ends. So every
-- game that draws the trailer, the opener's included, swings the lid itself when it sees the
-- door's state change (watchLids).
--
-- Nothing reports a door's lock changing, and installing the lid shows all its models
-- (VehiclePart.setInventoryItem), so every side watches the lid and shows the padlock again when
-- any of that changes; the server too, since its models are what it sends its clients
-- (VehiclePartModels).

ArrowBoard.LID = "TrunkDoor"
local PADLOCK = "Padlock"

-- The lids of the trailers this game has loaded, by vehicle: the lid part (lid), the lid's item,
-- lock and broken lock it last showed the padlock for, and whether it last saw the lid open (nil
-- until it first looks).
local lids = {}

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
    door:setLocked(not SandboxVars.VehicleEasyUse and ZombRandFloat(0, 1) < ArrowBoard.STOCK.lockedChance)
    door:setLockBroken(false)
end

--- Part `init` of the lid: runs on every side each time the trailer loads.
function ArrowBoard.initLid(vehicle, part)
    showPadlock(part)
    lids[vehicle] = lids[vehicle] or { lid = part }
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

-- OnTick: shows the padlock again on each loaded trailer whose lid has come off, gone on, been
-- locked, unlocked or cut since this game last looked and, but on a dedicated server, swings each
-- lid whose door it has seen open or shut (Lid, above). A lid seen for the first time isn't
-- swung: with no swing playing, the game holds the Opened or Closed pose by the door's state.
-- playPartAnim does nothing while the lid's model isn't loaded or the lid is off.
--
-- Per tick: a few field reads on each trailer this game has loaded, which are few; nothing the
-- game fires reports a door's state or lock changing, so it must look. Allocates nothing.
local function watchLids()
    for vehicle, entry in pairs(lids) do
        if vehicle:isRemovedFromWorld() then
            lids[vehicle] = nil
        else
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
    end
end

Events.OnTick.Add(watchLids)

-- Panels ---------------------------------------------------------------------------------------

local function isPanel(part)
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

-- Puts modules on its panels, as many as the panel rarity option gives, the second maybe cracked.
-- Once per trailer. Authority only.
local function stockPanels(vehicle)
    local modData = vehicle:getModData()
    if modData[ArrowBoard.PANELS_STOCKED] then
        return
    end
    modData[ArrowBoard.PANELS_STOCKED] = true
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

-- OnTick: gives the modules stocked last tick their stock conditions back where something has
-- set them since. Authority only. Per tick it only finds the list empty: no event follows the
-- game's setting the conditions, so the next tick is the first moment after it.
local function keepStockConditions()
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

if not isClient() then
    Events.OnTick.Add(keepStockConditions)
end

--- Part `create` of the panels: runs once for each when the trailer first enters the world.
function ArrowBoard.createPanel(vehicle, part)
    if not isClient() then
        stockPanels(vehicle)
    end
end

--- Part `init` of the panels: runs on every side each time the trailer loads. The trailer's
--- crashes are watched from then on (ArrowBoardCrashes.lua).
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

--- A thunderstorm may crack each panel as it would a flat panel's module (PanelSource.stormCrack), over
--- `stormHours` of storm. Authority only. Returns how many cracked.
function ArrowBoard.stormCrack(vehicle, stormHours)
    local cracked = 0
    for _, part in ipairs(installedPanels(vehicle)) do
        local source = { kind = "flat", modules = { { condition = part:getCondition() } } }
        if RenewableEnergy.PanelSource.stormCrack(source, stormHours) then
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

--- The watts its panels would make in full sun, as the same modules on a mount make.
function ArrowBoard.panelWatts(vehicle)
    local moduleWatts = RenewableEnergy.PowerBank.moduleWatts
    local watts = 0
    for _, part in ipairs(installedPanels(vehicle)) do
        watts = watts + moduleWatts(part:getInventoryItem():getFullType(), part:getCondition())
    end
    return watts
end

--- The trailer's panel `partId` if it holds a module that Seal Cracked Panel can seal, else nil.
function ArrowBoard.repairablePanel(vehicle, partId)
    local part = ArrowBoard.isTrailer(vehicle) and vehicle:getPartById(partId)
    local item = part and isPanel(part) and part:getInventoryItem()
    if item and ArrowBoard.isCracked(part:getCondition()) and RenewableEnergy.Recipes.isModuleBelowRepairCap(item) then
        return part
    end
    return nil
end

--- Seal Cracked Panel: Seal Cracked Module's inputs, skill, XP and effect on a module still
--- on the trailer. Authority only; returns whether it sealed.
function ArrowBoard.repairPanel(character, vehicle, partId)
    local Recipes = RenewableEnergy.Recipes
    local part = ArrowBoard.repairablePanel(vehicle, partId)
    local inputs = part and Recipes.panelRepairRefusal(character) == nil and Recipes.panelRepairInputs(character)
    if not inputs then
        return false
    end
    Recipes.useInputs(inputs, character)
    -- As vanilla's fixPart (VehicleCommands.lua): count the repair on the item, then send it.
    local item = part:getInventoryItem()
    local condition = Recipes.repairedCondition(item)
    item:setHaveBeenRepaired(item:getHaveBeenRepaired() + 1)
    setPanelCondition(vehicle, part, condition)
    vehicle:transmitPartItem(part)
    Recipes.moduleRepairRecipe():addXP(character)
    return true
end

-- Frame ----------------------------------------------------------------------------------------
--
-- The frame's front and back are parts under vanilla's EngineDoor and TruckBed ids, the only ids
-- whose condition the game shows as dents on the body (scripts/RenewableEnergy/Vehicles.txt), so
-- crashes and road kills dent them with no help from here. The lamp board is one more such part
-- (ArrowBoardPower.lua), dented on its own zone. Repair Frame welds them through vanilla's fixing,
-- from the trailer's menu, since the mechanics window doesn't show them.

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

return ArrowBoard
