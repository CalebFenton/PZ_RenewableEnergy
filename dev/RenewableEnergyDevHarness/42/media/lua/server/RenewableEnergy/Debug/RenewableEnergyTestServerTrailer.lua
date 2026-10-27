-- The authority's half of the arrow board tests, and the vehicle state every vehicle test reads:
-- the trailer's panels, box and frame change only where the authority runs them. Only registers
-- handlers, so a --stay rerun loads it again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says
-- how these handlers work. The module's readers serve the client's half too, which requires this
-- file when a test runs, since it loads after client Lua.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
require "PZHarness/Loot"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
local Items = require "cf_commonlib/Items"

local handler = PZHarness.serverHandler
local need, deferOnce, trialRoll = PZHarness.need, PZHarness.Fixtures.deferOnce, Helpers.trialRoll

local Trailer = {}

-- The conditions the panels of trailers spawned with `args.recordStock` got as they were stocked,
-- by vehicle id: { [partId] = condition }.
local stockedPanels = {}

-- Spawns `script` as the harness does (addVehicleDebug), an arrow board's stocked panels getting
-- the condition `roll(stockRoll)` returns for each, stockRoll being the roll stocking makes, in
-- ArrowBoard.PANELS order. No caller hands it a defer, so a pcall puts the rolls back before an
-- error goes on.
local function spawnStocking(script, square, facing, roll)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local weathered, cracked = WorldSpawns.weatheredCondition, WorldSpawns.crackedCondition
    WorldSpawns.weatheredCondition = function() return roll(weathered) end
    WorldSpawns.crackedCondition = function() return roll(cracked) end
    local ok, vehicle = pcall(addVehicleDebug, script, IsoDirections[facing], nil, square)
    WorldSpawns.weatheredCondition, WorldSpawns.crackedCondition = weathered, cracked
    if not ok then
        error(vehicle)
    end
    return vehicle
end

