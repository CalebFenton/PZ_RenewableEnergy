require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/VehicleBattery"
require "RenewableEnergy/UI/VehicleBatteryMenu"
-- RenewableEnergy.GadgetCharging is server Lua, which single player loads only once a game
-- starts, so it is looked up when a test runs rather than required here.
require "Moveables/ISMoveableSpriteProps"
require "Moveables/ISMoveableDefinitions"

-- Gadget tests: the maintainer, the cell charger, the deep cycle battery in a vehicle, the
-- garden light, and picking placed objects back up. See RenewableEnergyTestLib.lua for how the
-- runner works.

local test = RenewableEnergyTest.test
local expect, player = RenewableEnergyTest.expect, RenewableEnergyTest.player
local Sprites = RenewableEnergy.Sprites
local SolarMaintainer, SolarCellCharger = RenewableEnergy.SolarMaintainer, RenewableEnergy.SolarCellCharger
local SolarGardenLight = RenewableEnergy.SolarGardenLight

local NOON, MIDNIGHT = 12, 0

-- A free outdoor square holding only its floor, `distance` or more tiles from the player.
local function outdoorSquare(distance)
    local here = player():getCurrentSquare()
    if not here then return nil end
    for radius = distance, distance + 8 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local square = getCell():getGridSquare(here:getX() + dx, here:getY() + dy, here:getZ())
                if square and square:isOutside() and square:isFree(false) and square:getObjects():size() == 1
                    and not square:getVehicleContainer() then
                    return square
                end
            end
        end
    end
    return nil
end

local function setTime(self, hour)
    self.savedTime = self.savedTime or getGameTime():getTimeOfDay()
    getGameTime():setTimeOfDay(hour)
end

local function restoreTime(self)
    if self.savedTime then
        getGameTime():setTimeOfDay(self.savedTime)
    end
end

-- Solar Battery Maintainer ----------------------------------------------------------------------

-- An outdoor car with a half charged battery.
local function spawnCar(self)
    local square = outdoorSquare(6)
    local vehicle = square and addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, square)
    local part = vehicle and vehicle:getPartById("Battery")
    if not part then return nil end
    if not part:getInventoryItem() then
        part:setInventoryItem(instanceItem("Base.CarBattery1"))
    end
    part:getInventoryItem():setCurrentUsesFloat(0.5)
    self.vehicle = vehicle
    return vehicle, part:getInventoryItem()
end

local function removeCar(self)
    if self.vehicle then
        self.vehicle:permanentlyRemove()
        self.vehicle = nil
    end
end

local function attachMaintainer(vehicle)
    local item = player():getInventory():AddItem(SolarMaintainer.ITEM)
    return SolarMaintainer.attach(player(), vehicle, item)
end

test("renewable_energy_gadgets_maintainer_attach_detach", {
    run = function(self)
        local vehicle = spawnCar(self)
        if not vehicle then return end
        self.canAttach = SolarMaintainer.canAttach(vehicle)
        self.attached = attachMaintainer(vehicle)
        self.isAttached = SolarMaintainer.isAttached(vehicle)
        self.itemsWhileAttached = player():getInventory():getCountTypeRecurse(SolarMaintainer.ITEM)
        self.canAttachTwice = SolarMaintainer.canAttach(vehicle)
        self.detached = SolarMaintainer.detach(player(), vehicle)
        self.isAttachedAfter = SolarMaintainer.isAttached(vehicle)
        self.itemsAfter = player():getInventory():getCountTypeRecurse(SolarMaintainer.ITEM)
    end,
    validate = function(self)
        if not expect(self.canAttach ~= nil, "no car with a battery part spawned") then return end
        expect(self.canAttach and self.attached and self.isAttached, "the maintainer did not attach")
        expect(self.itemsWhileAttached == 0, "the attached maintainer is still in the inventory")
        expect(not self.canAttachTwice, "a second maintainer could attach")
        expect(self.detached and not self.isAttachedAfter, "the maintainer did not detach")
        expect(self.itemsAfter == 1, "detaching gave back " .. tostring(self.itemsAfter) .. " maintainers, expected 1")
    end,
    cleanup = removeCar,
})

