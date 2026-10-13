-- The authority's half of the arrow board tests: the trailer's panels, box and frame change only
-- where the authority runs them. Only registers handlers, so a --stay rerun loads it again
-- (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work. The module's
-- readers serve the client's half too, which requires this file when a test runs, since it loads
-- after client Lua.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"

local handler = PZHarness.serverHandler

local Trailer = {}

local vehicleById = PZHarness.Fixtures.vehicleById

-- The conditions the panels of trailers spawned with `args.recordStock` got as they were stocked,
-- by vehicle id: { [partId] = condition }.
local stockedPanels = {}

-- T.placeVehicle's spawn: an arrow board through ArrowBoard.spawn when `args.stocked`, as the world
-- spawns one; with `args.recordStock` the harness's plain addVehicleDebug, recording its panels'
-- stock conditions (arrowBoardStock); else the harness's spawn; whole when `args.repair`.
PZHarness.serverSettings = PZHarness.serverSettings or {}
function PZHarness.serverSettings.spawnVehicle(script, square, facing, args)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local vehicle
    if args and args.stocked then
        vehicle = ArrowBoard.spawn(square, facing)
    elseif args and args.recordStock then
        -- Stocking rolls a condition for each panel in turn, left first.
        local WorldSpawns, rolled = RenewableEnergy.WorldSpawns, {}
        local weathered, cracked = WorldSpawns.weatheredCondition, WorldSpawns.crackedCondition
        local function recording(roll)
            return function()
                local condition = roll()
                table.insert(rolled, condition)
                return condition
            end
        end
        WorldSpawns.weatheredCondition, WorldSpawns.crackedCondition = recording(weathered), recording(cracked)
        vehicle = addVehicleDebug(script, IsoDirections[facing], nil, square)
        WorldSpawns.weatheredCondition, WorldSpawns.crackedCondition = weathered, cracked
        stockedPanels[vehicle:getId()] = { [ArrowBoard.PANELS[1]] = rolled[1], [ArrowBoard.PANELS[2]] = rolled[2] }
    elseif args and args.repair then
        vehicle = addVehicleDebug(script, IsoDirections[facing], nil, square)
    end
    if vehicle and args.repair then
        vehicle:repair()
    end
    return vehicle
end

-- What each panel part shows: the ids of its part models in the vehicle's model list. Read by
-- reflection (debug only), since nothing exposes the list to Lua.
local function fieldValue(object, name)
    for i = 0, getNumClassFields(object) - 1 do
        local field = getClassField(object, i)
        if tostring(field):match("%." .. name .. "$") then
            return getClassFieldVal(object, field)
        end
    end
    return nil
end

--- The models a part of `vehicle` shows, sorted and joined with commas.
function Trailer.shownModels(vehicle, partId)
    local part, shown = vehicle:getPartById(partId), {}
    local models = fieldValue(vehicle, "models")
    for i = 0, models:size() - 1 do
        local info = models:get(i)
        if fieldValue(info, "part") == part then
            table.insert(shown, fieldValue(info, "scriptModel"):getId())
        end
    end
    table.sort(shown)
    return table.concat(shown, ",")
end

-- A part's installed item and its condition, or none.
local function partState(vehicle, partId)
    local part = vehicle:getPartById(partId)
    local item = part and part:getInventoryItem()
    return { installed = item ~= nil, type = item and item:getFullType(), condition = item and part:getCondition() }
end

--- What the tests read of a vehicle on either side: each panel's module, condition and shown
--- models, the frame's parts, what the battery box holds, the lid, the towing car's id and where
--- the vehicle is.
function Trailer.vehicleState(vehicle)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local state = {
        id = vehicle:getId(), x = vehicle:getX(), y = vehicle:getY(), atRest = vehicle:isAtRest(),
        up = vehicle:getUpVectorDot(), panels = {}, frame = {}, blood = {},
        towedBy = vehicle:getVehicleTowedBy() and vehicle:getVehicleTowedBy():getId() or nil,
        colorSat = vehicle:getColorSaturation(), colorVal = vehicle:getColorValue(),
    }
    if not ArrowBoard.isTrailer(vehicle) then
        return state
    end
    for _, id in ipairs(ArrowBoard.PANELS) do
        state.panels[id] = partState(vehicle, id)
        state.panels[id].shown = Trailer.shownModels(vehicle, id)
    end
    for _, frame in ipairs(ArrowBoard.FRAME) do
        state.frame[frame.id] = partState(vehicle, frame.id)
        state.frame[frame.id].category = vehicle:getPartById(frame.id):getCategory()
    end
    for _, side in ipairs({ "Front", "Rear", "Left", "Right" }) do
        state.blood[side] = vehicle:getBloodIntensity(side)
    end
    local box = vehicle:getPartById(ArrowBoard.BATTERY_BOX)
    local container = box and box:getItemContainer()
    if container then
        state.box = { items = {} }
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            table.insert(state.box.items, { type = item:getFullType(), id = item:getID(), condition = item:getCondition(),
                charge = RenewableEnergy.Battery.isBattery(item) and RenewableEnergy.Battery.getCharge(item) or nil })
        end
    end
    local lid = vehicle:getPartById("TrunkDoor")
    local door = lid and lid:getDoor()
    if door then
        state.lid = { open = door:isOpen(), locked = door:isLocked(), installed = lid:getInventoryItem() ~= nil }
    end
    return state
end

-- The vehicle of `args` ({ id, x, y, z }: RenewableEnergyTest.vehicleArgs; single player finds it
-- by the squares around x, y, z), or nil and what is missing.
local function vehicleArg(args)
    local vehicle = vehicleById(args.id, args)
    if not vehicle or vehicle:isRemovedFromWorld() then
        return nil, "vehicle " .. tostring(args.id) .. " on the server"
    end
    return vehicle
end

handler("vehicleState", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    return { state = Trailer.vehicleState(vehicle) }
end)

-- The stock conditions of the panels of a trailer spawned with `args.recordStock`, and its state.
handler("arrowBoardStock", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local stock = stockedPanels[vehicle:getId()]
    if not stock then
        return nil, "the stock conditions of vehicle " .. tostring(args.id)
    end
    return { stock = stock, state = Trailer.vehicleState(vehicle) }
end)

-- Puts a module of spec.type at spec.condition on the panel, or takes it off for a spec without a
-- type, as the mechanics window's install does, and shows it.
local function putPanel(vehicle, partId, spec)
    local part = vehicle:getPartById(partId)
    local item = spec.type and instanceItem(spec.type)
    part:setInventoryItem(item)
    if item then
        part:setCondition(spec.condition)
    end
    vehicle:transmitPartItem(part)
    vehicle:transmitPartCondition(part)
    RenewableEnergy.ArrowBoard.showPanel(part)
end

-- Sets up the trailer `args.id` on the authority, in this order: whole if `args.repair`; each
-- panel of `args.panels` ({ [partId] = { type, condition } }, an empty table taking the module
-- off); each frame part of `args.frame` ({ [partId] = condition }); the battery box emptied and
-- filled with `args.box` ({ { type, charge } }) if given; the blood of `args.blood` ({ [side] =
-- intensity }); the lid open or shut if `args.lidOpen` is set, and locked or not if
-- `args.lidLocked` is. Answers its state.
handler("setTrailer", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local ArrowBoard = RenewableEnergy.ArrowBoard
    if args.repair then
        vehicle:repair()
    end
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
        local items = container:getItems()
        for i = items:size() - 1, 0, -1 do
            local item = items:get(i)
            container:Remove(item)
            sendRemoveItemFromContainer(container, item)
        end
        for _, spec in ipairs(args.box) do
            local item = container:AddItem(spec.type)
            if spec.charge then
                RenewableEnergy.Battery.setCharge(item, spec.charge)
            end
            sendAddItemToContainer(container, item)
        end
    end
    for side, intensity in pairs(args.blood or {}) do
        vehicle:setBloodIntensity(side, intensity)
    end
    local lid = vehicle:getPartById("TrunkDoor")
    if args.lidOpen ~= nil then
        lid:getDoor():setOpen(args.lidOpen)
    end
    if args.lidLocked ~= nil then
        lid:getDoor():setLocked(args.lidLocked)
    end
    if args.lidOpen ~= nil or args.lidLocked ~= nil then
        vehicle:transmitPartDoor(lid)
    end
    return { state = Trailer.vehicleState(vehicle) }
end)

-- `args.hours` of the trailer's panels charging its box at the sun of the moment. Answers the
-- watt-hours stored, the panels' rating, what a flat watt of panel makes in an hour now, and the
-- trailer's state.
handler("arrowBoardCharge", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local watts = ArrowBoard.panelWatts(vehicle)
    local stored = ArrowBoard.charge(vehicle, args.hours)
    return { stored = stored, watts = watts, flatWh = RenewableEnergy.Sun.panelWatts(1, "flat"),
        state = Trailer.vehicleState(vehicle) }
end)

-- A crack on the panel `args.part`. Answers the trailer's state.
handler("arrowBoardCrack", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    RenewableEnergy.ArrowBoard.crackPanel(vehicle, vehicle:getPartById(args.part))
    return { state = Trailer.vehicleState(vehicle) }
end)

-- `args.hours` of thunderstorm over the trailer at the save's storm options. Answers how many
-- panels cracked and the trailer's state.
handler("arrowBoardStorm", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local cracked = RenewableEnergy.ArrowBoard.stormCrack(vehicle, args.hours)
    return { cracked = cracked, state = Trailer.vehicleState(vehicle) }
end)

-- The trailer loads as one from a save made before its panels were parts: empty panels and no
-- record of stocking them, then the panels' init. Then its panels are taken off and it loads
-- again. Answers its state after each load.
handler("arrowBoardOldPanels", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local ArrowBoard = RenewableEnergy.ArrowBoard
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
    vehicle:getModData().RenewableEnergy_panelsStocked = nil
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
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    vehicle:setColorHSV(args.hsv[1], args.hsv[2], args.hsv[3])
    for _, frame in ipairs(RenewableEnergy.ArrowBoard.FRAME) do
        local part = vehicle:getPartById(frame.id)
        part:setInventoryItem(nil)
        RenewableEnergy.ArrowBoard.initFrame(vehicle, part)
    end
    local script = vehicle:getScript()
    return { state = Trailer.vehicleState(vehicle), forcedSat = script:getForcedSat(), forcedVal = script:getForcedVal() }
end)

-- The game's own crash damage on the vehicle: `args.amount`, to the front if `args.front`.
-- Answers its state.
handler("vehicleCrash", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    vehicle:crash(args.amount, args.front)
    return { state = Trailer.vehicleState(vehicle) }
end)

-- The item types each panel takes, then the left panel emptied and the trailer repaired. Answers
-- the types and the trailer's state.
handler("arrowBoardRepairAll", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local types = {}
    for _, id in ipairs(RenewableEnergy.ArrowBoard.PANELS) do
        local list = vehicle:getPartById(id):getItemType()
        types[id] = {}
        for i = 0, list:size() - 1 do
            table.insert(types[id], list:get(i))
        end
    end
    putPanel(vehicle, RenewableEnergy.ArrowBoard.PANELS[1], {})
    vehicle:repair()
    return { types = types, state = Trailer.vehicleState(vehicle) }
end)

-- Turns the car `args.car` and the trailer `args.trailer` (each RenewableEnergyTest.vehicleArgs) square to
-- `args.facing` and puts the trailer's coupler on the car's tow bar
-- (PZHarness.Fixtures.lineUpTrailer), on the authority, which sends the clients their new places.
handler("lineUpTrailer", function(_, args)
    local car, trailer = vehicleArg(args.car), vehicleArg(args.trailer)
    if not (car and trailer) then
        return nil, "the car and the trailer on the server"
    end
    PZHarness.Fixtures.lineUpTrailer(car, trailer, args.facing)
    return {}
end)

return Trailer
