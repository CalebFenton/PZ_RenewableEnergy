-- What the client test libraries and the server handlers both know of the mod's things. The mod's
-- server modules load after shared Lua, and only on the authority, so the readers that need one
-- require it when they run.

require "PZHarness/Fixtures"
local Squares = require "cf_commonlib/Squares"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Trailer"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local CarAlternator = require "RenewableEnergy/Gadgets/CarAlternator"
local Digester = require "RenewableEnergy/Biogas/Digester"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local SolarCellCharger = require "RenewableEnergy/Gadgets/SolarCellCharger"
local SolarMaintainer = require "RenewableEnergy/Gadgets/SolarMaintainer"
local Sprites = require "RenewableEnergy/Sprites"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"

local Kinds = {}
local Fixtures = PZHarness.Fixtures

--- How many keys `entries` holds; 0 for nil.
function Kinds.count(entries)
    local n = 0
    for _ in pairs(entries or {}) do
        n = n + 1
    end
    return n
end

--- Whether `value` lies in `range` ({ min, max }), both ends included.
function Kinds.inRange(value, range)
    return value >= range.min and value <= range.max
end

--- The conditions the WorldSpawns wear profile `wear` gives a find, from its lowest roll to its
--- highest: no better than new.
function Kinds.wearRange(wear)
    return { min = wear.mean - wear.halfWidth, max = math.min(100, wear.mean + wear.halfWidth) }
end

