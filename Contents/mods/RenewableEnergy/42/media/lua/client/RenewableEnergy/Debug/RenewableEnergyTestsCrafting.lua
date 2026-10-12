require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/PowerBank/PowerBank"

-- Crafting tests: every recipe crafted the way a player starts it, instantly. See
-- RenewableEnergyTestLib.lua for the runner and the helpers.

local T = RenewableEnergyTest
local test, craftTest, expect, expectNear, player = T.test, T.craftTest, T.expect, T.expectNear, T.player
local MODULES_KEY = RenewableEnergy.PowerBank.MODULES

-- The test name for `recipe`: "RenewableEnergy_TakeApartSolarCellCharger", "returns_x" ->
-- "renewable_energy_craft_take_apart_solar_cell_charger_returns_x".
local function craftName(recipe, behavior)
    local name = recipe:gsub("^RenewableEnergy_", ""):gsub("(%l)(%u)", "%1_%2"):gsub("(%d)(%u)", "%1_%2")
    return "renewable_energy_craft_" .. string.lower(name) .. (behavior and "_" .. behavior or "")
end

local function first(fullType)
    return player():getInventory():getFirstTypeRecurse(fullType)
end

-- Every container the craft would take fluid from or pour into, emptied and filled with
-- `liters` of `fluid` (nil leaves them empty).
local function refill(fullType, fluid, liters)
    local items = player():getInventory():getAllTypeRecurse(fullType)
    for i = 0, items:size() - 1 do
        local container = items:get(i):getFluidContainer()
        container:Empty()
        if fluid then
            container:addFluid(fluid, liters)
        end
    end
end

-- Litres of `fluid` in all the character's containers.
local function fluidCarried(fluid)
    local liters = 0
    local items = player():getInventory():getItems()
    for i = 0, items:size() - 1 do
        local container = items:get(i):getFluidContainer()
        if container then
            liters = liters + container:getSpecificFluidAmount(fluid)
        end
    end
    return liters
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
    local modules = mount and mount:getModData()[MODULES_KEY]
    if not expect(modules ~= nil and #modules == #expected,
        "the mount holds " .. tostring(modules and #modules) .. " modules, expected " .. #expected) then
        return
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
        setup = function()
            first("RenewableEnergy.SolarModule"):setCondition(72)
            if count == 2 then
                local inventory = player():getInventory()
                inventory:Remove(inventory:getAllTypeRecurse("RenewableEnergy.SolarModule"):get(1))
                inventory:AddItem("RenewableEnergy.HomemadeSolarModule"):setCondition(41)
            end
        end,
        counts = { ["RenewableEnergy.SolarModule"] = 0, ["RenewableEnergy.HomemadeSolarModule"] = 0, [mount] = 1 },
        validate = function()
            local expected = { { type = "RenewableEnergy.SolarModule", condition = 72 } }
            if count == 2 then
                table.insert(expected, { type = "RenewableEnergy.HomemadeSolarModule", condition = 41 })
            end
            local modules = first(mount) and first(mount):getModData()[MODULES_KEY]
            -- Which input the craft lists first is its own business.
            if modules and #modules == 2 and modules[1].type ~= expected[1].type then
                expected[1], expected[2] = expected[2], expected[1]
            end
            expectModules(first(mount), expected)
        end,
    })
end

-- Unmounting gives back each module as the type and at the condition it went in.
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
        setup = function()
            local modules = { { type = "RenewableEnergy.HomemadeSolarModule", condition = 41 } }
            if rack then
                table.insert(modules, { type = "RenewableEnergy.SolarModule", condition = 12 })
            end
            first(mount):getModData()[MODULES_KEY] = modules
        end,
        counts = {
            [mount] = 0,
            ["RenewableEnergy.HomemadeSolarModule"] = 1,
            ["RenewableEnergy.SolarModule"] = rack and 1 or 0,
        },
        validate = function()
            local homemade = first("RenewableEnergy.HomemadeSolarModule")
            expect(homemade == nil or homemade:getCondition() == 41,
                "the homemade module came back at " .. tostring(homemade and homemade:getCondition()))
            local factory = first("RenewableEnergy.SolarModule")
            expect(factory == nil or factory:getCondition() == 12,
                "the factory module came back at " .. tostring(factory and factory:getCondition()))
        end,
    })
end

