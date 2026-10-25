require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/RecipeLearning"

-- Learning the mod's recipes by skill level (RecipeLearning.lua). Levels go up through the
-- authority's XP award, which fires LevelPerk. Each side's copy of the character is checked: the
-- authority's decides what may be built and crafted, this client's what the menus offer.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local RecipeLearning = RenewableEnergy.RecipeLearning

-- Every recipe of the mod, craftRecipe or build, that a character has to learn, as the scripts
-- state them: what each test expects known or not.
local RECIPES = {}
do
    local PREFIX, seen, scripts = "RenewableEnergy_", {}, getScriptManager()
    for _, recipes in ipairs({ scripts:getAllCraftRecipes(), scripts:getAllBuildableRecipes() }) do
        for i = 0, recipes:size() - 1 do
            local recipe = recipes:get(i)
            local name = recipe:getName()
            if name:sub(1, #PREFIX) == PREFIX and recipe:needToBeLearn() and not seen[name] then
                seen[name] = true
                table.insert(RECIPES, name)
            end
        end
    end
end

--- Queues making this client's and the server's copy of the character know (`known`) or not know
--- `names`. When the test ends each side knows exactly the recipes it knew before, including those
--- a level up taught meanwhile, which the leak check counts.
local function knowRecipes(self, names, known)
    T.step(function()
        local p = T.player()
        local saved = PZHarness.Fixtures.knownRecipes(p)
        if known then
            PZHarness.Fixtures.learnRecipes(p, names)
        else
            PZHarness.Fixtures.forgetRecipes(p, names)
        end
        T.defer(self, function()
            local list = p:getKnownRecipes()
            list:clear()
            for _, name in ipairs(saved) do
                list:add(name)
            end
        end)
    end)
    T.server(self, "knowRecipes", { names = names, known = known })
end

-- Which of RECIPES this client's copy of the character knows, as the crafting menus judge it: by
-- the recipe, which counts its MetaRecipe, where a name alone does not (IsoGameCharacter).
local function knownHere()
    local known, p, scripts = {}, T.player(), getScriptManager()
    for _, name in ipairs(RECIPES) do
        known[name] = p:isRecipeActuallyKnown(scripts:getCraftRecipe(name))
    end
    return known
end

-- Queues waits until the authority and then this client know each recipe `expected` marks true
-- (a multiplayer server sends what it taught), and leaves what each side knows in self.known.
local function awaitKnown(self, expected)
    local function knowsAll(known)
        for name, want in pairs(expected) do
            if want and not (known and known[name]) then
                return false
            end
        end
        return true
    end
    T.serverUntil(self, "recipesKnown", { names = RECIPES }, function(reply) return knowsAll(reply and reply.known) end)
    for name, want in pairs(expected) do
        if want then
            T.waitFor(self, function() return knownHere()[name] end, "this client's copy of the character knowing " .. name)
        end
    end
    T.step(function()
        self.known = { server = self.server["recipesKnown"].known, client = knownHere() }
    end)
end

-- Expects each side to know exactly the recipes `expected` marks true, of RECIPES, after `what`.
local function expectKnown(self, what, expected)
    for side, known in pairs(self.known or {}) do
        for _, name in ipairs(RECIPES) do
            local want = expected[name] == true
            expect(known[name] == want, what .. (want and " did not teach " or " taught ") .. name .. " on the " .. side)
        end
    end
end

-- The AutoLearn skills of the recipe `name` as { perk = perk id, level }, in `any` and `all`.
local function autoLearnOf(name)
    local recipe = getScriptManager():getCraftRecipe(name)
    local skills = { any = {}, all = {} }
    if not recipe then return skills end
    for i = 0, recipe:getAutoLearnAnySkillCount() - 1 do
        local skill = recipe:getAutoLearnAnySkill(i)
        table.insert(skills.any, { perk = skill:getPerk():getId(), level = skill:getLevel() })
    end
    for i = 0, recipe:getAutoLearnAllSkillCount() - 1 do
        local skill = recipe:getAutoLearnAllSkill(i)
        table.insert(skills.all, { perk = skill:getPerk():getId(), level = skill:getLevel() })
    end
    return skills
end

-- Which of RECIPES a character with `perk` at `level` and every other AutoLearn perk at 0 has the
-- AutoLearn skills of, as their scripts state them.
local function earnedAt(perk, level)
    local function meets(skill)
        return skill.level <= (skill.perk == perk and level or 0)
    end
    local earned = {}
    for _, name in ipairs(RECIPES) do
        local skills = autoLearnOf(name)
        for _, skill in ipairs(skills.any) do
            earned[name] = earned[name] or meets(skill)
        end
        if #skills.all > 0 then
            local all = true
            for _, skill in ipairs(skills.all) do
                all = all and meets(skill)
            end
            earned[name] = earned[name] or all
        end
    end
    return earned
end

-- Every perk and level RECIPES name in their AutoLearn skills, once each, and the highest.
local function autoLearnLevels()
    local rows, seen, highest = {}, {}, nil
    for _, name in ipairs(RECIPES) do
        local skills = autoLearnOf(name)
        for _, list in ipairs({ skills.any, skills.all }) do
            for _, skill in ipairs(list) do
                local key = skill.perk .. skill.level
                if not seen[key] then
                    seen[key] = true
                    table.insert(rows, skill)
                    if not highest or skill.level > highest.level then
                        highest = skill
                    end
                end
            end
        end
    end
    return rows, highest
end

-- Each AutoLearn perk at 0 but `perk`, which is at `level`.
local function levelsWith(rows, perk, level)
    local levels = {}
    for _, row in ipairs(rows) do
        levels[row.perk] = 0
    end
    levels[perk] = level
    return levels
end

-- For each perk and level the recipes' AutoLearn skills name, a character who knows none of them
-- levels that perk up to that level, every other at 0, and then knows exactly the recipes whose
-- AutoLearn it meets, on both sides: vanilla teaches the craftRecipes, RecipeLearning the builds,
-- which vanilla's check skips. Catches a recipe taught a level early or never, or taught on one
-- side only.
test("renewable_energy_learning_level_up_teaches_at_the_auto_learn_level", {
    timeoutSeconds = 300,
    run = function(self)
        local rows = autoLearnLevels()
        if not T.need(self, #rows > 0, "an AutoLearn skill on the mod's recipes") then return end
        self.rows, self.results = rows, {}
        knowRecipes(self, RECIPES, false)
        for i, row in ipairs(rows) do
            -- Each row starts knowing none; knowRecipes puts back what was known before the test.
            T.step(function() PZHarness.Fixtures.forgetRecipes(T.player(), RECIPES) end)
            T.server(self, "levelUp", { perk = row.perk, levels = levelsWith(rows, row.perk, row.level - 1),
                forget = RECIPES })
            awaitKnown(self, earnedAt(row.perk, row.level))
            T.step(function()
                self.results[i] = { up = self.server["levelUp"] or {}, known = self.known }
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
            expectKnown(self, what, earnedAt(row.perk, row.level))
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
        local rows, highest = autoLearnLevels()
        if not T.need(self, highest, "an AutoLearn skill on the mod's recipes") then return end
        self.highest = highest
        knowRecipes(self, RECIPES, false)
        T.server(self, "setLevelsQuietly", { levels = levelsWith(rows, highest.perk, highest.level), names = RECIPES })
        T.step(function()
            sendClientCommand(T.player(), RecipeLearning.COMMAND_MODULE, RecipeLearning.CATCH_UP, {})
        end)
        awaitKnown(self, earnedAt(highest.perk, highest.level))
    end,
    validate = function(self)
        local before = self.server["setLevelsQuietly"] or {}
        local knewAny = not before.known
        for _, name in ipairs(RECIPES) do
            knewAny = knewAny or before.known[name] == true
        end
        expect(not knewAny, "setting the levels alone taught the server a recipe, so the catch-up is untested")
        local highest = self.highest
        expectKnown(self, "joining at " .. highest.perk .. " " .. highest.level, earnedAt(highest.perk, highest.level))
    end,
})
