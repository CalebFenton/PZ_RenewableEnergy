require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/PowerBank/PowerBank"

-- Item and crafting tests. See RenewableEnergyTestLib.lua for how the runner works.

local test = RenewableEnergyTest.test
local expect, expectNear, player = RenewableEnergyTest.expect, RenewableEnergyTest.expectNear, RenewableEnergyTest.player
local MODULES_KEY = RenewableEnergy.PowerBank.MODULES

-- Every recipe Recipes.txt defines. Listed rather than read from the game, so that one that
-- fails to load is missed.
local RECIPES = {
    "RenewableEnergy_MakeBatteryBoxWood", "RenewableEnergy_MakeBatteryBoxMetal",
    "RenewableEnergy_BuildBatteryRackWood", "RenewableEnergy_BuildBatteryRackMetal",
    "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy_BuildBatteryBankMetal",
    "RenewableEnergy_MakeSolarFlat", "RenewableEnergy_MakeSolarWallWood", "RenewableEnergy_MakeSolarWallMetal",
    "RenewableEnergy_MakeSolarRackWood", "RenewableEnergy_MakeSolarRackMetal",
    "RenewableEnergy_UnmountSolarFlat", "RenewableEnergy_UnmountSolarWallWood", "RenewableEnergy_UnmountSolarWallMetal",
    "RenewableEnergy_UnmountSolarRackWood", "RenewableEnergy_UnmountSolarRackMetal",
    "RenewableEnergy_RepairCrackedModule", "RenewableEnergy_MakeHomemadeSolarModule",
    "RenewableEnergy_TakeApartCalculator", "RenewableEnergy_TakeApartSolarGardenLight",
    "RenewableEnergy_TakeApartSolarCellCharger", "RenewableEnergy_TakeApartSolarMaintainer",
    "RenewableEnergy_TakeApartShatteredModule",
    "RenewableEnergy_ServiceBattery", "RenewableEnergy_ReconditionBattery",
    "RenewableEnergy_StripCarBattery", "RenewableEnergy_StripDeepCycleBattery", "RenewableEnergy_StripL16Battery",
    "RenewableEnergy_RecastBatteryPlates",
    "RenewableEnergy_RebuildCarBattery", "RenewableEnergy_RebuildDeepCycleBattery", "RenewableEnergy_RebuildL16Battery",
    "RenewableEnergy_MakeBatteryPlatePattern", "RenewableEnergy_PressBatteryPlateMold", "RenewableEnergy_FireBatteryPlateMold",
    "RenewableEnergy_MakeChargeController", "RenewableEnergy_MakeSolarFailsafe",
}

local MAGAZINES = { "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2" }

-- Items -----------------------------------------------------------------------------------------

-- The crafting window and the inventory draw an item's script texture. A moveable without an
-- Icon has none, and the window drew a black square for it.
test("renewable_energy_items_have_icons", {
    validate = function()
        local question = getTexture("media/inventory/Question_On.png")
        for _, fullType in ipairs(RenewableEnergyDebug.ITEMS) do
            local script = getScriptManager():getItem(fullType)
            local texture = script and script:getNormalTexture()
            expect(texture ~= nil and texture ~= question, fullType .. " has no icon")
        end
    end,
})

-- A missing ItemName.json entry falls back to the script's DisplayName, and the scripts set none,
-- so to the full type (Translator.getItemNameFromFullType, Item.getDisplayName).
test("renewable_energy_items_have_names", {
    validate = function()
        for _, fullType in ipairs(RenewableEnergyDebug.ITEMS) do
            local item = instanceItem(fullType)
            expect(item ~= nil and item:getDisplayName() ~= fullType, fullType .. " has no name")
        end
    end,
})

-- A homemade module comes out of the box at its cap, 60, and the electrolyte bottle full of acid.
test("renewable_energy_new_items_start_right", {
    validate = function()
        local module = instanceItem("RenewableEnergy.HomemadeSolarModule")
        expect(module:getCondition() == 60 and module:getConditionMax() == 60,
            "a new homemade module is at " .. module:getCondition() .. " of " .. module:getConditionMax())
        local bottle = instanceItem("RenewableEnergy.BatteryElectrolyte"):getFluidContainer()
        expect(bottle ~= nil and math.abs(bottle:getSpecificFluidAmount(Fluid.Acid) - 1) < 0.01,
            "a new electrolyte bottle holds " .. tostring(bottle and bottle:getSpecificFluidAmount(Fluid.Acid)) .. " L of acid")
    end,
})

