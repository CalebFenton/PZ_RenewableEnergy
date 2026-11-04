-- The authority's half of the bank and panel tests: fixtures only the server's bank system
-- can build, and its passes, which a multiplayer client holds only copies of.

require "PZHarness/ServerHandlers"
require "PZHarness/ServerFixtures"
require "PZHarness/ServerRecords"
require "PZHarness/Rolls"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local Items = require "cf_commonlib/Items"
local Squares = require "cf_commonlib/Squares"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local ModFixtures = require "RenewableEnergy/Debug/RenewableEnergyFixtures"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local BankSystem = require "RenewableEnergy/PowerBank/BankSystem"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local Loads = require "RenewableEnergy/PowerBank/Loads"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local PanelSource = require "RenewableEnergy/PowerBank/PanelSource"
local PanelStorms = require "RenewableEnergy/PowerBank/PanelStorms"
local Payers = require "RenewableEnergy/PowerBank/Payers"
local Place = require "RenewableEnergy/World/Place"
local Recipes = require "RenewableEnergy/Recipes"
local Specs = require "RenewableEnergy/Specs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local SolarSites = require "RenewableEnergy/World/SolarSites"
local Sprites = require "RenewableEnergy/Sprites"
local Sun = require "RenewableEnergy/Sun"
local TreadmillSource = require "RenewableEnergy/PowerBank/TreadmillSource"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local Wind = require "RenewableEnergy/Wind"
local WindSource = require "RenewableEnergy/PowerBank/WindSource"

local handler, need = PZHarness.serverHandler, PZHarness.need
local Fixtures, Records = PZHarness.Fixtures, PZHarness.Records

local function bankRecord(args)
    return Records.at({ kind = "bank", x = args.x, y = args.y, z = args.z })
end

local function bankAt(args)
    local record, bank = bankRecord(args)
    return record, need(bank, "the bank's tile on the server")
end

local function stateOf(record)
    return Records.read("bank", record, record:getIsoObject())
end

-- Fixtures ---------------------------------------------------------------------------------------

