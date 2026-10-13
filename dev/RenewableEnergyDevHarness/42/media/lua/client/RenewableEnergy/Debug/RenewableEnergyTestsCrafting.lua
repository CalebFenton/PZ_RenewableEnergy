require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/PowerBank/PowerBank"

-- Crafting tests: every recipe crafted the way a player starts it, instantly, with the inputs the
-- authority gave, which also makes the outputs (T.craftTest). What a test then reads of the
-- items it reads from the authority's copies, through the carried handler of
-- RenewableEnergyTestServerWorld.lua. See RenewableEnergyTestLib.lua for the runner and the
-- helpers.

local T = RenewableEnergyTest
local test, craftTest, expect, expectNear, player = T.test, T.craftTest, T.expect, T.expectNear, T.player
local PowerBank = RenewableEnergy.PowerBank
local MODULES_KEY = PowerBank.MODULES

-- The test name for `recipe`: "RenewableEnergy_TakeApartSolarCellCharger", "returns_x" ->
-- "renewable_energy_craft_take_apart_solar_cell_charger_returns_x".
local function craftName(recipe, behavior)
    local name = recipe:gsub("^RenewableEnergy_", ""):gsub("(%l)(%u)", "%1_%2"):gsub("(%d)(%u)", "%1_%2")
    return "renewable_energy_craft_" .. string.lower(name) .. (behavior and "_" .. behavior or "")
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

-- Queues filling every given input of `fullType` with `liters` of `fluid` (nil leaves it empty),
-- on the authority, which sends it here.
local function refill(self, fullType, fluid, liters)
    for _, item in ipairs(inputsOf(self, fullType)) do
        T.server(self, "refillFluid", { id = item:getID(), fluid = fluid, liters = liters })
    end
end

-- Bank tiers and parts -------------------------------------------------------------------------

-- Each recipe makes one item and uses up its materials.
local MAKES = {
    { "RenewableEnergy_MakeBatteryBoxWood", "RenewableEnergy.BatteryBoxWood", { "Base.Plank", "Base.Nails" } },
    { "RenewableEnergy_MakeBatteryBoxMetal", "RenewableEnergy.BatteryBoxMetal", { "Base.SmallSheetMetal" } },
    { "RenewableEnergy_BuildBatteryRackWood", "RenewableEnergy.BatteryRackWood", { "Base.Plank", "Base.Nails" } },
    { "RenewableEnergy_BuildBatteryRackMetal", "RenewableEnergy.BatteryRackMetal", { "Base.SmallSheetMetal", "Base.MetalBar" } },
    { "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy.BatteryBankWood", { "Base.Plank", "Base.Nails" } },
    { "RenewableEnergy_BuildBatteryBankMetal", "RenewableEnergy.BatteryBankMetal", { "Base.SheetMetal", "Base.MetalBar" } },
    { "RenewableEnergy_MakeChargeController", "RenewableEnergy.ChargeController",
        { "Base.ElectronicsScrap", "Base.ElectricWire", "Base.SmallSheetMetal", "Base.Amplifier" } },
    { "RenewableEnergy_MakeSolarFailsafe", "RenewableEnergy.SolarFailsafe",
        { "Base.RemoteCraftedV3", "Base.ElectronicsScrap", "Base.ElectricWire" } },
}
for _, entry in ipairs(MAKES) do
    local recipe, result, materials = entry[1], entry[2], entry[3]
    local counts = { [result] = 1 }
    for _, material in ipairs(materials) do
        counts[material] = 0
    end
    craftTest(craftName(recipe), { recipe = recipe, from = materials[1], counts = counts })
end

-- Panel mounts ---------------------------------------------------------------------------------

-- Mounts remember each module's type and condition.
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
        local got = modules[i]
        expect(got.type == want.type and got.condition == want.condition,
            "module " .. i .. " is " .. tostring(got.type) .. " at " .. tostring(got.condition)
            .. ", expected " .. want.type .. " at " .. want.condition)
    end
end

