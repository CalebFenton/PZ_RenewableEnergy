require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Gadgets/SolarMaintainer"

-- Crafting tests: every recipe crafted the way a player starts it, instantly, with the inputs the
-- authority gave, which also makes the outputs (T.craftTest). The tests read the items from the
-- authority's copies, through the carried handler of RenewableEnergyTestServerCharacter.lua. See
-- RenewableEnergyTestLib.lua for the runner and the helpers.

local T = RenewableEnergyTest
local test, craftTest, expect, expectNear, player = T.test, T.craftTest, T.expect, T.expectNear, T.player
local PowerBank, Recipes = RenewableEnergy.PowerBank, RenewableEnergy.Recipes
local MODULES_KEY = PowerBank.MODULES
local FACTORY, HOMEMADE = "RenewableEnergy.SolarModule", "RenewableEnergy.HomemadeSolarModule"

-- The test name for `recipe`: "RenewableEnergy_TakeApartSolarCellCharger", "returns_x" ->
-- "renewable_energy_craft_take_apart_solar_cell_charger_returns_x".
local function craftName(recipe, behavior)
    return "renewable_energy_craft_" .. T.snake((recipe:gsub("^RenewableEnergy_", ""))) .. (behavior and "_" .. behavior or "")
end

-- The given inputs (this client's copies, T.craftTest's self.items.inputs) of `fullType`.
local function inputsOf(self, fullType)
    local found = {}
    for _, item in ipairs(self.items.inputs or {}) do
        if item:getFullType() == fullType then
            table.insert(found, item)
        end
    end
    return found
end

-- Queues reading the authority's copies of `types` and its litres of `fluids` into
-- self.server.carried (see the carried handler).
local function readCarried(self, types, fluids)
    T.server(self, "carried", { types = types, fluids = fluids })
end

-- The authority's first item of `fullType` from the last readCarried, or nil.
local function carriedFirst(self, fullType)
    local items = self.server.carried and self.server.carried.items[fullType]
    return items and items[1]
end

-- Queues a wait until this client's first `fullType` holds `liters` of fluid: the server's refill
-- reaches this client after its answer, and a craft picks its inputs from this client's copies.
local function waitForFluid(self, fullType, liters)
    T.waitFor(self, function()
        local item = T.carried(fullType)
        local fluids = item and item:getFluidContainer()
        return fluids ~= nil and math.abs(fluids:getAmount() - liters) < 0.001
    end, "this client's " .. fullType .. " holding " .. liters .. " L")
end

-- Queues setting the repair count of the carried `fullType` items on the authority, and a wait
-- until this client's copy has it: the craft tests its own copy.
local function setRepaired(self, fullType, repaired)
    T.server(self, "setRepaired", { type = fullType, repaired = repaired })
    T.waitFor(self, function()
        local item = T.carried(fullType)
        return item ~= nil and item:getHaveBeenRepaired() == repaired
    end, "this client's " .. fullType .. " repaired " .. repaired .. "x")
end

-- Bank tiers and parts -------------------------------------------------------------------------

-- Each recipe makes one item and uses up what its script takes, but the tools it keeps. A craft
-- starts from the material a player right-clicks.
local MAKES = {
    { "RenewableEnergy_MakeBatteryBoxWood", "RenewableEnergy.BatteryBoxWood", "Base.Plank" },
    { "RenewableEnergy_MakeBatteryBoxMetal", "RenewableEnergy.BatteryBoxMetal", "Base.SmallSheetMetal" },
    { "RenewableEnergy_BuildBatteryRackWood", "RenewableEnergy.BatteryRackWood", "Base.Plank" },
    { "RenewableEnergy_BuildBatteryRackMetal", "RenewableEnergy.BatteryRackMetal", "Base.SmallSheetMetal" },
    { "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy.BatteryBankWood", "Base.Plank" },
    { "RenewableEnergy_BuildBatteryBankMetal", "RenewableEnergy.BatteryBankMetal", "Base.SheetMetal" },
    { "RenewableEnergy_MakeChargeController", "RenewableEnergy.ChargeController", "Base.ElectronicsScrap" },
    { "RenewableEnergy_MakeSolarFailsafe", "RenewableEnergy.SolarFailsafe", "Base.RemoteCraftedV3" },
    { "RenewableEnergy_WeldMetalDrum", "Base.MetalDrum", "Base.SheetMetal" },
}

-- The items one craft of `recipe` uses up: those T.recipeInputs gives for the inputs it neither
-- keeps nor takes only some uses of, as a blowtorch's.
local function usedUp(recipe)
    local types = {}
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        local item = not input:isKeep() and T.inputItem(input)
        if item and (input:isItemCount() or not item:isItemType(ItemType.DRAINABLE)) then
            table.insert(types, item:getFullName())
        end
    end
    return types
end

