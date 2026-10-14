require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/Gadgets/SolarGardenLight"

-- Callbacks of the craftRecipes in media/scripts/RenewableEnergy/Recipes.txt. Shared, since
-- OnTest runs wherever the craft is checked. OnCreate runs once, on the authority (single
-- player or the server), after the outputs were already sent to a multiplayer client, so
-- whatever it changes on an item is sent again.
--
-- OnTest is asked about every candidate item of every input, tools included, so each one
-- answers only for the items it is about and lets the rest through.
RenewableEnergy = RenewableEnergy or {}
local Recipes = {}
RenewableEnergy.Recipes = Recipes

local Specs, Battery, Wear, PowerBank = RenewableEnergy.Specs, RenewableEnergy.Battery, RenewableEnergy.Wear, RenewableEnergy.PowerBank
-- Case modData: the car battery type it came out of, of the three vanilla car batteries.
local CASE_BATTERY_KEY = "RenewableEnergy_batteryType"
-- What Rebuild Car Battery makes from a case that doesn't say.
local CAR_BATTERY = "Base.CarBattery1"

-- Mount item types by their Specs.mounts kind.
local MOUNT_KINDS = {
    ["RenewableEnergy.SolarFlat"] = "flat",
    ["RenewableEnergy.SolarWallWood"] = "wall",
    ["RenewableEnergy.SolarWallMetal"] = "wall",
    ["RenewableEnergy.SolarRackWood"] = "rack",
    ["RenewableEnergy.SolarRackMetal"] = "rack",
}

-- What each mount recipe teaches when every module in it is new to mounting, by perk name. A
-- module teaches its share only the first time it is ever mounted (PowerBank.MOUNTED_ONCE), so
-- unmounting and mounting the same modules again teaches nothing.
Recipes.MOUNT_XP = {
    ["RenewableEnergy.SolarFlat"] = { Electricity = 10 },
    ["RenewableEnergy.SolarWallWood"] = { Electricity = 15, Woodwork = 5 },
    ["RenewableEnergy.SolarWallMetal"] = { Electricity = 15, MetalWelding = 5 },
    ["RenewableEnergy.SolarRackWood"] = { Electricity = 20, Woodwork = 10 },
    ["RenewableEnergy.SolarRackMetal"] = { Electricity = 20, MetalWelding = 10 },
}

-- Repair Cracked Module: condition it adds, and the most it brings each module type to. A
-- factory module's cells stay cracked under the new glass; a homemade one is at its
-- ConditionMax.
Recipes.MODULE_REPAIR = 30
Recipes.MODULE_REPAIR_CAP = {
    ["RenewableEnergy.SolarModule"] = 80,
    ["RenewableEnergy.HomemadeSolarModule"] = 60,
}

-- Service Battery adds a little to a tired battery; Recondition sets a better one.
Recipes.SERVICE_REPAIR = 10
Recipes.SERVICE_CAP = 60
Recipes.RECONDITION_CONDITION = 85

local function isModule(item)
    return Specs.modules[item:getFullType()] ~= nil
end

local function firstInput(craftRecipeData, matches)
    local items = craftRecipeData:getAllInputItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if matches(item) then
            return item
        end
    end
    return nil
end

local function sendModData(character, item)
    if isServer() then
        syncItemModData(character, item)
    end
end

-- Panel mounts -----------------------------------------------------------------------------------

