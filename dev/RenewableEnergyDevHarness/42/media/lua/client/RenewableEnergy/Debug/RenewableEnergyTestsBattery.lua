require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/PowerBank"

-- Battery tests: battery wear in a bank (PowerBank/Battery.lua, Wear.lua), jar batteries, and the
-- battery recipes that run the mod's Lua (Recipes.lua): repair, rebuild and the jar battery. See
-- RenewableEnergyTestLib.lua for the runner and the helpers.

local T = RenewableEnergyTest
local test, craftTest, expect, expectNear, player, stateItem = T.test, T.craftTest, T.expect, T.expectNear, T.player, T.stateItem
local Battery, Wear, Recipes = RenewableEnergy.Battery, RenewableEnergy.Wear, RenewableEnergy.Recipes
local function craftName(recipe, behavior) return T.craftName("battery", recipe, behavior) end

-- Wear ----------------------------------------------------------------------------------------

-- Discharge wear counts against rated capacity and grows with the square of the depth, and wear
-- under a point waits in the item until it makes one, which a repair forgets.
test("renewable_energy_battery_wear", {
    run = function(self)
        local battery = T.need(self, instanceItem("Base.CarBattery1"), "a Base.CarBattery1")
        local worn = T.need(self, instanceItem("Base.CarBattery1"), "a Base.CarBattery1")
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
        expectNear("condition the day before the wear makes a point", self.dayBefore, self.full, 0)
        expectNear("condition the day the wear makes a point", self.lastDay, self.full - 1, 0)
        expectNear("condition after a repair and less than a point of wear", self.repaired, self.setTo, 0)
    end,
})

-- A day's deepest discharge wears the batteries at the bank's first pass of the next day, on this
-- client's copies too: a car battery charged full, run down to a tenth, then a pass across
-- midnight.
test("renewable_energy_battery_depth_of_discharge_wears_batteries", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" })
        if not bank then return end
        self.bank = bank
        T.step(function() T.setTime(self, 23.5) end)
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.setCharge(self, bank, 0.1)
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.step(function() self.evening = bank.state end)
        end)
        -- Past midnight: the clock's next step turns the day (GameTime.update).
        T.step(function() T.setTime(self, 24.01) end)
        T.serverUntil(self, "bankState", bank.position, function(state)
            return state ~= nil and state.calendarDay ~= self.evening.calendarDay
        end)
        T.bankPass(self, bank, 0, { hours = 0.1 })
        T.waitFor(self, function()
            local battery = T.copyItem(bank, "Base.CarBattery1")
            local served = stateItem(bank.state, "Base.CarBattery1")
            return battery ~= nil and served ~= nil and battery:getCondition() == served.condition
        end, "this client's copy of the worn battery")
    end,
    validate = function(self)
        local evening, morning = self.evening, self.bank.state
        expect(morning.calendarDay ~= evening.calendarDay, "the day never turned")
        -- The charge comes back from whole battery uses, a hair off the tenth it was set to.
        expectNear("the evening's cycle depth", evening.cycleDepth, 0.9, 0.01)
        -- Battery.cycleWear's share of a new battery's condition for that depth, in whole points.
        local new = instanceItem("Base.CarBattery1")
        local max = new:getConditionMax()
        local expected = max - math.floor(Battery.cycleWear(new, evening.cycleDepth) * max)
        if not expect(expected < max, "a " .. evening.cycleDepth .. " deep day wears a car battery less than a point,"
            .. " so its wear can't show") then return end
        local battery = stateItem(morning, "Base.CarBattery1")
        expectNear("car battery condition after the deep day", battery and battery.condition, expected, 0)
        -- The run's last wait already failed the test if this client's copy differs.
        expectNear("cycle depth on the new day", morning.cycleDepth, 0, 0)
    end,
})

-- Jar batteries -------------------------------------------------------------------------------

