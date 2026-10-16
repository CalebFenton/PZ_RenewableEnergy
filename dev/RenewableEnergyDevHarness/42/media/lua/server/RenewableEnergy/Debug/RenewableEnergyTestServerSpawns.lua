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
-- first time places one. Answers whether it placed one, its tile and stock, and whether a battery
-- box stands on the square. Removed when the test ends.
handler("worldBank", function(_, args, defer)
    local square = squareAt(args)
    if not square then
        return nil, "the bank's square loaded on the server"
    end
    local bank = RenewableEnergy.WorldSpawns.placeBank(square, args.stock)
    if bank then
        defer(function() removeObject(bank) end)
    end
    local answer = { placed = bank ~= nil, boxOnSquare = objectWithSprite(square, Sprites.batteryBoxWood) ~= nil }
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
    expect(defaultChance > 0 and defaultChance < 0.1, "a garage shelf holds a cracked module with chance " .. defaultChance)
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

-- Every site's spots make sense on the map: banks and crates in a room (banks only work indoors),
-- panels outdoors, wall panels on a building's wall, garden lights at a building, arrow boards
-- outdoors with a facing; each site has a unique name, a known kind, and the spots its
-- kind uses, as many panel spots as the kind may place.
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
        end
    end
end)
