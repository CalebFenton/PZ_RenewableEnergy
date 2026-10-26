require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyDebug"

-- Item and recipe data as the game loaded it, for what the static check can't see. See
-- RenewableEnergyTestLib.lua for the runner and the helpers.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local Debug = RenewableEnergy.Debug

-- Items -----------------------------------------------------------------------------------------

-- Every item of the mod's has a ground model.
test("renewable_energy_items_have_ground_models", {
    validate = function()
        for _, fullType in ipairs(Debug.items()) do
            -- The static check proves a named model exists; nothing else asks for one.
            expect(getScriptManager():getItem(fullType):getWorldStaticModel() ~= nil, fullType .. " has no ground model")
        end
    end,
})

-- Recipes -------------------------------------------------------------------------------------

-- Every item a recipe of the mod's accepts, vanilla's included, has an icon: the crafting window's
-- "Possible Items" throws on one without (ISCraftInventoryPanel.populate). Each fluid input fits a
-- fluid: an unknown fluid name fails only as the game resolves the scripts
-- (InputScript.OnPostWorldDictionaryInit). The static check covers the rest of a recipe's shape.
test("renewable_energy_items_recipes_load", {
    validate = function()
        local names = T.recipeNames()
        expect(#names > 0, "no RenewableEnergy_ recipe loaded")
        for _, name in ipairs(names) do
            local recipe = getScriptManager():getCraftRecipe(name)
            local inputs = recipe and recipe:getInputs()
            for i = 0, (inputs and inputs:size() or 0) - 1 do
                local input = inputs:get(i)
                if input:getResourceType() == ResourceType.Item then
                    local possible = input:getPossibleInputItems()
                    for j = 0, possible:size() - 1 do
                        local item = possible:get(j)
                        expect(item:getNormalTexture() ~= nil, name .. " accepts " .. item:getFullName() .. ", which has no icon")
                    end
                elseif input:getResourceType() == ResourceType.Fluid then
                    expect(input:getPossibleInputFluids():size() > 0, name .. ": no fluid fits " .. input:getOriginalLine())
                end
            end
        end
    end,
})

-- Every recipe a magazine teaches (LearnedRecipes) or found hardware offers to research
-- (ResearchableRecipes) needs learning, else the item teaches what every character knows. A
-- magazine may teach a build-menu recipe; research offers only crafting recipes
-- (Item.getResearchableRecipes skips a name getCraftRecipe doesn't resolve).
test("renewable_energy_items_taught_recipes_need_learning", {
    validate = function()
        local builds = {}
        for _, name in ipairs(PZHarness.Test.buildRecipeNames()) do
            builds[name] = true
        end
        local function needsLearning(name)
            local recipe = getScriptManager():getCraftRecipe(name)
            return recipe ~= nil and recipe:needToBeLearn()
        end
        local taught = 0
        for _, fullType in ipairs(Debug.items()) do
            local item = getScriptManager():getItem(fullType)
            local learned, researchable = item:getLearnedRecipes(), item:getResearchableRecipes()
            for i = 0, (learned and learned:size() or 0) - 1 do
                local name = learned:get(i)
                taught = taught + 1
                expect(builds[name] or needsLearning(name), fullType .. " teaches " .. name .. ", which needs no learning")
            end
            for i = 0, (researchable and researchable:size() or 0) - 1 do
                local name = researchable:get(i)
                taught = taught + 1
                expect(needsLearning(name), fullType .. " offers to research " .. name .. ", which is no crafting recipe that needs learning")
            end
        end
        expect(taught > 0, "no item of the mod's teaches a recipe")
    end,
})
