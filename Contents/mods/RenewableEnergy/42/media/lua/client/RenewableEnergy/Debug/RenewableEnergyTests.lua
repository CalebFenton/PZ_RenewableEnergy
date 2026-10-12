require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Item and crafting tests. See RenewableEnergyTestLib.lua for how the runner works.

local test, craftTest = RenewableEnergyTest.test, RenewableEnergyTest.craftTest
local expect, player = RenewableEnergyTest.expect, RenewableEnergyTest.player

-- Every recipe Recipes.txt defines. Listed rather than read from the game, so that one that
-- fails to load is missed.
local RECIPES = {
    "RenewableEnergy_MakeBatteryBox",
    "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy_BuildBatteryBankMetal",
    "RenewableEnergy_MakeSolarFlat", "RenewableEnergy_MakeSolarWall", "RenewableEnergy_MakeSolarRack",
    "RenewableEnergy_UnmountSolarFlat", "RenewableEnergy_UnmountSolarWall", "RenewableEnergy_UnmountSolarRack",
    "RenewableEnergy_MakeChargeController", "RenewableEnergy_MakeSolarFailsafe", "RenewableEnergy_MakeSolarModule",
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
test("renewable_energy_read_homestead_power_1", {
    run = function()
        local p = player()
        RenewableEnergyDebug.forgetRecipes(p)
        local magazine = p:getInventory():AddItem("RenewableEnergy.HomesteadPowerMag1")
        ISTimedActionQueue.add(ISReadABook:new(p, magazine))
    end,
    validate = function()
        local learned = getScriptManager():getItem("RenewableEnergy.HomesteadPowerMag1"):getLearnedRecipes()
        for i = 0, learned:size() - 1 do
            expect(player():isRecipeActuallyKnown(learned:get(i)), "reading did not teach " .. learned:get(i))
        end
    end,
    cleanup = function()
        RenewableEnergyDebug.learnRecipes(player())
    end,
})

-- Researching found hardware teaches what to build from it: the item's own recipe
-- (OutputMapper) and its ResearchableRecipes.
local RESEARCH = {
    ["RenewableEnergy.SolarModule"] = { "RenewableEnergy_MakeSolarFlat", "RenewableEnergy_MakeSolarWall", "RenewableEnergy_MakeSolarRack" },
    ["RenewableEnergy.PlugInInverter"] = { "RenewableEnergy_MakeBatteryBox" },
    ["RenewableEnergy.PowerInverter"] = { "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy_BuildBatteryBankMetal" },
    ["RenewableEnergy.ChargeController"] = { "RenewableEnergy_MakeChargeController" },
}

for fullType, recipes in pairs(RESEARCH) do
    test("renewable_energy_research_" .. string.lower(string.match(fullType, "%.(.+)")), {
        run = function()
            local p = player()
            RenewableEnergyDebug.forgetRecipes(p)
            -- Research asks for two thirds of the recipe's highest skill level.
            p:setPerkLevelDebug(Perks.Electricity, 5)
            p:setPerkLevelDebug(Perks.MetalWelding, 2)
            p:setPerkLevelDebug(Perks.Woodwork, 2)
            local item = p:getInventory():AddItem(fullType)
            ISTimedActionQueue.add(ISResearchRecipe:new(p, item))
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

craftTest("renewable_energy_craft_battery_box", {
    recipe = "RenewableEnergy_MakeBatteryBox",
    from = "Base.Plank",
    counts = { ["Base.Plank"] = 0, ["RenewableEnergy.BatteryBox"] = 1 },
})

craftTest("renewable_energy_craft_battery_bank_wood", {
    recipe = "RenewableEnergy_BuildBatteryBankWood",
    from = "Base.Plank",
    counts = { ["Base.Plank"] = 0, ["RenewableEnergy.BatteryBank"] = 1 },
})

craftTest("renewable_energy_craft_battery_bank_metal", {
    recipe = "RenewableEnergy_BuildBatteryBankMetal",
    from = "Base.SmallSheetMetal",
    counts = { ["Base.SmallSheetMetal"] = 0, ["RenewableEnergy.BatteryBank"] = 1 },
})

craftTest("renewable_energy_craft_solar_flat", {
    recipe = "RenewableEnergy_MakeSolarFlat",
    from = "RenewableEnergy.SolarModule",
    counts = { ["RenewableEnergy.SolarModule"] = 0, ["RenewableEnergy.SolarFlat"] = 1 },
})

craftTest("renewable_energy_craft_solar_wall", {
    recipe = "RenewableEnergy_MakeSolarWall",
    from = "RenewableEnergy.SolarModule",
    counts = { ["RenewableEnergy.SolarModule"] = 0, ["RenewableEnergy.SolarWall"] = 1 },
})

craftTest("renewable_energy_craft_solar_rack", {
    recipe = "RenewableEnergy_MakeSolarRack",
    from = "RenewableEnergy.SolarModule",
    counts = { ["RenewableEnergy.SolarModule"] = 0, ["RenewableEnergy.SolarRack"] = 1 },
})

craftTest("renewable_energy_craft_unmount_solar_flat", {
    recipe = "RenewableEnergy_UnmountSolarFlat",
    from = "RenewableEnergy.SolarFlat",
    counts = { ["RenewableEnergy.SolarFlat"] = 0, ["RenewableEnergy.SolarModule"] = 1 },
})

craftTest("renewable_energy_craft_unmount_solar_wall", {
    recipe = "RenewableEnergy_UnmountSolarWall",
    from = "RenewableEnergy.SolarWall",
    counts = { ["RenewableEnergy.SolarWall"] = 0, ["RenewableEnergy.SolarModule"] = 1, ["Base.MetalBar"] = 2 },
})

craftTest("renewable_energy_craft_unmount_solar_rack", {
    recipe = "RenewableEnergy_UnmountSolarRack",
    from = "RenewableEnergy.SolarRack",
    counts = { ["RenewableEnergy.SolarRack"] = 0, ["RenewableEnergy.SolarModule"] = 2, ["Base.MetalPipe"] = 4 },
})

craftTest("renewable_energy_craft_charge_controller", {
    recipe = "RenewableEnergy_MakeChargeController",
    from = "Base.Amplifier",
    counts = { ["Base.Amplifier"] = 0, ["RenewableEnergy.ChargeController"] = 1 },
})

craftTest("renewable_energy_craft_failsafe", {
    recipe = "RenewableEnergy_MakeSolarFailsafe",
    from = "Base.RemoteCraftedV3",
    counts = { ["Base.RemoteCraftedV3"] = 0, ["RenewableEnergy.SolarFailsafe"] = 1 },
})

-- Salvaged cells make a worn module.
craftTest("renewable_energy_craft_solar_module_expanded", {
    recipe = "RenewableEnergy_MakeSolarModule",
    from = "Base.GlassPanel",
    sandbox = { enableExpandedRecipes = true },
    counts = { ["Base.GlassPanel"] = 0, ["RenewableEnergy.SolarModule"] = 1 },
    validate = function()
        local module = player():getInventory():getFirstTypeRecurse("RenewableEnergy.SolarModule")
        expect(module and module:getCondition() < module:getConditionMax(), "the salvaged module is in full condition")
    end,
})

craftTest("renewable_energy_craft_solar_module_needs_expanded_recipes", {
    recipe = "RenewableEnergy_MakeSolarModule",
    from = "Base.GlassPanel",
    sandbox = { enableExpandedRecipes = false },
    counts = { ["RenewableEnergy.SolarModule"] = 0, ["Base.GlassPanel"] = 1 },
    validate = function(self)
        expect(self.refusal ~= nil, "the game would start the craft")
    end,
})
