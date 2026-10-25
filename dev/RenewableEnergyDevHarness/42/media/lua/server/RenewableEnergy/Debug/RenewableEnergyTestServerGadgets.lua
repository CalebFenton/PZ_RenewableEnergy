-- The authority's half of the gadget, vehicle and clock tests: the solar battery charger, garden
-- light and maintainer passes, and vanilla's vehicle battery updates they are weighed against.
-- Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler
local squareAt, vehicleAt, onVehicle = PZHarness.Fixtures.squareAt, Helpers.vehicleAt, Helpers.onVehicle

-- Gadgets -----------------------------------------------------------------------------------------

local function usesOf(container)
    local uses = {}
    for i = 0, (container and container:getItems():size() or 0) - 1 do
        uses[i + 1] = container:getItems():get(i):getCurrentUsesFloat()
    end
    return uses
end

-- The watt-hours the solar battery charger keeps toward the next use.
local function storedWh(charger)
    return charger:getModData()[RenewableEnergy.SolarCellCharger.STORED_KEY] or 0
end

-- The charges of the batteries in the solar battery charger on the square at `args`.
handler("chargerState", function(_, args)
    local charger = RenewableEnergy.SolarCellCharger.findOn(squareAt(args))
    if not charger then
        return nil, "the solar battery charger on the server"
    end
    return { uses = usesOf(charger:getContainer()) }
end)