-- OnCreate of the mount recipes: the mount remembers its modules, as its placed object will, and
-- the modules new to mounting teach their share of the recipe's XP.
function Recipes.mountModules(craftRecipeData, character)
    local modules, new = {}, 0
    local items = craftRecipeData:getAllInputItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if isModule(item) then
            local module = PowerBank.moduleRecord(item)
            if not module.mounted then
                module.mounted = true
                new = new + 1
            end
            table.insert(modules, module)
        end
    end
    local mount = craftRecipeData:getFirstCreatedItem()
    mount:getModData()[PowerBank.MODULES] = modules
    sendModData(character, mount)
    if new > 0 then
        for perk, xp in pairs(Recipes.MOUNT_XP[mount:getFullType()]) do
            addXp(character, Perks[perk], xp * new / #modules)
        end
    end
end

local function isMount(item)
    return MOUNT_KINDS[item:getFullType()] ~= nil
end

-- OnCreate of the Unmount recipes: the modules come back as they went in.
function Recipes.unmountModules(craftRecipeData, character)
    local mount = firstInput(craftRecipeData, isMount)
    if not mount then
        return
    end
    for _, module in ipairs(PowerBank.modulesOf(mount, MOUNT_KINDS[mount:getFullType()])) do
        local item = instanceItem(module.type)
        Wear.setCondition(item, module.condition)
        PowerBank.markModule(item, module)
        Actions.addOrDropItem(character, item)
    end
end

-- Solar modules ----------------------------------------------------------------------------------

-- OnTest of Repair Cracked Module: the module must be below what the repair brings it to.
function Recipes.isModuleBelowRepairCap(item, character)
    local cap = Recipes.MODULE_REPAIR_CAP[item:getFullType()]
    return cap == nil or item:getCondition() < cap
end

--- What Repair Cracked Module brings the module's condition to.
function Recipes.repairedCondition(module)
    return math.min(Recipes.MODULE_REPAIR_CAP[module:getFullType()], module:getCondition() + Recipes.MODULE_REPAIR)
end

function Recipes.repairModule(craftRecipeData, character)
    local module = firstInput(craftRecipeData, function(item)
        return Recipes.MODULE_REPAIR_CAP[item:getFullType()] ~= nil
    end)
    Wear.setCondition(module, Recipes.repairedCondition(module))
    sendItemStats(module)
end

-- Repair Cracked Panel mends a module still on the arrow board trailer the way Repair Cracked
-- Module mends one in hand. It reads the recipe's inputs, skill, time and XP from the recipe
-- itself, so the two can't drift apart; the module input is the panel.
Recipes.MODULE_REPAIR_RECIPE = "RenewableEnergy_RepairCrackedModule"

function Recipes.moduleRepairRecipe()
    return getScriptManager():getCraftRecipe(Recipes.MODULE_REPAIR_RECIPE)
end

-- As CraftRecipeData.processKeepInputItem wears kept tools: the factor for each MayDegrade flag.
local function wearOf(input)
    if input:mayDegradeHeavy() then return 1 end
    if input:mayDegrade() then return 2 end
    if input:mayDegradeLight() then return 3 end
    if input:mayDegradeVeryLight() then return 6 end
    return nil
end

local function isModuleInput(input)
    return input:containsItem(getScriptManager():getItem(Specs.factoryModule))
end

--- The inventory items, bags included, that pay for a Repair Cracked Panel: for each of the
--- recipe's inputs but the module, { item, uses, keep, wear }, `uses` being the drainable uses it takes
--- (nil for a whole item), and `wear` the factor a kept tool's MayDegrade flag gives damageCheck.
--- Returns nil, and the first input nothing pays for, when one is missing.
function Recipes.panelRepairInputs(character)
    local inventory = character:getInventory()
    local inputs = Recipes.moduleRepairRecipe():getInputs()
    local picks, taken = {}, {}
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if not isModuleInput(input) then
            local needed = input:getIntAmount()
            local candidates = inventory:getAllEvalRecurse(function(item)
                return not taken[item] and not item:isBroken() and input:containsItem(item:getScriptItem())
            end)
            for j = 0, candidates:size() - 1 do
                if needed <= 0 then break end
                local item = candidates:get(j)
                if instanceof(item, "DrainableComboItem") then
                    -- A line such as [Base.Epoxy;2:Base.Glue] takes more uses of some items.
                    local uses = math.ceil(needed * input:getRelativeScale(item:getFullType()))
                    if item:getCurrentUses() >= uses then
                        table.insert(picks, { item = item, uses = uses, keep = input:isKeep() })
                        taken[item], needed = true, 0
                    end
                else
                    table.insert(picks, { item = item, keep = input:isKeep(), wear = wearOf(input) })
                    taken[item], needed = true, needed - 1
                end
            end
            if needed > 0 then
                return nil, input
            end
        end
    end
    return picks
end

--- Why the character can't do Repair Cracked Panel, as a translation key and its arguments,
--- or nil when they can: the recipe unknown, the skill short, or an input missing.
function Recipes.panelRepairRefusal(character)
    local recipe = Recipes.moduleRepairRecipe()
    if not character:isRecipeKnown(recipe) then
        return "Tooltip_RenewableEnergy_NeedRecipe", { recipe:getTranslationName() }
    end
    for i = 0, recipe:getRequiredSkillCount() - 1 do
        local skill = recipe:getRequiredSkill(i)
        if character:getPerkLevel(skill:getPerk()) < skill:getLevel() then
            return "Tooltip_RenewableEnergy_NeedSkill", { skill:getPerk():getName(), skill:getLevel() }
        end
    end
    local picks, missing = Recipes.panelRepairInputs(character)
    if not picks then
        return "Tooltip_RenewableEnergy_NeedItem", { missing:getPossibleInputItems():get(0):getDisplayName() }
    end
    return nil
end

--- Uses up what Recipes.panelRepairInputs picked; tools are kept and may wear as the recipe's
--- craft wears them. Authority only.
function Recipes.useInputs(picks, character)
    local recipe = Recipes.moduleRepairRecipe()
    for _, pick in ipairs(picks) do
        if pick.keep and pick.wear then
            local skill = recipe:getHighestRelevantSkillLevel(character) + pick.item:getMaintenanceMod(character)
            pick.item:damageCheck(skill, pick.wear, false)
            pick.item:syncItemFields()
        elseif not pick.keep then
            for _ = 1, pick.uses or 1 do
                pick.item:UseAndSync()
            end
        end
    end
end

-- OnTest of Take Apart Shattered Module: a module that still makes power stays whole.
function Recipes.isShatteredModule(item, character)
    return item:getFullType() ~= Specs.factoryModule or item:getCondition() <= 0
end

-- Batteries --------------------------------------------------------------------------------------

local function inputBattery(craftRecipeData)
    return firstInput(craftRecipeData, Battery.isBattery)
end

-- OnTest of Service Battery.
function Recipes.canServiceBattery(item, character)
    return not Battery.isBattery(item) or item:getCondition() < Recipes.SERVICE_CAP
end

function Recipes.serviceBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    Wear.setCondition(battery, math.min(Recipes.SERVICE_CAP, battery:getCondition() + Recipes.SERVICE_REPAIR))
    sendItemStats(battery)
end

-- OnTest of Recondition Battery.
function Recipes.canReconditionBattery(item, character)
    return not Battery.isBattery(item) or item:getCondition() < Recipes.RECONDITION_CONDITION
end

function Recipes.reconditionBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    Wear.setCondition(battery, Recipes.RECONDITION_CONDITION)
    Battery.setCharge(battery, 0)
    sendItemStats(battery)
end

-- OnCreate of Strip Car Battery: the case remembers which of the three car batteries it was,
-- since each fits different vehicles.
function Recipes.stripCarBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    local case = craftRecipeData:getFirstCreatedItem()
    case:getModData()[CASE_BATTERY_KEY] = battery:getFullType()
    sendModData(character, case)
end

local function setRebuilt(battery)
    Wear.setCondition(battery, battery:getConditionMax())
    Battery.setCharge(battery, 0)
end

-- OnCreate of Rebuild Deep Cycle and L-16 Battery: like new, and empty.
function Recipes.rebuildBattery(craftRecipeData, character)
    local battery = craftRecipeData:getFirstCreatedItem()
    setRebuilt(battery)
    sendItemStats(battery)
end

-- OnCreate of Rebuild Car Battery, which has no script output: it makes the car battery type
-- the case came out of.
function Recipes.rebuildCarBattery(craftRecipeData, character)
    local case = firstInput(craftRecipeData, function(item)
        return item:getFullType() == "RenewableEnergy.CarBatteryCase"
    end)
    local battery = instanceItem(case and case:getModData()[CASE_BATTERY_KEY] or CAR_BATTERY)
    setRebuilt(battery)
    Actions.addOrDropItem(character, battery)
end

-- Gadgets ----------------------------------------------------------------------------------------

-- OnCreate of Take Apart Solar Garden Light: the bulb in it comes out whole.
function Recipes.takeApartGardenLight(craftRecipeData, character)
    local SolarGardenLight = RenewableEnergy.SolarGardenLight
    local light = firstInput(craftRecipeData, function(item)
        return item:getFullType() == SolarGardenLight.ITEM
    end)
    local bulb = light and SolarGardenLight.getBulb(light)
    if bulb then
        Actions.addOrDropItem(character, instanceItem(bulb))
    end
end

return Recipes