-- A jar battery is a battery like any other in a bank: it counts, it holds the bank's charge, and
-- this client's copy shows it.
test("renewable_energy_battery_jar_stores_charge", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { "RenewableEnergy.JarBattery" }, { charge = 0.5 })
        if not self.bank then return end
        T.bankState(self, self.bank)
        T.waitFor(self, function()
            return math.abs(T.copyUses(self.bank, "RenewableEnergy.JarBattery") - 0.5) < 0.01
        end, "this client's jar battery half charged")
    end,
    validate = function(self)
        local state = self.bank.state
        expect(state.batteries == 1, "the bank counts " .. state.batteries .. " batteries, expected the jar battery")
        expect(state.nominalWh > 0, "a jar battery gives the bank no capacity")
        expectNear("Wh stored at half charge", state.storedWh, state.nominalWh / 2, 0.5)
    end,
})

-- Queues a wait until this client's first `fullType` holds `liters` of fluid: the server's refill
-- reaches this client after its answer, and a craft picks its inputs from this client's copies.
local function waitForFluid(self, fullType, liters)
    T.waitFor(self, function()
        local item = T.carried(fullType)
        local fluids = item and item:getFluidContainer()
        return fluids ~= nil and math.abs(fluids:getAmount() - liters) < 0.001
    end, "this client's " .. fullType .. " holding " .. liters .. " L")
end

local WORN, PLATES = "RenewableEnergy.WornBatteryPlates", "RenewableEnergy.BatteryPlates"

-- The jar battery comes out new and empty (Recipes.rebuildBattery), where a new item would be
-- full.
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
    counts = { [JAR_BATTERY] = 1 },
    after = function(self) T.readCarried(self, { JAR_BATTERY }) end,
    validate = function(self)
        local battery = T.carriedFirst(self, JAR_BATTERY)
        if not expect(battery ~= nil, "no jar battery was made") then return end
        local full = instanceItem(JAR_BATTERY):getConditionMax()
        expect(battery.condition == full, "the new jar battery is at " .. battery.condition .. ", expected " .. full)
        expectNear("the new jar battery's charge", battery.uses, 0, 0.001)
    end,
})

-- Repairs and rebuilds ------------------------------------------------------------------------