--- T.placeVehicle's spawn, the `spawnVehicle` setting (RenewableEnergyTestSettings.lua): an arrow
--- board through ArrowBoard.spawn when `args.stocked`, as the world spawns one; with
--- `args.recordStock` a plain spawn recording its panels' stock conditions (arrowBoardStock); else
--- the harness's spawn; whole when `args.repair`.
function Trailer.spawnVehicle(script, square, facing, args)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local vehicle
    if args and args.stocked then
        vehicle = ArrowBoard.spawn(square, facing)
    elseif args and args.recordStock then
        local rolled = {}
        vehicle = spawnStocking(script, square, facing, function(stockRoll)
            local condition = stockRoll()
            table.insert(rolled, condition)
            return condition
        end)
        stockedPanels[vehicle:getId()] = { [ArrowBoard.PANELS[1]] = rolled[1], [ArrowBoard.PANELS[2]] = rolled[2] }
    elseif args and args.repair then
        -- The tick after stocking puts the stock conditions back over a repair in the same tick
        -- (ArrowBoard.lua's keepStockConditions), so a whole trailer is stocked whole.
        vehicle = spawnStocking(script, square, facing, function() return 100 end)
    end
    if vehicle and args.repair then
        vehicle:repair()
    end
    return vehicle
end

-- The value of the Java field `name` of `object`, read by reflection (debug only), since nothing
-- exposes a vehicle's model list (BaseVehicle.models) to Lua.
local function fieldValue(object, name)
    local suffix = "%." .. name .. "$"
    for i = 0, getNumClassFields(object) - 1 do
        local field = getClassField(object, i)
        if tostring(field):match(suffix) then
            return getClassFieldVal(object, field)
        end
    end
    return nil
end

-- The entries of the vehicle's model list that draw the part `partId`.
local function partModels(vehicle, partId)
    local part, found = vehicle:getPartById(partId), {}
    local models = fieldValue(vehicle, "models")
    for i = 0, models:size() - 1 do
        local info = models:get(i)
        if fieldValue(info, "part") == part then
            table.insert(found, info)
        end
    end
    return found
end

-- The models a part of `vehicle` shows, sorted and joined with commas.
local function shownModels(vehicle, partId)
    local shown = {}
    for _, info in ipairs(partModels(vehicle, partId)) do
        table.insert(shown, fieldValue(info, "scriptModel"):getId())
    end
    table.sort(shown)
    return table.concat(shown, ",")
end

--- How the lid's model stands in this game, read from its animation track, or nil while the lid
--- shows no model: `clip`, the clip the track plays (nil before the game gives it one), `playing`,
--- whether it is swinging, and `open`, how far open it stands, from 0 shut to 1 open. The clip runs
--- from open to shut, and a reversed track plays it from its end (AnimationTrack.getCurrentTrackTime).
--- A dedicated server draws nothing, so only a client or single player has a track.
function Trailer.lidPose(vehicle)
    local info = partModels(vehicle, RenewableEnergy.ArrowBoard.LID)[1]
    if not info then
        return nil
    end
    local track = fieldValue(info, "track")
    local clip = track and fieldValue(track, "currentClip")
    if not clip then
        return {}
    end
    local duration, time = fieldValue(clip, "duration"), fieldValue(track, "currentTimeValue")
    local at = fieldValue(track, "reverse") and duration - time or time
    return { clip = fieldValue(clip, "name"), playing = fieldValue(track, "isPlaying"),
        open = duration > 0 and 1 - math.min(math.max(at / duration, 0), 1) or nil }
end

-- A part's installed item, its condition and its repair count, or none.
local function partState(vehicle, partId)
    local part = vehicle:getPartById(partId)
    local item = part and part:getInventoryItem()
    return { installed = item ~= nil, type = item and item:getFullType(), condition = item and part:getCondition(),
        repaired = item and item:getHaveBeenRepaired() }
end

--- What the tests read of a vehicle on either side: its battery and whether a maintainer is
--- attached, whether its alternator is out, its colour, and an arrow board's panels' module,
--- condition and shown models, the frame's parts and the lamp board, what the battery box holds,
--- the lid, the switch and the lamps.
function Trailer.vehicleState(vehicle)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local slot = RenewableEnergy.VehicleBattery.partOf(vehicle)
    local battery = slot and slot:getInventoryItem()
    local state = { panels = {}, frame = {}, colorSat = vehicle:getColorSaturation(), colorVal = vehicle:getColorValue(),
        battery = battery and { type = battery:getFullType(), uses = battery:getCurrentUsesFloat() } or nil,
        attached = RenewableEnergy.SolarMaintainer.isAttached(vehicle),
        alternatorOut = RenewableEnergy.CarAlternator.isOut(vehicle) }
    if not ArrowBoard.isTrailer(vehicle) then
        return state
    end
    for _, id in ipairs(ArrowBoard.PANELS) do
        state.panels[id] = partState(vehicle, id)
        state.panels[id].shown = shownModels(vehicle, id)
    end
    for _, frame in ipairs(ArrowBoard.FRAME) do
        state.frame[frame.id] = partState(vehicle, frame.id)
    end
    local box = vehicle:getPartById(ArrowBoard.BATTERY_BOX)
    local container = box and box:getItemContainer()
    if container then
        state.box = { items = Helpers.itemsOf(container) }
    end
    local lid = vehicle:getPartById(ArrowBoard.LID)
    local door = lid and lid:getDoor()
    if door then
        state.lid = { open = door:isOpen(), locked = door:isLocked(), lockBroken = door:isLockBroken(),
            installed = lid:getInventoryItem() ~= nil,
            shown = shownModels(vehicle, ArrowBoard.LID) }
    end
    state.switchOn = ArrowBoard.isSwitchedOn(vehicle)
    state.lamps = box and box:getModData()[ArrowBoard.LAMPS_KEY]
    return state
end

handler("vehicleState", function(_, args)
    return { state = Trailer.vehicleState(Helpers.vehicleAt(args)) }
end)

-- The stock conditions of the panels of a trailer spawned with `args.recordStock`, and its state.
handler("arrowBoardStock", function(_, args)
    local vehicle = Helpers.vehicleAt(args)
    return { stock = need(stockedPanels[vehicle:getId()], "the stock conditions of vehicle " .. tostring(args.id)),
        state = Trailer.vehicleState(vehicle) }
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
    RenewableEnergy.ArrowBoard.showPanel(part)
end

-- Sets up the trailer `args.id` on the authority, in this order: each panel of `args.panels`
-- ({ [partId] = { type, condition, repaired } }, an empty table taking the module off); each frame
-- part and the lamp board of `args.frame` ({ [partId] = condition }); the battery box emptied and
-- filled with `args.box` ({ { type, charge } }) if given; the lid taken off or a new one put on if
-- `args.lidInstalled` is set, open or shut if `args.lidOpen` is, locked or not if `args.lidLocked`
-- is, and its lock cut or whole if `args.lidLockBroken` is; the switch on or off if
-- `args.switchOn` is set, as the switch action does. Answers its state.
handler("setTrailer", function(_, args)
    local ArrowBoard, vehicle = RenewableEnergy.ArrowBoard, Helpers.vehicleAt(args)
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
                RenewableEnergy.Battery.setCharge(item, spec.charge)
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
    return { state = Trailer.vehicleState(vehicle) }
end)

-- ArrowBoard[args.call] on the trailer with the arguments `args.with`, or with the panel
-- `args.part`, as the clock, the switch action or a storm runs it. Answers what it returned, the
-- panels' rating before it, what a flat watt of panel makes in an hour now, and the trailer's
-- state.
handler("arrowBoardRun", function(_, args)
    local ArrowBoard, Sun, vehicle = RenewableEnergy.ArrowBoard, RenewableEnergy.Sun, Helpers.vehicleAt(args)
    local watts = ArrowBoard.panelWatts(vehicle)
    local result = ArrowBoard[args.call](vehicle, unpack(args.part and { vehicle:getPartById(args.part) } or args.with))
    return { result = result, watts = watts, flatWh = Sun.wattsFrom(1, Sun.skyNow().flat), state = Trailer.vehicleState(vehicle) }
end)

-- Rolls the trailer's switch as stocking does for each trial { was, roll }: the switch at `was`
-- (nil for none yet), and the one roll it may draw `roll`, or "under"/"at" for just under or at
-- STOCK.switchedOnChance, worked out here so the roll is exactly the chance. Then puts its own
-- switch back. Answers whether each came out on.
handler("arrowBoardSwitchRolls", function(_, args, defer)
    local ArrowBoard, vehicle = RenewableEnergy.ArrowBoard, Helpers.vehicleAt(args)
    local box = vehicle:getPartById(ArrowBoard.BATTERY_BOX)
    local modData, key = box:getModData(), ArrowBoard.SWITCH_KEY
    local own = modData[key]
    local restore = deferOnce(defer, function()
        modData[key] = own
        vehicle:transmitPartModData(box)
    end)
    local on = Helpers.eachTrial(defer, args.trials, function(trial)
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
    local ArrowBoard, vehicle = RenewableEnergy.ArrowBoard, Helpers.vehicleAt(args)
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
    local first = Trailer.vehicleState(vehicle)
    empty()
    load()
    return { first = first, second = Trailer.vehicleState(vehicle) }
end)

-- The trailer loads as one from a save made before its frame was parts: frame parts empty and the
-- random colour of `args.hsv`, then the frame's init. Answers its state and its script's forced
-- colour.
handler("arrowBoardOldFrame", function(_, args)
    local vehicle = Helpers.vehicleAt(args)
    vehicle:setColorHSV(args.hsv[1], args.hsv[2], args.hsv[3])
    for _, frame in ipairs(RenewableEnergy.ArrowBoard.FRAME) do
        local part = vehicle:getPartById(frame.id)
        part:setInventoryItem(nil)
        RenewableEnergy.ArrowBoard.initFrame(vehicle, part)
    end
    local script = vehicle:getScript()
    return { state = Trailer.vehicleState(vehicle), forcedSat = script:getForcedSat(), forcedVal = script:getForcedVal() }
end)

-- Gives the character a key to the vehicle `args`, which no arrow board ever spawns with, so a
-- test can show what a key holder could do to its lid.
handler("arrowBoardKey", function(player, args)
    return { given = { PZHarness.giveItem(player, Helpers.vehicleAt(args):createVehicleKey()) } }
end)

-- Makes the trailer's lid as its part `create` does (ArrowBoard.createLid) for each trial
-- { was, roll, easyUse }: the lid locked or not as `was`, every roll at `roll` (trialRoll of
-- STOCK.lockedChance) and the game's VehicleEasyUse option at `easyUse`. Then puts the lid and the
-- option back. Answers whether each left the lid locked.
handler("arrowBoardLidRolls", function(_, args, defer)
    local ArrowBoard, vehicle = RenewableEnergy.ArrowBoard, Helpers.vehicleAt(args)
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
    local locked = Helpers.eachTrial(defer, args.trials, function(trial)
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
-- loot option at 1. Answers each panel's condition after each stocking, and WorldSpawns' cracked
-- and weathered ranges.
handler("arrowBoardPanelStockRolls", function(_, args, defer)
    local ArrowBoard, WorldSpawns, vehicle = RenewableEnergy.ArrowBoard, RenewableEnergy.WorldSpawns, Helpers.vehicleAt(args)
    local restoreOptions = PZHarness.Fixtures.saveOptions(defer, { "LRMSolarPanels" })
    SandboxVars.RenewableEnergy.LRMSolarPanels = 1
    local stocked = Helpers.eachTrial(defer, args.rolls, function(roll)
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
    return { stocked = stocked, cracked = WorldSpawns.CRACKED, weathered = WorldSpawns.WEATHERED }
end)

-- Stocks a scratch battery box (ArrowBoard.stockBatteryBox) for each trial { misc, roll }: the
-- Batteries loot option at 0, so no battery draws a roll, the Misc option at `misc`, and every
-- roll at `roll` (trialRoll of STOCK.controllerChance × misc). Answers how many charge controllers
-- each got.
handler("arrowBoardControllerRolls", function(_, args, defer)
    local ArrowBoard, options = RenewableEnergy.ArrowBoard, SandboxVars.RenewableEnergy
    local controller = RenewableEnergy.Specs.controller
    local restoreOptions = PZHarness.Fixtures.saveOptions(defer, { "LRMBatteries", "LRMMisc" })
    options.LRMBatteries = 0
    local container = PZHarness.Loot.scratchContainer(nil)
    local controllers = Helpers.eachTrial(defer, args.trials, function(trial)
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
