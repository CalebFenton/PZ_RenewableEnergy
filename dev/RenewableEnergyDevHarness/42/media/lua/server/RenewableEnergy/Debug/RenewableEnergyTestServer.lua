-- The authority's half of the tests (PZHarness.Test.server): fixtures only the server's bank system
-- can build, its passes, and its records, which a multiplayer client holds only copies of. Single
-- player runs them in the same Lua state, so tests use them in both modes. Server Lua loads after
-- client Lua, and the mod's server files are empty on a multiplayer client, so the handlers look the
-- mod up when they run. Every answer is plain values, which cross the network. Only registers
-- handlers, so a --stay rerun loads it again (RELOAD_FILES).

require "PZHarness/ServerHandlers"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler
local overlaysOf, squareAt, vehicleAt = Helpers.overlaysOf, Helpers.squareAt, Helpers.vehicleAt

local function mod()
    return RenewableEnergy.PowerBank, RenewableEnergy.Battery, RenewableEnergy.Wear
end

-- The server's record of the bank at `position`, and its tile.
local function recordAt(position)
    local record = position and RenewableEnergy.PowerBank.serverSystem:getLuaObjectAt(position.x, position.y, position.z)
    return record, record and record:getIsoObject()
end

local function firstOfType(container, fullType)
    return container and container:getFirstType(fullType)
end

-- What the tests read of a bank on the authority: its record, its tile and the parts in it.
local function stateOf(record)
    if not record then
        return { found = false }
    end
    local bank = record:getIsoObject()
    local square = bank and bank:getSquare()
    local items = {}
    local container = bank and bank:getContainer()
    for i = 0, (container and container:getItems():size() or 0) - 1 do
        local item = container:getItems():get(i)
        table.insert(items, { type = item:getFullType(), id = item:getID(), condition = item:getCondition(),
            uses = item:getCurrentUsesFloat() })
    end
    return {
        found = true, on = record.on == true, name = record.name or "", charge = record.charge,
        storedWh = record.charge * record.nominalWh, nominalWh = record.nominalWh, overloaded = record.overloaded == true,
        cycleDepth = record.cycleDepth, limitW = record:limitW(), drawW = record:drawW(),
        sources = #record.sources, batteries = #record.batteries,
        activated = bank ~= nil and bank:isActivated(), powered = square ~= nil and square:haveElectricity(),
        items = items, overlays = overlaysOf(bank), status = record.status,
    }
end

local function stateAt(position)
    return stateOf((recordAt(position)))
end

-- A bank pass's context with the weather fixed: `light` W/m² on every mount, clear, 25 °C, no
-- snow, and `stormHours` of storm.
local function passContext(light, stormHours)
    local function irradiance() return light end
    return {
        weather = RenewableEnergy.Sun.CLEAR_WEATHER, precipitation = 0, airC = 25, elevation = light > 0 and 45 or -10,
        stormHours = stormHours or 0, irradiance = irradiance, clearIrradiance = irradiance,
    }
end

-- Fixtures ---------------------------------------------------------------------------------------

-- A bank of Sprites field `args.kind` on the square at `args.x`, `args.y`, `args.z`, holding the
-- full types `args.items`, its batteries charged to `args.charge` (full by default), filled straight
-- into its container as world spawns do and sent to the clients that see it. Answers with the
-- bank's position; removed when the test ends.
handler("placeBank", function(_, args, defer)
    local PowerBank, Battery = mod()
    local square = squareAt(args)
    if not square then
        return nil, "the bank's square loaded on the server"
    end
    local bank = PowerBank.place(square, RenewableEnergy.Sprites[args.kind], -1)
    defer(function()
        if bank:getObjectIndex() ~= -1 then
            PowerBank.remove(bank)
        end
    end)
    local container = bank:getContainer()
    for _, fullType in ipairs(args.items or {}) do
        local item = container:AddItem(fullType)
        if not item then
            return nil, "an item " .. tostring(fullType)
        end
        if Battery.isBattery(item) then
            Battery.setCharge(item, args.charge or 1)
        end
        sendAddItemToContainer(container, item)
    end
    local position = PowerBank.positionOf(bank)
    PowerBank.perform(nil, "refresh", { bank = position })
    if not PowerBank.serverSystem:getLuaObjectOnSquare(square) then
        return nil, "a bank the server's bank system registered"
    end
    return position
end)

