-- Setup helpers for the debug scenario, the tests and the dev harness. Debug mode only.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/PowerBank/PowerBank"

RenewableEnergy = RenewableEnergy or {}
local Debug = {}
RenewableEnergy.Debug = Debug

-- Every item this mod defines, in the order the README shows them.
Debug.ITEMS = {
    "RenewableEnergy.SolarModule", "RenewableEnergy.HomemadeSolarModule", "RenewableEnergy.SolarCells",
    "RenewableEnergy.SolarFlat", "RenewableEnergy.SolarWallWood", "RenewableEnergy.SolarWallMetal",
    "RenewableEnergy.SolarRackWood", "RenewableEnergy.SolarRackMetal",
    "RenewableEnergy.BatteryBoxWood", "RenewableEnergy.BatteryBoxMetal",
    "RenewableEnergy.BatteryRackWood", "RenewableEnergy.BatteryRackMetal",
    "RenewableEnergy.BatteryBankWood", "RenewableEnergy.BatteryBankMetal",
    "RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter", "RenewableEnergy.InverterCharger",
    "RenewableEnergy.ChargeController", "RenewableEnergy.SolarFailsafe",
    "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery",
    "RenewableEnergy.CarBatteryCase", "RenewableEnergy.DeepCycleBatteryCase", "RenewableEnergy.L16BatteryCase",
    "RenewableEnergy.WornBatteryPlates", "RenewableEnergy.BatteryPlates", "RenewableEnergy.WoodenBatteryPlatePattern",
    "RenewableEnergy.BatteryPlateMoldUnfired", "RenewableEnergy.BatteryPlateMold", "RenewableEnergy.BatteryElectrolyte",
    "RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger", "RenewableEnergy.SolarGardenLight",
    "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2",
    "RenewableEnergy.CrowcallRoadMap", "RenewableEnergy.DixieTrailerParkMap",
}

local RECIPE_PREFIX = "RenewableEnergy_"

-- Every craftRecipe of this mod, by the prefix they all share in module Base.
function Debug.recipeNames()
    local names = {}
    local recipes = getScriptManager():getAllCraftRecipes()
    for i = 0, recipes:size() - 1 do
        local name = recipes:get(i):getName()
        if string.sub(name, 1, #RECIPE_PREFIX) == RECIPE_PREFIX then
            table.insert(names, name)
        end
    end
    return names
end

function Debug.learnRecipes(player)
    for _, name in ipairs(Debug.recipeNames()) do
        player:learnRecipe(name)
    end
end

function Debug.forgetRecipes(player)
    for _, name in ipairs(Debug.recipeNames()) do
        player:getKnownRecipes():remove(name)
    end
end

local function pickInputItem(possible, prefer)
    for _, wanted in ipairs(prefer or {}) do
        for j = 0, possible:size() - 1 do
            if possible:get(j):getFullName() == wanted then
                return possible:get(j)
            end
        end
    end
    for j = 0, possible:size() - 1 do
        if possible:get(j):getFullName() ~= "Base.Moveable" then
            return possible:get(j)
        end
    end
    return possible:size() > 0 and possible:get(0) or nil
end

-- Adds what one craft of `recipe` takes, tools included. Each input gets the first of its
-- possible items listed in `prefer`, else its first possible item other than a generic
-- Base.Moveable. A drainable input that counts uses gets one full item. Returns the inputs that
-- had no possible item at all.
function Debug.addRecipeInputs(player, recipe, prefer)
    local inventory = player:getInventory()
    local unmatched = {}
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        local item = pickInputItem(input:getPossibleInputItems(), prefer)
        if item then
            local count = input:getIntAmount()
            if item:isItemType(ItemType.DRAINABLE) and not input:isItemCount() then
                count = 1
            end
            inventory:AddItems(item:getFullName(), count)
        else
            table.insert(unmatched, input:getOriginalLine())
        end
    end
    return unmatched
end

local WORK_TABLE_SPRITE = "carpentry_01_60" -- the Shoddy Table players build, a crafting surface

local function isWorkTable(object)
    local sprite = object:getSprite()
    return sprite ~= nil and sprite:getName() == WORK_TABLE_SPRITE
end

-- AnySurfaceCraft recipes need a table the character can walk to. Puts one on a free square next
-- to the character, with no wall in between, unless one is there already. IsoObject.new with a
-- name gives the object the sprite's properties, Surface included.
function Debug.placeWorkTable(player)
    local here = player:getSquare()
    local free
    for _, direction in ipairs({ IsoDirections.N, IsoDirections.W, IsoDirections.S, IsoDirections.E }) do
        local square = here:getAdjacentSquare(direction)
        if RenewableEnergy.findObjectOn(square, isWorkTable) then
            return
        end
        if not free and square and square:isFree(false) and not here:isBlockedTo(square) then
            free = square
        end
    end
    assert(free, "RenewableEnergy.Debug: no free square next to the character for a table")
    free:AddTileObject(IsoObject.new(free, WORK_TABLE_SPRITE, "Table"))
end

local function isContainerGeneratorOrPanel(object)
    return object:getContainer() ~= nil or instanceof(object, "IsoGenerator")
        or RenewableEnergy.PowerBank.sourceKind(object) ~= nil
end

-- Whether a test or the dev harness may put a bank or panel on `square`: free to walk on, with no
-- vehicle, container, generator or panel there, and indoors where a bank may stand if `indoors`,
-- else outdoors.
function Debug.isFreeSquare(square, indoors)
    return square ~= nil and square:isFree(false) and square:getVehicleContainer() == nil
        and RenewableEnergy.PowerBank.canPlaceBank(square) == indoors and (indoors or square:isOutside())
        and not RenewableEnergy.findObjectOn(square, isContainerGeneratorOrPanel)
end

-- An electrician and carpenter who knows every recipe, with a screwdriver and a table to craft at.
function Debug.setupPlayer(player)
    player:setPerkLevelDebug(Perks.Electricity, 8)
    player:setPerkLevelDebug(Perks.MetalWelding, 4)
    player:setPerkLevelDebug(Perks.Woodwork, 3)
    Debug.learnRecipes(player)
    player:getInventory():AddItem("Base.Screwdriver")
    Debug.placeWorkTable(player)
end

return Debug
