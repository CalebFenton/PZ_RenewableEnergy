-- The authority's half of the arrow board tests: the trailer's panels, box and frame change only
-- where the authority runs them.

require "PZHarness/ServerHandlers"
require "PZHarness/ServerFixtures"
require "PZHarness/Fixtures"
require "PZHarness/Loot"
require "PZHarness/Rolls"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local Items = require "cf_commonlib/Items"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Trailer"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local Finds = require "RenewableEnergy/Items/Finds"
local Specs = require "RenewableEnergy/Specs"
local Sun = require "RenewableEnergy/Sun"
local GadgetCharging = require "RenewableEnergy/Gadgets/GadgetCharging"

local handler = PZHarness.serverHandler
local Rolls = PZHarness.Rolls
local need, deferOnce, trialRoll = PZHarness.need, PZHarness.Fixtures.deferOnce, Rolls.trialRoll
local vehicleState, partState = Kinds.vehicleState, Kinds.partState

local Trailer = {}

-- The conditions the panels of trailers spawned with `args.recordStock` got as they were stocked,
-- by vehicle id: { [partId] = condition }.
local stockedPanels = {}

-- A roll over the second panel's crack chance, so a trailer stocked at it gets two weathered
-- modules; and one that gives weathered modules as good as new.
local WEATHERED_ROLL, WHOLE_ROLL = 0.7, 1 - Rolls.UNDER

-- Spawns `script` as the harness does (addVehicleDebug) with every roll at `roll`, so an arrow
-- board's stocking draws known conditions.
local function spawnAtRoll(defer, script, square, facing, roll)
    return Rolls.with(defer, roll, addVehicleDebug, script, IsoDirections[facing], nil, square)
end

