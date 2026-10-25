-- The authority's half of the world spawn tests: banks, crates and cracked modules are placed and
-- stocked only where the authority runs them. Only registers handlers, so a --stay rerun loads it
-- again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work. The solar
-- sites' are in RenewableEnergyTestServerSolarSites.lua.

require "PZHarness/ServerHandlers"
require "PZHarness/ServerChecks"
require "PZHarness/Fixtures"
require "PZHarness/Loot"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler, check, saveOptions = PZHarness.serverHandler, PZHarness.checkHandler, PZHarness.Fixtures.saveOptions
local squareAt, removePlaced = PZHarness.Fixtures.squareAt, PZHarness.Fixtures.removePlaced
local inRange, wearRange, UNDER = Helpers.inRange, Helpers.wearRange, Helpers.UNDER
local Sprites = RenewableEnergy.Sprites

local MODULE = RenewableEnergy.Specs.factoryModule

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

-- The objects on `square` other than items lying on it, as a set.
local function tilesOn(square)
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
            roll = Helpers.trialRoll(roll, 1 / (odds * WorldSpawns.RARITY[trial.setting]))
        end
        local objectsBefore, itemsBefore = tilesOn(square), itemsAround(square)
        local restoreRoll = Helpers.forceRolls(defer, roll)
        triggerEvent("OnSeeNewRoom", room)
        restoreRoll()
        local result, placed = { tiles = {}, modules = 0 }, {}
        for object in pairs(tilesOn(square)) do
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

-- The parts a bank may hold besides batteries, as PowerBank.partKind names them.
local PARTS = { "inverter", "controller", "charger" }

-- What BANK_STOCK[stockName] puts in an emptied `container` with every roll at `roll`: how many of
-- each of PARTS.
local function bankPartsAt(container, stockName, roll, defer)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local restoreRoll = Helpers.forceRolls(defer, roll)
    local found = { inverter = 0, controller = 0, charger = 0 }
    local function stock(c) WorldSpawns.stockBank(c, stockName) end
    for fullType, count in pairs(PZHarness.Loot.fillOnce(stock, container)) do
        local kind = RenewableEnergy.PowerBank.partKind(fullType)
        if found[kind] then
            found[kind] = found[kind] + count
        end
    end
    restoreRoll()
    return found
end

-- A scratch container for stocking parts, and the function that puts the loot options back. Found
-- batteries are sent to the clients that see them, and a server can't send an item of a container
-- that isn't in the world, so the Batteries option keeps them out; the parts don't depend on them.
local function partsContainer(defer)
    local restoreOptions = saveOptions(defer, { "LRMBatteries", "LRMMisc" })
    SandboxVars.RenewableEnergy.LRMBatteries = 0
    return RenewableEnergy.Loot.newContainer(nil), restoreOptions
end

