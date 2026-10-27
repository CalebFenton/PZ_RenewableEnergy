require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibCraft"
local Recipes = require "RenewableEnergy/Recipes"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local Battery = require "RenewableEnergy/PowerBank/Battery"

-- Battery tests: battery wear in a bank (PowerBank/Battery.lua, Wear.lua) and the battery recipes
-- that run the mod's Lua (Recipes.lua): repair, rebuild and the jar battery. See
-- PZHarness/TestLib.lua for the runner and RenewableEnergyTestLib.lua for the helpers.

local T = RenewableEnergyTest
local test, craftTest, expect, expectNear, expectEqual, player, stateItem = T.test, T.craftTest, T.expect, T.expectNear,
    T.expectEqual, T.player, T.stateItem
local function craftName(recipe, behavior) return T.craftName("battery", recipe, behavior) end

-- Wear ----------------------------------------------------------------------------------------

-- Discharge wear counts against rated capacity and grows with the square of the depth, and wear
-- under a point waits in the item until it makes one, which a repair forgets.
test("renewable_energy_battery_wear", {
    run = function(self)
        local battery = T.need(self, instanceItem(T.CAR_BATTERY), "a " .. T.CAR_BATTERY)
        local worn = T.need(self, instanceItem(T.CAR_BATTERY), "a " .. T.CAR_BATTERY)
        if not (battery and worn) then return end
        -- A half-worn battery run flat gives up what a new one does at half: the same watt-hours.
        Wear.setCondition(worn, 50)
        self.wornFlat, self.newHalf = Battery.cycleWear(worn, 1), Battery.cycleWear(battery, 0.5)
        self.newFlat = Battery.cycleWear(battery, 1)
        -- Days at half discharge until their wear makes a point: until then the fractions are kept.
        self.full = battery:getConditionMax()
        local days = math.ceil(1 / (Battery.cycleWear(battery, 0.5) * self.full))
        for _ = 1, days - 1 do
            Battery.wear(battery, Battery.cycleWear(battery, 0.5))
        end
        self.dayBefore = battery:getCondition()
        Battery.wear(battery, Battery.cycleWear(battery, 0.5))
        self.lastDay = battery:getCondition()
        -- A repair starts afresh: the part of a point still pending is forgotten.
        self.setTo = math.floor(self.full / 2)
        Wear.take(battery, 0.6)
        Wear.setCondition(battery, self.setTo)
        Wear.take(battery, 0.6)
        self.repaired = battery:getCondition()
    end,
    validate = function(self)
        expectNear("wear of a half-worn battery run flat, against a new one at half", self.wornFlat, self.newHalf, 1e-9)
        expectNear("wear of a flat night, against a half one", self.newFlat, 4 * self.newHalf, 1e-9)
        expectEqual("condition the day before the wear makes a point", self.dayBefore, self.full)
        expectEqual("condition the day the wear makes a point", self.lastDay, self.full - 1)
        expectEqual("condition after a repair and less than a point of wear", self.repaired, self.setTo)
    end,
})

-- A day's deepest discharge wears the batteries at the bank's first pass of the next day, on this
-- client's copies too: a car battery charged full, run down to a tenth, then a pass across
-- midnight.
test("renewable_energy_battery_depth_of_discharge_wears_batteries", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY })
        if not bank then return end
        self.bank = bank
        T.step(function() T.setTime(self, 23.5) end)
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.setCharge(self, bank, 0.1)
            T.bankPass(self, bank, 0, { hours = 0.1, label = "evening" })
        end)
        -- Past midnight: the clock's next step turns the day (GameTime.update).
        T.step(function() T.setTime(self, 24.01) end)
        T.serverUntil(self, "PZHarness.readRecord", T.at(bank, { kind = "bank" }), function(state)
            return state ~= nil and state.calendarDay ~= self.reads.evening.calendarDay
        end)
        T.bankPass(self, bank, 0, { hours = 0.1 })
        T.waitFor(self, function()
            local battery = T.copyItem(bank, T.CAR_BATTERY)
            local served = stateItem(bank.state, T.CAR_BATTERY)
            return battery ~= nil and served ~= nil and battery:getCondition() == served.condition
        end, "this client's copy of the worn battery")
    end,
    validate = function(self)
        local evening, morning = self.reads.evening, self.bank.state
        expect(morning.calendarDay ~= evening.calendarDay, "the day never turned")
        -- The charge comes back from whole battery uses, a hair off the tenth it was set to.
        expectNear("the evening's cycle depth", evening.cycleDepth, 0.9, 0.01)
        local max = instanceItem(T.CAR_BATTERY):getConditionMax()
        local expected = T.conditionAfterDischarge(T.CAR_BATTERY, evening.cycleDepth)
        if not expect(expected < max, "a " .. evening.cycleDepth .. " deep day wears a car battery less than a point,"
            .. " so its wear can't show") then return end
        local battery = stateItem(morning, T.CAR_BATTERY)
        expectEqual("car battery condition after the deep day", battery and battery.condition, expected)
        -- The run's last wait already failed the test if this client's copy differs.
        expectEqual("cycle depth on the new day", morning.cycleDepth, 0)
    end,
})

