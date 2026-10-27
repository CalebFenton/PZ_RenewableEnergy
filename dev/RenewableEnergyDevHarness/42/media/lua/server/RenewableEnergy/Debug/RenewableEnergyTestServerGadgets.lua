-- The authority's half of the gadget, vehicle and clock tests: the solar battery charger, garden
-- light and maintainer passes, and vanilla's vehicle battery updates they are weighed against.
-- Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
local Trailer = require "RenewableEnergy/Debug/RenewableEnergyTestServerTrailer"
local Items = require "cf_commonlib/Items"

local handler, need = PZHarness.serverHandler, PZHarness.need

-- Gadgets -----------------------------------------------------------------------------------------

-- The watt-hours the solar battery charger keeps toward the next use.
local function storedWh(charger)
    return charger:getModData()[RenewableEnergy.SolarCellCharger.STORED_KEY] or 0
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

-- The batteries in the solar battery charger at `args` (Helpers.find).
handler("chargerState", function(_, args)
    return { items = Helpers.itemsOf(Helpers.find(args):getContainer()) }
end)

-- Fills the solar battery charger at `args` (Helpers.find) with `args.count` batteries at
-- `args.uses` (full if nil) and charges it for `args.hours` at the sun of the moment, then, with
-- `args.pass`, runs the pass over every charger as long again. One call, since an empty battery
-- leaves its container on its next update (DrainableComboItem.update). Answers the uses added, the
-- batteries after, `full` (every battery at its whole maximum, which the float can't tell) and
-- the Wh kept.
handler("cellCharge", function(_, args)
    local SolarCellCharger = RenewableEnergy.SolarCellCharger
    local charger = Helpers.find(args)
    local container = charger:getContainer()
    for _ = 1, args.count do
        addAt(container, SolarCellCharger.BATTERY, args.uses)
    end
    local reply = { added = SolarCellCharger.charge(charger, args.hours), after = Helpers.itemsOf(container) }
    local items, full = container:getItems(), true
    for i = 0, items:size() - 1 do
        full = full and items:get(i):getCurrentUses() == items:get(i):getMaxUses()
    end
    reply.full, reply.storedWh = full, storedWh(charger)
    if args.pass then
        SolarCellCharger.chargeAll(args.hours)
        reply.afterPass = Helpers.itemsOf(container)
    end
    return reply
end)

-- Runs the garden light at `args` (Helpers.find) through the gadget pass (GadgetCharging.update)
-- for `args.hours`, at most the longest one pass makes up for, by moving the clock on that far,
-- from `args.charge` Wh if given. A pass first brings every gadget up to now, so that the next
-- covers only the hours the clock moves. The clock starts from its whole hour: the world age the
-- pass measures is a float (GameTime.getWorldAgeHours), which holds a whole hour plus the test's
-- hours exactly, and the moment the call lands a few ticks after the hour doesn't. Answers whether
-- the light is lit, its sprite and its charge in Wh.
handler("gardenLightUpdate", function(_, args)
    local SolarGardenLight, GadgetCharging = RenewableEnergy.SolarGardenLight, RenewableEnergy.GadgetCharging
    local light = Helpers.find(args)
    local time = getGameTime()
    time:setTimeOfDay(math.floor(time:getTimeOfDay()))
    GadgetCharging.update()
    if args.charge then
        light:getModData()[SolarGardenLight.CHARGE_KEY] = args.charge
    end
    time:setTimeOfDay(time:getTimeOfDay() + args.hours)
    GadgetCharging.update()
    return { lit = SolarGardenLight.isLit(light), sprite = light:getTextureName(), charge = SolarGardenLight.getChargeWh(light) }
end)

-- Swaps the bulb of the garden light at `args` (Helpers.find) for a new `args.bulb` in one go, so
-- that a multiplayer client gets the new bulb while its lamp is still lit, which no pair of timed
-- actions does reliably. The old bulb goes to the character. Answers whether the light is lit and
-- the bulb it holds.
handler("gardenLightSwapBulb", function(player, args)
    local SolarGardenLight = RenewableEnergy.SolarGardenLight
    local light = Helpers.find(args)
    need(SolarGardenLight.removeBulb(player, light) and SolarGardenLight.addBulb(player, light, instanceItem(args.bulb)),
        "a bulb swap in the garden light on the server")
    return { lit = SolarGardenLight.isLit(light), bulb = SolarGardenLight.getBulb(light) }
end)

-- Vehicles ----------------------------------------------------------------------------------------

local function batteryOf(vehicle)
    local part = RenewableEnergy.VehicleBattery.partOf(vehicle)
    return part, part and part:getInventoryItem()
end

-- Puts a new `args.type` in the vehicle's battery slot if given, empties it if `args.empty`, and
-- charges its battery to `args.uses` if given, sent to the clients. Answers its state.
handler("vehicleBattery", function(_, args)
    local vehicle = Helpers.vehicleAt(args)
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
    return { state = Trailer.vehicleState(vehicle) }
end)

-- `args.hours` of the maintainer on the vehicle at the sun of the moment, from a battery at
-- `args.uses`: the Wh it added, the charge after and the battery's capacity in Wh.
handler("maintainerCharge", function(_, args)
    local vehicle = Helpers.vehicleAt(args)
    local _, battery = batteryOf(vehicle)
    battery:setCurrentUsesFloat(args.uses)
    local wh = RenewableEnergy.SolarMaintainer.charge(vehicle, args.hours)
    return { wh = wh, after = battery:getCurrentUsesFloat(), capacityWh = RenewableEnergy.Battery.nominalWh(battery) }
end)

-- Marks a maintainer attached in the shape older saves hold, with the condition it went on with,
-- which no code writes but detach must still take. Answers the vehicle's state.
handler("oldMaintainerMark", function(_, args)
    local vehicle = Helpers.vehicleAt(args)
    local part = batteryOf(vehicle)
    part:getModData()[RenewableEnergy.SolarMaintainer.ATTACHED_KEY] = { condition = args.condition }
    vehicle:transmitPartModData(part)
    return { state = Trailer.vehicleState(vehicle) }
end)

-- The gadget pass over every loaded vehicle (GadgetCharging.chargeVehicles) for `args.hours`: the
-- vehicle's battery charge before and after.
handler("chargeVehicles", function(_, args)
    local _, battery = batteryOf(Helpers.vehicleAt(args))
    local before = battery:getCurrentUsesFloat()
    RenewableEnergy.GadgetCharging.chargeVehicles(args.hours)
    return { before = before, after = battery:getCurrentUsesFloat() }
end)

-- Vanilla's headlight update (Vehicles.Update.Headlight) for `args.minutes` with the engine off,
-- from a battery at `args.uses`: the share of a full charge it took.
handler("headlightDrain", function(_, args)
    local vehicle = Helpers.vehicleAt(args)
    local headlight = vehicle:getPartById("HeadlightLeft")
    need(headlight and headlight:getInventoryItem(), "a left headlight on the vehicle on the server")
    local _, battery = batteryOf(vehicle)
    battery:setCurrentUsesFloat(args.uses)
    vehicle:setHeadlightsOn(true)
    Vehicles.Update.Headlight(vehicle, headlight, args.minutes)
    vehicle:setHeadlightsOn(false)
    return { drop = args.uses - battery:getCurrentUsesFloat(), type = battery:getFullType() }
end)

-- Vanilla's lightbar drain for `args.minutes` with the engine off, from a battery at `args.uses`:
-- the battery's update runs it, there being no lightbar part (Vehicles.Update.Battery calls
-- Vehicles.Update.Lightbar). Answers the share of a full charge it took.
handler("lightbarDrain", function(_, args)
    local vehicle = Helpers.vehicleAt(args)
    need(vehicle:hasLightbar(), "a lightbar on the vehicle on the server")
    local part, battery = batteryOf(vehicle)
    battery:setCurrentUsesFloat(args.uses)
    vehicle:setLightbarLightsMode(1)
    Vehicles.Update.Battery(vehicle, part, args.minutes)
    vehicle:setLightbarLightsMode(0)
    return { drop = args.uses - battery:getCurrentUsesFloat(), type = battery:getFullType() }
end)

