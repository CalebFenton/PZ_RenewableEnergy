-- Setup helpers for the debug scenario and tests. Debug mode only.
RenewableEnergyDebug = {}

-- Every item this mod defines, in the order the README shows them.
RenewableEnergyDebug.ITEMS = {
    "RenewableEnergy.SolarModule",
    "RenewableEnergy.SolarFlat", "RenewableEnergy.SolarWall", "RenewableEnergy.SolarRack",
    "RenewableEnergy.BatteryBox", "RenewableEnergy.BatteryBank",
    "RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter", "RenewableEnergy.InverterCharger",
    "RenewableEnergy.ChargeController", "RenewableEnergy.SolarFailsafe",
    "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery",
    "RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger",
    "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2",
    "RenewableEnergy.CrowcallRoadMap", "RenewableEnergy.DixieTrailerParkMap",
}

local RECIPE_PREFIX = "RenewableEnergy_"

-- Every craftRecipe of this mod, by the prefix they all share in module Base.
function RenewableEnergyDebug.recipeNames()
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

function RenewableEnergyDebug.learnRecipes(player)
    for _, name in ipairs(RenewableEnergyDebug.recipeNames()) do
        player:learnRecipe(name)
    end
end

function RenewableEnergyDebug.forgetRecipes(player)
    for _, name in ipairs(RenewableEnergyDebug.recipeNames()) do
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
function RenewableEnergyDebug.addRecipeInputs(player, recipe, prefer)
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

local function hasWorkTable(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        if sprite and sprite:getName() == WORK_TABLE_SPRITE then
            return true
        end
    end
    return false
end

-- AnySurfaceCraft recipes need a table the character can walk to. Puts one on a free square next
-- to the character, with no wall in between, unless one is there already. IsoObject.new with a
-- name gives the object the sprite's properties, Surface included.
function RenewableEnergyDebug.placeWorkTable(player)
    local here = player:getSquare()
    local free
    for _, direction in ipairs({ IsoDirections.N, IsoDirections.W, IsoDirections.S, IsoDirections.E }) do
        local square = here:getAdjacentSquare(direction)
        if square and hasWorkTable(square) then
            return
        end
        if not free and square and square:isFree(false) and not here:isBlockedTo(square) then
            free = square
        end
    end
    assert(free, "RenewableEnergyDebug: no free square next to the character for a table")
    free:AddTileObject(IsoObject.new(free, WORK_TABLE_SPRITE, "Table"))
end

-- An electrician and carpenter who knows every recipe, with a screwdriver and a table to craft at.
function RenewableEnergyDebug.setupPlayer(player)
    player:setPerkLevelDebug(Perks.Electricity, 8)
    player:setPerkLevelDebug(Perks.MetalWelding, 4)
    player:setPerkLevelDebug(Perks.Woodwork, 3)
    RenewableEnergyDebug.learnRecipes(player)
    player:getInventory():AddItem("Base.Screwdriver")
    RenewableEnergyDebug.placeWorkTable(player)
end