-- A panel tile of `args.sprite` on the square at `args`, holding `args.modules` ({ { type,
-- condition } }) if given, placed as the moveables cursor places one (OnObjectAdded draws its
-- cracks), and connected by the server's character to the bank at `args.bank` if given. Answers
-- whether it connected and the refusal; removed when the test ends.
handler("placePanel", function(player, args, defer)
    local PowerBank = mod()
    local square = squareAt(args)
    if not square then
        return nil, "the panel's square loaded on the server"
    end
    local panel = IsoObject.new(square, args.sprite, "RenewableEnergy")
    if args.modules then
        panel:getModData()[PowerBank.MODULES] = args.modules
    end
    square:AddTileObject(panel)
    defer(function()
        if panel:getObjectIndex() ~= -1 then
            square:transmitRemoveItemFromSquare(panel)
        end
    end)
    if isServer() then
        panel:transmitCompleteItemToClients()
    end
    triggerEvent("OnObjectAdded", panel)
    if not args.bank then
        return { connected = false }
    end
    local connected, reason = PowerBank.perform(player, "connectSource",
        { bank = args.bank, source = PowerBank.positionOf(panel) })
    return { connected = connected, reason = reason }
end)

-- A fuelled Base.Generator plugged in on the square at `args`, running if `args.running`, with a
-- failsafe tile beside it if `args.failsafe`. Removed, switched off first, when the test ends.
handler("placeGenerator", function(_, args, defer)
    local square = squareAt(args)
    if not square then
        return nil, "the generator's square loaded on the server"
    end
    local generator = IsoGenerator.new(instanceItem("Base.Generator"), square:getCell(), square)
    defer(function()
        if generator:getObjectIndex() ~= -1 then
            -- Squares stay powered by a running generator that leaves them.
            if generator:isActivated() then
                generator:setActivated(false)
            end
            square:transmitRemoveItemFromSquare(generator)
        end
    end)
    generator:setConnected(true)
    generator:setFuel(10)
    generator:setCondition(100)
    if args.failsafe then
        local failsafe = IsoObject.new(square, RenewableEnergy.Sprites.failsafe, "RenewableEnergy")
        square:AddTileObject(failsafe)
        defer(function()
            if failsafe:getObjectIndex() ~= -1 then
                square:transmitRemoveItemFromSquare(failsafe)
            end
        end)
        if isServer() then
            failsafe:transmitCompleteItemToClients()
        end
    end
    if args.running then
        generator:setActivated(true)
    end
    return {}
end)

-- The generator on the square at `args`: whether it runs, and its fuel.
handler("generatorState", function(_, args)
    local square = squareAt(args)
    local generator = square and square:getGenerator()
    if not generator then
        return nil, "the generator on the server"
    end
    return { running = generator:isActivated(), fuel = generator:getFuel() }
end)

-- Banks ------------------------------------------------------------------------------------------

-- The server's record of the bank at `args` (see stateOf).
handler("bankState", function(_, args)
    return stateAt(args)
end)

local function needRecord(position)
    local record = recordAt(position)
    if not record then
        return nil, nil, "the bank's record on the server"
    end
    return record, record:getIsoObject()
end

-- Sets fields of the record of the bank at `args.bank` (its charge, its switch), then writes the
-- charge into its batteries if `args.writeBatteries`.
handler("bankSet", function(_, args)
    local record, bank, missing = needRecord(args.bank)
    if not record then return nil, missing end
    for key, value in pairs(args.fields or {}) do
        record[key] = value
    end
    if args.writeBatteries and bank and bank:getContainer() then
        record:writeBatteries(bank:getContainer(), false)
    end
    return stateOf(record)
end)

-- A pass of `args.hours` (1 by default) of the bank at `args.bank` with `args.light` W/m² on every
-- mount and `args.stormHours` of storm; answers the bank's state after it.
handler("bankPass", function(_, args)
    local record, _, missing = needRecord(args.bank)
    if not record then return nil, missing end
    record:update(args.hours or 1, passContext(args.light or 0, args.stormHours))
    return stateOf(record)
end)

