require "Items/Distributions"
require "Items/ProceduralDistributions"
require "Vehicles/VehicleDistributions"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Chance"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/StashHouses"
require "RenewableEnergy/World/WorldSpawns"
require "RenewableEnergy/World/ArrowBoard"
require "RenewableEnergy/World/ArrowBoardPower"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"

-- Where the mod's items spawn, 1993 style. apply() puts Distributions.items into the game's loot
-- tables in OnInitGlobalModData, scaled by the save's loot rarity options.

RenewableEnergy = RenewableEnergy or {}
local Distributions = {}
RenewableEnergy.Distributions = Distributions

local subDist = SuburbsDistributions
local procLists = ProceduralDistributions.list
local vehDist = VehicleDistributions
local Battery, Specs = RenewableEnergy.Battery, RenewableEnergy.Specs
local Stash = RenewableEnergy.Stash
local WorldSpawns = RenewableEnergy.WorldSpawns
local ArrowBoard = RenewableEnergy.ArrowBoard
local Chance = RenewableEnergy.Chance

-- The mod's own lists

-- A crate of RV and cabin solar gear, which some storage rooms pick instead of their usual loot.
-- Its RenewableEnergy items come from Distributions.items, so the rarity options scale them. The
-- hardware ignores the zombie density bonus anyway, but the magazines don't, and a crate shouldn't
-- grow fuller because the town around it is crowded.
procLists.RenewableEnergySolarKit = {
    rolls = 4,
    ignoreZombieDensity = true,
    items = {},
    junk = {
        rolls = 1,
        items = {
            "Base.ElectricWire", 20,
            "Base.ElectronicsScrap", 20,
            "Base.MetalBar", 10,
            "Base.SmallSheetMetal", 10,
            "Base.Screws", 5,
        },
    },
}

-- Back stock of batteries in electronics stores and warehouses.
procLists.RenewableEnergyBatteryStock = {
    rolls = 4,
    ignoreZombieDensity = true,
    items = {},
}

-- Loot respawn refills any explored, looted container that isn't an IsoThumpable
-- (LootRespawn.respawnInContainer), and a bank is an IsoGenerator, so the table a room gives these
-- types is what a player's own bank, charger or crate would be refilled with. Empty tables refill
-- nothing. addOwnContainersToRooms gives every room these, since a room's own "other" table comes
-- before "all" (ItemPickerJava.fillContainer).
local OWN_CONTAINER_TYPES = {
    "RenewableEnergyBatteryBoxWood", "RenewableEnergyBatteryBoxMetal", "RenewableEnergyBatteryRackWood",
    "RenewableEnergyBatteryRackMetal", "RenewableEnergyBatteryBankWood", "RenewableEnergyBatteryBankMetal",
    "RenewableEnergyCellCharger", Stash.CRATE_TYPE,
}
for _, containerType in ipairs(OWN_CONTAINER_TYPES) do
    subDist.all[containerType] = { rolls = 0, items = {} }
end

-- The spawn table of the mod's stash houses (StashHouses.lua). StashSystem.doBuildingStash
-- refills each container of the house whose type is a key here; the house's other containers keep
-- the loot of their own rooms. The crate the stash places rolls the kit's lists, more times.
local stashCache = copyTable(subDist.electronicsstorage)
subDist[Stash.SPAWN_TABLE] = stashCache
stashCache[Stash.CRATE_TYPE] = {
    rolls = 24,
    ignoreZombieDensity = true,
    items = procLists.RenewableEnergySolarKit.items,
    junk = procLists.RenewableEnergySolarKit.junk,
}
stashCache.crate = { procedural = true, procList = {} }
stashCache.metal_shelves = { procedural = true, procList = {} }

-- Rooms that pick the kit or the battery stock. Rooms whose only vanilla entry has no weightChance
-- (it counts as 1) are left out, because any entry added there would take half the picks.
local function pick(listName, weight, max)
    return { name = listName, min = 0, max = max or 1, weightChance = weight }
