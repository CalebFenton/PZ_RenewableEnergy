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

-- How WorldSpawns stocks the objects it places, each into a scratch container.
local function worldStock()
    local WorldSpawns = RenewableEnergy.WorldSpawns
    return {
        {
            label = "World battery boxes (sheds, garages, storage units)",
            reference = "world:batteryBox",
            fill = function(container) WorldSpawns.stockBank(container, "batteryBox") end,
        },
        {
            label = "World battery racks (farm and electronics storage)",
            reference = "world:batteryBank",
            fill = function(container) WorldSpawns.stockBank(container, "batteryBank") end,
        },
        { label = "World solar crates", reference = "world:crate", fill = WorldSpawns.stockCrate },
    }
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
