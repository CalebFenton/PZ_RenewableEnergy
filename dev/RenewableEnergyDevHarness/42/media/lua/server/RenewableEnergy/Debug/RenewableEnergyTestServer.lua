-- The authority's half of the bank and panel tests: fixtures only the server's bank system
-- can build, its passes, and its records, which a multiplayer client holds only copies of. Only
-- registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler
local overlaysOf, squareAt, bankRecordAt = PZHarness.Fixtures.overlaysOf, PZHarness.Fixtures.squareAt, Helpers.bankRecordAt

-- RenewableEnergyTest.forceRoll's handler: the authority's Chance.roll gives `args.rolls` until
-- the test ends (Helpers.forceRolls).
handler("forceRoll", function(_, args, defer)
    Helpers.forceRolls(defer, args.rolls)
    return {}
end)

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
    -- What the status doesn't show of each source's record.
    local records = {}
    for _, source in ipairs(record.sources) do
        table.insert(records, { x = source.x, y = source.y, z = source.z, kind = source.kind, blades = source.blades })
    end
    return {
        on = record.on == true, name = record.name or "", charge = record.charge,
        lastHour = record.lastHour, age = getGameTime():getWorldAgeHours(), calendarDay = getGameTime():getDay(),
        solarWhToday = record.solarWhToday, loadWhToday = record.loadWhToday,
        storedWh = record.charge * record.nominalWh, nominalWh = record.nominalWh, overloaded = record.overloaded == true,
        cycleDepth = record.cycleDepth, limitW = record:limitW(), drawW = record:drawW(),
        sources = #record.sources, batteries = #record.batteries, records = records,
        activated = bank ~= nil and bank:isActivated(), powered = square ~= nil and square:haveElectricity(),
        items = items, overlays = overlaysOf(bank), status = record:buildStatus(), watchers = Helpers.count(record.watchers),
    }
end

-- The state of the bank at `position`, or nil and what is missing, so that a test never indexes a
-- bank the server doesn't have.
local function stateAt(position)
    local record = bankRecordAt(position)
    if not record then
        return nil, "the bank's record on the server"
    end
    return stateOf(record)
end

-- Fixtures ---------------------------------------------------------------------------------------

-- RenewableEnergyTest.bank's handler: the bank the world places (WorldSpawns.placeBankWith), of the
-- Sprites field `args.kind` facing `args.facing` (S if nil), holding `args.items` with its
-- batteries at `args.charge`, and disconnected through the bank's own command when
-- `args.connected == false`. Answers the bank's position.
handler("placeBank", function(_, args, defer)
    local PowerBank, Battery = RenewableEnergy.PowerBank, RenewableEnergy.Battery
    local square = squareAt(args)
    if not square then
        return nil, "the bank's square loaded on the server"
    end
    local items = args.items or {}
    local sprite = RenewableEnergy.Sprites[args.kind][args.facing or "S"]
    local bank = RenewableEnergy.WorldSpawns.placeBankWith(square, sprite, function(container)
        for _, fullType in ipairs(items) do
            local item = container:AddItem(fullType)
            if item and Battery.isBattery(item) then
                Battery.setCharge(item, args.charge or 1)
            end
        end
    end)
    -- Whatever bank stands on the square when the test ends: a chunk loaded again, or a bank
    -- rebuilt, brings a new object.
    defer(function()
        local current = PowerBank.findOn(squareAt(args))
        if current then
            current:getSquare():transmitRemoveItemFromSquare(current)
        end
    end)
    if bank:getContainer():getItems():size() ~= #items then
        return nil, "every item of " .. table.concat(items, ", ") .. " in the bank"
    end
    local position = PowerBank.positionOf(bank)
    if args.connected == false then
        local ok, reason = PowerBank.perform(nil, "setBankConnected", { bank = position, connected = false })
        if not ok then
            return nil, "the bank disconnected (" .. tostring(reason) .. ")"
        end
    end
    return position
end)