end
local ROOM_PICKS = {
    { "electronicsstorage", "other", pick("RenewableEnergySolarKit", 10) },
    { "electronicsstorage", "other", pick("RenewableEnergyBatteryStock", 5) },
    { "campingstorage", "other", pick("RenewableEnergySolarKit", 10) },
    { "farmstorage", "other", pick("RenewableEnergySolarKit", 5) },
    { "toolstorestorage", "other", pick("RenewableEnergySolarKit", 10) },
    { "warehouse", "metal_shelves", pick("RenewableEnergySolarKit", 5) },
    { "warehouse", "metal_shelves", pick("RenewableEnergyBatteryStock", 5) },
    { "storageunit", "other", pick("RenewableEnergySolarKit", 3) },
    { "garagestorage", "crate", pick("RenewableEnergySolarKit", 3) },
    -- Randomized survivor safehouses switch to the _Mid and _Late tables as the world ages
    -- (RBSafehouse).
    { "SafehouseLoot", "metal_shelves", pick("RenewableEnergySolarKit", 5) },
    { "SafehouseLoot_Mid", "metal_shelves", pick("RenewableEnergySolarKit", 5) },
    { "SafehouseLoot_Late", "metal_shelves", pick("RenewableEnergySolarKit", 5) },
    { Stash.SPAWN_TABLE, "crate", pick("RenewableEnergySolarKit", 25, 3) },
    { Stash.SPAWN_TABLE, "crate", pick("RenewableEnergyBatteryStock", 10) },
    { Stash.SPAWN_TABLE, "metal_shelves", pick("RenewableEnergySolarKit", 20, 3) },
}
for _, roomPick in ipairs(ROOM_PICKS) do
    local room = subDist[roomPick[1]]
    local containerTable = room and room[roomPick[2]]
    if containerTable and containerTable.procList then
        table.insert(containerTable.procList, roomPick[3])
    else
        print("RenewableEnergy: no loot table " .. roomPick[1] .. "." .. roomPick[2] .. ", skipped")
    end
end

-- Vehicles

-- A copy of a vehicle container table, so the mod's entries go into its own table only. The junk
-- list is shared (ClutterTables) and never changed.
local function copyVehicleTable(name)
    local vanilla = vehDist[name]
    local items = {}
    for i, value in ipairs(vanilla.items) do
        items[i] = value
    end
    return { rolls = vanilla.rolls, items = items, junk = vanilla.junk }
end

-- A copy of a vehicle loot set (TruckBed, GloveBox, seats) with `truckBed` wherever it had
-- `vanillaTruckBed`.
local function vehicleLootWith(setName, vanillaTruckBed, truckBed)
    local set = {}
    for part, containerTable in pairs(vehDist[setName]) do
        if part ~= "specificId" then
            set[part] = containerTable == vanillaTruckBed and truckBed or containerTable
        end
    end
    return set
end

-- Knox Telecommunications and Deer Valley Power vans fill like any builder's van in vanilla
-- (ConstructionWorker); their own copies add battery plant and line crew stock. Camper trailers
-- get a tow-behind RV's house battery and roof panel. Built after the merge, so the copies carry
-- what other mods put into the vanilla tables.
local function addOwnVehicleTables()
    local byVehicle = vehDist[1]
    local constructionBed = vehDist.ConstructionWorkerTruckBed
    vehDist.RenewableEnergyTelecomTruckBed = copyVehicleTable("ConstructionWorkerTruckBed")
    vehDist.RenewableEnergyUtilityTruckBed = copyVehicleTable("ConstructionWorkerTruckBed")
    byVehicle.VanKnoxCom = {
        Normal = vehicleLootWith("ConstructionWorker", constructionBed, vehDist.RenewableEnergyTelecomTruckBed),
    }
    byVehicle.VanDeerValley = {
        Normal = vehicleLootWith("ConstructionWorker", constructionBed, vehDist.RenewableEnergyUtilityTruckBed),
    }

    vehDist.RenewableEnergyCamperTrailerTrunk = copyVehicleTable("CamperTruckBed")
    local camperTrailer = { TrailerTrunk = vehDist.RenewableEnergyCamperTrailerTrunk }
    for _, trailer in ipairs({ "Trailer", "TrailerCover" }) do
        table.insert(byVehicle[trailer].Specific, camperTrailer)
    end
end

--- Give every room an entry for the mod's container types, pointing at the empty ones in all.
--- Runs after the merge so rooms other mods add are covered. Bags share SuburbsDistributions with
--- the rooms; ItemPickerJava tells them apart by a rolls key, and so does this.
local function addOwnContainersToRooms()
    local all = subDist.all
    for roomName, room in pairs(subDist) do
        if roomName ~= "all" and type(room) == "table" and room.rolls == nil then
            for _, containerType in ipairs(OWN_CONTAINER_TYPES) do
                room[containerType] = room[containerType] or all[containerType]
            end
        end
    end
end

-- What spawns where