local WORN, PLATES = "RenewableEnergy.WornBatteryPlates", "RenewableEnergy.BatteryPlates"

-- The jar battery comes out new and empty (Recipes.rebuildBattery), where a new item would be
-- full.
craftTest(craftName("RenewableEnergy_MakeJarBattery"), {
    recipe = "RenewableEnergy_MakeJarBattery",
    from = PLATES,
    prefer = { "RenewableEnergy.BatteryElectrolyte", "Base.EmptyJar", "Base.Sandbag" },
    setup = function(self)
        T.give(self, "water", { { type = "Base.PopBottle" } })
        T.fillCarried(self, "Base.PopBottle", "Water", 2)
    end,
    counts = { [T.JAR_BATTERY] = 1 },
    after = function(self) T.readCarried(self, { T.JAR_BATTERY }) end,
    validate = function(self)
        local battery = T.carriedFirst(self, T.JAR_BATTERY)
        if not expect(battery ~= nil, "no jar battery was made") then return end
        expectEqual("the new jar battery's condition", battery.condition, instanceItem(T.JAR_BATTERY):getConditionMax())
        expectNear("the new jar battery's charge", battery.uses, 0, 0.001)
    end,
})

-- Repairs and rebuilds ------------------------------------------------------------------------

-- A repair brings a battery at most to its repair limit, which falls with each earlier repair:
-- Service adds a step and keeps the charge, Recondition sets the limit and empties the battery,
-- and both are refused at the limit. A repair counts once, on this client's copy too.
-- Rows: recipe, behaviour, then T.repairCraftTest's fields and the charge after.
-- A CarBattery2, unlike the T.CAR_BATTERY other tests use: the rebuild below proves a case keeps its type.
local CAR_BATTERY2 = "Base.CarBattery2"
local START_CHARGE = 0.7
local limit, step = Battery.repairLimit, Battery.SERVICE_REPAIR
-- The fewest repairs that leave no room for another, even at condition 1.
local SPENT = 0
while limit(SPENT) > 1 do SPENT = SPENT + 1 end
local SERVICE, RECONDITION = "RenewableEnergy_ServiceBattery", "RenewableEnergy_ReconditionBattery"
local BATTERY_REPAIRS = {
    { SERVICE, "adds_a_step", before = limit(0) - 2 * step, repaired = 0, after = limit(0) - step, charge = START_CHARGE },
    { SERVICE, "below_limit_stops_at_limit", before = limit(0) - 1, repaired = 0, after = limit(0), charge = START_CHARGE },
    { SERVICE, "after_two_repairs_stops_at_lower_limit", before = limit(2) - 1, repaired = 2, after = limit(2),
        charge = START_CHARGE },
    { SERVICE, "at_limit_refused", before = limit(0), repaired = 0, after = limit(0), charge = START_CHARGE, refused = true },
    { RECONDITION, "restores_and_empties", before = limit(0) - 2 * step, repaired = 0, after = limit(0), charge = 0 },
    { RECONDITION, "after_two_repairs_gives_lower_limit", before = limit(2) - 2 * step, repaired = 2, after = limit(2),
        charge = 0 },
    { RECONDITION, "at_limit_refused", before = limit(2), repaired = 2, after = limit(2), charge = START_CHARGE, refused = true },
    { RECONDITION, "past_last_repair_refused", before = 1, repaired = SPENT, after = 1, charge = START_CHARGE, refused = true },
}
for _, row in ipairs(BATTERY_REPAIRS) do
    row.repairedAfter = row.refused and row.repaired or row.repaired + 1
    row.uses = START_CHARGE
    row.prefer = { "RenewableEnergy.BatteryElectrolyte" }
    row.setup = function(self) T.fillCarried(self, "RenewableEnergy.BatteryElectrolyte", "Water", 1) end
    row.validate = function(_, battery) expectNear("the battery's charge", battery.uses, row.charge, 0.001) end
    T.repairCraftTest(craftName(row[1], row[2]), row[1], CAR_BATTERY2, row)
