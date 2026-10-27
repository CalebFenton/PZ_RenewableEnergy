-- Callbacks of the mod's craftRecipes. Shared: OnTest runs wherever the craft is checked, and every
-- side resolves all of a recipe's Lua calls when it sets up a craft (CraftRecipeData). OnCreate runs
-- once on the authority, after the outputs were already sent to an MP client, so item changes are
-- re-sent: outputs (in the inventory) with syncItemFields, inputs (maybe in a nearby container or on
-- the floor) with sendItemStats. The rules they apply are their owners': Battery's repairs,
-- ModuleRepair's seals and new glass, Panel's module records, Wear's crafted condition.
--
-- OnTest is asked about every candidate item of every input, tools included, so each one
-- answers only for the items it is about and lets the rest through.

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"
local Digester = require "RenewableEnergy/Biogas/Digester"
local Items = require "cf_commonlib/Items"
local RecipeLearning = require "cf_commonlib/RecipeLearning"

local Recipes = {}
RenewableEnergy.Recipes = Recipes

-- The mod's craftRecipes and build recipes with an AutoLearn skill are learned by level, its build
-- recipes only through this (cf_commonlib's RecipeLearning).
RecipeLearning.register("RenewableEnergy_")

-- Case modData: the full type of the vanilla car battery it came out of.
local CASE_BATTERY_KEY = "RenewableEnergy_batteryType"

-- Panel mounts by item type: kind, the Specs.mounts row; xp, what the mount recipe teaches, by
-- perk name, when every module in it is new to mounting. A module teaches its share only the
-- first time it is ever mounted (its record's `mounted` flag), so unmounting and mounting the
-- same modules again teaches nothing.
Recipes.MOUNTS = {
    ["RenewableEnergy.SolarFlat"] = { kind = "flat", xp = { Electricity = 10 } },
    ["RenewableEnergy.SolarWallWood"] = { kind = "wall", xp = { Electricity = 15, Woodwork = 5 } },
    ["RenewableEnergy.SolarWallMetal"] = { kind = "wall", xp = { Electricity = 15, MetalWelding = 5 } },
    ["RenewableEnergy.SolarRackWood"] = { kind = "rack", xp = { Electricity = 20, Woodwork = 10 } },
    ["RenewableEnergy.SolarRackMetal"] = { kind = "rack", xp = { Electricity = 20, MetalWelding = 10 } },
}

local function isModule(item)
    return Specs.modules[item:getFullType()] ~= nil
end

-- Sets the item's repair count; syncItemFields carries it to clients, sendItemStats the condition.
local function setRepairs(item, count)
    item:setHaveBeenRepaired(count)
    item:syncItemFields()
    sendItemStats(item)
end

local function countRepair(item)
    setRepairs(item, item:getHaveBeenRepaired() + 1)
end

-- OnCreate of the mount recipes: the mount remembers its modules, as its placed object will, and
-- the modules new to mounting teach their share of the recipe's XP.
function Recipes.mountModules(craftRecipeData, character)
    local modules, new = {}, 0
    local items = craftRecipeData:getAllInputItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if isModule(item) then
            local module = Panel.moduleRecord(item)
            if not module.mounted then
                module.mounted = true
                new = new + 1
            end
            table.insert(modules, module)
        end
    end
    local mount = craftRecipeData:getFirstCreatedItem()
    mount:getModData()[Panel.MODULES_KEY] = modules
    mount:syncItemFields()
    if new > 0 then
        for perk, xp in pairs(Recipes.MOUNTS[mount:getFullType()].xp) do
            addXp(character, Perks[perk], xp * new / #modules)
        end
    end
end

local function isMount(item)
    return Recipes.MOUNTS[item:getFullType()] ~= nil
end

-- OnCreate of the Unmount recipes: the modules come back as they went in.
function Recipes.unmountModules(craftRecipeData, character)
    local mount = Items.firstInput(craftRecipeData, isMount)
    if not mount then
        return
    end
    for _, module in ipairs(Panel.modulesOf(mount, Recipes.MOUNTS[mount:getFullType()].kind)) do
        local item = instanceItem(module.type)
        Wear.setCondition(item, module.condition)
        Panel.markModule(item, module)
        Items.giveItems(character, item)
    end
end

local function isSealType(item)
    return ModuleRepair.SEAL_CAP[item:getFullType()] ~= nil
end

-- OnTest of Seal Cracked Module and its glue twin: a module must be one a seal can help.
function Recipes.isModuleBelowRepairCap(item, character)
    return not isSealType(item)
        or ModuleRepair.sealable(item:getFullType(), item:getCondition(), item:getHaveBeenRepaired())
end

-- OnCreate of Seal Cracked Module and its glue twin.
function Recipes.repairModule(craftRecipeData, character)
    local module = Items.firstInput(craftRecipeData, isSealType)
    local condition, repaired = ModuleRepair.sealed(module:getFullType(), module:getCondition(),
        module:getHaveBeenRepaired())
    Wear.setCondition(module, condition)
    setRepairs(module, repaired)
end

-- What Reglaze Module brings the module item `item` to (ModuleRepair.reglazedCondition), or nil.
local function reglazedItem(item)
    return ModuleRepair.reglazedCondition(item:getFullType(), item:getCondition(), item:getHaveBeenRepaired())
end

-- OnTest of Reglaze Module: the module must be below what new glass brings it to.
function Recipes.isModuleBelowReglaze(item, character)
    local reglazed = reglazedItem(item)
    return reglazed == nil or item:getCondition() < reglazed
end

-- OnCreate of Reglaze Module: new glass, so the seals on the old no longer count.
function Recipes.reglazeModule(craftRecipeData, character)
    local module = Items.firstInput(craftRecipeData, isModule)
    Wear.setCondition(module, reglazedItem(module))
    setRepairs(module, 0)
end

-- OnTest of Take Apart Shattered Module: a module that still makes power stays whole.
function Recipes.isShatteredModule(item, character)
    return item:getFullType() ~= Specs.factoryModule or item:getCondition() <= 0
end

local function inputBattery(craftRecipeData)
    return Items.firstInput(craftRecipeData, Battery.isBattery)
end

-- OnTest of Service Battery and Recondition Battery.
function Recipes.canRepairBattery(item, character)
    return not Battery.isBattery(item) or item:getCondition() < Battery.repairLimit(item:getHaveBeenRepaired())
end

-- OnCreate of Service Battery.
function Recipes.serviceBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    Wear.setCondition(battery, math.min(Battery.repairLimit(battery:getHaveBeenRepaired()), battery:getCondition() + Battery.SERVICE_REPAIR))
    countRepair(battery)
end

-- OnCreate of Recondition Battery.
function Recipes.reconditionBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    Wear.setCondition(battery, Battery.repairLimit(battery:getHaveBeenRepaired()))
    Battery.setCharge(battery, 0)
    countRepair(battery)
end

-- OnCreate of Strip Car Battery: the case remembers which vanilla car battery it was,
-- since each fits different vehicles.
function Recipes.stripCarBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    local case = craftRecipeData:getFirstCreatedItem()
    case:getModData()[CASE_BATTERY_KEY] = battery:getFullType()
    case:syncItemFields()
end

local function setRebuilt(battery)
    Wear.setCondition(battery, battery:getConditionMax())
    Battery.setCharge(battery, 0)
end

-- OnCreate of the recipes that rebuild or make a battery: like new, and empty.
function Recipes.rebuildBattery(craftRecipeData, character)
    local battery = craftRecipeData:getFirstCreatedItem()
    setRebuilt(battery)
    battery:syncItemFields()
end

-- OnCreate of Rebuild Car Battery, which has no script output: it makes the car battery type
-- the case came out of.
function Recipes.rebuildCarBattery(craftRecipeData, character)
    local case = Items.firstInput(craftRecipeData, function(item)
        return item:getFullType() == "RenewableEnergy.CarBatteryCase"
    end)
    local battery = instanceItem(case and case:getModData()[CASE_BATTERY_KEY] or VehicleBattery.CAR_BATTERY)
    setRebuilt(battery)
    Items.giveItems(character, battery)
end

-- OnCreate of Make Charge Controller: a new controller has a condition of its own, so a loot
-- refill of the container it is kept in doesn't wear it as if found (Finds.readyFoundItems).
function Recipes.makeChargeController(craftRecipeData, character)
    local controller = craftRecipeData:getFirstCreatedItem()
    Wear.markOwnCondition(controller)
    controller:syncItemFields()
end

-- The Electricity level `recipe` needs, 0 if none.
local function electricityRequired(recipe)
    for i = 0, recipe:getRequiredSkillCount() - 1 do
        local skill = recipe:getRequiredSkill(i)
        if skill:getPerk() == Perks.Electricity then
            return skill:getLevel()
        end
    end
    return 0
end

-- OnCreate of the inverter recipes: the maker's skill sets the new inverter's condition
-- (Wear.craftedInverterCondition), and it is marked as having a condition of its own, as a new
-- controller is.
function Recipes.makeInverter(craftRecipeData, character)
    local inverter = craftRecipeData:getFirstCreatedItem()
    Wear.setCondition(inverter, Wear.craftedInverterCondition(inverter:getConditionMax(),
        character:getPerkLevel(Perks.Electricity), electricityRequired(craftRecipeData:getRecipe())))
    Wear.markOwnCondition(inverter)
    inverter:syncItemFields()
end

-- OnCreate of Take Apart Solar Garden Light: the bulb in it comes out whole.
function Recipes.takeApartGardenLight(craftRecipeData, character)
    local light = Items.firstInput(craftRecipeData, function(item)
        return item:getFullType() == SolarGardenLight.ITEM
    end)
    local bulb = light and SolarGardenLight.getBulb(light)
    if bulb then
        Items.giveItems(character, bulb)
    end
end

-- OnCreate of Refill Propane Bottle, as vanilla's Refill Blow Torch moves its propane
-- (RecipeCodeOnCreate.refillBlowTorch): the new bottle starts as the old one was and takes what
-- it has room for from the tank. The propane moves in whole uses of the tank, the coarser of the
-- two, so that rounding the tank's store can't make propane from nothing.
function Recipes.refillPropaneBottle(craftRecipeData, character)
    local bottle = craftRecipeData:getFirstCreatedItem()
    local old = craftRecipeData:getAllConsumedItems():get(0)
    local tank = craftRecipeData:getAllKeepInputItems():get(0)
    local bottlePerTankUse = tank:getUseDelta() / (Digester.BOTTLE_SHARE * bottle:getUseDelta())
    local room = math.floor((old:getMaxUses() - old:getCurrentUses()) / bottlePerTankUse + RenewableEnergy.EPSILON)
    local taken = math.min(room, tank:getCurrentUses())
    bottle:setCurrentUses(old:getCurrentUses() + round(taken * bottlePerTankUse))
    tank:setCurrentUses(tank:getCurrentUses() - taken)
    bottle:syncItemFields()
    sendItemStats(tank)
end

-- OnCreate of Air Out Iron Sponge: the sponge comes back with one packing fewer left than the
-- spent one had (its condition), as each airing leaves less iron to rust. The water's container
-- is kept, so the spent sponge is the only item consumed.
function Recipes.airOutIronSponge(craftRecipeData, character)
    local sponge = craftRecipeData:getFirstCreatedItem()
    sponge:setCondition(craftRecipeData:getAllConsumedItems():get(0):getCondition() - 1)
    sponge:syncItemFields()
end

return Recipes
