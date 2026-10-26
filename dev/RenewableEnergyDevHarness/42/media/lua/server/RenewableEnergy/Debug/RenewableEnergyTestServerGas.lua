-- The authority's half of the gas line and wood gas tests (RenewableEnergyTestsGasLine.lua,
-- RenewableEnergyTestsWoodGas.lua): generators with the Gas Conversion Kit, the load they carry,
-- burning a gasifier's wood, and vanilla's wood fires. The generator reads, settings and billing
-- serve the bank tests' generators too (RenewableEnergyTestsBankGenerators.lua). The records
-- themselves are RenewableEnergyTestServerBiogas.lua's.
-- Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Squares = require "cf_commonlib/Squares"
local FireAsh = require "RenewableEnergy/WoodGas/FireAsh"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler

-- Generators ------------------------------------------------------------------------------------

local function generatorOn(args)
    return Helpers.find({ x = args.x, y = args.y, z = args.z, kind = "generator" })
end

-- The generator at x, y, z: whether it runs, its fuel and condition, vanilla's idle bill an hour
-- (`idle`) and its whole bill an hour (`bill`), its kit's state (nil without a kit) with whether a
-- line is connected and to what kind of source, whether the gas pass lists it, its overlays and its
-- sprite, which picks the kit's and pipe's overlays (Sprites.gasKitFor), whether its building is
-- toxic, and the world hour on the server as it was read (`hours`).
local function generatorRead(generator)
    local GasKit = RenewableEnergy.GasKit
    local state = GasKit.stateOf(generator)
    local plain
    if state then
        local keys = {}
        for key in pairs(state) do
            table.insert(keys, key)
        end
        plain = PZHarness.Fixtures.fieldsOf(state, keys)
        plain.connected = state.source ~= nil
        plain.sourceKind = state.source and state.source.kind
    end
    local building = generator:getSquare():getBuilding()
    return {
        running = generator:isActivated(), fuel = generator:getFuel(), idle = generator:getBasePowerConsumption(),
        bill = generator:getTotalPowerUsing(), condition = generator:getCondition(), state = plain,
        listed = RenewableEnergy.GasLines.isListed(generator),
        overlays = PZHarness.Fixtures.overlaysOf(generator), sprite = RenewableEnergy.Sprites.nameOf(generator),
        toxic = building ~= nil and building:isToxic(), hours = getGameTime():getWorldAgeHours(),
    }
end

handler("generatorRead", function(player, args)
    return generatorRead(generatorOn(args))
end)

-- Reads a bank's charging demand and its generators' native bills on either side of a real job.
-- The completion and snapshots share one authority call; no tick or explicit billing can repair
-- a missing job-boundary settlement between them. Without a job this is a read-only snapshot.
handler("bankSettlement", function(player, args)
    local record, bank = Helpers.bankAt(args.bank)
    local function snapshot()
        local generators = {}
        for i, at in ipairs(args.generators or {}) do
            local generator = generatorOn(at)
            generators[i] = generatorRead(generator)
            generators[i].chargesBank = record:chargesFrom(generator)
        end
        return {
            activated = bank:isActivated(), on = record.on == true, name = record.name or "",
            charge = record.charge, chargeWantW = record.chargeWantW, chargeSource = record.chargeSource,
            chargerMaxW = record:chargerMaxW(), lastHour = record.lastHour, age = getGameTime():getWorldAgeHours(),
            batteries = #record.batteries, items = Helpers.itemsOf(bank:getContainer()), generators = generators,
        }
    end
    if not args.job then return snapshot() end
    local with = args.part and PZHarness.need(bank:getContainer():getFirstType(args.part),
        "a " .. args.part .. " in the bank on the server") or args.name
    local before = snapshot()
    local Action = RenewableEnergyAction
    local done = Action.completeJob(player, "bank", args.job, bank, with)
    local after = snapshot()
    return { before = before, after = after, ok = done,
        reason = not done and Action.jobsOf("bank").refusal(player, args.job, bank, with) or nil }
end)

-- Pours `args.pour` litres into the generator at x, y, z, as a player pouring petrol does (onto
-- whatever it shows), switches it on or off (`args.running`), as a player does, and has vanilla
-- rebuild the bills of the generators reaching it (`args.rebuild`). Answers the world update count
-- it acted at (`frame`, see worldFrame).
handler("generatorSet", function(player, args)
    local generator = generatorOn(args)
    if args.pour then
        generator:setFuel(math.min(generator:getMaxFuel(), generator:getFuel() + args.pour))
    end
    if args.running ~= nil then
        ISActivateGenerator.complete({ generator = generator, activate = args.running })
    end
    if args.rebuild then
        -- What an appliance switching in its reach does: the generators reaching it rebuild their bill
        -- in their next update (IsoGenerator.update).
        IsoGenerator.updateGenerator(generator:getSquare())
    end
    return { frame = getWorld():getFrameNo() }
end)

-- The world updates the authority has run (`frame`). A server serves commands between its updates
-- (GameServer.main), and single player within one, after the objects' (IsoCell.update), so once
-- the count passes an earlier answer's, every generator has had an update since that answer, and
-- a step queued after the wait for it comes after that update's OnTick too.
handler("worldFrame", function()
    return { frame = getWorld():getFrameNo() }
end)

-- Takes `args.litres` from the fuel of the generator at x, y, z, as vanilla's hourly bill
-- (IsoGenerator.update) and a bank charging from it (Bank:chargeFrom) take it.
handler("burnFuel", function(player, args)
    local generator = generatorOn(args)
    generator:setFuel(generator:getFuel() - args.litres)
    return {}
end)

