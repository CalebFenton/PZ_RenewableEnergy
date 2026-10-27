require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Sun = require "RenewableEnergy/Sun"
local Specs = require "RenewableEnergy/Specs"
local SolarMaintainer = require "RenewableEnergy/Gadgets/SolarMaintainer"
local SolarCellCharger = require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/UI/VehicleMechanicsMenu"
local VehicleMenu = require "RenewableEnergy/UI/VehicleMenu"
require "TimedActions/ISInventoryTransferAction"
local VehicleJobs = require "RenewableEnergy/Gadgets/VehicleJobs"
local Sprites = require "RenewableEnergy/Sprites"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"

-- Gadgets: the solar battery maintainer, the solar battery charger and the deep cycle vehicle
-- battery (Gadgets/*, UI/VehicleMechanicsMenu.lua, the maintainer option of UI/VehicleMenu.lua); the
-- garden light's are in RenewableEnergyTestsSolarGardenLight.lua. The authority runs them, so the
-- tests drive them through T.server and check this client's copies.

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual = T.test, T.expect, T.expectNear, T.expectEqual

local NOON, MIDNIGHT = 12, 0
local CAR = "Base.CarNormal"

-- The most a gadget rated `watts` can make in `hours`: full sun the whole time.
local function fullSunWh(watts, hours)
    return Sun.wattsFrom(watts, Sun.FULL_SUN, 0) * hours
end

-- Solar battery maintainer -----------------------------------------------------------------------

-- Queues the job of the maintainer option on `car`'s menu and a wait until this client's copy
-- shows it `attached` or not. Skips the option's walk, which the debug car may not allow.
local function chooseMaintainerOption(self, car, attached)
    T.step(function()
        local context = T.newContext()
        local option = VehicleMenu.addVehicleOptions(0, context, car.vehicle)
        context:hideAndChildren()
        if not T.need(self, option, "the maintainer option on the car's menu") then return end
        ISTimedActionQueue.add(RenewableEnergyAction:new(T.player(), option.param1, option.param2, option.param3, option.param4))
        T.waitFor(self, function() return SolarMaintainer.isAttached(car.vehicle) == attached end,
            "this client's car with the maintainer " .. (attached and "attached" or "detached"))
    end)
end

-- The menu offers no maintainer to someone without one; it attaches a carried one to a car, on the
-- server and this client, takes it from the inventory, refuses a second one, and detaching gives it
-- back and leaves nothing to detach.
test("renewable_energy_gadgets_maintainer_attach_detach", {
    instant = true,
    run = function(self)
        local car = T.placeVehicle(self, CAR, { battery = T.CAR_BATTERY, charge = 0.5 })
        if not car then return end
        self.car = car
        T.step(function()
            local context = T.newContext()
            self.offeredEmptyHanded = VehicleMenu.addVehicleOptions(0, context, car.vehicle) ~= nil
            context:hideAndChildren()
        end)
        T.give(self, "maintainer", { { type = SolarMaintainer.ITEM } })
        chooseMaintainerOption(self, car, true)
        T.onVehicle(self, car, "vehicleState", nil, "attached")
        T.count(self, "attached", { SolarMaintainer.ITEM })
        T.step(function()
            self.copyAttached = SolarMaintainer.isAttached(car.vehicle)
            self.canAttachTwice = SolarMaintainer.canAttach(car.vehicle)
        end)
        chooseMaintainerOption(self, car, false)
        T.onVehicle(self, car, "vehicleState", nil, "detached")
        T.count(self, "detached", { SolarMaintainer.ITEM })
    end,
    validate = function(self)
        expect(not self.offeredEmptyHanded, "a car offers a maintainer to someone without one")
        expect(self.reads.attached.state.attached, "the maintainer did not attach on the server")
        expect(self.copyAttached, "this client's copy of the car doesn't show the maintainer attached")
        expect(self.counts.attached[SolarMaintainer.ITEM] == 0, "the attached maintainer is still in the inventory")
        expect(not self.canAttachTwice, "a second maintainer could attach")
        expect(not self.reads.detached.state.attached, "the maintainer did not detach on the server")
        expect(not SolarMaintainer.isAttached(self.car.vehicle), "this client's copy of the car still shows the maintainer")
        expect(VehicleJobs.refusal(T.player(), VehicleJobs.DETACH_MAINTAINER, self.car.vehicle) ~= nil,
            "a car without a maintainer offers to detach one")
        expectEqual("maintainers detaching gave back", self.counts.detached[SolarMaintainer.ITEM], 1)
    end,
})

-- An hour on a half charged car battery: noon without a maintainer, then midnight and noon with one.
local WITHOUT_MAINTAINER = { what = "noon without a maintainer", hour = NOON }
local WITH_MAINTAINER = {
    { what = "midnight with a maintainer", hour = MIDNIGHT },
    { what = "noon with a maintainer", hour = NOON, charges = true },
}
local ROW_HOURS, ROW_START = 1, 0.5

-- Charges only by day with a maintainer attached, at most its rating in full sun, and the pass
-- over every vehicle gives as much. Noon reads live weather, so it is checked against bounds.
test("renewable_energy_gadgets_maintainer_charge", {
    instant = true,
    run = function(self)
        local car = T.placeVehicle(self, CAR, { battery = T.CAR_BATTERY })
        if not car then return end
        -- Each hour's clock is set in its turn: single player sets it at once, when it is queued.
        local function hour(row)
            T.step(function() T.setTime(self, row.hour) end)
            T.onVehicle(self, car, "maintainerCharge", { hours = ROW_HOURS, uses = ROW_START }, row.what)
        end
        hour(WITHOUT_MAINTAINER)
        T.give(self, "maintainer", { { type = SolarMaintainer.ITEM } })
        T.step(function()
            ISTimedActionQueue.add(RenewableEnergyAction:new(T.player(), "vehicle", VehicleJobs.ATTACH_MAINTAINER, car.vehicle,
                self.items.maintainer[1]))
        end)
        T.waitFor(self, function() return SolarMaintainer.isAttached(car.vehicle) end, "this client's car with the maintainer attached")
        for _, row in ipairs(WITH_MAINTAINER) do
            hour(row)
        end
        T.onVehicle(self, car, "chargeVehicles", { hours = ROW_HOURS }, "pass")
    end,
    validate = function(self)
        local charged
        for _, row in ipairs({ WITHOUT_MAINTAINER, WITH_MAINTAINER[1], WITH_MAINTAINER[2] }) do
            local reply = self.reads[row.what]
            local wh, after = reply.wh, reply.after
            if row.charges then
                charged = reply
                local most = fullSunWh(SolarMaintainer.WATTS, ROW_HOURS)
                expect(wh > 0 and wh <= most and after > ROW_START,
                    "an hour at " .. row.what .. " added " .. wh .. " Wh, expected more than 0 and at most " .. most)
            else
                expect(wh == 0 and math.abs(after - ROW_START) < 0.001, "an hour at " .. row.what .. " added " .. wh .. " Wh")
            end
        end
        -- The pass runs the maintainer for as long as the noon row, right after it, so it adds what
        -- that hour added; the light can still move a little between the two calls.
        local pass, capacityWh = self.reads.pass, charged.capacityWh
        expectNear("Wh the vehicle pass gave the maintained car", (pass.after - pass.before) * capacityWh, charged.wh, charged.wh / 50)
    end,
})

-- An older save marks an attached maintainer with the condition it went on with. Detaching one
-- still gives back a single whole maintainer, not one at that condition.
test("renewable_energy_gadgets_maintainer_detach_older_save_mark", {
    instant = true,
    run = function(self)
        local car = T.placeVehicle(self, CAR)
        if not car then return end
        T.onVehicle(self, car, "oldMaintainerMark", { condition = 1 })
        T.waitFor(self, function() return SolarMaintainer.isAttached(car.vehicle) end,
            "this client's car with the older save's maintainer mark")
        chooseMaintainerOption(self, car, false)
        T.onVehicle(self, car, "vehicleState", nil, "detached")
        T.count(self, "carried", { SolarMaintainer.ITEM })
        T.waitForCarried(self, SolarMaintainer.ITEM, "this client's copy of the detached maintainer")
        T.step(function()
            local item = T.carried(SolarMaintainer.ITEM)
            self.condition = item and item:getCondition()
        end)
    end,
    validate = function(self)
        expect(not self.reads.detached.state.attached, "an older save's maintainer did not detach on the server")
        expectEqual("maintainers detaching gave back", self.counts.carried[SolarMaintainer.ITEM], 1)
        expectEqual("the detached maintainer's condition", self.condition, instanceItem(SolarMaintainer.ITEM):getConditionMax())
    end,
})

-- Solar battery charger --------------------------------------------------------------------------

-- A solar battery charger the character places on a free outdoor square; see T.placeAsPlayer.
local function placeCharger(self)
    local square = T.square(self, { bare = true }, "a free outdoor square")
    return square and T.placeAsPlayer(self, square, SolarCellCharger.ITEM, Sprites.cellCharger)
end

-- Placed as a player does, it takes SolarCellCharger.SLOTS vanilla batteries and nothing else,
-- on the server and this client's copy.
test("renewable_energy_gadgets_solar_battery_charger_container", {
    instant = true,
    run = function(self)
        local charger = placeCharger(self)
        if not charger then return end
        self.charger = charger
        T.give(self, "batteries", { { type = SolarCellCharger.BATTERY, count = SolarCellCharger.SLOTS } })
        T.step(function()
            local p, container = T.player(), charger.object:getContainer()
            if not T.need(self, container, "a container in the placed solar battery charger") then return end
            self.acceptsBattery = container:isItemAllowed(instanceItem(SolarCellCharger.BATTERY))
            self.acceptsCarBattery = container:isItemAllowed(instanceItem(T.CAR_BATTERY))
            for _, battery in ipairs(self.items.batteries) do
                ISTimedActionQueue.add(ISInventoryTransferAction:new(p, battery, p:getInventory(), container))
            end
            T.waitFor(self, function() return container:getItems():size() == SolarCellCharger.SLOTS end,
                "this client's charger holding " .. SolarCellCharger.SLOTS .. " batteries")
            T.read(self, "chargerState", T.at(charger, { kind = "charger" }), "charger")
            T.step(function() self.acceptsPastSlots = container:isItemAllowed(instanceItem(SolarCellCharger.BATTERY)) end)
        end)
    end,
    validate = function(self)
        expect(self.acceptsBattery, "the solar battery charger refuses a battery")
        expect(not self.acceptsCarBattery, "the solar battery charger takes a car battery")
        expectEqual("batteries in the server's charger", #self.reads.charger.items, SolarCellCharger.SLOTS)
        expect(not self.acceptsPastSlots, "the solar battery charger takes a battery past its " .. SolarCellCharger.SLOTS .. " slots")
    end,
})

local CELL_HOURS = 2

-- A fresh charger per row, the pass row last since the pass charges every charger. "full" holds
-- cells as the game makes them full (their float reads just under 1).
local CHARGER_ROWS = {
    { name = "midnight", hour = MIDNIGHT, uses = 0 },
    { name = "full", hour = NOON },
    { name = "noon", hour = NOON, uses = 0, pass = true },
}

-- Charges by day only, at most its rating in full sun, in whole uses spread evenly, and the pass
-- over every charger as much again. Full cells take nothing and nothing is stored for later.
test("renewable_energy_gadgets_solar_battery_charger_charges", {
    instant = true,
    run = function(self)
        for _, row in ipairs(CHARGER_ROWS) do
            local charger = placeCharger(self)
            if not charger then return end
            T.step(function() T.setTime(self, row.hour) end)
            T.read(self, "cellCharge", T.at(charger,
                { kind = "charger", count = SolarCellCharger.SLOTS, uses = row.uses, hours = CELL_HOURS, pass = row.pass }), row.name)
        end
    end,
    validate = function(self)
        local noon, midnight, full = self.reads.noon, self.reads.midnight, self.reads.full
        local useDelta = instanceItem(SolarCellCharger.BATTERY):getUseDelta()
        local useWh = useDelta * SolarCellCharger.BATTERY_WH
        local most = fullSunWh(SolarCellCharger.WATTS, CELL_HOURS)
        expect(noon.added > 0 and noon.added * useWh <= most, CELL_HOURS .. " hours of noon sun added " .. noon.added
            .. " uses of " .. useWh .. " Wh, expected more than 0 and at most " .. most .. " Wh")
        -- Each battery's uses, in the charger's order.
        local function uses(items)
            local list = {}
            for i, item in ipairs(items) do
                list[i] = item.uses
            end
            return list
        end
        local after, afterPass = uses(noon.after), uses(noon.afterPass)
        local low, high = math.min(unpack(after)), math.max(unpack(after))
        expect(high - low <= useDelta + 1e-6, "the batteries charged unevenly, from " .. low .. " to " .. high)
        -- The pass gets the same sun for as long, plus what the first run kept toward a use.
        local passUses = 0
        for i, charge in ipairs(afterPass) do
            passUses = passUses + (charge - after[i]) / useDelta
        end
        expectNear("uses the charger pass as long again added", passUses, noon.added, 1.01)
        expect(midnight.added == 0 and math.max(unpack(uses(midnight.after))) == 0, CELL_HOURS .. " hours of night charged "
            .. midnight.added .. " uses")
        expectEqual("uses full cells took at noon", full.added, 0)
        expectEqual("whether full cells read all full", full.full, true)
        expectEqual("Wh the charger kept from full cells", full.storedWh, 0)
    end,
})

-- Sets the mechanics window's Lua cheat (no key, hood or walk) for the test, not the character's
-- cheat, which would also make the install instant and skip its isValid.
local function mechanicsCheat(self)
    local saved = ISVehicleMechanics.cheat
    T.defer(self, function() ISVehicleMechanics.cheat = saved end)
    ISVehicleMechanics.cheat = true
end

-- The mechanics menu of an empty battery slot installs a carried deep cycle battery. A real-time
-- action: an instant one fails vanilla's isValid on a multiplayer client when the server's slot
-- change arrives. Uninstalling is vanilla's alone (ISUninstallVehiclePart takes any item).
test("renewable_energy_gadgets_deep_cycle_battery_installs_from_mechanics_menu", {
    run = function(self)
        T.setPerk(self, Perks.Mechanics, 10)
        local car = T.placeVehicle(self, CAR)
        if not car then return end
        T.onVehicle(self, car, "vehicleBattery", { empty = true })
        T.waitFor(self, function() return T.vehicleBattery(car) == nil end, "this client's car without a battery")
        T.give(self, "battery", { { type = VehicleBattery.ITEM } })
        T.step(function()
            mechanicsCheat(self)
            local context = T.partMenu(car.vehicle, VehicleBattery.partOf(car.vehicle))
            T.defer(self, function() context:closeAll() end)
            local installOption = context:getOptionFromName(getText("IGUI_Install"))
            local install = T.subMenu(context, installOption)
            local deepCycleOption = install and install:getOptionFromName(getItemName(VehicleBattery.ITEM))
            local deepCycle = T.subMenu(context, deepCycleOption)
            local pick = deepCycle and deepCycle.options[1]
            self.offered = pick ~= nil
            if not pick then
                self.offerProblem = not installOption and "no Install option"
                    or not install and "Install has no submenu"
                    or not deepCycleOption and "Install doesn't list it"
                    or "it is listed but not available (" .. tostring(VehicleUtils.getItems(0)[VehicleBattery.ITEM] ~= nil) .. " in reach)"
                return
            end
            T.choose(pick)
            T.waitFor(self, function() return T.vehicleBattery(car) ~= nil end, "this client's car with the deep cycle battery")
            T.onVehicle(self, car, "vehicleState", nil, "installed")
            T.count(self, "installed", { VehicleBattery.ITEM })
        end)
    end,
    validate = function(self)
        if not expect(self.offered, "the mechanics menu doesn't offer the deep cycle battery under Install: "
            .. tostring(self.offerProblem)) then return end
        local installed = self.reads.installed.state.battery
        expectEqual("the server's battery slot's battery", installed and installed.type, VehicleBattery.ITEM)
        expect(self.counts.installed[VehicleBattery.ITEM] == 0, "the installed battery is still in the inventory")
    end,
})

-- What a car battery's charge over a deep cycle battery's comes to for the same watt-hours.
local function capacityRatio()
    return Specs.batteries[T.CAR_BATTERY].wh / Specs.batteries[VehicleBattery.ITEM].wh
end

-- Queues the server handler `name` on a `script` vehicle each with a car battery and a deep cycle
-- battery, with `args` plus the vehicle's T.vehicleArgs, each answer read under its battery's type.
-- When `full`, also waits for the client's charge to arrive from the initially partial charge.
local function onBothBatteries(self, script, name, args, full)
    for _, batteryType in ipairs({ T.CAR_BATTERY, VehicleBattery.ITEM }) do
        local car = T.placeVehicle(self, script, { battery = batteryType, charge = args.uses })
        if not car then return end
        T.onVehicle(self, car, name, args, batteryType)
        if full then
            T.waitFor(self, function() return T.vehicleBattery(car):getCurrentUsesFloat() == 1 end, "this client's full " .. batteryType)
        end
    end
end

-- The same run of each vanilla vehicle update on a car battery and on a deep cycle battery moves the
-- same watt-hours, so the deep cycle's share changes less by the capacity ratio. The lightbar must
-- be scaled once, though vanilla drains it inside the battery update the mod scales. `change` is
-- the answer field holding that share.
local VEHICLE_HOURS = {
    { behavior = "headlight_drain_scales_with_capacity", vehicle = CAR, handler = "headlightDrain", uses = 0.8,
        change = "drop", none = "the headlight didn't drain the car battery" },
    -- Vanilla's lightbar drain is small; a long run makes it measurable.
    { behavior = "lightbar_drain_scales_with_capacity", vehicle = "Base.CarLightsPolice", handler = "lightbarDrain",
        uses = 0.8, minutes = 600, change = "drop", none = "the lightbar didn't drain the car battery" },
    { behavior = "alternator_charge_scales_with_capacity", vehicle = CAR, handler = "alternatorCharge", uses = 0.2,
        change = "gain", none = "the alternator didn't charge the car battery" },
    { behavior = "alternator_fills_near_full_battery", vehicle = CAR, handler = "alternatorCharge", uses = 0.99,
        change = "gain", full = true },
}
for _, case in ipairs(VEHICLE_HOURS) do
    test("renewable_energy_gadgets_deep_cycle_battery_" .. case.behavior, {
        run = function(self)
            onBothBatteries(self, case.vehicle, case.handler, { uses = case.uses, minutes = case.minutes or 60 }, case.full)
        end,
        validate = function(self)
            local car, deepCycle = self.reads[T.CAR_BATTERY], self.reads[VehicleBattery.ITEM]
            if not expectEqual("the deep cycle car's battery", deepCycle.type, VehicleBattery.ITEM) then return end
            if case.full then
                expectNear("the near-full deep cycle battery's final charge", case.uses + deepCycle.gain, 1, 0.0001)
            elseif expect(car[case.change] > 0, case.none) then
                expectNear("deep cycle " .. case.change .. " over car battery " .. case.change,
                    deepCycle[case.change] / car[case.change], capacityRatio(), 0.01)
            end
        end,
    })
end
