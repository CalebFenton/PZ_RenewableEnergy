require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Gadgets/VehicleBattery"
require "RenewableEnergy/UI/VehicleMechanicsMenu"
require "RenewableEnergy/UI/Menu"
require "RenewableEnergy/UI/VehicleMenu"
require "Moveables/ISMoveableSpriteProps"
require "TimedActions/ISInventoryTransferAction"

-- Gadgets: the solar battery maintainer, the solar battery charger, the deep cycle vehicle battery
-- and the solar garden light (Gadgets/*, UI/VehicleMechanicsMenu.lua, the maintainer and garden light
-- options of UI/Menu.lua). The authority runs them, so the tests drive them through T.server and
-- check this client's copies.

local T = RenewableEnergyTest
local test, expect, expectNear = T.test, T.expect, T.expectNear
local Sprites, Specs, Sun = RenewableEnergy.Sprites, RenewableEnergy.Specs, RenewableEnergy.Sun
local SolarMaintainer, SolarCellCharger = RenewableEnergy.SolarMaintainer, RenewableEnergy.SolarCellCharger
local SolarGardenLight, VehicleBattery = RenewableEnergy.SolarGardenLight, RenewableEnergy.VehicleBattery

local NOON, MIDNIGHT = 12, 0
local CAR, CAR_BATTERY = "Base.CarNormal", "Base.CarBattery1"

local function outdoorSquare(self)
    return T.square(self, { bare = true }, "a free outdoor square")
end

-- The most a gadget rated `watts` can make in `hours`: full sun the whole time.
local function fullSunWh(watts, hours)
    return Sun.wattsFrom(watts, Sun.FULL_SUN, 0) * hours
end

-- Queues reading the server's copy of `car` (a handle) into self[key]: its battery, whether a
-- maintainer is attached and whether its engine runs.
local function carState(self, car, key)
    T.server(self, "carState", function() return T.vehicleArgs(car) end)
    T.step(function() self[key] = self.server.carState end)
end

-- Solar battery maintainer -----------------------------------------------------------------------

-- Queues the job of the maintainer option on `car`'s menu and a wait until this client's copy
-- shows it `attached` or not; self[key] is whether the menu offered it. Skips the option's walk,
-- which the debug car may not allow.
local function chooseMaintainerOption(self, car, attached, key)
    T.step(function()
        local context = T.newContext()
        local option = RenewableEnergy.VehicleMenu.addVehicleOptions(0, context, car.vehicle)
        context:hideAndChildren()
        self[key] = option ~= nil
        if not T.need(self, option, "the maintainer option on the car's menu") then return end
        ISTimedActionQueue.add(RenewableEnergyAction:new(T.player(), option.param1, nil, nil, option.param2, option.param3))
        T.waitFor(self, function() return SolarMaintainer.isAttached(car.vehicle) == attached end,
            "this client's car with the maintainer " .. (attached and "attached" or "detached"))
    end)
end

-- The menu attaches a carried maintainer to a car, on the server and this client, takes it from
-- the inventory, refuses a second one, and detaching gives it back.
test("renewable_energy_gadgets_maintainer_attach_detach", {
    instant = true,
    run = function(self)
        local car = T.placeVehicle(self, CAR, { battery = CAR_BATTERY, charge = 0.5 })
        if not car then return end
        self.car = car
        T.give(self, "maintainer", { { type = SolarMaintainer.ITEM } })
        chooseMaintainerOption(self, car, true, "attachOffered")
        carState(self, car, "attached")
        T.count(self, "attached", { SolarMaintainer.ITEM })
        T.step(function()
            self.copyAttached = SolarMaintainer.isAttached(car.vehicle)
            self.canAttachTwice = SolarMaintainer.canAttach(car.vehicle)
        end)
        chooseMaintainerOption(self, car, false, "detachOffered")
        carState(self, car, "detached")
        T.count(self, "detached", { SolarMaintainer.ITEM })
    end,
    validate = function(self)
        expect(self.attachOffered, "the car's menu offers no maintainer to attach")
        if not expect(self.attached and self.detached, "attaching and detaching never finished") then return end
        expect(self.attached.attached, "the maintainer did not attach on the server")
        expect(self.copyAttached, "this client's copy of the car doesn't show the maintainer attached")
        expect(self.counts.attached[SolarMaintainer.ITEM] == 0, "the attached maintainer is still in the inventory")
        expect(not self.canAttachTwice, "a second maintainer could attach")
        expect(self.detachOffered and not self.detached.attached, "the maintainer did not detach on the server")
        expect(not SolarMaintainer.isAttached(self.car.vehicle), "this client's copy of the car still shows the maintainer")
        expect(self.counts.detached[SolarMaintainer.ITEM] == 1, "detaching gave back "
            .. tostring(self.counts.detached[SolarMaintainer.ITEM]) .. " maintainers, expected 1")
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
        local car = T.placeVehicle(self, CAR, { battery = CAR_BATTERY })
        if not car then return end
        self.rows = {}
        -- Each hour's clock is set in its turn: single player sets it at once, when it is queued.
        local function hour(row)
            T.step(function() T.setTime(self, row.hour) end)
            T.server(self, "maintainerCharge", function() return { vehicle = T.vehicleArgs(car), hours = ROW_HOURS, uses = ROW_START } end)
            T.step(function() table.insert(self.rows, { row = row, reply = self.server.maintainerCharge }) end)
        end
        hour(WITHOUT_MAINTAINER)
        T.give(self, "maintainer", { { type = SolarMaintainer.ITEM } })
        T.step(function()
            ISTimedActionQueue.add(RenewableEnergyAction:new(T.player(), RenewableEnergyAction.ATTACH_MAINTAINER, nil, nil,
                car.vehicle, self.items.maintainer[1]))
        end)
        T.waitFor(self, function() return SolarMaintainer.isAttached(car.vehicle) end, "this client's car with the maintainer attached")
        for _, row in ipairs(WITH_MAINTAINER) do
            hour(row)
        end
        T.server(self, "chargeVehicles", function() return { vehicle = T.vehicleArgs(car), hours = ROW_HOURS } end)
    end,
    validate = function(self)
        if not expect(#self.rows == #WITH_MAINTAINER + 1 and self.server.chargeVehicles, "the hours on the car never all ran ("
            .. #self.rows .. " of " .. #WITH_MAINTAINER + 1 .. ")") then return end
        local charged
        for _, r in ipairs(self.rows) do
            local wh, after = r.reply.wh, r.reply.after
            if r.row.charges then
                charged = r.reply
                local most = fullSunWh(Specs.maintainerWatts, ROW_HOURS)
                expect(wh > 0 and wh <= most and after > ROW_START,
                    "an hour at " .. r.row.what .. " added " .. wh .. " Wh, expected more than 0 and at most " .. most)
            else
                expect(wh == 0 and math.abs(after - ROW_START) < 0.001, "an hour at " .. r.row.what .. " added " .. wh .. " Wh")
            end
        end
        -- The pass runs the maintainer for as long as the noon row, right after it, so it adds what
        -- that hour added; the light can still move a little between the two calls.
        local pass, capacityWh = self.server.chargeVehicles, charged.capacityWh
        expectNear("Wh the vehicle pass gave the maintained car", (pass.after - pass.before) * capacityWh, charged.wh, charged.wh / 50)
    end,
})

-- The maintainer option needs one carried, and detaching is refused where none is attached.
test("renewable_energy_gadgets_maintainer_menu_needs_carried_maintainer", {
    run = function(self)
        self.truck = T.placeVehicle(self, "Base.PickUpTruck")
        T.step(function()
            local context = T.newContext()
            self.offeredEmptyHanded = RenewableEnergy.VehicleMenu.addVehicleOptions(0, context, self.truck.vehicle) ~= nil
            context:hideAndChildren()
        end)
        T.give(self, "maintainer", { { type = SolarMaintainer.ITEM } })
    end,
    validate = function(self)
        local p, vehicle = T.player(), self.truck.vehicle
        local Action = RenewableEnergyAction
        expect(not self.offeredEmptyHanded, "a vehicle offers a maintainer to someone without one")
        local context = T.newContext()
        local option = RenewableEnergy.VehicleMenu.addVehicleOptions(0, context, vehicle)
        expect(option ~= nil and option.param1 == Action.ATTACH_MAINTAINER,
            "carrying a maintainer offers no Attach option on a vehicle")
        expect(not Action:new(p, Action.DETACH_MAINTAINER, nil, nil, vehicle):canPerform(),
            "a vehicle without a maintainer offers to detach one")
        context:hideAndChildren()
    end,
})

-- An older save marks an attached maintainer with the condition it went on with. Detaching one
-- still gives back a single whole maintainer, not one at that condition.
test("renewable_energy_gadgets_maintainer_detach_older_save_mark", {
    instant = true,
    run = function(self)
        local car = T.placeVehicle(self, CAR)
        if not car then return end
        T.server(self, "oldMaintainerMark", function() return { vehicle = T.vehicleArgs(car), condition = 1 } end)
        T.waitFor(self, function() return SolarMaintainer.isAttached(car.vehicle) end,
            "this client's car with the older save's maintainer mark")
        chooseMaintainerOption(self, car, false, "detachOffered")
        carState(self, car, "detached")
        T.count(self, "carried", { SolarMaintainer.ITEM })
        T.waitForCarried(self, SolarMaintainer.ITEM, "this client's copy of the detached maintainer")
        T.step(function()
            local item = T.carried(SolarMaintainer.ITEM)
            self.condition = item and item:getCondition()
        end)
    end,
    validate = function(self)
        expect(self.detachOffered, "the car's menu doesn't offer to detach an older save's maintainer")
        if not expect(self.detached, "detaching never finished") then return end
        expect(not self.detached.attached, "an older save's maintainer did not detach on the server")
        expect(self.counts.carried[SolarMaintainer.ITEM] == 1, "detaching gave back "
            .. tostring(self.counts.carried[SolarMaintainer.ITEM]) .. " maintainers, expected 1")
        local whole = instanceItem(SolarMaintainer.ITEM):getConditionMax()
        expect(self.condition == whole, "the detached maintainer came back at condition " .. tostring(self.condition)
            .. ", expected " .. whole)
    end,
})

-- Solar battery charger --------------------------------------------------------------------------

-- A solar battery charger the character places on a free outdoor square; see T.placeAsPlayer.
local function placeCharger(self)
    local square = outdoorSquare(self)
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
            self.acceptsCarBattery = container:isItemAllowed(instanceItem(CAR_BATTERY))
            for _, battery in ipairs(self.items.batteries) do
                ISTimedActionQueue.add(ISInventoryTransferAction:new(p, battery, p:getInventory(), container))
            end
            T.waitFor(self, function() return container:getItems():size() == SolarCellCharger.SLOTS end,
                "this client's charger holding " .. SolarCellCharger.SLOTS .. " batteries")
            T.server(self, "chargerState", { x = charger.x, y = charger.y, z = charger.z })
            T.step(function() self.acceptsPastSlots = container:isItemAllowed(instanceItem(SolarCellCharger.BATTERY)) end)
        end)
    end,
    validate = function(self)
        expect(self.acceptsBattery, "the solar battery charger refuses a battery")
        expect(not self.acceptsCarBattery, "the solar battery charger takes a car battery")
        if not expect(self.server.chargerState ~= nil, "the batteries never went into the charger") then return end
        expect(#self.server.chargerState.uses == SolarCellCharger.SLOTS, "the server's charger holds "
            .. #self.server.chargerState.uses .. " batteries, expected " .. SolarCellCharger.SLOTS)
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
        self.rows = {}
        for _, row in ipairs(CHARGER_ROWS) do
            local charger = placeCharger(self)
            if not charger then return end
            T.step(function() T.setTime(self, row.hour) end)
            T.server(self, "cellCharge", { x = charger.x, y = charger.y, z = charger.z,
                count = SolarCellCharger.SLOTS, uses = row.uses, hours = CELL_HOURS, pass = row.pass })
            T.step(function() self.rows[row.name] = self.server.cellCharge end)
        end
    end,
    validate = function(self)
        local noon, midnight, full = self.rows.noon, self.rows.midnight, self.rows.full
        if not expect(noon and midnight and full, "the chargers never all charged") then return end
        local useDelta = instanceItem(SolarCellCharger.BATTERY):getUseDelta()
        local useWh = useDelta * Specs.cellChargerBatteryWh
        local most = fullSunWh(Specs.cellChargerWatts, CELL_HOURS)
        expect(noon.added > 0 and noon.added * useWh <= most, CELL_HOURS .. " hours of noon sun added " .. noon.added
            .. " uses of " .. useWh .. " Wh, expected more than 0 and at most " .. most .. " Wh")
        local low, high = math.min(unpack(noon.after)), math.max(unpack(noon.after))
        expect(high - low <= useDelta + 1e-6, "the batteries charged unevenly, from " .. low .. " to " .. high)
        -- The pass gets the same sun for as long, plus what the first run kept toward a use.
        local passUses = 0
        for i, charge in ipairs(noon.afterPass) do
            passUses = passUses + (charge - noon.after[i]) / useDelta
        end
        expectNear("uses the charger pass as long again added", passUses, noon.added, 1.01)
        expect(midnight.added == 0 and math.max(unpack(midnight.after)) == 0, CELL_HOURS .. " hours of night charged "
            .. midnight.added .. " uses")
        expect(full.added == 0 and full.full == true and full.storedWh == 0, "full cells at noon took " .. tostring(full.added)
            .. " uses, are all full " .. tostring(full.full) .. ", and the charger kept " .. tostring(full.storedWh) .. " Wh")
    end,
})

-- Sets the mechanics window's Lua cheat (no key, hood or walk) for the test, not the character's
-- cheat, which would also make the install instant and skip its isValid.
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

-- The mechanics menu of an empty battery slot installs a carried deep cycle battery. A real-time
-- action: an instant one fails vanilla's isValid on a multiplayer client when the server's slot
-- change arrives. Uninstalling is vanilla's alone (ISUninstallVehiclePart takes any item).
test("renewable_energy_gadgets_deep_cycle_battery_installs_from_mechanics_menu", {
    run = function(self)
        T.setPerk(self, Perks.Mechanics, 10)
        local car = T.placeVehicle(self, CAR)
        if not car then return end
        T.server(self, "vehicleBattery", function() return { vehicle = T.vehicleArgs(car), empty = true } end)
        T.waitFor(self, function() return T.vehicleBattery(car) == nil end, "this client's car without a battery")
        T.give(self, "battery", { { type = VehicleBattery.ITEM } })
        T.step(function()
            mechanicsCheat(self)
            local context = partMenu(car.vehicle, VehicleBattery.partOf(car.vehicle))
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
            carState(self, car, "installed")
            T.count(self, "installed", { VehicleBattery.ITEM })
        end)
    end,
    validate = function(self)
        if not expect(self.offered, "the mechanics menu doesn't offer the deep cycle battery under Install: "
            .. tostring(self.offerProblem)) then return end
        if not expect(self.installed, "installing never finished") then return end
        local installed = self.installed.battery
        expect(installed and installed.type == VehicleBattery.ITEM, "the server's battery slot holds "
            .. tostring(installed and installed.type))
        expect(self.counts.installed[VehicleBattery.ITEM] == 0, "the installed battery is still in the inventory")
    end,
})

-- What a car battery's charge over a deep cycle battery's comes to for the same watt-hours.
local function capacityRatio()
    return Specs.batteries[CAR_BATTERY].wh / Specs.batteries[VehicleBattery.ITEM].wh
end

-- Queues the server handler `name` on a `script` vehicle each with a car battery and a deep cycle
-- battery, with `args` plus the vehicle's T.vehicleArgs, leaving the answers in self.answers in
-- that order.
local function onBothBatteries(self, script, name, args)
    self.answers = {}
    for _, batteryType in ipairs({ CAR_BATTERY, VehicleBattery.ITEM }) do
        local car = T.placeVehicle(self, script, { battery = batteryType })
        if not car then return end
        T.server(self, name, function()
            local withCar = { vehicle = T.vehicleArgs(car) }
            for key, value in pairs(args) do
                withCar[key] = value
            end
            return withCar
        end)
        T.step(function() table.insert(self.answers, self.server[name]) end)
    end
end

-- An hour of each vanilla vehicle update on a car battery and on a deep cycle battery moves the
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
}
for _, case in ipairs(VEHICLE_HOURS) do
    test("renewable_energy_gadgets_deep_cycle_battery_" .. case.behavior, {
        run = function(self)
            onBothBatteries(self, case.vehicle, case.handler, { uses = case.uses, minutes = case.minutes or 60 })
        end,
        validate = function(self)
            local car, deepCycle = self.answers[1], self.answers[2]
            if not expect(deepCycle and deepCycle.type == VehicleBattery.ITEM, "the second car holds "
                .. tostring(deepCycle and deepCycle.type)) then return end
            if expect(car[case.change] > 0, case.none) then
                expectNear("deep cycle " .. case.change .. " over car battery " .. case.change,
                    deepCycle[case.change] / car[case.change], capacityRatio(), 0.01)
            end
        end,
    })
end

-- Solar garden light -----------------------------------------------------------------------------

-- A garden light holding `charge` Wh and `bulb` (default: the plain bulb) that the character
-- places on a free outdoor square; see T.placeAsPlayer.
local function placeGardenLight(self, charge, bulb)
    local square = outdoorSquare(self)
    return square and T.placeAsPlayer(self, square, SolarGardenLight.ITEM, Sprites.gardenLight.off,
        { [SolarGardenLight.CHARGE_KEY] = charge, [SolarGardenLight.BULB_KEY] = bulb })
end

-- The lamp this client draws on `square`, or nil.
local function lampAt(square)
    return getCell():getLightSourceAt(square:getX(), square:getY(), square:getZ())
end

-- Whether this client draws a lamp on `square`.
local function lampOn(square)
    return lampAt(square) ~= nil
end

-- The colour the lamp shows: the native lighting doubles a lamp's colour and clips it at 1.
local function shownColour(lamp)
    return { r = math.min(1, lamp:getR() * 2), g = math.min(1, lamp:getG() * 2), b = math.min(1, lamp:getB() * 2) }
end

-- The colour of the bulb `fullType`, from its script.
local function bulbColour(fullType)
    local script = getScriptManager():FindItem(fullType)
    return { r = script:getColorRed(), g = script:getColorGreen(), b = script:getColorBlue() }
end

local function sameColour(a, b)
    return a ~= nil and b ~= nil and math.abs(a.r - b.r) < 0.01 and math.abs(a.g - b.g) < 0.01 and math.abs(a.b - b.b) < 0.01
end

local function describeColour(colour)
    return colour and string.format("(%.2f, %.2f, %.2f)", colour.r, colour.g, colour.b) or "none"
end

-- Whether this client draws a lamp on `square` that shines the colour of the bulb `fullType`.
local function lampShines(square, fullType)
    local lamp = lampAt(square)
    return lamp ~= nil and sameColour(shownColour(lamp), bulbColour(fullType))
end

-- Queues running the light on the server through the gadget pass for `hours` of the clock, from
-- `charge` Wh if given, and a wait until this client's tile and lamp match the server's answer.
local function runLight(self, light, charge, hours)
    T.server(self, "gardenLightUpdate", { x = light.x, y = light.y, z = light.z,
        charge = charge, hours = hours })
    T.waitFor(self, function()
        local reply = self.server.gardenLightUpdate
        return light.object:getTextureName() == reply.sprite and lampOn(light.square) == reply.lit
    end, "this client's garden light showing what the server's does")
end

-- The game minute on this client's clock.
local function gameMinute()
    return math.floor(getGameTime():getWorldAgeHours() * 60)
end

-- Queues moving the clock to the start of its minute, left in self.minute. A multiplayer client
-- redraws lamps every game minute, so a change within the minute came from the server's word.
local function startOfMinute(self)
    T.step(function()
        T.setTime(self, (math.floor(getGameTime():getTimeOfDay() * 60) + 0.05) / 60)
        T.step(function() self.minute = gameMinute() end)
    end)
end

-- At night a light stays lit while its battery holds any charge: a little more than the night
-- draws leaves it lit, exactly that much puts it out. By day the cell charges it, never past full.
local NIGHT_HOURS = 0.5
local NIGHT_WH = Specs.gardenLight.nightWatts * NIGHT_HOURS
-- A full battery: lasts the night hours the tests run.
local LIT_WH = Specs.gardenLight.wh
local GARDEN_LIGHT_HOURS = {
    { what = "with a little more than the night draws", hour = MIDNIGHT, charge = NIGHT_WH + 0.01, hours = NIGHT_HOURS,
        lit = true, after = 0.01 },
    { what = "with just what the night draws", hour = MIDNIGHT, charge = NIGHT_WH, hours = NIGHT_HOURS, lit = false, after = 0 },
    { what = "empty at noon", hour = NOON, charge = 0, hours = 1, lit = false, low = 0, high = Specs.gardenLight.wh },
    { what = "nearly full at noon", hour = NOON, charge = Specs.gardenLight.wh - 0.01, hours = 1, lit = false,
        after = Specs.gardenLight.wh },
}

test("renewable_energy_gadgets_garden_light_update", {
    instant = true,
    run = function(self)
        self.rows = {}
        local light = placeGardenLight(self, GARDEN_LIGHT_HOURS[1].charge)
        if not light then return end
        for _, row in ipairs(GARDEN_LIGHT_HOURS) do
            T.step(function() T.setTime(self, row.hour) end)
            runLight(self, light, row.charge, row.hours)
            T.step(function()
                local reply = self.server.gardenLightUpdate
                table.insert(self.rows, { row = row, lit = reply.lit, sprite = reply.sprite, charge = reply.charge,
                    copySprite = light.object:getTextureName(), lamp = lampOn(light.square) })
            end)
        end
    end,
    validate = function(self)
        for _, r in ipairs(self.rows) do
            local row = r.row
            local sprite = row.lit and Sprites.gardenLight.lit or Sprites.gardenLight.off
            expect(r.lit == row.lit and r.sprite == sprite and r.copySprite == sprite and r.lamp == row.lit,
                string.format("a light %s: lit %s, sprite %s, this client's sprite %s, lamp %s; expected lit %s", row.what,
                    tostring(r.lit), r.sprite, r.copySprite, tostring(r.lamp), tostring(row.lit)))
            if row.after then
                expectNear("charge of a light " .. row.what, r.charge, row.after)
            else
                expect(r.charge > row.low and r.charge <= row.high, "a light " .. row.what .. " ended at " .. r.charge .. " Wh")
            end
        end
    end,
})

-- Picking up a lit light takes its lamp away with it.
test("renewable_energy_gadgets_garden_light_pick_up_takes_light", {
    hour = MIDNIGHT,
    instant = true,
    run = function(self)
        local light = placeGardenLight(self, LIT_WH)
        if not light then return end
        self.light = light
        runLight(self, light, LIT_WH, NIGHT_HOURS)
        T.step(function()
            self.lamp = lampOn(light.square)
            if not self.lamp then return end
            T.pickUpAsPlayer(self, light, Sprites.gardenLight.lit)
            T.waitFor(self, function() return not lampOn(light.square) end, "this client's lamp going with the light")
        end)
    end,
    validate = function(self)
        if not expect(self.lamp, "the light never lit") then return end
        expect(T.objectWithSprite(self.light.square, Sprites.gardenLight.lit) == nil, "the lit garden light is still there")
        expect(not lampOn(self.light.square), "the light still shines where the garden light was")
    end,
})

-- Light bulbs ------------------------------------------------------------------------------------

local RED, GREEN = "Base.LightBulbRed", "Base.LightBulbGreen"

-- This client's right-click menu of the garden light `light` (a handle): the context menu, to hide
-- once read, its Add Light Bulb submenu or nil, and its Remove Light Bulb option or nil.
local function bulbMenu(light)
    local context = T.newContext()
    local menu = RenewableEnergy.Menu.addGardenLightOptions(0, context, light.object)
    return context, T.subMenu(context, menu:getOptionFromName(getText("ContextMenu_AddLightbulb"))),
        menu:getOptionFromName(getText("ContextMenu_RemoveLightbulb"))
end

-- Queues choosing, in this client's right-click menu of the garden light `light` (a handle),
-- Remove Light Bulb or, given `bulbType`, that bulb under Add Light Bulb, as a click does: the
-- option walks the character over and queues the job. Leaves whether the menu offered it in
-- self[key].
local function chooseBulbOption(self, light, bulbType, key)
    T.step(function()
        local context, add, remove = bulbMenu(light)
        local option = remove
        if bulbType then
            option = add and add:getOptionFromName(getItemName(bulbType))
        end
        context:hideAndChildren()
        self[key] = option ~= nil and not option.notAvailable
        if not T.need(self, self[key], "the garden light's " .. (bulbType and "Add Light Bulb " .. bulbType or "Remove Light Bulb") .. " option") then
            return
        end
        T.standNextTo(light.square)
        T.choose(option)
    end)
end

-- Queues a wait until this client's copy of the light shows the unlit tile and draws no lamp.
local function waitForDark(self, light)
    T.waitFor(self, function()
        return light.object:getTextureName() == Sprites.gardenLight.off and not lampOn(light.square)
    end, "this client's garden light dark")
end

-- Taking the bulb out of a lit light puts its lamp out within the minute and gives the bulb back;
-- the light then stays dark at night without draining, and offers to take a bulb.
test("renewable_energy_gadgets_garden_light_remove_bulb", {
    hour = MIDNIGHT,
    instant = true,
    run = function(self)
        local light = placeGardenLight(self, LIT_WH)
        if not light then return end
        self.light = light
        runLight(self, light, LIT_WH, NIGHT_HOURS)
        T.step(function() self.litBefore = lampOn(light.square) end)
        startOfMinute(self)
        chooseBulbOption(self, light, nil, "removeOffered")
        waitForDark(self, light)
        T.step(function() self.darkMinute = gameMinute() end)
        T.count(self, "removed", { SolarGardenLight.PLAIN_BULB })
        runLight(self, light, LIT_WH, 1)
        T.step(function()
            self.night = self.server.gardenLightUpdate
            self.copyDarkAtNight = light.object:getTextureName() == Sprites.gardenLight.off and not lampOn(light.square)
        end)
    end,
    validate = function(self)
        if not expect(self.litBefore, "the light never lit") then return end
        expect(self.removeOffered, "the lit light's menu doesn't offer Remove Light Bulb")
        expect(self.darkMinute == self.minute, "this client's lamp went out only at a later game minute")
        expect(self.counts.removed[SolarGardenLight.PLAIN_BULB] == 1, "taking the bulb out gave "
            .. tostring(self.counts.removed[SolarGardenLight.PLAIN_BULB]) .. " light bulbs, expected 1")
        expect(self.night and not self.night.lit and self.copyDarkAtNight, "the light without a bulb lit at night")
        expectNear("charge of a light without a bulb after an hour of night", self.night and self.night.charge, LIT_WH)
        local context, add, remove = bulbMenu(self.light)
        local plain = add and add:getOptionFromName(getItemName(SolarGardenLight.PLAIN_BULB))
        expect(plain ~= nil and not plain.notAvailable, "the light without a bulb doesn't offer the carried bulb under Add Light Bulb")
        expect(remove == nil, "the light without a bulb offers Remove Light Bulb")
        context:hideAndChildren()
    end,
})

-- The plain bulb shines warm, and swapping it for a red one through the menu takes the red bulb
-- and shines red.
test("renewable_energy_gadgets_garden_light_coloured_bulb", {
    hour = MIDNIGHT,
    instant = true,
    run = function(self)
        local light = placeGardenLight(self, LIT_WH)
        if not light then return end
        runLight(self, light, LIT_WH, NIGHT_HOURS)
        T.step(function()
            local lamp = lampAt(light.square)
            self.plain = lamp and shownColour(lamp)
        end)
        chooseBulbOption(self, light, nil, "removeOffered")
        waitForDark(self, light)
        T.give(self, "red", { { type = RED } })
        chooseBulbOption(self, light, RED, "addOffered")
        T.waitFor(self, function() return lampShines(light.square, RED) end, "this client's lamp shining red")
        T.count(self, "added", { RED })
        T.step(function() self.copyLit = light.object:getTextureName() == Sprites.gardenLight.lit end)
    end,
    validate = function(self)
        local plain = self.plain
        if not expect(plain ~= nil, "the light never lit with its plain bulb") then return end
        expect(plain.b < plain.r and not sameColour(plain, { r = 1, g = 1, b = 1 }),
            "the plain bulb's lamp shines " .. describeColour(plain) .. ", not a warm white")
        expect(self.addOffered, "the light without a bulb doesn't offer the carried red bulb")
        expect(self.copyLit, "with a red bulb this client's light shows the unlit tile")
        expect(self.counts.added[RED] == 0, "the red bulb is still in the inventory")
    end,
})

-- A bulb swapped while the light stays lit still recolours this client's lamp.
test("renewable_energy_gadgets_garden_light_bulb_swap_recolours_lamp", {
    hour = MIDNIGHT,
    instant = true,
    run = function(self)
        local light = placeGardenLight(self, LIT_WH)
        if not light then return end
        runLight(self, light, LIT_WH, NIGHT_HOURS)
        T.step(function() self.litBefore = lampOn(light.square) end)
        T.server(self, "gardenLightSwapBulb", { x = light.x, y = light.y, z = light.z, bulb = GREEN })
        T.waitFor(self, function() return lampShines(light.square, GREEN) end, "this client's lamp shining green after the swap")
    end,
    validate = function(self)
        if not expect(self.litBefore, "the light never lit") then return end
        local swap = self.server.gardenLightSwapBulb
        expect(swap.lit and swap.bulb == GREEN, "after the swap the server's light is lit " .. tostring(swap.lit)
            .. " with " .. tostring(swap.bulb))
    end,
})

-- Queues placing the carried garden light back on `light`'s square with the moveables action and
-- a wait until this client has it.
local function placeCarriedLight(self, light)
    T.step(function()
        local p = T.player()
        local item = T.need(self, T.carried(SolarGardenLight.ITEM), "the carried garden light")
        if not item then return end
        -- The tile it was picked up as, lit or not, as the moveables cursor places it.
        local sprite = item:getWorldSprite()
        local here = p:getCurrentSquare()
        PZHarness.Fixtures.teleportToMiddle(p, here:getX(), here:getY(), here:getZ())
        local props = ISMoveableSpriteProps.new(sprite)
        if not T.need(self, props:walkToAndEquip(p, light.square, "place", sprite), "a way to place the carried garden light") then
            return
        end
        ISTimedActionQueue.add(ISMoveablesAction:new(p, light.square, "place", sprite, nil,
            props:getFaceDirectionFromSpriteName(sprite), item, nil))
        T.waitFor(self, function() return T.objectWithSprite(light.square, sprite) ~= nil end,
            "this client's copy of the placed garden light")
        T.server(self, "PZHarness.trackPlaced", { x = light.x, y = light.y, z = light.z, sprite = sprite })
        T.step(function() light.object = T.objectWithSprite(light.square, sprite) end)
    end)
end

-- A picked-up light keeps its bulb and shines its colour when placed again.
test("renewable_energy_gadgets_garden_light_pick_up_keeps_bulb", {
    hour = MIDNIGHT,
    instant = true,
    run = function(self)
        local light = placeGardenLight(self, LIT_WH, GREEN)
        if not light then return end
        runLight(self, light, LIT_WH, NIGHT_HOURS)
        T.waitFor(self, function() return lampShines(light.square, GREEN) end, "this client's lamp shining green")
        T.pickUpAsPlayer(self, light, Sprites.gardenLight.lit)
        T.readCarried(self, { SolarGardenLight.ITEM })
        T.step(function()
            local item = T.carriedFirst(self, SolarGardenLight.ITEM)
            self.carriedBulb = item and item.modData[SolarGardenLight.BULB_KEY]
        end)
        placeCarriedLight(self, light)
        runLight(self, light, nil, NIGHT_HOURS)
        T.waitFor(self, function() return lampShines(light.square, GREEN) end, "this client's lamp shining green placed again")
    end,
    validate = function(self)
        expect(self.carriedBulb == GREEN, "the picked-up light holds " .. tostring(self.carriedBulb) .. ", expected " .. GREEN)
    end,
})

-- Taking a light apart gives back its bulb, whatever its colour, the plain one a light holds from
-- new (no bulb key), and none from a light without one.
for _, entry in ipairs({ { "returns_bulb", RED }, { "returns_plain_bulb", nil }, { "without_bulb", SolarGardenLight.NO_BULB } }) do
    local behavior, bulb = entry[1], entry[2]
    T.craftTest("renewable_energy_gadgets_garden_light_take_apart_" .. behavior, {
        recipe = "RenewableEnergy_TakeApartSolarGardenLight",
        from = SolarGardenLight.ITEM,
        setup = function(self)
            for _, item in ipairs(bulb and self.items.inputs or {}) do
                if item:getFullType() == SolarGardenLight.ITEM then
                    T.changeItem(self, item, { modData = { [SolarGardenLight.BULB_KEY] = bulb } })
                end
            end
        end,
        counts = { [SolarGardenLight.ITEM] = 0, [RED] = bulb == RED and 1 or 0,
            [SolarGardenLight.PLAIN_BULB] = bulb == nil and 1 or 0 },
    })
end

-- A garden light goes on the ground outdoors, where the sun reaches it.
test("renewable_energy_gadgets_garden_light_refused_indoors", {
    run = function(self)
        local indoor = T.square(self, { indoors = true }, "a free indoor square")
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
