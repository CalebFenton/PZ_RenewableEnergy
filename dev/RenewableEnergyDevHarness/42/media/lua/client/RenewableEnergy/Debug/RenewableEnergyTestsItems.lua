require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyDebug"

-- Item and recipe data as the game loaded it, for what the static check can't see. See
-- RenewableEnergyTestLib.lua for the runner and the helpers.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local Debug = RenewableEnergy.Debug

-- The mod's script items, as the game loaded them.
local function modItems()
    local found, items = {}, getScriptManager():getAllItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getModuleName() == "RenewableEnergy" then
            table.insert(found, item)
        end
    end
    return found
end

-- Items -----------------------------------------------------------------------------------------

-- Every item of the mod's has a ground model, and is listed for the promo and the art
-- (Debug.ITEMS, Debug.PART_ITEMS), which would otherwise silently leave it out.
test("renewable_energy_items_have_ground_models_and_debug_listing", {
    validate = function()
        local listed = {}
        for _, list in ipairs({ Debug.ITEMS, Debug.PART_ITEMS }) do
            for _, fullType in ipairs(list) do
                listed[fullType] = true
                expect(getScriptManager():getItem(fullType) ~= nil, "Debug lists " .. fullType .. ", which doesn't load")
            end
        end
        for _, item in ipairs(modItems()) do
            local fullType = item:getFullName()
            expect(listed[fullType], fullType .. " is in neither Debug.ITEMS nor Debug.PART_ITEMS")
            -- The static check proves a named model exists; nothing else asks for one.
            expect(item:getWorldStaticModel() ~= nil, fullType .. " has no ground model")
        end
    end,
})

-- Recipes -------------------------------------------------------------------------------------

-- Every recipe of the mod's resolves by its bare name in module Base, as research and the magazines
-- look it up, and names only items that exist and have icons: the crafting window's "Possible Items"
-- throws on one without (ISCraftInventoryPanel.populate).
test("renewable_energy_items_recipes_load", {
    validate = function()
        local names = T.recipeNames()
        expect(#names > 0, "no RenewableEnergy_ recipe loaded")
        for _, name in ipairs(names) do
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
    end,
})

-- Every recipe a magazine teaches (LearnedRecipes) or found hardware offers to research
-- (ResearchableRecipes) needs learning, else the item teaches what every character knows. A
-- magazine may teach a build-menu recipe; research offers only crafting recipes
-- (Item.getResearchableRecipes skips a name getCraftRecipe doesn't resolve).
test("renewable_energy_items_taught_recipes_need_learning", {
    validate = function()
        local builds = {}
        for _, name in ipairs(Debug.buildRecipes()) do
            builds[name] = true
        end
        local function needsLearning(name)
            local recipe = getScriptManager():getCraftRecipe(name)
            return recipe ~= nil and recipe:needToBeLearn()
        end
        local taught = 0
        for _, item in ipairs(modItems()) do
            local fullType = item:getFullName()
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