--- Each entry is { weight, list } before the loot rarity option named by `option`. A list is
--- "proc:<ProceduralDistributions list>", "proc:<list>.junk", "veh:<VehicleDistributions list>"
--- or "sub:<SuburbsDistributions path>". ItemPickerJava scales a weight by the loot rarity of the
--- item's category (junk ignores rarity). The scavenger's gear is the commonest and the
--- homestead's the rarest; modules stay a reward, mostly from kits, caches and vans.

-- Vanilla stash crates (spawnTable of most vanilla stash houses): a prepper's cache.
local SURVIVOR_CRATES = {
    "sub:SurvivorCache1.SurvivorCrate",
    "sub:SurvivorCache2.SurvivorCrate",
    "sub:SurvivorCacheBigBuilding.SurvivorCrate",
}

-- Corpse loot of every survivalist outfit, with its _Mid and _Late variants.
local SURVIVALIST_CORPSES = {}
for key in pairs(subDist.all) do
    if string.find(key, "^Outfit_Survivalist") then
        table.insert(SURVIVALIST_CORPSES, "sub:all." .. key)
    end
end
table.sort(SURVIVALIST_CORPSES)

-- Ordinary homes' shelves and side tables, where vanilla keeps its own how-to magazines
-- (ElectronicsMag*, CookingMag*), in plain, classy and redneck furnishings.
local HOME_SHELVES = { "proc:LivingRoomShelf", "proc:LivingRoomShelfClassy", "proc:LivingRoomShelfRedneck" }
local HOME_SIDE_TABLES = { "proc:LivingRoomSideTable", "proc:LivingRoomSideTableClassy", "proc:LivingRoomSideTableRedneck" }
local HOME_OTHER_SHELVES = { "proc:LivingRoomWardrobe", "proc:RecRoomShelf", "proc:ShelfGeneric" }
-- Randomized survivor safehouses' (RBSafehouse) bookshelves and hearths.
local SAFEHOUSE_READING = { "proc:SafehouseFireplace", "proc:SafehouseFireplace_Late" }

local function with(weight, lists, entries)
    for _, list in ipairs(lists) do
        table.insert(entries, { weight, list })
    end
    return entries
end