-- Vanilla's alternator charging (Vehicles.Update.Battery) for `args.minutes` with the engine
-- running, from a battery at `args.uses`: the share of a full charge it added. The engine is
-- repaired and fuelled first, since it shuts down without fuel and stalls at random when worn.
handler("alternatorCharge", function(_, args)
    local vehicle = Helpers.vehicleAt(args)
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
    local part = trailer:getPartById(RenewableEnergy.ArrowBoard.BATTERY_BOX)
    return part and part:getItemContainer()
end

-- The clock test's fixtures that `args` names: the bank's record, the car, the trailer, the solar
-- battery charger and the garden light (Helpers.find).
local function clockFixtures(args)
    return Helpers.bankRecord(args.bank), Helpers.vehicleAt(args.car), Helpers.vehicleAt(args.trailer),
        Helpers.find(args.charger), Helpers.find(args.light)
end

-- What the clock test's fixtures hold, in Wh: the bank's, the car battery's, the solar battery
-- charger's in its cells and toward the next use, the garden light's, and the trailer box
-- battery's (-1 for none). Also the world age of the bank's last pass and of now, and the watts
-- the trailer's panels make in full sun.
local function gadgetCharges(_, args)
    local Battery = RenewableEnergy.Battery
    local record, car, trailer, charger, light = clockFixtures(args)
    local cellWh = storedWh(charger)
    for _, cell in ipairs(Helpers.itemsOf(charger:getContainer())) do
        cellWh = cellWh + cell.uses * RenewableEnergy.SolarCellCharger.BATTERY_WH
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
        light = RenewableEnergy.SolarGardenLight.getChargeWh(light),
        trailer = boxed:size() > 0 and whIn(boxed:get(0)) or -1,
        trailerWatts = RenewableEnergy.ArrowBoard.panelWatts(trailer),
    }