-- Replaces the measured load of the bank at `args.bank` with appliances of the Specs.loads kinds
-- `args.names`, as if the scan had found them switched on, and lets the bank react: cut or restore
-- its power and send its status. The next pass measures the real load again.
handler("applyLoad", function(_, args)
    local record, _, missing = needRecord(args.bank)
    if not record then return nil, missing end
    local Loads = RenewableEnergy.Loads
    local load = Loads.new()
    for _, name in ipairs(args.names or {}) do
        Loads.add(load, name)
    end
    record.loadW, record.averageLoadW, record.loadByKind = load.watts, load.averageWatts, Loads.byKind(load)
    record:checkOverload()
    record:switchGenerator()
    record:sendStatus()
    return stateOf(record)
end)

-- Sets the condition of the first `args.type` in the bank at `args.bank`, sent to the clients, and
-- lets the bank read its parts again if `args.recount`.
handler("setPartCondition", function(_, args)
    local _, _, Wear = mod()
    local record, bank, missing = needRecord(args.bank)
    if not record then return nil, missing end
    local item = firstOfType(bank and bank:getContainer(), args.type)
    if not item then
        return nil, "a " .. tostring(args.type) .. " in the bank on the server"
    end
    Wear.setCondition(item, args.condition)
    sendItemStats(item)
    if args.recount then
        record:recount()
        record:sendStatus()
    end
    return stateOf(record)
end)

-- Takes the first `args.type` out of the bank at `args.bank`, past the bank's own commands, as a
-- part that disappeared would.
handler("removePart", function(_, args)
    local record, bank, missing = needRecord(args.bank)
    if not record then return nil, missing end
    local container = bank and bank:getContainer()
    local item = firstOfType(container, args.type)
    if not item then
        return nil, "a " .. tostring(args.type) .. " in the bank on the server"
    end
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    return stateOf(record)
end)

-- Runs the bank system's command `args.command` with `args.args` as the server's character, the
-- way a timed action's complete() does. Answers whether it did, why not, and the character's
-- Electricity XP before and after.
handler("perform", function(player, args)
    local PowerBank = mod()
    local xp = player:getXp():getXP(Perks.Electricity)
    local ok, reason = PowerBank.perform(player, args.command, args.args)
    return { ok = ok == true, reason = reason, xpBefore = xp, xpAfter = player:getXp():getXP(Perks.Electricity) }
end)

-- Finishes a Rename action on the bank at `args.bank` as the server's character, the way the server
-- finishes a client's timed action (ActionManager.update calls complete()). Answers whether it did.
handler("completeRename", function(player, args)
    local _, bank, missing = needRecord(args.bank)
    if not bank then return nil, missing end
    local Action = RenewableEnergyAction
    return { done = Action:new(player, Action.RENAME, nil, bank, nil, nil, args.name):complete() == true }
end)

-- The bank part's wear over `args.hours` hours on and `args.overloads` overloads, from the
-- conditions in `args.conditions` (full type to condition): the condition each type lost.
handler("wearParts", function(_, args)
    local _, _, Wear = mod()
    local record, bank, missing = needRecord(args.bank)
    if not record then return nil, missing end
    local container = bank:getContainer()
    for fullType, condition in pairs(args.conditions or {}) do
        Wear.setCondition(firstOfType(container, fullType), condition)
    end
    record:wearParts(container, args.hours or 0, args.overloads or 0)
    local lost = {}
    for fullType, condition in pairs(args.conditions or {}) do
        lost[fullType] = condition - firstOfType(container, fullType):getCondition()
    end
    return { lost = lost }
end)

-- A day of the bank at `args.bank` drawn from `args.high` down to `args.charge`, then the day
-- turning: the cycle depth before and after, and its batteries' conditions.
handler("cycleDay", function(_, args)
    local record, bank, missing = needRecord(args.bank)
    if not record then return nil, missing end
    record.cycleHigh = args.high
    record.charge = args.charge
    record:trackCycle()
    local depth = record.cycleDepth
    record.day = record.day and record.day - 1 or 0
    record:newDay(bank:getContainer(), record.day + 1)
    local state = stateOf(record)
    state.depthBefore = depth
    return state
end)

-- Switches the bank at `args.bank` on through its own power-up, as the player's switch does.
handler("powerUp", function(_, args)
    local record, _, missing = needRecord(args.bank)
    if not record then return nil, missing end
    record:powerUp()
    return stateOf(record)
end)

