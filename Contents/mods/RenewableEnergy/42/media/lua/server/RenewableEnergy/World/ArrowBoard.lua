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
-- trailer whose panels charge the batteries in a padlocked box on its tongue, which light an
-- arrow on its lamp board. It turns up among junkyard and traffic jam wrecks and at SolarSites'
-- road works. Distributions' OnFillContainer stocks its box when it first spawns, and
-- GadgetCharging's pass charges it and runs its lamps wherever it stands or is towed.
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
    batteries = { min = 4, max = 6 },
    battery = "RenewableEnergy.DeepCycleBattery",
    batteryCondition = { min = 0, max = 80 },
    controllerChance = 0.75,
    lockedChance = 0.75,
    switchedOnChance = 0.9,
}

-- A hard crash: the trailer's velocity changing by at least `kmh` within `ms` of real time, as a
-- car stopping dead against a wall from that speed does. Hard braking sheds about 3 km/h in that
-- time and running over a zombie or a kerb a few, so bumps never crack a panel. The physics spreads
-- a crash over several frames, and a trailer thrown forward jolts again when the hitch brings it up
-- short, half a second or more later, so a jolt is a new crash only after `quietMs` without one.
-- `unhitchedMs` and `unhitchedSquares` cover a crash that snaps the hitch (Crashes, below).
local CRASH = { kmh = 20, ms = 250, quietMs = 2000, unhitchedMs = 1000, unhitchedSquares = 8 }

-- Loaded trailers by vehicle, for watchCrashes: their recent velocities, oldest first, in the
-- lists ms, x and y, used as a ring of SAMPLE_SLOTS from `head`, `count` long, so that watching
-- allocates nothing each frame; when they last jolted (joltedAt); whether they have joined the
-- cell (inCell); on a multiplayer client the car of this game's player that last towed them and
-- until when its crashes still count (car, carUntil).
local tracked = {}
-- Enough for CRASH.ms at a thousand frames a second; at a higher rate the oldest samples go
-- early, which still leaves a crash's jolt well inside the window.
local SAMPLE_SLOTS = 256

local function track(vehicle)
    if not tracked[vehicle] and not isServer() then
        tracked[vehicle] = { ms = {}, x = {}, y = {}, head = 1, count = 0, joltedAt = -math.huge }
    end
end

-- Vehicle modData: its panels have been stocked, at spawn or, on a trailer saved before the panels
-- were parts, at its first load.
local PANELS_STOCKED = "RenewableEnergy_panelsStocked"
-- The client command a driver sends when the trailer they tow crashes.
local COMMAND_MODULE, CRASH_COMMAND = "RenewableEnergyArrowBoard", "crashed"

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
-- (Vehicles.InstallComplete.Door), or Cut Padlock (RenewableEnergyAction, offered by
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

-- The lids each game watches, by vehicle: the lid's item, lock and broken lock it last showed the
-- padlock for, whether it last saw the lid open (nil until it first looks), and on a server when
-- it last took a crash for the trailer (crashTakenAt).
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
    lids[vehicle] = lids[vehicle] or {}
    track(vehicle)
end

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

-- OnTick: gives the modules stocked last tick their stock conditions back where something has
-- set them since. Authority only.
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
    track(vehicle)
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

-- A hard crash cracks every panel with any glass left. Authority only.
local function crashCrack(vehicle)
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
-- crashes and road kills dent them with no help from here. The lamp board is one more such part
-- (Lamps, below), dented on its own zone. Repair Frame welds them through vanilla's fixing, from
-- the trailer's menu, since the mechanics window doesn't show them.

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

-- Crashes --------------------------------------------------------------------------------------
--
-- A crash reaches a towed trailer only as damage to vanilla's part ids (BaseVehicle.crash,
-- addDamageFront/Rear), which the panels aren't, and Lua can't read the trailer's own crash
-- durability. So the game running the trailer's physics watches its velocity: single player every
-- loaded trailer; a multiplayer client the trailer behind the car it drives, asking the server to
-- crack the panels as vanilla's own crash command does. A crash can snap the hitch in the physics
-- step that jolts the trailer (Bullet.onVehicleConstraintImpulse), so that client goes on watching
-- for CRASH.unhitchedMs, and the server takes the crash from the car's driver while the trailer is
-- within CRASH.unhitchedSquares of the car's tow bar.

