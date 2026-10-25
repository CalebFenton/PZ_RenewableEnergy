-- The authority's half of the solar site tests. The tests arm a site's spots with
-- SolarSites.addSite and let the world place them: when the chunk that holds a spot loads, the
-- system's OnChunkLoaded places it, or queues it for the next game minute. Nothing here places a
-- spot by hand. Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
require "RenewableEnergy/Sprites"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler, check, saveOptions = PZHarness.serverHandler, Helpers.check, Helpers.saveOptions
local objectWithSprite = PZHarness.Fixtures.objectWithSprite
local squareAt, removePlaced = Helpers.squareAt, PZHarness.Fixtures.removePlaced
local inRange, wearRange = Helpers.inRange, Helpers.wearRange
local Sprites = RenewableEnergy.Sprites

local MODULE = RenewableEnergy.Specs.factoryModule

-- Whether a module's condition is one a site, crate or arrow board gives: cracked or weathered.
local function isSiteCondition(condition)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    return inRange(condition, WorldSpawns.CRACKED) or inRange(condition, WorldSpawns.WEATHERED)
end

-- The site named `name` of this world's map, or nil.
local function siteNamed(name)
    for _, site in ipairs(RenewableEnergy.SolarSites.sites()) do
        if site.name == name then
            return site
        end
    end
    return nil
end

-- Forgets the site spot at x, y, z, if one waits there.
local function forgetSpot(x, y, z)
    local system = SGlobalObjects.getSystemByName(RenewableEnergy.SolarSites.SYSTEM_NAME)
    local object = system:getObjectAt(x, y, z)
    if object then
        system:removeObject(object)
    end
end

-- Every square a spot of the site may stand on, each { x, y, z }.
local function spotSquares(site)
    local squares = {}
    for _, panel in ipairs(site.panels or {}) do
        table.insert(squares, { panel[1], panel[2], panel[3] })
    end
    for _, field in ipairs({ "bank", "crate", "arrowBoard", "windCharger", "digester", "gasifier" }) do
        local spot = site[field]
        if spot then
            table.insert(squares, { spot[1], spot[2], spot[3] })
        end
    end
    if site.house then
        table.insert(squares, { site.house[1], site.house[2], 0 })
    end
    return squares
end

-- The buildings by x, y that could have the find `kind` (RuralFinds.buildingsBy), added to `found`
-- by key.
local function buildingsOfFind(kind, x, y, found)
    for _, def in ipairs(RenewableEnergy.RuralFinds.buildingsBy(kind, x, y)) do
        found[RenewableEnergy.BuildingWatch.key(def)] = def
    end
    return found
end

-- The find kind of a homestead site, its square, and the buildings whose own rural find roll
-- could give the farm another: those by the find and, for a wind charger, by its bank. Nil for
-- another site.
local function findOf(site)
    local kind = RenewableEnergy.SolarSites.KINDS[site.kind]
    if kind.wind then
        local at, bank = site.windCharger, site.bank
        return "wind", at, buildingsOfFind("wind", bank[1], bank[2], buildingsOfFind("wind", at[1], at[2], {}))
    elseif kind.gas then
        local at = site[kind.gas]
        return kind.gas, at, buildingsOfFind(kind.gas, at[1], at[2], {})
    end
    return nil
end

-- Arms the site's spots as the world does when it rolls the site in, after forgetting any the
-- world kept there, and forgets them when the test ends, along with what arming a homestead site
-- wrote into the rural find rolls of the buildings by its find. Answers the armed spots as plain
-- values: each spot's fields with its x, y, z.
local function armSite(site, defer)
    local SolarSites = RenewableEnergy.SolarSites
    local squares = spotSquares(site)
    for _, at in ipairs(squares) do
        forgetSpot(at[1], at[2], at[3])
    end
    local _, _, defs = findOf(site)
    for _, def in pairs(defs or {}) do
        Helpers.keepBuildingRoll(RenewableEnergy.RuralFinds.MOD_DATA, def, defer)
    end
    SolarSites.addSite(site)
    local spots = {}
    for _, at in ipairs(squares) do
        local fields = SolarSites.spotAt(at[1], at[2], at[3])
        if fields then
            local spot = { x = at[1], y = at[2], z = at[3] }
            for _, key in ipairs({ "what", "siteKind", "mount", "facing", "stock", "source", "toX", "toY", "toZ" }) do
                spot[key] = fields[key]
            end
            table.insert(spots, spot)
            defer(function() forgetSpot(at[1], at[2], at[3]) end)
        end
    end
    return spots
