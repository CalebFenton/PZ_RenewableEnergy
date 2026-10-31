-- The authority's half of the gadget, vehicle and clock tests: the solar battery charger, garden
-- light and maintainer passes, and vanilla's vehicle battery updates they are weighed against.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
require "PZHarness/ServerFixtures"
require "PZHarness/ServerRecords"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local Items = require "cf_commonlib/Items"
local Sun = require "RenewableEnergy/Sun"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Trailer"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local GadgetCharging = require "RenewableEnergy/Gadgets/GadgetCharging"
local SolarCellCharger = require "RenewableEnergy/Gadgets/SolarCellCharger"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local SolarMaintainer = require "RenewableEnergy/Gadgets/SolarMaintainer"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"

local handler, need = PZHarness.serverHandler, PZHarness.need

-- Gadgets -----------------------------------------------------------------------------------------

-- The watt-hours the solar battery charger keeps toward the next use.
local function storedWh(charger)
    return charger:getModData()[SolarCellCharger.STORED_KEY] or 0
end

-- Puts a new `fullType` at `uses` (as made if nil) in `container`. The uses go on first, since
-- Items.addItem tells the clients at once.
local function addAt(container, fullType, uses)
    local item = instanceItem(fullType)
    if uses then
        item:setCurrentUsesFloat(uses)
    end
    Items.addItem(container, item)
end

-- The batteries in the solar battery charger at `args` (Kinds.find).
handler("chargerState", function(_, args)
    return { items = Kinds.itemsOf(Kinds.find(args):getContainer()) }
end)