-- RenewableEnergyTest.panel's handler, for any source tile. A panel mount is placed from its item
-- the way the moveables cursor places it (WorldSpawns.placePanel), carrying `args.modules`. A wind
-- charger is built in place and a treadmill is vanilla furniture, neither from an item of the mod,
-- so their tile is put down bare, unless `args.built` builds the charger as its build-menu entity,
-- as the world builds its finds (WorldSpawns.buildEntity); its blades come broken when `args.broken`. A
-- treadmill's comes wired by its wiring's owner when `args.wired`. Answers whether the source
-- connected and the refusal.
handler("placePanel", function(player, args, defer)
    local PowerBank, Treadmill, TreadmillSource = RenewableEnergy.PowerBank, RenewableEnergy.Treadmill,
        RenewableEnergy.TreadmillSource
    local square = squareAt(args)
    if not square then
        return nil, "the panel's square loaded on the server"
    end
    local panel
    if getSprite(args.sprite):getProperties():has("CustomItem") then
        RenewableEnergy.WorldSpawns.placePanel(square, args.sprite, args.modules)
        panel = RenewableEnergy.findObjectOn(square, function(object) return RenewableEnergy.Sprites.nameOf(object) == args.sprite end)
        if not panel then
            return nil, "a placed " .. args.sprite .. " on the server"
        end
    elseif args.built then
        panel = RenewableEnergy.WorldSpawns.buildEntity(square, args.sprite, RenewableEnergy.Wind.OnCreate)
    else
        panel = PZHarness.Fixtures.newTile(square, args.sprite)
        -- As placing does: the mod's OnObjectAdded handlers see the new tile.
        triggerEvent("OnObjectAdded", panel)
    end
    if args.broken then
        RenewableEnergy.WindSource.setBroken(panel, true)
    end
    defer(function()
        if panel:getObjectIndex() ~= -1 then
            -- A wired treadmill taken away drops its wire on its square (TreadmillSource.unwire),
            -- which the tests that follow would find lying about; unwired first, it goes to the
            -- character, whose inventory the next test empties.
            if Treadmill.isWiredTile(panel) then
                TreadmillSource.unwire(panel, player)
            end
            -- Not "safely": that refuses one tile of a multi-tile object (a treadmill's) placed alone.
            square:transmitRemoveItemFromSquare(panel, false)
        end
    end)
    if args.wired then
        TreadmillSource.wire(panel)
    end
    if not args.bank then
        return { connected = false }
    end
    local connected, reason = PowerBank.perform(player, "connectSource",
        { bank = args.bank, source = PowerBank.positionOf(panel) })
    return { connected = connected, reason = reason }
end)

-- Takes away, when the test ends, whatever source the test builds at x, y, z by other means (the
-- build menu), on whichever tile its OnCreate left it.
handler("sourceTrack", function(_, args, defer)
    defer(function()
        local square = squareAt(args)
        local source = square and RenewableEnergy.Sources.findOn(square)
        if source then
            PZHarness.Fixtures.removePlaced(source)
        end
    end)
    return {}
end)

-- A Base.Generator plugged in on the square at `args`, fuelled with `args.fuel` litres (full
-- unless given), started as a player starts one if `args.running`, with a failsafe tile on its
-- square if `args.failsafe`. Both are removed when the test ends.
handler("placeGenerator", function(_, args, defer)
    local square = squareAt(args)
    if not square then
        return nil, "the generator's square loaded on the server"
    end
    local generator = IsoGenerator.new(instanceItem("Base.Generator"), square:getCell(), square)
    defer(function() PZHarness.Fixtures.removePlaced(generator) end)
    generator:setConnected(true)
    generator:setFuel(args.fuel or 10)
    generator:setCondition(100)
    if args.failsafe then
        local failsafe = PZHarness.Fixtures.newTile(square, RenewableEnergy.Sprites.failsafe)
        defer(function() PZHarness.Fixtures.removePlaced(failsafe) end)
    end
    if args.running then
        ISActivateGenerator.complete({ generator = generator, activate = true })
    end
    return {}
end)

-- A wooden floor one storey above the square at `args`, as a player roofs a yard: vanilla's
-- addFloor rechecks the roof below it (IsoCell.checkHaveRoof), which takes the square's exterior
-- flag away. Answers whether the square below is still outdoors. Removed when the test ends.
handler("roofOver", function(_, args, defer)
    local above = getCell():createNewGridSquare(args.x, args.y, args.z + 1, true)
    if not above then
        return nil, "the square above loaded on the server"
    end
    local floor = above:addFloor("carpentry_02_58")
    defer(function()
        PZHarness.Fixtures.removePlaced(floor)
        getCell():checkHaveRoof(args.x, args.y)
    end)
    return { outside = squareAt(args):isOutside() }
end)

-- A ring of `args.sprite` tiles on the eight squares around (x, y) on level `args.level`, the
-- squares made where that level has none, as building upstairs makes them. Answers how many went
-- down. Removed when the test ends.
handler("ringOfTiles", function(_, args, defer)
    local placed = 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local x, y = args.x + dx, args.y + dy
                local square = getSquare(x, y, args.level) or getCell():createNewGridSquare(x, y, args.level, true)
                if square then
                    local tile = PZHarness.Fixtures.newTile(square, args.sprite)
                    defer(function() PZHarness.Fixtures.removePlaced(tile) end)
                    placed = placed + 1
                end
            end
        end
    end
    return { placed = placed }
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
        local record, bank = bankRecordAt(args.bank)
        if not bank then
            return nil, "the bank's record and tile on the server"
        end
        return fn(record, bank, args, player, defer)
    end)
end

-- RenewableEnergyTest.setCharge's handler: every battery in the bank at `args.bank` charged to
-- `args.charge` by the batteries' own setter and sent, then the bank reads them again, as it does
-- after anything changed its container. Answers the bank's state.
onBank("setCharge", function(record, bank, args)
    local Battery = RenewableEnergy.Battery
    local items = bank:getContainer():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if Battery.isBattery(item) then
            Battery.setCharge(item, args.charge)
            sendItemStats(item)
        end
    end
    record:recount()
    record:sendStatus()
    return stateOf(record)
end)

-- Takes `args.points` of wear off the first `args.type` in the bank at `args.bank` by the mod's own
-- Wear.take, which keeps a fraction pending on the item, and sends it. Answers the bank's state.
onBank("takePartWear", function(record, bank, args)
    local item = bank:getContainer():getFirstType(args.type)
    if not item then
        return nil, "a " .. args.type .. " in the bank"
    end
    if RenewableEnergy.Wear.take(item, args.points) then
        sendItemStats(item)
    end
    return stateOf(record)
end)

-- Weather with snow falling hard.
local SNOWING = { cloud = 1, fog = 0, rain = 0, snowing = true, groundSnow = 0 }

-- RenewableEnergyTest.bankPass's handler: the bank system's own pass of the bank at `args.bank`
-- (BankSystem.updateBank) over the last `args.hours` (1 if nil), in the context the system builds
-- for it with the sky the test sets: `args.light` W/m² on every mount, with the sun above the
-- horizon only when there is light; snow falling at full strength if `args.snowing`, else clear;
-- `args.airC` °C (mild if nil); `args.stormHours` of storm and a wind of `args.windKph`. A bank
-- whose chunk is unloaded runs too. Answers the bank's state after the pass.
handler("bankPass", function(_, args)
    local record = bankRecordAt(args.bank)
    if not record then
        return nil, "the bank's record on the server"
    end
    local BankSystem = RenewableEnergy.BankSystem
    local light = args.light or 0
    local function irradiance() return light end
    record.lastHour = getGameTime():getWorldAgeHours() - (args.hours or 1)
    BankSystem.updateBank(record, function(hours)
        local context = BankSystem.passContext(hours)
        context.irradiance, context.clearIrradiance = irradiance, irradiance
        context.elevation = light > 0 and 45 or -10
        context.weather = args.snowing and SNOWING or RenewableEnergy.Sun.CLEAR_WEATHER
        context.precipitation = args.snowing and 1 or 0
        context.airC = args.airC or 25
        context.stormHours = args.stormHours or 0
        context.windKph = args.windKph or 0
        return context
    end)
    return stateOf(record)
end)

-- The bank at `args.bank` saved and loaded again, as quitting and continuing the game leaves it:
-- the Global Object System saves only a record's SAVED_FIELDS (SGlobalObject.save), so every
-- other field goes, and on load the bank system builds its records from what was saved
-- (BankSystem:initLuaObjects). Answers what the running generator at `args.generator` delivers
-- (GasLines.loadOf) before and after, and the bank's charger watts.
handler("saveAndLoadBank", function(_, args)
    local record = bankRecordAt(args.bank)
    local square = squareAt(args.generator)
    local generator = square and square:getGenerator()
    if not (record and generator) then
        return nil, "the bank's record and the generator on the server"
    end
    local GasLines = RenewableEnergy.GasLines
    local reply = { loadBefore = GasLines.loadOf(generator), chargerW = record:chargerMaxW() }
    local saved, gone = {}, {}
    for _, key in ipairs(RenewableEnergy.Bank.SAVED_FIELDS) do
        saved[key] = true
    end
    for key in pairs(record) do
        if not saved[key] then
            table.insert(gone, key)
        end
    end
    for _, key in ipairs(gone) do
        record[key] = nil
    end
    RenewableEnergy.BankSystem.instance:initLuaObjects()
    reply.loadAfter = GasLines.loadOf(generator)
    return reply
end)

-- Puts the last pass of the bank at `args.bank` `args.hours` before now, as a bank looks after
-- that long between passes; answers its state.
onBank("ageBank", function(record, _, args)
    record.lastHour = getGameTime():getWorldAgeHours() - args.hours
    return stateOf(record)
end)

-- RenewableEnergyTest.applyLoad's handler: the window tests' load, which is about how the window
-- shows a load of given kinds, not how a pass measures one; answers the bank's state.
onBank("applyLoad", function(record, _, args)
    local Loads = RenewableEnergy.Loads
    local load = Loads.new()
    for _, appliance in ipairs(args.appliances or {}) do
        Loads.add(load, appliance.name, appliance.watts)
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
    local item = bank:getContainer():getFirstType(args.type)
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
    local item = container:getFirstType(args.type)
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
    local _, object = bankRecordAt(bank)
    return object and object:getContainer():getFirstType(item.type)
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

-- Takes the tile of `args.sprite` on the square at `args` away, as a player picking it up does,
-- such as a fridge out of a bank's reach.
handler("removeTile", function(_, args)
    local object, missing = Helpers.objectAt(args)
    if not object then
        return nil, missing
    end
    PZHarness.Fixtures.removePlaced(object)
    return {}
end)

-- Takes the bank at `args.bank` away the way picking it up or destroying it does.
onBank("removeBank", function(_, bank, args)
    bank:getSquare():transmitRemoveItemFromSquare(bank)
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
            Helpers.removeFloorItem(square, object)
        end
    end
    return { items = items }
end)

-- Takes the containers off the bank at `args.bank`, as a bank tile a map or a placement that failed
-- halfway leaves, then loads its square the way its chunk loading does, which rebuilds it. Answers
-- the rebuilt bank's state; placeBank's cleanup takes the rebuilt bank away.
onBank("rebuildBank", function(_, bank, args)
    bank:removeAllContainers()
    local square = squareAt(args.bank)
    MapObjects.loadGridSquare(square)
    local rebuilt = RenewableEnergy.PowerBank.findOn(square)
    if not (rebuilt and rebuilt ~= bank and rebuilt:getContainer()) then
        return nil, "a rebuilt bank with a container on the server"
    end
    return stateAt(args.bank)
end)

-- Loads -------------------------------------------------------------------------------------------

-- What the load scan of the bank on the square at `args` finds, as the payer there: its watts and
-- the count of each kind.
handler("scanLoad", function(_, args)
    local square = squareAt(args)
    if not square then
        return nil, "the bank's square loaded on the server"
    end
    local Payers = RenewableEnergy.Payers
    local payer = { x = args.x, y = args.y, z = args.z, key = RenewableEnergy.PlaceTracker.key(args.x, args.y, args.z) }
    local load = RenewableEnergy.Loads.scan(square, payer, Payers.running())
    local counts = {}
    for name, kind in pairs(load.kinds) do
        counts[name] = kind.count
    end
    return { watts = load.watts, counts = counts }
end)

-- Where the stand-in for another mod's appliance stands, its kind and the fuel an hour it draws,
-- read by the consumer drawAt adds to the scan (Loads.addConsumer) once, as a --stay rerun loads
-- this file again and the mod's consumers stay.
RenewableEnergyTestConsumer = RenewableEnergyTestConsumer or {}

-- The floor of the square at `args` draws `args.fuel` an hour as the kind `args.kind` until the
-- test ends, as another mod's appliance that told the bank's scan what it draws.
handler("drawAt", function(_, args, defer)
    local stub = RenewableEnergyTestConsumer
    if not stub.added then
        stub.added = true
        RenewableEnergy.Loads.addConsumer(function(object)
            local at = stub.at
            local square = at and object:getSquare()
            if square and square:getX() == at.x and square:getY() == at.y and square:getZ() == at.z
                    and object == square:getFloor() then
                return at.kind, at.fuel
            end
            return nil
        end)
    end
    stub.at = { x = args.x, y = args.y, z = args.z, kind = args.kind, fuel = args.fuel }
    defer(function() stub.at = nil end)
    return {}
end)

-- Panels ------------------------------------------------------------------------------------------

-- A panel record off the map, as `args` lists it ({ kind, material, modules }).
local function panelRecord(args)
    local source = { kind = args.kind, material = args.material, modules = {} }
    for i, module in ipairs(args.modules or {}) do
        source.modules[i] = { type = module.type, condition = module.condition }
    end
    return source
end

-- PanelSource.stormChance for each trial { source, hours }, at the save's storm options.
handler("stormChances", function(_, args)
    local chances = {}
    for i, trial in ipairs(args.trials) do
        chances[i] = RenewableEnergy.PanelSource.stormChance(panelRecord(trial.source), trial.hours)
    end
    return { chances = chances }
end)

-- A storm (PanelSource.stormCrack) on a panel record off the map for each trial { source, hours,
-- roll }, roll a number, or "under" or "at" for a roll just under or at the trial's own
-- stormChance; worked out here, so the roll is exactly the chance the crack compares it with. A
-- storm draws that roll and, when it cracks, one more to pick the module (the first, at 0).
-- Answers whether each cracked and the modules after.
handler("stormCrack", function(_, args, defer)
    local PanelSource = RenewableEnergy.PanelSource
    local results = {}
    for i, trial in ipairs(args.trials) do
        local source = panelRecord(trial.source)
        local roll = Helpers.trialRoll(trial.roll, PanelSource.stormChance(source, trial.hours))
        local restore = Helpers.forceRolls(defer, { roll, 0 })
        results[i] = { cracked = PanelSource.stormCrack(source, trial.hours), modules = source.modules }
        restore()
    end
    return { results = results }
end)

-- The modules the panel on the square at `args` records, and the overlays its tile shows.
handler("panelState", function(_, args)
    local PowerBank = RenewableEnergy.PowerBank
    local panel = RenewableEnergy.Sources.findOn(squareAt(args))
    if not panel then
        return nil, "the panel on the server"
    end
    return { modules = panel:getModData()[PowerBank.MODULES_KEY], overlays = overlaysOf(panel) }
end)

-- `args.hours` of storm over the world's panels that no bank runs (PanelStorms.pass), at the save's
-- storm options. Answers the modules each panel at `args.panels` records after.
handler("panelStorm", function(_, args)
    RenewableEnergy.PanelStorms.pass(args.hours)
    local modules = {}
    for i, position in ipairs(args.panels) do
        local panel = RenewableEnergy.Sources.findOn(squareAt(position))
        if not panel then
            return nil, "the panel at " .. position.x .. "," .. position.y .. "," .. position.z .. " on the server"
        end
        modules[i] = panel:getModData()[RenewableEnergy.PowerBank.MODULES_KEY]
    end
    return { modules = modules }
end)
