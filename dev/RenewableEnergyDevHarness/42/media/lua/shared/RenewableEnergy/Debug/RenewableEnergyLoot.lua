-- Measures how often the mod's items spawn, with the game's own loot rolls on scratch containers
-- that never enter the world, and how world banks and crates are stocked. Shared Lua so the loot
-- tests can roll on a multiplayer server, whose loot tables alone hold the mod's entries.
-- The dev harness's --loot mode prints these reports. Debug mode only.
--
-- The report rolls copies of the lists with only the mod's items: each entry rolls on its own,
-- so the chances are the same, and rolling the whole lists thousands of times runs the client out
-- of memory. It ignores that a container filled by vanilla items stops rolling, so real chances
-- are a little lower in lists of heavy items.

require "RenewableEnergy/Specs"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/Sun"
require "PZHarness/Fixtures"
local Stash = require "RenewableEnergy/StashHouses"

RenewableEnergy = RenewableEnergy or {}
local Loot = {}
RenewableEnergy.Loot = Loot

-- ItemPickerJava.getItemContainer reaches a parsed table only through a room, and vehicle lists
-- not at all, so withLoot files the tables it measures under this made-up room.
local PROBE_ROOM = "RenewableEnergyLootProbe"
-- Prefix of the made-up ProceduralDistributions lists the room containers pick from.
local PROBE_LIST = "RenewableEnergyLootProbe_"
local MOD_PREFIX = "RenewableEnergy."

-- What each list fills, for the report. Corpse lists are labelled by their outfit.
local LABELS = {
    ["proc:ElectronicStoreMagazines"] = "Electronics store magazine racks",
    ["proc:ElectronicStoreMisc"] = "Electronics store misc shelves",
    ["proc:ElectricianTools"] = "Electronics store tool shelves",
    ["proc:GigamartHouseElectronics"] = "Department store electronics",
    ["proc:ToolStoreBooks"] = "Hardware store books",
    ["proc:ToolStoreFarming"] = "Hardware store farming",
    ["proc:ToolStoreMisc"] = "Hardware store misc shelves",
    ["proc:GardenStoreMisc"] = "Garden centre misc shelves",
    ["proc:GardenStoreTools"] = "Garden centre tools",
    ["proc:CrateGardening"] = "Gardening crates",
    ["proc:BookstoreBlueCollar"] = "Bookstore trade shelves",
    ["proc:BookstoreMisc"] = "Bookstore misc shelves",
    ["proc:BookstoreOutdoors"] = "Bookstore outdoors shelves",
    ["proc:BookstoreFarming"] = "Bookstore farming shelves",
    ["proc:CampingStoreBooks"] = "Camping and fishing store books",
    ["proc:CampingStoreLighting"] = "Camping store lighting",
    ["proc:CampingStoreGear"] = "Camping store gear",
    ["proc:CrateCamping"] = "Camping crates",
    ["proc:OutdoorSupplyMagazines"] = "Outdoor supply magazines",
    ["proc:RangerMagazines"] = "Ranger station magazines",
    ["proc:CarSupplyLiterature"] = "Auto parts store books",
    ["proc:CarSupplyBatteries"] = "Auto parts store batteries",
    ["proc:CarSupplyTools"] = "Auto parts store tools",
    ["proc:GasStoreEmergency"] = "Gas station emergency supplies",
    ["proc:MechanicShelfElectric"] = "Mechanics' electrical shelves",
    ["proc:GarageMechanics"] = "Garage mechanics",
    ["proc:GarageTools"] = "Garage tools",
    ["proc:CrateMagazines"] = "Magazine crates",
    ["proc:MagazineRackMixed"] = "Gas station and grocery magazine racks",
    ["proc:PostOfficeMagazines"] = "Post office magazines",
    ["proc:LibraryMagazines"] = "Library magazines",
    ["proc:EngineerTools"] = "Engineers' tools",
    ["proc:GeneratorRoom"] = "Generator and technical rooms",
    ["proc:ControlRoomCounter"] = "Control room counters",
    ["proc:RadioFactoryComponents"] = "Radio factory components",
    ["proc:ArmyStorageElectronics"] = "Army storage electronics",
    ["proc:ArmySurplusMisc"] = "Army surplus store",
    ["proc:LivingRoomShelf"] = "Living room shelves",
    ["proc:LivingRoomShelfClassy"] = "Living room shelves (classy)",
    ["proc:LivingRoomShelfRedneck"] = "Living room shelves (redneck)",
    ["proc:LivingRoomSideTable"] = "Living room side tables",
    ["proc:LivingRoomSideTableClassy"] = "Living room side tables (classy)",
    ["proc:LivingRoomSideTableRedneck"] = "Living room side tables (redneck)",
    ["proc:LivingRoomWardrobe"] = "Living room wardrobes",
    ["proc:RecRoomShelf"] = "Rec room shelves",
    ["proc:ShelfGeneric"] = "Generic shelves",
    ["proc:Hobbies"] = "Hobby shelves",
    ["proc:KitchenRandom"] = "Kitchen junk drawers",
    ["proc:ClosetShelfGeneric"] = "Closet shelves",
    ["proc:OfficeDeskHome"] = "Home office desks",
    ["proc:SurvivalGear"] = "Preppers' survival gear",
    ["proc:Homesteading"] = "Homestead supplies",
    ["proc:SafehouseLighting"] = "Survivor safehouse lighting",
    ["proc:SafehouseLighting_Late"] = "Survivor safehouse lighting (late)",
    ["proc:SafehouseBookShelf"] = "Survivor safehouse bookshelves",
    ["proc:SafehouseFireplace"] = "Survivor safehouse hearths",
    ["proc:SafehouseFireplace_Late"] = "Survivor safehouse hearths (late)",
    ["proc:ToolCabinetFarming"] = "Farm tool cabinets",
    ["proc:BarnTools"] = "Barn tools",
    ["proc:FishingStoreGear"] = "Fishing store gear",
    ["proc:CrateBatteries"] = "Battery plant crates",
    ["proc:CrateElectronics"] = "Electronics crates",
    ["proc:JunkHoard"] = "Junk hoards",
    ["proc:RenewableEnergySolarKit"] = "Solar kit (RenewableEnergySolarKit)",
    ["proc:RenewableEnergyBatteryStock"] = "Battery back stock (RenewableEnergyBatteryStock)",
    ["veh:ElectricianTruckBed"] = "Electrician vans",
    ["veh:RenewableEnergyTelecomTruckBed"] = "Knox Telecommunications vans",
    ["veh:RenewableEnergyUtilityTruckBed"] = "Deer Valley Power vans",
    ["veh:RadioTruckBed"] = "Radio station vans",
    ["veh:CamperTruckBed"] = "Campers (station wagons, SUVs, vans)",
    ["veh:CamperGloveBox"] = "Campers' glove boxes",
    ["veh:GloveBox"] = "Glove boxes of ordinary cars and trucks",
    ["veh:TrunkStandard"] = "Trunks of ordinary cars",
    ["veh:TrunkHeavy"] = "Truck beds of ordinary pickups and vans",
    ["veh:RenewableEnergyCamperTrailerTrunk"] = "Camper trailers",
    ["veh:SurvivalistTruckBed"] = "Survivalist vehicles",
    ["veh:RancherTruckBed"] = "Rancher trucks",
    ["veh:FarmerTruckBed"] = "Farmer trucks",
    ["veh:ConstructionWorkerTruckBed"] = "Construction trucks",
    ["veh:RangerTruckBed"] = "Ranger trucks",
    ["veh:FishermanTruckBed"] = "Fisherman trucks",
    ["sub:SurvivorCache1.SurvivorCrate"] = "Survivor stash crates",
    ["sub:SurvivorCache2.SurvivorCrate"] = "Survivor stash crates (8 rolls)",
    ["sub:SurvivorCacheBigBuilding.SurvivorCrate"] = "Survivor stash crates (big buildings)",
    ["proc:CrateFarming"] = "Farming crates",
    ["proc:PoliceDesk"] = "Police desks",
    ["proc:FireStorageTools"] = "Fire station tool storage",
    ["proc:LibraryGeneralReference"] = "Library reference shelves",
    ["proc:ArmySurplusLiterature"] = "Army surplus store books",
}
-- The solar crate of the mod's stash houses.
local STASH_CRATE = "sub:" .. Stash.SPAWN_TABLE .. "." .. Stash.CRATE_TYPE
LABELS[STASH_CRATE] = "Solar crate in the mod's stash houses"

