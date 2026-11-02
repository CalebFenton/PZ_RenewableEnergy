-- Measures how often the mod's items spawn, with the game's own loot rolls on scratch containers
-- that never enter the world, and how world banks and crates are stocked. Shared Lua so the loot
-- tests can roll on a multiplayer server, whose loot tables alone hold the mod's entries.
-- The dev harness's --loot mode prints the report. Debug mode only.
--
-- The report rolls copies of the lists with only the mod's items: each entry rolls on its own,
-- so the chances are the same, and rolling the whole lists thousands of times runs the client out
-- of memory. It ignores that a container filled by vanilla items stops rolling, so real chances
-- are a little lower in lists of heavy items.

require "PZHarness/Loot"
local Stash = require "RenewableEnergy/Stash"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Trailer"

local Loot = {}
local PZLoot = PZHarness.Loot

-- Prefix of the made-up ProceduralDistributions lists the room containers pick from.
local PROBE_LIST = "RenewableEnergyLootProbe_"
local MOD_PREFIX = "RenewableEnergy."

-- The solar crate of the mod's stash houses.
local STASH_CRATE = "sub:" .. Stash.SPAWN_TABLE .. "." .. Stash.CRATE_TYPE

-- Room containers that pick the mod's own lists among their vanilla lists, measured as a whole:
-- the share of all such containers that hold the item.
local ROOM_CONTAINERS = {
    { room = "electronicsstorage", container = "other" },
    { room = "campingstorage", container = "other" },
    { room = "farmstorage", container = "other" },
    { room = "toolstorestorage", container = "other" },
    { room = "warehouse", container = "metal_shelves" },
    { room = "storageunit", container = "other" },
    { room = "garagestorage", container = "crate" },
    { room = "SafehouseLoot", container = "metal_shelves" },
    { room = Stash.SPAWN_TABLE, container = "crate" },
    { room = Stash.SPAWN_TABLE, container = "metal_shelves" },
}

--- Sandbox options while measuring (PZHarness.Loot.withMeasureOptions): a new default-preset
--- game's loot settings, without the zombie density bonus (of the mod's items only the magazines
--- can get it, and the preset turns it off anyway) and without annotated maps, each of which uses
--- up a stash of the world.
Loot.MEASURE_OPTIONS = {
    OtherLootNew = PZLoot.DEFAULT,
    RecipeResourceLoot = PZLoot.DEFAULT,
    RollsMultiplier = PZLoot.DEFAULT,
    MaximumDiminishedLoot = 0,
    ZombiePopLootEffect = 0,
    AnnotatedMapChance = 1,
}
local LRM_OPTIONS = { "LRMSolarPanels", "LRMBatteries", "LRMMisc" }

--- Runs fn() with the mod's loot rarity options at `lrm` and the mod's loot applied for them, then
--- restores the options and applies the loot again. ItemPickerJava.Parse is left to the caller.
function Loot.withLootRarity(lrm, fn)
    local Distributions = require "RenewableEnergy/Items/Distributions"
    local saved = {}
    for _, option in ipairs(LRM_OPTIONS) do
        saved[option] = SandboxVars.RenewableEnergy[option]
        SandboxVars.RenewableEnergy[option] = lrm
    end
    return PZLoot.restoring(function()
        Distributions.apply()
        return fn()
    end, function()
        for option, value in pairs(saved) do
            SandboxVars.RenewableEnergy[option] = value
        end
        Distributions.apply()
    end)
end

-- The references in Distributions.items with junk lists folded into their own,
-- each with the set of item types it lists: { { reference = ..., items = { [fullType] = true } } }.
local function lootTargets()
    local Distributions = require "RenewableEnergy/Items/Distributions"
    local byReference, targets = {}, {}
    for _, spec in ipairs(Distributions.items) do
        for _, entry in ipairs(spec.entries) do
            local reference = string.gsub(entry[2], "%.junk$", "")
            local target = byReference[reference]
            if not target then
                target = { reference = reference, items = {} }
                byReference[reference] = target
                table.insert(targets, target)
            end
            target.items[spec.fullType] = true
        end
    end
    return targets