local function drivenHere(car)
    local driver = car:getDriver()
    return driver ~= nil and instanceof(driver, "IsoPlayer") and driver:isLocalPlayer()
end

-- On a multiplayer client, the car this game's player drives that tows the trailer or towed it a
-- moment ago, whose game runs the trailer's physics; nil if none.
local function carTowingHere(vehicle, entry, now)
    local tow = vehicle:getVehicleTowedBy()
    if tow and drivenHere(tow) then
        entry.car, entry.carUntil = tow, now + CRASH.unhitchedMs
    elseif entry.car and (now > entry.carUntil or tow or not drivenHere(entry.car)) then
        entry.car = nil
    end
    return entry.car
end

local velocity = Vector3f.new()

-- Records the trailer's velocity now and returns whether a new crash began: the velocity changed
-- by a crash's worth within CRASH.ms, CRASH.quietMs after the last jolt.
local function sampleCrash(vehicle, entry, now)
    vehicle:getLinearVelocity(velocity)
    local x, y = velocity:x(), velocity:z()
    local ms, xs, ys = entry.ms, entry.x, entry.y
    while entry.count > 0 and now - ms[entry.head] > CRASH.ms do
        entry.head = entry.head % SAMPLE_SLOTS + 1
        entry.count = entry.count - 1
    end
    local limitMps = CRASH.kmh / 3.6
    local limitSq = limitMps * limitMps
    local jolted, slot = false, entry.head
    for _ = 1, entry.count do
        local dx, dy = x - xs[slot], y - ys[slot]
        if dx * dx + dy * dy >= limitSq then
            jolted = true
            break
        end
        slot = slot % SAMPLE_SLOTS + 1
    end
    slot = (entry.head + entry.count - 1) % SAMPLE_SLOTS + 1
    if entry.count == SAMPLE_SLOTS then
        entry.head = entry.head % SAMPLE_SLOTS + 1
    else
        entry.count = entry.count + 1
    end
    ms[slot], xs[slot], ys[slot] = now, x, y
    if not jolted then
        return false
    end
    local newCrash = now - entry.joltedAt >= CRASH.quietMs
    entry.joltedAt = now
    return newCrash
end

local cell
local function watchCrashes()
    local now = getTimestampMs()
    local client = isClient()
    cell = cell or getCell()
    -- A vehicle joins the cell a frame after it enters the world, so one not yet in it waits. Once
    -- in, it stays until it leaves the world, so the cell's list is searched only until then.
    for vehicle, entry in pairs(tracked) do
        if vehicle:isRemovedFromWorld() then
            tracked[vehicle] = nil
        elseif entry.inCell or cell:getVehicles():contains(vehicle) then
            entry.inCell = true
            local car = client and carTowingHere(vehicle, entry, now)
            if (car or not client) and sampleCrash(vehicle, entry, now) then
                if client then
                    sendClientCommand(getPlayer(), COMMAND_MODULE, CRASH_COMMAND, { vehicle = vehicle:getId(), car = car:getId() })
                else
                    crashCrack(vehicle)
                end
            end
        end
    end
end

-- OnTick: shows the padlock again on each loaded trailer whose lid has come off, gone on, been
-- locked, unlocked or cut since this game last looked and, but on a dedicated server, swings each
-- lid whose door it has seen open or shut (Lid, above). A lid seen for the first time isn't
-- swung: with no swing playing, the game holds the Opened or Closed pose by the door's state.
-- playPartAnim does nothing while the lid's model isn't loaded or the lid is off.
local function watchLids()
    local server = isServer()
    for vehicle, entry in pairs(lids) do
        local lid = vehicle:getPartById(ArrowBoard.LID)
        local door = lid and lid:getDoor()
        if vehicle:isRemovedFromWorld() then
            lids[vehicle] = nil
        elseif door then
            local item, locked, broken = lid:getInventoryItem(), door:isLocked(), door:isLockBroken()
            if item ~= entry.item or locked ~= entry.locked or broken ~= entry.broken then
                showPadlock(lid)
                entry.item, entry.locked, entry.broken = item, locked, broken
            end
            local open = door:isOpen()
            if not server and entry.open ~= nil and open ~= entry.open then
                vehicle:playPartAnim(lid, open and "SwingOpen" or "SwingClose")
            end
            entry.open = open
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
    local squares = CRASH.unhitchedSquares
    return hitch ~= nil and coupler ~= nil and (hitch:x() - coupler:x()) ^ 2 + (hitch:y() - coupler:y()) ^ 2 <= squares * squares
