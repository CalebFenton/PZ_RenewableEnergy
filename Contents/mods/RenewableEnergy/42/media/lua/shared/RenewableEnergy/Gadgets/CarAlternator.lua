-- The Car Alternator: the generator of the car alternator wind charger, taken out of a car or cut
-- from a smashed wreck.
--
-- Vanilla cars have no alternator part, so a car's alternator being out is a mark in the modData
-- of its Engine part, which every car has and a trailer lacks. vehicle:transmitPartModData sends
-- that to multiplayer clients, and the part saves it with the vehicle; the vehicle's own modData
-- has no such send (DEVELOPMENT.md, Vehicles). Taking it out, putting it back and the wreck's drop
-- are the authority's: server/RenewableEnergy/Gadgets/CarAlternatorServer.lua.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Gadgets/VehicleBattery"
local Materials = require "cf_commonlib/Materials"

RenewableEnergy = RenewableEnergy or {}
local CarAlternator = {}
RenewableEnergy.CarAlternator = CarAlternator

CarAlternator.ITEM = "RenewableEnergy.CarAlternator"
CarAlternator.ENGINE = "Engine"
CarAlternator.HOOD = "EngineDoor"

-- Engine part modData: set while the car's alternator is out.
CarAlternator.OUT_KEY = "RenewableEnergy_AlternatorOut"
-- Engine part modData: set once taking the alternator out of this car has taught Mechanics, so
-- taking it out and putting it back over and over teaches nothing more.
CarAlternator.XP_KEY = "RenewableEnergy_AlternatorXp"