-- Charges in the noon sun, and through the pass that finds every loaded vehicle. A new vehicle
-- joins the cell's vehicle set on the next cell update (IsoCell.addVehicles), so the pass runs
-- in validate, a frame later.
test("renewable_energy_gadgets_maintainer_charges_in_sun", {
    run = function(self)
        local vehicle, battery = spawnCar(self)
        if not vehicle then return end
        attachMaintainer(vehicle)
        setTime(self, NOON)
        self.battery = battery
        self.wh = SolarMaintainer.charge(vehicle, 1)
        self.afterCharge = battery:getCurrentUsesFloat()
    end,
    validate = function(self)
        if not expect(self.wh ~= nil, "no car with a battery part spawned") then return end
        expect(self.wh > 0 and self.afterCharge > 0.5, "an hour of noon sun added " .. self.wh .. " Wh")
        if expect(RenewableEnergy.GadgetCharging ~= nil, "the gadget charging pass is not loaded") then
            RenewableEnergy.GadgetCharging.chargeVehicles(1)
            expect(self.battery:getCurrentUsesFloat() > self.afterCharge, "the vehicle pass did not charge the maintained car")
        end
    end,
    cleanup = function(self)
        restoreTime(self)
        removeCar(self)
    end,
})

test("renewable_energy_gadgets_maintainer_idle_at_night", {
    run = function(self)
        local vehicle, battery = spawnCar(self)
        if not vehicle then return end
        attachMaintainer(vehicle)
        setTime(self, MIDNIGHT)
        self.wh = SolarMaintainer.charge(vehicle, 1)
        self.after = battery:getCurrentUsesFloat()
    end,
    validate = function(self)
        if not expect(self.wh ~= nil, "no car with a battery part spawned") then return end
        expect(self.wh == 0 and math.abs(self.after - 0.5) < 0.001, "an hour of night added " .. self.wh .. " Wh")
    end,
    cleanup = function(self)
        restoreTime(self)
        removeCar(self)
    end,
})

-- No maintainer, no charge.
test("renewable_energy_gadgets_no_maintainer_no_charge", {
    run = function(self)
        local vehicle = spawnCar(self)
        if not vehicle then return end
        setTime(self, NOON)
        self.wh = SolarMaintainer.charge(vehicle, 1)
    end,
    validate = function(self)
        expect(self.wh == 0, "a car without a maintainer charged " .. tostring(self.wh) .. " Wh")
    end,
    cleanup = function(self)
        restoreTime(self)
        removeCar(self)
    end,
})

-- Solar Battery Charger -------------------------------------------------------------------------

-- Places a new `itemType` the way the moveables cursor does, with `modData` on the item first.
local function placeObject(square, itemType, spriteName, modData)
    local item = instanceItem(itemType)
    for key, value in pairs(modData or {}) do
        item:getModData()[key] = value
    end
    player():getInventory():AddItem(item)
    ISMoveableSpriteProps.new(spriteName):placeMoveable(player(), square, item:getWorldSprite(), true)
end

local objectWithSprite = RenewableEnergyTest.objectWithSprite

local function placeCharger(self)
    self.square = outdoorSquare(2)
    if not self.square then return nil end
    placeObject(self.square, "RenewableEnergy.SolarCellCharger", Sprites.cellCharger)
    return SolarCellCharger.findOn(self.square)
end

local function pickUpCharger(self)
    local charger = self.square and SolarCellCharger.findOn(self.square)
    if charger then
        charger:getContainer():removeAllItems()
        ISMoveableSpriteProps.new(Sprites.cellCharger):pickUpMoveable(player(), self.square, false, true)
    end
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

-- The placed charger takes four vanilla batteries and nothing else.
test("renewable_energy_gadgets_cell_charger_container", {
    run = function(self)
        local charger = placeCharger(self)
        local container = charger and charger:getContainer()
        if not container then return end
        self.acceptsBattery = container:isItemAllowed(instanceItem("Base.Battery"))
        self.acceptsCarBattery = container:isItemAllowed(instanceItem("Base.CarBattery1"))
        loadBatteries(container, SolarCellCharger.SLOTS)
        self.acceptsFifth = container:isItemAllowed(instanceItem("Base.Battery"))
    end,
    validate = function(self)
        if not expect(self.acceptsBattery ~= nil, "no cell charger with a container was placed") then return end
        expect(self.acceptsBattery, "the charger refuses a battery")
        expect(not self.acceptsCarBattery, "the charger takes a car battery")
        expect(not self.acceptsFifth, "the charger takes a fifth battery")
    end,
    cleanup = pickUpCharger,
})

