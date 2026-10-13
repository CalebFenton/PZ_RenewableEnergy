require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Gadgets/VehicleBattery"
require "RenewableEnergy/UI/VehicleBatteryMenu"
require "Moveables/ISMoveableSpriteProps"
-- RenewableEnergy.GadgetCharging and vanilla's vehicle updates (server/Vehicles/Vehicles.lua) are
-- server Lua, which single player loads only once a game starts, so tests look them up when they
-- run rather than require them here.

-- Gadget tests: the solar battery maintainer, the solar battery charger, the deep cycle battery in
-- a vehicle and the solar garden light. See RenewableEnergyTestLib.lua for how the runner works.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local Sprites, Specs = RenewableEnergy.Sprites, RenewableEnergy.Specs
local SolarMaintainer, SolarCellCharger = RenewableEnergy.SolarMaintainer, RenewableEnergy.SolarCellCharger
local SolarGardenLight, VehicleBattery = RenewableEnergy.SolarGardenLight, RenewableEnergy.VehicleBattery

local NOON, MIDNIGHT = 12, 0
local CAR, CAR_BATTERY = "Base.CarNormal", "Base.CarBattery1"
-- The longest a test waits for a new vehicle to join the cell or start, in ticks. Both happen in
-- real time, so at a high frame rate they take more ticks.
local VEHICLE_FRAMES = 600
-- The longest a test waits for the lighting to drop a removed light, in ticks.
local LIGHT_FRAMES = 600

local function outdoorSquare(self)
    return T.need(self, (T.squares(self, 1, { bare = true }) or {})[1], "a free outdoor square")
end

-- A new vehicle joins the cell's vehicle set, which the gadget passes walk, on a later cell update
-- (IsoCell.addVehicles).
local function inCell(vehicle)
    local vehicles = getCell():getVehicles():iterator()
    while vehicles:hasNext() do
        if vehicles:next() == vehicle then
            return true
        end
    end
    return false
end

-- Solar battery maintainer -----------------------------------------------------------------------

local function attachMaintainer(vehicle)
    local item = T.player():getInventory():AddItem(SolarMaintainer.ITEM)
    return SolarMaintainer.attach(T.player(), vehicle, item)
end

test("renewable_energy_gadgets_maintainer_attach_detach", {
    run = function(self)
        local vehicle = T.vehicle(self, CAR, { battery = CAR_BATTERY, charge = 0.5 })
        if not vehicle then return end
        local inventory = T.player():getInventory()
        self.canAttach = SolarMaintainer.canAttach(vehicle)
        self.attached = attachMaintainer(vehicle)
        self.isAttached = SolarMaintainer.isAttached(vehicle)
        self.itemsWhileAttached = inventory:getCountTypeRecurse(SolarMaintainer.ITEM)
        self.canAttachTwice = SolarMaintainer.canAttach(vehicle)
        self.detached = SolarMaintainer.detach(T.player(), vehicle)
        self.isAttachedAfter = SolarMaintainer.isAttached(vehicle)
        self.itemsAfter = inventory:getCountTypeRecurse(SolarMaintainer.ITEM)
    end,
    validate = function(self)
        expect(self.canAttach and self.attached and self.isAttached, "the maintainer did not attach")
        expect(self.itemsWhileAttached == 0, "the attached maintainer is still in the inventory")
        expect(not self.canAttachTwice, "a second maintainer could attach")
        expect(self.detached and not self.isAttachedAfter, "the maintainer did not detach")
        expect(self.itemsAfter == 1, "detaching gave back " .. tostring(self.itemsAfter) .. " maintainers, expected 1")
    end,
})

-- An hour on a half charged car battery, in order on one car. Charging reads the live weather, so
-- noon sun can only be expected to add something.
local MAINTAINER_HOURS = {
    { what = "noon without a maintainer", hour = NOON, maintainer = false, charges = false },
    { what = "midnight with a maintainer", hour = MIDNIGHT, maintainer = true, charges = false },
    { what = "noon with a maintainer", hour = NOON, maintainer = true, charges = true },
}