end

-- Whether the object is one a site places: a tile of the mod's, a bank or a generator.
local function isSiteObject(object)
    return RenewableEnergy.isGenerator(object) or RenewableEnergy.PowerBank.isBank(object)
        or Sprites.kindOfObject(object) ~= nil
end

-- Removes what a site put on `square`, a generator out of the gas pass's list too.
local function clearSquare(square)
    local objects = square:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local object = objects:get(i)
        if isSiteObject(object) then
            if RenewableEnergy.isGenerator(object) then
                RenewableEnergy.GasLines.unlist(object)
            end
            removePlaced(object)
        end
    end
end

-- The squares the spots took, their far ends included, each loaded here; or nil and the first
-- that isn't.
local function spotSquaresLoaded(spots)
    local squares = {}
    for _, spot in ipairs(spots) do
        for _, at in ipairs({ { spot.x, spot.y, spot.z }, spot.toX and { spot.toX, spot.toY, spot.toZ } or nil }) do
            local square = getSquare(at[1], at[2], at[3])
            if not square then
                return nil, at[1] .. "," .. at[2] .. "," .. at[3] .. " not loaded"
            end
            table.insert(squares, square)
        end
    end
    return squares
end

-- The kitted generator on `square` against the line it should have to the `kind` source at
-- `source`: plugged in, off, run down and low on petrol as SolarSites.GENERATOR says, on gas with
-- its line connected and listed for the gas pass, its kit drawn on it. Answers the generator.
local function expectKittedGenerator(expect, expectNear, square, source, kind)
    local GasKit, SolarSites = RenewableEnergy.GasKit, RenewableEnergy.SolarSites
    local generator = RenewableEnergy.findObjectOn(square, RenewableEnergy.isGenerator)
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
    expect(RenewableEnergy.GasLines.isListed(generator), "the gas pass doesn't list the generator")
    local overlays = Helpers.overlaysOf(generator)
    local kit = Sprites.gasKitFor(Sprites.nameOf(generator))
    local hasKit = false
    for _, overlay in ipairs(overlays) do
        hasKit = hasKit or overlay == kit
    end
    expect(hasKit, "the generator doesn't show its kit")
    return generator, state, overlays
end