-- What the job takes, as materials (cf_commonlib's Materials). An alternator hangs on two bolts
-- and a belt tensioner: a wrench, and a little more skill than the battery's screwdriver.
local SKILL = { perk = "Mechanics", need = 2 }
local WRENCH = { tool = "WRENCH", item = "Base.Wrench" }
local TAKE_OUT = { SKILL, WRENCH }
local PUT_BACK = { SKILL, WRENCH, { item = CarAlternator.ITEM, need = 1, keep = true } }

-- Action units at Mechanics 0: as long as vanilla's Take Engine Parts, the other job inside the
-- engine bay (ISVehicleMechanics.onTakeEngineParts).
local WORK_UNITS = 300
-- Mechanics XP the first time: the least vanilla gives for taking out a part whose uninstall asks
-- the same skill level (IsoPlayer.addMechanicsItem).
CarAlternator.XP = 4

local function hasText(name, text)
    return string.find(name, text, 1, true) ~= nil
end

local function scriptName(vehicle)
    return vehicle:getScript():getName()
end

--- Whether `vehicle` is a wreck vanilla scraps with a blowtorch: its script's name holds "Burnt"
--- or "Smashed", as ISVehicleMenu.FillMenuOutsideVehicle tests it to offer the scrap.
function CarAlternator.isWreck(vehicle)
    local name = scriptName(vehicle)
    return hasText(name, "Burnt") or hasText(name, "Smashed")
end

--- Whether `vehicle` is a smashed wreck that wasn't burnt: fire cooks an alternator's windings, a
--- crash leaves them.
function CarAlternator.isSmashedWreck(vehicle)
    local name = scriptName(vehicle)
    return hasText(name, "Smashed") and not hasText(name, "Burnt")
end

--- The Engine part of `vehicle`, or nil for no vehicle or one without an engine.
function CarAlternator.enginePart(vehicle)
    return vehicle and vehicle:getPartById(CarAlternator.ENGINE)
end

--- Whether `vehicle` is an intact vehicle in the world with an engine and a battery to charge,
--- the kind whose alternator can come out. Smashed wrecks keep their template's engine and
--- battery parts, so the script name rules them out.
function CarAlternator.isCar(vehicle)
    return vehicle ~= nil and not vehicle:isRemovedFromWorld() and CarAlternator.enginePart(vehicle) ~= nil
        and RenewableEnergy.VehicleBattery.partOf(vehicle) ~= nil and not CarAlternator.isWreck(vehicle)
end

--- Whether `vehicle`'s alternator has been taken out.
function CarAlternator.isOut(vehicle)
    local engine = CarAlternator.enginePart(vehicle)
    return engine ~= nil and engine:getModData()[CarAlternator.OUT_KEY] ~= nil
end

--- Whether the engine bay is open to work in: the hood open, off or not there at all.
function CarAlternator.hoodOpen(vehicle)
    return RenewableEnergy.isPartOpen(vehicle, CarAlternator.HOOD)
end

--- The hood part that has to be opened before the job, or nil when the bay is open.
function CarAlternator.shutHood(vehicle)
    if CarAlternator.hoodOpen(vehicle) then
        return nil
    end
    return vehicle:getPartById(CarAlternator.HOOD)
end

--- What taking the alternator out (`putBack` false) or putting one back takes of `character`,
--- for Materials.firstUnmet and cf_commonlib's Needs.
function CarAlternator.needs(character, putBack)
    return Materials.needs(character, putBack and PUT_BACK or TAKE_OUT)
end

--- What keeps `character` from taking the alternator out of `vehicle` (or putting one back) now
--- whatever they carry, as a translation key, or nil. A shut hood isn't one: the menu opens it
--- first, as vanilla's engine jobs do.
function CarAlternator.blocker(character, vehicle, putBack)
    if not CarAlternator.isCar(vehicle) then
        return "Tooltip_RenewableEnergy_NotACar"
    elseif putBack and not CarAlternator.isOut(vehicle) then
        return "Tooltip_RenewableEnergy_AlternatorFitted"
    elseif not putBack and CarAlternator.isOut(vehicle) then
        return "Tooltip_RenewableEnergy_AlternatorGone"
    elseif vehicle:isEngineStarted() or vehicle:isEngineRunning() then
        -- As vanilla refuses the battery (Vehicles.UninstallTest.Battery).
        return "Tooltip_RenewableEnergy_EngineRunning"
    elseif ISVehicleMechanics and VehicleUtils.RequiredKeyNotFound(CarAlternator.enginePart(vehicle), character) then
        -- As vanilla's engine jobs (ISVehicleMechanics.doPartContextMenu). The check reads the
        -- mechanics window's cheat, which a dedicated server never loads; vanilla checks a part
        -- job's key only on the player's side too (ISUninstallVehiclePart.isValid).
        return "Tooltip_vehicle_keyRequired"
    end
    return nil
end

--- Why `character` can't do the job on `vehicle` now, or nil if they can: the blocker, a shut
--- hood, or the kind of the first need they are short of.
function CarAlternator.refusal(character, vehicle, putBack)
    local blocker = CarAlternator.blocker(character, vehicle, putBack)
    if blocker then
        return blocker
    elseif not CarAlternator.hoodOpen(vehicle) then
        return "Tooltip_RenewableEnergy_HoodShut"
    end
    return Materials.unmetKind(CarAlternator.needs(character, putBack))
end

--- The job's length in action units for `character`: less with Mechanics, as a part's uninstall
--- is (ISUninstallVehiclePart.getDuration).
function CarAlternator.units(character)
    return WORK_UNITS - character:getPerkLevel(Perks.Mechanics) * WORK_UNITS / 15
end

-- Vanilla's scrap of a wreck (ISRemoveBurntVehicle:complete) runs a round per Metalworking level,
-- never fewer than its floor, and in each round rolls Engine Parts twice, each a 1 in (its base
-- less the lower of Mechanics and Metalworking) (checkAddItem). The names give each figure's place.
local SCRAP_MIN_ROUNDS = 5
local ENGINE_PARTS_PER_ROUND = 2
local ENGINE_PARTS_BASE = 25

--- The chance a smashed wreck scrapped at `mechanics` and `metalworking` gives its alternator:
--- that of at least one Engine Parts from the same scrap.
function CarAlternator.scrapChance(mechanics, metalworking)
    local rolls = ENGINE_PARTS_PER_ROUND * math.max(SCRAP_MIN_ROUNDS, metalworking)
    local each = 1 / (ENGINE_PARTS_BASE - math.min(mechanics, metalworking))
    return 1 - (1 - each) ^ rolls
end

return CarAlternator