test("renewable_energy_gadgets_cell_charger_charges_in_sun", {
    run = function(self)
        local charger = placeCharger(self)
        if not (charger and charger:getContainer()) then return end
        local batteries = loadBatteries(charger:getContainer(), SolarCellCharger.SLOTS)
        setTime(self, NOON)
        self.added = SolarCellCharger.charge(charger, 2)
        self.afterCharge = charges(batteries)
        SolarCellCharger.chargeAll(2)
        self.afterPass = charges(batteries)
    end,
    validate = function(self)
        if not expect(self.added ~= nil, "no cell charger with a container was placed") then return end
        expect(self.added > 0, "two hours of noon sun charged nothing")
        local low, high = math.min(unpack(self.afterCharge)), math.max(unpack(self.afterCharge))
        expect(high - low <= 0.01, "the batteries charged unevenly, from " .. low .. " to " .. high)
        expect(self.afterPass[1] > self.afterCharge[1] or self.afterPass[4] > self.afterCharge[4],
            "the charger pass did not charge the placed charger")
        -- A set fills in one to two sunny days; two noon hours are well short of that.
        expect(high < 0.5, "two hours of sun filled the batteries to " .. high)
    end,
    cleanup = function(self)
        restoreTime(self)
        pickUpCharger(self)
    end,
})

test("renewable_energy_gadgets_cell_charger_idle_at_night", {
    run = function(self)
        local charger = placeCharger(self)
        if not (charger and charger:getContainer()) then return end
        local batteries = loadBatteries(charger:getContainer(), 2)
        setTime(self, MIDNIGHT)
        self.added = SolarCellCharger.charge(charger, 2)
        self.after = charges(batteries)
    end,
    validate = function(self)
        if not expect(self.added ~= nil, "no cell charger with a container was placed") then return end
        expect(self.added == 0 and self.after[1] == 0, "two hours of night charged " .. self.added .. " uses")
    end,
    cleanup = function(self)
        restoreTime(self)
        pickUpCharger(self)
    end,
})

-- Deep cycle battery in a vehicle --------------------------------------------------------------
-- Vanilla's vehicle charge and drain (server/Vehicles/Vehicles.lua) are server Lua, which single
-- player loads once a game starts, so tests reach them when they run.

local VehicleBattery = RenewableEnergy.VehicleBattery
local CAR_BATTERY = "Base.CarBattery1"

-- An outdoor car `distance` or more tiles away whose battery slot holds a `batteryType` at
-- `charge`, or is empty for a nil type. Added to self.vehicles for removeCars.
local function spawnCarWith(self, distance, batteryType, charge)
    local square = outdoorSquare(distance)
    local vehicle = square and addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, square)
    local part = vehicle and vehicle:getPartById(VehicleBattery.PART)
    if not part then return nil end
    self.vehicles = self.vehicles or {}
    table.insert(self.vehicles, vehicle)
    local battery = batteryType and instanceItem(batteryType)
    if battery then
        battery:setCurrentUsesFloat(charge)
    end
    part:setInventoryItem(battery)
    return vehicle, part, battery
end

local function removeCars(self)
    for _, vehicle in ipairs(self.vehicles or {}) do
        vehicle:shutOff()
        vehicle:permanentlyRemove()
    end
    self.vehicles = nil
end

-- Works on vehicles as ISVehicleMechanics.cheat does, so that installing needs no key, hood or
-- walk, which the debug car may not allow.
local function mechanicsCheat(self, on)
    if on then
        self.savedCheat = ISVehicleMechanics.cheat
        ISVehicleMechanics.cheat = true
    else
        ISVehicleMechanics.cheat = self.savedCheat
    end
end

-- The mechanics window's menu for `part`, built by its own doPartContextMenu on a window that
-- has just what that function reads.
local function partMenu(vehicle, part)
    local window = setmetatable({ chr = player(), playerNum = 0, vehicle = vehicle }, { __index = ISVehicleMechanics })
    window.getAbsoluteX = function() return 0 end
    window.getAbsoluteY = function() return 0 end
    window:doPartContextMenu(part, 0, 0)
    return window.context
end

local function subMenuOf(context, option)
    return option and option.subOption and context:getSubMenu(option.subOption)
end