-- Takes the bank at `args.bank` away the way picking it up or destroying it does.
handler("removeBank", function(_, args)
    local _, bank, missing = needRecord(args.bank)
    if not bank then return nil, missing end
    RenewableEnergy.PowerBank.remove(bank)
    local square = squareAt(args.bank)
    return { powered = square:haveElectricity(),
        registered = RenewableEnergy.PowerBank.serverSystem:getLuaObjectOnSquare(square) ~= nil }
end)

-- Takes the containers off the bank at `args.bank`, as a bank tile a map or a placement that failed
-- halfway leaves, then loads its square the way its chunk loading does, which rebuilds it. Answers
-- the rebuilt bank's state. placeBank's cleanup removes only the tile it placed, so the rebuilt one
-- is removed when the test ends.
handler("rebuildBank", function(_, args, defer)
    local _, bank, missing = needRecord(args.bank)
    if not bank then return nil, missing end
    bank:removeAllContainers()
    local square = squareAt(args.bank)
    MapObjects.loadGridSquare(square)
    local rebuilt = RenewableEnergy.PowerBank.bankOn(square)
    if not (rebuilt and rebuilt ~= bank and rebuilt:getContainer()) then
        return nil, "a rebuilt bank with a container on the server"
    end
    defer(function()
        if rebuilt:getObjectIndex() ~= -1 then
            RenewableEnergy.PowerBank.remove(rebuilt)
        end
    end)
    return stateAt(args.bank)
end)

-- Loads -------------------------------------------------------------------------------------------

-- The watts each list of Specs.loads kinds in `args.sets` takes.
handler("loadWatts", function(_, args)
    local Loads = RenewableEnergy.Loads
    local watts = {}
    for i, names in ipairs(args.sets or {}) do
        local load = Loads.new()
        for _, name in ipairs(names) do
            Loads.add(load, name)
        end
        watts[i] = load.watts
    end
    return { watts = watts }
end)

-- What the load scan of the bank on the square at `args` finds: its watts and the count of each
-- kind.
handler("scanLoad", function(_, args)
    local square = squareAt(args)
    if not square then
        return nil, "the bank's square loaded on the server"
    end
    local load = RenewableEnergy.Loads.scan(square)
    local counts = {}
    for name, kind in pairs(load.kinds) do
        counts[name] = kind.count
    end
    return { watts = load.watts, counts = counts }
end)

-- Panels ------------------------------------------------------------------------------------------

-- Storms on panel records off the map: for each trial { source, hours, runs }, how many of `runs`
-- storms of `hours` cracked a fresh copy of `source` (Bank.stormCrack), and the modules of the last.
handler("stormCrack", function(_, args)
    local results = {}
    for i, trial in ipairs(args.trials or {}) do
        local count, source = 0, nil
        for _ = 1, trial.runs or 1 do
            source = { kind = trial.source.kind, material = trial.source.material, modules = {} }
            for j, module in ipairs(trial.source.modules) do
                source.modules[j] = { type = module.type, condition = module.condition }
            end
            if RenewableEnergy.Bank.stormCrack(source, trial.hours) then
                count = count + 1
            end
        end
        results[i] = { cracks = count, modules = source and source.modules or {} }
    end
    return { results = results }
end)

-- The modules the panel on the square at `args` records, and the overlays its tile shows.
handler("panelState", function(_, args)
    local PowerBank = mod()
    local panel = PowerBank.sourceOn(squareAt(args))
    if not panel then
        return nil, "the panel on the server"
    end
    return { modules = panel:getModData()[PowerBank.MODULES], overlays = overlaysOf(panel) }
end)

-- Snow `args.snow` deep on the panel at `args.source` in the record of the bank at `args.bank`, as
-- a night of snowfall leaves it, sent to the clients with the bank's status.
handler("setSnow", function(_, args)
    local record, _, missing = needRecord(args.bank)
    if not record then return nil, missing end
    local source = args.source and record:findSource(args.source.x, args.source.y, args.source.z)
    if not source then
        return nil, "the panel in the bank's record on the server"
    end
    source.snow = args.snow
    record:sendStatus()
    return stateOf(record)
end)

-- Gadgets -----------------------------------------------------------------------------------------

