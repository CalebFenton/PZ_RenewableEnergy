require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Wear"

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

local Battery, Wear = RenewableEnergy.Battery, RenewableEnergy.Wear
-- A mount item's modData, like its placed object's: its modules' types and conditions.
local MODULES = RenewableEnergy.PowerBank.MODULES
-- Case modData: the car battery type it came out of, of the three vanilla car batteries.
local CASE_BATTERY_KEY = "RenewableEnergy_batteryType"

local FACTORY_MODULE = "RenewableEnergy.SolarModule"
local CAR_BATTERY = "Base.CarBattery1"

-- Mount item types by their Specs.mounts kind.
local MOUNT_KINDS = {
    ["RenewableEnergy.SolarFlat"] = "flat",
    ["RenewableEnergy.SolarWallWood"] = "wall",
    ["RenewableEnergy.SolarWallMetal"] = "wall",
    ["RenewableEnergy.SolarRackWood"] = "rack",
    ["RenewableEnergy.SolarRackMetal"] = "rack",
}

-- Repair Cracked Module: condition it adds, and the most it brings each module type to. A
-- factory module's cells stay cracked under the new glass; a homemade one is at its
-- ConditionMax.
local MODULE_REPAIR = 30
local MODULE_REPAIR_CAP = {
    ["RenewableEnergy.SolarModule"] = 80,
    ["RenewableEnergy.HomemadeSolarModule"] = 60,
}

-- Service Battery adds a little to a tired battery; Recondition sets a better one.
local SERVICE_REPAIR = 10
local SERVICE_CAP = 60
local RECONDITION_CONDITION = 85

local function isModule(item)
    return RenewableEnergy.Specs.modules[item:getFullType()] ~= nil
end

local function firstInput(craftRecipeData, matches)
    local items = craftRecipeData:getAllInputItems()
    for i = 0, items:size() - 1 do
        if matches(items:get(i)) then
            return items:get(i)
        end
    end
    return nil
end

local function addToInventory(character, item)
    local inventory = character:getInventory()
    inventory:AddItem(item)
    if isServer() then
        sendAddItemToContainer(inventory, item)
    end
end

local function sendModData(character, item)
    if isServer() then
        syncItemModData(character, item)
    end
end

-- Panel mounts -----------------------------------------------------------------------------------

--- The modules a mount item holds, as written under PowerBank.MODULES. A mount that never had them
--- written, such as one spawned by debug, holds factory modules in full condition.
---@param mount InventoryItem
---@return table[] { { type, condition }, ... }
function Recipes.modulesOf(mount)
    local modules = mount:getModData()[MODULES]
    if modules then
        return modules
    end
    local list = {}
    local kind = MOUNT_KINDS[mount:getFullType()]
    for i = 1, kind and RenewableEnergy.Specs.mounts[kind].modules or 0 do
        list[i] = { type = FACTORY_MODULE, condition = 100 }
    end
    return list
end

-- OnCreate of the mount recipes: the mount remembers its modules.
function Recipes.mountModules(craftRecipeData, character)
    local modules = {}
    local items = craftRecipeData:getAllInputItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if isModule(item) then
            table.insert(modules, { type = item:getFullType(), condition = item:getCondition() })
        end
    end
    local mount = craftRecipeData:getFirstCreatedItem()
    mount:getModData()[MODULES] = modules
    sendModData(character, mount)
end

-- OnCreate of the Unmount recipes: the modules come back as they went in.
function Recipes.unmountModules(craftRecipeData, character)
    local mount = firstInput(craftRecipeData, function(item)
        return MOUNT_KINDS[item:getFullType()] ~= nil
    end)
    for _, module in ipairs(mount and Recipes.modulesOf(mount) or {}) do
        local item = instanceItem(module.type)
        Wear.setCondition(item, module.condition)
        addToInventory(character, item)
    end
end

-- Solar modules ----------------------------------------------------------------------------------

-- OnTest of Repair Cracked Module: the module must be below what the repair brings it to.
function Recipes.isModuleBelowRepairCap(item, character)
    local cap = MODULE_REPAIR_CAP[item:getFullType()]
    return cap == nil or item:getCondition() < cap
end

function Recipes.repairModule(craftRecipeData, character)
    local module = firstInput(craftRecipeData, function(item)
        return MODULE_REPAIR_CAP[item:getFullType()] ~= nil
    end)
    local cap = MODULE_REPAIR_CAP[module:getFullType()]
    Wear.setCondition(module, math.min(cap, module:getCondition() + MODULE_REPAIR))
    sendItemStats(module)
end

-- OnTest of Take Apart Shattered Module: a module that still makes power stays whole.
function Recipes.isShatteredModule(item, character)
    return item:getFullType() ~= FACTORY_MODULE or item:getCondition() <= 0
end

-- Batteries --------------------------------------------------------------------------------------

local function inputBattery(craftRecipeData)
    return firstInput(craftRecipeData, Battery.isBattery)
end

-- OnTest of Service Battery.
function Recipes.canServiceBattery(item, character)
    return not Battery.isBattery(item) or item:getCondition() < SERVICE_CAP
end

function Recipes.serviceBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    Wear.setCondition(battery, math.min(SERVICE_CAP, battery:getCondition() + SERVICE_REPAIR))
    sendItemStats(battery)
end

-- OnTest of Recondition Battery.
function Recipes.canReconditionBattery(item, character)
    return not Battery.isBattery(item) or item:getCondition() < RECONDITION_CONDITION
end

function Recipes.reconditionBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    Wear.setCondition(battery, RECONDITION_CONDITION)
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
    addToInventory(character, battery)
end

return Recipes
