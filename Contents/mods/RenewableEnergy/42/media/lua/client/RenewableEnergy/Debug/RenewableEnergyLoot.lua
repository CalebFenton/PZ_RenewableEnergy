require "RenewableEnergy/Utilities"

-- Measures how often the mod's items spawn, with the game's own loot rolls on scratch containers
-- that never enter the world, and how world banks and crates are stocked. For tuning
-- Distributions.lua and WorldSpawns.lua, for the numbers in the README, and for the loot tests.
-- dev/run-debug-client.sh --loot prints RenewableEnergyLoot.report(). Debug mode only.
--
-- The report rolls copies of the lists that hold only the mod's items. Each entry rolls on its
-- own, so that gives the same chances without creating the vanilla items, and rolling the whole
-- lists thousands of times ran the client out of memory. What it leaves out: a container that
-- the vanilla items have already filled stops rolling, which makes the real chances a little
-- lower in lists of heavy items.
RenewableEnergyLoot = {}

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
    ["sub:RenewableEnergyStashCache.RenewableEnergySolarBox"] = "Solar crate in the mod's stash houses",
}

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
    { room = "RenewableEnergyStashCache", container = "crate", label = "Crates in the mod's stash houses" },
    { room = "RenewableEnergyStashCache", container = "metal_shelves", label = "Metal shelves in the mod's stash houses" },
}

-- Sandbox options while measuring: the loot settings of a new game with the default preset,
-- without the zombie density bonus (of the mod's items only the magazines can get it, and that
-- preset turns it off anyway), and without annotated maps, each of which uses up a stash of the
-- world. DEFAULT stands for the option's default value, which the game takes from the Apocalypse
-- preset (SandboxOptions constructor).
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

--- The loot table a reference from RenewableEnergy.Distributions.items names. A junk list is
--- rolled with the list it belongs to, so "proc:X.junk" gives the table of X.
---@param reference string
---@return table?
function RenewableEnergyLoot.lootTable(reference)
    local kind, name = string.match(reference, "^(%a+):(.+)$")
    local list
    if kind == "proc" then
        list = ProceduralDistributions.list[string.match(name, "^([^.]+)%.junk$") or name]
    elseif kind == "veh" then
        list = VehicleDistributions[name]
    elseif kind == "sub" then
        list = SuburbsDistributions
        for part in string.gmatch(name, "[^.]+") do
            list = type(list) == "table" and list[part] or nil
        end
    end
    return type(list) == "table" and list or nil
end

--- The references in RenewableEnergy.Distributions.items with junk lists folded into their own,
--- each with the set of item types it lists: { { reference = ..., items = { [fullType] = true } } }.
function RenewableEnergyLoot.targets()
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

--- A copy of a loot table with only the mod's items, junk included.
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

--- Runs fn(parsed) with the mod's loot rarity options at `lrm` and the probe build() returns
--- parsed by the game. build() runs once the mod's loot is in for `lrm` and returns `containers`,
--- key -> loot table, and optionally `lists`, name -> extra ProceduralDistributions list for
--- procedural containers to pick. parsed[key] is the game's copy of the container to pass to
--- ItemPickerJava.rollItem, or nil if the game didn't take it. Afterwards restores the options and
--- parses the loot as it was.
function RenewableEnergyLoot.withLoot(lrm, build, fn)
    local saved = {}
    for _, option in ipairs(LRM_OPTIONS) do
        saved[option] = SandboxVars.RenewableEnergy[option]
        SandboxVars.RenewableEnergy[option] = lrm
    end
    RenewableEnergy.Distributions.apply()
    local containers, lists = build()
    lists = lists or {}
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
    local result = fn(parsed)
    SuburbsDistributions[PROBE_ROOM] = nil
    for name in pairs(lists) do
        ProceduralDistributions.list[name] = nil
    end
    for option, value in pairs(saved) do
        SandboxVars.RenewableEnergy[option] = value
    end
    RenewableEnergy.Distributions.apply()
    ItemPickerJava.Parse()
    return result
end

--- One table per target of RenewableEnergyLoot.targets(), keyed "t<index>": the list itself, or
--- with `modOnly` a copy of it with only the mod's items.
function RenewableEnergyLoot.tablesFor(targets, modOnly)
    local tables = {}
    for i, target in ipairs(targets) do
        local lootTable = RenewableEnergyLoot.lootTable(target.reference)
        if lootTable and modOnly then
            lootTable = modItemsOnly(lootTable)
        end
        tables["t" .. i] = lootTable
    end
    return tables