end

-- The server takes a crash only from the driver of the car towing the trailer, or towing it until
-- a moment ago, and only one within CRASH.quietMs: a client's own gate is all that
-- keeps one crash from cracking the panels twice, so the server keeps it too, on the lid's entry.
local function onClientCommand(module, command, player, args)
    if module ~= COMMAND_MODULE or command ~= CRASH_COMMAND or type(args) ~= "table" or type(args.vehicle) ~= "number"
        or type(args.car) ~= "number" then
        return
    end
    local vehicle, car = getVehicleById(args.vehicle), getVehicleById(args.car)
    if not (ArrowBoard.isTrailer(vehicle) and car and car:isDriver(player)
        and (vehicle:getVehicleTowedBy() == car or justUnhitched(vehicle, car))) then
        return
    end
    local now = getTimestampMs()
    local entry = lids[vehicle] or {}
    lids[vehicle] = entry
    if now - (entry.crashTakenAt or -math.huge) >= CRASH.quietMs then
        entry.crashTakenAt = now
        crashCrack(vehicle)
    end
end

if not isServer() then
    Events.OnTick.Add(watchCrashes)
end
Events.OnTick.Add(watchLids)
if not isClient() then
    Events.OnClientCommand.Add(onClientCommand)
    Events.OnTick.Add(keepStockConditions)
end

-- Repair on the trailer ------------------------------------------------------------------------

--- The trailer's panel `partId` if it holds a module that Repair Cracked Panel can mend, else nil.
function ArrowBoard.repairablePanel(vehicle, partId)
    local part = ArrowBoard.isTrailer(vehicle) and vehicle:getPartById(partId)
    local item = part and isPanel(part) and part:getInventoryItem()
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

--- The watts its panels would make in full sun, as the same modules on a mount make.
function ArrowBoard.panelWatts(vehicle)
    local moduleWatts = RenewableEnergy.PowerBank.moduleWatts
    local watts = 0
    for _, part in ipairs(installedPanels(vehicle)) do
        watts = watts + moduleWatts(part:getInventoryItem():getFullType(), part:getCondition())
    end
    return watts
end

-- A battery in the box that can still hold a charge.
local function holdsCharge(item)
    return RenewableEnergy.Battery.nominalWh(item) > 0
end

--- Adds `hours` of its panels' output under `sky` (Sun.skyNow, now if nil) to the batteries in
--- its battery box, the emptiest first, so that a mixed set fills evenly. The panels count as
--- flat, since the trailer may face any way, and make nothing under a roof. Authority only.
--- Returns the watt-hours stored.
---@param vehicle BaseVehicle
function ArrowBoard.charge(vehicle, hours, sky)
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
    local Sun = RenewableEnergy.Sun
    local wh = Sun.wattsFrom(ArrowBoard.panelWatts(vehicle), (sky or Sun.skyNow()).flat, 0) * hours
    local stored = 0
    local battery = wh > 0 and Battery.emptiestIn(container, holdsCharge)
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
        battery = wh > 0 and Battery.emptiestIn(container, holdsCharge)
    end
    return stored
end

-- Lamps ----------------------------------------------------------------------------------------
--
-- The lamps run off the box's batteries through the controller in it: lit day and night while
-- its switch is on, the lamp board isn't beaten to nothing and a battery is above the controller's
-- cutoff, dimmed by the photocell after dark. Once every battery is down to the cutoff they stay
-- off until one is back up at the reconnect level, so a board that barely charges doesn't flicker
-- from pass to pass.
--
-- The authority sets them in the charge pass, and at once when the switch moves, in the battery
-- box part's modData, which the part saves and the server sends its clients (transmitPartModData).
-- Every game that draws the trailer flashes them itself, by the real clock, through the vehicle's
-- windowLightsOn flag, which nothing else sets or sends and which lights the board's zone of the
-- lamps texture each frame it is set (Vehicles.txt). After dark it also gives the board a steady
-- lamppost, since moving a lamppost relights the cell, too dear to do every flash.