-- The mechanics menu of an empty battery slot offers the deep cycle battery the player carries,
-- and picking it installs it with vanilla's action.
test("renewable_energy_gadgets_deep_cycle_installs_in_vehicle", {
    run = function(self)
        local vehicle, part = spawnCarWith(self, 6, nil)
        if not vehicle then return end
        self.part = part
        mechanicsCheat(self, true)
        player():getInventory():AddItem(VehicleBattery.ITEM)
        local context = partMenu(vehicle, part)
        self.context = context
        local install = subMenuOf(context, context:getOptionFromName(getText("IGUI_Install")))
        local deepCycle = subMenuOf(context, install and install:getOptionFromName(getItemName(VehicleBattery.ITEM)))
        local pick = deepCycle and deepCycle.options[1]
        self.offered = pick ~= nil
        if pick then
            pick.onSelect(pick.target, pick.param1, pick.param2)
        end
    end,
    validate = function(self)
        if not expect(self.part ~= nil, "no car with a battery slot spawned") then return end
        expect(self.offered, "the mechanics menu doesn't offer the deep cycle battery under Install")
        local installed = self.part:getInventoryItem()
        expect(installed and installed:getFullType() == VehicleBattery.ITEM,
            "the battery slot holds " .. tostring(installed and installed:getFullType()))
        expect(player():getInventory():getCountTypeRecurse(VehicleBattery.ITEM) == 0, "the installed battery is still in the inventory")
    end,
    cleanup = function(self)
        if self.context then
            self.context:closeAll()
        end
        mechanicsCheat(self, false)
        removeCars(self)
    end,
})

test("renewable_energy_gadgets_deep_cycle_uninstalls_from_vehicle", {
    run = function(self)
        local vehicle, part = spawnCarWith(self, 6, VehicleBattery.ITEM, 0.5)
        if not vehicle then return end
        self.part = part
        mechanicsCheat(self, true)
        ISVehiclePartMenu.onUninstallPart(player(), part)
    end,
    validate = function(self)
        if not expect(self.part ~= nil, "no car with a battery slot spawned") then return end
        expect(self.part:getInventoryItem() == nil, "the battery slot still holds a battery")
        local battery = player():getInventory():getFirstTypeRecurse(VehicleBattery.ITEM)
        expect(battery ~= nil and math.abs(battery:getCurrentUsesFloat() - 0.5) < 0.001,
            "the deep cycle battery came back at " .. tostring(battery and battery:getCurrentUsesFloat()))
    end,
    cleanup = function(self)
        mechanicsCheat(self, false)
        removeCars(self)
    end,
})

-- Fraction of a full charge vanilla's headlight update takes from each car's battery in an hour
-- with the engine off. Both cars run the same light, and the deep cycle battery loses less of its
-- charge by its capacity over a car battery's.
test("renewable_energy_gadgets_deep_cycle_drains_slower", {
    run = function(self)
        self.car = { spawnCarWith(self, 6, CAR_BATTERY, 0.8) }
        self.deep = { spawnCarWith(self, 12, VehicleBattery.ITEM, 0.8) }
    end,
    validate = function(self)
        if not expect(self.car[3] ~= nil and self.deep[3] ~= nil, "the two cars didn't spawn") then return end
        local drops = {}
        for _, car in ipairs({ self.car, self.deep }) do
            local vehicle, battery = car[1], car[3]
            local headlight = vehicle:getPartById("HeadlightLeft")
            if not expect(headlight ~= nil and headlight:getInventoryItem() ~= nil, "the car has no left headlight") then return end
            vehicle:setHeadlightsOn(true)
            Vehicles.Update.Headlight(vehicle, headlight, 60)
            vehicle:setHeadlightsOn(false)
            table.insert(drops, 0.8 - battery:getCurrentUsesFloat())
        end
        local carDrop, deepDrop = drops[1], drops[2]
        print(string.format("RETest NOTE renewable_energy_gadgets_deep_cycle_drains_slower: an hour of one headlight takes %.5f of a car battery, %.5f of a deep cycle battery", carDrop, deepDrop))
        if expect(carDrop > 0, "the headlight didn't drain the car battery") then
            RenewableEnergyTest.expectNear("deep cycle drain over car battery drain", deepDrop / carDrop,
                RenewableEnergy.Specs.batteries[CAR_BATTERY].wh / RenewableEnergy.Specs.batteries[VehicleBattery.ITEM].wh, 0.01)
        end
    end,
    cleanup = removeCars,
})

-- Stands still for a moment, so the cars have their physics before their engines start.
local Settle = ISBaseTimedAction:derive("RenewableEnergyTestGadgetSettle")