end

--- The containers of ROOM_CONTAINERS keyed "r<index>", each picking from copies of its lists with
--- only the mod's items, and those copies.
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
function RenewableEnergyLoot.withMeasureOptions(fn)
    local options = getSandboxOptions()
    local saved = {}
    for name, value in pairs(MEASURE_OPTIONS) do
        local option = options:getOptionByName(name)
        saved[name] = option:getValue()
        option:setValue(value == DEFAULT and option:getDefaultValue() or value)
    end
    ItemPickerJava.InitSandboxLootSettings()
    local generalLog = DebugType.General:getLogSeverity()
    DebugType.General:setLogSeverity(LogSeverity.Off)
    local result = fn()
    DebugType.General:setLogSeverity(generalLog)
    for name, value in pairs(saved) do
        options:getOptionByName(name):setValue(value)
    end
    ItemPickerJava.InitSandboxLootSettings()
    return result
end

-- Adds the mod's items in the container to `counts` (fullType -> count), bags and boxes included.
local function countItems(container, counts)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fullType = item:getFullType()
        if isModItem(fullType) then
            counts[fullType] = (counts[fullType] or 0) + 1
        elseif item:IsInventoryContainer() then
            countItems(item:getInventory(), counts)
        end
    end
end

--- A scratch crate. A procedural table rolls only into a container on a square; give those one
--- outside any room, because a container in a room counts toward the room's per-room list limits
--- and gets its forced lists.
---@param square IsoGridSquare?
function RenewableEnergyLoot.newContainer(square)
    return ItemContainer.new("crate", square, nil)
end

-- Takes the container's items, bags' contents included, off the cell's processed items, where
-- ItemContainer.AddItem puts every new item. The report fills containers thousands of times in
-- one frame, before the cell would drop them: left there they pile up, and every AddItem scans
-- the whole list, until the run crawls and runs out of memory.
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

--- Calls fill(container) on an emptied `container` once and returns what it got: fullType ->
--- count, of the mod's items, or of every item with `everything`.
function RenewableEnergyLoot.fillOnce(fill, container, everything)
    container:removeAllItems()
    fill(container)
    local counts = {}
    if everything then
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local fullType = items:get(i):getFullType()
            counts[fullType] = (counts[fullType] or 0) + 1
        end
    else
        countItems(container, counts)
    end
    forgetItems(container, getCell():getProcessItems())
    container:removeAllItems()
    return counts
end

--- Rolls `list` (a parsed table) into an emptied `container` once and returns the mod's items it
--- got: fullType -> count.
function RenewableEnergyLoot.rollOnce(list, container)
    return RenewableEnergyLoot.fillOnce(function(target)
        ItemPickerJava.rollItem(list, target, true, nil, nil)
    end, container)
end

-- Fills `container` `samples` times. Returns fullType -> { share = fraction of samples holding
-- at least one, perContainer = mean count in those }.
local function sample(fill, samples, container, everything)
    local holding, total = {}, {}
    for _ = 1, samples do
        for fullType, count in pairs(RenewableEnergyLoot.fillOnce(fill, container, everything)) do
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

local function rollFill(list)
    return function(container)
        ItemPickerJava.rollItem(list, container, true, nil, nil)
    end
end

-- An outdoor square near the player, for procedural rolls.
function RenewableEnergyLoot.squareOutsideRooms()
    local player = getPlayer()
    local cell = getCell()
    if not player or not cell then
        return nil
    end
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    for radius = 0, 40 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
                local square = cell:getGridSquare(px + dx, py + dy, 0)
                if square and square:getRoom() == nil then
                    return square
                end
            end
        end
    end
    return nil
end