end

local function isModItem(fullType)
    return string.sub(fullType, 1, #MOD_PREFIX) == MOD_PREFIX
end

-- A copy of a loot table with only the mod's items, junk included.
local function modItemsOnly(lootTable)
    local items = {}
    for i = 1, #lootTable.items - 1, 2 do
        if isModItem(lootTable.items[i]) then
            table.insert(items, lootTable.items[i])
            table.insert(items, lootTable.items[i + 1])
        end
    end
    return {
        rolls = lootTable.rolls,
        ignoreZombieDensity = lootTable.ignoreZombieDensity,
        items = items,
        junk = lootTable.junk and modItemsOnly(lootTable.junk),
    }
end

-- Runs fn(parsed) with the mod's loot rarity options at `lrm` and the probe build() returns
-- parsed by the game (PZHarness.Loot.withParsed). build() runs once the mod's loot is in for `lrm`
-- and returns `containers`, key -> loot table, and optionally `lists`, name -> extra
-- ProceduralDistributions list for procedural containers to pick. Afterwards restores the options
-- and parses the loot again, since withParsed parses before the options are back.
local function withLoot(lrm, build, fn)
    return PZLoot.restoring(function()
        return Loot.withLootRarity(lrm, function()
            local containers, lists = build()
            return PZLoot.withParsed(containers, lists, fn)
        end)
    end, function() ItemPickerJava.Parse() end)
end

-- One table per target of lootTargets(), keyed "t<index>": a copy of the list with only the
-- mod's items.
-- cf_commonlib/Loot is server Lua, which a dedicated server loads after this shared file, so it is
-- required here, on the authority, when the loot is measured.
local function modOnlyTables(targets)
    local LibLoot = require "cf_commonlib/Loot"
    local tables = {}
    for i, target in ipairs(targets) do
        local lootTable = LibLoot.resolveTable(target.reference)
        tables["t" .. i] = lootTable and modItemsOnly(lootTable)
    end
    return tables
end

-- The containers of ROOM_CONTAINERS keyed "r<index>", each picking from copies of its lists with
-- only the mod's items, and those copies.
local function roomContainersModOnly()
    local containers, lists = {}, {}
    for i, spec in ipairs(ROOM_CONTAINERS) do
        local room = SuburbsDistributions[spec.room]
        local containerTable = room and room[spec.container]
        if containerTable and containerTable.procList then
            local procList = {}
            for _, choice in ipairs(containerTable.procList) do
                local copy = {}
                for key, value in pairs(choice) do
                    copy[key] = value
                end
                copy.name = PROBE_LIST .. choice.name
                local list = ProceduralDistributions.list[choice.name]
                lists[copy.name] = list and modItemsOnly(list) or { rolls = 1, items = {} }
                table.insert(procList, copy)
            end
            containers["r" .. i] = { procedural = true, procList = procList }
        end
    end
    return containers, lists
end

-- The mod's items in the container, bags' and boxes' contents included: fullType -> count.
local function countModItems(container)
    return PZLoot.countItems(container, isModItem)
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

--- What WorldSpawns and the arrow board stock the containers they place with, over `samples` fills
--- of each that every reader of `readers` (name -> read(container), as PZHarness.Loot.sample takes)
--- reads: `banks` and `crates` by BANK_STOCK and CRATE_STOCK name, and `arrowBoard`, each as reader
--- name -> PZHarness.Loot.sample's result. The stocks read only the loot rarity options, so the
--- caller sets those.
function Loot.sampleWorldStocks(samples, readers)
    local WorldSpawns = require "RenewableEnergy/World/WorldSpawns"
    local container = PZLoot.scratchContainer(nil)
    -- One fill feeds every reader, its keys tagged "<reader name> <key>".
    local function readAll(filled)
        local tagged = {}
        for name, read in pairs(readers) do
            for key, count in pairs(read(filled)) do
                tagged[name .. " " .. key] = count
            end
        end
        return tagged
    end
    local function sample(fill)
        local byReader = {}
        for name in pairs(readers) do
            byReader[name] = {}
        end
        for tagged, measured in pairs(PZLoot.sample(fill, samples, container, readAll)) do
            local name, key = tagged:match("^(%S+) (.+)$")
            byReader[name][key] = measured
        end
        return byReader
    end
    local stocks = { banks = {}, crates = {}, arrowBoard = sample(ArrowBoard.stockBatteryBox) }
    for name in pairs(WorldSpawns.BANK_STOCK) do
        stocks.banks[name] = sample(function(filled) WorldSpawns.stockBank(filled, name) end)
    end
    for name in pairs(WorldSpawns.CRATE_STOCK) do
        stocks.crates[name] = sample(function(filled) WorldSpawns.stockCrate(filled, name) end)
    end
    return stocks
end

-- Prints under `mark` how often each item came over `samples` fills, `items` being
-- PZHarness.Loot.sample's result or nil where nothing was filled, listing the `expected` items even
-- when none came.
local function printMeasured(mark, reference, samples, items, expected)
    local filled = items ~= nil
    items = items or {}
    local fullTypes = sortedKeys(expected)
    for fullType in pairs(items) do
        if not expected[fullType] then
            table.insert(fullTypes, fullType)
        end
    end
    table.sort(fullTypes)
    local parts = {}
    for _, fullType in ipairs(fullTypes) do
        local measured = items[fullType]
        local text = PZLoot.share(measured and measured.share or 0, 2, 0)
        if measured and measured.perContainer >= 1.05 then
            text = text .. string.format(", %.1f each", measured.perContainer)
        end
        -- Drops the module, so vanilla items the world entries count read the same way.
        table.insert(parts, (string.gsub(fullType, "^[^.]+%.", "")) .. " " .. text)
    end
    print(string.format("%s %s [%d samples]: %s", mark, reference, filled and samples or 0,
        #parts > 0 and table.concat(parts, "; ") or "nothing"))
end

--- Prints under `mark` how often the mod's items spawn in every list the mod adds to, the stash
--- crate and the room containers that pick the mod's own lists, each over `samples` fills, and
--- what world banks and crates are stocked with, vanilla items included, from `stocks`
--- (Loot.sampleWorldStocks with an `items` reader of PZHarness.Loot.countItems). The caller sets
--- the measuring options (MEASURE_OPTIONS) and loot rarity options 1.
function Loot.printReport(samples, mark, stocks)
    local targets = lootTargets()
    table.insert(targets, { reference = STASH_CRATE, items = {} })
    local function build()
        local containers, lists = roomContainersModOnly()
        for key, lootTable in pairs(modOnlyTables(targets)) do
            containers[key] = lootTable
        end
        return containers, lists
    end
    withLoot(1, build, function(parsed)
        print(string.format("%s settings: Other loot %.2f, Recipe Resources %.2f, loot rarity options 1, no zombie density bonus",
            mark, ItemPickerJava.getLootModifierFromType("Other"), ItemPickerJava.getLootModifierFromType("RecipeResource")))
        local container = PZLoot.scratchContainer(nil)
        for i, target in ipairs(targets) do
            local list = parsed["t" .. i]
            printMeasured(mark, target.reference, samples,
                list and PZLoot.sample(PZLoot.rollFill(list), samples, container, countModItems), target.items)
        end
        local square = PZLoot.squareOutsideRooms(getPlayer())
        local roomContainer = PZLoot.scratchContainer(square)
        for i, spec in ipairs(ROOM_CONTAINERS) do
            local list = square and parsed["r" .. i]
            printMeasured(mark, spec.room .. "." .. spec.container, samples,
                list and PZLoot.sample(PZLoot.rollFill(list), samples, roomContainer, countModItems), {})
        end
    end)
    for _, name in ipairs(sortedKeys(stocks.banks)) do
        printMeasured(mark, "world:bank." .. name, samples, stocks.banks[name].items, {})
    end
    for _, name in ipairs(sortedKeys(stocks.crates)) do
        printMeasured(mark, "world:crate." .. name, samples, stocks.crates[name].items, {})
    end
    printMeasured(mark, "world:arrowBoard", samples, stocks.arrowBoard.items, {})
end

return Loot
