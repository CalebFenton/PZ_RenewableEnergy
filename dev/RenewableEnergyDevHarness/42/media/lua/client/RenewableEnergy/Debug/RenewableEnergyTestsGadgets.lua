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
-- back and leaves nothing to detach. An older save marks an attached maintainer with the condition
-- it went on with; detaching one gives back a whole new maintainer all the same.
test("renewable_energy_gadgets_maintainer_attach_detach", {
    instant = true,
    run = function(self)
        local car = T.placeVehicle(self, CAR)
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
        T.step(function()
            self.refusesDetach = VehicleJobs.refusal(T.player(), VehicleJobs.DETACH_MAINTAINER, car.vehicle) ~= nil
        end)
        T.onVehicle(self, car, "oldMaintainerMark", { condition = 1 })
        T.waitFor(self, function() return SolarMaintainer.isAttached(car.vehicle) end,
            "this client's car with the older save's maintainer mark")
        chooseMaintainerOption(self, car, false)
        T.onVehicle(self, car, "vehicleState", nil, "oldDetached")
        T.count(self, "oldDetached", { SolarMaintainer.ITEM })
        T.waitFor(self, function()
            return T.player():getInventory():getCountTypeRecurse(SolarMaintainer.ITEM) == 2
        end, "this client's copies of both detached maintainers")
        T.step(function()
            local worst = math.huge
            local items = T.player():getInventory():getAllTypeRecurse(SolarMaintainer.ITEM)
            for i = 0, items:size() - 1 do
                worst = math.min(worst, items:get(i):getCondition())
            end
            self.worstCondition = worst
        end)
    end,
    validate = function(self)
        expect(not self.offeredEmptyHanded, "a car offers a maintainer to someone without one")
        expect(self.reads.attached.state.attached, "the maintainer did not attach on the server")
        expect(self.copyAttached, "this client's copy of the car doesn't show the maintainer attached")
        expectEqual("maintainers left in the inventory once attached", self.counts.attached[SolarMaintainer.ITEM], 0)
        expect(not self.canAttachTwice, "a second maintainer could attach")
        expect(not self.reads.detached.state.attached, "the maintainer did not detach on the server")
        expect(self.refusesDetach, "a car without a maintainer offers to detach one")
        expectEqual("maintainers detaching gave back", self.counts.detached[SolarMaintainer.ITEM], 1)
        expect(not self.reads.oldDetached.state.attached, "an older save's maintainer did not detach on the server")
        expect(not SolarMaintainer.isAttached(self.car.vehicle), "this client's copy of the car still shows a maintainer")
        expectEqual("maintainers carried after detaching an older save's", self.counts.oldDetached[SolarMaintainer.ITEM], 2)
        expectEqual("the worst condition of the detached maintainers", self.worstCondition,
            instanceItem(SolarMaintainer.ITEM):getConditionMax())
    end,
})

-- An hour on a half charged car battery: noon without a maintainer, then midnight and noon with one.
local WITHOUT_MAINTAINER = { what = "noon without a maintainer", hour = NOON }
local WITH_MAINTAINER = {
    { what = "midnight with a maintainer", hour = MIDNIGHT },
    { what = "noon with a maintainer", hour = NOON, charges = true },
}
local ROW_HOURS, ROW_START = 1, 0.5

-- Charges only by day with a maintainer attached, its rating in the sky the hour ran under, and
-- the pass over every vehicle gives as much.
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
                -- The battery keeps whole uses of its capacity, a car battery's a few thousandths of a Wh.
                local useWh = instanceItem(T.CAR_BATTERY):getUseDelta() * reply.capacityWh
                expect(reply.flat > 0, "no sun at " .. row.what)
                expectNear("Wh an hour at " .. row.what .. " added", wh, Sun.wattsFrom(SolarMaintainer.WATTS, reply.flat, 0) * ROW_HOURS,
                    useWh)
                expect(after > ROW_START, "an hour at " .. row.what .. " left the battery at " .. after)
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

-- One charger, which each row fills afresh; the pass row last, since the pass charges every
-- charger. "full" holds cells as the game makes them full (their float reads just under 1).
local CHARGER_ROWS = {
    { name = "midnight", hour = MIDNIGHT, uses = 0 },
    { name = "full", hour = NOON },
    { name = "noon", hour = NOON, uses = 0, pass = true },
}

