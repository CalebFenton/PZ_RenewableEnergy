-- The authority's half of the world spawn and solar site tests: banks, crates, cracked modules
-- and sites are placed and stocked only where the authority runs them. Only registers handlers,
-- so a --stay rerun loads it again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these
-- handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler, check, saveOptions = PZHarness.serverHandler, Helpers.check, Helpers.saveOptions
local objectWithSprite = PZHarness.Fixtures.objectWithSprite
local squareAt, removeObject = Helpers.squareAt, Helpers.removeObject
local Sprites = RenewableEnergy.Sprites

local MODULE = RenewableEnergy.Specs.factoryModule

local function inRange(value, range)
    return value >= range.min and value <= range.max
end

-- Whether a module's condition is one a site, crate or arrow board gives: cracked or weathered.
local function isSiteCondition(condition)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    return inRange(condition, WorldSpawns.CRACKED) or inRange(condition, WorldSpawns.WEATHERED)
end

local function batteryCharges(container)
    local charges = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if RenewableEnergy.Battery.isBattery(item) then
            table.insert(charges, RenewableEnergy.Battery.getCharge(item))
        end
    end
    return charges
end

local function moduleConditions(container)
    local conditions = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == MODULE then
            table.insert(conditions, item:getCondition())
        end
    end
    return conditions
end

-- World spawns -----------------------------------------------------------------------------------

-- What a world spawn left in `container`: its batteries' charges, its modules' conditions and how
-- many items it holds.
local function stockOf(container)
    return {
        charges = batteryCharges(container), modules = moduleConditions(container),
        items = container:getItems():size(), explored = container:isExplored(),
    }
end

-- WorldSpawns.placeBank with BANK_STOCK[args.stock] on the square at `args`, as a room seen for the
-- first time places one. Answers whether it placed one, its tile and stock, and whether the stock's
-- tile stands on the square. Removed when the test ends.
handler("worldBank", function(_, args, defer)
    local square = squareAt(args)
    if not square then
        return nil, "the bank's square loaded on the server"
    end
    local bank = RenewableEnergy.WorldSpawns.placeBank(square, args.stock)
    if bank then
        defer(function() removeObject(bank) end)
    end
    local tile = Sprites[RenewableEnergy.WorldSpawns.BANK_STOCK[args.stock].sprite]
    local answer = { placed = bank ~= nil, boxOnSquare = objectWithSprite(square, tile) ~= nil }
    if bank then
        answer.sprite = bank:getTextureName()
        answer.stock = stockOf(bank:getContainer())
    end
    return answer
end)

-- Stock names whose part rates bankStockRates measures: one battery box, one rack.
local RATE_STOCKS = { shed = true, farmStorage = true }
-- How many binomial standard errors a measured share may stray from its chance: wide enough that
-- a correct stock fails about once in tens of thousands of runs, narrow enough at the test's
-- sample count to catch a chance retuned by a few points.
local RATE_SIGMAS = 4

-- Over many banks, each part turns up about as often as BANK_STOCK says, and a battery box never
-- comes with a charge controller.
check("bankStockRates", function(expect, expectNear, _, args, defer)
    local WorldSpawns, Loot = RenewableEnergy.WorldSpawns, RenewableEnergy.Loot
    local container = Loot.newContainer(nil)
    local samples = args.samples
    -- Found batteries are sent to the clients that see them, and a server can't send an item of a
    -- container that isn't in the world; the parts' rates don't depend on the batteries.
    local options = SandboxVars.RenewableEnergy
    local restoreOptions = saveOptions(defer, { "LRMBatteries" })
    options.LRMBatteries = 0
    local function partCounts(stockName)
        local found = { inverter = 0, controller = 0, charger = 0 }
        local function stock(c) WorldSpawns.stockBank(c, stockName) end
        for _ = 1, samples do
            -- fillOnce takes the items off the cell's processed list, which thousands of banks in
            -- one frame would otherwise swamp.
            for fullType, count in pairs(Loot.fillOnce(stock, container, true)) do
                local kind = RenewableEnergy.PowerBank.partKind(fullType)
                if found[kind] then
                    found[kind] = found[kind] + count
                end
            end
        end
        return found
    end
    for stockName, stock in pairs(WorldSpawns.BANK_STOCK) do
        local isBox = args.boxTiles[stock.sprite]
        if RATE_STOCKS[stockName] or isBox then
            local found = partCounts(stockName)
            if RATE_STOCKS[stockName] then
                for kind, count in pairs(found) do
                    local part = stock[kind]
                    local chance = part and math.min(1, part.chance * options.LRMMisc) or 0
                    if part then
                        expect(part.chance > 0 and part.chance <= 1, stockName .. " banks hold a " .. kind .. " with chance " .. part.chance)
                    end
                    local tolerance = RATE_SIGMAS * math.sqrt(chance * (1 - chance) / samples) + 1e-9
                    expectNear(stockName .. " share holding a " .. kind, count / samples, chance, tolerance)
                end
            end
            if isBox then
                expect(found.controller == 0, found.controller .. " of " .. samples .. " " .. stockName .. " battery boxes hold a charge controller")
            end
        end
    end
    restoreOptions()
end)

