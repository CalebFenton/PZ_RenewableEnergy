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
local squareAt, removePlaced = Helpers.squareAt, PZHarness.Fixtures.removePlaced
local inRange, UNDER = Helpers.inRange, Helpers.UNDER
local Sprites = RenewableEnergy.Sprites

local MODULE = RenewableEnergy.Specs.factoryModule

-- Whether a module's condition is one a site, crate or arrow board gives: cracked or weathered.
local function isSiteCondition(condition)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    return inRange(condition, WorldSpawns.CRACKED) or inRange(condition, WorldSpawns.WEATHERED)
end

-- The batteries' charges and conditions, in container order.
local function batteryStats(container)
    local charges, conditions = {}, {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if RenewableEnergy.Battery.isBattery(item) then
            table.insert(charges, RenewableEnergy.Battery.getCharge(item))
            table.insert(conditions, item:getCondition())
        end
    end
    return charges, conditions
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

-- What a world spawn left in `container`: its batteries' charges and conditions, its modules'
-- conditions and how many items it holds.
local function stockOf(container)
    local charges, conditions = batteryStats(container)
    return {
        charges = charges, batteryConditions = conditions, modules = moduleConditions(container),
        items = container:getItems():size(), explored = container:isExplored(),
    }
end

-- WorldSpawns.placeBank with BANK_STOCK[args.stock] on the square at `args`, as a room seen for the
-- first time places one, with every Chance roll at `args.roll` if given. Answers whether it placed
-- one, its tile and stock, and whether the stock's tile, in any facing, stands on the square.
-- Removed when the test ends.
handler("worldBank", function(_, args, defer)
    local square = squareAt(args)
    if not square then
        return nil, "the bank's square loaded on the server"
    end
    local restoreRoll = args.roll and Helpers.forceRolls(defer, args.roll)
    local bank = RenewableEnergy.WorldSpawns.placeBank(square, args.stock)
    if restoreRoll then restoreRoll() end
    if bank then
        defer(function() removePlaced(bank) end)
    end
    local kind = RenewableEnergy.WorldSpawns.BANK_STOCK[args.stock].sprite
    local onSquare = RenewableEnergy.findObjectOn(square, function(object) return Sprites.kindOfObject(object) == kind end)
    local answer = { placed = bank ~= nil, boxOnSquare = onSquare ~= nil }
    if bank then
        answer.sprite = bank:getTextureName()
        answer.stock = stockOf(bank:getContainer())
    end
    return answer
end)

-- The world items lying on the square at `square` and the squares around it, each to its square.
local function itemsAround(square)
    local found = {}
    for dx = -1, 1 do
        for dy = -1, 1 do
            local near = getSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            local objects = near and near:getWorldObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                found[objects:get(i)] = near
            end
        end
    end
    return found
end

-- WorldSpawns.layModulesBeside for a BANK_STOCK[args.stock] bank on the square at `args`, with
-- every Chance roll at `args.roll`. Answers how many it laid and, of the modules that have come to
-- lie on the square and around it, their conditions and whether each lies in the square's room.
-- Removed when the test ends.
handler("bankModulesBeside", function(_, args, defer)
    local square = squareAt(args)
    if not square then
        return nil, "the bank's square loaded on the server"
    end
    local before = itemsAround(square)
    local restoreRoll = Helpers.forceRolls(defer, args.roll)
    local laid = RenewableEnergy.WorldSpawns.layModulesBeside(square, args.stock)
    restoreRoll()
    local answer = { laid = laid, conditions = {}, inRoom = true }
    for object, near in pairs(itemsAround(square)) do
        if not before[object] and object:getItem():getFullType() == MODULE then
            table.insert(answer.conditions, object:getItem():getCondition())
            answer.inRoom = answer.inRoom and near:getRoom() == square:getRoom()
            defer(function() removePlaced(object) end)
        end
    end
    return answer
end)

-- The parts a bank may hold besides batteries, as PowerBank.partKind names them.
local PARTS = { "inverter", "controller", "charger" }

-- What BANK_STOCK[stockName] puts in an emptied `container` with every roll at `roll`: how many of
-- each of PARTS.
local function bankPartsAt(container, stockName, roll, defer)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local restoreRoll = Helpers.forceRolls(defer, roll)
    local found = { inverter = 0, controller = 0, charger = 0 }
    local function stock(c) WorldSpawns.stockBank(c, stockName) end
    for fullType, count in pairs(RenewableEnergy.Loot.fillOnce(stock, container, true)) do
        local kind = RenewableEnergy.PowerBank.partKind(fullType)
        if found[kind] then
            found[kind] = found[kind] + count
        end
    end
    restoreRoll()
    return found
end

-- Every stock's parts are of their line's kind, each at a chance; the bank `args.stock` holds a
-- part when the roll comes in under its chance × the misc loot option and not at it, so neither a
-- part's chance nor the option goes astray; and a battery box (a tile of `args.boxTiles`), which has
-- no slot for a charge controller, never gets one, even from a stock that lists one.
check("bankStockParts", function(expect, _, _, args, defer)
    local WorldSpawns, PowerBank = RenewableEnergy.WorldSpawns, RenewableEnergy.PowerBank
    for stockName, stock in pairs(WorldSpawns.BANK_STOCK) do
        for _, kind in ipairs(PARTS) do
            local part = stock[kind]
            if part then
                expect(part.chance > 0 and part.chance <= 1, stockName .. " banks hold a " .. kind .. " with chance " .. part.chance)
                for _, entry in ipairs(part.types) do
                    expect(PowerBank.partKind(entry[1]) == kind, stockName .. "'s " .. kind .. " line holds a " .. entry[1])
                end
            end
        end
    end
    local container = RenewableEnergy.Loot.newContainer(nil)
    -- Found batteries are sent to the clients that see them, and a server can't send an item of a
    -- container that isn't in the world; the parts don't depend on the batteries.
    local options = SandboxVars.RenewableEnergy
    local restoreOptions = saveOptions(defer, { "LRMBatteries", "LRMMisc" })
    options.LRMBatteries = 0
    local stock = WorldSpawns.BANK_STOCK[args.stock]
    for _, multiplier in ipairs({ 1, 2 }) do
        options.LRMMisc = multiplier
        for _, kind in ipairs(PARTS) do
            if expect(stock[kind], args.stock .. " banks list no " .. kind) then
                local edge = stock[kind].chance * multiplier
                local under = bankPartsAt(container, args.stock, edge - UNDER, defer)[kind]
                local at = bankPartsAt(container, args.stock, edge, defer)[kind]
                expect(under == 1 and at == 0, string.format("at misc option %s a %s bank holds %d %s with a roll just under %s and %d at it",
                    multiplier, args.stock, under, kind, edge, at))
            end
        end
    end
    -- args.stock's batteries and a certain controller, on each box tile and on args.stock's rack.
    options.LRMMisc = 1
    local name = "renewableEnergyTestSlots"
    defer(function() WorldSpawns.BANK_STOCK[name] = nil end)
    local sprites = { [stock.sprite] = false }
    for sprite in pairs(args.boxTiles) do
        sprites[sprite] = true
    end
    for sprite, isBox in pairs(sprites) do
        WorldSpawns.BANK_STOCK[name] = { sprite = sprite, batteries = stock.batteries,
            controller = { chance = 1, types = { { RenewableEnergy.Specs.controller, 1 } } } }
        local controllers = bankPartsAt(container, name, 0, defer).controller
        expect(controllers == (isBox and 0 or 1), "a " .. sprite .. " bank listing a certain controller holds " .. controllers)
    end
    WorldSpawns.BANK_STOCK[name] = nil
    restoreOptions()
end)

-- Every stock's batteries name a wear profile. Each profile wears a found battery to its mean less
-- its half width at the lowest rolls, its mean at middling ones, and no better than new at the
-- highest, unrepaired; with a dud chance, a roll just under it makes a dud, at the dud's lowest
-- and highest condition by the next roll, with the dud's repairs, and a roll at it doesn't.
check("batteryWear", function(expect, _, _, _, defer)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local dud = WorldSpawns.DUD
    for stockName, stock in pairs(WorldSpawns.BANK_STOCK) do
        expect(WorldSpawns.BATTERY_WEAR[stock.batteries.wear] ~= nil, stockName .. " batteries wear as " .. tostring(stock.batteries.wear))
    end
    local function worn(name, rolls)
        local item = instanceItem("RenewableEnergy.DeepCycleBattery")
        local restoreRoll = Helpers.forceRolls(defer, rolls)
        WorldSpawns.wearFoundBattery(item, name)
        restoreRoll()
        return { condition = item:getCondition(), repairs = item:getHaveBeenRepaired() }
    end
    local TOP = 1 - UNDER
    for name, wear in pairs(WorldSpawns.BATTERY_WEAR) do
        -- A profile with duds rolls for one first; at the chance, it isn't one.
        local first = wear.dud and { wear.dud } or {}
        local cases = {
            { roll = 0, condition = wear.mean - wear.halfWidth },
            { roll = 0.5, condition = wear.mean },
            { roll = TOP, condition = math.min(100, wear.mean + wear.halfWidth) },
        }
        for _, case in ipairs(cases) do
            local rolls = { unpack(first) }
            for _ = 1, 3 do table.insert(rolls, case.roll) end
            local got = worn(name, rolls)
            expect(got.condition == case.condition and got.repairs == 0, string.format("%s at rolls of %s wears a battery to %d with %d repairs, not %d",
                name, case.roll, got.condition, got.repairs, case.condition))
        end
        if wear.dud then
            for _, case in ipairs({ { roll = 0, condition = dud.min }, { roll = TOP, condition = dud.max } }) do
                local got = worn(name, { wear.dud - UNDER, case.roll })
                expect(got.condition == case.condition and got.repairs == dud.repairs, string.format(
                    "a %s dud at a roll of %s has condition %d and %d repairs, not %d and %d",
                    name, case.roll, got.condition, got.repairs, case.condition, dud.repairs))
            end
        end
    end
end)

-- PART_WEAR wears every inverter and the charge controller, not the battery charger: to its mean
-- less its half width at the lowest rolls, its mean at middling ones and no better than new at the
-- highest; a roll just under its dud chance makes a dud, at PART_DUD's lowest and highest condition
-- by the next roll, worse than any working find, and a roll at it doesn't. Each worn part is marked
-- as having a condition of its own. With every roll middling, the parts of a bank's stock, a
-- crate's and an arrow board's battery box come at the mean, marked.
check("partWear", function(expect, _, _, _, defer)
    local WorldSpawns, Specs, Wear = RenewableEnergy.WorldSpawns, RenewableEnergy.Specs, RenewableEnergy.Wear
    local wear, dud = WorldSpawns.PART_WEAR, WorldSpawns.PART_DUD
    expect(dud.min >= 0 and dud.min <= dud.max and dud.max < wear.mean - wear.halfWidth,
        "a part dud's condition " .. dud.min .. " to " .. dud.max .. " overlaps a found part's from " .. wear.mean - wear.halfWidth)
    local types = { Specs.controller }
    for fullType in pairs(Specs.inverters) do
        table.insert(types, fullType)
    end
    for _, fullType in ipairs(types) do
        expect(WorldSpawns.isWornPart(fullType), fullType .. " isn't worn when found")
    end
    expect(not WorldSpawns.isWornPart(Specs.charger), Specs.charger .. " is worn when found")
    local function worn(fullType, rolls)
        local item = instanceItem(fullType)
        local restoreRoll = Helpers.forceRolls(defer, rolls)
        WorldSpawns.wearFoundPart(item)
        restoreRoll()
        return item:getCondition(), Wear.hasOwnCondition(item)
    end
    local TOP = 1 - UNDER
    for _, fullType in ipairs(types) do
        for _, case in ipairs({
            { roll = 0, condition = wear.mean - wear.halfWidth },
            { roll = 0.5, condition = wear.mean },
            { roll = TOP, condition = math.min(100, wear.mean + wear.halfWidth) },
        }) do
            local condition, marked = worn(fullType, { wear.dud, case.roll, case.roll, case.roll })
            expect(condition == case.condition and marked, string.format("a found %s at rolls of %s has condition %d, marked %s, not %d",
                fullType, case.roll, condition, tostring(marked), case.condition))
        end
        for _, case in ipairs({ { roll = 0, condition = dud.min }, { roll = TOP, condition = dud.max } }) do
            local condition, marked = worn(fullType, { wear.dud - UNDER, case.roll })
            expect(condition == case.condition and marked, string.format("a %s dud at a roll of %s has condition %d, marked %s, not %d",
                fullType, case.roll, condition, tostring(marked), case.condition))
        end
    end
    -- Found batteries are sent to the clients that see them, which a scratch container can't be, so
    -- the Batteries option keeps them out; the parts don't depend on them.
    local options = SandboxVars.RenewableEnergy
    local restoreOptions = saveOptions(defer, { "LRMBatteries", "LRMMisc" })
    options.LRMBatteries, options.LRMMisc = 0, 1
    local container = RenewableEnergy.Loot.newContainer(nil)
    local fills = {
        ["the powerYard bank"] = function(c) WorldSpawns.stockBank(c, "powerYard") end,
        ["the kit crate"] = function(c) WorldSpawns.stockCrate(c, "kit") end,
        ["an arrow board's battery box"] = function(c) RenewableEnergy.ArrowBoard.stockBatteryBox(c) end,
    }
    for what, fill in pairs(fills) do
        container:removeAllItems()
        local restoreRoll = Helpers.forceRolls(defer, 0.5)
        fill(container)
        restoreRoll()
        local parts, items = 0, container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if WorldSpawns.isWornPart(item:getFullType()) then
                parts = parts + 1
                expect(item:getCondition() == wear.mean and Wear.hasOwnCondition(item), string.format(
                    "%s's %s has condition %d, marked %s, not %d", what, item:getFullType(), item:getCondition(),
                    tostring(Wear.hasOwnCondition(item)), wear.mean))
            end
        end
        expect(parts > 0, what .. " holds no part at middling rolls")
    end
    container:removeAllItems()
    restoreOptions()
end)

-- How many items a `args.stock` bank gets at the save's options with every roll at `args.roll`.
handler("bankStockCount", function(_, args, defer)
    local container = RenewableEnergy.Loot.newContainer(nil)
    local restoreRoll = Helpers.forceRolls(defer, args.roll)
    RenewableEnergy.WorldSpawns.stockBank(container, args.stock)
    restoreRoll()
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
    defer(function() removePlaced(crate) end)
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

-- Farm storage shelves get a cracked module, at a cracked condition, when the roll comes in under
-- their chance and not at it; a bedroom's furniture and a garage's fridge never do. The chance
-- follows the Solar Panels loot option, and at the option's default a garage shelf's is small but
-- there.
check("crackedModules", function(expect, _, _, _, defer)
    local Distributions = RenewableEnergy.Distributions
    local container = RenewableEnergy.Loot.newContainer(nil)
    local function modulesAt(roomName, containerType, roll)
        -- The chance's roll, then the cracked condition's, at the middle of its range.
        local restoreRoll = Helpers.forceRolls(defer, { roll, 0.5 })
        Distributions.addCrackedModules(roomName, containerType, container)
        restoreRoll()
        local conditions = moduleConditions(container)
        container:removeAllItems()
        return conditions
    end
    local options = SandboxVars.RenewableEnergy
    local restoreOptions = saveOptions(defer, { "LRMSolarPanels" })
    options.LRMSolarPanels = 1
    local rooms = Distributions.CRACKED_MODULE_ROOMS
    local chance = Distributions.crackedModuleChance(rooms.farmstorage)
    expect(Distributions.crackedModuleChance(rooms.garage) > 0, "a garage shelf never holds a cracked module at the default option")
    local under, at = modulesAt("farmstorage", "metal_shelves", chance - UNDER), modulesAt("farmstorage", "metal_shelves", chance)
    expect(#under == 1 and #at == 0, string.format("a farm storage shelf got %d cracked modules with a roll just under its chance %s and %d at it",
        #under, chance, #at))
    if under[1] then
        expect(inRange(under[1], RenewableEnergy.WorldSpawns.CRACKED), "a cracked module is at condition " .. under[1])
    end
    local elsewhere = #modulesAt("bedroom", "wardrobe", 0) + #modulesAt("garage", "fridge", 0)
    expect(elsewhere == 0, elsewhere .. " modules in a bedroom wardrobe and a garage fridge")
    options.LRMSolarPanels = 2
    local doubled = Distributions.crackedModuleChance(rooms.farmstorage)
    options.LRMSolarPanels = 0
    local none = Distributions.crackedModuleChance(rooms.farmstorage)
    restoreOptions()
    expect(math.abs(doubled - 2 * chance) < 1e-12 and none == 0,
        "a farm storage shelf's chance is " .. chance .. ", " .. doubled .. " at twice the option and " .. none .. " at 0")
    expectConditionRanges(expect)
end)

-- What WorldSpawns stocks, which only the authority loads: for each BANK_STOCK name of
-- `args.names` its tile (a Sprites field), battery count range and wear profile; the module
-- conditions of crates; the battery wear profiles; and for the CRATE_STOCK name `args.crate`, if
-- given, each item's count range.
handler("worldSpawnStock", function(_, args)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local banks = {}
    for _, name in ipairs(args.names) do
        local stock = WorldSpawns.BANK_STOCK[name]
        banks[name] = { sprite = stock.sprite, batteries = { min = stock.batteries.min, max = stock.batteries.max },
            wear = stock.batteries.wear, modules = stock.modules }
    end
    local crate
    if args.crate then
        crate = {}
        for _, line in ipairs(WorldSpawns.CRATE_STOCK[args.crate]) do
            crate[line[1]] = { min = line[2], max = line[3] }
        end
    end
    return { banks = banks, crate = crate, cracked = WorldSpawns.CRACKED, weathered = WorldSpawns.WEATHERED,
        batteryWear = WorldSpawns.BATTERY_WEAR }
end)

-- Solar sites -----------------------------------------------------------------------------------
-- The tests arm a site's spots with SolarSites.addSite and let the world place them: when the
-- chunk that holds a spot loads, the system's OnChunkLoaded places it, or queues it for the next
-- game minute. Nothing here places a spot by hand.

local PAMPHLET = "RenewableEnergy.FemaPamphlet"

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
    local store = ModData.getOrCreate(RenewableEnergy.RuralFinds.MOD_DATA)
    for key in pairs(defs or {}) do
        local saved = nil
        if store[key] then
            saved = {}
            for found, value in pairs(store[key]) do
                saved[found] = value
            end
        end
        defer(function() store[key] = saved end)
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

-- Takes out every pamphlet of the building's containers.
local function takePamphlets(def)
    for container in pairs(Helpers.pamphletsIn(def)) do
        Helpers.emptyContainer(container, PAMPHLET)
    end
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
        local modules = mount:getModData()[RenewableEnergy.PowerBank.MODULES] or {}
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
        local bank = RenewableEnergy.PowerBank.bankOn(square)
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
        local bank = PowerBank.bankOn(far)
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
        local range = { min = wear.mean - wear.halfWidth, max = math.min(100, wear.mean + wear.halfWidth) }
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
        expect(building ~= nil and Helpers.pamphletTotal(building:getDef()) >= 1, "no pamphlet in the house's containers")
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
local function objectsOn(squares)
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
    local objects, placed = objectsOn(squares)
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
        local blocker = IsoObject.new(at, PZHarness.Fixtures.WORK_TABLE_SPRITE, "Table")
        at:AddTileObject(blocker)
        if isServer() then
            blocker:transmitCompleteItemToClients()
        end
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
-- place. Every name a world that rolled all sites at once stands for is a site's, since a renamed
-- site would be rolled again in such worlds.
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
    for _, name in ipairs(SolarSites.ROLLED_AT_ONCE) do
        expect(names[name], "a world that rolled every site at once stands for " .. name .. ", which is no site")
    end
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

-- The site named `args.name`, whose armed spots are `args.spots`: { ready = false, why } until
-- every spot's square is loaded here, then how many of its spots still wait.
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
    local isFind = RenewableEnergy.RuralFinds.FINDS[kind].is
    local reach = RenewableEnergy.BuildingWatch.REACH
    for key, def in pairs(defs) do
        local others = 0
        for x = def:getX() - reach, def:getX2() + reach - 1 do
            for y = def:getY() - reach, def:getY2() + reach - 1 do
                if not (x == at[1] and y == at[2]) and RenewableEnergy.findObjectOn(getSquare(x, y, 0), isFind) then
                    others = others + 1
                end
            end
        end
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
        takePamphlets(house:getBuilding():getDef())
    end
    return {}
end)

-- The objects on `square` other than items lying on it, as a set.
local function objectsOn(square)
    local found, objects = {}, square:getObjects()
    for i = 0, objects:size() - 1 do
        if not instanceof(objects:get(i), "IsoWorldInventoryObject") then
            found[objects:get(i)] = true
        end
    end
    return found
end

-- Fires OnSeeNewRoom, as the game does for a room seen for the first time (IsoCell.ProcessSpottedRooms),
-- for each trial { room, setting, roll, edge }: a room named `room` whose free squares are all the
-- square at `args`, Battery Bank Spawn at `setting`, and every roll at `roll`, a number, or "under"
-- or "at" one in BANK_ROOMS odds (`edge` "bank") or CRATE_ROOMS odds (`edge` "crate") × the
-- setting's RARITY. Answers, for each, the tiles it placed on the square and the modules it laid
-- around it, all removed before the next.
handler("seenRoom", function(_, args, defer)
    local square = squareAt(args)
    if not square then
        return nil, "an indoor square loaded on the server"
    end
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local restoreOptions = saveOptions(defer, { "BatteryBankSpawn" })
    local results = {}
    for i, trial in ipairs(args.trials) do
        SandboxVars.RenewableEnergy.BatteryBankSpawn = trial.setting
        local room = { getName = function() return trial.room end, getRandomFreeSquare = function() return square end }
        local roll = trial.roll
        if trial.edge then
            local odds = trial.edge == "bank" and WorldSpawns.BANK_ROOMS[trial.room].odds or WorldSpawns.CRATE_ROOMS[trial.room]
            local chance = 1 / (odds * WorldSpawns.RARITY[trial.setting])
            roll = trial.roll == "under" and chance - UNDER or chance
        end
        local objectsBefore, itemsBefore = objectsOn(square), itemsAround(square)
        local restoreRoll = Helpers.forceRolls(defer, roll)
        triggerEvent("OnSeeNewRoom", room)
        restoreRoll()
        local result, placed = { tiles = {}, modules = 0 }, {}
        for object in pairs(objectsOn(square)) do
            if not objectsBefore[object] then
                table.insert(result.tiles, object:getTextureName())
                table.insert(placed, object)
            end
        end
        for object in pairs(itemsAround(square)) do
            if not itemsBefore[object] then
                result.modules = result.modules + (object:getItem():getFullType() == MODULE and 1 or 0)
                table.insert(placed, object)
            end
        end
        for _, object in ipairs(placed) do
            removePlaced(object)
        end
        results[i] = result
    end
    restoreOptions()
    return { results = results }
end)