for _, entry in ipairs(MAKES) do
    local recipe, result, from = entry[1], entry[2], entry[3]
    craftTest(craftName(recipe), {
        recipe = recipe,
        from = from,
        counts = { [result] = 1 },
        after = function(self) T.count(self, "usedUp", usedUp(getScriptManager():getCraftRecipe(recipe))) end,
        validate = function(self)
            local checked = 0
            for fullType, count in pairs(self.counts.usedUp or {}) do
                checked = checked + 1
                expect(count == 0, count .. " " .. fullType .. " left after the craft, which uses it up")
            end
            expect(checked > 0, "the craft uses up nothing")
        end,
    })
end

-- Panel mounts ---------------------------------------------------------------------------------

-- Expects the mount's record of its modules to hold `expected`, each type at its condition and
-- seal count.
local function expectModules(mount, expected)
    local modules = mount and mount.modData[MODULES_KEY]
    if not expect(modules ~= nil and #modules == #expected,
        "the mount holds " .. tostring(modules and #modules) .. " modules, expected " .. #expected) then
        return
    end
    -- Which input the craft lists first is its own business.
    if #modules == 2 and modules[1].type ~= expected[1].type then
        expected = { expected[2], expected[1] }
    end
    for i, want in ipairs(expected) do
        local got, wantRepaired = modules[i], want.repaired or 0
        expect(got.type == want.type and got.condition == want.condition and (got.repaired or 0) == wantRepaired,
            "module " .. i .. " is " .. tostring(got.type) .. " at " .. tostring(got.condition) .. " sealed "
            .. tostring(got.repaired) .. "x, expected " .. want.type .. " at " .. want.condition .. " sealed " .. wantRepaired .. "x")
    end
end

-- Every mount item (Recipes.MOUNTS), the modules its Specs.mounts kind holds, and its name, by
-- which its recipes are RenewableEnergy_Make<name> and RenewableEnergy_Unmount<name>.
local MOUNTS = {}
for mount, row in pairs(Recipes.MOUNTS) do
    table.insert(MOUNTS, { mount = mount, count = RenewableEnergy.Specs.mounts[row.kind].modules, name = mount:match("%.(.+)") })
end

-- Mounting records each module's type, condition and seals, at conditions a new module doesn't
-- have; a two-module rack gets one of each type. A mount that recorded new modules instead, or
-- only the first of two, would unmount as something else than went in.
local FACTORY_MODULE = { type = FACTORY, condition = 72, repaired = 2 }
local HOMEMADE_MODULE = { type = HOMEMADE, condition = 41 }
for _, entry in ipairs(MOUNTS) do
    local mount, count = entry.mount, entry.count
    local recipe = "RenewableEnergy_Make" .. entry.name
    craftTest(craftName(recipe, "keeps_module_condition"), {
        recipe = recipe,
        from = FACTORY,
        prefer = { FACTORY },
        setup = function(self)
            local modules = inputsOf(self, FACTORY)
            T.changeItem(self, modules[1], { condition = FACTORY_MODULE.condition })
            setRepaired(self, FACTORY, FACTORY_MODULE.repaired)
            if count == 2 then
                -- One of the two a homemade module instead. This client must have lost the
                -- factory one before the craft picks its inputs from its own copy.
                local taken = modules[2]:getID()
                T.server(self, "takeItems", { ids = { taken } })
                T.give(self, "homemade", { { type = HOMEMADE, condition = HOMEMADE_MODULE.condition } })
                T.waitFor(self, function() return T.player():getInventory():getItemById(taken) == nil end,
                    "this client losing the second factory module")
            end
        end,
        counts = { [FACTORY] = 0, [HOMEMADE] = 0, [mount] = 1 },
        after = function(self) readCarried(self, { mount }) end,
        validate = function(self)
            expectModules(carriedFirst(self, mount), count == 2 and { FACTORY_MODULE, HOMEMADE_MODULE } or { FACTORY_MODULE })
        end,
    })
end

-- Unmounting gives back each module as the type, at the condition and with the seals it went in,
-- still marked as mounted and connected before if it was, and a module not so marked comes back
-- unmarked.
local MOUNTED_HOMEMADE = { type = HOMEMADE, condition = 41, repaired = 2, mounted = true, connected = true }
local PLAIN_FACTORY = { type = FACTORY, condition = 12 }
for _, entry in ipairs(MOUNTS) do
    local mount, count = entry.mount, entry.count
    local recipe = "RenewableEnergy_Unmount" .. entry.name
    craftTest(craftName(recipe, "returns_modules"), {
        recipe = recipe,
        from = mount,
        setup = function(self)
            local modules = { MOUNTED_HOMEMADE }
            if count == 2 then
                table.insert(modules, PLAIN_FACTORY)
            end
            T.changeItem(self, inputsOf(self, mount)[1], { modData = { [MODULES_KEY] = modules } })
        end,
        counts = { [mount] = 0, [HOMEMADE] = 1, [FACTORY] = count == 2 and 1 or 0 },
        after = function(self) readCarried(self, { HOMEMADE, FACTORY }) end,
        validate = function(self)
            local homemade = carriedFirst(self, HOMEMADE)
            if expect(homemade ~= nil, "no homemade module came back") then
                local data = homemade.modData
                expect(homemade.condition == MOUNTED_HOMEMADE.condition, "the homemade module came back at " .. homemade.condition)
                expect(homemade.repaired == MOUNTED_HOMEMADE.repaired, "the homemade module came back sealed " .. homemade.repaired .. "x")
                expect(data[PowerBank.MOUNTED_ONCE] == true and data[PowerBank.CONNECTED_ONCE] == true,
                    "the homemade module came back without its mounted and connected marks")
            end
            local factory = carriedFirst(self, FACTORY)
            if count == 2 and expect(factory ~= nil, "no factory module came back") then
                expect(factory.condition == PLAIN_FACTORY.condition, "the factory module came back at " .. factory.condition)
                expect(factory.repaired == 0, "the factory module came back sealed " .. factory.repaired .. "x")
                expect(factory.modData[PowerBank.MOUNTED_ONCE] ~= true, "the factory module came back marked as mounted before")
            end
        end,
    })
end

-- A mount nobody wrote modules to, as debug spawns make, holds new factory modules.
craftTest(craftName("RenewableEnergy_UnmountSolarRackMetal", "without_record_returns_new_modules"), {
    recipe = "RenewableEnergy_UnmountSolarRackMetal",
    from = "RenewableEnergy.SolarRackMetal",
    counts = { ["RenewableEnergy.SolarRackMetal"] = 0, [FACTORY] = RenewableEnergy.Specs.mounts.rack.modules, ["Base.MetalPipe"] = 4 },
})

-- Mounting teaches only modules never mounted before: a module mounted, unmounted and mounted
-- again teaches nothing the second time, and a rack of that module and a new one teaches the new
-- one's share. The XP is the authority's character's, read before and after each craft.
test("renewable_energy_craft_mount_xp_only_for_new_modules", {
    instant = true,
    run = function(self)
        local manager = getScriptManager()
        local recipes = {}
        for key, name in pairs({ flat = "RenewableEnergy_MakeSolarFlat", unmount = "RenewableEnergy_UnmountSolarFlat",
            rack = "RenewableEnergy_MakeSolarRackWood" }) do
            recipes[key] = T.need(self, manager:getCraftRecipe(name), "the recipe " .. name)
            if not recipes[key] then return end
        end
        local p = player()
        local module, flat = FACTORY, "RenewableEnergy.SolarFlat"
        T.learnRecipes(p)
        T.placeWorkTable(p)
        T.setPerk(self, Perks.Electricity, 3)
        T.setPerk(self, Perks.Woodwork, 4)
        self.xp = {}
        local function readXp(key)
            T.server(self, "electricityAward", { xp = 0 })
            T.step(function() self.xp[key] = self.server.electricityAward.xp end)
        end
        local function craft(recipe, fullType)
            T.waitForCarried(self, fullType, "this client's " .. fullType .. " to craft from")
            T.step(function() T.startCraft(self, recipe, T.carried(fullType)) end)
        end
        -- The flat mount's wire and screws, for each time it is made.
        local fixings = {}
        for _, input in ipairs(T.recipeInputs(recipes.flat, { module })) do
            if input.type ~= module and input.type ~= "Base.Screwdriver" then
                table.insert(fixings, input)
            end
        end
        T.give(self, "flat", T.recipeInputs(recipes.flat, { module }))
        readXp("start")
        craft(recipes.flat, module)
        readXp("mounted")
        craft(recipes.unmount, flat)
        T.give(self, "again", fixings)
        readXp("unmounted")
        craft(recipes.flat, module)
        readXp("remounted")
        craft(recipes.unmount, flat)
        -- The rack's inputs with one new module, beside the one mounted twice.
        local rack = {}
        for _, input in ipairs(T.recipeInputs(recipes.rack, { module })) do
            if input.type == module then
                input.count = input.count - 1
            end
            table.insert(rack, input)
        end
        T.waitForCarried(self, module, "this client's unmounted module")
        T.give(self, "rack", rack)
        readXp("unmountedAgain")
        craft(recipes.rack, module)
        T.batch(function()
            readXp("rack")
            T.count(self, "made", { flat, "RenewableEnergy.SolarRackWood", module })
            -- What the game gives this character for each award, through the call CraftRecipe.addXP
            -- makes.
            local mounts = Recipes.MOUNTS
            T.server(self, "electricityAward", { xp = mounts[flat].xp.Electricity })
            T.step(function() self.flatAward = self.server.electricityAward.gained end)
            T.server(self, "electricityAward", { xp = mounts["RenewableEnergy.SolarRackWood"].xp.Electricity / 2 })
            T.step(function() self.rackShareAward = self.server.electricityAward.gained end)
            -- The rack's own xpAward for building the frame, given whatever the modules.
            local frame = 0
            for i = 0, recipes.rack:getXPAwardCount() - 1 do
                local award = recipes.rack:getXPAward(i)
                if award:getPerk() == Perks.Electricity then frame = frame + award:getAmount() end
            end
            T.server(self, "electricityAward", { xp = frame })
            T.step(function() self.rackFrameAward = self.server.electricityAward.gained end)
        end)
    end,
    validate = function(self)
        local refusal = self.refusal and "; the game refused: " .. self.refusal or ""
        local xp, made = self.xp, self.counts.made or {}
        if not expect(xp.rack ~= nil and made["RenewableEnergy.SolarRackWood"] == 1,
            "the crafts never got to the rack" .. refusal) then return end
        expect(xp.mounted > xp.start, "mounting a new module gave no Electricity XP")
        expectNear("Electricity XP from mounting a new module", xp.mounted - xp.start, self.flatAward, 0.01)
        expectNear("Electricity XP from unmounting", xp.unmounted - xp.mounted, 0, 0)
        expectNear("Electricity XP from mounting the same module again", xp.remounted - xp.unmounted, 0, 0)
        expectNear("Electricity XP from a rack of a used and a new module", xp.rack - xp.unmountedAgain,
            self.rackShareAward + self.rackFrameAward, 0.01)
    end,
})

-- Solar modules --------------------------------------------------------------------------------

-- Seal Cracked Module adds 20 condition, up to 55 for a factory module and 40 for a homemade one,
-- less 10 for each earlier seal, and is refused at that limit with the module untouched. Each seal
-- counts once, on this client's copy too, and a sealed module still shows cracked. Each row: the
-- behaviour, the module, its condition and seal count before, its condition after, and whether
-- the game refuses.
local MODULE_REPAIRS = {
    { "factory_adds_a_step", FACTORY, 25, 0, 45 },
    { "factory_below_limit_stops_at_55", FACTORY, 54, 0, 55 },
    { "factory_at_limit_refused", FACTORY, 55, 0, 55, true },
    { "factory_after_two_seals_stops_at_35", FACTORY, 30, 2, 35 },
    { "factory_after_three_seals_at_25_refused", FACTORY, 25, 3, 25, true },
    { "homemade_below_limit_stops_at_40", HOMEMADE, 39, 0, 40 },
    { "homemade_after_one_seal_stops_at_30", HOMEMADE, 20, 1, 30 },
}
for _, entry in ipairs(MODULE_REPAIRS) do
    local behavior, module, before, repaired, after, refused = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
    local repairedAfter = refused and repaired or repaired + 1
    craftTest(craftName("RenewableEnergy_RepairCrackedModule", behavior), {
        recipe = "RenewableEnergy_RepairCrackedModule",
        from = module,
        prefer = { module },
        setup = function(self)
            T.changeItem(self, inputsOf(self, module)[1], { condition = before })
            setRepaired(self, module, repaired)
        end,
        counts = { [module] = 1 },
        after = function(self)
            readCarried(self, { module })
            T.waitFor(self, function()
                local item = T.carried(module)
                return item ~= nil and item:getHaveBeenRepaired() == repairedAfter
            end, "this client's module repaired " .. repairedAfter .. "x")
        end,
        validate = function(self)
            local item = carriedFirst(self, module)
            if not expect(item ~= nil, "the module is gone") then return end
            expect(item.condition == after, "the module is at " .. item.condition .. ", expected " .. after)
            expect(item.repaired == repairedAfter, "the module reads repaired " .. item.repaired .. "x, expected " .. repairedAfter)
            -- The seal leaves the glass cracked, and the module showing it.
            expect(item.condition < RenewableEnergy.Specs.crackedBelow, "a sealed module shows whole")
            if refused then
                expect(self.refusal ~= nil, "the game would start the seal")
            end
        end,
    })
end

-- Reglaze Module sets a module below what new glass brings it to, and is refused there with the
-- module and the pane untouched; it teaches Glassmaking, and the new glass clears the old seals.
-- Each row: the behaviour, the module, its condition and seal count before, its condition after,
-- and whether the game refuses.
local REGLAZE = Recipes.REGLAZE
local REGLAZES = {
    { "factory_cracked_set_to_new_glass", FACTORY, 20, 0, REGLAZE[FACTORY] },
    { "factory_sealed_three_times_clears_seals", FACTORY, 25, 3, REGLAZE[FACTORY] },
    { "factory_just_below_set_to_new_glass", FACTORY, REGLAZE[FACTORY] - 1, 0, REGLAZE[FACTORY] },
    { "factory_at_new_glass_refused", FACTORY, REGLAZE[FACTORY], 0, REGLAZE[FACTORY], true },
    { "homemade_cracked_set_to_new_glass", HOMEMADE, 20, 0, REGLAZE[HOMEMADE] },
    { "homemade_at_new_glass_refused", HOMEMADE, REGLAZE[HOMEMADE], 0, REGLAZE[HOMEMADE], true },
}
for _, entry in ipairs(REGLAZES) do
    local behavior, module, before, repaired, after, refused = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
    local repairedAfter = refused and repaired or 0
    craftTest(craftName("RenewableEnergy_ReglazeModule", behavior), {
        recipe = "RenewableEnergy_ReglazeModule",
        from = module,
        prefer = { module },
        setup = function(self)
            T.changeItem(self, inputsOf(self, module)[1], { condition = before })
            if repaired > 0 then
                setRepaired(self, module, repaired)
            end
            T.server(self, "perkXp", { perk = "Glassmaking" })
            T.step(function() self.glassmakingBefore = self.server.perkXp.value end)
        end,
        counts = { [module] = 1, ["Base.GlassPanel"] = refused and 1 or 0 },
        after = function(self)
            readCarried(self, { module })
            T.server(self, "perkXp", { perk = "Glassmaking" })
        end,
        validate = function(self)
            local item = carriedFirst(self, module)
            if not expect(item ~= nil, "the module is gone") then return end
            expect(item.condition == after, "the module is at " .. item.condition .. ", expected " .. after)
            expect(item.repaired == repairedAfter, "the module reads repaired " .. item.repaired .. "x, expected " .. repairedAfter)
            if refused then
                expect(self.refusal ~= nil, "the game would start the reglaze")
            else
                expect(item.condition >= RenewableEnergy.Specs.crackedBelow, "a reglazed module shows cracked")
                local xp = self.server and self.server.perkXp
                expect(xp and self.glassmakingBefore and xp.value > self.glassmakingBefore, "reglazing taught no Glassmaking")
            end
        end,
    })
end

craftTest(craftName("RenewableEnergy_MakeHomemadeSolarModule"), {
    recipe = "RenewableEnergy_MakeHomemadeSolarModule",
    from = "RenewableEnergy.SolarCells",
    counts = { ["RenewableEnergy.SolarCells"] = 0, ["RenewableEnergy.HomemadeSolarModule"] = 1 },
})

-- Taking things apart for their cells. A garden light gives back the plain bulb it comes with.
local TAKE_APART = {
    { "RenewableEnergy_TakeApartCalculator", "Base.Calculator", 1, { ["Base.ElectronicsScrap"] = 1 } },
    { "RenewableEnergy_TakeApartSolarGardenLight", RenewableEnergy.SolarGardenLight.ITEM, 2,
        { [RenewableEnergy.SolarGardenLight.PLAIN_BULB] = 1 } },
    { "RenewableEnergy_TakeApartSolarCellCharger", RenewableEnergy.SolarCellCharger.ITEM, 4 },
    { "RenewableEnergy_TakeApartSolarMaintainer", RenewableEnergy.SolarMaintainer.ITEM, 6 },
}
for _, entry in ipairs(TAKE_APART) do
    local recipe, input, cells = entry[1], entry[2], entry[3]
    local counts = { [input] = 0, ["RenewableEnergy.SolarCells"] = cells }
    for fullType, count in pairs(entry[4] or {}) do
        counts[fullType] = count
    end
    craftTest(craftName(recipe), { recipe = recipe, from = input, counts = counts })
end

-- Only a module that makes no power comes apart: one at 0 does, one at 1 is worth more whole.
for _, entry in ipairs({ { nil, 0 }, { "refuses_working_module", 1 } }) do
    local behavior, condition = entry[1], entry[2]
    local refused = condition > 0
    craftTest(craftName("RenewableEnergy_TakeApartShatteredModule", behavior), {
        recipe = "RenewableEnergy_TakeApartShatteredModule",
        from = FACTORY,
        setup = function(self)
            T.changeItem(self, inputsOf(self, FACTORY)[1], { condition = condition })
        end,
        counts = { [FACTORY] = refused and 1 or 0, ["RenewableEnergy.SolarCells"] = refused and 0 or 12 },
        validate = function(self)
            if refused then
                expect(self.refusal ~= nil, "the game would take a working module apart")
            end
        end,
    })
end

-- Battery repairs ------------------------------------------------------------------------------

-- Each row: the recipe, the behaviour, the car battery's condition and repair count before, its
-- condition and charge after, and whether the game refuses. Every battery starts at START_CHARGE.
-- A repair brings a battery at most to its repair limit, 85 less 10 per earlier repair: Service
-- adds a step and keeps the charge, Recondition sets the limit and empties the battery, and both
-- are refused at the limit. A repair the game makes counts once, on this client's copy too.
local CAR_BATTERY = "Base.CarBattery2"
local START_CHARGE = 0.7
local BATTERY_REPAIRS = {
    { "RenewableEnergy_ServiceBattery", "adds_a_step", 30, 0, 40, START_CHARGE },
    { "RenewableEnergy_ServiceBattery", "below_limit_stops_at_limit", 80, 0, 85, START_CHARGE },
    { "RenewableEnergy_ServiceBattery", "after_two_repairs_stops_at_65", 60, 2, 65, START_CHARGE },
    { "RenewableEnergy_ServiceBattery", "at_limit_refused", 85, 0, 85, START_CHARGE, true },
    { "RenewableEnergy_ReconditionBattery", "restores_and_empties", 30, 0, 85, 0 },
    { "RenewableEnergy_ReconditionBattery", "after_two_repairs_gives_65", 30, 2, 65, 0 },
    { "RenewableEnergy_ReconditionBattery", "at_limit_refused", 65, 2, 65, START_CHARGE, true },
    { "RenewableEnergy_ReconditionBattery", "past_last_repair_refused", 1, 9, 1, START_CHARGE, true },
}
for _, entry in ipairs(BATTERY_REPAIRS) do
    local recipe, behavior, before, repaired, after, charge, refused = entry[1], entry[2], entry[3], entry[4], entry[5],
        entry[6], entry[7]
    local repairedAfter = refused and repaired or repaired + 1
    craftTest(craftName(recipe, behavior), {
        recipe = recipe,
        from = CAR_BATTERY,
        prefer = { CAR_BATTERY, "RenewableEnergy.BatteryElectrolyte" },
        setup = function(self)
            T.changeItem(self, inputsOf(self, CAR_BATTERY)[1], { condition = before, uses = START_CHARGE })
            setRepaired(self, CAR_BATTERY, repaired)
            T.server(self, "refillFluid", { type = "RenewableEnergy.BatteryElectrolyte", fluid = "Water", liters = 1 })
            waitForFluid(self, "RenewableEnergy.BatteryElectrolyte", 1)
        end,
        counts = { [CAR_BATTERY] = 1 },
        after = function(self)
            readCarried(self, { CAR_BATTERY })
            -- The tooltip's "Repaired: Nx" reads this client's copy.
            T.waitFor(self, function()
                local battery = T.carried(CAR_BATTERY)
                return battery ~= nil and battery:getHaveBeenRepaired() == repairedAfter
            end, "this client's battery repaired " .. repairedAfter .. "x")
        end,
        validate = function(self)
            local battery = carriedFirst(self, CAR_BATTERY)
            if not expect(battery ~= nil, "the battery is gone") then return end
            expect(battery.condition == after, "the battery is at " .. battery.condition .. ", expected " .. after)
            expect(battery.repaired == repairedAfter, "the battery reads repaired " .. battery.repaired .. "x, expected " .. repairedAfter)
            expectNear("the battery's charge", battery.uses, charge, 0.001)
            if refused then
                expect(self.refusal ~= nil, "the game would start the repair")
            end
        end,
    })
end

-- Stripping a battery past its last repair and rebuilding it from its own case, with new plates in
-- place of the recast: the battery comes back new and empty, its acid goes out and back in, and
-- it has no repairs behind it, so a Recondition takes it to the full 85 again.
local REBUILDS = {
    { battery = "Base.CarBattery2", case = "RenewableEnergy.CarBatteryCase", plates = 1,
      strip = "RenewableEnergy_StripCarBattery", rebuild = "RenewableEnergy_RebuildCarBattery" },
    { battery = "RenewableEnergy.DeepCycleBattery", case = "RenewableEnergy.DeepCycleBatteryCase", plates = 2,
      strip = "RenewableEnergy_StripDeepCycleBattery", rebuild = "RenewableEnergy_RebuildDeepCycleBattery" },
    { battery = "RenewableEnergy.L16Battery", case = "RenewableEnergy.L16BatteryCase", plates = 3,
      strip = "RenewableEnergy_StripL16Battery", rebuild = "RenewableEnergy_RebuildL16Battery" },
}
for _, chain in ipairs(REBUILDS) do
    local counted = { chain.case, "RenewableEnergy.WornBatteryPlates", chain.battery, "RenewableEnergy.BatteryPlates" }
    test(craftName(chain.rebuild, "from_its_stripped_case"), {
        instant = true,
        run = function(self)
            local manager = getScriptManager()
            local strip = T.need(self, manager:getCraftRecipe(chain.strip), "the recipe " .. chain.strip)
            local rebuild = T.need(self, manager:getCraftRecipe(chain.rebuild), "the recipe " .. chain.rebuild)
            if not (strip and rebuild) then return end
            local p = player()
            T.learnRecipes(p)
            T.placeWorkTable(p)
            T.setPerk(self, Perks.Electricity, 5)
            -- One empty litre bottle per litre of acid.
            local given = { { type = "Base.Screwdriver" }, { type = "Base.Wrench" }, { type = "Base.Gloves_Dish" },
                { type = chain.battery, condition = 20, uses = 0.6 } }
            for _ = 1, chain.plates do
                table.insert(given, { type = "RenewableEnergy.BatteryElectrolyte" })
            end
            T.give(self, "inputs", given)
            setRepaired(self, chain.battery, 9)
            T.server(self, "refillFluid", { type = "RenewableEnergy.BatteryElectrolyte" })
            waitForFluid(self, "RenewableEnergy.BatteryElectrolyte", 0)
            T.step(function() T.startCraft(self, strip, inputsOf(self, chain.battery)[1]) end)
            readCarried(self, counted, { "Acid" })
            T.step(function()
                local carried = self.server.carried
                self.stripped = {
                    case = #carried.items[chain.case], worn = #carried.items["RenewableEnergy.WornBatteryPlates"],
                    acid = carried.fluids.Acid, batteries = #carried.items[chain.battery],
                }
            end)
            -- New plates in place of the worn, and a litre of water to top up.
            T.server(self, "takeItems", { type = "RenewableEnergy.WornBatteryPlates" })
            T.give(self, "rebuild", { { type = "RenewableEnergy.BatteryPlates", count = chain.plates },
                { type = "Base.WaterBottle" } })
            T.server(self, "refillFluid", { type = "Base.WaterBottle", fluid = "Water", liters = 1 })
            T.waitForCarried(self, chain.case, "this client's " .. chain.case)
            waitForFluid(self, "Base.WaterBottle", 1)
            T.step(function() T.startCraft(self, rebuild, T.carried(chain.case)) end)
            readCarried(self, counted, { "Acid" })
            T.step(function()
                self.rebuilt = carriedFirst(self, chain.battery)
                self.rebuiltCarried = self.server.carried
            end)
            -- Worn down again, then reconditioned.
            T.waitForCarried(self, chain.battery, "this client's rebuilt " .. chain.battery)
            T.step(function() T.changeItem(self, T.carried(chain.battery), { condition = 30 }) end)
            T.give(self, "recondition", { { type = "Base.BakingSoda", count = 2 } })
            T.server(self, "refillFluid", { type = "Base.WaterBottle", fluid = "Water", liters = 1 })
            waitForFluid(self, "Base.WaterBottle", 1)
            T.step(function()
                local recondition = getScriptManager():getCraftRecipe("RenewableEnergy_ReconditionBattery")
                T.startCraft(self, recondition, T.carried(chain.battery))
            end)
            readCarried(self, { chain.battery })
        end,
        validate = function(self)
            local refusal = self.refusal and "; the game refused: " .. self.refusal or ""
            local s = self.stripped
            if not expect(s ~= nil, "the strip step never ran" .. refusal) then return end
            expect(s.batteries == 0 and s.case == 1 and s.worn == chain.plates,
                "stripping left " .. s.batteries .. " batteries, " .. s.case .. " cases, " .. s.worn .. " worn plates" .. refusal)
            expectNear("acid poured out by stripping", s.acid, chain.plates, 0.01)
            local carried = self.rebuiltCarried
            local battery = self.rebuilt
            if expect(battery ~= nil, "no " .. chain.battery .. " was rebuilt" .. refusal) then
                expect(battery.condition == 100, "the rebuilt battery is at " .. battery.condition)
                expectNear("the rebuilt battery's charge", battery.uses, 0, 0.001)
                expect(battery.repaired == 0, "the rebuilt battery reads repaired " .. battery.repaired .. "x")
            end
            expect(#carried.items[chain.case] == 0, "the case is still there")
            expect(#carried.items["RenewableEnergy.BatteryPlates"] == 0, "plates are left over")
            expectNear("acid left after rebuilding", carried.fluids.Acid, 0, 0.01)
            local reconditioned = carriedFirst(self, chain.battery)
            if expect(reconditioned ~= nil, "the rebuilt battery is gone" .. refusal) then
                expect(reconditioned.condition == 85, "the rebuilt battery reconditions to " .. reconditioned.condition .. refusal)
            end
        end,
    })
end

-- Battery plates -------------------------------------------------------------------------------

-- The plate mold the way vanilla makes its ingot mold: a wooden pattern at a table, pressed into
-- clay at a hand press and fired in a kiln; the pattern and the mold last. Lead plates are
-- recast in a primitive furnace burning charcoal, and lose lead doing it: three worn sets make
-- two new ones, or two and a lead pipe do, and two worn sets alone make nothing.
craftTest(craftName("RenewableEnergy_MakeBatteryPlatePattern"), {
    recipe = "RenewableEnergy_MakeBatteryPlatePattern",
    from = "Base.Plank",
    counts = { ["Base.Plank"] = 0, ["Base.Nails"] = 0, ["RenewableEnergy.WoodenBatteryPlatePattern"] = 1 },
})

craftTest(craftName("RenewableEnergy_PressBatteryPlateMold"), {
    recipe = "RenewableEnergy_PressBatteryPlateMold",
    bench = { "Base.Hand_Press", "crafted_01_72" },
    from = "Base.Clay",
    counts = {
        ["Base.Clay"] = 0, ["RenewableEnergy.WoodenBatteryPlatePattern"] = 1, ["RenewableEnergy.BatteryPlateMoldUnfired"] = 1,
    },
})

craftTest(craftName("RenewableEnergy_FireBatteryPlateMold"), {
    recipe = "RenewableEnergy_FireBatteryPlateMold",
    bench = { "Base.Kiln_Small", "crafted_01_56" },
    from = "RenewableEnergy.BatteryPlateMoldUnfired",
    prefer = { "Base.Log" },
    counts = { ["RenewableEnergy.BatteryPlateMoldUnfired"] = 0, ["Base.Log"] = 0, ["RenewableEnergy.BatteryPlateMold"] = 1 },
})

local WORN, PLATES = "RenewableEnergy.WornBatteryPlates", "RenewableEnergy.BatteryPlates"
local FURNACE = { "Base.Primitive_Furnace", "crafted_01_112" }

craftTest(craftName("RenewableEnergy_RecastBatteryPlates", "three_worn_make_two"), {
    recipe = "RenewableEnergy_RecastBatteryPlates",
    bench = FURNACE,
    from = WORN,
    prefer = { "Base.Charcoal" },
    counts = { [WORN] = 0, ["Base.Charcoal"] = 0, ["RenewableEnergy.BatteryPlateMold"] = 1, [PLATES] = 2 },
})

craftTest(craftName("RenewableEnergy_RecastBatteryPlates", "lead_pipe_makes_up_the_loss"), {
    recipe = "RenewableEnergy_RecastBatteryPlates",
    bench = FURNACE,
    from = WORN,
    prefer = { "Base.LeadPipe", "Base.Charcoal" },
    counts = { [WORN] = 0, ["Base.LeadPipe"] = 0, ["Base.Charcoal"] = 0, [PLATES] = 2 },
})

craftTest(craftName("RenewableEnergy_RecastBatteryPlates", "refuses_two_worn"), {
    recipe = "RenewableEnergy_RecastBatteryPlates",
    bench = FURNACE,
    from = WORN,
    prefer = { "Base.Charcoal" },
    setup = function(self)
        T.server(self, "takeItems", { ids = { inputsOf(self, WORN)[3]:getID() } })
    end,
    counts = { [WORN] = 2, [PLATES] = 0 },
    validate = function(self)
        expect(self.refusal ~= nil, "the game would recast two worn sets of plates")
    end,
})

-- New lead with no case: three lead pipes cast one set of plates.
craftTest(craftName("RenewableEnergy_CastBatteryPlatesFromLeadPipe", "three_pipes_make_one"), {
    recipe = "RenewableEnergy_CastBatteryPlatesFromLeadPipe",
    bench = FURNACE,
    from = "Base.LeadPipe",
    prefer = { "Base.Charcoal" },
    counts = { ["Base.LeadPipe"] = 0, ["Base.Charcoal"] = 0, ["RenewableEnergy.BatteryPlateMold"] = 1, [PLATES] = 1 },
})

-- Jar batteries -------------------------------------------------------------------------------

-- Six empty jars, a set of plates, a litre of acid and two of water in a sand tray: a new jar
-- battery, empty. Acid comes from battery acid bottles, the water from a 2 L bottle.
local JAR_BATTERY = "RenewableEnergy.JarBattery"
craftTest(craftName("RenewableEnergy_MakeJarBattery"), {
    recipe = "RenewableEnergy_MakeJarBattery",
    from = PLATES,
    prefer = { "RenewableEnergy.BatteryElectrolyte", "Base.EmptyJar", "Base.Sandbag" },
    setup = function(self)
        T.give(self, "water", { { type = "Base.PopBottle" } })
        T.server(self, "refillFluid", { type = "Base.PopBottle", fluid = "Water", liters = 2 })
        waitForFluid(self, "Base.PopBottle", 2)
    end,
    counts = {
        [JAR_BATTERY] = 1, ["Base.EmptyJar"] = 0, [PLATES] = 0, ["Base.Plank"] = 0, ["Base.Nails"] = 0,
        ["Base.ElectricWire"] = 0,
    },
    after = function(self) readCarried(self, { JAR_BATTERY }, { "Acid", "Water" }) end,
    validate = function(self)
        local battery = carriedFirst(self, JAR_BATTERY)
        if not expect(battery ~= nil, "no jar battery was made") then return end
        expect(battery.condition == 100, "the new jar battery is at " .. battery.condition)
        expectNear("the new jar battery's charge", battery.uses, 0, 0.001)
        local fluids = self.server.carried.fluids
        expectNear("acid left of two litres", fluids.Acid, 1, 0.01)
        expectNear("water left of two litres", fluids.Water, 0, 0.01)
    end,
})

-- A dead jar battery strips too: five jars whole and one cracked, its plates worn, its acid
-- poured into an empty bottle.
craftTest(craftName("RenewableEnergy_StripJarBattery", "dead_battery"), {
    recipe = "RenewableEnergy_StripJarBattery",
    from = JAR_BATTERY,
    prefer = { "RenewableEnergy.BatteryElectrolyte", "Base.Gloves_Dish" },
    setup = function(self)
        T.changeItem(self, inputsOf(self, JAR_BATTERY)[1], { condition = 0 })
        T.server(self, "refillFluid", { type = "RenewableEnergy.BatteryElectrolyte" })
        waitForFluid(self, "RenewableEnergy.BatteryElectrolyte", 0)
    end,
    counts = { [JAR_BATTERY] = 0, ["Base.EmptyJar"] = 5, ["Base.BrokenGlass"] = 1, [WORN] = 1 },
    after = function(self) readCarried(self, {}, { "Acid" }) end,
    validate = function(self)
        expectNear("acid poured out", self.server.carried.fluids.Acid, 1, 0.01)
    end,
})
