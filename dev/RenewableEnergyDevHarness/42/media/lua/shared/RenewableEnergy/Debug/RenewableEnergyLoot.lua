-- Measures how often the mod's items spawn, with the game's own loot rolls on scratch containers
-- that never enter the world, and how world banks and crates are stocked. Shared Lua so the loot
-- tests can roll on a multiplayer server, whose loot tables alone hold the mod's entries.
-- The dev harness's --loot mode prints the report. Debug mode only.
--
-- The report rolls copies of the lists with only the mod's items: each entry rolls on its own,
-- so the chances are the same, and rolling the whole lists thousands of times runs the client out
-- of memory. It ignores that a container filled by vanilla items stops rolling, so real chances
-- are a little lower in lists of heavy items.

require "RenewableEnergy/Specs"
require "PZHarness/Loot"
local Stash = require "RenewableEnergy/Stash"

RenewableEnergy = RenewableEnergy or {}
local Loot = {}
RenewableEnergy.Loot = Loot
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
    local saved = {}
    for _, option in ipairs(LRM_OPTIONS) do
        saved[option] = SandboxVars.RenewableEnergy[option]
        SandboxVars.RenewableEnergy[option] = lrm
    end
    return PZLoot.restoring(function()
        RenewableEnergy.Distributions.apply()
        return fn()
    end, function()
        for option, value in pairs(saved) do
            SandboxVars.RenewableEnergy[option] = value
        end
        RenewableEnergy.Distributions.apply()
    end)
end

-- The references in RenewableEnergy.Distributions.items with junk lists folded into their own,
-- each with the set of item types it lists: { { reference = ..., items = { [fullType] = true } } }.
local function lootTargets()
    local byReference, targets = {}, {}
    for _, spec in ipairs(RenewableEnergy.Distributions.items) do
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

--- A scratch crate. A procedural table rolls only into a container on a square; give those one
--- outside any room, because a container in a room counts toward the room's per-room list limits
--- and gets its forced lists.
---@param square IsoGridSquare?
function Loot.newContainer(square)
    return ItemContainer.new("crate", square, nil)
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

-- How WorldSpawns and the arrow board stock the containers they place, each into a scratch
-- container: { reference, fill } rows.
local function worldStock()
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local stocks = {}
    for _, name in ipairs(sortedKeys(WorldSpawns.BANK_STOCK)) do
        table.insert(stocks, { "world:bank." .. name, function(container) WorldSpawns.stockBank(container, name) end })
    end
    for _, name in ipairs(sortedKeys(WorldSpawns.CRATE_STOCK)) do
        table.insert(stocks, { "world:crate." .. name, function(container) WorldSpawns.stockCrate(container, name) end })
    end
    table.insert(stocks, { "world:arrowBoard", function(container)
        RenewableEnergy.ArrowBoard.stockBatteryBox(container)
        RenewableEnergy.Distributions.readyFoundItems(container)
    end })
    return stocks
end

local function share(fraction)
    return string.format("%.2f%% (1 in %.0f)", fraction * 100, 1 / fraction)
end

-- Prints how often `fill` put each item in `container` over `samples` fills, as `count` counts
-- them, listing the `expected` items even when none came.
local function printMeasured(reference, samples, fill, container, expected, count)
    local items = fill and PZLoot.sample(fill, samples, container, count) or {}
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
        local text = measured and share(measured.share) or "none"
        if measured and measured.perContainer >= 1.05 then
            text = text .. string.format(", %.1f each", measured.perContainer)
        end
        -- Drops the module, so vanilla items the world entries count read the same way.
        table.insert(parts, (string.gsub(fullType, "^[^.]+%.", "")) .. " " .. text)
    end
    print(string.format("RELootReport %s [%d samples]: %s", reference, fill and samples or 0,
        #parts > 0 and table.concat(parts, "; ") or "nothing"))
end

--- Prints how often the mod's items spawn in every list the mod adds to, the stash crate and the
--- room containers that pick the mod's own lists, and what world banks and crates are stocked
--- with, vanilla items included, each over `samples` fills at the default loot rarity options.
function Loot.printReport(samples)
    PZLoot.withMeasureOptions(Loot.MEASURE_OPTIONS, function()
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
            print(string.format("RELootReport settings: Other loot %.2f, Recipe Resources %.2f, loot rarity options 1, no zombie density bonus",
                ItemPickerJava.getLootModifierFromType("Other"), ItemPickerJava.getLootModifierFromType("RecipeResource")))
            local container = Loot.newContainer(nil)
            for i, target in ipairs(targets) do
                local list = parsed["t" .. i]
                printMeasured(target.reference, samples, list and PZLoot.rollFill(list), container, target.items, countModItems)
            end
            local square = PZLoot.squareOutsideRooms(getPlayer())
            local roomContainer = Loot.newContainer(square)
            for i, spec in ipairs(ROOM_CONTAINERS) do
                local list = square and parsed["r" .. i]
                printMeasured(spec.room .. "." .. spec.container, samples, list and PZLoot.rollFill(list), roomContainer, {},
                    countModItems)
            end
            for _, stock in ipairs(worldStock()) do
                printMeasured(stock[1], samples, stock[2], container, {}, PZLoot.countItems)
            end
        end)
    end)
end

-- Yardsticks ------------------------------------------------------------------------------------

--- A guessed mix of clear, broken and overcast days: { share, weather } rows, the weather as
--- Sun.planeIrradiance takes it.
Loot.WEATHER_MIX = {
    { 0.4, { cloud = 0, fog = 0, rain = 0, snowing = false, groundSnow = 0 } },
    { 0.3, { cloud = 0.5, fog = 0, rain = 0, snowing = false, groundSnow = 0 } },
    { 0.3, { cloud = 1, fog = 0, rain = 0, snowing = false, groundSnow = 0 } },
}
--- The mounts the light is measured on, by name: Sun.planeIrradiance's kind and facing.
Loot.SOUTH_MOUNTS = { flat = { "flat" }, rack = { "rack", "S" }, wall = { "wall", "S" } }

-- Vanilla's generator fuel an hour for each appliance kind (IsoGenerator's *PowerConsumption
-- constants).
Loot.APPLIANCE_FUEL = {
    fridgeFreezer = 0.13, fridge = 0.08, light = 0.002, television = 0.03, radio = 0.01,
    microwave = 0.09, range = 0.09, washer = 0.09, dryer = 0.09, batteryCharger = 0.05,
}

--- The watts an appliance of the kind `name` (a Loot.APPLIANCE_FUEL key) draws as a bank bills it.
function Loot.applianceWatts(name)
    return RenewableEnergy.Specs.wattsFromFuel(Loot.APPLIANCE_FUEL[name])
end

return Loot
