-- The Car Alternator on the authority: taking it out of a car and putting it back, from a timed
-- action's complete(), and the one a smashed wreck may give when it is scrapped.

if isClient() then return end

require "Vehicles/TimedActions/ISRemoveBurntVehicle"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Chance"
require "RenewableEnergy/Gadgets/CarAlternator"
local Items = require "cf_commonlib/Items"

local CarAlternator, Chance = RenewableEnergy.CarAlternator, RenewableEnergy.Chance

--- Takes the alternator out of `vehicle` and gives it to `character`, teaching Mechanics the
--- first time this car's comes out. Returns whether it did.
function CarAlternator.takeOut(character, vehicle)
    local engine = CarAlternator.enginePart(vehicle)
    if not engine or CarAlternator.isOut(vehicle) then
        return false
    end
    engine:getModData()[CarAlternator.OUT_KEY] = true
    RenewableEnergy.teachOnce(character, engine, CarAlternator.XP_KEY, Perks.Mechanics, CarAlternator.XP)
    vehicle:transmitPartModData(engine)
    Items.giveItems(character, CarAlternator.ITEM)
    return true
end

--- Takes `item` from `character` and bolts it into `vehicle` in place of its missing alternator.
--- Returns whether it did.
function CarAlternator.putBack(character, vehicle, item)
    local engine = CarAlternator.enginePart(vehicle)
    if not (engine and item and item:getFullType() == CarAlternator.ITEM and CarAlternator.isOut(vehicle)) then
        return false
    end
    Items.takeItem(character, item)
    engine:getModData()[CarAlternator.OUT_KEY] = nil
    vehicle:transmitPartModData(engine)
    return true
end

local vanillaScrapComplete = ISRemoveBurntVehicle.complete

-- A smashed wreck's alternator comes off with its engine parts, so scrapping one may also drop it
-- on the wreck's square, as vanilla drops the rest, with the Metalworking XP vanilla gives for
-- each item. Vanilla runs complete() on the authority, so this runs there too. The skills are read
-- before vanilla's complete(), whose XP could raise them, as its own rolls read them before it.
function ISRemoveBurntVehicle:complete()
    local vehicle, character = self.vehicle, self.character
    local square = vehicle and vehicle:getSquare()
    local smashed = square ~= nil and CarAlternator.isSmashedWreck(vehicle) and not CarAlternator.isOut(vehicle)
    local chance = smashed and CarAlternator.scrapChance(character:getPerkLevel(Perks.Mechanics),
        character:getPerkLevel(Perks.MetalWelding))
    local done = vanillaScrapComplete(self)
    if not (done and smashed) then
        return done
    end
    if Chance.hit(chance) then
        Items.dropOn(square, CarAlternator.ITEM)
        addXp(character, Perks.MetalWelding, 1)
    end
    return done
end
