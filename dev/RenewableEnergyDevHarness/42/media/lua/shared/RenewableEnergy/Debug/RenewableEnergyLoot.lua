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
require "PZHarness/Fixtures"
local Stash = require "RenewableEnergy/Stash"

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
    ["proc:CrateMechanics"] = "Mechanic parts crates",
    ["proc:MechanicShelfBrakes"] = "Mechanics' brake shelves",
    ["proc:MechanicShelfMufflers"] = "Mechanics' muffler shelves",
    ["proc:MechanicShelfSuspension"] = "Mechanics' suspension shelves",
    ["proc:MechanicSpecial"] = "Mechanics' special parts",
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

--- Runs fn() with the mod's loot rarity options at `lrm` and the mod's loot applied for them, then
--- restores the options and applies the loot again. ItemPickerJava.Parse is left to the caller.
function Loot.withLootRarity(lrm, fn)
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
        return Loot.withLootRarity(lrm, function()
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
        RenewableEnergy.Distributions.readyFoundItems(container)
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
