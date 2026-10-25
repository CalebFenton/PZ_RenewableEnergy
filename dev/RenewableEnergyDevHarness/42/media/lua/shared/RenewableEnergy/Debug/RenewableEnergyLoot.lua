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
require "PZHarness/Loot"
local Stash = require "RenewableEnergy/Stash"

RenewableEnergy = RenewableEnergy or {}
local Loot = {}
RenewableEnergy.Loot = Loot
local PZLoot = PZHarness.Loot

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
    return PZLoot.withMeasureOptions(Loot.MEASURE_OPTIONS, function()
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
                    items = fill and PZLoot.sample(fill, samples, container, everything and PZLoot.countItems or countModItems) or {},
                    expected = expected,
                })
            end
            local container = Loot.newContainer(nil)
            for i, target in ipairs(targets) do
                local list = parsed["t" .. i]
                add(labelFor(target.reference), target.reference, list and PZLoot.rollFill(list), container, target.items)
            end
            local square = PZLoot.squareOutsideRooms(getPlayer())
            local roomContainer = Loot.newContainer(square)
            for i, spec in ipairs(ROOM_CONTAINERS) do
                local list = square and parsed["r" .. i]
                add(spec.label, spec.room .. "." .. spec.container, list and PZLoot.rollFill(list), roomContainer, {})
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
