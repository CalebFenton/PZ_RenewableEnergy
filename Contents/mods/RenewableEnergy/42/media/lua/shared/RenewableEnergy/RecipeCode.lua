-- Callbacks of the craftRecipes in media/scripts/RenewableEnergy/Recipes.txt. Shared, since
-- OnTest runs wherever the craft is checked. OnCreate runs once, on the authority (single
-- player or the server), after the outputs were already sent to a multiplayer client, so
-- whatever it changes on an output is synced again.
RenewableEnergy = RenewableEnergy or {}
local Recipes = {}
RenewableEnergy.Recipes = Recipes

-- Condition of a module built from salvaged cells.
local SALVAGED_MODULE_CONDITION = 60

function Recipes.salvagedModule(craftRecipeData, character)
    local module = craftRecipeData:getFirstCreatedItem()
    module:setCondition(SALVAGED_MODULE_CONDITION)
    module:syncItemFields()
end

-- OnTest of the Expanded Recipes. It is asked about every candidate input, so every one of
-- them fails while the option is off.
function Recipes.expandedRecipesEnabled(item, character)
    return SandboxVars.RenewableEnergy.enableExpandedRecipes == true
end

-- OnAddToMenu of the Expanded Recipes. A global of its own: the crafting window fetches it
-- with one rawget on the global table, so a dotted path would resolve to nil.
function RenewableEnergy_ExpandedRecipesEnabled(params)
    return SandboxVars.RenewableEnergy.enableExpandedRecipes == true
end

return Recipes