Distributions.items = {
    -- Scavenger: the first magazine, plug-in power and the solar gadgets
    {
        -- The magazine that starts the mod, so it turns up in ordinary homes too: a few in a
        -- town's worth of houses.
        fullType = "RenewableEnergy.HomesteadPowerMag1",
        option = "LRMMisc",
        entries = with(2, SURVIVOR_CRATES, with(1, SURVIVALIST_CORPSES, with(0.6, HOME_SHELVES,
            with(0.4, HOME_SIDE_TABLES, with(0.6, HOME_OTHER_SHELVES, with(0.5, SAFEHOUSE_READING, {
            { 6, "proc:ElectronicStoreMagazines" },
            { 2, "proc:ToolStoreBooks" },
            { 2, "proc:BookstoreBlueCollar" },
            { 1.5, "proc:BookstoreMisc" },
            { 1.5, "proc:BookstoreOutdoors" },
            { 1, "proc:BookstoreFarming" },
            { 2, "proc:CampingStoreBooks" },
            { 2, "proc:OutdoorSupplyMagazines" },
            { 1, "proc:CarSupplyLiterature" },
            { 1, "proc:CrateMagazines" },
            { 0.8, "proc:MagazineRackMixed" },
            { 0.8, "proc:PostOfficeMagazines" },
            { 0.8, "proc:LibraryMagazines" },
            { 0.5, "proc:RangerMagazines" },
            { 1, "proc:ElectricianTools" },
            { 0.5, "proc:EngineerTools" },
            -- Hobbyists, homesteaders and preppers read them most.
            { 1, "proc:Hobbies" },
            { 1.5, "proc:Homesteading" },
            { 2, "proc:SurvivalGear" },
            { 3, "proc:SafehouseBookShelf" },
            { 0.5, "proc:GarageMechanics" },
            { 1, "veh:CamperTruckBed" },
            { 1, "veh:RenewableEnergyCamperTrailerTrunk" },
            { 1, "veh:SurvivalistTruckBed" },
            { 1, "sub:all.Outfit_Camper" },
            { 8, "proc:RenewableEnergySolarKit.junk" },
        })))))),
    },
    {
        -- Sold in every auto parts store and truck stop for the cigarette lighter, so it rode in
        -- glove boxes and trunks and ended up in garages and junk drawers.
        fullType = "RenewableEnergy.PlugInInverter",
        option = "LRMMisc",
        entries = with(1, SURVIVOR_CRATES, {
            { 2, "proc:CarSupplyTools" },
            { 2, "proc:CarSupplyBatteries" },
            { 2, "proc:GasStoreEmergency" },
            { 2, "proc:ElectronicStoreMisc" },
            { 1, "proc:GigamartHouseElectronics" },
            { 1, "proc:MechanicShelfElectric" },
            { 1.5, "proc:GarageMechanics" },
            { 1, "proc:GarageTools" },
            { 0.3, "proc:KitchenRandom" },
            { 0.3, "proc:ClosetShelfGeneric" },
            { 0.1, "proc:OfficeDeskHome" },
            { 0.3, "proc:CampingStoreGear" },
            { 1, "proc:SafehouseLighting" },
            { 0.5, "proc:SurvivalGear" },
            { 0.3, "proc:CrateElectronics" },
            { 0.2, "proc:JunkHoard" },
            { 1, "veh:GloveBox" },
            { 0.5, "veh:TrunkStandard" },
            { 1, "veh:TrunkHeavy" },
            { 2, "veh:CamperTruckBed" },
            { 1, "veh:CamperGloveBox" },
            { 2, "veh:RenewableEnergyCamperTrailerTrunk" },
            { 0.5, "sub:all.Outfit_Trucker" },
        }),
    },
    {
        fullType = RenewableEnergy.SolarMaintainer.ITEM,
        option = "LRMMisc",
        entries = with(1, SURVIVOR_CRATES, {
            -- Kept on the batteries of RVs, boats and seasonal tractors.
            { 2, "proc:CarSupplyBatteries" },
            { 1, "proc:CarSupplyTools" },
            { 1, "proc:MechanicShelfElectric" },
            { 0.5, "proc:GasStoreEmergency" },
            { 0.5, "proc:ElectronicStoreMisc" },
            { 0.5, "proc:GarageMechanics" },
            { 1, "proc:ToolStoreFarming" },
            { 1, "proc:ToolCabinetFarming" },
            { 0.5, "proc:BarnTools" },
            { 0.5, "proc:FishingStoreGear" },
            { 0.5, "proc:SafehouseLighting" },
            { 1.5, "veh:CamperTruckBed" },
            { 1.5, "veh:RenewableEnergyCamperTrailerTrunk" },
            { 1, "veh:FishermanTruckBed" },
            { 0.8, "veh:FarmerTruckBed" },
            { 0.8, "veh:RancherTruckBed" },
        }),
    },
    {
        fullType = RenewableEnergy.SolarCellCharger.ITEM,
        option = "LRMMisc",
        entries = with(1.5, SURVIVOR_CRATES, {
            { 2, "proc:ElectronicStoreMisc" },
            { 1, "proc:GigamartHouseElectronics" },
            { 2, "proc:CampingStoreLighting" },
            { 0.5, "proc:CampingStoreGear" },
            { 0.3, "proc:CrateCamping" },
            { 2, "proc:SafehouseLighting" },
            { 2, "proc:SafehouseLighting_Late" },
            { 1, "proc:SurvivalGear" },
            { 0.5, "proc:ArmySurplusMisc" },
            { 0.1, "proc:JunkHoard" },
            { 0.5, "veh:CamperTruckBed" },
        }),
    },
    {
        -- Sold by the boxful at garden centres and hardware stores in the early 1990s, and
        -- put away in sheds and garages once their batteries died.
        fullType = RenewableEnergy.SolarGardenLight.ITEM,
        option = "LRMMisc",
        entries = {
            { 6, "proc:GardenStoreMisc" },
            { 3, "proc:GardenStoreTools" },
            { 2, "proc:ToolStoreFarming" },
            { 1, "proc:ToolStoreMisc" },
            { 1, "proc:CrateGardening" },
            { 1, "proc:GarageTools" },
            { 0.5, "proc:BarnTools" },
        },
    },
    -- RV and cabin: the second magazine, modules, deep cycle batteries and their electronics
    {
        -- Turns up wherever the first magazine does, homes included, but less often.
        fullType = "RenewableEnergy.HomesteadPowerMag2",
        option = "LRMMisc",
        entries = with(1.5, SURVIVOR_CRATES, with(0.5, SURVIVALIST_CORPSES, with(0.3, HOME_SHELVES,
            with(0.2, HOME_SIDE_TABLES, with(0.3, HOME_OTHER_SHELVES, with(0.3, SAFEHOUSE_READING, {
            { 3, "proc:ElectronicStoreMagazines" },
            { 1.5, "proc:BookstoreBlueCollar" },
            { 1, "proc:ToolStoreBooks" },
            { 2, "proc:ElectricianTools" },
            { 1, "proc:GeneratorRoom" },
            { 1, "proc:EngineerTools" },
            { 0.5, "proc:ControlRoomCounter" },
            { 0.4, "proc:CrateMagazines" },
            { 0.3, "proc:MagazineRackMixed" },
            { 0.4, "proc:LibraryMagazines" },
            { 0.5, "proc:Hobbies" },
            { 0.8, "proc:Homesteading" },
            { 1, "proc:SurvivalGear" },
            { 1.5, "proc:SafehouseBookShelf" },
            { 0.3, "proc:GarageMechanics" },
            { 3, "veh:ElectricianTruckBed" },
            { 2, "veh:RadioTruckBed" },
            { 2, "veh:RenewableEnergyTelecomTruckBed" },
            { 2, "veh:RenewableEnergyUtilityTruckBed" },
            { 4, "proc:RenewableEnergySolarKit.junk" },
        })))))),
    },
    {
        -- Biogas: on farms, where the manure is, and with preppers. Rarer, since the skills teach
        -- its recipes too.
        fullType = "RenewableEnergy.HomesteadPowerMag3",
        option = "LRMMisc",
        entries = with(1, SURVIVOR_CRATES, with(0.3, SURVIVALIST_CORPSES, with(0.3, SAFEHOUSE_READING, {
            { 3, "proc:BookstoreFarming" },
            { 2, "proc:Homesteading" },
            { 1.5, "proc:ToolStoreFarming" },
            { 1, "proc:ToolCabinetFarming" },
            { 1, "proc:BarnTools" },
            { 1, "proc:CrateFarming" },
            { 1, "proc:SafehouseBookShelf" },
            { 2, "veh:FarmerTruckBed" },
        }))),
    },
    {
        -- Wood gas: government paper, as FEMA sent it out in 1989 to post offices, police, fire
        -- and civil defense, libraries and the army surplus that sold it on; and preppers.
        fullType = "RenewableEnergy.FemaPamphlet",
        option = "LRMMisc",
        entries = with(1, SURVIVOR_CRATES, with(0.5, SURVIVALIST_CORPSES, with(0.2, SAFEHOUSE_READING, {
            { 2, "proc:PostOfficeMagazines" },
            { 1, "proc:PoliceDesk" },
            { 1, "proc:FireStorageTools" },
            { 1, "proc:LibraryGeneralReference" },
            { 2, "proc:ArmySurplusLiterature" },
            { 0.5, "proc:SafehouseBookShelf" },
            { 0.5, "proc:SurvivalGear" },
        }))),
    },
    {
        -- Wind and the treadmill: on farms, with electricians and in hobby shops; preppers. Rare,
        -- since the skills teach its recipes too.
        fullType = "RenewableEnergy.HomesteadPowerMag4",
        option = "LRMMisc",
        entries = with(1, SURVIVOR_CRATES, with(0.3, SURVIVALIST_CORPSES, with(0.3, SAFEHOUSE_READING, {
            { 2, "proc:BookstoreFarming" },
            { 1.5, "proc:Homesteading" },
            { 1, "proc:ToolStoreFarming" },
            { 1, "proc:BarnTools" },
            { 1, "proc:ElectricianTools" },
            { 1, "proc:Hobbies" },
            { 0.5, "proc:SafehouseBookShelf" },
            { 1.5, "veh:FarmerTruckBed" },
            { 1, "veh:ElectricianTruckBed" },
        }))),
    },
    {
        fullType = Specs.factoryModule,
        option = "LRMSolarPanels",
        entries = with(2, SURVIVOR_CRATES, {
            -- RV roofs, installers' stock, preppers, telecom repeaters and arrow boards.
            { 1, "veh:CamperTruckBed" },
            { 2, "veh:RenewableEnergyCamperTrailerTrunk" },
            { 0.8, "veh:ElectricianTruckBed" },
            { 0.8, "proc:ElectricianTools" },
            { 0.8, "veh:SurvivalistTruckBed" },
            { 0.4, "proc:SurvivalGear" },
            { 0.4, "proc:Homesteading" },
            { 1, "veh:RenewableEnergyTelecomTruckBed" },
            { 0.8, "veh:RenewableEnergyUtilityTruckBed" },
            { 0.5, "proc:GeneratorRoom" },
            { 0.3, "proc:ControlRoomCounter" },
            { 0.3, "veh:ConstructionWorkerTruckBed" },
            { 0.3, "veh:RangerTruckBed" },
            { 0.2, "proc:ArmyStorageElectronics" },
            { 0.1, "proc:CrateElectronics" },
            { 0.1, "proc:JunkHoard" },
            { 48, "proc:RenewableEnergySolarKit" },
        }),
    },
    {
        fullType = "RenewableEnergy.PowerInverter",
        option = "LRMMisc",
        entries = with(1, SURVIVOR_CRATES, {
            { 1, "proc:CarSupplyBatteries" },
            { 0.5, "proc:CarSupplyTools" },
            { 0.5, "proc:MechanicShelfElectric" },
            { 0.5, "proc:ElectronicStoreMisc" },
            { 1, "proc:ElectricianTools" },
            { 0.3, "proc:GasStoreEmergency" },
            { 0.5, "proc:GeneratorRoom" },
            { 0.3, "proc:SurvivalGear" },
            { 1, "veh:ElectricianTruckBed" },
            { 1, "veh:CamperTruckBed" },
            { 1.5, "veh:RenewableEnergyCamperTrailerTrunk" },
            { 0.8, "veh:SurvivalistTruckBed" },
            { 0.5, "veh:RenewableEnergyUtilityTruckBed" },
            { 16, "proc:RenewableEnergySolarKit.junk" },
        }),
    },
    {
        fullType = "RenewableEnergy.ChargeController",
        option = "LRMMisc",
        entries = with(0.8, SURVIVOR_CRATES, {
            { 1, "proc:ElectricianTools" },
            { 0.5, "proc:GeneratorRoom" },
            { 0.5, "proc:ControlRoomCounter" },
            { 0.3, "proc:RadioFactoryComponents" },
            { 0.2, "proc:ArmyStorageElectronics" },
            { 0.2, "proc:SurvivalGear" },
            { 1, "veh:ElectricianTruckBed" },
            { 1.5, "veh:RenewableEnergyTelecomTruckBed" },
            { 1.5, "veh:RenewableEnergyUtilityTruckBed" },
            { 0.5, "veh:RadioTruckBed" },
            { 0.3, "veh:RangerTruckBed" },
            { 0.8, "veh:RenewableEnergyCamperTrailerTrunk" },
            { 0.3, "veh:CamperTruckBed" },
            { 16, "proc:RenewableEnergySolarKit" },
        }),
    },
    {
        fullType = "RenewableEnergy.DeepCycleBattery",
        option = "LRMBatteries",
        entries = with(0.5, SURVIVOR_CRATES, {
            -- Far rarer than car batteries there.
            { 2, "proc:CarSupplyBatteries" },
            { 1, "proc:MechanicShelfElectric" },
            { 1, "proc:CrateBatteries" },
            { 0.3, "proc:GeneratorRoom" },
            { 0.3, "proc:ToolCabinetFarming" },
            { 0.3, "proc:FishingStoreGear" },
            { 0.2, "proc:GarageMechanics" },
            -- RV house batteries and trolling motors.
            { 0.8, "veh:CamperTruckBed" },
            { 2, "veh:RenewableEnergyCamperTrailerTrunk" },
            { 0.6, "veh:FishermanTruckBed" },
            { 0.5, "veh:SurvivalistTruckBed" },
            { 36, "proc:RenewableEnergySolarKit" },
            { 36, "proc:RenewableEnergyBatteryStock" },
        }),
    },
    {
        fullType = "RenewableEnergy.SolarFailsafe",
        option = "LRMMisc",
        entries = {
            { 0.1, "proc:GeneratorRoom" },
            { 0.5, "proc:RenewableEnergySolarKit.junk" },
        },
    },
    -- Homestead: the Inverter/Charger, L-16 batteries and battery acid
    {
        fullType = "RenewableEnergy.InverterCharger",
        option = "LRMMisc",
        entries = with(0.3, SURVIVOR_CRATES, {
            { 0.3, "proc:GeneratorRoom" },
            { 0.3, "proc:ControlRoomCounter" },
            { 0.1, "proc:ArmyStorageElectronics" },
            { 0.2, "veh:ElectricianTruckBed" },
            { 0.5, "veh:RenewableEnergyTelecomTruckBed" },
            { 0.3, "veh:RenewableEnergyUtilityTruckBed" },
            { 0.2, "veh:RenewableEnergyCamperTrailerTrunk" },
            { 2, "proc:RenewableEnergySolarKit.junk" },
        }),
    },
    {
        fullType = "RenewableEnergy.L16Battery",
        option = "LRMBatteries",
        entries = with(0.2, SURVIVOR_CRATES, {
            { 0.5, "proc:CrateBatteries" },
            { 0.2, "proc:GeneratorRoom" },
            { 0.2, "proc:ControlRoomCounter" },
            { 0.1, "proc:CarSupplyBatteries" },
            { 0.5, "veh:RenewableEnergyTelecomTruckBed" },
            { 0.3, "veh:RenewableEnergyUtilityTruckBed" },
            { 6, "proc:RenewableEnergyBatteryStock" },
        }),
    },
    {
        -- Battery acid by the litre, for refilling rebuilt batteries: auto parts stores and
        -- mechanics sold it for topping up, and battery plants stocked it by the crate.
        fullType = "RenewableEnergy.BatteryElectrolyte",
        option = "LRMBatteries",
        entries = {
            { 3, "proc:CarSupplyBatteries" },
            { 1, "proc:CarSupplyTools" },
            { 2, "proc:MechanicShelfElectric" },
            { 0.5, "proc:GarageMechanics" },
            { 4, "proc:CrateBatteries" },
        },
    },
}