-- Fills the solar battery charger on the square at `args` with `args.count` batteries at
-- `args.uses` (full if nil) and charges it for `args.hours` at the sun of the moment, then, with
-- `args.pass`, runs the pass over every charger as long again. One call, since an empty battery
-- leaves its container on its next update (DrainableComboItem.update). Answers the uses added, the
-- charges after, `full` (every battery at its whole maximum, which the float can't tell) and the
-- Wh kept.
handler("cellCharge", function(_, args)
    local SolarCellCharger = RenewableEnergy.SolarCellCharger
    local charger = SolarCellCharger.findOn(squareAt(args))
    if not charger then
        return nil, "the solar battery charger on the server"
    end
    local container = charger:getContainer()
    for _ = 1, args.count do
        local battery = container:AddItem(SolarCellCharger.BATTERY)
        if args.uses then
            battery:setCurrentUsesFloat(args.uses)
        end
        sendAddItemToContainer(container, battery)
    end
    local reply = { added = SolarCellCharger.charge(charger, args.hours), after = usesOf(container) }
    local items, full = container:getItems(), true
    for i = 0, items:size() - 1 do
        full = full and items:get(i):getCurrentUses() == items:get(i):getMaxUses()
    end
    reply.full, reply.storedWh = full, storedWh(charger)
    if args.pass then
        SolarCellCharger.chargeAll(args.hours)
        reply.afterPass = usesOf(container)
    end
    return reply
end)

-- Runs the garden light on the square at `args` through the gadget pass (GadgetCharging.update)
-- for `args.hours`, at most the longest one pass makes up for, by moving the clock on that far,
-- from `args.charge` Wh if given. A pass first brings every gadget up to now, so that the next
-- covers only the hours the clock moves. The clock starts from its whole hour: the world age the
-- pass measures is a float (GameTime.getWorldAgeHours), which holds a whole hour plus the test's
-- hours exactly, and the moment the call lands a few ticks after the hour doesn't. Answers whether
-- the light is lit, its sprite and its charge in Wh.
handler("gardenLightUpdate", function(_, args)
    local SolarGardenLight, GadgetCharging = RenewableEnergy.SolarGardenLight, RenewableEnergy.GadgetCharging
    local light = SolarGardenLight.findOn(squareAt(args))
    if not light then
        return nil, "the garden light on the server"
    end
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

-- Swaps the bulb of the garden light on the square at `args` for a new `args.bulb` in one go, so
-- that a multiplayer client gets the new bulb while its lamp is still lit, which no pair of timed
-- actions does reliably. The old bulb goes to the character. Answers whether the light is lit and
-- the bulb it holds.
handler("gardenLightSwapBulb", function(player, args)
    local SolarGardenLight = RenewableEnergy.SolarGardenLight
    local light = SolarGardenLight.findOn(squareAt(args))
    if not light then
        return nil, "the garden light on the server"
    end
    if not (SolarGardenLight.removeBulb(player, light) and SolarGardenLight.addBulb(player, light, instanceItem(args.bulb))) then
        return nil, "a bulb swap in the garden light on the server"
    end
    return { lit = SolarGardenLight.isLit(light), bulb = SolarGardenLight.getBulb(light) }
end)

-- Vehicles ----------------------------------------------------------------------------------------

local function batteryOf(vehicle)
    local part = RenewableEnergy.VehicleBattery.partOf(vehicle)
    return part, part and part:getInventoryItem()
end

-- What the tests read of a vehicle: its battery and whether a maintainer is attached.
local function carState(vehicle)
    local _, battery = batteryOf(vehicle)
    return {
        battery = battery and { type = battery:getFullType(), uses = battery:getCurrentUsesFloat() } or nil,
        attached = RenewableEnergy.SolarMaintainer.isAttached(vehicle),
    }
end

onVehicle("carState", carState)

-- Puts a new `args.type` in the vehicle's battery slot if given, empties it if `args.empty`, and
-- charges its battery to `args.uses` if given, sent to the clients.
onVehicle("vehicleBattery", function(vehicle, args)
    local part = batteryOf(vehicle)
    if not part then
        return nil, "a battery slot in the vehicle on the server"
    end
    if args.type or args.empty then
        part:setInventoryItem(args.type and instanceItem(args.type) or nil)
        vehicle:transmitPartItem(part)
    end
    local _, battery = batteryOf(vehicle)
    if battery and args.uses then
        battery:setCurrentUsesFloat(args.uses)
        vehicle:transmitPartUsedDelta(part)
    end
    return carState(vehicle)
end)

-- `args.hours` of the maintainer on the vehicle at the sun of the moment, from a battery at
-- `args.uses`: the Wh it added, the charge after and the battery's capacity in Wh.
onVehicle("maintainerCharge", function(vehicle, args)
    local _, battery = batteryOf(vehicle)
    battery:setCurrentUsesFloat(args.uses)
    local wh = RenewableEnergy.SolarMaintainer.charge(vehicle, args.hours)
    return { wh = wh, after = battery:getCurrentUsesFloat(), capacityWh = RenewableEnergy.Battery.nominalWh(battery) }
end)

-- Marks a maintainer attached in the shape older saves hold, with the condition it went on with,
-- which no code writes but detach must still take.
onVehicle("oldMaintainerMark", function(vehicle, args)
    local part = batteryOf(vehicle)
    part:getModData()[RenewableEnergy.SolarMaintainer.ATTACHED_KEY] = { condition = args.condition }
    vehicle:transmitPartModData(part)
    return carState(vehicle)
end)

-- The gadget pass over every loaded vehicle (GadgetCharging.chargeVehicles) for `args.hours`: the
-- vehicle's battery charge before and after.
onVehicle("chargeVehicles", function(vehicle, args)
    local _, battery = batteryOf(vehicle)
    local before = battery:getCurrentUsesFloat()
    RenewableEnergy.GadgetCharging.chargeVehicles(args.hours)
    return { before = before, after = battery:getCurrentUsesFloat() }
end)

-- Vanilla's headlight update (Vehicles.Update.Headlight) for `args.minutes` with the engine off,
-- from a battery at `args.uses`: the share of a full charge it took.
onVehicle("headlightDrain", function(vehicle, args)
    local headlight = vehicle:getPartById("HeadlightLeft")
    if not (headlight and headlight:getInventoryItem()) then
        return nil, "a left headlight on the vehicle on the server"
    end
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
onVehicle("lightbarDrain", function(vehicle, args)
    if not vehicle:hasLightbar() then
        return nil, "a lightbar on the vehicle on the server"
    end
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
onVehicle("alternatorCharge", function(vehicle, args)
    vehicle:repair()
    local tank = vehicle:getPartById("GasTank")
    if tank then
        tank:setContainerContentAmount(tank:getContainerCapacity())
    end
    local part, battery = batteryOf(vehicle)
    battery:setCurrentUsesFloat(args.uses)
    vehicle:engineDoRunning()
    if not vehicle:isEngineRunning() then
        return nil, "a running engine in the vehicle on the server"
    end
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

-- What the clock test's fixtures hold, on the squares and vehicles `args` names, in Wh: the bank's,
-- the car battery's, the solar battery charger's in its cells and toward the next use, the garden
-- light's, and the trailer box battery's (-1 for none). Also the world age of the bank's last pass
-- and of now, and the watts the trailer's panels make in full sun.
local function gadgetCharges(args)
    local SolarCellCharger, Battery = RenewableEnergy.SolarCellCharger, RenewableEnergy.Battery
    local record = Helpers.bankRecordAt(args.bank)
    local car, trailer = vehicleAt(args.car), vehicleAt(args.trailer)
    local charger = SolarCellCharger.findOn(squareAt(args.charger))
    local light = RenewableEnergy.SolarGardenLight.findOn(squareAt(args.light))
    if not (record and car and trailer and charger and light) then
        return nil, "the clock test's bank, car, trailer, solar battery charger and garden light on the server"
    end
    local cellWh = storedWh(charger)
    for _, uses in ipairs(usesOf(charger:getContainer())) do
        cellWh = cellWh + uses * RenewableEnergy.Specs.cellChargerBatteryWh
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

-- Readies the clock test's gadgets, half charged: a maintainer on the car, one deep cycle battery
-- in the trailer's box, which may have spawned stocked, with its lamps switched off, since they
-- would draw what the panels make, a cell in every slot of the solar battery charger, and the
-- garden light empty. Answers their charges (gadgetCharges). The gadget pass runs first, so that
-- the clock's passes from here on cover no more than the time the clock moves.
handler("stockGadgets", function(player, args)
    RenewableEnergy.GadgetCharging.update()
    local SolarCellCharger = RenewableEnergy.SolarCellCharger
    local car, trailer = vehicleAt(args.car), vehicleAt(args.trailer)
    local charger = SolarCellCharger.findOn(squareAt(args.charger))
    local light = RenewableEnergy.SolarGardenLight.findOn(squareAt(args.light))
    if not (car and trailer and charger and light) then
        return nil, "the clock test's car, trailer, solar battery charger and garden light on the server"
    end
    if not RenewableEnergy.SolarMaintainer.attach(player, car, instanceItem(RenewableEnergy.SolarMaintainer.ITEM)) then
        return nil, "a maintainer on the car on the server"
    end
    local box = batteryBoxOf(trailer)
    box:removeAllItems()
    box:AddItem("RenewableEnergy.DeepCycleBattery"):setCurrentUsesFloat(0.5)
    RenewableEnergy.ArrowBoard.setSwitch(trailer, false)
    -- An empty cell is used up and leaves its container on its next update
    -- (DrainableComboItem.update), so the cells start half charged.
    local cells = charger:getContainer()
    for _ = 1, SolarCellCharger.SLOTS do
        local cell = cells:AddItem(SolarCellCharger.BATTERY)
        cell:setCurrentUsesFloat(0.5)
        sendAddItemToContainer(cells, cell)
    end
    light:getModData()[RenewableEnergy.SolarGardenLight.CHARGE_KEY] = 0
    return gadgetCharges(args)
end)

handler("gadgetCharges", function(_, args)
    return gadgetCharges(args)
end)