function Settle:new(character)
    local o = ISBaseTimedAction.new(self, character)
    o.maxTime = 60
    return o
end

function Settle:isValid()
    return true
end

-- A running engine charges both batteries by the same watt-hours, so the bigger one gains less
-- of its charge; a solar maintainer charges it too.
test("renewable_energy_gadgets_deep_cycle_charges_from_vehicle", {
    run = function(self)
        self.car = { spawnCarWith(self, 6, CAR_BATTERY, 0.2) }
        self.deep = { spawnCarWith(self, 12, VehicleBattery.ITEM, 0.2) }
        ISTimedActionQueue.add(Settle:new(player()))
    end,
    validate = function(self)
        if not expect(self.car[3] ~= nil and self.deep[3] ~= nil, "the two cars didn't spawn") then return end
        local gains = {}
        for _, car in ipairs({ self.car, self.deep }) do
            local vehicle, part, battery = car[1], car[2], car[3]
            vehicle:engineDoRunning()
            if not vehicle:isEngineRunning() then
                print("RETest NOTE renewable_energy_gadgets_deep_cycle_charges_from_vehicle: the debug car's engine wouldn't run")
                break
            end
            Vehicles.Update.Battery(vehicle, part, 60)
            vehicle:shutOff()
            table.insert(gains, battery:getCurrentUsesFloat() - 0.2)
        end
        if #gains == 2 and expect(gains[1] > 0, "the alternator didn't charge the car battery") then
            RenewableEnergyTest.expectNear("deep cycle gain over car battery gain", gains[2] / gains[1],
                RenewableEnergy.Specs.batteries[CAR_BATTERY].wh / RenewableEnergy.Specs.batteries[VehicleBattery.ITEM].wh, 0.01)
        end

        local vehicle, battery = self.deep[1], self.deep[3]
        local item = player():getInventory():AddItem(SolarMaintainer.ITEM)
        SolarMaintainer.attach(player(), vehicle, item)
        setTime(self, NOON)
        local before = battery:getCurrentUsesFloat()
        local wh = SolarMaintainer.charge(vehicle, 1)
        expect(wh > 0, "the maintainer added no charge to the deep cycle battery at noon")
        RenewableEnergyTest.expectNear("maintainer Wh in the deep cycle battery",
            (battery:getCurrentUsesFloat() - before) * RenewableEnergy.Battery.nominalWh(battery), wh, 0.01)
    end,
    cleanup = function(self)
        restoreTime(self)
        removeCars(self)
    end,
})

-- Solar Garden Light ----------------------------------------------------------------------------

local function placeGardenLight(self, charge)
    self.square = outdoorSquare(2)
    if not self.square then return nil end
    placeObject(self.square, SolarGardenLight.ITEM, Sprites.gardenLight.off, { [SolarGardenLight.CHARGE_KEY] = charge })
    return SolarGardenLight.findOn(self.square)
end

local function pickUpGardenLight(self)
    local light = self.square and SolarGardenLight.findOn(self.square)
    if light then
        ISMoveableSpriteProps.new(light:getTextureName()):pickUpMoveable(player(), self.square, false, true)
    end
end

local function lampOn(square)
    return getCell():getLightSourceAt(square:getX(), square:getY(), square:getZ())
end

-- Runs a placed light for `hours` at `hour` of the day, and notes what it shows.
local function runGardenLight(self, hour, charge, hours)
    local light = placeGardenLight(self, charge)
    if not light then return end
    setTime(self, hour)
    self.lit = SolarGardenLight.update(light, hours)
    self.sprite = light:getTextureName()
    self.lamp = lampOn(self.square) ~= nil
    self.charge = SolarGardenLight.getCharge(light)
end

local function gardenLightCleanup(self)
    restoreTime(self)
    pickUpGardenLight(self)
end

test("renewable_energy_gadgets_garden_light_lit_at_night", {
    run = function(self)
        runGardenLight(self, MIDNIGHT, 2, 0.5)
    end,
    validate = function(self)
        if not expect(self.lit ~= nil, "no garden light was placed") then return end
        expect(self.lit and self.sprite == Sprites.gardenLight.lit, "a charged light is dark at midnight")
        expect(self.lamp, "the lit light gives no light")
        RenewableEnergyTest.expectNear("charge after half an hour lit", self.charge,
            2 - RenewableEnergy.Specs.gardenLight.nightWatts * 0.5)
    end,
    cleanup = gardenLightCleanup,
})

