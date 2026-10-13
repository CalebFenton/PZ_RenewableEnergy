require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Item and recipe data as the game loaded it, and learning recipes from magazines and research.
-- See RenewableEnergyTestLib.lua for the runner and the helpers.

local T = RenewableEnergyTest
local test, expect, player = T.test, T.expect, T.player
local Debug = RenewableEnergy.Debug

-- Every recipe Recipes.txt defines. Listed rather than read from the game, so that one that
-- fails to load is caught.
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

-- "RenewableEnergy.HomesteadPowerMag1" -> "homestead_power_mag1".
local function snakeName(fullType)
    local name = string.match(fullType, "%.(.+)") or fullType
    return string.lower((name:gsub("(%l)(%u)", "%1_%2"):gsub("(%d)(%u)", "%1_%2")))
end

-- Items -----------------------------------------------------------------------------------------

-- The inventory and the crafting window draw an item's icon, the floor its ground model, and a
-- missing ItemName.json entry shows the full type, since the scripts set no DisplayName
-- (Translator.getItemNameFromFullType).
test("renewable_energy_items_have_icons_names_and_ground_models", {
    validate = function()
        local items = getScriptManager():getAllItems()
        local checked = 0
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item:getModuleName() == "RenewableEnergy" then
                checked = checked + 1
                local fullType = item:getFullName()
                local model = item:getWorldStaticModel()
                expect(model ~= nil and getScriptManager():getModelScript(model) ~= nil,
                    fullType .. " has no ground model (" .. tostring(model) .. ")")
                local icon = item:getIcon()
                expect(icon ~= nil and getTexture("Item_" .. icon) ~= nil, fullType .. " has no icon (" .. tostring(icon) .. ")")
                local instance = instanceItem(fullType)
                expect(instance ~= nil and instance:getDisplayName() ~= fullType, fullType .. " has no name")
            end
        end
        local expected = #Debug.ITEMS + #Debug.PART_ITEMS
        expect(checked == expected, checked .. " RenewableEnergy items loaded, expected " .. expected)
    end,
})

