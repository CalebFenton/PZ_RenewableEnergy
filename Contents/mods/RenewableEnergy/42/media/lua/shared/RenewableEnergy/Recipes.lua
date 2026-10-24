require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Gadgets/VehicleBattery"

-- Callbacks of the mod's craftRecipes. Shared: OnTest runs wherever the craft is checked, and every
-- side resolves all of a recipe's Lua calls when it sets up a craft (CraftRecipeData). OnCreate runs
-- once on the authority, after the outputs were already sent to an MP client, so item changes are
-- re-sent: outputs (in the inventory) with syncItemFields, inputs (maybe in a nearby container or on
-- the floor) with sendItemStats.
--
-- OnTest is asked about every candidate item of every input, tools included, so each one
-- answers only for the items it is about and lets the rest through.
RenewableEnergy = RenewableEnergy or {}
local Recipes = {}
RenewableEnergy.Recipes = Recipes

local Specs, Battery, Wear, PowerBank = RenewableEnergy.Specs, RenewableEnergy.Battery, RenewableEnergy.Wear, RenewableEnergy.PowerBank
local Sources = RenewableEnergy.Sources
local SolarGardenLight, VehicleBattery = RenewableEnergy.SolarGardenLight, RenewableEnergy.VehicleBattery
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

-- Each patch-up repair counts on vanilla's per-item repair count ("Repaired: Nx") and lowers the
-- most the next can bring the item to by this step, so patching runs out. Remaking it with fresh
-- parts (Rebuild Battery, Reglaze Module) starts the count again.
Recipes.REPAIR_LIMIT_STEP = 10

-- Seal Cracked Module (RenewableEnergy_RepairCrackedModule): condition it adds, and the most a
-- first seal brings each module type to. The caps stay below Specs.crackLooks.lightBelow of the
-- type's ConditionMax, and a first seal's at or above heavyBelow: sealed glass is still cracked
-- glass, and at best shows light cracks (RenewableEnergy.crackLookOf).
Recipes.MODULE_REPAIR = 20
Recipes.MODULE_REPAIR_CAP = {
    [Specs.factoryModule] = 55,
    ["RenewableEnergy.HomemadeSolarModule"] = 40,
}

-- Reglaze Module's new glass, as shares of the module's ConditionMax: a module whose cracks stayed
-- in the glass comes back as new; one cracked heavily (RenewableEnergy.crackLookOf), or sealed,
-- since a crack that needed sealing ran deep enough to let the weather in, keeps the cells cracked
-- under it. Both shares stay at or above Specs.crackLooks.lightBelow, so new glass shows whole.
Recipes.REGLAZE = { glassOnly = 1, cellsCracked = 0.9 }

--- The condition Reglaze Module brings a module of `fullType` at `condition`, sealed `repaired`
--- times, to; nil for a type that is no module.
function Recipes.reglazedCondition(fullType, condition, repaired)
    if not Specs.modules[fullType] then
        return nil
    end
    local deep = (repaired or 0) > 0 or RenewableEnergy.crackLookOf(fullType, condition) == "heavy"
    local share = deep and Recipes.REGLAZE.cellsCracked or Recipes.REGLAZE.glassOnly
    return math.floor(RenewableEnergy.conditionMaxOf(fullType) * share)
end

-- Service Battery adds a little to a tired battery; Recondition brings it to its repair limit.
Recipes.SERVICE_REPAIR = 10
Recipes.REPAIR_LIMIT = 85

-- The most a repair can bring a battery repaired this many times to.
function Recipes.repairLimit(timesRepaired)
    return Recipes.REPAIR_LIMIT - Recipes.REPAIR_LIMIT_STEP * timesRepaired
end

-- The most Seal Cracked Module can bring a module of `fullType`, sealed `repaired` times, to; nil
-- for a type that is no module.
local function sealCap(fullType, repaired)
    local cap = Recipes.MODULE_REPAIR_CAP[fullType]
    return cap and cap - Recipes.REPAIR_LIMIT_STEP * (repaired or 0)
end

-- The most Seal Cracked Module can bring `module` to, or nil for an item that is no module.
function Recipes.sealLimit(module)
    return sealCap(module:getFullType(), module:getHaveBeenRepaired())
end

--- Whether Seal Cracked Module can help the module record `module` (PowerBank.moduleRecord).
function Recipes.canSealRecord(module)
    local limit = sealCap(module.type, module.repaired)
    return limit ~= nil and module.condition < limit
end

--- The placed panel's module records (PowerBank.modulesOf), or nil for an object that is no panel.
function Recipes.panelModules(panel)
    local kind = Sources.kindOf(panel)
    return Sources.familyOf(kind) == "panel" and PowerBank.modulesOf(panel, kind) or nil