-- Battery box part modData: the switch (true on), the lamps as the authority last set them
-- (LAMPS_DAY or LAMPS_NIGHT, nil while dark), and whether the controller has cut them off for flat
-- batteries. The box's discharge cycle of the day, as a bank tracks its own (Bank:trackCycle): the
-- day, the highest charge that day and the deepest discharge from it.
local SWITCH_KEY, LAMPS_KEY, CUT_OFF_KEY = "RenewableEnergy_switchOn", "RenewableEnergy_lamps", "RenewableEnergy_cutOff"
local CYCLE_DAY, CYCLE_HIGH, CYCLE_DEPTH = "RenewableEnergy_cycleDay", "RenewableEnergy_cycleHigh", "RenewableEnergy_cycleDepth"
local LAMPS_DAY, LAMPS_NIGHT = "day", "night"

-- The lamps' amber, halved, since the native lighting doubles a lamp's colour (SolarGardenLight).
local GROUND_LIGHT = { r = 0.5, g = 0.35, b = 0.08 }
-- A battery's charge is kept in whole uses and read back as a 32-bit float, so one set to the
-- cutoff reads back a hair off it; charges this close count as at the cutoff.
local AT_CUTOFF = 1e-6

local function boxOf(vehicle)
    return vehicle:getPartById(ArrowBoard.BATTERY_BOX)
end

--- Whether the controller's switch is on.
function ArrowBoard.isSwitchedOn(vehicle)
    local box = boxOf(vehicle)
    return box ~= nil and box:getModData()[SWITCH_KEY] == true
end

--- The lamps as the authority last set them: "day", "night" (dimmed), or nil while dark.
function ArrowBoard.lamps(vehicle)
    local box = boxOf(vehicle)
    return box and box:getModData()[LAMPS_KEY] or nil
end

-- Whether the lamp board can light: on the trailer, and not beaten to nothing.
local function boardIntact(vehicle)
    local board = vehicle:getPartById(ArrowBoard.BOARD)
    return board ~= nil and board:getInventoryItem() ~= nil and board:getCondition() > 0
end

--- Whether a character at the box can reach the switch: inside the box, so only with the lid open
--- or off, as the padlock means it to be.
function ArrowBoard.switchReachable(vehicle)
    local lid = vehicle:getPartById(ArrowBoard.LID)
    local door = lid and lid:getDoor()
    if not (door and lid:getInventoryItem()) then
        return true
    end
    return door:isOpen()
end

--- Whether the switch can be set to `on`: on an arrow board, reachable, and not there already.
function ArrowBoard.canSwitch(vehicle, on)
    return ArrowBoard.isTrailer(vehicle) and ArrowBoard.switchReachable(vehicle) and ArrowBoard.isSwitchedOn(vehicle) ~= on
end

--- Sets the switch of a trailer that has none yet: on by STOCK.switchedOnChance. Authority only.
function ArrowBoard.rollSwitch(vehicle)
    local box = vehicle and boxOf(vehicle)
    local modData = box and box:getModData()
    if modData and modData[SWITCH_KEY] == nil then
        modData[SWITCH_KEY] = ZombRandFloat(0, 1) < ArrowBoard.STOCK.switchedOnChance
        vehicle:transmitPartModData(box)
    end
end

-- The batteries in the box that hold a charge: the charge of the fullest (-1 for none) and the
-- watt-hours they store and hold when full.
local function batteriesIn(container)
    local Battery = RenewableEnergy.Battery
    local fullest, storedWh, nominalWh = -1, 0, 0
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local wh = Battery.nominalWh(item)
        if wh > 0 then
            local charge = Battery.getCharge(item)
            fullest = math.max(fullest, charge)
            storedWh, nominalWh = storedWh + charge * wh, nominalWh + wh
        end
    end
    return fullest, storedWh, nominalWh
end

-- The fullest battery in the box with charge above `floor`, or nil.
local function fullestAbove(container, floor)
    local Battery = RenewableEnergy.Battery
    local fullest, highest
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if holdsCharge(item) then
            local charge = Battery.getCharge(item)
            if charge > floor + AT_CUTOFF and (not fullest or charge > highest) then
                fullest, highest = item, charge
            end
        end
    end
    return fullest