-- Recipes -------------------------------------------------------------------------------------

-- Research and the magazine's recipe list look a recipe up by its bare name, which resolves only
-- in module Base.
test("renewable_energy_recipes_resolve_in_base", {
    validate = function()
        for _, name in ipairs(RECIPES) do
            local recipe = getScriptManager():getCraftRecipe(name)
            if expect(recipe ~= nil, name .. " does not resolve by its bare name") then
                expect(recipe:getModule():getName() == "Base", name .. " is in module " .. recipe:getModule():getName())
            end
        end
        expect(#RenewableEnergyDebug.recipeNames() == #RECIPES,
            #RenewableEnergyDebug.recipeNames() .. " RenewableEnergy_ recipes loaded, expected " .. #RECIPES)
    end,
})

-- An input or output naming an item that doesn't exist makes the recipe impossible, silently.
test("renewable_energy_recipe_items_exist", {
    validate = function()
        for _, name in ipairs(RECIPES) do
            local recipe = getScriptManager():getCraftRecipe(name)
            local inputs = recipe and recipe:getInputs()
            for i = 0, inputs and inputs:size() - 1 or -1 do
                local input = inputs:get(i)
                if input:getResourceType() == ResourceType.Item then
                    expect(input:getPossibleInputItems():size() > 0, name .. ": no item fits " .. input:getOriginalLine())
                end
            end
            local outputs = recipe and recipe:getOutputs()
            for i = 0, outputs and outputs:size() - 1 or -1 do
                local output = outputs:get(i)
                if output:getResourceType() == ResourceType.Item then
                    expect(output:getPossibleResultItems():size() > 0, name .. ": an output is no item")
                end
            end
        end
    end,
})

-- Expanding "Possible Items" for a recipe input in the crafting window reads the icon of every
-- item the input accepts (ISCraftInventoryPanel.populate), and throws for one without.
test("renewable_energy_recipe_inputs_have_icons", {
    validate = function()
        for _, name in ipairs(RECIPES) do
            local recipe = getScriptManager():getCraftRecipe(name)
            local inputs = recipe and recipe:getInputs()
            for i = 0, inputs and inputs:size() - 1 or -1 do
                local input = inputs:get(i)
                local possible = input:getResourceType() == ResourceType.Item and input:getPossibleInputItems()
                for j = 0, possible and possible:size() - 1 or -1 do
                    local item = possible:get(j)
                    expect(item:getNormalTexture() ~= nil, name .. " accepts " .. item:getFullName() .. ", which has no icon")
                end
            end
        end
    end,
})

-- Learning ------------------------------------------------------------------------------------

test("renewable_energy_magazines_teach_existing_recipes", {
    validate = function()
        for _, fullType in ipairs(MAGAZINES) do
            local learned = getScriptManager():getItem(fullType):getLearnedRecipes()
            expect(learned:size() > 0, fullType .. " teaches nothing")
            for i = 0, learned:size() - 1 do
                local recipe = getScriptManager():getCraftRecipe(learned:get(i))
                if expect(recipe ~= nil, fullType .. " teaches " .. learned:get(i) .. ", which does not exist") then
                    expect(recipe:needToBeLearn(), fullType .. " teaches " .. learned:get(i) .. ", which needs no learning")
                end
            end
        end
    end,
})

-- Reading a magazine through the vanilla action teaches its recipes.
for _, magazine in ipairs(MAGAZINES) do
    test("renewable_energy_read_" .. string.lower(string.match(magazine, "%.(.+)")), {
        run = function()
            local p = player()
            RenewableEnergyDebug.forgetRecipes(p)
            ISTimedActionQueue.add(ISReadABook:new(p, p:getInventory():AddItem(magazine)))
        end,
        validate = function()
            local learned = getScriptManager():getItem(magazine):getLearnedRecipes()
            for i = 0, learned:size() - 1 do
                expect(player():isRecipeActuallyKnown(learned:get(i)), "reading did not teach " .. learned:get(i))
            end
        end,
        cleanup = function()
            RenewableEnergyDebug.learnRecipes(player())
        end,
    })
end

-- Researching found hardware teaches what to build from it: the item's own recipe
-- (OutputMapper) and its ResearchableRecipes.
local RESEARCH = {
    ["RenewableEnergy.SolarModule"] = {
        "RenewableEnergy_MakeSolarFlat", "RenewableEnergy_MakeSolarWallWood", "RenewableEnergy_MakeSolarWallMetal",
        "RenewableEnergy_MakeSolarRackWood", "RenewableEnergy_MakeSolarRackMetal",
    },
    ["RenewableEnergy.PlugInInverter"] = { "RenewableEnergy_MakeBatteryBoxWood", "RenewableEnergy_MakeBatteryBoxMetal" },
    ["RenewableEnergy.PowerInverter"] = { "RenewableEnergy_BuildBatteryRackWood", "RenewableEnergy_BuildBatteryRackMetal" },
    ["RenewableEnergy.InverterCharger"] = { "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy_BuildBatteryBankMetal" },
    ["RenewableEnergy.ChargeController"] = { "RenewableEnergy_MakeChargeController" },
}

-- Skills high enough for every recipe: research asks for two thirds of a recipe's highest level.
local function skilled(p)
    p:setPerkLevelDebug(Perks.Electricity, 10)
    p:setPerkLevelDebug(Perks.MetalWelding, 10)
    p:setPerkLevelDebug(Perks.Woodwork, 10)
end

for fullType, recipes in pairs(RESEARCH) do
    test("renewable_energy_research_" .. string.lower(string.match(fullType, "%.(.+)")), {
        run = function()
            local p = player()
            RenewableEnergyDebug.forgetRecipes(p)
            skilled(p)
            ISTimedActionQueue.add(ISResearchRecipe:new(p, p:getInventory():AddItem(fullType)))
        end,
        validate = function()
            for _, recipe in ipairs(recipes) do
                expect(player():isRecipeActuallyKnown(recipe), "researching " .. fullType .. " did not teach " .. recipe)
            end
        end,
        cleanup = function()
            RenewableEnergyDebug.learnRecipes(player())
        end,
    })
end

-- Crafting ------------------------------------------------------------------------------------

-- A craft test (RenewableEnergyTest.craftTest) by a character skilled enough for every recipe.
local function craftTest(name, spec)
    local setup = spec.setup
    spec.setup = function(self)
        skilled(player())
        if setup then
            setup(self)
        end
    end
    RenewableEnergyTest.craftTest(name, spec)
end

local function first(fullType)
    return player():getInventory():getFirstTypeRecurse(fullType)
end

-- Every container the craft would take fluid from or pour into, emptied and filled with
-- `liters` of `fluid` (nil leaves them empty).
local function refill(fullType, fluid, liters)
    local items = player():getInventory():getAllTypeRecurse(fullType)
    for i = 0, items:size() - 1 do
        local container = items:get(i):getFluidContainer()
        container:Empty()
        if fluid then
            container:addFluid(fluid, liters)
        end
    end
end

-- Litres of `fluid` in all the character's containers.
local function fluidCarried(fluid)
    local liters = 0
    local items = player():getInventory():getItems()
    for i = 0, items:size() - 1 do
        local container = items:get(i):getFluidContainer()
        if container then
            liters = liters + container:getSpecificFluidAmount(fluid)
        end
    end
    return liters
end

-- Storage tiers: each recipe makes its own tier and material.
local STORAGE = {
    { "RenewableEnergy_MakeBatteryBoxWood", "Base.Plank", "RenewableEnergy.BatteryBoxWood" },
    { "RenewableEnergy_MakeBatteryBoxMetal", "Base.SmallSheetMetal", "RenewableEnergy.BatteryBoxMetal" },
    { "RenewableEnergy_BuildBatteryRackWood", "Base.Plank", "RenewableEnergy.BatteryRackWood" },
    { "RenewableEnergy_BuildBatteryRackMetal", "Base.SmallSheetMetal", "RenewableEnergy.BatteryRackMetal" },
    { "RenewableEnergy_BuildBatteryBankWood", "Base.Plank", "RenewableEnergy.BatteryBankWood" },
    { "RenewableEnergy_BuildBatteryBankMetal", "Base.SheetMetal", "RenewableEnergy.BatteryBankMetal" },
}
-- A craft whose output weighs more than the character can carry drops it at their feet
-- (Actions.addOrDropItem): counts those, and clears them away.
local function takeDroppedAround(fullType)
    local here, count = player():getCurrentSquare(), 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = here and getCell():getGridSquare(here:getX() + dx, here:getY() + dy, here:getZ())
            local objects = square and square:getWorldObjects()
            for i = (objects and objects:size() or 0) - 1, 0, -1 do
                if objects:get(i):getItem():getFullType() == fullType then
                    count = count + 1
                    square:removeWorldObject(objects:get(i))
                end
            end
        end
    end
    return count
end

for _, entry in ipairs(STORAGE) do
    local recipe, material, result = entry[1], entry[2], entry[3]
    craftTest("renewable_energy_craft_" .. string.lower(string.match(result, "%.(.+)")), {
        recipe = recipe,
        from = material,
        counts = { [material] = 0 },
        validate = function()
            local made = player():getInventory():getCountTypeRecurse(result) + takeDroppedAround(result)
            expect(made == 1, made .. " " .. result .. " made, expected 1")
        end,
    })
end

-- Mounts remember each module's type and condition.
local function expectModules(mount, expected)
    local modules = mount and mount:getModData()[MODULES_KEY]
    if not expect(modules ~= nil and #modules == #expected,
        "the mount holds " .. tostring(modules and #modules) .. " modules, expected " .. #expected) then
        return
    end
    for i, want in ipairs(expected) do
        local got = modules[i]
        expect(got.type == want.type and got.condition == want.condition,
            "module " .. i .. " is " .. tostring(got.type) .. " at " .. tostring(got.condition)
            .. ", expected " .. want.type .. " at " .. want.condition)
    end
end

local MOUNTS = {
    { "RenewableEnergy_MakeSolarFlat", "RenewableEnergy.SolarFlat", 1 },
    { "RenewableEnergy_MakeSolarWallWood", "RenewableEnergy.SolarWallWood", 1 },
    { "RenewableEnergy_MakeSolarWallMetal", "RenewableEnergy.SolarWallMetal", 1 },
    { "RenewableEnergy_MakeSolarRackWood", "RenewableEnergy.SolarRackWood", 2 },
    { "RenewableEnergy_MakeSolarRackMetal", "RenewableEnergy.SolarRackMetal", 2 },
}
for _, entry in ipairs(MOUNTS) do
    local recipe, mount, count = entry[1], entry[2], entry[3]
    craftTest("renewable_energy_craft_" .. string.lower(string.match(mount, "%.(.+)")) .. "_keeps_module_condition", {
        recipe = recipe,
        from = "RenewableEnergy.SolarModule",
        prefer = { "RenewableEnergy.SolarModule" },
        setup = function()
            first("RenewableEnergy.SolarModule"):setCondition(72)
            if count == 2 then
                local inventory = player():getInventory()
                inventory:Remove(inventory:getAllTypeRecurse("RenewableEnergy.SolarModule"):get(1))
                inventory:AddItem("RenewableEnergy.HomemadeSolarModule"):setCondition(41)
            end
        end,
        counts = { ["RenewableEnergy.SolarModule"] = 0, ["RenewableEnergy.HomemadeSolarModule"] = 0, [mount] = 1 },
        validate = function()
            local expected = { { type = "RenewableEnergy.SolarModule", condition = 72 } }
            if count == 2 then
                table.insert(expected, { type = "RenewableEnergy.HomemadeSolarModule", condition = 41 })
            end
            local modules = first(mount) and first(mount):getModData()[MODULES_KEY]
            -- Which input the craft lists first is its own business.
            if modules and #modules == 2 and modules[1].type ~= expected[1].type then
                expected[1], expected[2] = expected[2], expected[1]
            end
            expectModules(first(mount), expected)
        end,
    })
end

-- Unmounting gives back each module as the type and at the condition it went in.
local UNMOUNTS = {
    { "RenewableEnergy_UnmountSolarFlat", "RenewableEnergy.SolarFlat" },
    { "RenewableEnergy_UnmountSolarWallWood", "RenewableEnergy.SolarWallWood" },
    { "RenewableEnergy_UnmountSolarWallMetal", "RenewableEnergy.SolarWallMetal" },
    { "RenewableEnergy_UnmountSolarRackWood", "RenewableEnergy.SolarRackWood" },
    { "RenewableEnergy_UnmountSolarRackMetal", "RenewableEnergy.SolarRackMetal" },
}
for _, entry in ipairs(UNMOUNTS) do
    local recipe, mount = entry[1], entry[2]
    local rack = mount:find("Rack") ~= nil
    craftTest("renewable_energy_craft_" .. string.lower((recipe:gsub("RenewableEnergy_", ""))) .. "_returns_modules", {
        recipe = recipe,
        from = mount,
        setup = function()
            local modules = { { type = "RenewableEnergy.HomemadeSolarModule", condition = 41 } }
            if rack then
                table.insert(modules, { type = "RenewableEnergy.SolarModule", condition = 12 })
            end
            first(mount):getModData()[MODULES_KEY] = modules
        end,
        counts = {
            [mount] = 0,
            ["RenewableEnergy.HomemadeSolarModule"] = 1,
            ["RenewableEnergy.SolarModule"] = rack and 1 or 0,
        },
        validate = function()
            local homemade = first("RenewableEnergy.HomemadeSolarModule")
            expect(homemade == nil or homemade:getCondition() == 41,
                "the homemade module came back at " .. tostring(homemade and homemade:getCondition()))
            local factory = first("RenewableEnergy.SolarModule")
            expect(factory == nil or factory:getCondition() == 12,
                "the factory module came back at " .. tostring(factory and factory:getCondition()))
        end,
    })
end

-- A mount nobody wrote modules to, as debug and older spawns make, holds new factory modules.
craftTest("renewable_energy_craft_unmount_unrecorded_rack", {
    recipe = "RenewableEnergy_UnmountSolarRackMetal",
    from = "RenewableEnergy.SolarRackMetal",
    counts = { ["RenewableEnergy.SolarRackMetal"] = 0, ["RenewableEnergy.SolarModule"] = 2, ["Base.MetalPipe"] = 4 },
})

-- Repair Cracked Module: +30, up to 80 for a factory module and 60 for a homemade one, and
-- refused at the cap, with the module untouched.
local MODULE_REPAIRS = {
    { "factory", "RenewableEnergy.SolarModule", 40, 70 },
    { "factory_capped", "RenewableEnergy.SolarModule", 65, 80 },
    { "homemade_capped", "RenewableEnergy.HomemadeSolarModule", 45, 60 },
    { "factory_at_cap_refused", "RenewableEnergy.SolarModule", 80, 80, true },
    { "homemade_at_cap_refused", "RenewableEnergy.HomemadeSolarModule", 60, 60, true },
}
for _, entry in ipairs(MODULE_REPAIRS) do
    local label, module, before, after, refused = entry[1], entry[2], entry[3], entry[4], entry[5]
    craftTest("renewable_energy_craft_repair_module_" .. label, {
        recipe = "RenewableEnergy_RepairCrackedModule",
        from = module,
        prefer = { module },
        setup = function()
            first(module):setCondition(before)
        end,
        counts = { [module] = 1, ["Base.GlassPanel"] = refused and 1 or 0 },
        validate = function(self)
            local item = first(module)
            expect(item and item:getCondition() == after,
                "the module is at " .. tostring(item and item:getCondition()) .. ", expected " .. after)
            if refused then
                expect(self.refusal ~= nil, "the game would start the repair")
            end
        end,
    })
end

craftTest("renewable_energy_craft_homemade_module", {
    recipe = "RenewableEnergy_MakeHomemadeSolarModule",
    from = "RenewableEnergy.SolarCells",
    counts = { ["RenewableEnergy.SolarCells"] = 0, ["RenewableEnergy.HomemadeSolarModule"] = 1 },
    validate = function()
        local module = first("RenewableEnergy.HomemadeSolarModule")
        expect(module and module:getCondition() == 60, "the homemade module is at " .. tostring(module and module:getCondition()))
    end,
})

-- Taking things apart for their cells.
local TAKE_APART = {
    { "RenewableEnergy_TakeApartCalculator", "Base.Calculator", 1, { ["Base.ElectronicsScrap"] = 1 } },
    { "RenewableEnergy_TakeApartSolarGardenLight", "RenewableEnergy.SolarGardenLight", 2 },
    { "RenewableEnergy_TakeApartSolarCellCharger", "RenewableEnergy.SolarCellCharger", 4 },
    { "RenewableEnergy_TakeApartSolarMaintainer", "RenewableEnergy.SolarMaintainer", 6 },
}
for _, entry in ipairs(TAKE_APART) do
    local recipe, input, cells = entry[1], entry[2], entry[3]
    local counts = { [input] = 0, ["RenewableEnergy.SolarCells"] = cells }
    for fullType, count in pairs(entry[4] or {}) do
        counts[fullType] = count
    end
    craftTest("renewable_energy_craft_" .. string.lower((recipe:gsub("RenewableEnergy_", ""))), {
        recipe = recipe,
        from = input,
        counts = counts,
    })
end

craftTest("renewable_energy_craft_take_apart_shattered_module", {
    recipe = "RenewableEnergy_TakeApartShatteredModule",
    from = "RenewableEnergy.SolarModule",
    setup = function()
        first("RenewableEnergy.SolarModule"):setCondition(0)
    end,
    counts = { ["RenewableEnergy.SolarModule"] = 0, ["RenewableEnergy.SolarCells"] = 12 },
})

-- A module that still makes power is worth more whole.
craftTest("renewable_energy_craft_take_apart_working_module_refused", {
    recipe = "RenewableEnergy_TakeApartShatteredModule",
    from = "RenewableEnergy.SolarModule",
    setup = function()
        first("RenewableEnergy.SolarModule"):setCondition(20)
    end,
    counts = { ["RenewableEnergy.SolarModule"] = 1, ["RenewableEnergy.SolarCells"] = 0 },
    validate = function(self)
        expect(self.refusal ~= nil, "the game would take a working module apart")
    end,
})

-- Battery repairs ------------------------------------------------------------------------------
-- Each repair on a car battery that starts at `before` condition and 70% charge.

local CAR_BATTERY = "Base.CarBattery2"
local BATTERY_REPAIRS = {
    { "service", "RenewableEnergy_ServiceBattery", 30, 40, 0.7 },
    { "service_capped", "RenewableEnergy_ServiceBattery", 55, 60, 0.7 },
    { "service_at_cap_refused", "RenewableEnergy_ServiceBattery", 60, 60, 0.7, true },
    { "recondition", "RenewableEnergy_ReconditionBattery", 30, 85, 0 },
    { "recondition_above_refused", "RenewableEnergy_ReconditionBattery", 90, 90, 0.7, true },
}
for _, entry in ipairs(BATTERY_REPAIRS) do
    local label, recipe, before, after, charge, refused = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
    craftTest("renewable_energy_craft_" .. label .. "_battery", {
        recipe = recipe,
        from = CAR_BATTERY,
        prefer = { CAR_BATTERY, "RenewableEnergy.BatteryElectrolyte" },
        setup = function()
            local battery = first(CAR_BATTERY)
            battery:setCondition(before)
            battery:setCurrentUsesFloat(0.7)
            refill("RenewableEnergy.BatteryElectrolyte", "Water", 1)
        end,
        counts = { [CAR_BATTERY] = 1 },
        validate = function(self)
            local battery = first(CAR_BATTERY)
            if not expect(battery ~= nil, "the battery is gone") then return end
            expect(battery:getCondition() == after, "the battery is at " .. battery:getCondition() .. ", expected " .. after)
            expectNear("the battery's charge", battery:getCurrentUsesFloat(), charge, 0.001)
            if refused then
                expect(self.refusal ~= nil, "the game would start the repair")
            end
        end,
    })
end

-- Stripping a battery and rebuilding it from its own case, with the furnace's recast stood in
-- for: the battery comes back new and empty, and its acid goes out and back in.

-- Runs `fn` once the actions queued before it are done.
local Step = ISBaseTimedAction:derive("RenewableEnergyTestStep")

function Step:new(character, fn)
    local o = ISBaseTimedAction.new(self, character)
    o.fn = fn
    o.maxTime = 1
    return o
end

function Step:isValid()
    return true
end

function Step:perform()
    self.fn()
    ISBaseTimedAction.perform(self)
end

local function queueCraft(self, name, fromType)
    local recipe = getScriptManager():getCraftRecipe(name)
    local from = first(fromType)
    if not (recipe and from) then
        self.refusal = (self.refusal or "") .. " nothing to start " .. name
        return
    end
    local refusal = RenewableEnergyTest.craftRefusal(recipe, from)
    if refusal then
        self.refusal = (self.refusal or "") .. " " .. name .. ": " .. refusal
    end
    ISInventoryPaneContextMenu.OnNewCraft(from, recipe, player():getPlayerNum(), false)
end

local REBUILDS = {
    { battery = "Base.CarBattery2", case = "RenewableEnergy.CarBatteryCase", plates = 1,
      strip = "RenewableEnergy_StripCarBattery", rebuild = "RenewableEnergy_RebuildCarBattery" },
    { battery = "RenewableEnergy.DeepCycleBattery", case = "RenewableEnergy.DeepCycleBatteryCase", plates = 2,
      strip = "RenewableEnergy_StripDeepCycleBattery", rebuild = "RenewableEnergy_RebuildDeepCycleBattery" },
    { battery = "RenewableEnergy.L16Battery", case = "RenewableEnergy.L16BatteryCase", plates = 3,
      strip = "RenewableEnergy_StripL16Battery", rebuild = "RenewableEnergy_RebuildL16Battery" },
}
for _, chain in ipairs(REBUILDS) do
    test("renewable_energy_craft_rebuild_" .. string.lower(string.match(chain.battery, "%.(.+)")), {
        run = function(self)
            local p = player()
            RenewableEnergyDebug.setupPlayer(p)
            skilled(p)
            local inventory = p:getInventory()
            inventory:AddItem("Base.Wrench")
            inventory:AddItem("Base.Gloves_Dish")
            local battery = inventory:AddItem(chain.battery)
            battery:setCondition(20)
            battery:setCurrentUsesFloat(0.6)
            -- One empty litre bottle per litre of acid, and one with the water.
            for _ = 1, chain.plates do
                inventory:AddItem("RenewableEnergy.BatteryElectrolyte"):getFluidContainer():Empty()
            end
            queueCraft(self, chain.strip, chain.battery)
            ISTimedActionQueue.add(Step:new(p, function()
                self.stripped = {
                    case = inventory:getCountTypeRecurse(chain.case),
                    worn = inventory:getCountTypeRecurse("RenewableEnergy.WornBatteryPlates"),
                    acid = fluidCarried(Fluid.Acid),
                    batteries = inventory:getCountTypeRecurse(chain.battery),
                }
                inventory:RemoveAll("RenewableEnergy.WornBatteryPlates")
                inventory:AddItems("RenewableEnergy.BatteryPlates", chain.plates)
                inventory:AddItem("Base.WaterBottle"):getFluidContainer():Empty()
                refill("Base.WaterBottle", "Water", 1)
                queueCraft(self, chain.rebuild, chain.case)
            end))
        end,
        validate = function(self)
            local s = self.stripped
            if not expect(s ~= nil, "the strip step never ran" .. (self.refusal or "")) then return end
            expect(s.batteries == 0 and s.case == 1 and s.worn == chain.plates,
                "stripping left " .. s.batteries .. " batteries, " .. s.case .. " cases, " .. s.worn .. " worn plates")
            expectNear("acid poured out by stripping", s.acid, chain.plates, 0.01)
            local inventory = player():getInventory()
            local battery = first(chain.battery)
            if expect(battery ~= nil, "no " .. chain.battery .. " was rebuilt;" .. (self.refusal or "")) then
                expect(battery:getCondition() == 100, "the rebuilt battery is at " .. battery:getCondition())
                expectNear("the rebuilt battery's charge", battery:getCurrentUsesFloat(), 0, 0.001)
            end
            expect(inventory:getCountTypeRecurse(chain.case) == 0, "the case is still there")
            expect(inventory:getCountTypeRecurse("RenewableEnergy.BatteryPlates") == 0, "plates are left over")
            expectNear("acid left after rebuilding", fluidCarried(Fluid.Acid), 0, 0.01)
        end,
    })
end