-- How WorldSpawns and the arrow board stock the containers they place, each into a scratch
-- container.
local function worldStock()
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local stocks = {}
    local function add(label, reference, fill)
        table.insert(stocks, { label = label, reference = reference, fill = fill })
    end
    local bankNames = {}
    for name in pairs(WorldSpawns.BANK_STOCK) do
        table.insert(bankNames, name)
    end
    table.sort(bankNames)
    for _, name in ipairs(bankNames) do
        add("World bank: " .. name .. " (" .. WorldSpawns.BANK_STOCK[name].sprite .. ")", "world:bank." .. name,
            function(container) WorldSpawns.stockBank(container, name) end)
    end
    for _, name in ipairs({ "kit", "powerYard" }) do
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
function RenewableEnergyLoot.report(samples)
    return RenewableEnergyLoot.withMeasureOptions(function()
        local targets = RenewableEnergyLoot.targets()
        table.insert(targets, { reference = "sub:RenewableEnergyStashCache.RenewableEnergySolarBox", items = {} })
        local function build()
            local containers, lists = roomContainersModOnly()
            for key, lootTable in pairs(RenewableEnergyLoot.tablesFor(targets, true)) do
                containers[key] = lootTable
            end
            return containers, lists
        end
        return RenewableEnergyLoot.withLoot(1, build, function(parsed)
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
            local container = RenewableEnergyLoot.newContainer(nil)
            for i, target in ipairs(targets) do
                local list = parsed["t" .. i]
                add(labelFor(target.reference), target.reference, list and rollFill(list), container, target.items)
            end
            local square = RenewableEnergyLoot.squareOutsideRooms()
            local roomContainer = RenewableEnergyLoot.newContainer(square)
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
-- How many solar modules, and how many watts of them, a thorough player finds in a town: every
-- container of every room, the crates world spawns put in rooms, the vehicles its stalls hold
-- and the solar sites in its bounds, from dev/loot/census.py's counts times each one's expected
-- modules. Expectations come from the loot tables' weights the way ItemPickerJava rolls them
-- (DEVELOPMENT.md, Loot), so the report is exact for the lists and approximate where the game
-- picks among them: a procedural container picks a list by weightChance, at most `max` per room,
-- and lists forced by zone, tile or room are left out. Watts weigh each module by its condition;
-- "repaired" is after one Repair Cracked Module on every module it helps.

local MODULE = "RenewableEnergy.SolarModule"
-- Repair Cracked Module: condition added, and the most it brings a factory module to.
local REPAIR = { add = 30, cap = 80 }

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

-- One module whose condition is uniform over the range: { count = 1, condition, repaired }.
local function moduleOver(range)
    local sum, repairedSum, n = 0, 0, 0
    for condition = range.min, range.max do
        sum = sum + condition
        repairedSum = repairedSum + (condition < REPAIR.cap and math.min(REPAIR.cap, condition + REPAIR.add) or condition)
        n = n + 1
    end
    return haul(1, sum / n, repairedSum / n)
end

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

local function chancePerRoll(weight, multiplier)
    return math.min(1, math.ceil(weight * 100 * multiplier) / 10000)
end

--- Expected count of `fullType` in one fill of a loot table, junk included.
local function expectedIn(lootTable, fullType)
    if type(lootTable) ~= "table" then
        return 0
    end
    local total = 0
    local multiplier = ItemPickerJava.getLootModifier(fullType)
    local items = lootTable.items or {}
    for i = 1, #items - 1, 2 do
        if items[i] == fullType then
            total = total + (lootTable.rolls or 1) * chancePerRoll(items[i + 1], multiplier)
        end
    end
    local junk = lootTable.junk
    for i = 1, #(junk and junk.items or {}) - 1, 2 do
        if junk.items[i] == fullType then
            total = total + (junk.rolls or 1) * chancePerRoll(junk.items[i + 1] * 1.4, 1)
        end
    end
    return total
end

local function isForced(pick)
    return pick.forceForZones or pick.forceForTiles or pick.forceForRooms or pick.forceForItems
end

--- Expected modules in `count` containers of `containerType` spread over `rooms` rooms named
--- `roomName`.
local function expectedInContainers(roomName, containerType, count, rooms)
    local room = SuburbsDistributions[roomName]
    local entry = room and room[containerType] or SuburbsDistributions.all[containerType]
    if type(entry) ~= "table" then
        return 0
    end
    if not entry.procedural then
        return count * expectedIn(entry, MODULE)
    end
    local totalWeight = 0
    for _, pick in ipairs(entry.procList or {}) do
        if not isForced(pick) then
            totalWeight = totalWeight + math.max(1, pick.weightChance or 1)
        end
    end
    local perRoom = count / rooms
    local total = 0
    for _, pick in ipairs(entry.procList or {}) do
        local list = ProceduralDistributions.list[pick.name]
        if not isForced(pick) and list then
            local picked = perRoom * math.max(1, pick.weightChance or 1) / totalWeight
            total = total + rooms * math.min(picked, pick.max or picked) * expectedIn(list, MODULE)
        end
    end
    return total
end

-- What the rooms of a town hold: list modules (whole), cracked modules and world crates.
local function roomsHaul(town, kinds)
    local Distributions, WorldSpawns = RenewableEnergy.Distributions, RenewableEnergy.WorldSpawns
    local listed, cracked, crates = 0, 0, 0
    for roomName, byType in pairs(town.containers) do
        local rooms = math.max(1, town.rooms[roomName] or 0)
        for containerType, count in pairs(byType) do
            listed = listed + expectedInContainers(roomName, containerType, count, rooms)
            local weight = Distributions.CRACKED_MODULE_CONTAINERS[containerType] and Distributions.CRACKED_MODULE_ROOMS[roomName]
            if weight then
                cracked = cracked + count * Distributions.crackedModuleChance(weight)
            end
        end
    end
    local rarity = WorldSpawns.RARITY[SandboxVars.RenewableEnergy.BatteryBankSpawn]
    local crateModules = 0
    for _, line in ipairs(WorldSpawns.CRATE_STOCK.kit) do
        if line[1] == MODULE then
            crateModules = (line[2] + line[3]) / 2 * SandboxVars.RenewableEnergy[line[4]]
        end
    end
    for roomName, odds in pairs(WorldSpawns.CRATE_ROOMS) do
        if rarity then
            crates = crates + (town.rooms[roomName] or 0) / (odds * rarity) * crateModules
        end
    end
    return {
        listed = haul(listed, kinds.intact.condition, kinds.intact.repaired),
        cracked = haul(cracked, kinds.cracked.condition, kinds.cracked.repaired),
        crates = haul(crates, kinds.site.condition, kinds.site.repaired),
    }
end

local function arrowBoardHaul(kinds)
    local stock = RenewableEnergy.ArrowBoard.STOCK
    local total = emptyHaul()
    local modules = stock.modules * SandboxVars.RenewableEnergy.LRMSolarPanels
    addHaul(total, kinds.weathered, math.min(1, modules))
    addHaul(total, kinds.secondOnArrowBoard, math.max(0, modules - 1))
    return total
end

-- Expected modules in one vehicle of a script: its Normal loot, or one of its Specific sets at
-- the vehicle's special loot chance (BaseVehicle.randomizeContainers: 8 in 100).
local SPECIAL_LOOT_CHANCE = 0.08
local function vehicleModules(script)
    local name = string.gsub(script, "^Base%.", "")
    local distribution = VehicleDistributions[1][name]
    if not distribution then
        return 0
    end
    local function setModules(set)
        local total = 0
        for part, lootTable in pairs(set or {}) do
            if part ~= "specificId" then
                total = total + expectedIn(lootTable, MODULE)
            end
        end
        return total
    end
    local specific = distribution.Specific or {}
    if #specific == 0 then
        return setModules(distribution.Normal)
    end
    local specificTotal = 0
    for _, set in ipairs(specific) do
        specificTotal = specificTotal + setModules(set)
    end
    return (1 - SPECIAL_LOOT_CHANCE) * setModules(distribution.Normal) + SPECIAL_LOOT_CHANCE * specificTotal / #specific
end

--- Vehicles that come with a zone's stalls, by script, each { share, perStall }: the chance a
--- stall holds one. As IsoChunk.AddVehicles_OnZone and VehicleType.getRandomVehicleType roll
--- them, leaving out the special vehicles a few stalls of an ordinary zone turn into.
local function zoneVehicles(zoneName)
    local zone = VehicleZoneDistribution[zoneName]
    if not zone or not zone.vehicles then
        return {}
    end
    local spawn = math.min(1, ((zone.spawnRate or 16) + 1) / 100) * (1 - (zone.chanceToSpawnBurnt or 0) / 100)
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
    local normal = zone.specialCar and (zone.chanceToSpawnNormal or 80) / 100 or 0
    addFrom(zone.vehicles, spawn * (1 - normal))
    if normal > 0 then
        addFrom(VehicleZoneDistribution.parkingstall.vehicles, spawn * normal)
    end
    return result
end

local function vehiclesHaul(stalls, kinds)
    local Distributions = RenewableEnergy.Distributions
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
                cache[script] = cache[script] or vehicleModules(script)
                addHaul(total, kinds.intact, vehicles * cache[script])
                if zoneName == "junkyard" then
                    addHaul(total, kinds.cracked, vehicles * Distributions.crackedModuleChance(Distributions.CRACKED_MODULE_JUNKYARD))
                end
            end
        end
    end
    return total, arrowBoards
end

local function siteSpot(site)
    local spot = (site.panels and site.panels[1]) or site.bank or site.arrowBoard
    return spot[1], spot[2]
end

--- Expected modules of a site once placed.
local function siteHaul(site, kinds)
    local SolarSites, WorldSpawns = RenewableEnergy.SolarSites, RenewableEnergy.WorldSpawns
    local kind = SolarSites.KINDS[site.kind]
    local total = emptyHaul()
    if kind.panels then
        local panels = (kind.panels.min + math.min(kind.panels.max, #site.panels)) / 2
        local perPanel = 0
        for _, panel in ipairs(site.panels) do
            local mount = RenewableEnergy.Sprites.kindOf(SolarSites.mountSprite(panel[4], panel[5]))
            perPanel = perPanel + (kind.modules and (kind.modules.min + kind.modules.max) / 2 or RenewableEnergy.Specs.mounts[mount].modules)
        end
        addHaul(total, kinds.site, panels * perPanel / #site.panels)
    end
    for _, line in ipairs(kind.crate and WorldSpawns.CRATE_STOCK[kind.crate] or {}) do
        if line[1] == MODULE then
            addHaul(total, kinds.site, (line[2] + line[3]) / 2 * SandboxVars.RenewableEnergy[line[4]])
        end
    end
    if site.arrowBoard then
        addHaul(total, arrowBoardHaul(kinds))
    end
    return total
end

local function inTown(town, x, y)
    return x >= town.x1 and x <= town.x2 and y >= town.y1 and y <= town.y2
end

--- The module report: for each town of the census, { name, listed, cracked, crates, vehicles,
--- sites, total } hauls ({ count, condition, repaired }, condition summed over the modules);
--- `sites`, each { name, kind, haul } at its Solar Sites chance; `arrowBoards`, the expected
--- number on the map, { zones, roadWorks }. At the default loot settings and loot rarity
--- options 1.
function RenewableEnergyLoot.moduleReport(census)
    return RenewableEnergyLoot.withMeasureOptions(function()
        local saved = {}
        for _, option in ipairs(LRM_OPTIONS) do
            saved[option] = SandboxVars.RenewableEnergy[option]
            SandboxVars.RenewableEnergy[option] = 1
        end
        RenewableEnergy.Distributions.apply()
        local kinds = moduleKinds()
        local siteChance = SandboxVars.RenewableEnergy.SolarSites / 100
        local report = { towns = {}, sites = {} }
        for _, site in ipairs(RenewableEnergy.SolarSites.sites()) do
            table.insert(report.sites, { name = site.name, kind = site.kind, haul = siteHaul(site, kinds), site = site })
        end
        for _, town in ipairs(census.towns) do
            local row = roomsHaul(town, kinds)
            row.name = town.name
            row.vehicles = vehiclesHaul(town.vehicleStalls, kinds)
            row.sites = emptyHaul()
            for _, entry in ipairs(report.sites) do
                if inTown(town, siteSpot(entry.site)) then
                    addHaul(row.sites, entry.haul, siteChance)
                end
            end
            row.total = emptyHaul()
            for _, part in ipairs({ row.listed, row.cracked, row.crates, row.vehicles, row.sites }) do
                addHaul(row.total, part)
            end
            table.insert(report.towns, row)
        end
        local _, zoneBoards = vehiclesHaul(census.mapVehicleStalls, kinds)
        local roadWorks = 0
        for _, entry in ipairs(report.sites) do
            if entry.site.arrowBoard then
                roadWorks = roadWorks + siteChance
            end
        end
        report.arrowBoards = { zones = zoneBoards, roadWorks = roadWorks }
        report.siteChance = siteChance
        for option, value in pairs(saved) do
            SandboxVars.RenewableEnergy[option] = value
        end
        RenewableEnergy.Distributions.apply()
        return report
    end)
end
