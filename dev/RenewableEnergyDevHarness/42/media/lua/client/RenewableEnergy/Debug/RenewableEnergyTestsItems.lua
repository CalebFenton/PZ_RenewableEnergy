require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyDebug"

-- Item and recipe data as the game loaded it, and learning recipes from magazines and research,
-- through the vanilla actions, which teach on the authority. See RenewableEnergyTestLib.lua for
-- the runner and the helpers.

local T = RenewableEnergyTest
local test, expect, player = T.test, T.expect, T.player
local Debug = RenewableEnergy.Debug

-- "RenewableEnergy.HomesteadPowerMag1" -> "homestead_power_mag1".
local function snakeName(fullType)
    return T.snake(string.match(fullType, "%.(.+)") or fullType)
end

-- Items -----------------------------------------------------------------------------------------

-- Every item of the mod's shows an icon, a name and a ground model, and is listed for the promo and
-- the art (Debug.ITEMS, Debug.PART_ITEMS), which would otherwise silently leave it out.
test("renewable_energy_items_have_icons_names_and_ground_models", {
    validate = function()
        local listed = {}
        for _, list in ipairs({ Debug.ITEMS, Debug.PART_ITEMS }) do
            for _, fullType in ipairs(list) do
                listed[fullType] = true
                expect(getScriptManager():getItem(fullType) ~= nil, "Debug lists " .. fullType .. ", which doesn't load")
            end
        end
        local items = getScriptManager():getAllItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item:getModuleName() == "RenewableEnergy" then
                local fullType = item:getFullName()
                expect(listed[fullType], fullType .. " is in neither Debug.ITEMS nor Debug.PART_ITEMS")
                local model = item:getWorldStaticModel()
                expect(model ~= nil and getScriptManager():getModelScript(model) ~= nil,
                    fullType .. " has no ground model (" .. tostring(model) .. ")")
                local icon = item:getIcon()
                expect(icon ~= nil and getTexture("Item_" .. icon) ~= nil, fullType .. " has no icon (" .. tostring(icon) .. ")")
                local instance = instanceItem(fullType)
                expect(instance ~= nil and instance:getDisplayName() ~= fullType, fullType .. " has no name")
            end
        end
    end,
})