local function labelFor(reference)
    local outfit = string.match(reference, "^sub:all%.Outfit_(.+)$")
    return LABELS[reference] or (outfit and ("Corpses: " .. outfit)) or reference
end

-- Room containers that pick the mod's own lists among their vanilla lists, measured as a whole:
-- the share of all such containers that hold the item.
local ROOM_CONTAINERS = {
    { room = "electronicsstorage", container = "other", label = "Electronics store storage room" },
    { room = "campingstorage", container = "other", label = "Camping store storage room" },
    { room = "farmstorage", container = "other", label = "Farm storage" },
    { room = "toolstorestorage", container = "other", label = "Hardware store storage room" },
    { room = "warehouse", container = "metal_shelves", label = "Warehouse metal shelves" },
    { room = "storageunit", container = "other", label = "Storage units" },
    { room = "garagestorage", container = "crate", label = "Garage crates" },
    { room = "SafehouseLoot", container = "metal_shelves", label = "Survivor safehouse metal shelves" },
    { room = Stash.SPAWN_TABLE, container = "crate", label = "Crates in the mod's stash houses" },
    { room = Stash.SPAWN_TABLE, container = "metal_shelves", label = "Metal shelves in the mod's stash houses" },
}

-- Sandbox options while measuring: a new default-preset game's loot settings, without the zombie
-- density bonus (of the mod's items only the magazines can get it, and the preset turns it off
-- anyway) and without annotated maps, each of which uses up a stash of the world. DEFAULT stands
-- for the option's default value, which the game takes from the Apocalypse preset
-- (SandboxOptions constructor).
local DEFAULT = {}
local MEASURE_OPTIONS = {
    OtherLootNew = DEFAULT,
    RecipeResourceLoot = DEFAULT,
    RollsMultiplier = DEFAULT,
    MaximumDiminishedLoot = 0,
    ZombiePopLootEffect = 0,
    AnnotatedMapChance = 1,
}
local LRM_OPTIONS = { "LRMSolarPanels", "LRMBatteries", "LRMMisc" }

-- Returns fn()'s result, calling restore() after fn whether or not it throws; a throw goes on
-- after restore, so a failed measurement still leaves the game's loot and options as they were.
local function restoring(fn, restore)
    local ok, result = pcall(fn)
    restore()
    if not ok then
        error(result)
    end
    return result
end