-- Fills the solar battery charger at `args` (Kinds.find) with `args.count` batteries at
-- `args.uses` (full if nil) and charges it for `args.hours` under the sky of the moment, then, with
-- `args.pass`, runs the pass over every charger as long again. One call, since an empty battery
-- leaves its container on its next update (DrainableComboItem.update). Answers the uses added, the
-- batteries after, `full` (every battery at its whole maximum, which the float can't tell), the
-- Wh kept and `flat`, the light the sky gave (Sun.skyNow).
handler("cellCharge", function(_, args)
    local charger = Kinds.find(args)
    local container = charger:getContainer()
    for _ = 1, args.count do
        addAt(container, SolarCellCharger.BATTERY, args.uses)
    end
    local sky = Sun.skyNow()
    local reply = { added = SolarCellCharger.charge(charger, args.hours, sky), after = Kinds.itemsOf(container), flat = sky.flat }
    local items, full = container:getItems(), true
    for i = 0, items:size() - 1 do
        full = full and items:get(i):getCurrentUses() == items:get(i):getMaxUses()
    end
    reply.full, reply.storedWh = full, storedWh(charger)
    if args.pass then
        SolarCellCharger.chargeAll(args.hours, sky)
        reply.afterPass = Kinds.itemsOf(container)
    end
    return reply
end)

-- Runs the garden light at `args` (Kinds.find) through the gadget pass (GadgetCharging.update)
-- for `args.hours`, at most the longest one pass makes up for, by moving the clock on that far,
-- from `args.charge` Wh if given. A pass first brings every gadget up to now, so that the next
-- covers only the hours the clock moves. The clock starts from its whole hour: the world age the
-- pass measures is a float (GameTime.getWorldAgeHours), which holds a whole hour plus the test's
-- hours exactly, and the moment the call lands a few ticks after the hour doesn't. Answers whether
-- the light is lit, its sprite, its charge in Wh and `flat`, the light the sky gave the pass that
-- moved the clock (Sun.skyNow).
handler("gardenLightUpdate", function(_, args)
    local light = Kinds.find(args)
    local time = getGameTime()
    time:setTimeOfDay(math.floor(time:getTimeOfDay()))
    GadgetCharging.update()
    if args.charge then
        light:getModData()[SolarGardenLight.CHARGE_KEY] = args.charge
    end
    time:setTimeOfDay(time:getTimeOfDay() + args.hours)
    GadgetCharging.update()
    return { lit = SolarGardenLight.isLit(light), sprite = light:getTextureName(), charge = SolarGardenLight.getChargeWh(light),
        flat = Sun.skyNow().flat }
end)

-- Vehicles ----------------------------------------------------------------------------------------

local function batteryOf(vehicle)
    local part = VehicleBattery.partOf(vehicle)
    return part, part and part:getInventoryItem()
end

-- Puts a new `args.type` in the vehicle's battery slot if given, empties it if `args.empty`, and
-- charges its battery to `args.uses` if given, sent to the clients. Answers its state.
handler("vehicleBattery", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    local part = need(batteryOf(vehicle), "a battery slot in the vehicle on the server")
    if args.type or args.empty then
        part:setInventoryItem(args.type and instanceItem(args.type) or nil)
        vehicle:transmitPartItem(part)
    end
    local _, battery = batteryOf(vehicle)
    if battery and args.uses then
        battery:setCurrentUsesFloat(args.uses)
        vehicle:transmitPartUsedDelta(part)
    end
    return { state = Kinds.vehicleState(vehicle) }
end)

-- `args.hours` of the maintainer on the vehicle under the sky of the moment, from a battery at
-- `args.uses`: the Wh it added, the charge after, the battery's capacity in Wh and `flat`, the
-- light the sky gave (Sun.skyNow).
handler("maintainerCharge", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    local _, battery = batteryOf(vehicle)
    battery:setCurrentUsesFloat(args.uses)
    local sky = Sun.skyNow()
    local wh = SolarMaintainer.charge(vehicle, args.hours, sky)
    return { wh = wh, after = battery:getCurrentUsesFloat(), capacityWh = Battery.nominalWh(battery), flat = sky.flat }
end)

-- Marks a maintainer attached in the shape older saves hold, with the condition it went on with,
-- which no code writes but detach must still take. Answers the vehicle's state.
handler("oldMaintainerMark", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    local part = batteryOf(vehicle)
    part:getModData()[SolarMaintainer.ATTACHED_KEY] = { condition = args.condition }
    vehicle:transmitPartModData(part)
    return { state = Kinds.vehicleState(vehicle) }
end)

-- The gadget pass over every loaded vehicle (GadgetCharging.chargeVehicles) for `args.hours`: the
-- vehicle's battery charge before and after.
handler("chargeVehicles", function(_, args)
    local _, battery = batteryOf(PZHarness.vehicleAt(args))
    local before = battery:getCurrentUsesFloat()
    GadgetCharging.chargeVehicles(args.hours, Sun.skyNow())
    return { before = before, after = battery:getCurrentUsesFloat() }
end)

-- Runs `update(part)` of the vehicle's battery part with its lights switched on by `switch(true)`,
-- from a battery at `args.uses`, then switches them off: the share of a full charge it took.
local function lightDrain(vehicle, args, switch, update)
    local part, battery = batteryOf(vehicle)
    battery:setCurrentUsesFloat(args.uses)
    switch(true)
    update(part)
    switch(false)
    return { drop = args.uses - battery:getCurrentUsesFloat(), type = battery:getFullType() }
end

-- Vanilla's headlight update (Vehicles.Update.Headlight) for `args.minutes` with the engine off,
-- from a battery at `args.uses`: the share of a full charge it took.
handler("headlightDrain", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    local headlight = vehicle:getPartById("HeadlightLeft")
    need(headlight and headlight:getInventoryItem(), "a left headlight on the vehicle on the server")
    return lightDrain(vehicle, args, function(on) vehicle:setHeadlightsOn(on) end,
        function() Vehicles.Update.Headlight(vehicle, headlight, args.minutes) end)
end)

-- Vanilla's lightbar drain for `args.minutes` with the engine off, from a battery at `args.uses`:
-- the battery's update runs it, there being no lightbar part (Vehicles.Update.Battery calls
-- Vehicles.Update.Lightbar). Answers the share of a full charge it took.
handler("lightbarDrain", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    need(vehicle:hasLightbar(), "a lightbar on the vehicle on the server")
    return lightDrain(vehicle, args, function(on) vehicle:setLightbarLightsMode(on and 1 or 0) end,
        function(part) Vehicles.Update.Battery(vehicle, part, args.minutes) end)
end)