-- What each kind of spot leaves on its square once placed, checked once the world placed it.
-- Each records what is wrong; `spot` is the armed spot, `far` the square at its far end.
local SPOT_CHECKS = {
    -- A mount of its tile holding modules at site conditions, as many as its kind says.
    panel = function(expect, _, square, spot)
        local SolarSites = RenewableEnergy.SolarSites
        local mount = objectWithSprite(square, SolarSites.mountSprite(spot.mount, spot.facing))
        if not expect(mount ~= nil, "no " .. spot.mount .. " mount on the panel spot") then
            return
        end
        local modules = mount:getModData()[RenewableEnergy.PowerBank.MODULES_KEY] or {}
        local range = SolarSites.KINDS[spot.siteKind].modules
        if range then
            expect(inRange(#modules, range), #modules .. " modules on the " .. spot.siteKind .. "'s mount, expected "
                .. range.min .. " to " .. range.max)
        else
            expect(#modules > 0, "the " .. spot.siteKind .. "'s mount holds no modules")
        end
        for _, module in ipairs(modules) do
            expect(module.type == MODULE and isSiteCondition(module.condition),
                "the mount holds " .. tostring(module.type) .. " at " .. tostring(module.condition))
        end
    end,
    bank = function(expect, _, square, spot)
        local bank = RenewableEnergy.PowerBank.findOn(square)
        local stock = RenewableEnergy.WorldSpawns.BANK_STOCK[spot.stock]
        expect(bank ~= nil and Sprites.kindOfObject(bank) == stock.sprite, "no " .. spot.stock .. " bank on the bank spot")
    end,
    crate = function(expect, _, square)
        expect(objectWithSprite(square, Sprites.crate) ~= nil, "no crate on the crate spot")
    end,
    -- The wind charger braked with its blades broken, wired to a plugged-in rack of tired batteries.
    windCharger = function(expect, _, at, spot, far)
        local Wind, PowerBank, WorldSpawns = RenewableEnergy.Wind, RenewableEnergy.PowerBank, RenewableEnergy.WorldSpawns
        local charger = RenewableEnergy.findObjectOn(at, Wind.isCharger)
        local bank = PowerBank.findOn(far)
        if not (expect(charger ~= nil, "no wind charger on the site's square") and expect(bank ~= nil, "no bank on the site's bank square")) then
            return
        end
        expect(Sprites.kindOfObject(charger) == "propeller", "the wind charger is a " .. tostring(Sprites.kindOfObject(charger)))
        expect(Wind.isBroken(charger) and Wind.isBraked(charger), "the wind charger is found broken " .. tostring(Wind.isBroken(charger))
            .. ", braked " .. tostring(Wind.isBraked(charger)))
        local stock = WorldSpawns.BANK_STOCK[spot.stock]
        expect(Sprites.kindOfObject(bank) == stock.sprite, "the bank stands on " .. tostring(Sprites.nameOf(bank)))
        expect(bank:isConnected(), "the bank isn't plugged in")
        local wired = PowerBank.bankOfSource(at:getX(), at:getY(), at:getZ())
        expect(wired ~= nil and PowerBank.samePosition(wired, { x = far:getX(), y = far:getY(), z = far:getZ() }),
            "the wind charger isn't wired to the site's bank")
        local wear = WorldSpawns.BATTERY_WEAR[stock.batteries.wear]
        local range = wearRange(wear)
        local batteries, items = 0, bank:getContainer():getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if RenewableEnergy.Battery.isBattery(item) then
                batteries = batteries + 1
                expect(item:getFullType() == "RenewableEnergy.DeepCycleBattery" and inRange(item:getCondition(), range),
                    "the bank holds a " .. item:getFullType() .. " at condition " .. item:getCondition())
            end
        end
        expect(inRange(batteries, stock.batteries), batteries .. " batteries in the bank")
    end,
    -- The digester cold, torn and sour, or the primitive gasifier with a full ash pit and its
    -- packing all tarred, piped to the kitted generator.
    gasLine = function(expect, expectNear, at, spot, far)
        local record, object = Helpers.recordAt({ kind = spot.source, x = at:getX(), y = at:getY(), z = at:getZ() })
        if not expect(record ~= nil, "no " .. spot.source .. " on the site's square") then
            return
        end
        local GasKit, Gasifier = RenewableEnergy.GasKit, RenewableEnergy.Gasifier
        if spot.source == "digester" then
            expect(record.sour and record:isTorn(), "the digester is found sour " .. tostring(record.sour) .. ", torn "
                .. tostring(record:isTorn()))
        else
            local clean, tarry = Gasifier.filterCounts(Gasifier.filterOf(object))
            expect(Sprites.nameOf(object) == Sprites.gasifier.primitive and record.ash == Gasifier.ASH_FULL and clean == 0 and tarry > 0,
                "the gasifier is found " .. tostring(Sprites.nameOf(object)) .. ", ash " .. tostring(record.ash) .. ", "
                .. clean .. " clean and " .. tarry .. " tarry packing")
            local side = Gasifier.sideOf(at:getX(), at:getY(), far:getX(), far:getY())
            expect(record.pipe == side, "the gasifier's pipe runs " .. tostring(record.pipe) .. ", not " .. tostring(side))
        end
        local generator, state, overlays = expectKittedGenerator(expect, expectNear, far, object, spot.source)
        if not (generator and state.line) then
            return
        end
        if spot.source == "digester" then
            expect(state.line.item == GasKit.HOSE and state.line.count == GasKit.hosesFor(generator, object),
                "the line took " .. tostring(state.line.count) .. " " .. tostring(state.line.item))
        else
            local pipe = Sprites.gasifierPipeGenFor(Sprites.nameOf(generator), Gasifier.sideOf(far:getX(), far:getY(), at:getX(), at:getY()))
            local piped = false
            for _, overlay in ipairs(overlays) do
                piped = piped or overlay == pipe
            end
            expect(piped, "the generator doesn't show its half of the pipe")
            expect(state.line.item == GasKit.PIPE and state.line.count == 1,
                "the line took " .. tostring(state.line.count) .. " " .. tostring(state.line.item))
        end
    end,
    pamphlet = function(expect, _, square)
        local building = square:getBuilding()
        expect(building ~= nil and Helpers.readingTotal(building:getDef(), RenewableEnergy.RuralFinds.PAMPHLET) >= 1, "no pamphlet in the house")
    end,
    -- The house promised its lights, or rolled for them already.
    gardenLights = function(expect, _, square)
        local building = square:getBuilding()
        local GardenLights = RenewableEnergy.GardenLights
        local roll = building and ModData.getOrCreate(GardenLights.MOD_DATA)[RenewableEnergy.BuildingWatch.key(building:getDef())]
        expect(roll ~= nil, "the site's house was promised no garden lights")
    end,
}

-- For each armed spot whose site waits there no more: what it left, recorded as SPOT_CHECKS says,
-- or that it was never placed. Answers what is missing while a square isn't loaded here.
local function checkSpots(expect, expectNear, spots)
    local SolarSites = RenewableEnergy.SolarSites
    local _, notLoaded = spotSquaresLoaded(spots)
    if notLoaded then
        return notLoaded
    end
    for _, spot in ipairs(spots) do
        local where = spot.what .. " spot at " .. spot.x .. "," .. spot.y .. "," .. spot.z
        if expect(SolarSites.spotAt(spot.x, spot.y, spot.z) == nil, "the " .. where .. " still waits (the log says why)")
            and expect(SPOT_CHECKS[spot.what] ~= nil, "no check for a " .. where) then
            local far = spot.toX and getSquare(spot.toX, spot.toY, spot.toZ)
            SPOT_CHECKS[spot.what](expect, expectNear, getSquare(spot.x, spot.y, spot.z), spot, far)
        end
    end
end

-- How many objects stand on the squares, and how many of them a site places.
local function objectCounts(squares)
    local count, placed = 0, 0
    for _, square in ipairs(squares) do
        local objects = square:getObjects()
        count = count + objects:size()
        for i = 0, objects:size() - 1 do
            if isSiteObject(objects:get(i)) then
                placed = placed + 1
            end
        end
    end
    return count, placed
end

-- How many of the armed spots still wait.
local function waitingSpots(spots)
    local waiting = 0
    for _, spot in ipairs(spots) do
        if RenewableEnergy.SolarSites.spotAt(spot.x, spot.y, spot.z) then
            waiting = waiting + 1
        end
    end
    return waiting
end

-- How many of the armed spots `args.spots` still wait, and how many objects stand on their
-- squares and far ends, loaded here, and of them what a site places.
handler("siteSpots", function(_, args)
    local squares, notLoaded = spotSquaresLoaded(args.spots)
    if not squares then
        return nil, notLoaded
    end
    local objects, placed = objectCounts(squares)
    return { waiting = waitingSpots(args.spots), objects = objects, placed = placed }
end)

-- Open ground a wind charger may stand on (RuralFinds.canPlace) within reach of the bank's
-- square, nearest first, or nil.
local function chargerSquareFor(bank)
    local position = { x = bank:getX(), y = bank:getY(), z = bank:getZ() }
    for r = 1, RenewableEnergy.Specs.sourceReach.tiles do
        for x, y in PZHarness.Fixtures.ring(position.x, position.y, r) do
            local square = getSquare(x, y, 0)
            if RenewableEnergy.RuralFinds.canPlace("wind", square)
                and RenewableEnergy.PowerBank.isInReach(position, x, y, 0) then
                return square
            end
        end
    end
    return nil
end

-- A test site armed near the character: a stock tank pump's rack on the square at `args.at`, or
-- a wind farm whose bank stands on the square at `args.bank` and its charger on open ground in
-- reach of it. With `args.block` a work table, as a player's things would, stands on the rack's
-- or the charger's square first. Answers the armed spots and that square; what the site placed is
-- removed when the test ends.
handler("siteArm", function(_, args, defer)
    local bank = squareAt(args.bank)
    local at = bank and chargerSquareFor(bank) or squareAt(args.at)
    if not (at and (bank or not args.bank)) then
        return nil, "the site's squares loaded on the server, open ground for a wind charger by the bank"
    end
    local ends = { at:getX(), at:getY(), at:getZ() }
    local site
    if bank then
        site = { kind = "windFarm", name = "test wind farm", windCharger = ends, bank = { bank:getX(), bank:getY(), bank:getZ() } }
    else
        site = { kind = "stockTank", name = "test stock tank", panels = { { ends[1], ends[2], ends[3], "rackMetal", "S" } } }
    end
    -- By position: the trips away load the chunk again with new squares and objects.
    for _, square in ipairs({ at, bank }) do
        local x, y, z = square:getX(), square:getY(), square:getZ()
        defer(function()
            local now = getSquare(x, y, z)
            if now then
                clearSquare(now)
                local blocker = objectWithSprite(now, PZHarness.Fixtures.WORK_TABLE_SPRITE)
                if blocker and args.block then
                    removePlaced(blocker)
                end
            end
        end)
    end
    if args.block then
        PZHarness.Fixtures.newTile(at, PZHarness.Fixtures.WORK_TABLE_SPRITE)
    end
    return { spots = armSite(site, defer), at = { x = ends[1], y = ends[2], z = ends[3] } }
end)

-- Takes the work table siteArm put on the square at `args` away.
handler("siteUnblock", function(_, args)
    local square = squareAt(args)
    local blocker = square and objectWithSprite(square, PZHarness.Fixtures.WORK_TABLE_SPRITE)
    if not blocker then
        return nil, "the work table on the site's square"
    end
    removePlaced(blocker)
    return {}
end)

-- The armed spots `args.spots` were placed by the world, each as its kind leaves it.
check("sitePlaced", function(expect, expectNear, _, args)
    return checkSpots(expect, expectNear, args.spots)
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

-- Real sites ------------------------------------------------------------------------------------

-- Arms the sites named `args.names` as the world does when it rolls one in, while the character is
-- far from them, so that the world places them when the character gets there. Answers each site's
-- armed spots by name, and for a homestead site the buildings by its find that its own roll could
-- have given one, by key, with the finds their rolls count, read right after arming. Those rolls
-- are put back when the test ends.
handler("sitesArm", function(_, args, defer)
    local RuralFinds = RenewableEnergy.RuralFinds
    local armed = {}
    for _, name in ipairs(args.names) do
        local site = siteNamed(name)
        if not site then
            return nil, "a site named " .. tostring(name)
        end
        local kind, _, defs = findOf(site)
        local spots = armSite(site, defer)
        local claimed = {}
        for key, def in pairs(defs or {}) do
            local finds = {}
            for found in pairs(RuralFinds.rolled(def) or {}) do
                table.insert(finds, found)
            end
            claimed[key] = finds
        end
        armed[name] = { spots = spots, find = kind, claimed = claimed }
    end
    return armed
end)

-- The site whose armed spots are `args.spots`: { ready = false, why } until every spot's square is
-- loaded here, then how many of its spots still wait.
handler("siteVisit", function(_, args)
    local squares, notLoaded = spotSquaresLoaded(args.spots)
    if not squares then
        return { ready = false, why = notLoaded }
    end
    return { ready = true, waiting = waitingSpots(args.spots) }
end)

-- The site named `args.name` was placed by the world as its armed spots `args.spots` say, and no
-- building that counts a homestead site's find got another find of that kind by it.
check("siteVisited", function(expect, expectNear, _, args)
    local missing = checkSpots(expect, expectNear, args.spots)
    if missing then
        return missing
    end
    local kind, at, defs = findOf(siteNamed(args.name))
    if not kind then
        return
    end
    for key, def in pairs(defs) do
        local others = Helpers.findsAround(def, RenewableEnergy.RuralFinds.FINDS[kind].is, at)
        expect(others == 0, args.name .. ": " .. others .. " more " .. kind .. " finds by the building at " .. key)
    end
end)

-- Takes away what the site named `args.name` placed on the squares of its armed spots `args.spots`
-- and their far ends, and the pamphlets of its house, while they are loaded: the test moves on.
handler("siteClear", function(_, args)
    local squares, notLoaded = spotSquaresLoaded(args.spots)
    if not squares then
        return nil, notLoaded
    end
    for _, square in ipairs(squares) do
        clearSquare(square)
    end
    local site = siteNamed(args.name)
    local house = site and site.house and getSquare(site.house[1], site.house[2], 0)
    if house and house:getBuilding() then
        Helpers.takeReadingSince(house:getBuilding():getDef(), RenewableEnergy.RuralFinds.PAMPHLET, {})
    end
    return {}
end)