test("renewable_energy_gadgets_garden_light_dark_without_charge", {
    run = function(self)
        runGardenLight(self, MIDNIGHT, 0, 0.5)
    end,
    validate = function(self)
        if not expect(self.lit ~= nil, "no garden light was placed") then return end
        expect(not self.lit and self.sprite == Sprites.gardenLight.off, "an empty light is lit")
        expect(not self.lamp, "an empty light gives light")
    end,
    cleanup = gardenLightCleanup,
})

-- It goes out once the night has drawn its battery empty.
test("renewable_energy_gadgets_garden_light_runs_out", {
    run = function(self)
        runGardenLight(self, MIDNIGHT, 0.2, 1)
    end,
    validate = function(self)
        if not expect(self.lit ~= nil, "no garden light was placed") then return end
        expect(not self.lit and not self.lamp, "a light that ran out at night still shines")
        RenewableEnergyTest.expectNear("charge after running out", self.charge, 0)
    end,
    cleanup = gardenLightCleanup,
})

-- By day it is dark and its cell charges the battery, never past full.
test("renewable_energy_gadgets_garden_light_charges_by_day", {
    run = function(self)
        runGardenLight(self, NOON, 0, 2)
    end,
    validate = function(self)
        if not expect(self.lit ~= nil, "no garden light was placed") then return end
        expect(not self.lit and not self.lamp, "the light shines at noon")
        expect(self.charge > 0 and self.charge <= RenewableEnergy.Specs.gardenLight.wh,
            "two hours of noon sun left the light at " .. self.charge .. " Wh")
    end,
    cleanup = gardenLightCleanup,
})

-- Picking up a lit light takes its light away with it, by the next lighting pass.
test("renewable_energy_gadgets_garden_light_pick_up_takes_light", {
    run = function(self)
        runGardenLight(self, MIDNIGHT, 2, 0.5)
        if self.lamp then
            pickUpGardenLight(self)
        end
    end,
    validate = function(self)
        if not expect(self.lamp, "the light never lit") then return end
        expect(lampOn(self.square) == nil, "the light still shines where the garden light was")
    end,
    cleanup = restoreTime,
})

-- A garden light goes on the ground outdoors, where the sun reaches it.
test("renewable_energy_gadgets_garden_light_refused_indoors", {
    run = function(self)
        local here = player():getCurrentSquare()
        local indoor
        for dx = -20, 20 do
            for dy = -20, 20 do
                local square = here and getCell():getGridSquare(here:getX() + dx, here:getY() + dy, 0)
                if not indoor and square and not square:isOutside() and square:getFloor() and square:isFree(false) then
                    indoor = square
                end
            end
        end
        local outdoor = outdoorSquare(2)
        if not (indoor and outdoor) then return end
        local props = ISMoveableSpriteProps.new(Sprites.gardenLight.off)
        local item = instanceItem(SolarGardenLight.ITEM)
        self.indoors = props:canPlaceMoveable(player(), indoor, item)
        self.outdoors = props:canPlaceMoveable(player(), outdoor, item)
    end,
    validate = function(self)
        if not expect(self.indoors ~= nil, "no indoor and outdoor squares near the character") then return end
        expect(not self.indoors, "a garden light can be placed indoors")
        expect(self.outdoors, "a garden light can't be placed outdoors")
    end,
})

-- Picking up --------------------------------------------------------------------------------

-- Every placed tile, with the item that places it and that picking it up must give back. The
-- tiles' CustomItem decides it; without one the game hands back a generic Moveable.
local PLACED = {
    { Sprites.flat, "RenewableEnergy.SolarFlat" },
    { Sprites.failsafe, "RenewableEnergy.SolarFailsafe" },
    { Sprites.cellCharger, "RenewableEnergy.SolarCellCharger" },
    { Sprites.gardenLight.off, SolarGardenLight.ITEM },
}
for material, suffix in pairs({ wood = "Wood", metal = "Metal" }) do
    for _, sprite in pairs(Sprites.wall[material]) do
        table.insert(PLACED, { sprite, "RenewableEnergy.SolarWall" .. suffix })
    end
    for _, sprite in pairs(Sprites.rack[material]) do
        table.insert(PLACED, { sprite, "RenewableEnergy.SolarRack" .. suffix })
    end
end
for field in pairs(Sprites.bankFill) do
    table.insert(PLACED, { Sprites[field], "RenewableEnergy." .. field:gsub("^%l", string.upper) })
