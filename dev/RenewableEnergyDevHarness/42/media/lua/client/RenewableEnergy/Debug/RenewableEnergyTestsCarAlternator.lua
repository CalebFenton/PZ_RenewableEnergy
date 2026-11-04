require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local CarAlternator = require "RenewableEnergy/Gadgets/CarAlternator"
local VehicleMechanicsMenu = require "RenewableEnergy/UI/VehicleMechanicsMenu"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local VehicleJobs = require "RenewableEnergy/Gadgets/VehicleJobs"

-- The car alternator: taken out of a car and put back (Gadgets/CarAlternator*.lua,
-- UI/VehicleMechanicsMenu.lua), the car's battery charging without it (VehicleBatteryCharging.lua),
-- and a wreck's scrap dropping one. The authority runs the jobs and the scrap, so the tests drive
-- them through the job's action and T.server, and check this client's copies.

local T = RenewableEnergyTest
local test, expect, expectEqual = T.test, T.expect, T.expectEqual

local CAR = "Base.CarNormal"

-- Queues a car with a car battery, its hood open and its doors unlocked, a wrench and the
-- Mechanics the job takes. Returns the car's handle, or nil without one.
local function readyCar(self)
    T.setPerk(self, Perks.Mechanics, 2)
    local car = T.placeVehicle(self, CAR, { battery = T.CAR_BATTERY })
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
-- car on the server and this client. Then the menu offers only Put Back, the job is refused, the
-- authority gives no second alternator, and an hour of the running engine's battery update (the
-- alternatorCharge handler, RenewableEnergyTestServerGadgets.lua) adds nothing to the battery.
-- Putting it back takes it from the inventory and the battery charges again.
test("renewable_energy_gadgets_car_alternator_take_out_and_put_back", {
    instant = true,
    run = function(self)
        local car = readyCar(self)
        if not car then return end
        local function charge(label)
            T.onVehicle(self, car, "alternatorCharge", { uses = 0.2, minutes = 60 }, label)
        end
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
            local option = VehicleMechanicsMenu.addOption(context, T.player(), car.vehicle)
            self.secondOption = option and option.name
            context:hideAndChildren()
            self.canTakeTwice = VehicleJobs.refusal(T.player(), VehicleJobs.TAKE_OUT_ALTERNATOR, car.vehicle) == nil
        end)
        T.onVehicle(self, car, "takeOutAlternatorAgain", nil, "again")
        T.count(self, "afterSecond", { CarAlternator.ITEM })
        charge("without")
        alternatorJob(self, car, VehicleJobs.PUT_BACK_ALTERNATOR, false)
        T.count(self, "putBack", { CarAlternator.ITEM })
        charge("with")
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
        local without, with = self.reads.without, self.reads.with
        expect(math.abs(without.gain) < 1e-6, "a car without its alternator gained " .. without.gain .. " of a charge")
        expectEqual("alternators left in the inventory once put back", self.counts.putBack[CarAlternator.ITEM], 0)
        expect(with.gain > 0, "the car didn't charge once its alternator was back")
    end,
})

-- Scrapping a smashed wreck drops one alternator on a roll under the character's scrap chance and
-- none on a roll over it; a burnt wreck never does, even on the lowest roll. The chance is that of
-- vanilla's scrap giving at least one Engine Parts: a round per Metalworking level, at least 5, of
-- two rolls, each 1 in (25 less the lower of Mechanics and Metalworking). At Mechanics and
-- Metalworking 0 that is 1 - (24/25)^10 = 0.33517; at Mechanics 3 and Metalworking 8 it is
-- 1 - (21/22)^16 = 0.52494 (with the two skills swapped it would be 0.37199). Each roll lies within
-- 0.0001 of its chance. One test per pair of skills, which a test sets once: on a multiplayer
-- client T.setPerk holds its level until the test ends.
local SMASHED, BURNT = "Base.CarNormalSmashedFront", "Base.CarNormalBurnt"
local SCRAPS = {
    { skill = "unskilled", mechanics = 0, metalworking = 0, rows = {
        { what = "hit", script = SMASHED, roll = 0.3351, alternators = 1 },
        { what = "miss", script = SMASHED, roll = 0.3352, alternators = 0 },
        { what = "burnt wreck", script = BURNT, roll = 0, alternators = 0 },
    } },
    { skill = "skilled", mechanics = 3, metalworking = 8, rows = {
        { what = "hit", script = SMASHED, roll = 0.5249, alternators = 1 },
        { what = "miss", script = SMASHED, roll = 0.525, alternators = 0 },
    } },
}
-- Each wreck goes before the next is placed, so every one lands on open ground.
for _, scraps in ipairs(SCRAPS) do
    test("renewable_energy_gadgets_car_alternator_scrap_" .. scraps.skill, {
        run = function(self)
            T.setPerk(self, Perks.Mechanics, scraps.mechanics)
            T.setPerk(self, Perks.MetalWelding, scraps.metalworking)
            for _, row in ipairs(scraps.rows) do
                local wreck = T.placeVehicle(self, row.script)
                if not wreck then return end
                T.onVehicle(self, wreck, "scrapWreck", { roll = row.roll }, row.what)
            end
        end,
        validate = function(self)
            for _, row in ipairs(scraps.rows) do
                local scrap = self.reads[row.what]
                if expect(scrap.done and scrap.removed, "the " .. row.what .. "'s wreck was never scrapped") then
                    expectEqual("alternators the " .. row.what .. " dropped at a roll of " .. row.roll, scrap.alternators,
                        row.alternators)
                end
            end
        end,
    })
end