-- Charges in the noon sun only with a maintainer attached, and through the pass that finds every
-- loaded vehicle.
test("renewable_energy_gadgets_maintainer_charge", {
    run = function(self)
        local vehicle, battery = T.vehicle(self, CAR, { battery = CAR_BATTERY })
        if not T.need(self, battery, "a car battery") then return end
        self.battery, self.rows = battery, {}
        for _, row in ipairs(MAINTAINER_HOURS) do
            if row.maintainer and not SolarMaintainer.isAttached(vehicle) then
                attachMaintainer(vehicle)
            end
            T.setTime(self, row.hour)
            battery:setCurrentUsesFloat(0.5)
            local wh = SolarMaintainer.charge(vehicle, 1)
            table.insert(self.rows, { row = row, wh = wh, after = battery:getCurrentUsesFloat() })
        end
        T.waitUntil(function() return inCell(vehicle) end, VEHICLE_FRAMES)
    end,
    validate = function(self)
        for _, r in ipairs(self.rows) do
            if r.row.charges then
                expect(r.wh > 0 and r.after > 0.5, "an hour at " .. r.row.what .. " added " .. r.wh .. " Wh")
            else
                expect(r.wh == 0 and math.abs(r.after - 0.5) < 0.001, "an hour at " .. r.row.what .. " added " .. r.wh .. " Wh")
            end
        end
        if expect(RenewableEnergy.GadgetCharging ~= nil, "the gadget charging pass is not loaded") then
            local before = self.battery:getCurrentUsesFloat()
            RenewableEnergy.GadgetCharging.chargeVehicles(1)
            expect(self.battery:getCurrentUsesFloat() > before, "the vehicle pass did not charge the maintained car")
        end
    end,
})

-- Solar battery charger --------------------------------------------------------------------------

local function placeCharger(self)
    local square = outdoorSquare(self)
    return square and T.placeMoveable(self, square, "RenewableEnergy.SolarCellCharger", Sprites.cellCharger)
        and SolarCellCharger.findOn(square)
end

local function loadBatteries(container, count)
    local batteries = {}
    for _ = 1, count do
        local battery = container:AddItem("Base.Battery")
        battery:setCurrentUsesFloat(0)
        table.insert(batteries, battery)
    end
    return batteries
end

local function charges(batteries)
    local list = {}
    for i, battery in ipairs(batteries) do
        list[i] = battery:getCurrentUsesFloat()
    end
    return list
end

-- Placed through the moveables cursor, it takes four vanilla batteries and nothing else.
test("renewable_energy_gadgets_solar_battery_charger_container", {
    run = function(self)
        local charger = placeCharger(self)
        local container = T.need(self, charger and charger:getContainer(), "a placed solar battery charger with a container")
        if not container then return end
        self.acceptsBattery = container:isItemAllowed(instanceItem("Base.Battery"))
        self.acceptsCarBattery = container:isItemAllowed(instanceItem(CAR_BATTERY))
        loadBatteries(container, SolarCellCharger.SLOTS)
        self.acceptsFifth = container:isItemAllowed(instanceItem("Base.Battery"))
    end,
    validate = function(self)
        expect(self.acceptsBattery, "the solar battery charger refuses a battery")
        expect(not self.acceptsCarBattery, "the solar battery charger takes a car battery")
        expect(not self.acceptsFifth, "the solar battery charger takes a fifth battery")
    end,
})