end

-- Stripping a car battery past its last repair and rebuilding it from its own case, with new
-- plates in place of the recast: the battery comes back new and empty with no repairs behind it.
-- It is a CarBattery2, not the type a case without a record rebuilds into, so its coming back
-- proves the case kept its type.
local CASE, STRIP, REBUILD = "RenewableEnergy.CarBatteryCase", "RenewableEnergy_StripCarBattery", "RenewableEnergy_RebuildCarBattery"
test(craftName(REBUILD, "from_its_stripped_case"), {
    instant = true,
    run = function(self)
        local manager = getScriptManager()
        local strip = T.need(self, manager:getCraftRecipe(STRIP), "the recipe " .. STRIP)
        local rebuild = T.need(self, manager:getCraftRecipe(REBUILD), "the recipe " .. REBUILD)
        if not (strip and rebuild) then return end
        local p = player()
        T.learnRecipes(p)
        T.placeWorkTable(p)
        T.setPerk(self, Perks.Electricity, 5)
        -- An empty acid bottle to take the stripped acid.
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Gloves_Dish" },
            { type = CAR_BATTERY2, condition = 20, uses = 0.6, repaired = SPENT }, { type = "RenewableEnergy.BatteryElectrolyte" } })
        T.fillCarried(self, "RenewableEnergy.BatteryElectrolyte")
        T.step(function() T.startCraft(self, strip, T.inputsOf(self, CAR_BATTERY2)[1]) end)
        -- New plates in place of the worn, and water to top up.
        T.takeItems(self, nil, WORN)
        T.give(self, "rebuild", { { type = PLATES }, { type = "Base.WaterBottle" } })
        T.fillCarried(self, "Base.WaterBottle", "Water", 1)
        T.waitForCarried(self, CASE, "this client's " .. CASE)
        T.step(function() T.startCraft(self, rebuild, T.carried(CASE)) end)
        T.readCarried(self, { CAR_BATTERY2 })
    end,
    validate = function(self)
        local battery = T.carriedFirst(self, CAR_BATTERY2)
        if not expect(battery ~= nil, "no " .. CAR_BATTERY2 .. " was rebuilt") then return end
        expectEqual("the rebuilt battery's condition", battery.condition, instanceItem(CAR_BATTERY2):getConditionMax())
        expectNear("the rebuilt battery's charge", battery.uses, 0, 0.001)
        expectEqual("the rebuilt battery's repairs", battery.repaired, 0)
    end,
})

-- A car battery case with no record of the battery it came out of rebuilds into the plain car
-- battery, VehicleBattery.CAR_BATTERY.
test(craftName(REBUILD, "from_a_case_with_no_record"), {
    instant = true,
    run = function(self)
        local rebuild = T.need(self, getScriptManager():getCraftRecipe(REBUILD), "the recipe " .. REBUILD)
        if not rebuild then return end
        local p = player()
        T.learnRecipes(p)
        T.placeWorkTable(p)
        T.setPerk(self, Perks.Electricity, 5)
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = CASE }, { type = PLATES },
            { type = "RenewableEnergy.BatteryElectrolyte" }, { type = "Base.WaterBottle" } })
        T.fillCarried(self, "Base.WaterBottle", "Water", 1)
        T.waitForFluid(self, "RenewableEnergy.BatteryElectrolyte", 1)
        T.step(function() T.startCraft(self, rebuild, T.carried(CASE)) end)
        T.readCarried(self, { T.CAR_BATTERY })
    end,
    validate = function(self)
        expect(T.carriedFirst(self, T.CAR_BATTERY) ~= nil, "a case with no record rebuilt no " .. T.CAR_BATTERY)
    end,
})