-- Bills every running generator its share, as the ten-minute pass does (Payers.billGenerators).
handler("billGenerators", function()
    RenewableEnergy.Payers.billGenerators()
    return {}
end)

-- Sets the wear chance of the item script of the generator at x, y, z to one in `args.oneIn` an
-- hour it runs (its ConditionLowerChanceOneIn) until the test ends.
handler("generatorWearChance", function(player, args, defer)
    local generator = generatorOn(args)
    local item = PZHarness.need(getScriptManager():getItem(generator:getGeneratorItemType()),
        "the item script of the generator at " .. args.x .. "," .. args.y)
    local was = item:getConditionLowerChance()
    item:setConditionLowerChance(args.oneIn)
    defer(function() item:setConditionLowerChance(was) end)
    return {}
end)

-- Builds the action of `args.feature` and `args.job` at the generator at x, y, z as the server
-- builds the one a client asks for (NetTimedAction.parse calls the class's new, the class first).
-- Answers whether that gave an action.
handler("gasActionFrom", function(player, args)
    local generator = generatorOn(args)
    local action = RenewableEnergyAction.new(RenewableEnergyAction, player, args.feature, args.job, generator)
    return { built = action ~= nil }
end)

-- Does the kit job `args.job` at the generator at x, y, z for the character as the authority does
-- the one a client's action asks for once it ends: the action's complete(). Answers whether it was
-- done; a client's own action that the server turns down stops its whole queue. With `args.payer`,
-- snapshots bracket complete in the same authority call, before any native update or periodic pass.
handler("kitJobComplete", function(player, args)
    local generator = generatorOn(args)
    local action = RenewableEnergyAction:new(player, "kit", args.job, generator)
    if args.payer then
        local payer = generatorOn(args.payer)
        local before = { generator = generatorRead(generator), payer = generatorRead(payer) }
        local done = action:complete()
        return { done = done, before = before,
            after = { generator = generatorRead(generator), payer = generatorRead(payer) } }
    end
    return { done = action:complete() }
end)

-- Has the kit job `args.job` not get done on the authority until the test ends, as a job whose
-- work fails there: its site's act (Jobs.perform) answers false and changes nothing.
handler("kitJobNotDone", function(player, args, defer)
    local site = RenewableEnergy.GasLines.jobSite
    local act = site.act
    site.act = function(character, job, ...)
        if job == args.job then
            return false
        end
        return act(character, job, ...)
    end
    defer(function() site.act = act end)
    return {}
end)

-- Runs the gas pass as though `args.hours` had passed since the last of the kitted generator at
-- x, y, z.
handler("gasPass", function(player, args)
    local generator = generatorOn(args)
    local state = PZHarness.need(RenewableEnergy.GasKit.stateOf(generator),
        "a kit on the generator at " .. args.x .. "," .. args.y)
    state.lastHour = getGameTime():getWorldAgeHours() - args.hours
    RenewableEnergy.GasLines.updateAll()
    return {}
end)

-- Makes every kitted generator deliver `args.watts` in place of what its scan finds, until the test
-- ends. GasLines.run looks loadOf up on every call.
handler("gasLoad", function(player, args, defer)
    local GasLines = RenewableEnergy.GasLines
    local scan = GasLines.loadOf
    GasLines.loadOf = function() return args.watts end
    defer(function() GasLines.loadOf = scan end)
    return {}
end)

-- Gasifiers ------------------------------------------------------------------------------------

-- Burns `args.kg` in the gasifier record `args` (T.recordArgs), as a pass would, to leave its ash
-- and tar.
handler("burnGasifier", function(player, args)
    local record = Helpers.recordAt(args)
    local burned = record:burn(args.kg)
    record:afterChange()
    return { burned = burned }
end)

-- Wood fires ------------------------------------------------------------------------------------

-- A charcoal grill's tile, as vanilla's own tests place one (TimedActionsTests.lua's newBBQCharcoal).
local CHARCOAL_GRILL = "appliances_cooking_01_35"

-- A vanilla wood fire on the square at `args`, empty and unlit: a campfire as building one makes it
-- (SCampfireSystem:addCampfire), or with `args.grill` a charcoal grill. Whatever fire stands there
-- when the test ends goes.
handler("placeFire", function(_, args, defer)
    local square = Helpers.squareAt(args)
    if args.grill then
        local grill = IsoBarbecue.new(getCell(), square, getSprite(CHARCOAL_GRILL))
        square:AddTileObject(grill)
        grill:transmitCompleteItemToClients()
    else
        SCampfireSystem.instance:addCampfire(square)
    end
    defer(function()
        local fire = Squares.findObjectOn(PZHarness.Fixtures.squareAt(args), FireAsh.isFire)
        if fire then
            PZHarness.Fixtures.removePlaced(fire)
        end
    end)
    return {}
end)

-- Burns `args.minutes` of the fuel in the unlit wood fire at `args`, as the campfire system's
-- minutes or a grill's update would while it burned. Answers the Wood Ash it then has
-- (FireAsh.ashItems).
handler("burnFire", function(_, args)
    local fire = PZHarness.need(Squares.findObjectOn(Helpers.squareAt(args), FireAsh.isFire), "a wood fire on the server")
    local campfire = SCampfireSystem.instance:getLuaObjectOnSquare(fire:getSquare())
    if campfire then
        SCampfireSystem.instance:lowerFuelAmountSpecific(campfire, args.minutes)
    else
        fire:setFuelAmount(fire:getFuelAmount() - args.minutes)
        fire:sendObjectChange(IsoObjectChange.STATE)
    end
    return { ash = FireAsh.ashItems(fire) }
end)