local MOUNTS = {
    { "RenewableEnergy_MakeSolarFlat", "RenewableEnergy.SolarFlat", 1 },
    { "RenewableEnergy_MakeSolarWallWood", "RenewableEnergy.SolarWallWood", 1 },
    { "RenewableEnergy_MakeSolarWallMetal", "RenewableEnergy.SolarWallMetal", 1 },
    { "RenewableEnergy_MakeSolarRackWood", "RenewableEnergy.SolarRackWood", 2 },
    { "RenewableEnergy_MakeSolarRackMetal", "RenewableEnergy.SolarRackMetal", 2 },
}
for _, entry in ipairs(MOUNTS) do
    local recipe, mount, count = entry[1], entry[2], entry[3]
    craftTest(craftName(recipe, "keeps_module_condition"), {
        recipe = recipe,
        from = "RenewableEnergy.SolarModule",
        prefer = { "RenewableEnergy.SolarModule" },
        setup = function(self)
            local modules = inputsOf(self, "RenewableEnergy.SolarModule")
            T.changeItem(self, modules[1], { condition = 72 })
            if count == 2 then
                -- One of the two a homemade module instead.
                T.server(self, "takeItems", { ids = { modules[2]:getID() } })
                T.give(self, "homemade", { { type = "RenewableEnergy.HomemadeSolarModule", condition = 41 } })
            end
        end,
        counts = { ["RenewableEnergy.SolarModule"] = 0, ["RenewableEnergy.HomemadeSolarModule"] = 0, [mount] = 1 },
        validate = function(self)
            local expected = { { type = "RenewableEnergy.SolarModule", condition = 72 } }
            if count == 2 then
                table.insert(expected, { type = "RenewableEnergy.HomemadeSolarModule", condition = 41 })
            end
            expectModules(carriedFirst(self, mount), expected)
        end,
        after = function(self) readCarried(self, { mount }) end,
    })
end

-- Unmounting gives back each module as the type and at the condition it went in, still marked as
-- mounted and connected before if it was.
local UNMOUNTS = {
    { "RenewableEnergy_UnmountSolarFlat", "RenewableEnergy.SolarFlat" },
    { "RenewableEnergy_UnmountSolarWallWood", "RenewableEnergy.SolarWallWood" },
    { "RenewableEnergy_UnmountSolarWallMetal", "RenewableEnergy.SolarWallMetal" },
    { "RenewableEnergy_UnmountSolarRackWood", "RenewableEnergy.SolarRackWood" },
    { "RenewableEnergy_UnmountSolarRackMetal", "RenewableEnergy.SolarRackMetal" },
}
for _, entry in ipairs(UNMOUNTS) do
    local recipe, mount = entry[1], entry[2]
    local rack = mount:find("Rack") ~= nil
    craftTest(craftName(recipe, "returns_modules"), {
        recipe = recipe,
        from = mount,
        setup = function(self)
            local modules = { { type = "RenewableEnergy.HomemadeSolarModule", condition = 41, mounted = true, connected = true } }
            if rack then
                table.insert(modules, { type = "RenewableEnergy.SolarModule", condition = 12 })
            end
            T.changeItem(self, inputsOf(self, mount)[1], { modData = { [MODULES_KEY] = modules } })
        end,
        counts = {
            [mount] = 0,
            ["RenewableEnergy.HomemadeSolarModule"] = 1,
            ["RenewableEnergy.SolarModule"] = rack and 1 or 0,
        },
        after = function(self)
            readCarried(self, { "RenewableEnergy.HomemadeSolarModule", "RenewableEnergy.SolarModule" })
        end,
        validate = function(self)
            local homemade = carriedFirst(self, "RenewableEnergy.HomemadeSolarModule")
            expect(homemade == nil or homemade.condition == 41,
                "the homemade module came back at " .. tostring(homemade and homemade.condition))
            local data = homemade and homemade.modData or {}
            expect(homemade == nil or (data[PowerBank.MOUNTED_ONCE] == true and data[PowerBank.CONNECTED_ONCE] == true),
                "the homemade module came back without its mounted and connected marks")
            local factory = carriedFirst(self, "RenewableEnergy.SolarModule")
            expect(factory == nil or factory.condition == 12,
                "the factory module came back at " .. tostring(factory and factory.condition))
        end,
    })
end

