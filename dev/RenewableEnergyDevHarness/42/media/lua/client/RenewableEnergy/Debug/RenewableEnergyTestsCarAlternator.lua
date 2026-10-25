require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Gadgets/CarAlternator"
require "RenewableEnergy/UI/VehicleMechanicsMenu"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "Vehicles/ISUI/ISVehicleMechanics"

-- The car alternator: taken out of a car and put back (Gadgets/CarAlternator*.lua,
-- UI/VehicleMechanicsMenu.lua), the car's battery charging without it (VehicleBatteryCharging.lua),
-- and a wreck's scrap dropping one. The authority runs the jobs and the scrap, so the tests drive
-- them through the job's action and T.server, and check this client's copies.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local CarAlternator, CarAlternatorMenu = RenewableEnergy.CarAlternator, RenewableEnergy.CarAlternatorMenu
local Action = RenewableEnergyAction

local CAR, CAR_BATTERY = "Base.CarNormal", "Base.CarBattery1"

-- The mechanics window's menu for the car's engine, built by its own doPartContextMenu on a window
-- that has just what that function reads.
local function engineMenu(vehicle)
    local window = setmetatable({ chr = T.player(), playerNum = 0, vehicle = vehicle }, { __index = ISVehicleMechanics })
    window.getAbsoluteX = function() return 0 end
    window.getAbsoluteY = function() return 0 end
    window:doPartContextMenu(CarAlternator.enginePart(vehicle), 0, 0)
    return window.context
end

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

-- Queues the job of `mode` on `car` (Put Back with the carried alternator) and a wait until this
-- client's copy shows the alternator `out` or not. Skips the menu's walk and hood, which the
-- fixture has seen to.
local function alternatorJob(self, car, mode, out)
    T.step(function()
        local item = mode == Action.PUT_BACK_ALTERNATOR and T.carried(CarAlternator.ITEM) or nil
        ISTimedActionQueue.add(Action:new(T.player(), mode, nil, nil, car.vehicle, item))
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
        self.car = car
        T.step(function()
            local context = engineMenu(car.vehicle)
            local option = context and T.optionNamed(context, getText("IGUI_RenewableEnergy_TakeOutAlternator"))
            self.offered = T.optionState(option)
            if context then context:closeAll() end
        end)
        alternatorJob(self, car, Action.TAKE_OUT_ALTERNATOR, true)
        T.onVehicle(self, car, "alternatorState")
        T.count(self, "takenOut", { CarAlternator.ITEM })
        T.step(function()
            local context = T.newContext()
            local option = CarAlternatorMenu.addOption(context, T.player(), car.vehicle)
            self.secondOption = option and option.name
            context:hideAndChildren()
            self.canTakeTwice = Action:new(T.player(), Action.TAKE_OUT_ALTERNATOR, nil, nil, car.vehicle):canPerform()
        end)
        T.onVehicle(self, car, "takeOutAlternatorAgain")
        T.count(self, "afterSecond", { CarAlternator.ITEM })
    end,
    validate = function(self)
        local offered = self.offered
        expect(offered and offered.shown and not offered.greyed, "the engine's menu doesn't offer Take Out Alternator: "
            .. tostring(offered and offered.reason))
        if not expect(self.server.alternatorState and self.counts.takenOut, "taking the alternator out never finished") then return end
        expect(self.server.alternatorState.out, "the server's car doesn't show its alternator out")
        expect(self.counts.takenOut[CarAlternator.ITEM] == 1, "taking it out gave "
            .. tostring(self.counts.takenOut[CarAlternator.ITEM]) .. " alternators, expected 1")
        expect(self.secondOption == getText("IGUI_RenewableEnergy_PutBackAlternator"), "with the alternator out the menu offers "
            .. tostring(self.secondOption))
        expect(not self.canTakeTwice, "the job would take a second alternator out of the car")
        expect(self.server.takeOutAlternatorAgain and not self.server.takeOutAlternatorAgain.gave,
            "the authority gave a second alternator")
        expect(self.counts.afterSecond[CarAlternator.ITEM] == 1, "a second try left "
            .. tostring(self.counts.afterSecond[CarAlternator.ITEM]) .. " alternators, expected 1")
    end,
})

-- An hour of vanilla's alternator charging (the alternatorCharge handler, RenewableEnergyTestServer.lua)
-- adds nothing to the battery of a car whose alternator is out, and charges it again once the
-- alternator is back, which takes it from the inventory.
test("renewable_energy_gadgets_car_alternator_out_stops_charging", {
    instant = true,
    run = function(self)
        local car = readyCar(self, { battery = CAR_BATTERY })
        if not car then return end
        local function charge(key)
            T.onVehicle(self, car, "alternatorCharge", { uses = 0.2, minutes = 60 })
            T.step(function() self[key] = car.answer end)
        end
        alternatorJob(self, car, Action.TAKE_OUT_ALTERNATOR, true)
        charge("without")
        alternatorJob(self, car, Action.PUT_BACK_ALTERNATOR, false)
        charge("with")
        T.count(self, "putBack", { CarAlternator.ITEM })
    end,
    validate = function(self)
        if not expect(self.without and self.with, "the charging hours never both ran") then return end
        expect(math.abs(self.without.gain) < 1e-6, "a car without its alternator gained " .. self.without.gain .. " of a charge")
        expect(self.with.gain > 0, "the car didn't charge once its alternator was back")
        expect(self.counts.putBack[CarAlternator.ITEM] == 0, "the alternator put back is still in the inventory")
    end,
})

-- Scrapping a smashed wreck drops one alternator when the roll comes up and none when it doesn't;
-- a burnt wreck never does, whatever the roll.
local SCRAPS = {
    { behavior = "smashed_wreck_hit_drops_one", script = "Base.CarNormalSmashedFront", roll = 0, alternators = 1 },
    { behavior = "smashed_wreck_miss_drops_none", script = "Base.CarNormalSmashedFront", roll = 1 - T.UNDER, alternators = 0 },
    { behavior = "burnt_wreck_never_drops", script = "Base.CarNormalBurnt", roll = 0, alternators = 0 },
}
for _, case in ipairs(SCRAPS) do
    test("renewable_energy_gadgets_car_alternator_scrap_" .. case.behavior, {
        run = function(self)
            local wreck = T.placeVehicle(self, case.script)
            if not wreck then return end
            T.forceRoll(self, case.roll)
            T.onVehicle(self, wreck, "scrapWreck")
        end,
        validate = function(self)
            local scrap = self.server.scrapWreck
            if not expect(scrap and scrap.done and scrap.removed, "the wreck was never scrapped") then return end
            expect(scrap.alternators == case.alternators, "scrapping a " .. case.script .. " at a roll of " .. case.roll
                .. " dropped " .. scrap.alternators .. " alternators, expected " .. case.alternators)
        end,
    })
end