end

--- The module in `slot` of the placed panel `panel` if Seal Cracked Module can help it, else nil;
--- second, the panel's whole list of module records it was read from.
function Recipes.sealableModule(panel, slot)
    local modules = Recipes.panelModules(panel)
    local module = modules and type(slot) == "number" and modules[slot]
    if module and Recipes.canSealRecord(module) then
        return module, modules
    end
    return nil
end

--- Seals the module record `module` of a placed panel as Seal Cracked Module seals one in hand.
function Recipes.sealRecord(module)
    module.condition = math.min(sealCap(module.type, module.repaired), module.condition + Recipes.MODULE_REPAIR)
    module.repaired = (module.repaired or 0) + 1
end

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
    local mount = firstInput(craftRecipeData, isMount)
    if not mount then
        return
    end
    for _, module in ipairs(PowerBank.modulesOf(mount, Recipes.MOUNTS[mount:getFullType()].kind)) do
        local item = instanceItem(module.type)
        Wear.setCondition(item, module.condition)
        PowerBank.markModule(item, module)
        RenewableEnergy.giveItems(character, item)
    end
end

-- OnTest of Seal Cracked Module: the module must be below what the seal brings it to.
function Recipes.isModuleBelowRepairCap(item, character)
    local limit = Recipes.sealLimit(item)
    return limit == nil or item:getCondition() < limit
end

--- What Seal Cracked Module brings the module's condition to.
function Recipes.repairedCondition(module)
    return math.min(Recipes.sealLimit(module), module:getCondition() + Recipes.MODULE_REPAIR)
end

-- OnCreate of Seal Cracked Module.
function Recipes.repairModule(craftRecipeData, character)
    local module = firstInput(craftRecipeData, function(item)
        return Recipes.MODULE_REPAIR_CAP[item:getFullType()] ~= nil
    end)
    Wear.setCondition(module, Recipes.repairedCondition(module))
    countRepair(module)
end

-- What Reglaze Module brings the module item `item` to (Recipes.reglazedCondition), or nil.
local function reglazedItem(item)
    return Recipes.reglazedCondition(item:getFullType(), item:getCondition(), item:getHaveBeenRepaired())
end

-- OnTest of Reglaze Module: the module must be below what new glass brings it to.
function Recipes.isModuleBelowReglaze(item, character)
    local reglazed = reglazedItem(item)
    return reglazed == nil or item:getCondition() < reglazed
end

-- OnCreate of Reglaze Module: new glass, so the seals on the old no longer count.
function Recipes.reglazeModule(craftRecipeData, character)
    local module = firstInput(craftRecipeData, isModule)
    Wear.setCondition(module, reglazedItem(module))
    setRepairs(module, 0)
end

-- Seal Cracked Panel seals a module still on the arrow board trailer, and Seal Cracked Module on a
-- placed panel one still on its mount, the way Seal Cracked Module seals one in hand. They read the
-- recipe's inputs, skill, time and XP from the recipe itself, so they can't drift apart; the module
-- input is the panel. Reglazing isn't offered in place: the module comes off to be reglazed, as
-- vanilla car glass is replaced, not repaired.
local MODULE_REPAIR_RECIPE = "RenewableEnergy_RepairCrackedModule"
-- Seal Cracked Module and its glue twin (Recipes.txt says why there are two), in the order the
-- jobs in place try their inputs: glue first, the commoner tube, keeping epoxy for what only it
-- does, such as vanilla's Fix With Epoxy (recipes_fixing.txt). The twins list the same inputs in
-- the same order but the adhesive.
local MODULE_REPAIR_RECIPES = { "RenewableEnergy_RepairCrackedModuleWithGlue", MODULE_REPAIR_RECIPE }

--- Seal Cracked Module: the recipe the jobs in place need known, and take their skill, time and
--- XP from; its glue twin has the same, and MetaRecipe makes it known with this one.
function Recipes.moduleRepairRecipe()
    return getScriptManager():getCraftRecipe(MODULE_REPAIR_RECIPE)
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

-- The rounding CraftRecipeData.consumeInputFromItems forgives when scaled uses pay an input.
local PAID_TOLERANCE = 1e-5