end

test("renewable_energy_gadgets_pick_up_returns_mod_item", {
    run = function(self)
        self.results = {}
        local square = outdoorSquare(2)
        if not square then return end
        local inventory = player():getInventory()
        for _, entry in ipairs(PLACED) do
            local spriteName, fullType = entry[1], entry[2]
            inventory:clear()
            placeObject(square, fullType, spriteName)
            local placed = objectWithSprite(square, spriteName) ~= nil
            ISMoveableSpriteProps.new(spriteName):pickUpMoveable(player(), square, true, true)
            table.insert(self.results, {
                spriteName = spriteName,
                fullType = fullType,
                placed = placed,
                removed = objectWithSprite(square, spriteName) == nil,
                returned = inventory:getCountTypeRecurse(fullType),
                items = inventory:getItems():size(),
            })
        end
    end,
    validate = function(self)
        if not expect(#self.results > 0, "no free outdoor square") then return end
        for _, r in ipairs(self.results) do
            local what = r.spriteName .. " (" .. r.fullType .. ")"
            if expect(r.placed, what .. " was not placed") then
                expect(r.removed, what .. " was not picked up")
                expect(r.returned == 1 and r.items == 1,
                    what .. " gave back " .. r.items .. " items, " .. r.returned .. " of them " .. r.fullType)
            end
        end
    end,
})

-- A mount keeps each module's condition, and a garden light its charge, from item to placed
-- object and back.
local MODULES = {
    { type = "RenewableEnergy.HomemadeSolarModule", condition = 41 },
    { type = "RenewableEnergy.SolarModule", condition = 72 },
}
local CARRIED = {
    { Sprites.rack.wood.S, "RenewableEnergy.SolarRackWood", RenewableEnergy.PowerBank.MODULES, MODULES },
    { Sprites.flat, "RenewableEnergy.SolarFlat", RenewableEnergy.PowerBank.MODULES, { MODULES[1] } },
    { Sprites.gardenLight.off, SolarGardenLight.ITEM, SolarGardenLight.CHARGE_KEY, 2.5 },
}

local function describe(value)
    if type(value) ~= "table" then
        return tostring(value)
    end
    local parts = {}
    for _, module in ipairs(value) do
        table.insert(parts, tostring(module.type) .. "@" .. tostring(module.condition))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

test("renewable_energy_gadgets_pick_up_keeps_mod_data", {
    run = function(self)
        self.results = {}
        local square = outdoorSquare(2)
        if not square then return end
        local inventory = player():getInventory()
        for _, entry in ipairs(CARRIED) do
            local spriteName, fullType, key, value = entry[1], entry[2], entry[3], entry[4]
            inventory:clear()
            placeObject(square, fullType, spriteName, { [key] = value })
            local object = objectWithSprite(square, spriteName)
            ISMoveableSpriteProps.new(spriteName):pickUpMoveable(player(), square, true, true)
            local item = inventory:getFirstTypeRecurse(fullType)
            table.insert(self.results, {
                what = fullType,
                expected = describe(value),
                placed = describe(object and object:getModData()[key]),
                pickedUp = describe(item and item:getModData()[key]),
            })
        end
    end,
    validate = function(self)
        if not expect(#self.results > 0, "no free outdoor square") then return end
        for _, r in ipairs(self.results) do
            expect(r.placed == r.expected, "placed " .. r.what .. " holds " .. r.placed .. ", expected " .. r.expected)
            expect(r.pickedUp == r.expected, "picked-up " .. r.what .. " holds " .. r.pickedUp .. ", expected " .. r.expected)
        end
    end,
})

-- Scrapping a bank finishes on the server, which only has shared Lua, so the definitions for the
-- banks' tile Materials must come from shared Lua, with an Electricity check and parts back.
test("renewable_energy_gadgets_bank_scrap_definitions", {
    validate = function()
        local defs = ISMoveableDefinitions:getInstance()
        for field in pairs(Sprites.bankFill) do
            local material = "RenewableEnergy" .. field:gsub("^%l", string.upper)
            local def = defs.getScrapDefinition(material)
            if expect(def ~= nil and defs.isScrapDefinitionValid(material), material .. " has no valid scrap definition") then
                expect(def.perk == Perks.Electricity, "scrapping " .. material .. " does not use Electricity")
                expect(#def.returnItemsStatic > 0, "scrapping " .. material .. " returns nothing")
            end
        end
    end,
})
