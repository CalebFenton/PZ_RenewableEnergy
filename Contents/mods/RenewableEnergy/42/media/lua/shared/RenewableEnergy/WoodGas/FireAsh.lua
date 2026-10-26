-- Wood Ash from vanilla's wood fires: campfires, fireplaces, wood stoves and charcoal grills, not
-- propane grills. Each keeps on its tile the minutes of fuel put in it that haven't yet been
-- cleaned out as ash; what of those has burned, beyond what is still in it, gives Clean Out Ash
-- a Wood Ash per MINUTES_PER_ASH. Vanilla's two Add Fuel actions count the fuel on the authority.

require "Camping/TimedActions/ISAddFuelAction"
require "TimedActions/ISBBQAddFuel"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local GasifierJobs = require "RenewableEnergy/WoodGas/GasifierJobs"
local Items = require "cf_commonlib/Items"
local Jobs = require "cf_commonlib/Jobs"

local FireAsh = {}

FireAsh.CLEAN_ASH = GasifierJobs.CLEAN_ASH
-- One Wood Ash per this many minutes of fuel burned, an hour of fire: about 1.5 kg of wood, as
-- vanilla burns a kg in 40 minutes (ISCampingMenu's DefaultBurnRatio), near what leaves one in a
-- gasifier's pit.
FireAsh.MINUTES_PER_ASH = 60
local FUEL_KEY = "RenewableEnergy_ashFuel"

-- A vanilla campfire's tile, by vanilla's own test (CCampfireSystem.isValidIsoObject).
local function isCampfire(object)
    return object:getName() == "Campfire"
end

--- Whether `object` is a vanilla fire that burns wood.
function FireAsh.isFire(object)
    return isCampfire(object) or object:isFireInteractionObject() and not object:isPropaneBBQ()
end

-- Minutes of fuel left in the fire `object`. A campfire's tile carries its campfire's state.
local function fuelLeft(object)
    if isCampfire(object) then
        return object:getModData().fuelAmt or 0
    end
    return object:getFuelAmount()
end

--- The Wood Ash the fire `object` has to clean out.
function FireAsh.ashItems(object)
    local burned = (object:getModData()[FUEL_KEY] or 0) - fuelLeft(object)
    return math.max(0, math.floor(burned / FireAsh.MINUTES_PER_ASH))
end

-- `minutes` of fuel went into the fire `object`. Fuel that was in it uncounted, from before this
-- mod or the world's own, burns to ash too.
local function fed(object, minutes)
    local modData = object:getModData()
    modData[FUEL_KEY] = math.max((modData[FUEL_KEY] or 0) + minutes, fuelLeft(object))
    object:transmitModData()
end

--- Clean Out Ash at the fire `fire`: `character` gets its Wood Ash. Returns true, as it's done.
function FireAsh.cleanOut(character, fire)
    local count = FireAsh.ashItems(fire)
    Items.giveItems(character, Gasifier.WOOD_ASH, count)
    local modData = fire:getModData()
    modData[FUEL_KEY] = modData[FUEL_KEY] - count * FireAsh.MINUTES_PER_ASH
    fire:transmitModData()
    return true
end

FireAsh.JOBS = {
    [FireAsh.CLEAN_ASH] = GasifierJobs.cleanAshRow(FireAsh.ashItems),
}

Jobs.define(FireAsh, {
    subjectOf = function(fire) return FireAsh.isFire(fire) and fire or nil end, missing = "no fire",
})

local vanillaCampfireComplete = ISAddFuelAction.complete
function ISAddFuelAction:complete()
    local done = vanillaCampfireComplete(self)
    local campfire = SCampfireSystem.instance:getLuaObjectAt(self.campfire.x, self.campfire.y, self.campfire.z)
    local object = campfire and campfire:getIsoObject()
    if object then
        fed(object, self.fuelAmt)
    end
    return done
end

local vanillaFireComplete = ISBBQAddFuel.complete
function ISBBQAddFuel:complete()
    local done = vanillaFireComplete(self)
    if self.fireplace then
        fed(self.fireplace, self.fuelAmt)
    end
    return done
end

return FireAsh