-- What `recipe` takes of the character's inventory, bags included, but the module: the items that
-- pay its inputs, nil when one is missing, and each input as a need (see panelRepairInputs).
local function recipeInputs(recipe, inventory)
    local inputs = recipe:getInputs()
    local picks, taken, needs, complete = {}, {}, {}, true
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if not isModuleInput(input) then
            local amount = input:getIntAmount()
            local needed = amount
            local candidates = inventory:getAllEvalRecurse(function(item)
                return not taken[item] and RenewableEnergy.notBroken(item) and input:containsItem(item:getScriptItem())
            end)
            for j = 0, candidates:size() - 1 do
                if needed <= PAID_TOLERANCE then break end
                local item = candidates:get(j)
                if instanceof(item, "DrainableComboItem") then
                    -- A line such as [Base.Epoxy;2:Base.Glue] takes more uses of some items.
                    local scale = input:getRelativeScale(item:getFullType())
                    local uses = math.min(item:getCurrentUses(), math.ceil(needed * scale))
                    if uses > 0 then
                        table.insert(picks, { item = item, uses = uses, keep = input:isKeep() })
                        taken[item], needed = true, needed - uses / scale
                    end
                else
                    table.insert(picks, { item = item, keep = input:isKeep(), wear = wearOf(input) })
                    taken[item], needed = true, needed - 1
                end
            end
            local paid = needed <= PAID_TOLERANCE
            table.insert(needs, { kind = "item", input = input, have = paid and amount or math.floor(amount - needed), need = amount })
            complete = complete and paid
        end
    end
    return complete and picks or nil, needs
end

-- Whether two input lines take the same amount of the same items.
local function sameInput(a, b)
    local itemsA, itemsB = a:getPossibleInputItems(), b:getPossibleInputItems()
    if a:getIntAmount() ~= b:getIntAmount() or itemsA:size() ~= itemsB:size() then
        return false
    end
    for i = 0, itemsA:size() - 1 do
        if itemsA:get(i):getFullName() ~= itemsB:get(i):getFullName() then
            return false
        end
    end
    return true
end

--- The inventory items, bags included, that pay for a Seal Cracked Panel's inputs but the
--- module, each as { item, uses, keep, wear }: `uses` the drainable uses it takes (nil for a
--- whole item), `wear` the factor a kept tool's MayDegrade flag gives damageCheck; they pay the
--- first of MODULE_REPAIR_RECIPES the character carries every input of, and are nil when there is
--- none. Second, each of those inputs as a need (RenewableEnergy.firstUnmet), `have` being how many
--- whole units of its amount the items found pay; an input the twins differ in is one need any of
--- theirs meets. Since they differ only in the adhesive, that need is met exactly when a twin is.
--- As CraftRecipeData.consumeInputFromItems and processDestroyAndUsedItems do, several part-used
--- drainables add up to one input, each giving the uses it has until the input is paid.
function Recipes.panelRepairInputs(character)
    local inventory = character:getInventory()
    local paid, byRecipe = nil, {}
    for _, name in ipairs(MODULE_REPAIR_RECIPES) do
        local picks, needs = recipeInputs(getScriptManager():getCraftRecipe(name), inventory)
        paid = paid or picks
        table.insert(byRecipe, needs)
    end
    local needs = {}
    for i, need in ipairs(byRecipe[1]) do
        local options, met, same = {}, false, true
        for _, recipeNeeds in ipairs(byRecipe) do
            local option = recipeNeeds[i]
            table.insert(options, option)
            met = met or option.have >= option.need
            same = same and sameInput(option.input, need.input)
        end
        table.insert(needs, same and need or { kind = "item", anyOf = options, have = met and 1 or 0, need = 1 })
    end
    return paid, needs
end

--- What Seal Cracked Panel takes of `character` (RenewableEnergy.firstUnmet): the recipe
--- known, its skills, and its inputs but the module.
function Recipes.panelRepairNeeds(character)
    local recipe = Recipes.moduleRepairRecipe()
    local needs = { { kind = "recipe", recipe = recipe, have = character:isRecipeKnown(recipe) and 1 or 0, need = 1 } }
    for i = 0, recipe:getRequiredSkillCount() - 1 do
        local skill = recipe:getRequiredSkill(i)
        table.insert(needs, { kind = "skill", perk = skill:getPerk(), have = character:getPerkLevel(skill:getPerk()), need = skill:getLevel() })
    end
    local _, inputs = Recipes.panelRepairInputs(character)
    for _, need in ipairs(inputs) do
        table.insert(needs, need)
    end
    return needs
end

--- Why the character can't do Seal Cracked Panel, or nil when they can: the kind of the first
--- of panelRepairNeeds they are short of.
function Recipes.panelRepairRefusal(character)
    return RenewableEnergy.unmetKind(Recipes.panelRepairNeeds(character))
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

local function inputBattery(craftRecipeData)
    return firstInput(craftRecipeData, Battery.isBattery)
end

local function canRepair(item)
    return not Battery.isBattery(item) or item:getCondition() < Recipes.repairLimit(item:getHaveBeenRepaired())