-- Vanilla's alternator charging (Vehicles.Update.Battery) for `args.minutes` with the engine
-- running, from a battery at `args.uses`: the share of a full charge it added. The engine is
-- repaired and fuelled first, since it shuts down without fuel and stalls at random when worn.
handler("alternatorCharge", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    vehicle:repair()
    local tank = vehicle:getPartById("GasTank")
    if tank then
        tank:setContainerContentAmount(tank:getContainerCapacity())
    end
    local part, battery = batteryOf(vehicle)
    battery:setCurrentUsesFloat(args.uses)
    vehicle:engineDoRunning()
    need(vehicle:isEngineRunning(), "a running engine in the vehicle on the server")
    Vehicles.Update.Battery(vehicle, part, args.minutes)
    local gain = battery:getCurrentUsesFloat() - args.uses
    vehicle:shutOff()
    return { gain = gain, type = battery:getFullType() }
end)

-- The clock ---------------------------------------------------------------------------------------

local function batteryBoxOf(trailer)
    local part = trailer:getPartById(ArrowBoard.BATTERY_BOX)
    return part and part:getItemContainer()
end

-- The clock test's fixtures that `args` names: the bank's record, the car, the trailer, the solar
-- battery charger and the garden light (Kinds.find).
local function clockFixtures(args)
    local bank = args.bank
    return PZHarness.Records.at({ kind = "bank", x = bank.x, y = bank.y, z = bank.z }), PZHarness.vehicleAt(args.car),
        PZHarness.vehicleAt(args.trailer),
        Kinds.find(args.charger), Kinds.find(args.light)
end

-- What the clock test's fixtures hold, in Wh: the bank's, the car battery's, the solar battery
-- charger's in its cells and toward the next use, the garden light's, and the trailer box
-- battery's (-1 for none). Also the world age of the bank's last pass and of now, and the watts
-- the trailer's panels make in full sun.
local function gadgetCharges(_, args)
    local record, car, trailer, charger, light = clockFixtures(args)
    local cellWh = storedWh(charger)
    for _, cell in ipairs(Kinds.itemsOf(charger:getContainer())) do
        cellWh = cellWh + cell.uses * SolarCellCharger.BATTERY_WH
    end
    local function whIn(battery)
        return Battery.getCharge(battery) * Battery.nominalWh(battery)
    end
    local _, carBattery = batteryOf(car)
    local boxed = batteryBoxOf(trailer):getItems()
    return {
        bank = record.charge * record.nominalWh,
        bankPassAge = record.lastHour, age = getGameTime():getWorldAgeHours(),
        car = whIn(carBattery), charger = cellWh,
        light = SolarGardenLight.getChargeWh(light),
        trailer = boxed:size() > 0 and whIn(boxed:get(0)) or -1,
        trailerWatts = ArrowBoard.panelWatts(trailer),
    }
end

handler("gadgetCharges", gadgetCharges)

-- Readies the clock test's gadgets, half charged: a maintainer on the car, one deep cycle battery
-- in the trailer's box, which may have spawned stocked, with its lamps switched off, since they
-- would draw what the panels make, a cell in every slot of the solar battery charger, and the
-- garden light empty. Answers their charges (gadgetCharges). The gadget pass runs first, so that
-- the clock's passes from here on cover no more than the time the clock moves.
handler("stockGadgets", function(player, args)
    GadgetCharging.update()
    local _, car, trailer, charger, light = clockFixtures(args)
    need(SolarMaintainer.attach(player, car, instanceItem(SolarMaintainer.ITEM)), "a maintainer on the car on the server")
    local box = batteryBoxOf(trailer)
    Helpers.emptyContainer(box)
    addAt(box, "RenewableEnergy.DeepCycleBattery", 0.5)
    ArrowBoard.setSwitch(trailer, false)
    -- An empty cell is used up and leaves its container on its next update
    -- (DrainableComboItem.update), so the cells start half charged.
    for _ = 1, SolarCellCharger.SLOTS do
        addAt(charger:getContainer(), SolarCellCharger.BATTERY, 0.5)
    end
    light:getModData()[SolarGardenLight.CHARGE_KEY] = 0
    return gadgetCharges(player, args)
end)
