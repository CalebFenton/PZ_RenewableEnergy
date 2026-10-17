-- The authority's half of the bank, panel and gadget tests: fixtures only the server's bank system
-- can build, its passes, and its records, which a multiplayer client holds only copies of. Only
-- registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler
local overlaysOf, squareAt, vehicleAt = Helpers.overlaysOf, Helpers.squareAt, Helpers.vehicleAt

-- The server's record of the bank at `position`, and its tile.
local function recordAt(position)
    local record = position and RenewableEnergy.PowerBank.serverSystem:getLuaObjectAt(position.x, position.y, position.z)
    return record, record and record:getIsoObject()
end

local function firstOfType(container, fullType)
    return container and container:getFirstType(fullType)
end

-- What the tests read of a bank on the authority: its record, the status it would send a watching
-- player now, how many players watch it, its tile and the parts in it, and the world age now and at
-- its last pass.
local function stateOf(record)
    local bank = record:getIsoObject()
    local square = bank and bank:getSquare()
    local items = {}
    local container = bank and bank:getContainer()
    for i = 0, (container and container:getItems():size() or 0) - 1 do
        local item = container:getItems():get(i)
        table.insert(items, { type = item:getFullType(), id = item:getID(), condition = item:getCondition(),
            uses = item:getCurrentUsesFloat() })
    end
    local watchers = 0
    for _ in pairs(record.watchers or {}) do
        watchers = watchers + 1
    end
    return {
        on = record.on == true, name = record.name or "", charge = record.charge,
        lastHour = record.lastHour, age = getGameTime():getWorldAgeHours(),
        solarWhToday = record.solarWhToday, loadWhToday = record.loadWhToday,
        storedWh = record.charge * record.nominalWh, nominalWh = record.nominalWh, overloaded = record.overloaded == true,
        cycleDepth = record.cycleDepth, limitW = record:limitW(), drawW = record:drawW(),
        sources = #record.sources, batteries = #record.batteries,
        activated = bank ~= nil and bank:isActivated(), powered = square ~= nil and square:haveElectricity(),
        items = items, overlays = overlaysOf(bank), status = record:buildStatus(), watchers = watchers,
    }
end

-- The state of the bank at `position`, or nil and what is missing, so that a test never indexes a
-- bank the server doesn't have.
local function stateAt(position)
    local record = recordAt(position)
    if not record then
        return nil, "the bank's record on the server"
    end
    return stateOf(record)
end

-- A bank pass's context with fixed, clear weather: `light` W/m² on every mount, the sun above the
-- horizon only when there is light (a sun below it reads as night), and `stormHours` of storm.
local function passContext(light, stormHours, windKph)
    local function irradiance() return light end
    return {
        weather = RenewableEnergy.Sun.CLEAR_WEATHER, precipitation = 0, airC = 25, elevation = light > 0 and 45 or -10,
        stormHours = stormHours or 0, irradiance = irradiance, clearIrradiance = irradiance, windKph = windKph or 0,
    }
end

-- Fixtures ---------------------------------------------------------------------------------------

-- RenewableEnergyTest.bank's handler. Answers with the bank's position.
handler("placeBank", function(_, args, defer)
    local PowerBank, Battery = RenewableEnergy.PowerBank, RenewableEnergy.Battery
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
    -- PowerBank.place makes an installed, connected bank; a player's placed one starts unconnected.
    if args.connected == false then
        bank:setConnected(false)
        local luaObject = PowerBank.serverSystem:getLuaObjectOnSquare(square)
        if luaObject then
            luaObject.connected = false
        end
    end
    local position = PowerBank.positionOf(bank)
    PowerBank.perform(nil, "refresh", { bank = position })
    if not PowerBank.serverSystem:getLuaObjectOnSquare(square) then
        return nil, "a bank the server's bank system registered"
    end
    return position
end)