-- A repair brings a battery at most to its repair limit, which falls with each earlier repair:
-- Service adds a step and keeps the charge, Recondition sets the limit and empties the battery,
-- and both are refused at the limit. A repair counts once, on this client's copy too.
-- Rows: recipe, behaviour, condition and repairs before, condition and charge after, refused.
local CAR_BATTERY = "Base.CarBattery2"
local START_CHARGE = 0.7
local limit, step = Recipes.repairLimit, Recipes.SERVICE_REPAIR
-- The fewest repairs that leave no room for another, even at condition 1.
local SPENT = 0
while limit(SPENT) > 1 do SPENT = SPENT + 1 end
local SERVICE, RECONDITION = "RenewableEnergy_ServiceBattery", "RenewableEnergy_ReconditionBattery"
local BATTERY_REPAIRS = {
    { SERVICE, "adds_a_step", limit(0) - 2 * step, 0, limit(0) - step, START_CHARGE },
    { SERVICE, "below_limit_stops_at_limit", limit(0) - 1, 0, limit(0), START_CHARGE },
    { SERVICE, "after_two_repairs_stops_at_lower_limit", limit(2) - 1, 2, limit(2), START_CHARGE },
    { SERVICE, "at_limit_refused", limit(0), 0, limit(0), START_CHARGE, true },
    { RECONDITION, "restores_and_empties", limit(0) - 2 * step, 0, limit(0), 0 },
    { RECONDITION, "after_two_repairs_gives_lower_limit", limit(2) - 2 * step, 2, limit(2), 0 },
    { RECONDITION, "at_limit_refused", limit(2), 2, limit(2), START_CHARGE, true },
    { RECONDITION, "past_last_repair_refused", 1, SPENT, 1, START_CHARGE, true },
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
            T.changeItem(self, T.inputsOf(self, CAR_BATTERY)[1], { condition = before, uses = START_CHARGE })
            T.setRepaired(self, CAR_BATTERY, repaired)
            T.server(self, "refillFluid", { type = "RenewableEnergy.BatteryElectrolyte", fluid = "Water", liters = 1 })
            waitForFluid(self, "RenewableEnergy.BatteryElectrolyte", 1)
        end,
        counts = { [CAR_BATTERY] = 1 },
        after = function(self)
            T.readCarried(self, { CAR_BATTERY })
            -- The tooltip's "Repaired: Nx" reads this client's copy.
            T.waitFor(self, function()
                local battery = T.carried(CAR_BATTERY)
                return battery ~= nil and battery:getHaveBeenRepaired() == repairedAfter
            end, "this client's battery repaired " .. repairedAfter .. "x")
        end,
        validate = function(self)
            local battery = T.carriedFirst(self, CAR_BATTERY)
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
-- place of the recast: the battery comes back new and empty with no repairs behind it, so a
-- Recondition takes it to the first repair limit again. The car battery is a CarBattery2, not the
-- type a case without a record rebuilds into, so its coming back proves the case kept its type.
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
            T.learnRecipes(p)
            T.placeWorkTable(p)
            T.setPerk(self, Perks.Electricity, 5)
            -- Empty acid bottles to take the stripped acid.
            local given = { { type = "Base.Screwdriver" }, { type = "Base.Wrench" }, { type = "Base.Gloves_Dish" },
                { type = chain.battery, condition = 20, uses = 0.6 } }
            for _ = 1, chain.plates do
                table.insert(given, { type = "RenewableEnergy.BatteryElectrolyte" })
            end
            T.give(self, "inputs", given)
            T.setRepaired(self, chain.battery, SPENT)
            T.server(self, "refillFluid", { type = "RenewableEnergy.BatteryElectrolyte" })
            waitForFluid(self, "RenewableEnergy.BatteryElectrolyte", 0)
            T.step(function() T.startCraft(self, strip, T.inputsOf(self, chain.battery)[1]) end)
            -- New plates in place of the worn, and water to top up.
            T.server(self, "takeItems", { type = WORN })
            T.give(self, "rebuild", { { type = PLATES, count = chain.plates }, { type = "Base.WaterBottle" } })
            T.server(self, "refillFluid", { type = "Base.WaterBottle", fluid = "Water", liters = 1 })
            T.waitForCarried(self, chain.case, "this client's " .. chain.case)
            waitForFluid(self, "Base.WaterBottle", 1)
            T.step(function() T.startCraft(self, rebuild, T.carried(chain.case)) end)
            T.readCarried(self, { chain.battery })
            T.step(function() self.rebuilt = T.carriedFirst(self, chain.battery) end)
            -- Worn down again, then reconditioned.
            T.waitForCarried(self, chain.battery, "this client's rebuilt " .. chain.battery)
            T.step(function() T.changeItem(self, T.carried(chain.battery), { condition = limit(0) - 2 * step }) end)
            T.give(self, "recondition", { { type = "Base.BakingSoda", count = 2 } })
            T.server(self, "refillFluid", { type = "Base.WaterBottle", fluid = "Water", liters = 1 })
            waitForFluid(self, "Base.WaterBottle", 1)
            T.step(function()
                local recondition = getScriptManager():getCraftRecipe("RenewableEnergy_ReconditionBattery")
                T.startCraft(self, recondition, T.carried(chain.battery))
            end)
            T.readCarried(self, { chain.battery })
        end,
        validate = function(self)
            local battery = self.rebuilt
            if not expect(battery ~= nil, "no " .. chain.battery .. " was rebuilt") then return end
            local full = instanceItem(chain.battery):getConditionMax()
            expect(battery.condition == full, "the rebuilt battery is at " .. battery.condition .. ", expected " .. full)
            expectNear("the rebuilt battery's charge", battery.uses, 0, 0.001)
            expect(battery.repaired == 0, "the rebuilt battery reads repaired " .. battery.repaired .. "x")
            local reconditioned = T.carriedFirst(self, chain.battery)
            if not expect(reconditioned ~= nil, "the rebuilt battery is gone") then return end
            expect(reconditioned.condition == limit(0),
                "the rebuilt battery reconditions to " .. reconditioned.condition .. ", expected " .. limit(0))
        end,
    })
end