-- A mount nobody wrote modules to, as debug spawns make, holds new factory modules.
craftTest(craftName("RenewableEnergy_UnmountSolarRackMetal", "without_record_returns_new_modules"), {
    recipe = "RenewableEnergy_UnmountSolarRackMetal",
    from = "RenewableEnergy.SolarRackMetal",
    counts = { ["RenewableEnergy.SolarRackMetal"] = 0, ["RenewableEnergy.SolarModule"] = 2, ["Base.MetalPipe"] = 4 },
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
        setup = function()
            first(module):setCondition(before)
        end,
        counts = { [module] = 1, ["Base.GlassPanel"] = refused and 1 or 0 },
        validate = function(self)
            local item = first(module)
            expect(item and item:getCondition() == after,
                "the module is at " .. tostring(item and item:getCondition()) .. ", expected " .. after)
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

-- Taking things apart for their cells.
local TAKE_APART = {
    { "RenewableEnergy_TakeApartCalculator", "Base.Calculator", 1, { ["Base.ElectronicsScrap"] = 1 } },
    { "RenewableEnergy_TakeApartSolarGardenLight", "RenewableEnergy.SolarGardenLight", 2 },
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
    setup = function()
        first("RenewableEnergy.SolarModule"):setCondition(0)
    end,
    counts = { ["RenewableEnergy.SolarModule"] = 0, ["RenewableEnergy.SolarCells"] = 12 },
})

-- A module that still makes power is worth more whole.
craftTest(craftName("RenewableEnergy_TakeApartShatteredModule", "refuses_working_module"), {
    recipe = "RenewableEnergy_TakeApartShatteredModule",
    from = "RenewableEnergy.SolarModule",
    setup = function()
        first("RenewableEnergy.SolarModule"):setCondition(20)
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
        setup = function()
            local battery = first(CAR_BATTERY)
            battery:setCondition(before)
            battery:setCurrentUsesFloat(0.7)
            refill("RenewableEnergy.BatteryElectrolyte", "Water", 1)
        end,
        counts = { [CAR_BATTERY] = 1 },
        validate = function(self)
            local battery = first(CAR_BATTERY)
            if not expect(battery ~= nil, "the battery is gone") then return end
            expect(battery:getCondition() == after, "the battery is at " .. battery:getCondition() .. ", expected " .. after)
            expectNear("the battery's charge", battery:getCurrentUsesFloat(), charge, 0.001)
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
    test(craftName(chain.rebuild, "from_its_stripped_case"), {
        instant = true,
        run = function(self)
            local manager = getScriptManager()
            local strip = T.need(self, manager:getCraftRecipe(chain.strip), "the recipe " .. chain.strip)
            local rebuild = T.need(self, manager:getCraftRecipe(chain.rebuild), "the recipe " .. chain.rebuild)
            if not (strip and rebuild) then return end
            local p = player()
            RenewableEnergy.Debug.learnRecipes(p)
            RenewableEnergy.Debug.placeWorkTable(p)
            T.setPerk(self, Perks.Electricity, 5)
            local inventory = p:getInventory()
            inventory:AddItem("Base.Screwdriver")
            inventory:AddItem("Base.Wrench")
            inventory:AddItem("Base.Gloves_Dish")
            local battery = inventory:AddItem(chain.battery)
            battery:setCondition(20)
            battery:setCurrentUsesFloat(0.6)
            -- One empty litre bottle per litre of acid, and one with the water.
            for _ = 1, chain.plates do
                inventory:AddItem("RenewableEnergy.BatteryElectrolyte"):getFluidContainer():Empty()
            end
            T.startCraft(self, strip, battery)
            T.step(function()
                self.stripped = {
                    case = inventory:getCountTypeRecurse(chain.case),
                    worn = inventory:getCountTypeRecurse("RenewableEnergy.WornBatteryPlates"),
                    acid = fluidCarried(Fluid.Acid),
                    batteries = inventory:getCountTypeRecurse(chain.battery),
                }
                inventory:RemoveAll("RenewableEnergy.WornBatteryPlates")
                inventory:AddItems("RenewableEnergy.BatteryPlates", chain.plates)
                inventory:AddItem("Base.WaterBottle"):getFluidContainer():Empty()
                refill("Base.WaterBottle", "Water", 1)
                local case = first(chain.case)
                if case then
                    T.startCraft(self, rebuild, case)
                end
            end)
        end,
        validate = function(self)
            local refusal = self.refusal and "; the game refused: " .. self.refusal or ""
            local s = self.stripped
            if not expect(s ~= nil, "the strip step never ran" .. refusal) then return end
            expect(s.batteries == 0 and s.case == 1 and s.worn == chain.plates,
                "stripping left " .. s.batteries .. " batteries, " .. s.case .. " cases, " .. s.worn .. " worn plates" .. refusal)
            expectNear("acid poured out by stripping", s.acid, chain.plates, 0.01)
            local inventory = player():getInventory()
            local battery = first(chain.battery)
            if expect(battery ~= nil, "no " .. chain.battery .. " was rebuilt" .. refusal) then
                expect(battery:getCondition() == 100, "the rebuilt battery is at " .. battery:getCondition())
                expectNear("the rebuilt battery's charge", battery:getCurrentUsesFloat(), 0, 0.001)
            end
            expect(inventory:getCountTypeRecurse(chain.case) == 0, "the case is still there")
            expect(inventory:getCountTypeRecurse("RenewableEnergy.BatteryPlates") == 0, "plates are left over")
            expectNear("acid left after rebuilding", fluidCarried(Fluid.Acid), 0, 0.01)
        end,
    })
end

-- Battery plates -------------------------------------------------------------------------------

-- The plate mold the way vanilla makes its ingot mold: a wooden pattern at a table, pressed into
-- clay at a hand press and fired in a kiln; the pattern and the mold last. Lead plates are
-- recast in a primitive furnace burning charcoal.
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

craftTest(craftName("RenewableEnergy_RecastBatteryPlates"), {
    recipe = "RenewableEnergy_RecastBatteryPlates",
    bench = { "Base.Primitive_Furnace", "crafted_01_112" },
    from = "RenewableEnergy.WornBatteryPlates",
    prefer = { "Base.Charcoal" },
    counts = {
        ["RenewableEnergy.WornBatteryPlates"] = 0, ["Base.Charcoal"] = 0,
        ["RenewableEnergy.BatteryPlateMold"] = 1, ["RenewableEnergy.BatteryPlates"] = 1,
    },
})
