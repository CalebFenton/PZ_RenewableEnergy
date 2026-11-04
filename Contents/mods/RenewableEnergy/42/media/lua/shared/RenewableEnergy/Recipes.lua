-- Callbacks of the mod's craftRecipes. Shared: OnTest runs wherever the craft is checked, and every
-- side resolves all of a recipe's Lua calls when it sets up a craft (CraftRecipeData). OnCreate runs
-- once on the authority, after the outputs were already sent to an MP client, so item changes are
-- re-sent: outputs (in the inventory) with syncItemFields, inputs (maybe in a nearby container or on
-- the floor) with sendItemStats, or whole where that misses a field. The rules they apply are their owners': Battery's repairs,
-- ModuleRepair's seals and new glass, Panel's module records, Wear's crafted condition.
--
-- OnTest is asked about every candidate item of every input, tools included, so each one
-- answers only for the items it is about and lets the rest through.

local Utilities = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local Sprites = require "RenewableEnergy/Sprites"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"
local Digester = require "RenewableEnergy/Biogas/Digester"
local Items = require "cf_commonlib/Items"
local RecipeLearning = require "cf_commonlib/RecipeLearning"

local Recipes = {}
-- Recipes.txt names its OnTest and OnCreate functions by Lua path.
RenewableEnergy = RenewableEnergy or {}
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

--- Shows on the panel mount item `item` the modules it holds: its ground model and icon by how
--- many are homemade (its model index, Sprites.homemadeCount). Also the mount items' OnCreate: the
--- game gives a new item that has models by index a random one, and a new mount holds factory
--- modules (Panel.modulesOf).
function Recipes.showMountModules(item)
    item:setModelIndex(Sprites.homemadeCount(Panel.modulesOf(item, Recipes.MOUNTS[item:getFullType()].kind)))
end

-- Sends a crafted `item` to the clients again, whole: an MP client got it before OnCreate ran,
-- and no item sync carries its model index. In a container it replaces itself; on the floor it is
-- put down again where it lies.
local function resendWhole(item)
    if not isServer() then return end
    local container, worldItem = item:getContainer(), item:getWorldItem()
    if container then
        sendReplaceItemInContainer(container, item, item)
    elseif worldItem then
        local square = worldItem:getSquare()
        local x, y, z = worldItem:getOffX(), worldItem:getOffY(), worldItem:getOffZ()
        square:transmitRemoveItemFromSquare(worldItem)
        square:removeWorldObject(worldItem)
        item:setWorldItem(nil)
        square:AddWorldInventoryItem(item, x, y, z)
    end
end

-- Sets an input's repair count, and sends it with its condition. syncItemFields carries the count
-- only for an item a player holds (InventoryItem.syncItemFields), and sendItemStats never does, so
-- one in a nearby container or on the floor is sent whole.
local function setRepairs(item, count)
    item:setHaveBeenRepaired(count)
    local outer = item:getOutermostContainer()
    if outer and instanceof(outer:getParent(), "IsoPlayer") then
        item:syncItemFields()
        sendItemStats(item)
    else
        resendWhole(item)
    end
end

local function countRepair(item)
    setRepairs(item, item:getHaveBeenRepaired() + 1)
end

-- OnCreate of the mount recipes: the mount remembers its modules, as its placed object will, and
-- shows them; the modules new to mounting teach their share of the recipe's XP.
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
    Recipes.showMountModules(mount)
    resendWhole(mount)
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

-- OnTest of Seal Cracked Module: a module must be one a seal can help.
function Recipes.isModuleBelowRepairCap(item, character)
    return not isModule(item)
        or ModuleRepair.sealable(item:getFullType(), item:getCondition(), item:getHaveBeenRepaired())
end

-- OnCreate of Seal Cracked Module.
function Recipes.repairModule(craftRecipeData, character)
    local module = Items.firstInput(craftRecipeData, isModule)
    local condition, repaired = ModuleRepair.sealed(module:getFullType(), module:getCondition(),
        module:getHaveBeenRepaired())
    Wear.setCondition(module, condition)
    setRepairs(module, repaired)
end

-- OnTest of Reglaze Module: the module must be damaged.
function Recipes.isReglazableModule(item, character)
    return not isModule(item) or ModuleRepair.reglazable(item:getFullType(), item:getCondition())
end

-- OnCreate of Reglaze Module: new glass brings the module back to new, and the seals on the old no
-- longer count.
function Recipes.reglazeModule(craftRecipeData, character)
    local module = Items.firstInput(craftRecipeData, isModule)
    Wear.setCondition(module, module:getConditionMax())
    setRepairs(module, 0)
end

-- OnTest of Take Apart Shattered Module: a module that still makes power stays whole.
function Recipes.isShatteredModule(item, character)
    return item:getFullType() ~= Specs.factoryModule or item:isBroken()
end

-- OnTest of Take Out Window Glass. Whatever tile was picked up is the same script item, told apart
-- only by its world sprite, whose MoveType the game's own moveables code reads to treat it as a
-- window (ISMoveableSpriteProps). Pickup makes an item only of a whole window
-- (ISMoveableSpriteProps:instanceItem), so every window item still has its glass.
function Recipes.isWindow(item, character)
    if not instanceof(item, "Moveable") then
        return true
    end
    local spriteName = item:getWorldSprite()
    local sprite = spriteName and getSprite(spriteName)
    return sprite ~= nil and sprite:getProperties():get("MoveType") == "Window"
end

local function inputBattery(craftRecipeData)
    return Items.firstInput(craftRecipeData, Battery.isBattery)
end

-- OnTest of Service Battery.
function Recipes.canServiceBattery(item, character)
    return not Battery.isBattery(item) or item:getCondition() < Battery.serviceLimit(item:getHaveBeenRepaired())
end

-- OnTest of Recondition Battery.
function Recipes.canReconditionBattery(item, character)
    return not Battery.isBattery(item) or item:getCondition() < Battery.repairLimit(item:getHaveBeenRepaired())
end

-- OnCreate of Service Battery: a top-up, not a repair, so it leaves the repair count be.
function Recipes.serviceBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    Wear.setCondition(battery, Battery.serviced(battery:getCondition(), battery:getHaveBeenRepaired()))
    sendItemStats(battery)
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
    local case = Items.firstInput(craftRecipeData, Items.ofType("RenewableEnergy.CarBatteryCase"))
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
    local light = Items.firstInput(craftRecipeData, Items.ofType(SolarGardenLight.ITEM))
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
    local room = math.floor((old:getMaxUses() - old:getCurrentUses()) / bottlePerTankUse + Utilities.EPSILON)
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
