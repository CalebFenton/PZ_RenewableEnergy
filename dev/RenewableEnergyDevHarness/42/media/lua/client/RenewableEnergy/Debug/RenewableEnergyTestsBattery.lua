require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibCraft"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local Specs = require "RenewableEnergy/Specs"

-- Battery tests: battery wear in a bank (PowerBank/Battery.lua, Wear.lua) and the battery recipes
-- that run the mod's Lua (Recipes.lua): repair, rebuild and the jar battery. See
-- PZHarness/TestLib.lua for the runner and RenewableEnergyTestLib.lua for the helpers.

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual, stateItem = T.test, T.expect, T.expectNear, T.expectEqual, T.stateItem

-- Wear ----------------------------------------------------------------------------------------

-- Discharge wear counts against rated capacity and grows with the square of the depth, a half-deep
-- cycle of a new battery taking 1 / cyclesAt50 of its life, and wear under a point waits in the
-- item until it makes one, which a repair forgets.
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
        local days = math.ceil(Specs.batteries[T.CAR_BATTERY].cyclesAt50 / self.full)
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
        expectNear("wear of a half-deep cycle on a new battery", self.newHalf, 1 / Specs.batteries[T.CAR_BATTERY].cyclesAt50, 1e-12)
        expectNear("wear of a half-worn battery run flat, against a new one at half", self.wornFlat, self.newHalf, 1e-9)
        expectNear("wear of a flat night, against a half one", self.newFlat, 4 * self.newHalf, 1e-9)
        expectEqual("condition the day before the wear makes a point", self.dayBefore, self.full)
        expectEqual("condition the day the wear makes a point", self.lastDay, self.full - 1)
        expectEqual("condition after a repair and less than a point of wear", self.repaired, self.setTo)
    end,
})

-- A day's deepest discharge wears the batteries at the bank's first pass of the next day, on this
-- client's copies too: a rack of jar batteries charged full and run down, then a pass across
-- midnight with the inverter carrying the load in reach. What it draws before midnight deepens the
-- day that ends, and what it draws after starts the next, and is the new day's Used Today.
-- Batteries enough that the pass leaves them some charge.
local EVENING_CHARGE, PASS_HOURS, PAST_MIDNIGHT = 0.3, 0.6, 0.5
test("renewable_energy_battery_depth_of_discharge_wears_batteries", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        T.setGrid(self, false)
        local parts = { T.INVERTER_CHARGER }
        for _ = 1, Specs.banks["RenewableEnergy.BatteryRackWood"].maxBatteries do
            table.insert(parts, T.JAR_BATTERY)
        end
        local bank = T.bank(self, "batteryRackWood", parts)
        if not bank then return end
        self.bank = bank
        T.switchOn(self, bank)
        -- The clock stands still, and both times lie the same minutes past the hour, so neither
        -- the clock nor its jump fires the bank system's ten-minute pass (GameTime.update): the
        -- test's pass is the one that crosses midnight. That holds only once the clock has stepped
        -- at 23:30. A server serves commands between its world updates, so without a server frame
        -- between them the evening's passes and the jump could all come before that step; the
        -- jump would then find the tens of minutes changed since the clock's last step, and the
        -- ten-minute pass would cross midnight before the test's.
        T.step(function()
            T.setMultiplier(self, 0)
            T.setTime(self, 23.5)
        end)
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.setCharge(self, bank, EVENING_CHARGE)
            T.bankPass(self, bank, 0, { hours = 0.1, label = "evening" })
        end)
        T.awaitServerFrame(self)
        -- Past midnight: the clock's next step turns the day (GameTime.update).
        T.step(function() T.setTime(self, 24 + PAST_MIDNIGHT) end)
        T.serverUntil(self, "PZHarness.readRecord", T.at(bank, { kind = "bank" }), function(state)
            return state ~= nil and state.calendarDay ~= self.reads.evening.calendarDay
        end)
        T.bankPass(self, bank, 0, { hours = PASS_HOURS })
        T.waitFor(self, function()
            local battery = T.copyItem(bank, T.JAR_BATTERY)
            local served = stateItem(bank.state, T.JAR_BATTERY)
            return battery ~= nil and served ~= nil and battery:getCondition() == served.condition
        end, "this client's copy of the worn battery")
    end,
    validate = function(self)
        local evening, morning = self.reads.evening, self.bank.state
        expect(morning.calendarDay ~= evening.calendarDay, "the day never turned")
        local drawn = evening.charge - morning.charge
        if not (expect(drawn > 0, "the bank drew nothing across midnight")
            and expect(morning.charge > 0, "the batteries ran out across midnight")) then return end
        local afterMidnight = drawn * PAST_MIDNIGHT / PASS_HOURS
        local max = instanceItem(T.JAR_BATTERY):getConditionMax()
        local expected = T.conditionAfterDischarge(T.JAR_BATTERY, evening.cycleDepth + drawn - afterMidnight)
        if not expect(expected < max, "a " .. evening.cycleDepth .. " deep day wears a jar battery less than a point,"
            .. " so its wear can't show") then return end
        local battery = stateItem(morning, T.JAR_BATTERY)
        expectEqual("jar battery condition after the deep day", battery and battery.condition, expected)
        -- The run's last wait already failed the test if this client's copy differs.
        expectNear("cycle depth on the new day, the draw after midnight", morning.cycleDepth, afterMidnight, 0.001)
        local status = morning.status
        if expect(status.loadW > 0, "the bank powered no load across midnight") then
            expectNear("Wh used on the new day, the load after midnight", status.loadWhToday, status.loadW * PAST_MIDNIGHT, 0.001)
        end
    end,
})