-- A mount nobody wrote modules to, as debug spawns make, holds new factory modules.
craftTest(craftName("RenewableEnergy_UnmountSolarRackMetal", "without_record_returns_new_modules"), {
    recipe = "RenewableEnergy_UnmountSolarRackMetal",
    from = "RenewableEnergy.SolarRackMetal",
    counts = { ["RenewableEnergy.SolarRackMetal"] = 0, ["RenewableEnergy.SolarModule"] = 2, ["Base.MetalPipe"] = 4 },
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
        local module, flat = "RenewableEnergy.SolarModule", "RenewableEnergy.SolarFlat"
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
            T.waitForCopy(function() return p:getInventory():getFirstTypeRecurse(fullType) ~= nil end)
            T.step(function()
                local from = p:getInventory():getFirstTypeRecurse(fullType)
                if from then
                    T.startCraft(self, recipe, from)
                end
            end)
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
        T.waitForCopy(function() return p:getInventory():getFirstTypeRecurse(module) ~= nil end)
        T.give(self, "rack", rack)
        readXp("unmountedAgain")
        craft(recipes.rack, module)
        readXp("rack")
        T.count(self, "made", { flat, "RenewableEnergy.SolarRackWood", module })
        -- What the game gives this character for each award, through the call CraftRecipe.addXP
        -- makes.
        local mountXp = RenewableEnergy.Recipes.MOUNT_XP
        T.server(self, "electricityAward", { xp = mountXp[flat].Electricity })
        T.step(function() self.flatAward = self.server.electricityAward.gained end)
        T.server(self, "electricityAward", { xp = mountXp["RenewableEnergy.SolarRackWood"].Electricity / 2 })
        T.step(function() self.rackShareAward = self.server.electricityAward.gained end)
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
        expectNear("Electricity XP from a rack of a used and a new module", xp.rack - xp.unmountedAgain, self.rackShareAward, 0.01)
    end,
})

-- Solar modules --------------------------------------------------------------------------------

