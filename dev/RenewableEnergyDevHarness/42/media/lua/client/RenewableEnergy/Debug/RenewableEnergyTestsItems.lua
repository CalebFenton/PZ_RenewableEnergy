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

-- The inventory and the crafting window draw an item's icon, the floor its ground model, and a
-- missing ItemName.json entry shows the full type, since the scripts set no DisplayName
-- (Translator.getItemNameFromFullType). The promo and the art list the items by hand
-- (Debug.ITEMS, Debug.PART_ITEMS): a new item missing there, or a listed one renamed, would
-- silently drop out of them.
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
test("renewable_energy_items_new_start_right", {
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

-- Every recipe of the mod's resolves by its bare name in module Base (research and the magazines
-- look it up so), and names only items that exist: a missing item makes a recipe impossible
-- without a word. Expanding "Possible Items" in the crafting window reads the icon of every item
-- an input accepts (ISCraftInventoryPanel.populate), and throws for one without. A recipe that
-- fails to load fails the craft, magazine and research tests that name it.
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

-- What each magazine teaches: its crafting recipes and its build-menu recipes (entity scripts).
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
    ["RenewableEnergy.HomesteadPowerMag3"] = {
        "RenewableEnergy_MakeGasConversionKit", "RenewableEnergy_MakeGasHeater",
        builds = {
            "RenewableEnergy_BarrelDigesterSteel", "RenewableEnergy_BarrelDigesterPlastic",
            "RenewableEnergy_InsulatedDigester", "RenewableEnergy_BrickDome",
        },
    },
    ["RenewableEnergy.FemaPamphlet"] = {
        "RenewableEnergy_MakeGasConversionKit", "RenewableEnergy_MakeVinegarMildewSpray", "RenewableEnergy_MakeVinegarAphidSpray",
        builds = { "RenewableEnergy_PrimitiveGasifier", "RenewableEnergy_Gasifier", "RenewableEnergy_AdvancedGasifier" },
    },
    ["RenewableEnergy.HomesteadPowerMag4"] = {
        "RenewableEnergy_CarveWoodenBlades", "RenewableEnergy_CutPipeBlades", "RenewableEnergy_ForgeSteelBlades",
        "RenewableEnergy_MakeHomemadeAlternator",
        builds = {
            "RenewableEnergy_ScoopRotor", "RenewableEnergy_PropellerWood", "RenewableEnergy_PropellerPipe",
            "RenewableEnergy_AlternatorWindCharger",
        },
    },
}

-- Every recipe of the mod's a character can learn: the crafting recipes and the build menu's.
local function learnable()
    local names = T.recipeNames()
    for _, name in ipairs(Debug.buildRecipes()) do
        table.insert(names, name)
    end
    return names
end

-- Which of the mod's recipes this client's character has learned; the knownRecipes handler reads
-- the authority's list. A multiplayer server teaches and sends what it taught.
local function knownHere()
    local known, list = {}, player():getKnownRecipes()
    for _, name in ipairs(learnable()) do
        if list:contains(name) then
            known[name] = true
        end
    end
    return known
end

-- Queues a wait until the authority and this client both know `recipes`, as far as a fixture's
-- wait goes, and leaves what each knows in self.known.
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
    local expected = {}
    for _, name in ipairs(recipes) do
        expected[name] = true
    end
    for side, known in pairs(self.known) do
        for _, name in ipairs(recipes) do
            expect(known[name], what .. " did not teach " .. name .. " on the " .. side)
        end
        for _, name in ipairs(learnable()) do
            expect(expected[name] or not known[name], what .. " taught " .. name .. " on the " .. side)
        end
    end
end

-- Forgets every recipe of the mod's on both sides until the test ends, so that what a test teaches
-- is all that is known; the scenario taught them all.
local function forgetAll(self, p)
    T.forgetRecipes(p)
    T.defer(self, function() T.learnRecipes(p) end)
    -- The build menu's recipes, which T.forgetRecipes leaves out.
    local builds = Debug.buildRecipes()
    PZHarness.Fixtures.forgetRecipes(p, builds)
    T.defer(self, function() PZHarness.Fixtures.learnRecipes(p, builds) end)
    T.server(self, "forgetRecipesUntilEnd", { names = builds })
end

-- Reading a magazine through the vanilla action teaches exactly its recipes, the crafting ones
-- each a recipe that has to be learned, and its build-menu recipes.
for magazine, crafts in pairs(MAGAZINES) do
    local recipes = {}
    for _, list in ipairs({ crafts, crafts.builds or {} }) do
        for _, name in ipairs(list) do
            table.insert(recipes, name)
        end
    end
    test("renewable_energy_items_read_" .. snakeName(magazine) .. "_teaches_its_recipes", {
        instant = true,
        run = function(self)
            local p = player()
            forgetAll(self, p)
            T.give(self, "magazine", { { type = magazine } })
            -- onCreateRecipeMagazine gives every copy a literatureTitle, and a title read within
            -- the literature cooldown teaches nothing (ISReadABook:complete), so the title is
            -- forgotten on both sides first, or a second run in the same world would fail.
            T.server(self, "forgetLiterature", { type = magazine })
            T.step(function()
                local item = self.items.magazine[1]
                p:getReadLiterature():remove(item:getModData().literatureTitle)
                ISTimedActionQueue.add(ISReadABook:new(p, item))
            end)
            awaitKnown(self, recipes)
        end,
        validate = function(self)
            for _, name in ipairs(crafts) do
                local recipe = getScriptManager():getCraftRecipe(name)
                expect(recipe ~= nil and recipe:needToBeLearn(), magazine .. " teaches " .. name .. ", which needs no learning")
            end
            expectTaught(self, "reading " .. magazine, recipes)
        end,
    })
end

-- Cutting up a fridge with a blowtorch also gives its compressor, which a digester uses to fill
-- propane tanks.
test("renewable_energy_items_fridge_scraps_to_compressor", {
    validate = function()
        local fridge = ISMoveableDefinitions:getInstance().getScrapDefinition("Fridge")
        local found = false
        -- Moveables.lua adds it with a static size, as vanilla adds the fridge's other scrap.
        for _, entry in ipairs(fridge and fridge.returnItemsStatic or {}) do
            found = found or entry.returnItem == RenewableEnergy.Digester.COMPRESSOR
        end
        expect(found, "scrapping a fridge doesn't list " .. tostring(RenewableEnergy.Digester.COMPRESSOR))
    end,
})

-- Researching found hardware teaches exactly what to build from it: the item's own recipe
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
            forgetAll(self, p)
            -- Research needs two thirds of a recipe's highest skill requirement
            -- (CraftRecipe.getResearchSkillLevel); the top level meets any.
            for _, perk in ipairs({ Perks.Electricity, Perks.MetalWelding, Perks.Woodwork }) do
                T.setPerk(self, perk, 10)
            end
            T.give(self, "hardware", { { type = fullType } })
            T.step(function()
                ISTimedActionQueue.add(ISResearchRecipe:new(p, self.items.hardware[1]))
            end)
            awaitKnown(self, recipes)
        end,
        validate = function(self) expectTaught(self, "researching " .. fullType, recipes) end,
    })
end