-- RenewableEnergyTest.panel's handler, for any source tile: a treadmill's comes wired when
-- `args.wired`. Answers whether the source connected and the refusal.
handler("placePanel", function(player, args, defer)
    local PowerBank = RenewableEnergy.PowerBank
    local square = squareAt(args)
    if not square then
        return nil, "the panel's square loaded on the server"
    end
    local panel = IsoObject.new(square, args.sprite, "RenewableEnergy")
    if args.modules then
        panel:getModData()[PowerBank.MODULES] = args.modules
    end
    if args.wired then
        panel:getModData()[RenewableEnergy.Treadmill.WIRED] = true
    end
    square:AddTileObject(panel)
    defer(function()
        if panel:getObjectIndex() ~= -1 then
            -- A wired treadmill taken away drops its wire (TreadmillSource.unwire), which the
            -- tests that follow would find lying about.
            panel:getModData()[RenewableEnergy.Treadmill.WIRED] = nil
            -- Not "safely": that refuses one tile of a multi-tile object (a treadmill's) placed alone.
            square:transmitRemoveItemFromSquare(panel, false)
        end
    end)
    if isServer() then
        panel:transmitCompleteItemToClients()
    end
    -- As the moveables cursor's placement does: the mod's OnObjectAdded draws the panel's cracks.
    triggerEvent("OnObjectAdded", panel)
    if not args.bank then
        return { connected = false }
    end
    local connected, reason = PowerBank.perform(player, "connectSource",
        { bank = args.bank, source = PowerBank.positionOf(panel) })
    return { connected = connected, reason = reason }
end)

-- A Base.Generator plugged in on the square at `args`, fuelled with `args.fuel` litres (full
-- unless given), running if `args.running`, with a failsafe tile beside it if `args.failsafe`.
-- Removed, switched off first, when the test ends.
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
    generator:setFuel(args.fuel or 10)
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

-- Banks ------------------------------------------------------------------------------------------

-- The server's record of the bank at `args` (see stateOf).
handler("bankState", function(_, args)
    return stateAt(args)
end)

-- Registers the handler `name` on the bank at `args.bank`: `fn(record, bank, args, player, defer)`
-- runs once the server's record of it and its tile are found.
local function onBank(name, fn)
    handler(name, function(player, args, defer)
        local record, bank = recordAt(args.bank)
        if not bank then
            return nil, "the bank's record and tile on the server"
        end
        return fn(record, bank, args, player, defer)
    end)
end

-- RenewableEnergyTest.bankSet's handler; answers the bank's state.
onBank("bankSet", function(record, bank, args)
    for key, value in pairs(args.fields or {}) do
        record[key] = value
    end
    if args.writeBatteries and bank:getContainer() then
        record:writeBatteries(bank:getContainer(), false)
    end
    return stateOf(record)
end)

-- RenewableEnergyTest.bankPass's handler; answers the bank's state after the pass.
onBank("bankPass", function(record, _, args)
    record:update(args.hours or 1, passContext(args.light or 0, args.stormHours, args.windKph))
    return stateOf(record)
end)

-- Puts the last pass of the bank at `args.bank` `args.hours` before now, as a bank looks after
-- that long between passes; answers its state.
onBank("ageBank", function(record, _, args)
    record.lastHour = getGameTime():getWorldAgeHours() - args.hours
    return stateOf(record)
end)

-- RenewableEnergyTest.applyLoad's handler; answers the bank's state.
onBank("applyLoad", function(record, _, args)
    local Loads = RenewableEnergy.Loads
    local load = Loads.new()
    for _, name in ipairs(args.names or {}) do
        Loads.add(load, name)
    end
    record.loadW, record.loadByKind = load.watts, Loads.byKind(load)
    record:checkOverload()
    record:switchGenerator()
    record:sendStatus()
    return stateOf(record)
end)

-- RenewableEnergyTest.setPartCondition's handler, which sends the item to the clients; answers the
-- bank's state.
onBank("setPartCondition", function(record, bank, args)
    local item = firstOfType(bank:getContainer(), args.type)
    if not item then
        return nil, "a " .. tostring(args.type) .. " in the bank on the server"
    end
    RenewableEnergy.Wear.setCondition(item, args.condition)
    sendItemStats(item)
    if args.repaired then
        item:setHaveBeenRepaired(args.repaired)
        item:syncItemFields()
    end
    if args.recount then
        record:recount()
        record:sendStatus()
    end
    return stateOf(record)
end)

-- Takes the first `args.type` out of the bank at `args.bank`, past the bank's own commands, as a
-- part that disappeared would.
onBank("removePart", function(record, bank, args)
    local container = bank:getContainer()
    local item = firstOfType(container, args.type)
    if not item then
        return nil, "a " .. tostring(args.type) .. " in the bank on the server"
    end
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    return stateOf(record)
end)

-- The first `item.type` the server's character carries, or with `item.inBank` the first in the bank
-- at `bank`: the item a client's command would name by id, found in the call's turn, so that the
-- call needn't wait for an earlier answer to learn the id.
local function itemFor(player, item, bank)
    if not item.inBank then
        return player:getInventory():getFirstTypeRecurse(item.type)
    end
    local _, object = recordAt(bank)
    return object and firstOfType(object:getContainer(), item.type)
end

-- Runs the bank system's command `args.command` with `args.args` as the server's character, the
-- way a timed action's complete() does, with `args.args.itemId` the id of `args.item` (itemFor) if
-- given. Answers whether it did, why not, and the character's Electricity XP before and after.
handler("perform", function(player, args)
    local commandArgs = args.args
    if args.item then
        local item = itemFor(player, args.item, commandArgs.bank)
        if not item then
            return nil, "a " .. tostring(args.item.type) .. (args.item.inBank and " in the bank" or " on the character")
                .. " on the server"
        end
        commandArgs.itemId = item:getID()
    end
    local xp = player:getXp():getXP(Perks.Electricity)
    local ok, reason = RenewableEnergy.PowerBank.perform(player, args.command, commandArgs)
    return { ok = ok == true, reason = reason, xpBefore = xp, xpAfter = player:getXp():getXP(Perks.Electricity) }
end)

-- Finishes a Rename action on the bank at `args.bank` as the server's character, the way the server
-- finishes a client's timed action (ActionManager.update calls complete()). Answers whether it did.
onBank("completeRename", function(_, bank, args, player)
    local Action = RenewableEnergyAction
    return { done = Action:new(player, Action.RENAME, nil, bank, nil, nil, args.name):complete() == true }
end)

-- Finishes a whole Run on Treadmill on the wired treadmill tile at `args` as the server's
-- character, the way the server finishes a client's action (complete()). Answers whether it
-- settled, and the character's Fitness XP and endurance before and after.
handler("completeTreadmillRun", function(player, args)
    local tile = RenewableEnergy.findObjectOn(squareAt(args), RenewableEnergy.Treadmill.isWiredTile)
    if not tile then
        return nil, "a wired treadmill on the server"
    end
    local stats, xp = player:getStats(), player:getXp()
    local reply = { xpBefore = xp:getXP(Perks.Fitness), enduranceBefore = stats:get(CharacterStat.ENDURANCE) }
    reply.done = RenewableEnergyTreadmillAction:new(player, tile):complete() == true
    reply.xpAfter, reply.enduranceAfter = xp:getXP(Perks.Fitness), stats:get(CharacterStat.ENDURANCE)
    return reply
end)

-- The bank part's wear over `args.hours` hours on and `args.overloads` overloads, from the
-- conditions in `args.conditions` (full type to condition): the condition each type lost.
onBank("wearParts", function(record, bank, args)
    local Wear = RenewableEnergy.Wear
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
onBank("cycleDay", function(record, bank, args)
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
onBank("powerUp", function(record)
    record:powerUp()
    return stateOf(record)
end)

-- Takes the bank at `args.bank` away the way picking it up or destroying it does.
onBank("removeBank", function(_, bank, args)
    RenewableEnergy.PowerBank.remove(bank)
    local square = squareAt(args.bank)
    return { powered = square:haveElectricity(),
        registered = RenewableEnergy.PowerBank.serverSystem:getLuaObjectOnSquare(square) ~= nil }
end)

-- Takes the items lying on the squares `args.squares` ({ x, y, z } each) off the floor, as a player
-- picking them up would leave none behind, and answers them: { { type, uses, modData }, ... },
-- uses for drainable items, modData's plain values.
handler("takeFloorItems", function(_, args)
    local items = {}
    for _, at in ipairs(args.squares or {}) do
        local square = squareAt(at)
        if not square then
            return nil, "the square " .. at.x .. "," .. at.y .. " loaded on the server"
        end
        local objects = square:getWorldObjects()
        for i = objects:size() - 1, 0, -1 do
            local object = objects:get(i)
            local item = object:getItem()
            local modData = {}
            for key, value in pairs(item:getModData()) do
                if type(value) ~= "table" then
                    modData[key] = value
                end
            end
            table.insert(items, { type = item:getFullType(), modData = modData,
                uses = instanceof(item, "DrainableComboItem") and item:getCurrentUsesFloat() or nil })
            square:transmitRemoveItemFromSquare(object)
        end
    end
    return { items = items }
end)

-- Takes the containers off the bank at `args.bank`, as a bank tile a map or a placement that failed
-- halfway leaves, then loads its square the way its chunk loading does, which rebuilds it. Answers
-- the rebuilt bank's state. placeBank's cleanup removes only the tile it placed, so the rebuilt one
-- is removed when the test ends.
onBank("rebuildBank", function(_, bank, args, _, defer)
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
-- storms of `hours` cracked a fresh copy of `source` (PanelSource.stormCrack), and the modules of the last.
handler("stormCrack", function(_, args)
    local results = {}
    for i, trial in ipairs(args.trials or {}) do
        local count, source = 0, nil
        for _ = 1, trial.runs or 1 do
            source = { kind = trial.source.kind, material = trial.source.material, modules = {} }
            for j, module in ipairs(trial.source.modules) do
                source.modules[j] = { type = module.type, condition = module.condition }
            end
            if RenewableEnergy.PanelSource.stormCrack(source, trial.hours) then
                count = count + 1
            end
        end
        results[i] = { cracks = count, modules = source and source.modules or {} }
    end
    return { results = results }
end)

-- The modules the panel on the square at `args` records, and the overlays its tile shows.
handler("panelState", function(_, args)
    local PowerBank = RenewableEnergy.PowerBank
    local panel = RenewableEnergy.Sources.on(squareAt(args))
    if not panel then
        return nil, "the panel on the server"
    end
    return { modules = panel:getModData()[PowerBank.MODULES], overlays = overlaysOf(panel) }
end)

-- Snow `args.snow` deep on the panel at `args.source` in the record of the bank at `args.bank`, as
-- a night of snowfall leaves it, sent to the clients with the bank's status.
onBank("setSnow", function(record, _, args)
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

-- The watt-hours the solar battery charger keeps toward the next use.
local function storedWh(charger)
    return charger:getModData()[RenewableEnergy.SolarCellCharger.STORED_KEY] or 0
end

-- What the solar battery charger on the square at `args` holds: its batteries' charges and the
-- watt-hours it keeps toward the next use.
handler("chargerState", function(_, args)
    local charger = RenewableEnergy.SolarCellCharger.findOn(squareAt(args))
    if not charger then
        return nil, "the solar battery charger on the server"
    end
    return { uses = usesOf(charger:getContainer()), storedWh = storedWh(charger) }
end)

-- Fills the solar battery charger on the square at `args` with `args.count` batteries at
-- `args.uses` (as AddItem makes them, full, if nil), sent to the clients, and charges it for
-- `args.hours` at the sun of the moment, then, if `args.pass`, runs the pass over every charger for
-- as long again. An empty battery leaves its container on its next update
-- (DrainableComboItem.update), so filling and charging happen in one call. Answers the uses added,
-- the charges after each, `full` (every battery at its whole maximum of uses, which the float
-- can't tell), the Wh kept toward the next use, and flatWh: what an hour of the sun it charged in
-- gives a flat panel per rated watt, since the live weather sets it.
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
    local reply = { added = SolarCellCharger.charge(charger, args.hours), after = usesOf(container),
        flatWh = RenewableEnergy.Sun.panelWatts(1, "flat") }
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

-- Registers the handler `name` on the vehicle `args.vehicle` names (RenewableEnergyTest.vehicleArgs):
-- `fn(vehicle, args)` runs once it is found.
local function onCar(name, fn)
    handler(name, function(_, args)
        local vehicle, missing = vehicleAt(args.vehicle)
        if not vehicle then
            return nil, missing
        end
        return fn(vehicle, args)
    end)
end

-- Puts a new `args.type` in the vehicle's battery slot if given, empties it if `args.empty`, and
-- charges its battery to `args.uses` if given, sent to the clients.
onCar("vehicleBattery", function(vehicle, args)
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

-- `args.hours` of the maintainer on the vehicle at the sun of the moment, from a battery at
-- `args.uses`: the Wh it added, the charge after, the battery's capacity in Wh, and flatWh as
-- cellCharge answers it.
onCar("maintainerCharge", function(vehicle, args)
    local _, battery = batteryOf(vehicle)
    battery:setCurrentUsesFloat(args.uses)
    local wh = RenewableEnergy.SolarMaintainer.charge(vehicle, args.hours)
    return { wh = wh, after = battery:getCurrentUsesFloat(), capacityWh = RenewableEnergy.Battery.nominalWh(battery),
        flatWh = RenewableEnergy.Sun.panelWatts(1, "flat") }
end)

-- The gadget pass over every loaded vehicle (GadgetCharging.chargeVehicles) for `args.hours`: the
-- vehicle's battery charge before and after.
onCar("chargeVehicles", function(vehicle, args)
    local _, battery = batteryOf(vehicle)
    local before = battery:getCurrentUsesFloat()
    RenewableEnergy.GadgetCharging.chargeVehicles(args.hours)
    return { before = before, after = battery:getCurrentUsesFloat() }
end)

-- Vanilla's headlight update (Vehicles.Update.Headlight) for `args.minutes` with the engine off,
-- from a battery at `args.uses`: the share of a full charge it took.
onCar("headlightDrain", function(vehicle, args)
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
onCar("lightbarDrain", function(vehicle, args)
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
-- repaired and fuelled first, since it shuts down without fuel and stalls at random below half
-- condition, and switched off after.
onCar("alternatorCharge", function(vehicle, args)
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
-- light's, and the trailer box battery's (-1 for none). Also the world age of the bank's last pass
-- and of now, and the watts the trailer's panels make in full sun.
local function gadgetCharges(args)
    local SolarCellCharger, Battery = RenewableEnergy.SolarCellCharger, RenewableEnergy.Battery
    local record = recordAt(args.bank)
    local car, trailer = vehicleAt(args.car), vehicleAt(args.trailer)
    local charger = SolarCellCharger.findOn(squareAt(args.charger))
    local light = RenewableEnergy.SolarGardenLight.findOn(squareAt(args.light))
    if not (record and car and trailer and charger and light) then
        return nil, "the clock test's bank, car, trailer, solar battery charger and garden light on the server"
    end
    local cellWh = storedWh(charger)
    for _, uses in ipairs(usesOf(charger:getContainer())) do
        cellWh = cellWh + uses * SolarCellCharger.BATTERY_WH
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
        light = RenewableEnergy.SolarGardenLight.getCharge(light),
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