-- Two hours on a full set of empty batteries at noon and at midnight, a charger each. Charging
-- reads the live weather, so noon sun can only be expected to add something, evenly; a set fills
-- in one to two sunny days, so two noon hours stay well short of half.
test("renewable_energy_gadgets_solar_battery_charger_charges", {
    run = function(self)
        self.rows = {}
        for _, hour in ipairs({ NOON, MIDNIGHT }) do
            local charger = placeCharger(self)
            local container = T.need(self, charger and charger:getContainer(), "a placed solar battery charger with a container")
            if not container then return end
            local batteries = loadBatteries(container, SolarCellCharger.SLOTS)
            T.setTime(self, hour)
            local row = { hour = hour, added = SolarCellCharger.charge(charger, 2), after = charges(batteries) }
            if hour == NOON then
                SolarCellCharger.chargeAll(2)
                row.afterPass = charges(batteries)
            end
            table.insert(self.rows, row)
        end
    end,
    validate = function(self)
        local noon, midnight = self.rows[1], self.rows[2]
        expect(noon.added > 0, "two hours of noon sun charged nothing")
        local low, high = math.min(unpack(noon.after)), math.max(unpack(noon.after))
        expect(high - low <= 0.01, "the batteries charged unevenly, from " .. low .. " to " .. high)
        expect(high < 0.5, "two hours of noon sun filled the batteries to " .. high)
        expect(noon.afterPass[1] > noon.after[1], "the charger pass did not charge the placed solar battery charger")
        expect(midnight.added == 0 and math.max(unpack(midnight.after)) == 0, "two hours of night charged " .. midnight.added .. " uses")
    end,
})

-- Deep cycle battery in a vehicle ----------------------------------------------------------------

-- Works on vehicles as ISVehicleMechanics.cheat does, so that installing needs no key, hood or
-- walk, which the debug car may not allow.
local function mechanicsCheat(self)
    local saved = ISVehicleMechanics.cheat
    T.defer(self, function() ISVehicleMechanics.cheat = saved end)
    ISVehicleMechanics.cheat = true
end

-- The mechanics window's menu for `part`, built by its own doPartContextMenu on a window that
-- has just what that function reads.
local function partMenu(vehicle, part)
    local window = setmetatable({ chr = T.player(), playerNum = 0, vehicle = vehicle }, { __index = ISVehicleMechanics })
    window.getAbsoluteX = function() return 0 end
    window.getAbsoluteY = function() return 0 end
    window:doPartContextMenu(part, 0, 0)
    return window.context
end

local function subMenuOf(context, option)
    return option and option.subOption and context:getSubMenu(option.subOption)
end

-- The mechanics menu of an empty battery slot offers the deep cycle battery the character
-- carries, and picking it installs it with vanilla's action; uninstalling gives it back with its
-- charge.
test("renewable_energy_gadgets_deep_cycle_battery_installs_and_uninstalls", {
    instant = true,
    run = function(self)
        local vehicle = T.vehicle(self, CAR)
        local part = T.need(self, vehicle and vehicle:getPartById(VehicleBattery.PART), "a car with a battery slot")
        if not part then return end
        self.part = part
        part:setInventoryItem(nil)
        mechanicsCheat(self)
        T.player():getInventory():AddItem(VehicleBattery.ITEM)
        local context = partMenu(vehicle, part)
        T.defer(self, function() context:closeAll() end)
        local install = subMenuOf(context, context:getOptionFromName(getText("IGUI_Install")))
        local deepCycle = subMenuOf(context, install and install:getOptionFromName(getItemName(VehicleBattery.ITEM)))
        local pick = deepCycle and deepCycle.options[1]
        self.offered = pick ~= nil
        if not pick then return end
        pick.onSelect(pick.target, pick.param1, pick.param2)
        T.step(function()
            local installed = part:getInventoryItem()
            self.installed = installed and installed:getFullType()
            self.carriedWhileInstalled = T.player():getInventory():getCountTypeRecurse(VehicleBattery.ITEM)
            if installed then
                installed:setCurrentUsesFloat(0.5)
                ISVehiclePartMenu.onUninstallPart(T.player(), part)
            end
        end)
    end,
    validate = function(self)
        if not expect(self.offered, "the mechanics menu doesn't offer the deep cycle battery under Install") then return end
        expect(self.installed == VehicleBattery.ITEM, "the battery slot holds " .. tostring(self.installed))
        expect(self.carriedWhileInstalled == 0, "the installed battery is still in the inventory")
        expect(self.part:getInventoryItem() == nil, "the battery slot still holds a battery after uninstalling")
        local battery = T.player():getInventory():getFirstTypeRecurse(VehicleBattery.ITEM)
        expect(battery ~= nil and math.abs(battery:getCurrentUsesFloat() - 0.5) < 0.001,
            "the deep cycle battery came back at " .. tostring(battery and battery:getCurrentUsesFloat()))
    end,
})