-- Charges by day only, its rating in the sky the run had, in whole uses spread evenly, and the
-- pass over every charger as much again. Full cells take nothing and nothing is stored for later.
test("renewable_energy_gadgets_solar_battery_charger_charges", {
    instant = true,
    run = function(self)
        local charger = placeCharger(self)
        if not charger then return end
        for _, row in ipairs(CHARGER_ROWS) do
            T.step(function() T.setTime(self, row.hour) end)
            T.read(self, "cellCharge", T.at(charger,
                { kind = "charger", count = SolarCellCharger.SLOTS, uses = row.uses, hours = CELL_HOURS, pass = row.pass }), row.name)
        end
    end,
    validate = function(self)
        local noon, midnight, full = self.reads.noon, self.reads.midnight, self.reads.full
        local useDelta = instanceItem(SolarCellCharger.BATTERY):getUseDelta()
        local useWh = useDelta * SolarCellCharger.BATTERY_WH
        -- What the panel made goes into the cells in whole uses, and what is short of a use is kept.
        expect(noon.added > 0, CELL_HOURS .. " hours of noon sun added nothing")
        expectNear("Wh " .. CELL_HOURS .. " hours of noon sun put in the cells or kept", noon.added * useWh + noon.storedWh,
            Sun.wattsFrom(SolarCellCharger.WATTS, noon.flat, 0) * CELL_HOURS, 0.001)
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

-- Sets the mechanics window's Lua cheat (no key, hood or walk) for the test. Not the character's
-- cheat, which would skip the install's isValid, its check that the slot takes the battery.
local function mechanicsWindowCheat(self)
    local saved = ISVehicleMechanics.cheat
    T.defer(self, function() ISVehicleMechanics.cheat = saved end)
    ISVehicleMechanics.cheat = true
end

-- The mechanics menu of an empty battery slot installs a carried deep cycle battery, and doesn't
-- list one the character hasn't got. Uninstalling is vanilla's alone (ISUninstallVehiclePart takes
-- any item).
test("renewable_energy_gadgets_deep_cycle_battery_installs_from_mechanics_menu", {
    instant = true,
    run = function(self)
        T.setPerk(self, Perks.Mechanics, 10)
        if isClient() then
            T.setMechanicsCheat(self, true)
        end
        local car = T.placeVehicle(self, CAR)
        if not car then return end
        T.onVehicle(self, car, "vehicleBattery", { empty = true })
        T.waitFor(self, function() return T.vehicleBattery(car) == nil end, "this client's car without a battery")
        T.step(function()
            mechanicsWindowCheat(self)
            local context = T.partMenu(car.vehicle, VehicleBattery.partOf(car.vehicle))
            local install = T.subMenu(context, context:getOptionFromName(getText("IGUI_Install")))
            self.installWithout = install ~= nil
            self.listedWithout = install ~= nil and install:getOptionFromName(getItemName(VehicleBattery.ITEM)) ~= nil
            context:closeAll()
        end)
        T.give(self, "battery", { { type = VehicleBattery.ITEM } })
        T.step(function()
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
            T.shortenQueuedInstalls()
            T.waitFor(self, function() return T.vehicleBattery(car) ~= nil end, "this client's car with the deep cycle battery")
            T.onVehicle(self, car, "vehicleState", nil, "installed")
            T.count(self, "installed", { VehicleBattery.ITEM })
        end)
    end,
    validate = function(self)
        if not expect(self.installWithout, "the mechanics menu has no Install submenu without a deep cycle battery") then return end
        expect(not self.listedWithout, "Install lists the deep cycle battery while the character has none")
        if not expect(self.offered, "the mechanics menu doesn't offer the deep cycle battery under Install: "
            .. tostring(self.offerProblem)) then return end
        local installed = self.reads.installed.state.battery
        expectEqual("the server's battery slot's battery", installed and installed.type, VehicleBattery.ITEM)
        expectEqual("deep cycle batteries left in the inventory once installed", self.counts.installed[VehicleBattery.ITEM], 0)
    end,
})

-- What a car battery's charge over a deep cycle battery's comes to for the same watt-hours.
local function capacityRatio()
    return Specs.batteries[T.CAR_BATTERY].wh / Specs.batteries[VehicleBattery.ITEM].wh
end

-- Each of the mod's wraps of vanilla's battery drain and update (the handlers named), given the
-- same input, moves a car battery and a deep cycle battery by the same watt-hours, so the deep
-- cycle's share (the answer's `change`) moves less by the capacity ratio.
local BATTERY_ROWS = {
    -- A game minute an update, as the game updates parts (VehicleParts.updatePart), for an hour:
    -- the battery keeps whole uses and a minute's scaled drain is a few, so the scale holds over
    -- the hour only if what rounding leaves of each minute carries on. Vanilla drains the
    -- lightbar inside the battery update the mod scales for the alternator: scaled once.
    { what = "lightbar drain", handler = "lightbarDrain", uses = 0.8, minutes = 1, updates = 60, change = "drop" },
    { what = "alternator charge", handler = "alternatorCharge", uses = 0.2, minutes = 60, change = "gain" },
}
-- A charge an hour of the alternator fills, scaled or not: the wrap scales the minutes vanilla
-- charges for, before vanilla clamps the charge, not the gain after.
local NEAR_FULL = 0.99

-- The rows on one car with each battery, police cars for the lightbar.
local BATTERIES = { T.CAR_BATTERY, VehicleBattery.ITEM }
test("renewable_energy_gadgets_deep_cycle_battery_scales_vanilla_charge_and_drain", {
    run = function(self)
        local cars = {}
        for i, batteryType in ipairs(BATTERIES) do
            cars[i] = T.placeVehicle(self, "Base.CarLightsPolice", { battery = batteryType })
            if not cars[i] then return end
        end
        for _, row in ipairs(BATTERY_ROWS) do
            for i, batteryType in ipairs(BATTERIES) do
                T.onVehicle(self, cars[i], row.handler, { uses = row.uses, minutes = row.minutes, updates = row.updates },
                    row.what .. " " .. batteryType)
            end
        end
        T.onVehicle(self, cars[2], "alternatorCharge", { uses = NEAR_FULL, minutes = 60 }, "near full")
    end,
    validate = function(self)
        for _, row in ipairs(BATTERY_ROWS) do
            local car, deepCycle = self.reads[row.what .. " " .. T.CAR_BATTERY], self.reads[row.what .. " " .. VehicleBattery.ITEM]
            if expectEqual("the deep cycle car's battery in the " .. row.what, deepCycle.type, VehicleBattery.ITEM)
                and expect(car[row.change] > 0, "the " .. row.what .. " didn't move the car battery") then
                expectNear("deep cycle " .. row.change .. " over car battery " .. row.change .. " in the " .. row.what,
                    deepCycle[row.change] / car[row.change], capacityRatio(), 0.01)
            end
        end
        expectNear("the near-full deep cycle battery's charge after an hour of the alternator",
            NEAR_FULL + self.reads["near full"].gain, 1, 0.0001)
    end,
})