-- A homemade module comes out of the box at its cap, below a factory module's, and the
-- electrolyte bottle full of acid.
test("renewable_energy_items_new_items_start_full", {
    validate = function()
        local module = instanceItem("RenewableEnergy.HomemadeSolarModule")
        local factoryCap = instanceItem("RenewableEnergy.SolarModule"):getConditionMax()
        expect(module:getCondition() == module:getConditionMax() and module:getConditionMax() < factoryCap,
            "a new homemade module is at " .. module:getCondition() .. " of " .. module:getConditionMax()
            .. ", a factory module's cap being " .. factoryCap)
        local bottle = instanceItem("RenewableEnergy.BatteryElectrolyte"):getFluidContainer()
        expect(bottle ~= nil and math.abs(bottle:getSpecificFluidAmount(Fluid.Acid) - bottle:getCapacity()) < 0.01,
            "a new electrolyte bottle holds " .. tostring(bottle and bottle:getSpecificFluidAmount(Fluid.Acid)) .. " L of acid, of "
            .. tostring(bottle and bottle:getCapacity()))
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

-- Learning ------------------------------------------------------------------------------------

local MAGAZINES = {
    "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2", "RenewableEnergy.HomesteadPowerMag3",
    "RenewableEnergy.HomesteadPowerMag4", "RenewableEnergy.FemaPamphlet",
}

local RESEARCHABLE = {
    "RenewableEnergy.SolarModule", "RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter",
    "RenewableEnergy.InverterCharger", "RenewableEnergy.ChargeController",
}

-- Every recipe of the mod's a character can learn: the crafting recipes and the build menu's.
local function learnable()
    local names = T.recipeNames()
    for _, name in ipairs(Debug.buildRecipes()) do
        table.insert(names, name)
    end
    return names
end

local function toList(javaList)
    local list = {}
    for i = 0, (javaList and javaList:size() or 0) - 1 do
        table.insert(list, javaList:get(i))
    end
    return list
end

-- Which of the mod's recipes this client's character has learned; the knownRecipes handler reads
-- the authority's list.
local function knownHere()
    local known, list = {}, player():getKnownRecipes()
    for _, name in ipairs(learnable()) do
        if list:contains(name) then
            known[name] = true
        end
    end
    return known
end

-- Waits until the authority and this client both know `recipes`, and leaves what each knows in
-- self.known.
local function awaitKnown(self, recipes)
    local function knowsAll(known)
        for _, name in ipairs(recipes) do
            if not known[name] then
                return false
            end
        end
        return true
    end
    T.serverUntil(self, "knownRecipes", { prefix = "RenewableEnergy_" }, function(reply) return knowsAll(reply.known) end)
    T.waitFor(self, function() return knowsAll(knownHere()) end, "this client learning the recipes")
    T.step(function()
        self.known = { server = self.server.knownRecipes.known, client = knownHere() }
    end)
end

-- Expects `what` to have taught exactly `recipes` of the mod's, on both sides.
local function expectTaught(self, what, recipes)
    expect(#recipes > 0, what .. " teaches nothing")
    local expected = {}
    for _, name in ipairs(recipes) do
        expected[name] = true
    end
    for side, known in pairs(self.known or {}) do
        for _, name in ipairs(recipes) do
            expect(known[name], what .. " did not teach " .. name .. " on the " .. side)
        end
        for _, name in ipairs(learnable()) do
            expect(expected[name] or not known[name], what .. " taught " .. name .. " on the " .. side)
        end
    end
end

-- Forgets every recipe of the mod's on both sides until the test ends, so that what a test teaches
-- is all that is known.
local function forgetAll(self, p)
    T.forgetRecipes(p)
    T.defer(self, function() T.learnRecipes(p) end)
    -- T.forgetRecipes leaves out the build menu's.
    local builds = Debug.buildRecipes()
    PZHarness.Fixtures.forgetRecipes(p, builds)
    T.defer(self, function() PZHarness.Fixtures.learnRecipes(p, builds) end)
    T.server(self, "forgetRecipesUntilEnd", { names = builds })
end

-- Reading a magazine through the vanilla action teaches, on both sides, exactly the recipes its
-- script lists, each a crafting recipe that needs learning or a build-menu recipe.
for _, magazine in ipairs(MAGAZINES) do
    local function recipes()
        local script = getScriptManager():getItem(magazine)
        return toList(script and script:getLearnedRecipes())
    end
    test("renewable_energy_items_read_" .. snakeName(magazine) .. "_teaches_its_recipes", {
        instant = true,
        run = function(self)
            local p = player()
            forgetAll(self, p)
            T.give(self, "magazine", { { type = magazine } })
            -- A title read within the literature cooldown teaches nothing (ISReadABook:complete),
            -- so a rerun in the same world forgets it first.
            T.server(self, "forgetLiterature", { type = magazine })
            T.step(function()
                local item = self.items.magazine[1]
                p:getReadLiterature():remove(item:getModData().literatureTitle)
                ISTimedActionQueue.add(ISReadABook:new(p, item))
            end)
            awaitKnown(self, recipes())
        end,
        validate = function(self)
            local builds = {}
            for _, name in ipairs(Debug.buildRecipes()) do
                builds[name] = true
            end
            for _, name in ipairs(recipes()) do
                local recipe = getScriptManager():getCraftRecipe(name)
                expect(builds[name] or (recipe ~= nil and recipe:needToBeLearn()),
                    magazine .. " teaches " .. name .. ", which is no recipe that needs learning")
            end
            expectTaught(self, "reading " .. magazine, recipes())
        end,
    })
end

-- Researching found hardware teaches, on both sides, exactly what the game offers to research from
-- it: its own recipe and its ResearchableRecipes.
for _, fullType in ipairs(RESEARCHABLE) do
    test("renewable_energy_items_research_" .. snakeName(fullType) .. "_teaches_its_recipes", {
        instant = true,
        run = function(self)
            local p = player()
            forgetAll(self, p)
            -- Research needs two thirds of a recipe's highest skill requirement
            -- (CraftRecipe.getResearchSkillLevel); the top level meets any.
            for _, perk in ipairs({ Perks.Electricity, Perks.MetalWelding, Perks.Woodwork }) do
                T.setPerk(self, perk, 10)
            end
            T.give(self, "hardware", { { type = fullType } })
            -- Filled before the waits read it, once the recipes are forgotten.
            self.offered = {}
            T.step(function()
                local item = self.items.hardware[1]
                for _, name in ipairs(toList(item:getScriptItem():getResearchableRecipes(p))) do
                    table.insert(self.offered, name)
                end
                ISTimedActionQueue.add(ISResearchRecipe:new(p, item))
            end)
            awaitKnown(self, self.offered)
        end,
        validate = function(self) expectTaught(self, "researching " .. fullType, self.offered or {}) end,
    })
end