end

-- OnTest of Service Battery.
function Recipes.canServiceBattery(item, character)
    return canRepair(item)
end

-- OnCreate of Service Battery.
function Recipes.serviceBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    Wear.setCondition(battery, math.min(Recipes.repairLimit(battery:getHaveBeenRepaired()), battery:getCondition() + Recipes.SERVICE_REPAIR))
    countRepair(battery)
end

-- OnTest of Recondition Battery.
function Recipes.canReconditionBattery(item, character)
    return canRepair(item)
end

-- OnCreate of Recondition Battery.
function Recipes.reconditionBattery(craftRecipeData, character)
    local battery = inputBattery(craftRecipeData)
    Wear.setCondition(battery, Recipes.repairLimit(battery:getHaveBeenRepaired()))
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
    local case = firstInput(craftRecipeData, function(item)
        return item:getFullType() == "RenewableEnergy.CarBatteryCase"
    end)
    local battery = instanceItem(case and case:getModData()[CASE_BATTERY_KEY] or VehicleBattery.CAR_BATTERY)
    setRebuilt(battery)
    RenewableEnergy.giveItems(character, battery)
end

-- OnCreate of Make Charge Controller: a new controller has a condition of its own, so a loot
-- refill of the container it is kept in doesn't wear it as if found (Distributions.readyFoundItems).
function Recipes.makeChargeController(craftRecipeData, character)
    local controller = craftRecipeData:getFirstCreatedItem()
    Wear.markOwnCondition(controller)
    controller:syncItemFields()
end

-- A crafted inverter comes out short of its ConditionMax by CRAFTED_SHORTFALL at the recipe's
-- Electricity level, and each level past it makes up CRAFTED_PER_LEVEL, up to the cap: the more
-- skilled the maker, the better the first build.
Recipes.CRAFTED_SHORTFALL = 20
Recipes.CRAFTED_PER_LEVEL = 5

--- The condition an inverter of ConditionMax `conditionMax` comes out at, made at Electricity
--- `level` by a recipe that needs `required`.
function Recipes.craftedInverterCondition(conditionMax, level, required)
    local condition = conditionMax - Recipes.CRAFTED_SHORTFALL + Recipes.CRAFTED_PER_LEVEL * math.max(0, level - required)
    return math.min(conditionMax, condition)
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

-- OnCreate of the inverter recipes: the maker's skill sets the new inverter's condition, and it
-- is marked as having a condition of its own, as a new controller is.
function Recipes.makeInverter(craftRecipeData, character)
    local inverter = craftRecipeData:getFirstCreatedItem()
    Wear.setCondition(inverter, Recipes.craftedInverterCondition(inverter:getConditionMax(),
        character:getPerkLevel(Perks.Electricity), electricityRequired(craftRecipeData:getRecipe())))
    Wear.markOwnCondition(inverter)
    inverter:syncItemFields()
end

-- OnCreate of Take Apart Solar Garden Light: the bulb in it comes out whole.
function Recipes.takeApartGardenLight(craftRecipeData, character)
    local light = firstInput(craftRecipeData, function(item)
        return item:getFullType() == SolarGardenLight.ITEM
    end)
    local bulb = light and SolarGardenLight.getBulb(light)
    if bulb then
        RenewableEnergy.giveItems(character, bulb)
    end
end

-- What a full lantern bottle holds, as a share of a full tank: a one-pound bottle off a twenty.
Recipes.PROPANE_BOTTLE_SHARE = 0.05

-- OnCreate of Refill Propane Bottle, as vanilla's Refill Blow Torch moves its propane
-- (RecipeCodeOnCreate.refillBlowTorch): the new bottle starts as the old one was and takes what
-- it has room for from the tank. The propane moves in whole uses of the tank, the coarser of the
-- two, so that rounding the tank's store can't make propane from nothing.
function Recipes.refillPropaneBottle(craftRecipeData, character)
    local bottle = craftRecipeData:getFirstCreatedItem()
    local old = craftRecipeData:getAllConsumedItems():get(0)
    local tank = craftRecipeData:getAllKeepInputItems():get(0)
    local share, tankUse = Recipes.PROPANE_BOTTLE_SHARE, tank:getUseDelta()
    local room = round((1 - old:getCurrentUsesFloat()) * share / tankUse)
    local taken = math.min(room, tank:getCurrentUses())
    bottle:setCurrentUsesFloat(old:getCurrentUsesFloat() + taken * tankUse / share)
    tank:setCurrentUses(tank:getCurrentUses() - taken)
    bottle:syncItemFields()
    sendItemStats(tank)
end

return Recipes