local function usesOf(container)
    local uses = {}
    for i = 0, (container and container:getItems():size() or 0) - 1 do
        uses[i + 1] = container:getItems():get(i):getCurrentUsesFloat()
    end
    return uses
end

-- What the solar battery charger on the square at `args` holds: its batteries' charges and the
-- watt-hours it keeps toward the next use.
handler("chargerState", function(_, args)
    local charger = RenewableEnergy.SolarCellCharger.findOn(squareAt(args))
    if not charger then
        return nil, "the solar battery charger on the server"
    end
    return { uses = usesOf(charger:getContainer()), storedWh = charger:getModData().RenewableEnergy_storedWh or 0 }
end)

-- Fills the solar battery charger on the square at `args` with `args.count` batteries at
-- `args.uses`, sent to the clients, and charges it for `args.hours` at the sun of the moment, then,
-- if `args.pass`, runs the pass over every charger for as long again. An empty battery leaves its
-- container on its next update (DrainableComboItem.update), so filling and charging happen in one
-- call. Answers the uses added, the charges after each, and flatWh: what an hour of the sun it
-- charged in gives a flat panel per rated watt, since the live weather sets it.
handler("cellCharge", function(_, args)
    local SolarCellCharger = RenewableEnergy.SolarCellCharger
    local charger = SolarCellCharger.findOn(squareAt(args))
    if not charger then
        return nil, "the solar battery charger on the server"
    end
    local container = charger:getContainer()
    for _ = 1, args.count do
        local battery = container:AddItem(SolarCellCharger.BATTERY)
        battery:setCurrentUsesFloat(args.uses)
        sendAddItemToContainer(container, battery)
    end
    local reply = { added = SolarCellCharger.charge(charger, args.hours), after = usesOf(container),
        flatWh = RenewableEnergy.Sun.panelWatts(1, "flat") }
    if args.pass then
        SolarCellCharger.chargeAll(args.hours)
        reply.afterPass = usesOf(container)
    end
    return reply
end)