-- How many items `args.times` electronics storage banks get at the save's options.
handler("bankStockCount", function(_, args)
    local container = ItemContainer.new("crate", nil, nil)
    for _ = 1, args.times do
        RenewableEnergy.WorldSpawns.stockBank(container, "electronicsStorage")
    end
    local count = container:getItems():size()
    container:removeAllItems()
    return { items = count }
end)

-- WorldSpawns.placeCrate with CRATE_STOCK[args.stock] on the square at `args`. Answers its stock
-- and the name of its overlay. Removed when the test ends.
handler("worldCrate", function(_, args, defer)
    local square = squareAt(args)
    if not square then
        return nil, "the crate's square loaded on the server"
    end
    local crate = RenewableEnergy.WorldSpawns.placeCrate(square, args.stock)
    defer(function() removeObject(crate) end)
    local container, overlay = crate:getContainer(), crate:getOverlaySprite()
    if not container then
        return nil, "the crate's container"
    end
    return { stock = stockOf(container), overlay = overlay and overlay:getName() }
end)

-- The cracked and weathered condition ranges are real conditions, and a cracked module always
-- reads worse than a weathered one, so players can tell which needs repair.
local function expectConditionRanges(expect)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    for name, range in pairs({ cracked = WorldSpawns.CRACKED, weathered = WorldSpawns.WEATHERED }) do
        expect(range.min >= 1 and range.min < range.max and range.max <= 100,
            "the " .. name .. " condition range is " .. range.min .. " to " .. range.max)
    end
    expect(WorldSpawns.CRACKED.max < WorldSpawns.WEATHERED.min, "cracked and weathered conditions overlap")
end