-- A homemade module comes out of the box at its cap, 60, and the electrolyte bottle full of acid.
test("renewable_energy_items_new_start_right", {
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

-- Every recipe loads, resolves by its bare name in module Base (research and the magazines look
-- it up so), and names only items that exist: a missing item makes a recipe impossible without
-- a word. Expanding "Possible Items" in the crafting window reads the icon of every item an
-- input accepts (ISCraftInventoryPanel.populate), and throws for one without.
test("renewable_energy_items_recipes_load", {
    validate = function()
        for _, name in ipairs(RECIPES) do
            local recipe = getScriptManager():getCraftRecipe(name)
            if expect(recipe ~= nil, name .. " does not resolve by its bare name") then
                expect(recipe:getModule():getName() == "Base", name .. " is in module " .. recipe:getModule():getName())
                local inputs = recipe:getInputs()
                for i = 0, inputs:size() - 1 do
                    local input = inputs:get(i)
                    if input:getResourceType() == ResourceType.Item then
                        local possible = input:getPossibleInputItems()
                        expect(possible:size() > 0, name .. ": no item fits " .. input:getOriginalLine())
                        for j = 0, possible:size() - 1 do
                            local item = possible:get(j)
                            expect(item:getNormalTexture() ~= nil, name .. " accepts " .. item:getFullName() .. ", which has no icon")
                        end
                    end
                end
                local outputs = recipe:getOutputs()
                for i = 0, outputs:size() - 1 do
                    local output = outputs:get(i)
                    if output:getResourceType() == ResourceType.Item then
                        expect(output:getPossibleResultItems():size() > 0, name .. ": an output is no item")
                    end
                end
            end
        end
        local loaded = #Debug.recipeNames()
        expect(loaded == #RECIPES, loaded .. " RenewableEnergy_ recipes loaded, expected " .. #RECIPES)
    end,
})

-- Learning ------------------------------------------------------------------------------------

-- What each magazine teaches, as the README promises: #1 the boxes, racks, mounts and module
-- repair; #2 the banks, the charge controller, the failsafe, homemade modules, reconditioning
-- and rebuilding.
local MAGAZINES = {
    ["RenewableEnergy.HomesteadPowerMag1"] = {
        "RenewableEnergy_MakeBatteryBoxWood", "RenewableEnergy_MakeBatteryBoxMetal",
        "RenewableEnergy_BuildBatteryRackWood", "RenewableEnergy_BuildBatteryRackMetal",
        "RenewableEnergy_MakeSolarFlat", "RenewableEnergy_MakeSolarWallWood", "RenewableEnergy_MakeSolarWallMetal",
        "RenewableEnergy_MakeSolarRackWood", "RenewableEnergy_MakeSolarRackMetal",
        "RenewableEnergy_RepairCrackedModule",
    },
    ["RenewableEnergy.HomesteadPowerMag2"] = {
        "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy_BuildBatteryBankMetal",
        "RenewableEnergy_MakeChargeController", "RenewableEnergy_MakeSolarFailsafe",
        "RenewableEnergy_MakeHomemadeSolarModule", "RenewableEnergy_ReconditionBattery",
        "RenewableEnergy_StripCarBattery", "RenewableEnergy_StripDeepCycleBattery", "RenewableEnergy_StripL16Battery",
        "RenewableEnergy_RecastBatteryPlates",
        "RenewableEnergy_RebuildCarBattery", "RenewableEnergy_RebuildDeepCycleBattery", "RenewableEnergy_RebuildL16Battery",
        "RenewableEnergy_MakeBatteryPlatePattern", "RenewableEnergy_PressBatteryPlateMold",
        "RenewableEnergy_FireBatteryPlateMold",
    },
}

-- Reading a magazine through the vanilla action teaches exactly its recipes, each one a recipe
-- that has to be learned.
for magazine, recipes in pairs(MAGAZINES) do
    test("renewable_energy_items_read_" .. snakeName(magazine) .. "_teaches_its_recipes", {
        instant = true,
        run = function(self)
            local p = player()
            Debug.forgetRecipes(p)
            T.defer(self, function() Debug.learnRecipes(p) end)
            ISTimedActionQueue.add(ISReadABook:new(p, p:getInventory():AddItem(magazine)))
        end,
        validate = function()
            local expected, known = {}, player():getKnownRecipes()
            for _, name in ipairs(recipes) do
                expected[name] = true
                local recipe = getScriptManager():getCraftRecipe(name)
                expect(recipe ~= nil and recipe:needToBeLearn(), magazine .. " teaches " .. name .. ", which needs no learning")
                expect(known:contains(name), "reading " .. magazine .. " did not teach " .. name)
            end
            for _, name in ipairs(Debug.recipeNames()) do
                expect(expected[name] or not known:contains(name), "reading " .. magazine .. " taught " .. name)
            end
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
    ["RenewableEnergy.InverterCharger"] = {
        "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy_BuildBatteryBankMetal", "RenewableEnergy_MakeSolarFailsafe",
    },
    ["RenewableEnergy.ChargeController"] = { "RenewableEnergy_MakeChargeController" },
}

for fullType, recipes in pairs(RESEARCH) do
    test("renewable_energy_items_research_" .. snakeName(fullType) .. "_teaches_its_recipes", {
        instant = true,
        run = function(self)
            local p = player()
            Debug.forgetRecipes(p)
            T.defer(self, function() Debug.learnRecipes(p) end)
            -- Research asks for two thirds of a recipe's highest level.
            for _, perk in ipairs({ Perks.Electricity, Perks.MetalWelding, Perks.Woodwork }) do
                T.setPerk(self, perk, 10)
            end
            ISTimedActionQueue.add(ISResearchRecipe:new(p, p:getInventory():AddItem(fullType)))
        end,
        validate = function()
            for _, recipe in ipairs(recipes) do
                expect(player():isRecipeActuallyKnown(recipe), "researching " .. fullType .. " did not teach " .. recipe)
            end
        end,
    })
end
