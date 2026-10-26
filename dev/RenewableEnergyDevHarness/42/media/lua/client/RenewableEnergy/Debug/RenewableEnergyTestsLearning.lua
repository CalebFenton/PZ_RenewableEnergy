require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local RecipeLearning = require "cf_commonlib/RecipeLearning"

-- Learning the mod's recipes by skill level (cf_commonlib's RecipeLearning, which Recipes.lua
-- registers the mod's prefix with), through the harness's T.autoLearnTests. Levels go up through
-- the authority's XP award, which fires LevelPerk: vanilla teaches the craftRecipes, RecipeLearning
-- the builds, which vanilla's check skips. Each side's copy of the character is checked: the
-- authority's decides what may be built and crafted, this client's what the menus offer.

local T = RenewableEnergyTest

-- Every recipe of the mod, craftRecipe or build, that a character has to learn, as the scripts
-- state them: what each test expects known or not. Named here, not by the recipePrefix setting,
-- which may register after this file loads.
T.autoLearnTests("renewable_energy", T.learnableRecipeNames("RenewableEnergy_"), {
    timeoutSeconds = 300,
    -- RecipeLearning's OnCreatePlayer request.
    catchUp = function()
        sendClientCommand(T.player(), RecipeLearning.COMMAND_MODULE, RecipeLearning.CATCH_UP, {})
    end,
})