-- Farm storage shelves get cracked modules, at cracked conditions, and a bedroom's furniture none,
-- at the save's Solar Panels loot option; at the option's default a garage shelf's chance is the
-- room's weight at the module's loot multiplier, small but there.
check("crackedModules", function(expect, expectNear, _, args, defer)
    local Distributions = RenewableEnergy.Distributions
    local container = ItemContainer.new("crate", nil, nil)
    for _ = 1, args.samples do
        Distributions.addCrackedModules("farmstorage", "metal_shelves", container)
    end
    local conditions = moduleConditions(container)
    container:removeAllItems()
    for _ = 1, args.samples do
        Distributions.addCrackedModules("bedroom", "wardrobe", container)
        Distributions.addCrackedModules("garage", "fridge", container)
    end
    local elsewhere = container:getItems():size()
    container:removeAllItems()
    local restoreOptions = saveOptions(defer, { "LRMSolarPanels" })
    SandboxVars.RenewableEnergy.LRMSolarPanels = 1
    local garage = Distributions.CRACKED_MODULE_ROOMS.garage
    local defaultChance = Distributions.crackedModuleChance(garage)
    restoreOptions()
    expectConditionRanges(expect)
    expect(#conditions == args.samples, #conditions .. " cracked modules on " .. args.samples .. " farm storage shelves")
    for _, condition in ipairs(conditions) do
        if not expect(inRange(condition, RenewableEnergy.WorldSpawns.CRACKED), "a cracked module is at condition " .. condition) then
            break
        end
    end
    expect(elsewhere == 0, elsewhere .. " modules in bedrooms and garage fridges")
    -- A loot weight is out of 100 rolls, scaled by the item's loot category multiplier.
    local lootModifier = ItemPickerJava.getLootModifier(RenewableEnergy.Specs.factoryModule)
    expectNear("a garage shelf's chance of a cracked module", defaultChance, garage * lootModifier / 100, 1e-9)
    expect(defaultChance > 0, "a garage shelf never holds a cracked module at the default option")
end)

-- What WorldSpawns stocks, which only the authority loads: for each BANK_STOCK name of
-- `args.names` its tile (a Sprites field) and battery count range; the module conditions of
-- crates; and for the CRATE_STOCK name `args.crate`, if given, each item's count range.
handler("worldSpawnStock", function(_, args)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local banks = {}
    for _, name in ipairs(args.names) do
        local stock = WorldSpawns.BANK_STOCK[name]
        banks[name] = { sprite = stock.sprite, batteries = { min = stock.batteries.min, max = stock.batteries.max } }
    end
    local crate
    if args.crate then
        crate = {}
        for _, line in ipairs(WorldSpawns.CRATE_STOCK[args.crate]) do
            crate[line[1]] = { min = line[2], max = line[3] }
        end
    end
    return { banks = banks, crate = crate, cracked = WorldSpawns.CRACKED, weathered = WorldSpawns.WEATHERED }
end)

-- Solar sites -----------------------------------------------------------------------------------

-- A site goes down once when its chunk loads, and its spot is forgotten, so loading the chunk
-- again places nothing. Its pump's pole mount holds as many modules as the stock tank kind says,
-- at site conditions. The site has one spot, a metal rack facing south on the square at `args`;
-- the rack is removed when the test ends.
check("sitePlacedOnce", function(expect, _, _, args, defer)
    local square = squareAt(args)
    if not square then
        return "the site's square loaded on the server"
    end
    local SolarSites = RenewableEnergy.SolarSites
    local x, y, z = args.x, args.y, args.z
    local chunkX, chunkY = math.floor(x / 8), math.floor(y / 8)
    SolarSites.addSite({ kind = "stockTank", name = "test", panels = { { x, y, z, "rackMetal", "S" } } })
    local waiting = SolarSites.spotAt(x, y, z) ~= nil
    SolarSites.placeChunk(chunkX, chunkY)
    local leftOver = SolarSites.spotAt(x, y, z) ~= nil
    local objects = square:getObjects():size()
    SolarSites.placeChunk(chunkX, chunkY)
    local addedAgain = square:getObjects():size() - objects
    local rack = objectWithSprite(square, Sprites.rack.metal.S)
    if not rack then
        return "the site's rack on its spot"
    end
    defer(function() removeObject(rack) end)
    expect(waiting, "the site kept no spot to place")
    expect(not leftOver, "the site's spot was not forgotten once placed")
    expect(addedAgain == 0, "loading the chunk again added " .. addedAgain .. " objects to the spot")
    local modules = rack:getModData()[RenewableEnergy.PowerBank.MODULES] or {}
    local range = SolarSites.KINDS.stockTank.modules
    expect(inRange(#modules, range), #modules .. " modules on the pump's mount, expected " .. range.min .. " to " .. range.max)
    for _, module in ipairs(modules) do
        expect(module.type == MODULE and isSiteCondition(module.condition),
            "the pump's mount holds " .. tostring(module.type) .. " at " .. tostring(module.condition))
    end
end)

-- Site kinds that are an arrow board on the road and nothing else.
local ARROW_BOARD_KINDS = { roadWorks = true, checkpoint = true }

-- A homestead kind's spots make sense on the map: its find and generator outdoors, its wind
-- charger within reach of its bank in a room, its generator beside a gasifier or within a
-- digester's hose reach on the same level, its pamphlet's house a building.
local function expectHomesteadSpots(expect, metaGrid, site, kind)
    local function outdoors(field)
        local spot = site[field]
        return expect(spot ~= nil, site.name .. " has no " .. field .. " spot")
            and expect(metaGrid:getRoomAt(spot[1], spot[2], spot[3]) == nil, site.name .. "'s " .. field .. " is indoors")
    end
    if kind.wind and outdoors("windCharger") then
        local at, bank = site.windCharger, site.bank
        if expect(bank ~= nil and metaGrid:getRoomAt(bank[1], bank[2], bank[3]) ~= nil, site.name .. "'s bank is in no room") then
            expect(RenewableEnergy.PowerBank.isInReach({ x = bank[1], y = bank[2], z = bank[3] }, at[1], at[2], at[3]),
                site.name .. "'s wind charger is out of its bank's reach")
        end
    end
    if kind.gas and outdoors(kind.gas) and outdoors("generator") then
        local source, generator = site[kind.gas], site.generator
        local sameLevel = source[3] == generator[3]
        if kind.gas == "gasifier" then
            expect(sameLevel and RenewableEnergy.Gasifier.sideOf(generator[1], generator[2], source[1], source[2]) ~= nil,
                site.name .. "'s generator isn't beside its gasifier")
        else
            expect(sameLevel and IsoUtils.DistanceTo(generator[1], generator[2], source[1], source[2]) <= RenewableEnergy.GasKit.REACH,
                site.name .. "'s generator is out of its " .. kind.gas .. "'s reach")
        end
    end
    if kind.pamphlet then
        expect(site.house ~= nil and metaGrid:getRoomAt(site.house[1], site.house[2], 0) ~= nil,
            site.name .. "'s pamphlet is in no building")
    end
end

-- Every site's spots make sense on the map: banks and crates in a room (banks only work indoors),
-- panels outdoors, wall panels on a building's wall, garden lights at a building, arrow boards
-- outdoors with a facing, homestead installations as expectHomesteadSpots says; each site has a
-- unique name, a known kind, and the spots its kind uses, as many panel spots as the kind may
-- place.
check("sitesPlacedSensibly", function(expect)
    local SolarSites = RenewableEnergy.SolarSites
    local metaGrid = getWorld():getMetaGrid()
    local sites = SolarSites.sites()
    expect(#sites > 0, "this map has no solar sites")
    local names = {}
    for _, site in ipairs(sites) do
        expect(not names[site.name], "two sites are named " .. tostring(site.name))
        names[site.name] = true
        local kind = SolarSites.KINDS[site.kind]
        if expect(kind ~= nil, site.name .. " is of no known kind " .. tostring(site.kind)) then
            for _, panel in ipairs(site.panels or {}) do
                local x, y, z, mount, facing = panel[1], panel[2], panel[3], panel[4], panel[5]
                local where = site.name .. " panel at " .. x .. "," .. y .. "," .. z
                local kindOf = Sprites.kindOf(SolarSites.mountSprite(mount, facing))
                expect(kindOf == "flat" or kindOf == "wall" or kindOf == "rack", where .. " names no mount tile")
                expect(metaGrid:getRoomAt(x, y, z) == nil, where .. " is indoors")
                if mount == "wallMetal" then
                    expect(metaGrid:getRoomAt(x, y - 1, z) ~= nil, where .. " has no building wall behind it")
                end
            end
            local panels = #(site.panels or {})
            if kind.panels then
                expect(panels >= kind.panels.min and panels <= kind.panels.max, string.format(
                    "%s has %d panel spots, its kind places %d to %d", site.name, panels, kind.panels.min, kind.panels.max))
            else
                expect(panels == 0, site.name .. " has panel spots its kind never places")
            end
            for _, field in ipairs({ "bank", "crate" }) do
                if kind[field] then
                    local spot = site[field]
                    expect(spot ~= nil and metaGrid:getRoomAt(spot[1], spot[2], spot[3]) ~= nil,
                        site.name .. "'s " .. field .. " is in no room")
                end
            end
            if kind.gardenLights then
                expect(site.house ~= nil and metaGrid:getRoomAt(site.house[1], site.house[2], 0) ~= nil,
                    site.name .. "'s garden lights are at no building")
            end
            if ARROW_BOARD_KINDS[site.kind] then
                expect(site.arrowBoard ~= nil, site.name .. " has no arrow board spot")
            end
            if site.arrowBoard then
                local spot = site.arrowBoard
                expect(metaGrid:getRoomAt(spot[1], spot[2], spot[3]) == nil and IsoDirections[spot[4]] ~= nil,
                    site.name .. "'s arrow board is indoors or faces nowhere")
            end
            expectHomesteadSpots(expect, metaGrid, site, kind)
        end
    end
end)

local PAMPHLET = "RenewableEnergy.FemaPamphlet"

-- The pamphlets in each container of the building's lowest two levels, where
-- RuralFinds.leavePamphlet looks.
local function pamphletsIn(def)
    local found = {}
    for z = 0, 1 do
        for x = def:getX(), def:getX2() - 1 do
            for y = def:getY(), def:getY2() - 1 do
                local square = getSquare(x, y, z)
                local objects = square and square:getObjects()
                for i = 0, (objects and objects:size() or 0) - 1 do
                    local container = objects:get(i):getContainer()
                    if container then
                        found[container] = container:getCountType(PAMPHLET)
                    end
                end
            end
        end
    end
    return found
end

-- Takes out the pamphlets the building's containers gained since `before` (pamphletsIn), and
-- answers how many that was.
local function takeNewPamphlets(def, before)
    local taken = 0
    for container, count in pairs(pamphletsIn(def)) do
        for _ = (before[container] or 0) + 1, count do
            local item = container:getFirstType(PAMPHLET)
            container:Remove(item)
            sendRemoveItemFromContainer(container, item)
            taken = taken + 1
        end
    end
    return taken
end

-- Forgets the site spot at x, y, z, if one waits there.
local function forgetSpot(x, y, z)
    local system = SGlobalObjects.getSystemByName(RenewableEnergy.SolarSites.SYSTEM_NAME)
    local object = system:getObjectAt(x, y, z)
    if object then
        system:removeObject(object)
    end
end

local function chunkOf(square)
    return math.floor(square:getX() / 8), math.floor(square:getY() / 8)
end

-- Removes whatever a homestead site put on `square` when the test ends: its find, its bank or
-- its generator, switched off first and out of the gas pass's list.
local function clearSquare(square, defer)
    defer(function()
        local objects = square:getObjects()
        for i = objects:size() - 1, 0, -1 do
            local object = objects:get(i)
            if RenewableEnergy.GasKit.isGenerator(object) then
                if object:isActivated() then
                    object:setActivated(false)
                end
                ModData.getOrCreate(RenewableEnergy.GasLines.MOD_DATA)[square:getX() .. "," .. square:getY() .. "," .. square:getZ()] = nil
                square:transmitRemoveItemFromSquare(object)
            elseif RenewableEnergy.PowerBank.isBank(object) or Sprites.kindOf(Sprites.nameOf(object)) then
                removeObject(object)
            end
        end
    end)
end

-- The kitted generator on `square` against the line it should have to the `kind` source at
-- `source`: plugged in, off, run down and low on petrol as SolarSites.GENERATOR says, on gas with
-- its line connected and listed for the gas pass, its kit drawn on it. Answers the generator.
local function expectKittedGenerator(expect, expectNear, square, source, kind)
    local GasKit, SolarSites = RenewableEnergy.GasKit, RenewableEnergy.SolarSites
    local generator = RenewableEnergy.findObjectOn(square, GasKit.isGenerator)
    if not expect(generator ~= nil, "no generator at the site's far end") then
        return nil
    end
    local spec = SolarSites.GENERATOR
    expect(generator:isConnected() and not generator:isActivated(), "the generator is found plugged in "
        .. tostring(generator:isConnected()) .. ", running " .. tostring(generator:isActivated()))
    expect(inRange(generator:getCondition(), spec.condition), "the generator is at condition " .. generator:getCondition())
    local fuel = generator:getFuel()
    expect(fuel >= spec.fuel.min - 0.01 and fuel <= spec.fuel.max + 0.01, "the generator holds " .. fuel .. " litres")
    local state = GasKit.stateOf(generator)
    if expect(state ~= nil, "the generator has no gas kit") then
        local line = state.source
        expect(state.mode == "gas" and line ~= nil and line.kind == kind and line.x == source:getX() and line.y == source:getY()
            and line.z == source:getZ(), "the generator's line doesn't run to the " .. kind)
        expectNear("the generator's tank as the kit keeps it", state.tank or -1, fuel, 0.01)
    end
    local key = square:getX() .. "," .. square:getY() .. "," .. square:getZ()
    expect(ModData.getOrCreate(RenewableEnergy.GasLines.MOD_DATA)[key] ~= nil, "the gas pass doesn't list the generator")
    local overlays = Helpers.overlaysOf(generator)
    local kit = Sprites.gasKitFor(Sprites.nameOf(generator))
    local hasKit = false
    for _, overlay in ipairs(overlays) do
        hasKit = hasKit or overlay == kit
    end
    expect(hasKit, "the generator doesn't show its kit")
    return generator, state, overlays
end

-- What each homestead kind left, checked once placed: `at` is its find's square, `far` its bank's or
-- generator's, `def` the house of a pamphlet. Each answers nothing; it records what is wrong.
local KIND_CHECKS = {
    -- The wind charger braked with its blades broken, wired to a rack of tired batteries.
    windFarm = function(expect, _, at, far)
        local Wind, PowerBank, WorldSpawns = RenewableEnergy.Wind, RenewableEnergy.PowerBank, RenewableEnergy.WorldSpawns
        local charger = RenewableEnergy.findObjectOn(at, Wind.isCharger)
        local bank = PowerBank.bankOn(far)
        if not (expect(charger ~= nil, "no wind charger on the site's square") and expect(bank ~= nil, "no bank on the site's bank square")) then
            return
        end
        expect(Sprites.kindOf(Sprites.nameOf(charger)) == "propeller", "the wind charger is a " .. tostring(Sprites.kindOf(Sprites.nameOf(charger))))
        expect(Wind.isBroken(charger) and Wind.isBraked(charger), "the wind charger is found broken " .. tostring(Wind.isBroken(charger))
            .. ", braked " .. tostring(Wind.isBraked(charger)))
        local stock = WorldSpawns.BANK_STOCK.windFarm
        expect(Sprites.nameOf(bank) == Sprites[stock.sprite], "the bank stands on " .. tostring(Sprites.nameOf(bank)))
        expect(bank:isConnected(), "the bank isn't plugged in")
        local wired = PowerBank.bankOfSource(at:getX(), at:getY(), at:getZ())
        expect(wired ~= nil and PowerBank.samePosition(wired, { x = far:getX(), y = far:getY(), z = far:getZ() }),
            "the wind charger isn't wired to the site's bank")
        local batteries, items = 0, bank:getContainer():getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if RenewableEnergy.Battery.isBattery(item) then
                batteries = batteries + 1
                expect(item:getFullType() == "RenewableEnergy.DeepCycleBattery" and inRange(item:getCondition(), stock.batteries.condition),
                    "the bank holds a " .. item:getFullType() .. " at condition " .. item:getCondition())
            end
        end
        expect(inRange(batteries, stock.batteries), batteries .. " batteries in the bank")
    end,
    -- The barrel digester cold, torn and sour, piped to the generator.
    homestead = function(expect, expectNear, at, far)
        local digester, object = Helpers.recordAt({ kind = "digester", x = at:getX(), y = at:getY(), z = at:getZ() })
        if not expect(digester ~= nil, "no digester on the site's square") then
            return
        end
        expect(digester.sour and digester:isTorn(), "the digester is found sour " .. tostring(digester.sour) .. ", torn "
            .. tostring(digester:isTorn()))
        local generator, state = expectKittedGenerator(expect, expectNear, far, object, "digester")
        if state and state.line then
            local GasKit = RenewableEnergy.GasKit
            expect(state.line.item == GasKit.HOSE and state.line.count == GasKit.hosesFor(generator, object),
                "the line took " .. tostring(state.line.count) .. " " .. tostring(state.line.item))
        end
    end,
    -- The primitive gasifier with a full ash pit and its packing all tarred, piped to the
    -- generator beside it; a pamphlet in the house.
    prepper = function(expect, expectNear, at, far, pamphlets)
        local Gasifier = RenewableEnergy.Gasifier
        local gasifier, object = Helpers.recordAt({ kind = "gasifier", x = at:getX(), y = at:getY(), z = at:getZ() })
        if not expect(gasifier ~= nil, "no gasifier on the site's square") then
            return
        end
        local clean, tarry = Gasifier.filterCounts(Gasifier.filterOf(object))
        expect(Sprites.nameOf(object) == Sprites.gasifier.primitive and gasifier.ash == Gasifier.ASH_FULL and clean == 0 and tarry > 0,
            "the gasifier is found " .. tostring(Sprites.nameOf(object)) .. ", ash " .. tostring(gasifier.ash) .. ", "
            .. clean .. " clean and " .. tarry .. " tarry packing")
        local side = Gasifier.sideOf(at:getX(), at:getY(), far:getX(), far:getY())
        expect(gasifier.pipe == side, "the gasifier's pipe runs " .. tostring(gasifier.pipe) .. ", not " .. tostring(side))
        local generator, state, overlays = expectKittedGenerator(expect, expectNear, far, object, "gasifier")
        if generator then
            local pipe = Sprites.gasifierPipeGenFor(Sprites.nameOf(generator), Gasifier.sideOf(far:getX(), far:getY(), at:getX(), at:getY()))
            local piped = false
            for _, overlay in ipairs(overlays) do
                piped = piped or overlay == pipe
            end
            expect(piped, "the generator doesn't show its half of the pipe")
            expect(state.line and state.line.item == RenewableEnergy.GasKit.PIPE and state.line.count == 1,
                "the line took " .. tostring(state.line and state.line.count) .. " " .. tostring(state.line and state.line.item))
        end
        expect(pamphlets == 1, "the house got " .. tostring(pamphlets) .. " pamphlets, not 1")
    end,
}

-- A homestead site of kind `args.kind` goes down once, when its chunks load, worn as RuralFinds
-- leaves its finds and connected as a player would leave it: its find on the square at `args.at`,
-- its bank or generator on the one at `args.far`, and a pamphlet in the house at `args.house`.
-- Its spot is then forgotten, and loading the chunks again places nothing. What it placed is
-- removed when the test ends.
check("siteKindPlaced", function(expect, expectNear, _, args, defer)
    local SolarSites = RenewableEnergy.SolarSites
    local kind = SolarSites.KINDS[args.kind]
    local at, far = squareAt(args.at), squareAt(args.far)
    if not (kind and at and far) then
        return "a homestead kind " .. tostring(args.kind) .. " and its squares loaded on the server"
    end
    local site = { kind = args.kind, name = "test " .. args.kind }
    local ends = { at:getX(), at:getY(), at:getZ() }
    local farEnds = { far:getX(), far:getY(), far:getZ() }
    if kind.wind then
        site.windCharger, site.bank = ends, farEnds
    else
        site[kind.gas], site.generator = ends, farEnds
    end
    local house = args.house and squareAt(args.house)
    local building = house and house:getBuilding()
    local def, before = building and building:getDef(), nil
    if kind.pamphlet then
        if not def then
            return "a building at the pamphlet's square"
        end
        site.house = { house:getX(), house:getY() }
        before = pamphletsIn(def)
        defer(function() takeNewPamphlets(def, before) end)
        defer(function() forgetSpot(house:getX(), house:getY(), 0) end)
    end
    clearSquare(at, defer)
    clearSquare(far, defer)
    defer(function() forgetSpot(at:getX(), at:getY(), at:getZ()) end)
    SolarSites.addSite(site)
    local waiting = SolarSites.spotAt(at:getX(), at:getY(), at:getZ()) ~= nil
    local function loadChunks()
        SolarSites.placeChunk(chunkOf(at))
        if house then
            SolarSites.placeChunk(chunkOf(house))
        end
        SolarSites.placeWaiting()
    end
    loadChunks()
    expect(waiting, "the site kept no spot to place")
    expect(SolarSites.spotAt(at:getX(), at:getY(), at:getZ()) == nil, "the site's spot was not forgotten once placed")
    local objects = at:getObjects():size() + far:getObjects():size()
    loadChunks()
    local addedAgain = at:getObjects():size() + far:getObjects():size() - objects
    expect(addedAgain == 0, "loading the chunks again added " .. addedAgain .. " objects to the site")
    local pamphlets = def and takeNewPamphlets(def, before)
    KIND_CHECKS[args.kind](expect, expectNear, at, far, pamphlets)
end)

-- A world saved while every site was rolled at once (`rolled` true) rolls a site added since,
-- once, and none of the sites it rolled then; a site the world has rolled is never rolled again,
-- `always` or not; and the option at 0 keeps a new `always` site out while marking it rolled. The
-- sites are stock tank pumps whose spots wait on the outdoor squares `args.squares`; their spots
-- and the world's rolls are put back when the test ends.
check("siteRolledOnce", function(expect, _, _, args, defer)
    local SolarSites = RenewableEnergy.SolarSites
    local modData = SGlobalObjects.getSystemByName(SolarSites.SYSTEM_NAME):getModData()
    local saved = modData.rolled
    defer(function() modData.rolled = saved end)
    local sites = {}
    -- One of the sites a world rolled at once, and two added since.
    for i, name in ipairs({ "Pasture north of Rosewood", "test site added later", "test site added with the option at 0" }) do
        local square = args.squares[i]
        sites[i] = { kind = "stockTank", name = name, always = true, panels = { { square.x, square.y, square.z, "rackMetal", "S" } } }
        defer(function() forgetSpot(square.x, square.y, square.z) end)
    end
    local function waits(i)
        local square = args.squares[i]
        return SolarSites.spotAt(square.x, square.y, square.z) ~= nil
    end
    modData.rolled = true
    SolarSites.rollNew({ sites[1], sites[2] })
    expect(not waits(1), "a world that rolled every site at once rolled " .. sites[1].name .. " again")
    expect(waits(2), "a world that rolled every site at once never rolled a site added since")
    local rolled = modData.rolled
    expect(type(rolled) == "table" and rolled[sites[1].name] and rolled[sites[2].name],
        "the world doesn't remember the sites it rolled")
    forgetSpot(args.squares[2].x, args.squares[2].y, args.squares[2].z)
    SolarSites.rollNew({ sites[1], sites[2] })
    expect(not waits(2), "a site the world had rolled was rolled again")
    local restore = saveOptions(defer, { "SolarSites" })
    SandboxVars.RenewableEnergy.SolarSites = 0
    SolarSites.rollNew({ sites[3] })
    restore()
    expect(not waits(3), "with the option at 0 a new always site was rolled in")
    expect(modData.rolled[sites[3].name], "with the option at 0 a new site wasn't marked rolled")
end)

-- Whether `square` holds what a site places: a tile of the mod's or a generator.
local function holdsSiteObject(square)
    return RenewableEnergy.findObjectOn(square, function(object)
        return RenewableEnergy.GasKit.isGenerator(object) or Sprites.kindOf(Sprites.nameOf(object)) ~= nil
    end) ~= nil
end

-- Open ground with nothing on it, as RuralFinds puts its finds on.
local function isOpenGround(square)
    return square:getZ() == 0 and square:getBuilding() == nil and square:isOutside() and square:hasFloor()
        and not square:HasTree() and not square:getProperties():has(IsoFlagType.water)
        and square:isFree(false) and square:getSpecialObjects():size() == 0
end

-- No building, tree or wall within a square of `square`, as a wind charger wants.
local function inTheOpen(square)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local near = getSquare(square:getX() + dx, square:getY() + dy, 0)
            if not near or near:getBuilding() or near:HasTree() or near:getWall(true) or near:getWall(false) then
                return false
            end
        end
    end
    return true
end

-- What a site's square must be, by the kind of spot.
local SQUARE_NEEDS = {
    ground = { what = "free open ground", fits = isOpenGround },
    open = { what = "free open ground with nothing around it", fits = function(square) return isOpenGround(square) and inTheOpen(square) end },
    room = { what = "a free floor square indoors", fits = function(square)
        return RenewableEnergy.PowerBank.canPlaceBank(square) and square:isFree(false)
    end },
    roof = { what = "a free flat roof", fits = function(square)
        return square:isOutside() and square:hasFloor() and square:isFree(false)
    end },
    building = { what = "a building", fits = function(square) return square:getBuilding() ~= nil end },
}

-- Each square the site `site` uses, as { x, y, z, need }, need a SQUARE_NEEDS key.
local function siteSquares(site)
    local squares = {}
    for _, panel in ipairs(site.panels or {}) do
        table.insert(squares, { panel[1], panel[2], panel[3], need = panel[3] > 0 and "roof" or "ground" })
    end
    for field, need in pairs({ bank = "room", crate = "room", windCharger = "open", digester = "ground", gasifier = "ground", generator = "ground" }) do
        local spot = site[field]
        if spot then
            table.insert(squares, { spot[1], spot[2], spot[3], need = need })
        end
    end
    if site.house then
        table.insert(squares, { site.house[1], site.house[2], 0, need = "building" })
    end
    return squares
end

-- The squares of the site named `args.name`, in the world as loaded here: { ready = false, why }
-- until every one has loaded, then each square that isn't what its spot needs, as text. A square
-- already holding what a site places passes, since the world may have placed the site meanwhile.
handler("siteSquaresAt", function(_, args)
    local found
    for _, site in ipairs(RenewableEnergy.SolarSites.sites()) do
        if site.name == args.name then
            found = site
        end
    end
    if not found then
        return nil, "a site named " .. tostring(args.name)
    end
    local wrong = {}
    for _, spot in ipairs(siteSquares(found)) do
        local square = getSquare(spot[1], spot[2], spot[3])
        local where = spot[1] .. "," .. spot[2] .. "," .. spot[3]
        if not square then
            return { ready = false, why = where .. " not loaded" }
        end
        local need = SQUARE_NEEDS[spot.need]
        if not (need.fits(square) or (spot.need ~= "building" and holdsSiteObject(square))) then
            table.insert(wrong, where .. " is not " .. need.what)
        end
    end
    return { ready = true, wrong = wrong }
end)