-- Runs the garden light on the square at `args` for `args.hours` at the sun of the moment, from
-- `args.charge` Wh if given: the gadget pass may have run the light since it was placed. Answers
-- whether it is lit, its sprite and its charge in Wh.
handler("gardenLightUpdate", function(_, args)
    local SolarGardenLight = RenewableEnergy.SolarGardenLight
    local light = SolarGardenLight.findOn(squareAt(args))
    if not light then
        return nil, "the garden light on the server"
    end
    if args.charge then
        light:getModData()[SolarGardenLight.CHARGE_KEY] = args.charge
    end
    local lit = SolarGardenLight.update(light, args.hours)
    return { lit = lit, sprite = light:getTextureName(), charge = SolarGardenLight.getCharge(light) }
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
    local part = vehicle:getPartById(RenewableEnergy.VehicleBattery.PART)
    return part, part and part:getInventoryItem()
end

-- What the tests read of a vehicle: its battery, whether a maintainer is attached, whether its
-- engine runs.
local function vehicleState(vehicle)
    local _, battery = batteryOf(vehicle)
    return {
        battery = battery and { type = battery:getFullType(), uses = battery:getCurrentUsesFloat() } or nil,
        attached = RenewableEnergy.SolarMaintainer.isAttached(vehicle),
        running = vehicle:isEngineRunning(),
    }
end

-- Named apart from the arrow board tests' "vehicleState" (RenewableEnergyTestServerTrailer.lua):
-- one registry holds every handler, and the file loaded later wins.
handler("carState", function(_, args)
    local vehicle, missing = vehicleAt(args)
    if not vehicle then return nil, missing end
    return vehicleState(vehicle)
end)

-- Puts a new `args.type` in the vehicle's battery slot if given, empties it if `args.empty`, and
-- charges its battery to `args.uses` if given, sent to the clients.
handler("vehicleBattery", function(_, args)
    local vehicle, missing = vehicleAt(args.vehicle)
    if not vehicle then return nil, missing end
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
    return vehicleState(vehicle)
end)

-- An hour's worth, `args.hours`, of the maintainer on the vehicle at the sun of the moment, from a
-- battery at `args.uses`: the Wh it added, the charge after, the battery's capacity in Wh, and
-- flatWh as cellCharge answers it.
handler("maintainerCharge", function(_, args)
    local vehicle, missing = vehicleAt(args.vehicle)
    if not vehicle then return nil, missing end
    local _, battery = batteryOf(vehicle)
    battery:setCurrentUsesFloat(args.uses)
    local wh = RenewableEnergy.SolarMaintainer.charge(vehicle, args.hours)
    return { wh = wh, after = battery:getCurrentUsesFloat(), capacityWh = RenewableEnergy.Battery.nominalWh(battery),
        flatWh = RenewableEnergy.Sun.panelWatts(1, "flat") }
end)

-- The gadget pass over every loaded vehicle (GadgetCharging.chargeVehicles) for `args.hours`: the
-- vehicle's battery charge before and after.
handler("chargeVehicles", function(_, args)
    local vehicle, missing = vehicleAt(args.vehicle)
    if not vehicle then return nil, missing end
    local _, battery = batteryOf(vehicle)
    local before = battery:getCurrentUsesFloat()
    RenewableEnergy.GadgetCharging.chargeVehicles(args.hours)
    return { before = before, after = battery:getCurrentUsesFloat() }
end)

-- Vanilla's headlight update (Vehicles.Update.Headlight) for `args.minutes` with the engine off,
-- from a battery at `args.uses`: the share of a full charge it took.
handler("headlightDrain", function(_, args)
    local vehicle, missing = vehicleAt(args.vehicle)
    if not vehicle then return nil, missing end
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

-- Vanilla's alternator charging (Vehicles.Update.Battery) for `args.minutes` with the engine
-- running, from a battery at `args.uses`: the share of a full charge it added. The engine is
-- repaired and fuelled first, since it shuts down without fuel and stalls at random below half
-- condition, and switched off after.
handler("alternatorCharge", function(_, args)
    local vehicle, missing = vehicleAt(args.vehicle)
    if not vehicle then return nil, missing end
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

-- The arrow board trailer's battery box.
local function batteryBoxOf(trailer)
    local part = trailer:getPartById(RenewableEnergy.ArrowBoard.BATTERY_BOX)
    return part and part:getItemContainer()
end

-- What the clock test's fixtures hold, on the squares and vehicles `args` names, in Wh: the bank's,
-- the car battery's, the solar battery charger's in its cells and toward the next use, the garden
-- light's, and the trailer box battery's (-1 for none). Also the hour of the bank's status, the
-- world age of the bank's last pass and of now, and the watts the trailer's panels make in full sun.
local function gadgetCharges(args)
    local SolarCellCharger, Battery = RenewableEnergy.SolarCellCharger, RenewableEnergy.Battery
    local record = recordAt(args.bank)
    local car, trailer = vehicleAt(args.car), vehicleAt(args.trailer)
    local charger = SolarCellCharger.findOn(squareAt(args.charger))
    local light = RenewableEnergy.SolarGardenLight.findOn(squareAt(args.light))
    if not (record and car and trailer and charger and light) then
        return nil, "the clock test's bank, car, trailer, solar battery charger and garden light on the server"
    end
    local cellWh = charger:getModData().RenewableEnergy_storedWh or 0
    for _, uses in ipairs(usesOf(charger:getContainer())) do
        cellWh = cellWh + uses * SolarCellCharger.BATTERY_WH
    end
    local function whIn(battery)
        return Battery.getCharge(battery) * Battery.nominalWh(battery)
    end
    local _, carBattery = batteryOf(car)
    local boxed = batteryBoxOf(trailer):getItems()
    return {
        bank = record.charge * record.nominalWh, hour = record.status and record.status.hour or 0,
        bankPassAge = record.lastHour, age = getGameTime():getWorldAgeHours(),
        car = whIn(carBattery), charger = cellWh,
        light = RenewableEnergy.SolarGardenLight.getCharge(light),
        trailer = boxed:size() > 0 and whIn(boxed:get(0)) or -1,
        trailerWatts = RenewableEnergy.ArrowBoard.panelWatts(trailer),
    }
end

-- Readies the clock test's gadgets, half charged: a maintainer on the car, one deep cycle battery
-- in the trailer's box, which may have spawned stocked, four cells in the solar battery charger,
-- and the garden light empty. Answers their charges (gadgetCharges). The gadget pass runs first,
-- so that the clock's passes from here on cover no more than the time the clock moves.
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
