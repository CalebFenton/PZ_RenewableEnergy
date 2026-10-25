require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local RecipeLearning = require "cf_commonlib/RecipeLearning"

-- Learning the mod's recipes by skill level (cf_commonlib's RecipeLearning, which Recipes.lua
-- registers the mod's prefix with). Levels go up through the authority's XP award, which fires
-- LevelPerk. Each side's copy of the character is checked: the authority's decides what may be
-- built and crafted, this client's what the menus offer.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect

-- Every recipe of the mod, craftRecipe or build, that a character has to learn, as the scripts
-- state them: what each test expects known or not. Named here, not by the recipePrefix setting,
-- which may register after this file loads.
local RECIPES = T.learnableRecipeNames("RenewableEnergy_")

-- For each perk and level the recipes' AutoLearn skills name, a character who knows none of them
-- levels that perk up to that level, every other at 0, and then knows exactly the recipes whose
-- AutoLearn it meets, on both sides: vanilla teaches the craftRecipes, RecipeLearning the builds,
-- which vanilla's check skips. Catches a recipe taught a level early or never, or taught on one
-- side only.
test("renewable_energy_learning_level_up_teaches_at_the_auto_learn_level", {
    timeoutSeconds = 300,
    run = function(self)
        local rows = T.autoLearnLevels(RECIPES)
        if not T.need(self, #rows > 0, "an AutoLearn skill on the mod's recipes") then return end
        self.rows, self.results = rows, {}
        for i, row in ipairs(rows) do
            -- Each row starts knowing none; the end of the test puts back what was known before.
            T.knowRecipes(self, RECIPES, false)
            T.levelUp(self, row.perk, T.autoLearnLevelsWith(rows, row.perk, row.level - 1))
            T.waitForKnown(self, RECIPES, T.autoLearnedAt(RECIPES, row.perk, row.level))
            T.step(function()
                self.results[i] = { up = self.server["PZHarness.levelUp"] or {}, known = self.known }
            end)
        end
    end,
    validate = function(self)
        for i, row in ipairs(self.rows or {}) do
            local result = self.results[i] or {}
            local up, what = result.up or {}, row.perk .. " " .. row.level
            expect(up.before == row.level - 1 and up.after == row.level, row.perk .. " went from " .. tostring(up.before)
                .. " to " .. tostring(up.after) .. ", expected " .. (row.level - 1) .. " to " .. row.level)
            self.known = result.known
            T.expectKnown(self, RECIPES, what, T.autoLearnedAt(RECIPES, row.perk, row.level))
        end
    end,
})

-- A character who reached the highest AutoLearn level before the mod was added joins a server: the
-- client asks the server to catch up as it enters the world (RecipeLearning's OnCreatePlayer), and
-- the server, which runs no check of its own on a join, teaches what that level earns and tells
-- the client. Catches a joining character left without recipes the server then refuses to use.
test("renewable_energy_learning_joining_server_catches_up_earned_recipes", {
    mpOnly = "single player has one copy of the character, which IsoWorld.init's own check covers",
    run = function(self)
        local rows, highest = T.autoLearnLevels(RECIPES)
        if not T.need(self, highest, "an AutoLearn skill on the mod's recipes") then return end
        self.highest = highest
        T.knowRecipes(self, RECIPES, false)
        T.setLevelsQuietly(self, T.autoLearnLevelsWith(rows, highest.perk, highest.level), RECIPES)
        T.step(function()
            sendClientCommand(T.player(), RecipeLearning.COMMAND_MODULE, RecipeLearning.CATCH_UP, {})
        end)
        T.waitForKnown(self, RECIPES, T.autoLearnedAt(RECIPES, highest.perk, highest.level))
    end,
    validate = function(self)
        local before = self.server["PZHarness.setLevelsQuietly"] or {}
        local knewAny = not before.known
        for _, name in ipairs(RECIPES) do
            knewAny = knewAny or before.known[name] == true
        end
        expect(not knewAny, "setting the levels alone taught the server a recipe, so the catch-up is untested")
        local highest = self.highest
        T.expectKnown(self, RECIPES, "joining at " .. highest.perk .. " " .. highest.level,
            T.autoLearnedAt(RECIPES, highest.perk, highest.level))
    end,
})