-- What a car battery's charge over a deep cycle battery's comes to for the same watt-hours.
local function capacityRatio()
    return Specs.batteries[CAR_BATTERY].wh / Specs.batteries[VehicleBattery.ITEM].wh
end

-- Fraction of a full charge vanilla's headlight update takes from each car's battery in an hour
-- with the engine off. Both cars run the same light, and the deep cycle battery loses less of its
-- charge by its capacity over a car battery's.
test("renewable_energy_gadgets_deep_cycle_battery_drains_slower", {
    run = function(self)
        self.cars = {}
        for _, batteryType in ipairs({ CAR_BATTERY, VehicleBattery.ITEM }) do
            local vehicle, battery = T.vehicle(self, CAR, { battery = batteryType, charge = 0.8 })
            local headlight = vehicle and vehicle:getPartById("HeadlightLeft")
            if not T.need(self, headlight and headlight:getInventoryItem(), "a car with a left headlight") then return end
            table.insert(self.cars, { vehicle = vehicle, battery = battery, headlight = headlight })
        end
    end,
    validate = function(self)
        local drops = {}
        for _, car in ipairs(self.cars) do
            car.vehicle:setHeadlightsOn(true)
            Vehicles.Update.Headlight(car.vehicle, car.headlight, 60)
            car.vehicle:setHeadlightsOn(false)
            table.insert(drops, 0.8 - car.battery:getCurrentUsesFloat())
        end
        if expect(drops[1] > 0, "the headlight didn't drain the car battery") then
            T.expectNear("deep cycle drain over car battery drain", drops[2] / drops[1], capacityRatio(), 0.01)
        end
    end,
})

-- A running engine charges both batteries by the same watt-hours, so the bigger one gains less
-- of its charge.
test("renewable_energy_gadgets_deep_cycle_battery_charges_from_vehicle", {
    run = function(self)
        self.cars = {}
        for _, batteryType in ipairs({ CAR_BATTERY, VehicleBattery.ITEM }) do
            local vehicle = T.vehicle(self, CAR, { battery = batteryType })
            if not vehicle then return end
            T.defer(self, function() vehicle:shutOff() end)
            -- A running engine shuts down without fuel and stalls at random below half condition.
            vehicle:repair()
            local tank = vehicle:getPartById("GasTank")
            if tank then
                tank:setContainerContentAmount(tank:getContainerCapacity())
            end
            local part = vehicle:getPartById(VehicleBattery.PART)
            local battery = part:getInventoryItem()
            if not T.need(self, battery and battery:getFullType() == batteryType, "a car holding a " .. batteryType) then return end
            battery:setCurrentUsesFloat(0.2)
            table.insert(self.cars, { vehicle = vehicle, battery = battery, part = part })
        end
        -- Starts both engines, again each tick until both report running.
        T.waitUntil(function()
            local running = true
            for _, car in ipairs(self.cars) do
                if not car.vehicle:isEngineRunning() then
                    car.vehicle:engineDoRunning()
                    running = running and car.vehicle:isEngineRunning()
                end
            end
            return running
        end, VEHICLE_FRAMES)
    end,
    validate = function(self)
        local gains = {}
        for _, car in ipairs(self.cars) do
            if not expect(car.vehicle:isEngineRunning(), "the debug car's engine wouldn't run") then return end
            Vehicles.Update.Battery(car.vehicle, car.part, 60)
            table.insert(gains, car.battery:getCurrentUsesFloat() - 0.2)
        end
        if expect(gains[1] > 0, "the alternator didn't charge the car battery") then
            T.expectNear("deep cycle gain over car battery gain", gains[2] / gains[1], capacityRatio(), 0.01)
        end
    end,
})

-- Solar garden light -----------------------------------------------------------------------------

local function placeGardenLight(self, charge)
    local square = outdoorSquare(self)
    return square and T.placeMoveable(self, square, SolarGardenLight.ITEM, Sprites.gardenLight.off,
        { [SolarGardenLight.CHARGE_KEY] = charge }) and SolarGardenLight.findOn(square)