-- Repair Cracked Module: +30, up to 80 for a factory module and 60 for a homemade one, and
-- refused at the cap, with the module untouched.
local MODULE_REPAIRS = {
    { "factory_adds_30", "RenewableEnergy.SolarModule", 40, 70 },
    { "factory_stops_at_80", "RenewableEnergy.SolarModule", 65, 80 },
    { "homemade_stops_at_60", "RenewableEnergy.HomemadeSolarModule", 45, 60 },
    { "factory_at_cap_refused", "RenewableEnergy.SolarModule", 80, 80, true },
    { "homemade_at_cap_refused", "RenewableEnergy.HomemadeSolarModule", 60, 60, true },
}
for _, entry in ipairs(MODULE_REPAIRS) do
    local behavior, module, before, after, refused = entry[1], entry[2], entry[3], entry[4], entry[5]
    craftTest(craftName("RenewableEnergy_RepairCrackedModule", behavior), {
        recipe = "RenewableEnergy_RepairCrackedModule",
        from = module,
        prefer = { module },
        setup = function(self)
            T.changeItem(self, inputsOf(self, module)[1], { condition = before })
        end,
        counts = { [module] = 1, ["Base.GlassPanel"] = refused and 1 or 0 },
        after = function(self) readCarried(self, { module }) end,
        validate = function(self)
            local item = carriedFirst(self, module)
            expect(item and item.condition == after,
                "the module is at " .. tostring(item and item.condition) .. ", expected " .. after)
            if refused then
                expect(self.refusal ~= nil, "the game would start the repair")
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
    { "RenewableEnergy_TakeApartSolarGardenLight", "RenewableEnergy.SolarGardenLight", 2, { ["Base.LightBulb"] = 1 } },
    { "RenewableEnergy_TakeApartSolarCellCharger", "RenewableEnergy.SolarCellCharger", 4 },
    { "RenewableEnergy_TakeApartSolarMaintainer", "RenewableEnergy.SolarMaintainer", 6 },
}
for _, entry in ipairs(TAKE_APART) do
    local recipe, input, cells = entry[1], entry[2], entry[3]
    local counts = { [input] = 0, ["RenewableEnergy.SolarCells"] = cells }
    for fullType, count in pairs(entry[4] or {}) do
        counts[fullType] = count
    end
    craftTest(craftName(recipe), { recipe = recipe, from = input, counts = counts })
end

craftTest(craftName("RenewableEnergy_TakeApartShatteredModule"), {
    recipe = "RenewableEnergy_TakeApartShatteredModule",
    from = "RenewableEnergy.SolarModule",
    setup = function(self)
        T.changeItem(self, inputsOf(self, "RenewableEnergy.SolarModule")[1], { condition = 0 })
    end,
    counts = { ["RenewableEnergy.SolarModule"] = 0, ["RenewableEnergy.SolarCells"] = 12 },
})

-- A module that still makes power is worth more whole.
craftTest(craftName("RenewableEnergy_TakeApartShatteredModule", "refuses_working_module"), {
    recipe = "RenewableEnergy_TakeApartShatteredModule",
    from = "RenewableEnergy.SolarModule",
    setup = function(self)
        T.changeItem(self, inputsOf(self, "RenewableEnergy.SolarModule")[1], { condition = 20 })
    end,
    counts = { ["RenewableEnergy.SolarModule"] = 1, ["RenewableEnergy.SolarCells"] = 0 },
    validate = function(self)
        expect(self.refusal ~= nil, "the game would take a working module apart")
    end,
})

-- Battery repairs ------------------------------------------------------------------------------

-- Each repair on a car battery that starts at `before` condition and 70% charge.
local CAR_BATTERY = "Base.CarBattery2"
local BATTERY_REPAIRS = {
    { "RenewableEnergy_ServiceBattery", "adds_10", 30, 40, 0.7 },
    { "RenewableEnergy_ServiceBattery", "stops_at_60", 55, 60, 0.7 },
    { "RenewableEnergy_ServiceBattery", "at_cap_refused", 60, 60, 0.7, true },
    { "RenewableEnergy_ReconditionBattery", "restores_85_and_empties", 30, 85, 0 },
    { "RenewableEnergy_ReconditionBattery", "above_85_refused", 90, 90, 0.7, true },
}
for _, entry in ipairs(BATTERY_REPAIRS) do
    local recipe, behavior, before, after, charge, refused = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
    craftTest(craftName(recipe, behavior), {
        recipe = recipe,
        from = CAR_BATTERY,
        prefer = { CAR_BATTERY, "RenewableEnergy.BatteryElectrolyte" },
        setup = function(self)
            T.changeItem(self, inputsOf(self, CAR_BATTERY)[1], { condition = before, uses = 0.7 })
            refill(self, "RenewableEnergy.BatteryElectrolyte", "Water", 1)
        end,
        counts = { [CAR_BATTERY] = 1 },
        after = function(self) readCarried(self, { CAR_BATTERY }) end,
        validate = function(self)
            local battery = carriedFirst(self, CAR_BATTERY)
            if not expect(battery ~= nil, "the battery is gone") then return end
            expect(battery.condition == after, "the battery is at " .. battery.condition .. ", expected " .. after)
            expectNear("the battery's charge", battery.uses, charge, 0.001)
            if refused then
                expect(self.refusal ~= nil, "the game would start the repair")
            end
        end,
    })
end

-- Stripping a battery and rebuilding it from its own case, with new plates in place of the
-- recast: the battery comes back new and empty, and its acid goes out and back in.
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
            T.step(function()
                refill(self, "RenewableEnergy.BatteryElectrolyte", nil)
                T.step(function()
                    T.startCraft(self, strip, inputsOf(self, chain.battery)[1])
                    readCarried(self, counted, { "Acid" })
                    T.step(function()
                        local carried = self.server.carried
                        self.stripped = {
                            case = #carried.items[chain.case], worn = #carried.items["RenewableEnergy.WornBatteryPlates"],
                            acid = carried.fluids.Acid, batteries = #carried.items[chain.battery],
                        }
                        -- New plates in place of the worn, and a litre of water to top up.
                        T.server(self, "takeItems", { type = "RenewableEnergy.WornBatteryPlates" })
                        T.give(self, "rebuild", { { type = "RenewableEnergy.BatteryPlates", count = chain.plates },
                            { type = "Base.WaterBottle" } })
                        T.server(self, "refillFluid", function()
                            return { id = self.items.rebuild[#self.items.rebuild]:getID(), fluid = "Water", liters = 1 }
                        end)
                        T.waitForCopy(function() return p:getInventory():getFirstTypeRecurse(chain.case) ~= nil end)
                        T.step(function()
                            local case = p:getInventory():getFirstTypeRecurse(chain.case)
                            if case then
                                T.startCraft(self, rebuild, case)
                            end
                            readCarried(self, counted, { "Acid" })
                        end)
                    end)
                end)
            end)
        end,
        validate = function(self)
            local refusal = self.refusal and "; the game refused: " .. self.refusal or ""
            local s = self.stripped
            if not expect(s ~= nil, "the strip step never ran" .. refusal) then return end
            expect(s.batteries == 0 and s.case == 1 and s.worn == chain.plates,
                "stripping left " .. s.batteries .. " batteries, " .. s.case .. " cases, " .. s.worn .. " worn plates" .. refusal)
            expectNear("acid poured out by stripping", s.acid, chain.plates, 0.01)
            local carried = self.server.carried
            local battery = carriedFirst(self, chain.battery)
            if expect(battery ~= nil, "no " .. chain.battery .. " was rebuilt" .. refusal) then
                expect(battery.condition == 100, "the rebuilt battery is at " .. battery.condition)
                expectNear("the rebuilt battery's charge", battery.uses, 0, 0.001)
            end
            expect(#carried.items[chain.case] == 0, "the case is still there")
            expect(#carried.items["RenewableEnergy.BatteryPlates"] == 0, "plates are left over")
            expectNear("acid left after rebuilding", carried.fluids.Acid, 0, 0.01)
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
})