-- RenewableEnergyTest.bank's handler. Whatever bank stands on the square when the test ends goes,
-- with its record (Records.track): a chunk loaded again, or a bank rebuilt, brings a new object.
handler("placeBank", function(player, args, defer)
    local square = PZHarness.squareAt(args)
    local items = args.items or {}
    Records.track(defer, player, { kind = "bank", x = args.x, y = args.y, z = args.z })
    local bank = ModFixtures.placeBank(square, Sprites[args.kind][args.facing or "S"], items, args.charge or 1)
    need(bank:getContainer():getItems():size() == #items, "every item of " .. table.concat(items, ", ") .. " in the bank")
    if args.connected == false then
        need(RenewableEnergyAction.completeJob(player, "bank", BankJobs.DISCONNECT, bank), "the bank disconnected")
    end
    return Squares.positionOf(bank)
end)

-- RenewableEnergyTest.panel's handler, for any source tile. A panel mount is placed from its item
-- the way the moveables cursor places it (Place.panel), carrying `args.modules`. A wind
-- charger is built in place and a treadmill is vanilla furniture, neither from an item of the mod,
-- so their tile is put down bare, unless `args.built` builds the charger as its build-menu entity,
-- as the world builds its finds (Place.entity); its blades come broken when `args.broken`. A
-- treadmill's comes wired by its wiring's owner when `args.wired`. With `args.bank`, the server's
-- character connects it to the bank there. What stands on the square when the test ends goes
-- (PZHarness.trackSquare; the test setting's `remove` unwires a treadmill first). Answers whether
-- the source connected and the refusal.
handler("placePanel", function(player, args, defer)
    local square = PZHarness.squareAt(args)
    PZHarness.trackSquare(defer, player, args)
    local panel
    if getSprite(args.sprite):getProperties():has("CustomItem") then
        Place.panel(square, args.sprite, args.modules)
        panel = need(Squares.findObjectOn(square, function(object) return Sprites.nameOf(object) == args.sprite end),
            "a placed " .. args.sprite .. " on the server")
    elseif args.built then
        panel = Place.entity(square, args.sprite, Wind.OnCreate)
    else
        panel = Fixtures.newTile(square, args.sprite)
        -- As placing does: the mod's OnObjectAdded handlers see the new tile.
        triggerEvent("OnObjectAdded", panel)
    end
    if args.broken then
        WindSource.setBroken(panel, true)
    end
    if args.wired then
        TreadmillSource.wire(panel)
    end
    if not args.bank then
        return { connected = false }
    end
    local Action, connect = RenewableEnergyAction, SourceJobs.CONNECT
    local bank = Kinds.find({ x = args.bank.x, y = args.bank.y, z = args.bank.z, kind = "bank" })
    local connected = Action.completeJob(player, "source", connect, panel, bank)
    return { connected = connected, reason = not connected and Action.jobsOf("source").refusal(player, connect, panel, bank) or nil }
end)

-- Takes what stands at x, y, z drawn as `args.sprite`, else of the kind `args.kind` (Kinds.findOn),
-- away the way the game does, as a player picking it up, a sledgehammer or a pickup would.
handler("removeAt", function(player, args)
    Fixtures.removePlaced(Kinds.find(args), player)
    return {}
end)

-- A Base.Generator plugged in on the square at `args`, fuelled with `args.fuel` litres (full
-- unless given), started as a player starts one if `args.running`, with a failsafe tile on its
-- square if `args.failsafe`. Both are removed when the test ends by what is new on the square, so
-- a chunk reload's fresh objects go too.
handler("placeGenerator", function(player, args, defer)
    local square = PZHarness.squareAt(args)
    PZHarness.trackSquare(defer, player, args)
    local generator = SolarSites.placeGenerator(square, 100, args.fuel or 10)
    if args.failsafe then
        Fixtures.newTile(square, Sprites.failsafe)
    end
    if args.running then
        ISActivateGenerator.complete({ generator = generator, activate = true })
    end
    return {}
end)

-- Banks ------------------------------------------------------------------------------------------

-- RenewableEnergyTest.setCharge's handler. Answers the bank's read.
handler("setCharge", function(_, args)
    local record, bank = bankAt(args)
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

-- RenewableEnergyTest.bankPart's handler, past the bank's own commands. Wear.take keeps a fraction
-- pending on the item. Answers the bank's read.
handler("bankPart", function(_, args)
    local record, bank = bankAt(args)
    local item = need(bank:getContainer():getFirstType(args.type), "a " .. tostring(args.type) .. " in the bank on the server")
    if args.remove then
        Items.removeItem(item)
    else
        if args.condition then
            Wear.setCondition(item, args.condition)
        end
        if args.wear then
            Wear.take(item, args.wear)
        end
        sendItemStats(item)
        if args.repaired then
            item:setHaveBeenRepaired(args.repaired)
            item:syncItemFields()
        end
    end
    if args.recount then
        record:recount()
        record:sendStatus()
    end
    return stateOf(record)
end)

-- Battery.shift into the batteries of the bank at x, y, z toward full, `args.uses` giving each its
-- whole uses first, in container order, `args.wh` counted in uses of the first battery and
-- `args.usesPerStep` passed on. Answers what moved, in those uses and in whole uses, whether a
-- battery is still short of full, and each battery's uses after.
handler("shiftBatteries", function(_, args)
    local record, bank = bankAt(args)
    local container = bank:getContainer()
    local batteries = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        if Battery.isBattery(items:get(i)) then
            table.insert(batteries, items:get(i))
        end
    end
    need(#batteries == #args.uses, #args.uses .. " batteries in the bank on the server")
    for i, item in ipairs(batteries) do
        item:setCurrentUses(args.uses[i])
    end
    local useWh = batteries[1]:getUseDelta() * Battery.nominalWh(batteries[1])
    local moved, movedUses, short = Battery.shift(container, args.wh * useWh, 1, 1, Battery.isBattery, Battery.nominalWh,
        args.usesPerStep)
    local after = {}
    for i, item in ipairs(batteries) do
        after[i] = item:getCurrentUses()
    end
    record:recount()
    return { moved = moved / useWh, movedUses = movedUses, short = short, uses = after }
end)

local SNOWING = { cloud = 1, fog = 0, rain = 0, snowing = true, groundSnow = 0 }

-- RenewableEnergyTest.bankPass's handler: the bank system's own pass (Bank:catchUp, then
-- Bank:afterChange) in the context the system builds, with the sky the test sets; the sun is above
-- the horizon only when there is light. Answers the bank's read after the pass.
handler("bankPass", function(_, args)
    local record = bankRecord(args)
    local light = args.light or 0
    local function irradiance() return light end
    PanelStorms.add(args.stormHours or 0)
    record.lastHour = getGameTime():getWorldAgeHours() - (args.hours or 1)
    record:catchUp(function(hours)
        local context = BankSystem.passContext(hours)
        context.irradiance, context.clearIrradiance = irradiance, irradiance
        context.elevation = light > 0 and 45 or -10
        context.weather = args.snowing and SNOWING or Sun.CLEAR_WEATHER
        context.precipitation = args.snowing and 1 or 0
        context.airC = args.airC or 25
        context.windKph = args.windKph or 0
        return context
    end)
    record:afterChange()
    return stateOf(record)
end)

-- What the running generator at x, y, z delivers (Payers.deliveredW): a read for a bank's reload
-- (T.reloadRecord) to take before and after.
handler("generatorLoad", function(_, args)
    return { deliveredW = Payers.deliveredW(need(PZHarness.squareAt(args):getGenerator(), "the generator on the server")) }
end)

-- RenewableEnergyTest.applyLoad's handler: the window tests' load, which is about how the window
-- shows a load of given kinds, not how a pass measures one; answers the bank's read.
handler("applyLoad", function(_, args)
    local record = bankAt(args)
    local load = Loads.new()
    for _, appliance in ipairs(args.appliances or {}) do
        Loads.add(load, appliance.name, appliance.watts)
    end
    record.loadW, record.loadByKind, record.loadElsewhere = load.watts, Loads.byKind(load), Loads.elsewhere(load) or false
    record:checkOverload()
    record:switchGenerator()
    record:afterChange()
    return stateOf(record)
end)

-- Brings the bank up to date with its container, as opening its status window does.
handler("refreshBank", function(_, args)
    bankRecord(args):refresh()
    return {}
end)

-- Takes the bank away the way picking it up or destroying it does.
handler("removeBank", function(_, args)
    local _, bank = bankAt(args)
    bank:getSquare():transmitRemoveItemFromSquare(bank)
    local square = PZHarness.squareAt(args)
    return { powered = square:haveElectricity(), registered = PowerBank.serverSystem:getLuaObjectOnSquare(square) ~= nil }
end)

-- Takes the containers off the bank, as a bank tile a map or a placement that failed halfway
-- leaves, then loads its square the way its chunk loading does, which rebuilds it. Answers the
-- rebuilt bank's read; placeBank's cleanup takes the rebuilt bank away.
handler("rebuildBank", function(_, args)
    local _, bank = bankAt(args)
    bank:removeAllContainers()
    local square = PZHarness.squareAt(args)
    MapObjects.loadGridSquare(square)
    local rebuilt = PowerBank.findOn(square)
    need(rebuilt and rebuilt ~= bank and rebuilt:getContainer(), "a rebuilt bank with a container on the server")
    return stateOf((bankRecord(args)))
end)

-- Loads -------------------------------------------------------------------------------------------

-- What the load scan of the bank on the square at `args` finds, as the payer there: its watts and
-- the count of each kind, in this building or another.
handler("scanLoad", function(_, args)
    local payer = { x = args.x, y = args.y, z = args.z, key = Squares.placeKey(args.x, args.y, args.z) }
    local load = Payers.scan(payer, Payers.running())
    local counts = {}
    for _, group in ipairs({ load, load.elsewhere }) do
        for name, kind in pairs(group.kinds) do
            counts[name] = (counts[name] or 0) + kind.count
        end
    end
    return { watts = load.watts, counts = counts }
end)

-- Where the stand-in for another mod's appliance stands, its kind and the fuel an hour it draws,
-- read by the draw drawAt adds to the scan (GeneratorReach.addDraw) once, as a --stay rerun loads
-- this file again and the mod's draws stay: GeneratorReach has no way to take a draw back.
RenewableEnergyTestConsumer = RenewableEnergyTestConsumer or {}

-- The floor of the square at `args` draws `args.fuel` an hour as the kind `args.kind` until the
-- test ends, as another mod's appliance that told the bank's scan what it draws.
handler("drawAt", function(_, args, defer)
    local stub = RenewableEnergyTestConsumer
    if not stub.added then
        stub.added = true
        GeneratorReach.addDraw(function(object)
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

-- The module `id` in a container on the square `at`, or nil.
local function moduleInContainerAt(at, id)
    local objects = PZHarness.squareAt(at):getObjects()
    for i = 0, objects:size() - 1 do
        local container = objects:get(i):getContainer()
        local module = container and container:getItemWithID(id)
        if module then
            return module
        end
    end
    return nil
end

-- A factory module at `args.condition` in a crate on the square at x, y, z, sent to the clients
-- with it: an input a craft takes from beside the player's inventory.
handler("moduleInCrate", function(_, args, defer)
    local square = PZHarness.squareAt(args)
    local crate = IsoObject.new(square, "carpentry_01_16", "RenewableEnergyTest")
    crate:setContainer(ItemContainer.new("crate", square, crate))
    local module = crate:getContainer():AddItem(Specs.factoryModule)
    Wear.setCondition(module, args.condition)
    square:AddTileObject(crate)
    if isServer() then
        crate:transmitCompleteItemToClients()
    end
    defer(function() Fixtures.removePlaced(crate) end)
    return { id = module:getID() }
end)

-- Seal Cracked Module's OnCreate on the module `args.id` in a container at x, y, z, as a craft that
-- took it from there runs it.
handler("sealModuleInCrate", function(_, args)
    local module = need(moduleInContainerAt(args, args.id), "the crate's module on the server")
    local inputs = ArrayList.new()
    inputs:add(module)
    Recipes.repairModule({ getAllInputItems = function() return inputs end })
    return { condition = module:getCondition(), repaired = module:getHaveBeenRepaired() }
end)

-- A panel record off the map, as `args` lists it ({ kind, material, modules }).
local function panelRecord(args)
    local source = { kind = args.kind, material = args.material, modules = {} }
    for i, module in ipairs(args.modules or {}) do
        source.modules[i] = { type = module.type, condition = module.condition }
    end
    return source
end

handler("stormChances", function(_, args)
    local chances = {}
    for i, trial in ipairs(args.trials) do
        chances[i] = PanelStorms.stormChance(panelRecord(trial.source), trial.hours)
    end
    return { chances = chances }
end)

-- A storm (PanelStorms.stormCrack) on a panel record off the map for each trial { source, hours,
-- roll }, roll a number, or "under" or "at" for a roll just under or at the trial's own
-- stormChance; worked out here, so the roll is exactly the chance the crack compares it with. A
-- storm draws that roll and, when it cracks, one more to pick the module (the first, at 0).
-- Answers whether each cracked and the modules after.
handler("stormCrack", function(_, args, defer)
    local Rolls = PZHarness.Rolls
    return { results = Rolls.eachTrial(defer, args.trials, function(trial)
        return { Rolls.trialRoll(trial.roll, PanelStorms.stormChance(panelRecord(trial.source), trial.hours)), 0 }
    end, function(trial)
        local source = panelRecord(trial.source)
        return { cracked = PanelStorms.stormCrack(source, trial.hours), modules = source.modules }
    end) }
end)

-- The modules the panel on the square at `args` records, and the overlays its tile shows.
handler("panelState", function(_, args)
    local panel = Kinds.find({ x = args.x, y = args.y, z = args.z, kind = "source" })
    return { modules = panel:getModData()[Panel.MODULES_KEY], overlays = Fixtures.overlaysOf(panel) }
end)

handler("panelStorm", function(_, args)
    PanelStorms.add(args.hours)
    PanelSource.weatherLoaded()
    local modules = {}
    for i, position in ipairs(args.panels) do
        local panel = Kinds.find({ x = position.x, y = position.y, z = position.z, kind = "source" })
        modules[i] = panel:getModData()[Panel.MODULES_KEY]
    end
    return { modules = modules }
end)