-- Charging a set a whole use at a time (Battery.shift with usesPerStep, as the solar cell charger
-- fills cells) moves one use per pick, the emptier battery first, so two batteries a use apart
-- given three and a half uses end level, and the half use short of a whole one stays unmoved.
-- Catches a pick that moves several uses at once, or part of one.
test("renewable_energy_battery_shift_steps_whole_uses", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.CAR_BATTERY })
        if not bank then return end
        self.half = math.floor(instanceItem(T.CAR_BATTERY):getMaxUses() / 2)
        T.read(self, "shiftBatteries", T.at(bank, { uses = { self.half, self.half + 1 }, wh = 3.5, usesPerStep = 1 }), "shifted")
    end,
    validate = function(self)
        local shifted = self.reads.shifted
        expectNear("uses' worth of watt-hours moved", shifted.moved, 3, 1e-6)
        expectEqual("whole uses moved", shifted.movedUses, 3)
        expectEqual("uses of the battery that started a use emptier", shifted.uses[1], self.half + 2)
        expectEqual("uses of the other battery", shifted.uses[2], self.half + 2)
        expect(shifted.short, "the half-charged batteries count as full")
    end,
})

-- Repairs and rebuilds ------------------------------------------------------------------------

-- A CarBattery2, unlike the T.CAR_BATTERY other tests use: the rebuild below proves a case keeps
-- its type.
local CAR_BATTERY2, ELECTROLYTE = "Base.CarBattery2", "RenewableEnergy.BatteryElectrolyte"
local START_CHARGE = 0.7
-- The most a repair brings a battery repaired `repairs` times to: Battery.REPAIR_LIMIT, a
-- Wear.REPAIR_LIMIT_STEP lower for each earlier repair, so that repairs run out.
local function limit(repairs) return Battery.REPAIR_LIMIT - repairs * Wear.REPAIR_LIMIT_STEP end
-- The fewest repairs that leave no room for another, even at condition 1.
local SPENT = 0
while limit(SPENT) > 1 do SPENT = SPENT + 1 end

