require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Item and recipe data as the game loaded it, for what the static check can't see. See
-- RenewableEnergyTestLib.lua for the runner and the helpers.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect

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
