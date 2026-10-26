require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Gadgets/CarAlternator"
require "RenewableEnergy/UI/VehicleMechanicsMenu"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local VehicleJobs = require "RenewableEnergy/Gadgets/VehicleJobs"

-- The car alternator: taken out of a car and put back (Gadgets/CarAlternator*.lua,
-- UI/VehicleMechanicsMenu.lua), the car's battery charging without it (VehicleBatteryCharging.lua),
-- and a wreck's scrap dropping one. The authority runs the jobs and the scrap, so the tests drive
-- them through the job's action and T.server, and check this client's copies.

local T = RenewableEnergyTest
local test, expect, expectEqual = T.test, T.expect, T.expectEqual
local CarAlternator, CarAlternatorMenu = RenewableEnergy.CarAlternator, RenewableEnergy.CarAlternatorMenu

local CAR = "Base.CarNormal"

-- Queues a car with the hood open and its doors unlocked, a wrench and Mechanics the job takes;
-- `opts.battery` as T.placeVehicle's. Returns the car's handle, or nil without one.
local function readyCar(self, opts)
    T.setPerk(self, Perks.Mechanics, 2)
    local car = T.placeVehicle(self, CAR, opts)
    if not car then return nil end
    T.give(self, "wrench", { { type = "Base.Wrench" } })
    T.onVehicle(self, car, "openCarHood")
    T.waitFor(self, function() return CarAlternator.hoodOpen(car.vehicle) end, "this client's car with its hood open")
    return car
end

-- Queues the job `job` on `car` (Put Back with the carried alternator) and a wait until this
-- client's copy shows the alternator `out` or not. Skips the menu's walk and hood, which the
-- fixture has seen to.
local function alternatorJob(self, car, job, out)
    T.step(function()
        local item = job == VehicleJobs.PUT_BACK_ALTERNATOR and T.carried(CarAlternator.ITEM) or nil
        ISTimedActionQueue.add(RenewableEnergyAction:new(T.player(), "vehicle", job, car.vehicle, item))
    end)
    T.waitFor(self, function() return CarAlternator.isOut(car.vehicle) == out end,
        "this client's car with its alternator " .. (out and "out" or "back in"))
end

-- The engine's menu offers Take Out Alternator; taking it out gives one alternator and marks the
-- car on the server and this client, and then the menu offers only Put Back, the job is refused,
-- and the authority gives no second alternator.
test("renewable_energy_gadgets_car_alternator_take_out_once", {
    instant = true,
    run = function(self)
        local car = readyCar(self)
        if not car then return end
        T.step(function()
            local context = T.partMenu(car.vehicle, CarAlternator.enginePart(car.vehicle))
            local option = context and T.optionNamed(context, getText("IGUI_RenewableEnergy_TakeOutAlternator"))
            T.noteOption(self, "Take Out Alternator", option)
            if context then context:closeAll() end
        end)
        alternatorJob(self, car, VehicleJobs.TAKE_OUT_ALTERNATOR, true)
        T.onVehicle(self, car, "vehicleState", nil, "takenOut")
        T.count(self, "takenOut", { CarAlternator.ITEM })
        T.step(function()
            local context = T.newContext()
            local option = CarAlternatorMenu.addOption(context, T.player(), car.vehicle)
            self.secondOption = option and option.name
            context:hideAndChildren()
            self.canTakeTwice = VehicleJobs.refusal(T.player(), VehicleJobs.TAKE_OUT_ALTERNATOR, car.vehicle) == nil
        end)
        T.onVehicle(self, car, "takeOutAlternatorAgain", nil, "again")
        T.count(self, "afterSecond", { CarAlternator.ITEM })
    end,
    validate = function(self)
        T.expectOffered(self, "Take Out Alternator")
        expect(self.reads.takenOut.state.alternatorOut, "the server's car doesn't show its alternator out")
        expectEqual("alternators taking it out gave", self.counts.takenOut[CarAlternator.ITEM], 1)
        expectEqual("the menu's option with the alternator out", self.secondOption,
            getText("IGUI_RenewableEnergy_PutBackAlternator"))
        expect(not self.canTakeTwice, "the job would take a second alternator out of the car")
        expect(not self.reads.again.gave, "the authority gave a second alternator")
        expectEqual("alternators after a second try", self.counts.afterSecond[CarAlternator.ITEM], 1)
    end,
})

-- An hour of vanilla's alternator charging (the alternatorCharge handler, RenewableEnergyTestServerGadgets.lua)
-- adds nothing to the battery of a car whose alternator is out, and charges it again once the
-- alternator is back, which takes it from the inventory.
test("renewable_energy_gadgets_car_alternator_out_stops_charging", {
    instant = true,
    run = function(self)
        local car = readyCar(self, { battery = T.CAR_BATTERY })
        if not car then return end
        local function charge(label)
            T.onVehicle(self, car, "alternatorCharge", { uses = 0.2, minutes = 60 }, label)
        end
        alternatorJob(self, car, VehicleJobs.TAKE_OUT_ALTERNATOR, true)
        charge("without")
        alternatorJob(self, car, VehicleJobs.PUT_BACK_ALTERNATOR, false)
        charge("with")
        T.count(self, "putBack", { CarAlternator.ITEM })
    end,
    validate = function(self)
        local without, with = self.reads.without, self.reads.with
        expect(math.abs(without.gain) < 1e-6, "a car without its alternator gained " .. without.gain .. " of a charge")
        expect(with.gain > 0, "the car didn't charge once its alternator was back")
        expect(self.counts.putBack[CarAlternator.ITEM] == 0, "the alternator put back is still in the inventory")
    end,
})

-- Scrapping a smashed wreck drops one alternator on a roll just under the character's scrap
-- chance and none on a roll at it; a burnt wreck never does, even just under it.
local SCRAPS = {
    { behavior = "smashed_wreck_hit_drops_one", script = "Base.CarNormalSmashedFront", roll = "under", alternators = 1 },
    { behavior = "smashed_wreck_miss_drops_none", script = "Base.CarNormalSmashedFront", roll = "at", alternators = 0 },
    { behavior = "burnt_wreck_never_drops", script = "Base.CarNormalBurnt", roll = "under", alternators = 0 },
}
for _, case in ipairs(SCRAPS) do
    test("renewable_energy_gadgets_car_alternator_scrap_" .. case.behavior, {
        run = function(self)
            local wreck = T.placeVehicle(self, case.script)
            if not wreck then return end
            T.onVehicle(self, wreck, "scrapWreck", { roll = case.roll }, "scrap")
        end,
        validate = function(self)
            local scrap = self.reads.scrap
            if not expect(scrap.done and scrap.removed, "the wreck was never scrapped") then return end
            expectEqual("alternators scrapping a " .. case.script .. " at a roll of " .. case.roll .. " dropped",
                scrap.alternators, case.alternators)
        end,
    })
end