--- The items in `container` (nil for none) as plain values, in container order: { type, id,
--- condition, uses, charge (a battery's) }.
function Kinds.itemsOf(container)
    local list = {}
    local items = container and container:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        local item = items:get(i)
        table.insert(list, { type = item:getFullType(), id = item:getID(), condition = item:getCondition(),
            uses = item:getCurrentUsesFloat(), charge = Battery.isBattery(item) and Battery.getCharge(item) or nil })
    end
    return list
end

-- Kinds of object a handler finds that are no job feature's target (RenewableEnergyAction.targetOn
-- finds those by their feature's name).
local FIND = {
    charger = SolarCellCharger.isCharger,
    wiredTreadmill = Treadmill.isWiredTile,
    generator = GeneratorReach.isVanillaGenerator,
}

--- The object on the square at `at` ({ x, y, z }) drawn as `at.sprite`, else of the kind `at.kind`:
--- a FIND kind or a job feature (RenewableEnergyAction.targetOn); nil, also while the square isn't
--- loaded.
function Kinds.findOn(at)
    local square = Fixtures.squareAt(at)
    if at.sprite then
        return Fixtures.objectWithSprite(square, at.sprite)
    elseif FIND[at.kind] then
        return Squares.findObjectOn(square, FIND[at.kind])
    end
    return square and RenewableEnergyAction.targetOn(at.kind, square)
end

--- Kinds.findOn's object, or the running server handler ends as missing it.
function Kinds.find(at)
    return PZHarness.need(Kinds.findOn(at), "a " .. tostring(at.sprite or at.kind) .. " at " .. tostring(at.x) .. ","
        .. tostring(at.y) .. "," .. tostring(at.z) .. " on the server")
end

-- Builds a `kind` on the Sprites[kind] tile `tile` (a dotted path: "barrel.MetalDrum",
-- "standard") on `square` as the build menu does, through the builder rural finds use
-- (Place.entity), which sends it to the clients, with the kind's system's OnCreate.
local function buildEntity(kind, systemPath)
    return function(square, tile)
        local sprite = Sprites[kind]
        for part in string.gmatch(tile, "[^.]+") do
            sprite = sprite and sprite[part]
        end
        PZHarness.need(type(sprite) == "string", "the " .. kind .. " tile " .. tostring(tile))
        local Place = require "RenewableEnergy/World/Place"
        return Place.entity(square, sprite, require(systemPath).OnCreate)
    end
end

local function addToxic(object, state)
    local building = object:getSquare():getBuilding()
    state.toxic = building ~= nil and building:isToxic()
end

--- The record kinds of the harness's record kit (the `records` test setting).
Kinds.RECORDS = {
    digester = {
        owner = function() return Digester end,
        build = buildEntity("digester", "RenewableEnergy/Biogas/DigesterSystem"),
        containers = function(object) return { hopper = object:getContainer() } end,
        -- The air its square has now; the stink's ghosts, which only these reads use
        -- (Stink.counted), since the game's corpse count is out of Lua's reach.
        extras = function(record, object, state)
            state.capacity = record:capacity()
            state.torn = record:isTorn()
            state.ghosts = require("RenewableEnergy/Biogas/Stink").counted(record:key())
            state.eaten = Kinds.count(record.eaten)
            state.snapshot = #record.hopper
            if object then
                addToxic(object, state)
                state.containerCapacity = object:getContainer():getCapacity()
                state.hopperItems = object:getContainer():getItems():size()
                state.air = getClimateManager():getAirTemperatureForSquare(object:getSquare())
            end
        end,
    },
    gasifier = {
        owner = function() return Gasifier end,
        build = buildEntity("gasifier", "RenewableEnergy/WoodGas/GasifierSystem"),
        containers = function(object) return { hopper = Gasifier.hopperOf(object), filter = Gasifier.filterOf(object) } end,
        extras = function(_, object, state)
            if object then
                addToxic(object, state)
                state.hopperKg = Gasifier.hopperKg(Gasifier.hopperOf(object))
                state.containers = object:getContainerCount()
                state.clean, state.tarry = Gasifier.filterCounts(Gasifier.filterOf(object))
            end
        end,
    },
    -- Placed with its parts by the bank handlers' placeBank.
    bank = {
        owner = function() return PowerBank end,
        extras = function(record, bank, state)
            local square = bank and bank:getSquare()
            -- What the status doesn't show of each source's record.
            local records = {}
            for _, source in ipairs(record.sources) do
                table.insert(records,
                    { x = source.x, y = source.y, z = source.z, kind = source.kind, blades = source.blades })
            end
            state.on, state.name, state.overloaded = record.on == true, record.name or "", record.overloaded == true
            state.age, state.calendarDay = getGameTime():getWorldAgeHours(), getGameTime():getDay()
            state.storedWh = record.charge * record.nominalWh
            state.limitW, state.drawW, state.chargerMaxW = record:limitW(), record:drawW(), record:chargerMaxW()
            state.sources, state.batteries, state.records = #record.sources, #record.batteries, records
            state.activated = bank ~= nil and bank:isActivated()
            state.powered = square ~= nil and square:haveElectricity()
            state.items = Kinds.itemsOf(bank and bank:getContainer())
            state.overlays = Fixtures.overlaysOf(bank)
            state.status = record:buildStatus()
            state.watchers = Kinds.count(record.watchers)
        end,
    },
}

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
function Kinds.lidPose(vehicle)
    local info = partModels(vehicle, ArrowBoard.LID)[1]
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

--- A part's installed item, its condition and its repair count, or none.
function Kinds.partState(vehicle, partId)
    local part = vehicle:getPartById(partId)
    local item = part and part:getInventoryItem()
    return { installed = item ~= nil, type = item and item:getFullType(), condition = item and part:getCondition(),
        repaired = item and item:getHaveBeenRepaired() }
end

--- What the tests read of a vehicle on either side: its battery and whether a maintainer is
--- attached, whether its alternator is out, its colour, and an arrow board's panels' module,
--- condition and shown models, the frame's parts and the lamp board, what the battery box holds,
--- the lid, the switch and the lamps.
function Kinds.vehicleState(vehicle)
    local slot = VehicleBattery.partOf(vehicle)
    local battery = slot and slot:getInventoryItem()
    local state = { panels = {}, frame = {}, colorSat = vehicle:getColorSaturation(), colorVal = vehicle:getColorValue(),
        battery = battery and { type = battery:getFullType(), uses = battery:getCurrentUsesFloat() } or nil,
        attached = SolarMaintainer.isAttached(vehicle),
        alternatorOut = CarAlternator.isOut(vehicle) }
    if not ArrowBoard.isTrailer(vehicle) then
        return state
    end
    for _, id in ipairs(ArrowBoard.PANELS) do
        state.panels[id] = Kinds.partState(vehicle, id)
        state.panels[id].shown = shownModels(vehicle, id)
    end
    for _, frame in ipairs(ArrowBoard.FRAME) do
        state.frame[frame.id] = Kinds.partState(vehicle, frame.id)
    end
    local box = vehicle:getPartById(ArrowBoard.BATTERY_BOX)
    local container = box and box:getItemContainer()
    if container then
        state.box = { items = Kinds.itemsOf(container) }
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

return Kinds