end

--- The lamps' average draw while they flash, in watts: full by day, dimmed at `night`.
function ArrowBoard.lampWatts(night)
    local spec = Specs.arrowBoard
    return (night and spec.nightWatts or spec.dayWatts) * spec.onShare + spec.offWatts * (1 - spec.onShare)
end

-- Takes `wh` from the batteries in the box, the fullest first, so that a mixed set drains evenly,
-- none below the controller's cutoff. Authority only. Returns the watt-hours taken.
local function drain(container, wh)
    local Battery = RenewableEnergy.Battery
    local cutoff = Specs.arrowBoard.cutoff
    local taken = 0
    local battery = wh > 0 and fullestAbove(container, cutoff)
    while battery do
        local before, nominal = Battery.getCharge(battery), Battery.nominalWh(battery)
        local room = (before - cutoff) * nominal
        local took = math.min(wh, room)
        -- Exactly at the cutoff when it gets there, so the loop moves on to the next battery.
        Battery.setCharge(battery, took == room and cutoff or before - took / nominal)
        if VehicleUtils.compareFloats(before, Battery.getCharge(battery), 2) then
            sendItemStats(battery)
        end
        wh, taken = wh - took, taken + took
        battery = wh > 0 and fullestAbove(container, cutoff)
    end
    return taken
end

-- Wears every battery in the box by one discharge `depth` deep, as a bank wears its own.
local function wearBatteries(container, depth)
    local Battery = RenewableEnergy.Battery
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local spec = Battery.spec(item)
        if spec and Battery.wear(item, Battery.cycleWear(spec, depth) * Battery.wearScale()) then
            sendItemStats(item)
        end
    end
end

-- Follows the box's discharge cycle, and on a new day wears its batteries by the day before's
-- deepest discharge, as a bank does (Bank:trackCycle, Bank:newDay).
local function trackCycle(box, container)
    local _, storedWh, nominalWh = batteriesIn(container)
    if nominalWh <= 0 then
        return
    end
    local charge = storedWh / nominalWh
    local modData = box:getModData()
    local high = math.max(modData[CYCLE_HIGH] or charge, charge)
    local depth = math.max(modData[CYCLE_DEPTH] or 0, high - charge)
    local day = math.floor(getGameTime():getWorldAgeHours() / 24)
    if modData[CYCLE_DAY] ~= day then
        if modData[CYCLE_DAY] and depth > 0 then
            wearBatteries(container, depth)
        end
        modData[CYCLE_DAY] = day
        high, depth = charge, 0
    end
    modData[CYCLE_HIGH], modData[CYCLE_DEPTH] = high, depth
end

-- Sets the lamps by the switch, the board, the batteries and the photocell, which sees dark at
-- `night`, and sends them to the clients when they change.
local function setLamps(vehicle, box, night)
    local spec, modData = Specs.arrowBoard, box:getModData()
    local fullest = batteriesIn(box:getItemContainer())
    if fullest <= spec.cutoff + AT_CUTOFF then
        modData[CUT_OFF_KEY] = true
    elseif fullest >= spec.reconnect then
        modData[CUT_OFF_KEY] = nil
    end
    local lit = modData[SWITCH_KEY] == true and not modData[CUT_OFF_KEY] and boardIntact(vehicle)
    local lamps = lit and (night and LAMPS_NIGHT or LAMPS_DAY) or nil
    if modData[LAMPS_KEY] ~= lamps then
        modData[LAMPS_KEY] = lamps
        vehicle:transmitPartModData(box)
    end
end

-- Whether the photocell sees dark: the sun below the horizon, when a garden light comes on too.
local function isNight()
    return RenewableEnergy.Sun.positionNow().up <= 0
end

--- `hours` of the lamps as they were lit, drawn from the box, then the lamps set again for the
--- switch, the board, the batteries and the photocell (`night`, now if nil) as they are now.
--- Authority only. Returns the watt-hours the lamps drew.
function ArrowBoard.runLamps(vehicle, hours, night)
    local box = boxOf(vehicle)
    local container = box and box:getItemContainer()
    if not container then
        return 0
    end
    local lamps = box:getModData()[LAMPS_KEY]
    local drawn = lamps and drain(container, ArrowBoard.lampWatts(lamps == LAMPS_NIGHT) * hours) or 0
    trackCycle(box, container)
    if night == nil then
        night = isNight()
    end
    setLamps(vehicle, box, night)
    return drawn