-- Service adds a step up to the limit and keeps the charge; Recondition sets the limit and empties
-- the battery; the one OnTest both share refuses a battery at its limit, tried here through
-- Recondition. A repair counts once.
local SERVICE, RECONDITION, STEP = "RenewableEnergy_ServiceBattery", "RenewableEnergy_ReconditionBattery", Battery.SERVICE_REPAIR
T.conditionCraftsTest("renewable_energy_battery_craft_repairs_stop_at_a_falling_limit", CAR_BATTERY2, {
    { SERVICE, "adds a step and keeps the charge", before = limit(0) - 2 * STEP, repaired = 0, after = limit(0) - STEP,
        repairedAfter = 1 },
    { SERVICE, "after two repairs stops at the lower limit", before = limit(2) - 1, repaired = 2, after = limit(2),
        repairedAfter = 3 },
    { RECONDITION, "after two repairs restores the lower limit and empties", before = limit(2) - 2 * STEP, repaired = 2,
        after = limit(2), repairedAfter = 3, charge = 0 },
    { RECONDITION, "at the limit refused", before = limit(2), repaired = 2, refused = true },
    { RECONDITION, "past the last repair refused", before = 1, repaired = SPENT, refused = true },
}, {
    uses = START_CHARGE,
    -- Its any-item water input takes the acid bottle, which the setup fills.
    prefer = { ELECTROLYTE },
    setup = function(self) T.fillCarried(self, ELECTROLYTE, "Water", 1) end,
    validate = function(row, battery, what)
        expectNear(what .. ": its charge", battery.uses, row.charge or START_CHARGE, 0.001)
    end,
})

-- A rebuilt or newly made battery comes out empty, where a new item comes full
-- (Recipes.rebuildBattery, Recipes.rebuildCarBattery).
-- Stripping a car battery past its last repair and rebuilding its case gives back the type it came
-- out of; a case with no record, as debug spawns make, rebuilds into the plain car battery,
-- VehicleBattery.CAR_BATTERY.
local CASE, PLATES = "RenewableEnergy.CarBatteryCase", "RenewableEnergy.BatteryPlates"
local STRIP, REBUILD, JAR = "RenewableEnergy_StripCarBattery", "RenewableEnergy_RebuildCarBattery", "RenewableEnergy_MakeJarBattery"
test("renewable_energy_battery_craft_rebuilt_batteries_come_out_empty", {
    instant = true,
    run = function(self)
        local recipes = T.readyToCraft(self, { STRIP, REBUILD, JAR })
        if not recipes then return end
        -- Each any-item fluid input is given an acid bottle, and the water comes in a bottle of its
        -- own, which holds what the jar battery takes.
        local function water(litres)
            return function()
                T.give(self, "water", { { type = "Base.PopBottle" } })
                T.fillCarried(self, "Base.PopBottle", "Water", litres)
            end
        end
        T.craftFrom(self, recipes[STRIP], { type = CAR_BATTERY2, condition = 20, uses = 0.6, repaired = SPENT }, {
            prefer = { ELECTROLYTE },
            -- An empty bottle to take the stripped acid.
            setup = function() T.fillCarried(self, ELECTROLYTE) end,
        })
        self.rebuilt = T.craftFrom(self, recipes[REBUILD], CASE, { prefer = { ELECTROLYTE }, setup = water(1), read = { CAR_BATTERY2 } })
        self.unrecorded = T.craftFrom(self, recipes[REBUILD], { type = CASE },
            { prefer = { ELECTROLYTE }, setup = water(1), read = { T.CAR_BATTERY } })
        self.jar = T.craftFrom(self, recipes[JAR], { type = PLATES },
            { prefer = { ELECTROLYTE, "Base.EmptyJar", "Base.Sandbag" }, setup = water(2), read = { T.JAR_BATTERY } })
    end,
    validate = function(self)
        for _, check in ipairs({
            { self.rebuilt, CAR_BATTERY2, "the stripped case rebuilt" },
            { self.unrecorded, T.CAR_BATTERY, "a case with no record rebuilt" },
            { self.jar, T.JAR_BATTERY, "the jar battery made" },
        }) do
            local result, fullType, what = check[1], check[2], check[3]
            T.expectCrafted(result, what)
            local battery = T.carriedFirst(self, fullType, result.label)
            if expect(battery ~= nil, what .. " no " .. fullType) then
                expectNear(what .. ": its charge", battery.uses, 0, 0.001)
            end
        end
    end,
})