--- T.placeVehicle's spawn, the `spawnVehicle` setting (RenewableEnergyTestSettings.lua).
function Trailer.spawnVehicle(script, square, facing, args, defer)
    local vehicle
    if args and args.stocked then
        vehicle = ArrowBoard.spawn(square, facing)
    elseif args and args.recordStock then
        vehicle = spawnAtRoll(defer, script, square, facing, WEATHERED_ROLL)
        -- The weathered condition stocking gave each module at that roll.
        local condition = Rolls.with(defer, WEATHERED_ROLL, Finds.weatheredCondition)
        stockedPanels[vehicle:getId()] = { [ArrowBoard.PANELS[1]] = condition, [ArrowBoard.PANELS[2]] = condition }
    elseif args and args.repair then
        -- The tick after stocking puts the stock conditions back over a repair in the same tick
        -- (Trailer.lua's keepStockConditions), so a whole trailer is stocked whole.
        vehicle = spawnAtRoll(defer, script, square, facing, WHOLE_ROLL)
    end
    if vehicle and args.repair then
        vehicle:repair()
    end
    return vehicle
end

handler("vehicleState", function(_, args)
    return { state = vehicleState(PZHarness.vehicleAt(args)) }
end)

-- The stock conditions of the panels of a trailer spawned with `args.recordStock`, and its state.
handler("arrowBoardStock", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    return { stock = need(stockedPanels[vehicle:getId()], "the stock conditions of vehicle " .. tostring(args.id)),
        state = vehicleState(vehicle) }
end)

-- Puts a module of spec.type at spec.condition, repaired spec.repaired times, on the panel, or
-- takes it off for a spec without a type, as the mechanics window's install does, and shows it.
local function putPanel(vehicle, partId, spec)
    local part = vehicle:getPartById(partId)
    local item = spec.type and instanceItem(spec.type)
    part:setInventoryItem(item)
    if item then
        item:setHaveBeenRepaired(spec.repaired or 0)
        part:setCondition(spec.condition)
    end
    vehicle:transmitPartItem(part)
    vehicle:transmitPartCondition(part)
    ArrowBoard.showPanel(part)
end

-- Sets up the trailer `args.id` on the authority, in this order: each panel of `args.panels`
-- ({ [partId] = { type, condition, repaired } }, an empty table taking the module off); each frame
-- part and the lamp board of `args.frame` ({ [partId] = condition }); the battery box emptied and
-- filled with `args.box` ({ { type, charge } }) if given; the lid taken off or a new one put on if
-- `args.lidInstalled` is set, open or shut if `args.lidOpen` is, locked or not if `args.lidLocked`
-- is, and its lock cut or whole if `args.lidLockBroken` is; the switch on or off if
-- `args.switchOn` is set, as the switch action does. Answers its state.
handler("setTrailer", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    for partId, spec in pairs(args.panels or {}) do
        putPanel(vehicle, partId, spec)
    end
    for partId, condition in pairs(args.frame or {}) do
        local part = vehicle:getPartById(partId)
        part:setCondition(condition)
        vehicle:transmitPartCondition(part)
    end
    if args.box then
        local container = vehicle:getPartById(ArrowBoard.BATTERY_BOX):getItemContainer()
        Helpers.emptyContainer(container)
        for _, spec in ipairs(args.box) do
            local item = instanceItem(spec.type)
            if spec.charge then
                Battery.setCharge(item, spec.charge)
            end
            Items.addItem(container, item)
        end
    end
    local lid = vehicle:getPartById(ArrowBoard.LID)
    if args.lidInstalled == false then
        lid:setInventoryItem(nil)
        vehicle:transmitPartItem(lid)
    elseif args.lidInstalled then
        VehicleUtils.createPartInventoryItem(lid)
        vehicle:transmitPartItem(lid)
    end
    if args.lidOpen ~= nil then
        lid:getDoor():setOpen(args.lidOpen)
    end
    if args.lidLocked ~= nil then
        lid:getDoor():setLocked(args.lidLocked)
    end
    if args.lidLockBroken ~= nil then
        lid:getDoor():setLockBroken(args.lidLockBroken)
    end
    if args.lidOpen ~= nil or args.lidLocked ~= nil or args.lidLockBroken ~= nil then
        vehicle:transmitPartDoor(lid)
    end
    if args.switchOn ~= nil then
        ArrowBoard.setSwitch(vehicle, args.switchOn)
    end
    return { state = vehicleState(vehicle) }
end)

-- ArrowBoard[args.call] on the trailer with the arguments `args.with`, as the clock, the switch
-- action, a storm or a crash runs it; the charging calls take the sky after them, as the clock's
-- pass gives it. `gadgetPass` runs the clock's own charge pass over every loaded vehicle
-- (GadgetCharging.chargeVehicles) for `args.with[1]` hours instead. Answers what it returned, the
-- panels' rating before it, what a flat watt of panel makes in an hour under that sky, and the
-- trailer's state.
local TAKES_SKY = { charge = true, update = true }
handler("arrowBoardRun", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    local watts = ArrowBoard.panelWatts(vehicle)
    local sky = Sun.skyNow()
    local with = args.with or {}
    if TAKES_SKY[args.call] then
        with = { with[1], sky }
    end
    local result
    if args.call == "gadgetPass" then
        GadgetCharging.chargeVehicles(with[1], sky)
    else
        result = ArrowBoard[args.call](vehicle, unpack(with))
    end
    return { result = result, watts = watts, flatWh = Sun.wattsFrom(1, sky.flat), state = vehicleState(vehicle) }
end)

-- The authority's trailers before a chunk reload trip, by place, so that the one found after it
-- tells whether the authority's chunk went too.
local beforeReload = {}

local function placeKey(at)
    return at.x .. "," .. at.y .. "," .. at.z
end

-- How far from its spawn square a trailer is looked for once its chunk is back.
local RELOAD_SEARCH = 4

-- Notes the trailer `args` names as it stands before its chunk goes.
handler("arrowBoardBeforeReload", function(_, args, defer)
    local key = placeKey(args)
    beforeReload[key] = PZHarness.vehicleAt(args)
    defer(function() beforeReload[key] = nil end)
    return {}
end)

-- The arrow board near `args` once its chunk is back: its id (nil while none stands there yet), its
-- state, and whether it is a new object, loaded from the save. A new one is removed when the test
-- ends, since the fixture's removal takes only the object it placed.
handler("arrowBoardAfterReload", function(_, args, defer)
    local key = placeKey(args)
    for dx = -RELOAD_SEARCH, RELOAD_SEARCH do
        for dy = -RELOAD_SEARCH, RELOAD_SEARCH do
            local square = getSquare(args.x + dx, args.y + dy, args.z)
            local vehicle = square and square:getVehicleContainer()
            if ArrowBoard.isTrailer(vehicle) and not vehicle:isRemovedFromWorld() then
                local fresh = vehicle ~= beforeReload[key]
                if fresh then
                    beforeReload[key] = vehicle
                    defer(function() PZHarness.Fixtures.removePlaced(vehicle) end)
                end
                return { id = vehicle:getId(), fresh = fresh, state = vehicleState(vehicle) }
            end
        end
    end
    return {}
end)

-- Rolls the trailer's switch as stocking does for each trial { was, roll }: the switch at `was`
-- (nil for none yet), and the one roll it may draw `roll`, or "under"/"at" for just under or at
-- STOCK.switchedOnChance, worked out here so the roll is exactly the chance. Then puts its own
-- switch back. Answers whether each came out on.
handler("arrowBoardSwitchRolls", function(_, args, defer)
    local vehicle = PZHarness.vehicleAt(args)
    local box = vehicle:getPartById(ArrowBoard.BATTERY_BOX)
    local modData, key = box:getModData(), ArrowBoard.SWITCH_KEY
    local own = modData[key]
    local restore = deferOnce(defer, function()
        modData[key] = own
        vehicle:transmitPartModData(box)
    end)
    local on = Rolls.eachTrial(defer, args.trials, function(trial)
        return { trialRoll(trial.roll, ArrowBoard.STOCK.switchedOnChance) }
    end, function(trial)
        modData[key] = trial.was
        ArrowBoard.rollSwitch(vehicle)
        return ArrowBoard.isSwitchedOn(vehicle)
    end)
    restore()
    return { on = on }
end)

-- The trailer loads as one from a save made before its panels were parts: empty panels and no
-- record of stocking them, then the panels' init. Then its panels are taken off and it loads
-- again. Answers its state after each load.
handler("arrowBoardOldPanels", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    local function load()
        for _, id in ipairs(ArrowBoard.PANELS) do
            ArrowBoard.initPanel(vehicle, vehicle:getPartById(id))
        end
    end
    local function empty()
        for _, id in ipairs(ArrowBoard.PANELS) do
            putPanel(vehicle, id, {})
        end
    end
    empty()
    vehicle:getModData()[ArrowBoard.PANELS_STOCKED_KEY] = nil
    load()
    local first = vehicleState(vehicle)
    empty()
    load()
    return { first = first, second = vehicleState(vehicle) }
end)

-- The trailer loads as one from a save made before the script forced its colour: the random colour
-- of `args.hsv`, then the frame's init. Answers its state and its script's forced
-- colour.
handler("arrowBoardOldFrame", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    vehicle:setColorHSV(args.hsv[1], args.hsv[2], args.hsv[3])
    for _, frame in ipairs(ArrowBoard.FRAME) do
        ArrowBoard.initFrame(vehicle, vehicle:getPartById(frame.id))
    end
    local script = vehicle:getScript()
    return { state = vehicleState(vehicle), forcedSat = script:getForcedSat(), forcedVal = script:getForcedVal() }
end)

-- Makes the trailer's lid as its part `create` does (ArrowBoard.createLid) for each trial
-- { was, roll, easyUse }: the lid locked or not as `was`, every roll at `roll` (trialRoll of
-- STOCK.lockedChance) and the game's VehicleEasyUse option at `easyUse`. Then puts the lid and the
-- option back. Answers whether each left the lid locked.
handler("arrowBoardLidRolls", function(_, args, defer)
    local vehicle = PZHarness.vehicleAt(args)
    local lid = vehicle:getPartById(ArrowBoard.LID)
    local door = lid:getDoor()
    local wasOpen, wasLocked, wasBroken, easyUse = door:isOpen(), door:isLocked(), door:isLockBroken(), SandboxVars.VehicleEasyUse
    local restore = deferOnce(defer, function()
        SandboxVars.VehicleEasyUse = easyUse
        door:setOpen(wasOpen)
        door:setLocked(wasLocked)
        door:setLockBroken(wasBroken)
        vehicle:transmitPartDoor(lid)
    end)
    local locked = Rolls.eachTrial(defer, args.trials, function(trial)
        return trialRoll(trial.roll, ArrowBoard.STOCK.lockedChance)
    end, function(trial)
        door:setLocked(trial.was)
        SandboxVars.VehicleEasyUse = trial.easyUse == true
        ArrowBoard.createLid(vehicle, lid)
        return door:isLocked()
    end)
    restore()
    return { locked = locked }
end)

-- Stocks the trailer's panels afresh, as its panels' part `create` does on a new trailer, for each
-- of `args.rolls` (trialRoll of STOCK.secondCrackedChance), every roll at it, with the Solar Panels
-- loot option at 1. Answers each panel's condition after each stocking, and Finds' cracked and
-- weathered ranges.
handler("arrowBoardPanelStockRolls", function(_, args, defer)
    local vehicle = PZHarness.vehicleAt(args)
    local restoreOptions = PZHarness.Fixtures.saveOptions(defer, { "LRMSolarPanels" })
    SandboxVars.RenewableEnergy.LRMSolarPanels = 1
    local stocked = Rolls.eachTrial(defer, args.rolls, function(roll)
        return trialRoll(roll, ArrowBoard.STOCK.secondCrackedChance)
    end, function()
        for _, id in ipairs(ArrowBoard.PANELS) do
            putPanel(vehicle, id, {})
        end
        vehicle:getModData()[ArrowBoard.PANELS_STOCKED_KEY] = nil
        ArrowBoard.createPanel(vehicle, vehicle:getPartById(ArrowBoard.PANELS[1]))
        local conditions = {}
        for _, id in ipairs(ArrowBoard.PANELS) do
            conditions[id] = partState(vehicle, id).condition
        end
        return conditions
    end)
    restoreOptions()
    return { stocked = stocked, cracked = Finds.CRACKED, weathered = Finds.WEATHERED }
end)

-- Stocks a scratch battery box (ArrowBoard.stockBatteryBox) for each trial { misc, roll }: the
-- Batteries loot option at 0, so no battery draws a roll, the Misc option at `misc`, and every
-- roll at `roll` (trialRoll of STOCK.controllerChance × misc). Answers how many charge controllers
-- each got.
handler("arrowBoardControllerRolls", function(_, args, defer)
    local options = SandboxVars.RenewableEnergy
    local controller = Specs.controller
    local restoreOptions = PZHarness.Fixtures.saveOptions(defer, { "LRMBatteries", "LRMMisc" })
    options.LRMBatteries = 0
    local container = PZHarness.Loot.scratchContainer(nil)
    local controllers = Rolls.eachTrial(defer, args.trials, function(trial)
        return trialRoll(trial.roll, ArrowBoard.STOCK.controllerChance * trial.misc)
    end, function(trial)
        options.LRMMisc = trial.misc
        ArrowBoard.stockBatteryBox(container)
        local count = container:getCountType(controller)
        container:removeAllItems()
        return count
    end)
    restoreOptions()
    return { controllers = controllers }
end)

return Trailer