end

handler("gadgetCharges", gadgetCharges)

-- Readies the clock test's gadgets, half charged: a maintainer on the car, one deep cycle battery
-- in the trailer's box, which may have spawned stocked, with its lamps switched off, since they
-- would draw what the panels make, a cell in every slot of the solar battery charger, and the
-- garden light empty. Answers their charges (gadgetCharges). The gadget pass runs first, so that
-- the clock's passes from here on cover no more than the time the clock moves.
handler("stockGadgets", function(player, args)
    RenewableEnergy.GadgetCharging.update()
    local SolarCellCharger, SolarMaintainer = RenewableEnergy.SolarCellCharger, RenewableEnergy.SolarMaintainer
    local _, car, trailer, charger, light = clockFixtures(args)
    need(SolarMaintainer.attach(player, car, instanceItem(SolarMaintainer.ITEM)), "a maintainer on the car on the server")
    local box = batteryBoxOf(trailer)
    Helpers.emptyContainer(box)
    addAt(box, "RenewableEnergy.DeepCycleBattery", 0.5)
    RenewableEnergy.ArrowBoard.setSwitch(trailer, false)
    -- An empty cell is used up and leaves its container on its next update
    -- (DrainableComboItem.update), so the cells start half charged.
    for _ = 1, SolarCellCharger.SLOTS do
        addAt(charger:getContainer(), SolarCellCharger.BATTERY, 0.5)
    end
    light:getModData()[RenewableEnergy.SolarGardenLight.CHARGE_KEY] = 0
    return gadgetCharges(player, args)
end)