end

local function lampOn(square)
    return getCell():getLightSourceAt(square:getX(), square:getY(), square:getZ()) ~= nil
end

-- A placed light run for `hours` at `hour` from `charge` Wh: whether it is lit afterwards (its
-- sprite and its lamp both), and its charge in Wh, or for the noon row a range. It goes out once
-- the night has drawn its battery empty, and by day its cell charges the battery, never past full.
local GARDEN_LIGHT_HOURS = {
    { what = "charged at midnight", hour = MIDNIGHT, charge = 2, hours = 0.5, lit = true,
        after = 2 - Specs.gardenLight.nightWatts * 0.5 },
    { what = "empty at midnight", hour = MIDNIGHT, charge = 0, hours = 0.5, lit = false, after = 0 },
    { what = "running out at night", hour = MIDNIGHT, charge = 0.2, hours = 1, lit = false, after = 0 },
    { what = "empty at noon", hour = NOON, charge = 0, hours = 2, lit = false, low = 0, high = Specs.gardenLight.wh },
}

test("renewable_energy_gadgets_garden_light_update", {
    run = function(self)
        self.rows = {}
        for _, row in ipairs(GARDEN_LIGHT_HOURS) do
            local light = placeGardenLight(self, row.charge)
            if not light then return end
            T.setTime(self, row.hour)
            table.insert(self.rows, {
                row = row,
                lit = SolarGardenLight.update(light, row.hours),
                sprite = light:getTextureName(),
                lamp = lampOn(light:getSquare()),
                charge = SolarGardenLight.getCharge(light),
            })
        end
    end,
    validate = function(self)
        for _, r in ipairs(self.rows) do
            local row = r.row
            local sprite = row.lit and Sprites.gardenLight.lit or Sprites.gardenLight.off
            expect(r.lit == row.lit and r.sprite == sprite and r.lamp == row.lit,
                string.format("a light %s: lit %s, sprite %s, lamp %s; expected lit %s", row.what,
                    tostring(r.lit), r.sprite, tostring(r.lamp), tostring(row.lit)))
            if row.after then
                T.expectNear("charge of a light " .. row.what, r.charge, row.after)
            else
                expect(r.charge > row.low and r.charge <= row.high, "a light " .. row.what .. " ended at " .. r.charge .. " Wh")
            end
        end
    end,
})

-- Picking up a lit light takes its light away with it, by a later lighting pass.
test("renewable_energy_gadgets_garden_light_pick_up_takes_light", {
    hour = MIDNIGHT,
    run = function(self)
        local light = placeGardenLight(self, 2)
        if not light then return end
        local square = light:getSquare()
        self.square = square
        SolarGardenLight.update(light, 0.5)
        self.lamp = lampOn(square)
        if not self.lamp then return end
        ISMoveableSpriteProps.new(light:getTextureName()):pickUpMoveable(T.player(), square, false, true)
        T.waitUntil(function() return not lampOn(square) end, LIGHT_FRAMES)
    end,
    validate = function(self)
        if not expect(self.lamp, "the light never lit") then return end
        expect(not lampOn(self.square), "the light still shines where the garden light was")
    end,
})

-- A garden light goes on the ground outdoors, where the sun reaches it.
test("renewable_energy_gadgets_garden_light_refused_indoors", {
    run = function(self)
        local indoor = T.need(self, (T.squares(self, 1, { indoors = true }) or {})[1], "a free indoor square")
        local outdoor = outdoorSquare(self)
        if not (indoor and outdoor) then return end
        local props = ISMoveableSpriteProps.new(Sprites.gardenLight.off)
        local item = instanceItem(SolarGardenLight.ITEM)
        self.indoors = props:canPlaceMoveable(T.player(), indoor, item)
        self.outdoors = props:canPlaceMoveable(T.player(), outdoor, item)
    end,
    validate = function(self)
        expect(not self.indoors, "a garden light can be placed indoors")
        expect(self.outdoors, "a garden light can't be placed outdoors")
    end,
})