-- Every stock's parts are of their line's kind; the bank `args.stock` holds a part when the roll
-- comes in under its chance × the misc loot option and not at it, so neither a part's chance nor
-- the option goes astray; and a battery box (a tile of `args.boxTiles`), which has no slot for a
-- charge controller, never gets one, even from a stock that lists one.
check("bankStockParts", function(expect, _, _, args, defer)
    local WorldSpawns, PowerBank = RenewableEnergy.WorldSpawns, RenewableEnergy.PowerBank
    for stockName, stock in pairs(WorldSpawns.BANK_STOCK) do
        for _, kind in ipairs(PARTS) do
            local part = stock[kind]
            if part then
                for _, entry in ipairs(part.types) do
                    expect(PowerBank.partKind(entry[1]) == kind, stockName .. "'s " .. kind .. " line holds a " .. entry[1])
                end
            end
        end
    end
    local container, restoreOptions = partsContainer(defer)
    local options = SandboxVars.RenewableEnergy
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

-- The rolls a wear profile is checked at, its lowest, a middling one and its highest, and the
-- condition each gives.
local function wearCases(wear)
    local range = wearRange(wear)
    return { { roll = 0, condition = range.min }, { roll = 0.5, condition = wear.mean }, { roll = 1 - UNDER, condition = range.max } }
end

-- The rolls a dud's condition is checked at, its lowest and its highest, and the condition each gives.
local function dudCases(dud)
    return { { roll = 0, condition = dud.min }, { roll = 1 - UNDER, condition = dud.max } }
end

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
    for name, wear in pairs(WorldSpawns.BATTERY_WEAR) do
        -- A profile with duds rolls for one first; at the chance, it isn't one.
        local first = wear.dud and { wear.dud } or {}
        for _, case in ipairs(wearCases(wear)) do
            local rolls = { unpack(first) }
            for _ = 1, 3 do table.insert(rolls, case.roll) end
            local got = worn(name, rolls)
            expect(got.condition == case.condition and got.repairs == 0, string.format("%s at rolls of %s wears a battery to %d with %d repairs, not %d",
                name, case.roll, got.condition, got.repairs, case.condition))
        end
        if wear.dud then
            for _, case in ipairs(dudCases(dud)) do
                local got = worn(name, { wear.dud - UNDER, case.roll })
                expect(got.condition == case.condition and got.repairs == dud.repairs, string.format(
                    "a %s dud at a roll of %s has condition %d and %d repairs, not %d and %d",
                    name, case.roll, got.condition, got.repairs, case.condition, dud.repairs))
            end
        end
    end
end)

-- PART_WEAR wears every found inverter and the charge controller, not a homemade inverter or the
-- battery charger: to its mean less its half width at the lowest rolls, its mean at middling ones
-- and no better than new at the highest; a roll just under its dud chance makes a dud, at
-- PART_DUD's lowest and highest condition by the next roll, worse than any working find, and a
-- roll at it doesn't. Each worn part is marked as having a condition of its own. With every roll
-- middling, the parts of a bank's stock, a crate's and an arrow board's battery box come at the
-- mean, marked.
check("partWear", function(expect, _, _, _, defer)
    local WorldSpawns, Specs, Wear = RenewableEnergy.WorldSpawns, RenewableEnergy.Specs, RenewableEnergy.Wear
    local wear, dud = WorldSpawns.PART_WEAR, WorldSpawns.PART_DUD
    local lowest = wearRange(wear).min
    expect(dud.min >= 0 and dud.min <= dud.max and dud.max < lowest,
        "a part dud's condition " .. dud.min .. " to " .. dud.max .. " overlaps a found part's from " .. lowest)
    local types = { Specs.controller }
    for fullType, spec in pairs(Specs.inverters) do
        if spec.homemade then
            expect(not WorldSpawns.isWornPart(fullType), fullType .. ", crafted, is worn as if found")
        else
            table.insert(types, fullType)
        end
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
    for _, fullType in ipairs(types) do
        for _, case in ipairs(wearCases(wear)) do
            local condition, marked = worn(fullType, { wear.dud, case.roll, case.roll, case.roll })
            expect(condition == case.condition and marked, string.format("a found %s at rolls of %s has condition %d, marked %s, not %d",
                fullType, case.roll, condition, tostring(marked), case.condition))
        end
        for _, case in ipairs(dudCases(dud)) do
            local condition, marked = worn(fullType, { wear.dud - UNDER, case.roll })
            expect(condition == case.condition and marked, string.format("a %s dud at a roll of %s has condition %d, marked %s, not %d",
                fullType, case.roll, condition, tostring(marked), case.condition))
        end
    end
    local container, restoreOptions = partsContainer(defer)
    SandboxVars.RenewableEnergy.LRMMisc = 1
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

-- A cracked module always reads worse than a weathered one, so players can tell which needs
-- repair, and shows cracked glass.
local function expectConditionRanges(expect)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    expect(WorldSpawns.CRACKED.max < WorldSpawns.WEATHERED.min, "cracked and weathered conditions overlap")
    local best = WorldSpawns.CRACKED.max
    expect(RenewableEnergy.crackLookOf(RenewableEnergy.Specs.factoryModule, best) ~= nil,
        "a cracked module at " .. best .. " shows whole glass")
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