-- Runs fn() with the mod's loot rarity options at `lrm` and the mod's loot applied for them, then
-- restores the options and applies the loot again. ItemPickerJava.Parse is left to the caller.
local function withLootRarity(lrm, fn)
    local saved = {}
    for _, option in ipairs(LRM_OPTIONS) do
        saved[option] = SandboxVars.RenewableEnergy[option]
        SandboxVars.RenewableEnergy[option] = lrm
    end
    return restoring(function()
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
-- parsed by the game. build() runs once the mod's loot is in for `lrm` and returns `containers`,
-- key -> loot table, and optionally `lists`, name -> extra ProceduralDistributions list for
-- procedural containers to pick. parsed[key] is the game's copy of the container to pass to
-- ItemPickerJava.rollItem, or nil if the game didn't take it. Afterwards restores the options and
-- parses the loot as it was.
local function withLoot(lrm, build, fn)
    return restoring(function()
        return withLootRarity(lrm, function()
            local containers, lists = build()
            lists = lists or {}
            return restoring(function()
                for name, list in pairs(lists) do
                    ProceduralDistributions.list[name] = list
                end
                SuburbsDistributions[PROBE_ROOM] = containers
                ItemPickerJava.Parse()
                local parsed = {}
                for key, containerTable in pairs(containers) do
                    -- For a procedural container, a list name no entry has returns the container itself.
                    parsed[key] = ItemPickerJava.getItemContainer(PROBE_ROOM, key, containerTable.procedural and "" or nil, false)
                end
                return fn(parsed)
            end, function()
                SuburbsDistributions[PROBE_ROOM] = nil
                for name in pairs(lists) do
                    ProceduralDistributions.list[name] = nil
                end
            end)
        end)
    end, function() ItemPickerJava.Parse() end)
end

-- One table per target of lootTargets(), keyed "t<index>": a copy of the list with only the
-- mod's items.
local function modOnlyTables(targets)
    local tables = {}
    for i, target in ipairs(targets) do
        local lootTable = RenewableEnergy.Distributions.resolveTable(target.reference)
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

--- Runs fn with MEASURE_OPTIONS and the General debug log off: in debug mode ItemPickInfo logs a
--- line for every roll into a container that isn't on a square, which floods console.txt. The
--- loot category multipliers are cached when a game loads, so they are reloaded around fn.
function Loot.withMeasureOptions(fn)
    local options = getSandboxOptions()
    local saved = {}
    local generalLog = DebugType.General:getLogSeverity()
    return restoring(function()
        for name, value in pairs(MEASURE_OPTIONS) do
            local option = options:getOptionByName(name)
            saved[name] = option:getValue()
            option:setValue(value == DEFAULT and option:getDefaultValue() or value)
        end
        ItemPickerJava.InitSandboxLootSettings()
        DebugType.General:setLogSeverity(LogSeverity.Off)
        return fn()
    end, function()
        DebugType.General:setLogSeverity(generalLog)
        for name, value in pairs(saved) do
            options:getOptionByName(name):setValue(value)
        end
        ItemPickerJava.InitSandboxLootSettings()
    end)
end

-- Adds the items in the container to `counts` (fullType -> count), bags' and boxes' contents
-- included: the mod's items, or every item with `everything`.
local function countItems(container, counts, everything)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fullType = item:getFullType()
        if everything or isModItem(fullType) then
            counts[fullType] = (counts[fullType] or 0) + 1
        end
        if item:IsInventoryContainer() then
            countItems(item:getInventory(), counts, everything)
        end
    end
end

--- A scratch crate. A procedural table rolls only into a container on a square; give those one
--- outside any room, because a container in a room counts toward the room's per-room list limits
--- and gets its forced lists.
---@param square IsoGridSquare?
function Loot.newContainer(square)
    return ItemContainer.new("crate", square, nil)
end

-- Takes the container's items, bags' contents included, off the cell's processed items, where
-- ItemContainer.AddItem puts every new item: thousands of fills in one frame pile up there until
-- the run runs out of memory (DEVELOPMENT.md, Loot).
local function forgetItems(container, processItems)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        processItems:remove(item)
        if item:IsInventoryContainer() then
            forgetItems(item:getInventory(), processItems)
        end
    end
end

--- Calls fill(container) on an emptied `container` once and returns what it got, bags' contents
--- included: fullType -> count, of the mod's items, or of every item with `everything`.
function Loot.fillOnce(fill, container, everything)
    container:removeAllItems()
    fill(container)
    local counts = {}
    countItems(container, counts, everything)
    forgetItems(container, getCell():getProcessItems())
    container:removeAllItems()
    return counts
end

local function rollFill(list)
    return function(container)
        ItemPickerJava.rollItem(list, container, true, nil, nil)
    end
end

-- Fills `container` `samples` times. Returns fullType -> { share = fraction of samples holding
-- at least one, perContainer = mean count in those }.
local function sample(fill, samples, container, everything)
    local holding, total = {}, {}
    for _ = 1, samples do
        for fullType, count in pairs(Loot.fillOnce(fill, container, everything)) do
            holding[fullType] = (holding[fullType] or 0) + 1
            total[fullType] = (total[fullType] or 0) + count
        end
    end
    local result = {}
    for fullType, n in pairs(holding) do
        result[fullType] = { share = n / samples, perContainer = total[fullType] / n }
    end
    return result
end

-- An outdoor square near the player, for procedural rolls.
local function squareOutsideRooms()
    local character, cell = getPlayer(), getCell()
    if not character or not cell then
        return nil
    end
    local px, py = math.floor(character:getX()), math.floor(character:getY())
    for radius = 0, 40 do
        for x, y in PZHarness.Fixtures.ring(px, py, radius) do
            local square = cell:getGridSquare(x, y, 0)
            if square and square:getRoom() == nil then
                return square
            end
        end
    end
    return nil
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
-- container.
local function worldStock()
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local stocks = {}
    local function add(label, reference, fill)
        table.insert(stocks, { label = label, reference = reference, fill = fill })
    end
    for _, name in ipairs(sortedKeys(WorldSpawns.BANK_STOCK)) do
        add("World bank: " .. name .. " (" .. WorldSpawns.BANK_STOCK[name].sprite .. ")", "world:bank." .. name,
            function(container) WorldSpawns.stockBank(container, name) end)
    end
    for _, name in ipairs(sortedKeys(WorldSpawns.CRATE_STOCK)) do
        add("World crate: " .. name, "world:crate." .. name, function(container) WorldSpawns.stockCrate(container, name) end)
    end
    add("Arrow board battery box", "world:arrowBoard", function(container)
        RenewableEnergy.ArrowBoard.stockBatteryBox(container)
        RenewableEnergy.Distributions.chargeFoundBatteries(container)
    end)
    return stocks
end

--- Measures every list the mod adds to, the stash crate, the room containers that pick the mod's
--- own lists, and the stock of world banks and crates, at the default loot rarity options. Returns
--- a list of { label, reference, samples, items = fullType -> { share, perContainer }, expected =
--- { [fullType] = true } }, with the loot multipliers it measured at in `settings`: { other = ...,
--- recipeResource = ... }. World stock counts vanilla items too.
function Loot.report(samples)
    return Loot.withMeasureOptions(function()
        local targets = lootTargets()
        table.insert(targets, { reference = STASH_CRATE, items = {} })
        local function build()
            local containers, lists = roomContainersModOnly()
            for key, lootTable in pairs(modOnlyTables(targets)) do
                containers[key] = lootTable
            end
            return containers, lists
        end
        return withLoot(1, build, function(parsed)
            local entries = {}
            local function add(label, reference, fill, container, expected, everything)
                table.insert(entries, {
                    label = label,
                    reference = reference,
                    samples = fill and samples or 0,
                    items = fill and sample(fill, samples, container, everything) or {},
                    expected = expected,
                })
            end
            local container = Loot.newContainer(nil)
            for i, target in ipairs(targets) do
                local list = parsed["t" .. i]
                add(labelFor(target.reference), target.reference, list and rollFill(list), container, target.items)
            end
            local square = squareOutsideRooms()
            local roomContainer = Loot.newContainer(square)
            for i, spec in ipairs(ROOM_CONTAINERS) do
                local list = square and parsed["r" .. i]
                add(spec.label, spec.room .. "." .. spec.container, list and rollFill(list), roomContainer, {})
            end
            for _, stock in ipairs(worldStock()) do
                add(stock.label, stock.reference, stock.fill, container, {}, true)
            end
            entries.settings = {
                other = ItemPickerJava.getLootModifierFromType("Other"),
                recipeResource = ItemPickerJava.getLootModifierFromType("RecipeResource"),
            }
            return entries
        end)
    end)
end

-- Module-watts report ------------------------------------------------------------------------------
-- How many solar modules a thorough player finds in a town, with their summed condition, which
-- --loot turns into watts: dev/loot/census.py's counts of the town's container tiles, rooms and
-- vehicle stalls, each times its expected modules, plus the world crates of its rooms and the
-- solar sites in its bounds. Expectations come from the loot tables' weights the way the game
-- rolls them (ItemPickerJava.getActualSpawnChance), so the report is exact for the lists and
-- approximate where the game picks among them: a procedural container picks a list by
-- weightChance, at most `max` per room, and lists forced by zone, tile or room are left out.
-- "Repaired" is after one Seal Cracked Module on every module it helps.

local MODULE = RenewableEnergy.Specs.factoryModule

-- A count of modules with their summed condition, as found and as repaired.
local function haul(count, condition, repaired)
    return { count = count, condition = condition * count, repaired = repaired * count }
end

local function addHaul(total, part, times)
    times = times or 1
    total.count = total.count + part.count * times
    total.condition = total.condition + part.condition * times
    total.repaired = total.repaired + part.repaired * times
end

local function emptyHaul()
    return haul(0, 0, 0)
end

-- The mean of a { min, max } range whose every whole number is as likely.
local function midpoint(range)
    return (range.min + range.max) / 2
end

-- One module whose condition is uniform over the range: { count = 1, condition, repaired }. A
-- scratch module takes each condition, so Seal Cracked Module's own test and result price it.
local function moduleOver(range)
    local Recipes = RenewableEnergy.Recipes
    local module = instanceItem(MODULE)
    local sum, repairedSum, n = 0, 0, 0
    for condition = range.min, range.max do
        RenewableEnergy.Wear.setCondition(module, condition)
        sum = sum + condition
        repairedSum = repairedSum + (Recipes.isModuleBelowRepairCap(module) and Recipes.repairedCondition(module) or condition)
        n = n + 1
    end
    return haul(1, sum / n, repairedSum / n)
end

-- One module that is `a` with chance `share`, else `b`.
local function mix(share, a, b)
    return haul(1, share * a.condition + (1 - share) * b.condition, share * a.repaired + (1 - share) * b.repaired)
end

local function moduleKinds()
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local cracked, weathered = moduleOver(WorldSpawns.CRACKED), moduleOver(WorldSpawns.WEATHERED)
    return {
        intact = haul(1, 100, 100),
        cracked = cracked,
        weathered = weathered,
        site = mix(WorldSpawns.SITE_CRACKED_SHARE, cracked, weathered),
        secondOnArrowBoard = mix(RenewableEnergy.ArrowBoard.STOCK.secondCrackedChance, cracked, weathered),
    }
end

-- ItemPickerJava.getBaseChanceMultiplier: a junk entry rolls at its weight times this.
local JUNK_WEIGHT_MULTIPLIER = 1.4

-- The chance one roll of an entry of `weight` hits: ItemPickerJava rolls Rand.Next(10000) below
-- getActualSpawnChance, which is weight * 100 * the loot multiplier.
local function chancePerRoll(weight, multiplier)
    return math.min(1, math.ceil(weight * 100 * multiplier) / 10000)
end

-- Expected count of `fullType` in one fill of `list`'s items, with each weight times `weightFactor`.
-- Vanilla's lists name Base items without their module.
local function expectedInItems(list, fullType, weightFactor, multiplier)
    local total = 0
    local items = list.items or {}
    local short = fullType:match("^Base%.(.+)$")
    for i = 1, #items - 1, 2 do
        if items[i] == fullType or items[i] == short then
            total = total + (list.rolls or 1) * chancePerRoll(items[i + 1] * weightFactor, multiplier)
        end
    end
    return total
end

-- Expected count of `fullType` in one fill of a loot table, junk included, at the loot multipliers
-- ItemPickerJava.getLootModifier gives an entry and a junk entry.
local function expectedIn(lootTable, fullType)
    if type(lootTable) ~= "table" then
        return 0
    end
    local total = expectedInItems(lootTable, fullType, 1, ItemPickerJava.getLootModifier(fullType))
    if lootTable.junk then
        total = total + expectedInItems(lootTable.junk, fullType, JUNK_WEIGHT_MULTIPLIER,
            ItemPickerJava.getLootModifier(fullType, true))
    end
    return total
end

local function isForced(pick)
    return pick.forceForZones or pick.forceForTiles or pick.forceForRooms or pick.forceForItems
end

local function pickWeight(pick)
    return math.max(1, pick.weightChance or 1)
end

-- Expected items of `fullType` in `count` containers of `containerType` spread over `rooms` rooms
-- named `roomName`.
local function expectedInContainers(roomName, containerType, count, rooms, fullType)
    local room = SuburbsDistributions[roomName]
    local entry = room and room[containerType] or SuburbsDistributions.all[containerType]
    if type(entry) ~= "table" then
        return 0
    end
    if not entry.procedural then
        return count * expectedIn(entry, fullType)
    end
    local procList = entry.procList or {}
    local totalWeight = 0
    for _, pick in ipairs(procList) do
        if not isForced(pick) then
            totalWeight = totalWeight + pickWeight(pick)
        end
    end
    local perRoom = count / rooms
    local total = 0
    for _, pick in ipairs(procList) do
        local list = ProceduralDistributions.list[pick.name]
        if not isForced(pick) and list then
            local picked = perRoom * pickWeight(pick) / totalWeight
            total = total + rooms * math.min(picked, pick.max or picked) * expectedIn(list, fullType)
        end
    end
    return total
end

-- Expected count of a CRATE_STOCK line, as WorldSpawns.stockCrate rolls and scales it.
local function crateLineCount(line)
    return (line[2] + line[3]) / 2 * (line[4] and SandboxVars.RenewableEnergy[line[4]] or 1)
end

-- Expected modules in a world crate stocked from WorldSpawns.CRATE_STOCK[name].
local function crateModules(name)
    local modules = 0
    for _, line in ipairs(RenewableEnergy.WorldSpawns.CRATE_STOCK[name]) do
        if line[1] == MODULE then
            modules = modules + crateLineCount(line)
        end
    end
    return modules
end

-- What WorldSpawns' OnSeeNewRoom puts in a town's rooms on average: `banks`, by BANK_ROOMS room
-- name, { placed, stock }; and `crates`, which it stocks as kits. None with Battery Bank Spawn off.
local function roomSpawns(town)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local spawns = { banks = {}, crates = 0 }
    local rarity = WorldSpawns.RARITY[SandboxVars.RenewableEnergy.BatteryBankSpawn]
    if rarity then
        for roomName, bank in pairs(WorldSpawns.BANK_ROOMS) do
            spawns.banks[roomName] = { placed = (town.rooms[roomName] or 0) / (bank.odds * rarity), stock = bank.stock }
        end
        for roomName, odds in pairs(WorldSpawns.CRATE_ROOMS) do
            spawns.crates = spawns.crates + (town.rooms[roomName] or 0) / (odds * rarity)
        end
    end
    return spawns
end

-- What the rooms of a town hold: list modules (whole), cracked modules, world crates, and the
-- modules beside the world banks that lay them (WorldSpawns.layModulesBeside).
local function roomsHaul(town, kinds)
    local Distributions, WorldSpawns = RenewableEnergy.Distributions, RenewableEnergy.WorldSpawns
    local listed, cracked, besideBanks = 0, 0, 0
    for roomName, byType in pairs(town.containers) do
        local rooms = math.max(1, town.rooms[roomName] or 0)
        for containerType, count in pairs(byType) do
            listed = listed + expectedInContainers(roomName, containerType, count, rooms, MODULE)
            local weight = Distributions.crackedModuleRoomWeight(roomName, containerType)
            if weight > 0 then
                cracked = cracked + count * Distributions.crackedModuleChance(weight)
            end
        end
    end
    local spawns = roomSpawns(town)
    for _, bank in pairs(spawns.banks) do
        local spec = WorldSpawns.BANK_STOCK[bank.stock].modules
        if spec then
            besideBanks = besideBanks + bank.placed * spec.chance * midpoint(spec) * SandboxVars.RenewableEnergy.LRMSolarPanels
        end
    end
    return {
        listed = haul(listed, kinds.intact.condition, kinds.intact.repaired),
        cracked = haul(cracked, kinds.cracked.condition, kinds.cracked.repaired),
        crates = haul(spawns.crates * crateModules("kit"), kinds.site.condition, kinds.site.repaired),
        besideBanks = haul(besideBanks, kinds.site.condition, kinds.site.repaired),
    }
end

-- An arrow board's modules: as many as the panel rarity option gives, one a panel at most.
local function arrowBoardHaul(kinds)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local total = emptyHaul()
    local modules = math.min(#ArrowBoard.PANELS, ArrowBoard.STOCK.modules * SandboxVars.RenewableEnergy.LRMSolarPanels)
    addHaul(total, kinds.weathered, math.min(1, modules))
    addHaul(total, kinds.secondOnArrowBoard, math.max(0, modules - 1))
    return total
end

-- BaseVehicle.randomizeContainers' special loot chance for a script whose own is 0 or less. It
-- rolls Rand.Next(100) <= chance, so a chance of n is n + 1 in 100.
local DEFAULT_SPECIAL_LOOT_CHANCE = 8

-- Expected items of `fullType` in one vehicle of a script: its Normal loot, or one of its Specific
-- sets at the vehicle's special loot chance.
local function vehicleExpected(script, fullType)
    local name = string.gsub(script, "^Base%.", "")
    -- Vanilla VehicleDistributions.lua inserts its table by vehicle script name at index 1.
    local distribution = VehicleDistributions[1][name]
    if not distribution then
        return 0
    end
    local vehicleScript = getScriptManager():getVehicle(script)
    local chance = vehicleScript and vehicleScript:getSpecialLootChance() or 0
    local specialShare = ((chance > 0 and chance or DEFAULT_SPECIAL_LOOT_CHANCE) + 1) / 100
    local function inSet(set)
        local total = 0
        for part, lootTable in pairs(set or {}) do
            if part ~= "specificId" then
                total = total + expectedIn(lootTable, fullType)
            end
        end
        return total
    end
    local specific = distribution.Specific or {}
    if #specific == 0 then
        return inSet(distribution.Normal)
    end
    local specificTotal = 0
    for _, set in ipairs(specific) do
        specificTotal = specificTotal + inSet(set)
    end
    return (1 - specialShare) * inSet(distribution.Normal) + specialShare * specificTotal / #specific
end

-- The chance a traffic jam's slot takes a car (Rand.Next(100) <= 80), and that a chunk of an
-- rtrafficjam zone jams at all (IsoChunk.AddVehicles).
local JAM_SLOT_TAKEN, RANDOM_JAM_CHUNK = 0.81, 0.1
-- VehicleType's spawnRate and chanceToSpawnNormal for a zone that sets none.
local DEFAULT_SPAWN_RATE, DEFAULT_CHANCE_TO_SPAWN_NORMAL = 16, 80

-- The vehicles a stall of the zone holds, by script: the chance a stall holds one, as
-- IsoChunk.AddVehicles_OnZone and VehicleType.getRandomVehicleType roll them, leaving out the
-- special vehicles a few stalls of an ordinary zone turn into. A traffic jam's slots, which
-- census.py counts as IsoChunk.AddVehicles_TrafficJam_* lays them out, take a car far more often
-- than a stall does.
local function zoneVehicles(zoneName)
    local randomJam = zoneName:match("^r(trafficjam%a)$")
    local zone = VehicleZoneDistribution[randomJam or zoneName]
    if not zone or not zone.vehicles then
        return {}
    end
    local spawn
    if randomJam then
        spawn = JAM_SLOT_TAKEN * RANDOM_JAM_CHUNK
    elseif zoneName:match("^trafficjam%a$") then
        spawn = JAM_SLOT_TAKEN
    else
        spawn = math.min(1, ((zone.spawnRate or DEFAULT_SPAWN_RATE) + 1) / 100)
    end
    spawn = spawn * (1 - (zone.chanceToSpawnBurnt or 0) / 100)
    local result = {}
    local function addFrom(vehicles, share)
        local total = 0
        for _, entry in pairs(vehicles) do
            total = total + entry.spawnChance
        end
        for script, entry in pairs(vehicles) do
            result[script] = (result[script] or 0) + share * entry.spawnChance / total
        end
    end
    local normal = zone.specialCar and (zone.chanceToSpawnNormal or DEFAULT_CHANCE_TO_SPAWN_NORMAL) / 100 or 0
    addFrom(zone.vehicles, spawn * (1 - normal))
    if normal > 0 then
        addFrom(VehicleZoneDistribution.parkingstall.vehicles, spawn * normal)
    end
    return result
end

-- The cracked modules one vehicle of the script holds in the vehicle zone `zoneName`: each of its
-- containers that BaseVehicle.randomizeContainers fills rolls Distributions.addCrackedModules
-- once. A part counts as a container when the script's loot names it, which leaves out its doors.
local function vehicleCrackedModules(script, zoneName)
    local Distributions = RenewableEnergy.Distributions
    local distribution = VehicleDistributions[1][(string.gsub(script, "^Base%.", ""))]
    local vehicleScript = getScriptManager():getVehicle(script)
    if not (distribution and distribution.Normal and vehicleScript) then
        return 0
    end
    local total = 0
    for i = 0, vehicleScript:getPartCount() - 1 do
        local partId = vehicleScript:getPart(i):getId()
        if distribution.Normal[partId] then
            total = total + Distributions.crackedModuleChance(Distributions.crackedModuleVehicleWeight(zoneName, partId))
        end
    end
    return total
end

local function vehiclesHaul(stalls, kinds)
    local arrowBoard = RenewableEnergy.ArrowBoard.SCRIPT
    local total, arrowBoards = emptyHaul(), 0
    local cache = {}
    for zoneName, count in pairs(stalls) do
        for script, perStall in pairs(zoneVehicles(zoneName)) do
            local vehicles = count * perStall
            if script == arrowBoard then
                arrowBoards = arrowBoards + vehicles
                addHaul(total, arrowBoardHaul(kinds), vehicles)
            else
                cache[script] = cache[script] or vehicleExpected(script, MODULE)
                addHaul(total, kinds.intact, vehicles * cache[script])
                addHaul(total, kinds.cracked, vehicles * vehicleCrackedModules(script, zoneName))
            end
        end
    end
    return total, arrowBoards
end

local function siteSpot(site)
    local spot = (site.panels and site.panels[1]) or site.bank or site.arrowBoard or site.generator
    return spot[1], spot[2]
end

-- Expected modules of a site once placed.
local function siteHaul(site, kinds)
    local SolarSites = RenewableEnergy.SolarSites
    local kind = SolarSites.KINDS[site.kind]
    local total = emptyHaul()
    if kind.panels then
        local placedPanels = (kind.panels.min + math.min(kind.panels.max, #site.panels)) / 2
        local moduleSum = 0
        for _, panel in ipairs(site.panels) do
            local mount = SolarSites.mountKind(panel[4])
            moduleSum = moduleSum + (kind.modules and midpoint(kind.modules) or RenewableEnergy.Specs.mounts[mount].modules)
        end
        addHaul(total, kinds.site, placedPanels * moduleSum / #site.panels)
    end
    if kind.crate then
        addHaul(total, kinds.site, crateModules(kind.crate))
    end
    if site.arrowBoard then
        addHaul(total, arrowBoardHaul(kinds))
    end
    return total
end

local function inTown(town, x, y)
    return x >= town.x1 and x <= town.x2 and y >= town.y1 and y <= town.y2
end

local function buildModuleReport(census)
    local SolarSites = RenewableEnergy.SolarSites
    local kinds = moduleKinds()
    local report = { towns = {}, sites = {} }
    for _, site in ipairs(SolarSites.sites()) do
        table.insert(report.sites, { name = site.name, kind = site.kind, haul = siteHaul(site, kinds), site = site,
            chance = SolarSites.siteChance(site) })
    end
    -- The census's last town is the whole map.
    local zoneBoards = 0
    for _, town in ipairs(census.towns) do
        local row = roomsHaul(town, kinds)
        row.name = town.name
        row.vehicles, zoneBoards = vehiclesHaul(town.vehicleStalls, kinds)
        row.sites = emptyHaul()
        for _, entry in ipairs(report.sites) do
            if inTown(town, siteSpot(entry.site)) then
                addHaul(row.sites, entry.haul, entry.chance)
            end
        end
        row.total = emptyHaul()
        for _, part in ipairs({ row.listed, row.cracked, row.crates, row.besideBanks, row.vehicles, row.sites }) do
            addHaul(row.total, part)
        end
        table.insert(report.towns, row)
    end
    local siteBoards = 0
    for _, entry in ipairs(report.sites) do
        if entry.site.arrowBoard then
            siteBoards = siteBoards + entry.chance
        end
    end
    report.arrowBoards = { zones = zoneBoards, sites = siteBoards }
    return report
end

--- The module report: for each town of the census, { name, listed, cracked, crates, besideBanks, vehicles,
--- sites, total } hauls ({ count, condition, repaired }, condition summed over the modules);
--- `sites`, each { name, kind, haul, chance }, the haul once placed; `arrowBoards`, the expected
--- number on the map, { zones, sites }. At the default loot settings and loot rarity
--- options 1.
function Loot.moduleReport(census)
    return Loot.withMeasureOptions(function()
        return withLootRarity(1, function()
            return buildModuleReport(census)
        end)
    end)
end

-- Battery report ---------------------------------------------------------------------------------
-- How many batteries a thorough player finds in a town, and their watt-hours as found, from the
-- same census as the module report: the mod's deep cycles and L-16s in room loot and vehicles
-- (whole, as loot spawns them), the world banks and kit crates WorldSpawns' OnSeeNewRoom puts in
-- rooms (each room kind's count over its odds), the solar sites in the town, and arrow boards. Car
-- batteries in room loot are counted apart: vanilla's, and every car carries one besides.

local LOOSE_BATTERIES = { "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery" }
local CAR_BATTERIES = { "Base.CarBattery1", "Base.CarBattery2", "Base.CarBattery3" }

local function batteries(count, wh)
    return { count = count, wh = wh }
end

local function addBatteries(total, part, times)
    times = times or 1
    total.count = total.count + part.count * times
    total.wh = total.wh + part.wh * times
end

local function batteryWh(fullType)
    return RenewableEnergy.Specs.batteries[fullType].wh
end

-- Rolls per side of the grid wearShare averages the three wear rolls over.
local WEAR_GRID = 20

-- The mean share of full condition the BATTERY_WEAR profile `wearName` leaves a battery, duds
-- included: WorldSpawns.foundBatteryPercent averaged over a grid of midpoints of its three rolls.
local function wearShare(wearName)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local wear, dud = WorldSpawns.BATTERY_WEAR[wearName], WorldSpawns.DUD
    local sum = 0
    for a = 0, WEAR_GRID - 1 do
        for b = 0, WEAR_GRID - 1 do
            for c = 0, WEAR_GRID - 1 do
                sum = sum + WorldSpawns.foundBatteryPercent(wear, (a + 0.5) / WEAR_GRID, (b + 0.5) / WEAR_GRID,
                    (c + 0.5) / WEAR_GRID)
            end
        end
    end
    local chance = wear.dud or 0
    return ((1 - chance) * sum / WEAR_GRID ^ 3 + chance * midpoint(dud)) / 100
end

-- The batteries a bank stocked as BANK_STOCK[stockName] holds on average.
local function stockBatteries(stockName)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local stock = WorldSpawns.BANK_STOCK[stockName]
    local cap = RenewableEnergy.PowerBank.bankOfSprite(RenewableEnergy.Sprites[stock.sprite]).spec.maxBatteries
    local counts, count = 0, 0
    for rolled = stock.batteries.min, stock.batteries.max do
        count = count + math.min(cap, rolled * SandboxVars.RenewableEnergy.LRMBatteries)
        counts = counts + 1
    end
    count = count / counts
    local weights, wh = 0, 0
    for _, entry in ipairs(stock.batteries.types) do
        weights = weights + entry[2]
        wh = wh + entry[2] * batteryWh(entry[1])
    end
    return batteries(count, count * wh / weights * wearShare(stock.batteries.wear))
end

-- The batteries a world crate stocked from CRATE_STOCK[name] holds on average.
local function crateBatteries(name)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local total = batteries(0, 0)
    for _, line in ipairs(WorldSpawns.CRATE_STOCK[name]) do
        if RenewableEnergy.Specs.batteries[line[1]] then
            local count = crateLineCount(line)
            addBatteries(total, batteries(count, count * batteryWh(line[1]) * wearShare(WorldSpawns.CRATE_WEAR)))
        end
    end
    return total
end

-- An arrow board's battery box on average: its count, worn from years on the road.
local function arrowBoardBatteries()
    local stock = RenewableEnergy.ArrowBoard.STOCK
    local count = midpoint(stock.batteries) * SandboxVars.RenewableEnergy.LRMBatteries
    local condition = midpoint(stock.batteryCondition) / 100
    return batteries(count, count * batteryWh(stock.battery) * condition)
end

-- What the rooms of a town hold: the mod's batteries in room loot, car batteries in room loot,
-- world banks (with how many) and kit crates.
local function roomsBatteries(town)
    local listed, cars = batteries(0, 0), 0
    for roomName, byType in pairs(town.containers) do
        local rooms = math.max(1, town.rooms[roomName] or 0)
        for containerType, count in pairs(byType) do
            for _, fullType in ipairs(LOOSE_BATTERIES) do
                local found = expectedInContainers(roomName, containerType, count, rooms, fullType)
                addBatteries(listed, batteries(found, found * batteryWh(fullType)))
            end
            for _, fullType in ipairs(CAR_BATTERIES) do
                cars = cars + expectedInContainers(roomName, containerType, count, rooms, fullType)
            end
        end
    end
    local spawns = roomSpawns(town)
    local banks, bankCount, banksByRoom = batteries(0, 0), 0, {}
    for roomName, bank in pairs(spawns.banks) do
        bankCount = bankCount + bank.placed
        banksByRoom[roomName] = bank.placed
        addBatteries(banks, stockBatteries(bank.stock), bank.placed)
    end
    local crates = batteries(0, 0)
    addBatteries(crates, crateBatteries("kit"), spawns.crates)
    return { listed = listed, cars = cars, banks = banks, bankCount = bankCount, banksByRoom = banksByRoom, crates = crates }
end

-- The mod's batteries in the vehicles of `stalls`, arrow boards' boxes included.
local function vehiclesBatteries(stalls)
    local arrowBoard = RenewableEnergy.ArrowBoard.SCRIPT
    local total, cache = batteries(0, 0), {}
    for zoneName, count in pairs(stalls) do
        for script, perStall in pairs(zoneVehicles(zoneName)) do
            local vehicles = count * perStall
            if script == arrowBoard then
                addBatteries(total, arrowBoardBatteries(), vehicles)
            else
                for _, fullType in ipairs(LOOSE_BATTERIES) do
                    local key = script .. fullType
                    cache[key] = cache[key] or vehicleExpected(script, fullType)
                    addBatteries(total, batteries(cache[key], cache[key] * batteryWh(fullType)), vehicles)
                end
            end
        end
    end
    return total
end

-- The batteries of a site once placed: its bank, its crate and its arrow board's box.
local function siteBatteries(site)
    local kind = RenewableEnergy.SolarSites.KINDS[site.kind]
    local total = batteries(0, 0)
    local stock = site.bank and (kind.bank or kind.wind)
    if stock then
        addBatteries(total, stockBatteries(stock))
    end
    if kind.crate then
        addBatteries(total, crateBatteries(kind.crate))
    end
    if site.arrowBoard then
        addBatteries(total, arrowBoardBatteries())
    end
    return total
end

local function buildBatteryReport(census)
    local sites = {}
    local SolarSites = RenewableEnergy.SolarSites
    for _, site in ipairs(SolarSites.sites()) do
        table.insert(sites, { site = site, haul = siteBatteries(site), chance = SolarSites.siteChance(site) })
    end
    local report = { towns = {} }
    for _, town in ipairs(census.towns) do
        local row = roomsBatteries(town)
        row.name = town.name
        row.vehicles = vehiclesBatteries(town.vehicleStalls)
        row.sites = batteries(0, 0)
        for _, entry in ipairs(sites) do
            if inTown(town, siteSpot(entry.site)) then
                addBatteries(row.sites, entry.haul, entry.chance)
            end
        end
        row.total = batteries(0, 0)
        for _, part in ipairs({ row.listed, row.banks, row.crates, row.vehicles, row.sites }) do
            addBatteries(row.total, part)
        end
        table.insert(report.towns, row)
    end
    report.stocks = {}
    for name in pairs(RenewableEnergy.WorldSpawns.BANK_STOCK) do
        report.stocks[name] = stockBatteries(name)
    end
    return report
end

--- The battery report: for each town of the census, { name, listed, banks, crates, vehicles,
--- sites, total } batteries ({ count, wh }, wh as found), `bankCount`, the world banks, and
--- `banksByRoom` them by room name, `cars`, car batteries in room loot; and `stocks`, each
--- BANK_STOCK's batteries on average. At the default loot settings and loot rarity options 1.
function Loot.batteryReport(census)
    return Loot.withMeasureOptions(function()
        return withLootRarity(1, function()
            return buildBatteryReport(census)
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
local CLEAR_ONLY = { { 1, Loot.WEATHER_MIX[1][2] } }
-- The 15th of July and of December, as days of the year.
local MONTH_DAYS = { july = 196, december = 349 }
--- The mounts the light is measured on, by name: Sun.planeIrradiance's kind and facing.
Loot.SOUTH_MOUNTS = { flat = { "flat" }, rack = { "rack", "S" }, wall = { "wall", "S" } }

-- Vanilla's generator fuel an hour for each appliance kind (IsoGenerator's *PowerConsumption
-- constants).
local APPLIANCE_FUEL = {
    fridgeFreezer = 0.13, fridge = 0.08, light = 0.002, television = 0.03, radio = 0.01,
    microwave = 0.09, range = 0.09, washer = 0.09, dryer = 0.09, batteryCharger = 0.05,
}

--- The watts an appliance of the kind `name` (an APPLIANCE_FUEL key) draws as a bank bills it.
function Loot.applianceWatts(name)
    return RenewableEnergy.Specs.wattsFromFuel(APPLIANCE_FUEL[name])
end

-- Watt-hours a factory module at full condition on `mount` banks over the day `dayOfYear` under
-- `mix`, in half-hour steps, at the save's Sunlight Multiplier.
local function moduleDayWh(dayOfYear, mount, mix)
    local Sun = RenewableEnergy.Sun
    local rated = RenewableEnergy.Specs.modules[MODULE].watts
    local latitude = getClimateManager():getSeason():getLat()
    local step, wh = 0.5, 0
    for hour = -12, 12 - step, step do
        local sun = Sun.position(dayOfYear, hour + step / 2, latitude)
        for _, part in ipairs(mix) do
            wh = wh + part[1] * Sun.wattsFrom(rated, Sun.planeIrradiance(sun, mount[1], mount[2], part[2]), 0) * step
        end
    end
    return wh
end

-- Each kind of battery a bank holds; the three car batteries are alike, so one stands for them.
local LIFE_BATTERIES = { "Base.CarBattery1", "RenewableEnergy.JarBattery", "RenewableEnergy.DeepCycleBattery",
    "RenewableEnergy.L16Battery" }

-- Nights a new battery of `fullType` takes to fall to half capacity carrying a load of `depth` of
-- its new capacity every night, worn as a bank wears it (Battery.cycleWear at the Battery Wear
-- option): the same load is a deeper share of what a worn battery holds. nil if wear is off.
local function nightsToHalf(fullType, depth)
    local Battery = RenewableEnergy.Battery
    local scale = Battery.wearScale()
    if scale <= 0 then
        return nil
    end
    local item = instanceItem(fullType)
    local full = item:getConditionMax()
    local nights = 0
    while item:getCondition() > full / 2 do
        Battery.wear(item, Battery.cycleWear(item, math.min(1, depth * full / item:getCondition())) * scale)
        nights = nights + 1
    end
    return nights
end

--- What turns the hauls into hours: `moduleWh[month][mount]`, { average, clear }, watt-hours a
--- day one new factory module banks mid-July and mid-December; `applianceW`, each appliance's
--- watts as a bank bills it; `sunlight`, the Sunlight Multiplier they assume; `batteryLife`, for
--- each of LIFE_BATTERIES in order, { fullType, half, quarter }, the nights it lasts to half
--- capacity under a nightly load of half and of a quarter its new capacity (nil with wear off);
--- `batteryWear`, the Battery Wear option they assume.
function Loot.yardsticks()
    local moduleWh = {}
    for month, day in pairs(MONTH_DAYS) do
        moduleWh[month] = {}
        for name, mount in pairs(Loot.SOUTH_MOUNTS) do
            moduleWh[month][name] = { average = moduleDayWh(day, mount, Loot.WEATHER_MIX), clear = moduleDayWh(day, mount, CLEAR_ONLY) }
        end
    end
    local applianceW = {}
    for name in pairs(APPLIANCE_FUEL) do
        applianceW[name] = Loot.applianceWatts(name)
    end
    local batteryLife = {}
    for _, fullType in ipairs(LIFE_BATTERIES) do
        table.insert(batteryLife, { fullType = fullType, half = nightsToHalf(fullType, 0.5), quarter = nightsToHalf(fullType, 0.25) })
    end
    return { moduleWh = moduleWh, applianceW = applianceW, sunlight = SandboxVars.RenewableEnergy.SunlightMultiplier,
        batteryLife = batteryLife, batteryWear = SandboxVars.RenewableEnergy.BatteryWear }
end

return Loot