-- Applying

-- The items-list holder each prefix of a list reference names, by the name after the prefix.
local LIST_HOLDERS = {
    -- A ProceduralDistributions list, or "<list>.junk" for its junk.
    proc = function(name)
        local listName = string.match(name, "^([^.]+)%.junk$")
        if listName then
            return procLists[listName] and procLists[listName].junk
        end
        return procLists[name]
    end,
    veh = function(name)
        return vehDist[name]
    end,
    -- A dotted path into SuburbsDistributions.
    sub = function(name)
        local holder = subDist
        for part in string.gmatch(name, "[^.]+") do
            holder = type(holder) == "table" and holder[part] or nil
        end
        return holder
    end,
}

--- The loot table a "proc:", "veh:" or "sub:" name refers to, the one whose `items` the name's
--- entries go into ("proc:<list>.junk": the list's junk table), or nil if the game has no such
--- table.
---@param reference string
---@return table?
function Distributions.resolveTable(reference)
    local prefix, name = string.match(reference, "^(%a+):(.+)$")
    local holderOf = LIST_HOLDERS[prefix]
    local holder = holderOf and holderOf(name)
    return type(holder) == "table" and holder or nil
end

--- The items list a "proc:", "veh:" or "sub:" name refers to, or nil if the game has no such
--- list.
---@param reference string
---@return table?
function Distributions.resolveItemList(reference)
    local holder = Distributions.resolveTable(reference)
    return holder and holder.items or nil
end

-- Items lists are flat name, weight pairs.
local function removeItem(items, fullType)
    for i = #items - 1, 1, -2 do
        if items[i] == fullType then
            table.remove(items, i + 1)
            table.remove(items, i)
        end
    end
end

-- Puts each stash's map item into the loot lists its description names, if the Stash Houses
-- option drops maps.
local function applyStashMaps()
    local inLoot = Stash.mapsInLoot()
    for description, extra in pairs(Stash.descriptions) do
        for _, entry in ipairs(extra.loot or {}) do
            local items = Distributions.resolveItemList(entry[2])
            if items then
                removeItem(items, description.item)
                if inLoot then
                    table.insert(items, description.item)
                    table.insert(items, entry[1])
                end
            else
                print("RenewableEnergy: no loot list " .. entry[2] .. " for " .. description.item .. ", skipped")
            end
        end
    end
end

--- Puts every entry of Distributions.items into its list, weighted by the save's sandbox options,
--- and the stash maps into their lists, replacing the entries an earlier call made. An option at
--- 0 leaves its items out altogether: a zero weight would still spawn through the zombie density
--- bonus, which ItemPickerJava adds rather than multiplies. ItemPickerJava reads the Lua tables
--- only when it parses them, so ItemPickerJava.Parse() has to run afterwards.
function Distributions.apply()
    for _, spec in ipairs(Distributions.items) do
        local multiplier = SandboxVars.RenewableEnergy[spec.option]
        for _, entry in ipairs(spec.entries) do
            local items = Distributions.resolveItemList(entry[2])
            if items then
                removeItem(items, spec.fullType)
                if multiplier > 0 then
                    table.insert(items, spec.fullType)
                    table.insert(items, entry[1] * multiplier)
                end
            else
                print("RenewableEnergy: no loot list " .. entry[2] .. " for " .. spec.fullType .. ", skipped")
            end
        end
    end
    applyStashMaps()
end

-- Found batteries

--- Gives the mod's batteries in a freshly filled container, bags included, a part charge. A
--- battery that already has a charge of its own is one a refill (loot respawn) found there.
---@param container ItemContainer
function Distributions.chargeFoundBatteries(container)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:IsInventoryContainer() then
            Distributions.chargeFoundBatteries(item:getInventory())
        elseif item:getModule() == "RenewableEnergy" and Battery.isBattery(item) and not Battery.hasCharge(item) then
            Battery.setFoundCharge(item)
        end
    end
end

-- Cracked modules
-- Modules whose glass broke lie around where people kept junk and spares. They are added when a
-- container is filled rather than through the loot lists, so that they come with their cracked
-- condition and the lists' modules stay whole. Weights scale like a loot list's.

-- Rooms, and the weight of each of their shelves, boxes, crates and cabinets.
Distributions.CRACKED_MODULE_ROOMS = {
    garage = 1.5,
    garagestorage = 1.5,
    shed = 1.5,
    farmstorage = 3,
    electronicsstorage = 3,
}
Distributions.CRACKED_MODULE_CONTAINERS = {
    crate = true, smallcrate = true, cardboardbox = true, smallbox = true, metal_shelves = true,
    shelves = true, toolcabinet = true, counter = true,
}
-- Weight for each trunk and truck bed of a vehicle in a junkyard (vanilla vehicle zone
-- "junkyard"): someone pulled the panel off an RV.
Distributions.CRACKED_MODULE_JUNKYARD = 3

local function crackedModuleWeight(roomName, containerType, container)
    local vehicle = container:getVehicle()
    if vehicle then
        local part = container:getVehiclePart()
        local partId = part and part:getId() or ""
        local isCargo = string.find(partId, "Trunk") or string.find(partId, "TruckBed")
        return (vehicle:getZone() == "junkyard" and isCargo) and Distributions.CRACKED_MODULE_JUNKYARD or 0
    end
    if Distributions.CRACKED_MODULE_CONTAINERS[containerType] then
        return Distributions.CRACKED_MODULE_ROOMS[roomName] or 0
    end
    return 0
end

--- The chance that a container of this weight gets a cracked module, at the save's options.
function Distributions.crackedModuleChance(weight)
    local multiplier = ItemPickerJava.getLootModifier(Specs.factoryModule)
    return weight * multiplier * SandboxVars.RenewableEnergy.LRMSolarPanels / 100
end

--- Maybe adds a cracked module to a freshly filled container, if its room or vehicle keeps them.
function Distributions.addCrackedModules(roomName, containerType, container)
    local weight = crackedModuleWeight(roomName, containerType, container)
    if weight > 0 and Chance.hit(Distributions.crackedModuleChance(weight)) then
        WorldSpawns.addModule(container, WorldSpawns.crackedCondition())
    end
end

-- Rooms, vehicles and corpses fire this after rolling their loot; vanilla's own drainable
-- randomizing (ItemPickerJava.rollItem) runs before it. ItemPickerJava's bag fills pass the bag's
-- loot table in place of a container. Stash and safehouse fills (fillContainerType) don't fire
-- it. The arrow board's battery box is stocked here, so that its batteries get their charge with
-- the rest.
local function onFillContainer(roomName, containerType, container)
    if instanceof(container, "ItemContainer") then
        Distributions.addCrackedModules(roomName, containerType, container)
        ArrowBoard.stockIfBatteryBox(roomName, container)
        Distributions.chargeFoundBatteries(container)
    end
end

-- The sandbox options of the save aren't loaded yet when this file runs, nor during the
-- distribution merge events: IsoWorld.init fires those, then loads the options, then parses the
-- tables, and only then fires OnInitGlobalModData. A multiplayer client fills no containers.
local function onInitGlobalModData()
    if isClient() then
        return
    end
    Distributions.apply()
    ItemPickerJava.Parse()
end

Events.OnPostDistributionMerge.Add(addOwnVehicleTables)
Events.OnPostDistributionMerge.Add(addOwnContainersToRooms)
Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.OnFillContainer.Add(onFillContainer)

return Distributions
