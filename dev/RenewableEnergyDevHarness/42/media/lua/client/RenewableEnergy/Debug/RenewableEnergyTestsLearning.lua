require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local RecipeLearning = require "cf_commonlib/RecipeLearning"

-- Learning the mod's recipes by skill level (cf_commonlib's RecipeLearning, which Recipes.lua
-- registers the mod's prefix with), through the harness's T.autoLearnTests. Levels go up through
-- the authority's XP award, which fires LevelPerk: vanilla teaches the craftRecipes, RecipeLearning
-- the builds, which vanilla's check skips. Each side's copy of the character is checked: the
-- authority's decides what may be built and crafted, this client's what the menus offer.

local T = RenewableEnergyTest
local PREFIX = "RenewableEnergy_"

-- One learnable recipe of each way a recipe is learned: a craftRecipe or a build, by AutoLearnAny,
-- AutoLearnAll or neither (a magazine's). Each way runs one rule for every recipe, so one of each
-- catches a rule that is wrong for that way, and the test levels up once per skill of these few
-- rather than once per skill and level any recipe names. The first of each, in script order, so
-- that every run picks the same. Named here, not by the recipePrefix setting, which may register
-- after this file loads.
local function oneOfEachWay()
    local scripts, picked, names = getScriptManager(), {}, {}
    for _, kind in ipairs({ { "craft", scripts:getAllCraftRecipes() }, { "build", scripts:getAllBuildableRecipes() } }) do
        local recipes = kind[2]
        for i = 0, recipes:size() - 1 do
            local recipe = recipes:get(i)
            local way = kind[1] .. (recipe:getAutoLearnAnySkillCount() > 0 and " any" or "")
                .. (recipe:getAutoLearnAllSkillCount() > 0 and " all" or "")
            if luautils.stringStarts(recipe:getName(), PREFIX) and recipe:needToBeLearn() and not picked[way] then
                picked[way] = true
                table.insert(names, recipe:getName())
            end
        end
    end
    return names
end

T.autoLearnTests("renewable_energy", oneOfEachWay(), {
    timeoutSeconds = 300,
    -- RecipeLearning's OnCreatePlayer request.
    catchUp = function()
        sendClientCommand(T.player(), RecipeLearning.COMMAND_MODULE, RecipeLearning.CATCH_UP, {})
    end,
})