end

--- Sets the switch on or off, the lamps following at once. Authority only, from the switch
--- action's complete(). Returns whether it could.
function ArrowBoard.setSwitch(vehicle, on)
    local box = boxOf(vehicle)
    if not (box and box:getItemContainer()) then
        return false
    end
    box:getModData()[SWITCH_KEY] = on
    vehicle:transmitPartModData(box)
    setLamps(vehicle, box, isNight())
    return true
end

--- Whether the flashing lamps are lit at real time `ms`, and how many milliseconds they have been
--- lit or dark.
function ArrowBoard.flashPhase(ms)
    local spec = Specs.arrowBoard
    local period = 60000 / spec.flashesPerMinute
    local into, litFor = ms % period, period * spec.onShare
    if into < litFor then
        return true, into
    end
    return false, into - litFor
end

-- Every loaded trailer this game draws, by vehicle: its battery box part, and while it lights the
-- ground its lamppost and that lamppost's square (x, y, z).
local boards = {}

local function removeGroundLight(entry)
    if entry.light then
        getCell():removeLamppost(entry.light)
        entry.light = nil
    end
end

-- Gives the board a lamppost on the trailer's square, moved only when the trailer moves to another.
local function placeGroundLight(entry, vehicle)
    local x, y, z = math.floor(vehicle:getX()), math.floor(vehicle:getY()), math.floor(vehicle:getZ())
    if entry.light and entry.x == x and entry.y == y and entry.z == z then
        return
    end
    removeGroundLight(entry)
    entry.light = getCell():addLamppost(x, y, z, GROUND_LIGHT.r, GROUND_LIGHT.g, GROUND_LIGHT.b, Specs.arrowBoard.radius)
    entry.x, entry.y, entry.z = x, y, z
end

-- OnTick, but on a dedicated server: flashes the lamps of every loaded trailer that is lit, and
-- lights the ground around those dimmed for the night. Allocates nothing unless a lamppost moves.
local function flashLamps()
    local flashLit = ArrowBoard.flashPhase(getTimestampMs())
    for vehicle, entry in pairs(boards) do
        if vehicle:isRemovedFromWorld() then
            removeGroundLight(entry)
            boards[vehicle] = nil
        else
            entry.box = entry.box or boxOf(vehicle)
            local lamps = entry.box and entry.box:getModData()[LAMPS_KEY]
            local show = lamps ~= nil and flashLit
            if vehicle:getWindowLightsOn() ~= show then
                vehicle:setWindowLightsOn(show)
            end
            if lamps == LAMPS_NIGHT then
                placeGroundLight(entry, vehicle)
            else
                removeGroundLight(entry)
            end
        end
    end
end

--- Part `init` of the lamp board: runs on every side each time the trailer loads. A trailer saved
--- before it had the board and the switch gets them here.
function ArrowBoard.initBoard(vehicle, part)
    ArrowBoard.initFrame(vehicle, part)
    if not isClient() then
        ArrowBoard.rollSwitch(vehicle)
    end
    if not isServer() then
        boards[vehicle] = boards[vehicle] or {}
    end
end

if not isServer() then
    Events.OnTick.Add(flashLamps)
end

--- The charge pass for one loaded vehicle under `sky` (Sun.skyNow, now if nil): if it is an
--- arrow board, storms may crack its panels, its panels show what they hold, they charge its box
--- and its lamps draw from it. Authority only. Returns the watt-hours its panels stored.
function ArrowBoard.update(vehicle, hours, sky)
    if not ArrowBoard.isTrailer(vehicle) then
        return 0
    end
    sky = sky or RenewableEnergy.Sun.skyNow()
    ArrowBoard.stormCrack(vehicle, RenewableEnergy.Bank.stormHours(hours))
    ArrowBoard.showPanels(vehicle)
    local stored = ArrowBoard.charge(vehicle, hours, sky)
    ArrowBoard.runLamps(vehicle, hours, sky.up <= 0)
    return stored
end

return ArrowBoard
