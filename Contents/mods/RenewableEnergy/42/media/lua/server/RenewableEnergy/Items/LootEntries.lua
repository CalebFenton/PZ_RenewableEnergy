-- What spawns where: the entries Distributions.apply puts into the game's loot tables.

require "Items/Distributions"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Gadgets/CarAlternator"

local subDist = SuburbsDistributions
local Specs = RenewableEnergy.Specs

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

local weighted = RenewableEnergy.weightedEntries

local items = {
    -- Scavenger: the first magazine, plug-in power and the solar gadgets
    {
        -- The magazine that starts the mod, so it turns up in ordinary homes too: a few in a
        -- town's worth of houses.
        fullType = "RenewableEnergy.HomesteadPowerMag1",
        option = "LRMMisc",
        entries = weighted({
            { 0.5, SAFEHOUSE_READING }, { 0.6, HOME_OTHER_SHELVES }, { 0.4, HOME_SIDE_TABLES },
            { 0.6, HOME_SHELVES }, { 1, SURVIVALIST_CORPSES }, { 2, SURVIVOR_CRATES },
        }, {
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
        }),
    },
    {
        -- Sold in every auto parts store and truck stop for the cigarette lighter, so it rode in
        -- glove boxes and trunks and ended up in garages and junk drawers.
        fullType = "RenewableEnergy.PlugInInverter",
        option = "LRMMisc",
        entries = weighted({ { 1, SURVIVOR_CRATES } }, {
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
        entries = weighted({ { 1, SURVIVOR_CRATES } }, {
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
        entries = weighted({ { 1.5, SURVIVOR_CRATES } }, {
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
        entries = weighted({
            { 0.3, SAFEHOUSE_READING }, { 0.3, HOME_OTHER_SHELVES }, { 0.2, HOME_SIDE_TABLES },
            { 0.3, HOME_SHELVES }, { 0.5, SURVIVALIST_CORPSES }, { 1.5, SURVIVOR_CRATES },
        }, {
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
        }),
    },
    {
        -- Biogas: about half as common as #2, on farms, where the manure is, and on the farming
        -- shelves of hardware stores and bookstores; in homes too, less often, and with preppers.
        -- Barns have almost no loot containers, so RuralFinds leaves this one in barns.
        fullType = "RenewableEnergy.HomesteadPowerMag3",
        option = "LRMMisc",
        entries = weighted({
            { 0.3, SAFEHOUSE_READING }, { 0.1, HOME_OTHER_SHELVES }, { 0.07, HOME_SIDE_TABLES },
            { 0.1, HOME_SHELVES }, { 0.3, SURVIVALIST_CORPSES }, { 1, SURVIVOR_CRATES },
        }, {
            { 4, "proc:BookstoreFarming" },
            { 1, "proc:BookstoreBlueCollar" },
            { 3, "proc:ToolStoreBooks" },
            { 6, "proc:ToolStoreFarming" },
            { 1, "proc:GardenStoreMisc" },
            { 3, "proc:Homesteading" },
            { 3, "proc:ToolCabinetFarming" },
            { 3, "proc:BarnTools" },
            { 3, "proc:CrateFarming" },
            { 0.3, "proc:CrateMagazines" },
            { 0.3, "proc:MagazineRackMixed" },
            { 0.3, "proc:LibraryMagazines" },
            { 1, "proc:SafehouseBookShelf" },
            { 3, "veh:FarmerTruckBed" },
        }),
    },
    {
        -- Wood gas: government paper, as FEMA sent it out in 1989 to post offices, police, fire
        -- and civil defense, libraries and the army surplus that sold it on, and the free
        -- literature racks of hardware stores and newsstands; kept on a shelf at home now and then,
        -- and by preppers.
        fullType = "RenewableEnergy.FemaPamphlet",
        option = "LRMMisc",
        entries = weighted({
            { 0.05, HOME_SHELVES }, { 0.15, HOME_OTHER_SHELVES }, { 0.2, SAFEHOUSE_READING },
            { 0.5, SURVIVALIST_CORPSES }, { 1, SURVIVOR_CRATES },
        }, {
            { 6, "proc:PostOfficeMagazines" },
            { 3, "proc:PoliceDesk" },
            { 3, "proc:FireStorageTools" },
            { 3, "proc:LibraryGeneralReference" },
            { 1, "proc:LibraryMagazines" },
            { 4, "proc:ArmySurplusLiterature" },
            { 1, "proc:ToolStoreBooks" },
            { 1, "proc:BookstoreMisc" },
            { 0.5, "proc:MagazineRackMixed" },
            { 0.5, "proc:CrateMagazines" },
            { 0.5, "proc:SafehouseBookShelf" },
            { 0.5, "proc:SurvivalGear" },
        }),
    },
    {
        -- Wind and the treadmill: about two thirds as common as #2, on farms, with electricians, in
        -- hobby shops and on the magazine racks of hardware and electronics stores; in homes, less
        -- often, and with preppers.
        fullType = "RenewableEnergy.HomesteadPowerMag4",
        option = "LRMMisc",
        entries = weighted({
            { 0.3, SAFEHOUSE_READING }, { 0.2, HOME_OTHER_SHELVES }, { 0.13, HOME_SIDE_TABLES },
            { 0.2, HOME_SHELVES }, { 0.3, SURVIVALIST_CORPSES }, { 1, SURVIVOR_CRATES },
        }, {
            { 2, "proc:ElectronicStoreMagazines" },
            { 3, "proc:BookstoreFarming" },
            { 1, "proc:BookstoreBlueCollar" },
            { 1.5, "proc:ToolStoreBooks" },
            { 2, "proc:ToolStoreFarming" },
            { 2, "proc:Homesteading" },
            { 2, "proc:BarnTools" },
            { 1.5, "proc:ElectricianTools" },
            { 1, "proc:Hobbies" },
            { 0.3, "proc:CrateMagazines" },
            { 0.2, "proc:MagazineRackMixed" },
            { 0.3, "proc:LibraryMagazines" },
            { 0.5, "proc:SafehouseBookShelf" },
            { 2, "veh:FarmerTruckBed" },
            { 1, "veh:ElectricianTruckBed" },
        }),
    },
    {
        fullType = Specs.factoryModule,
        option = "LRMSolarPanels",
        entries = weighted({ { 2, SURVIVOR_CRATES } }, {
            -- RV roofs, installers' stock, preppers, telecom repeaters and arrow boards. Twice what
            -- the batteries' lists give, against the banks and car batteries a player finds besides.
            { 2, "veh:CamperTruckBed" },
            { 4, "veh:RenewableEnergyCamperTrailerTrunk" },
            { 1.6, "veh:ElectricianTruckBed" },
            { 1.6, "proc:ElectricianTools" },
            { 1.6, "veh:SurvivalistTruckBed" },
            { 0.8, "proc:SurvivalGear" },
            { 0.8, "proc:Homesteading" },
            { 2, "veh:RenewableEnergyTelecomTruckBed" },
            { 1.6, "veh:RenewableEnergyUtilityTruckBed" },
            { 1, "proc:GeneratorRoom" },
            { 0.6, "proc:ControlRoomCounter" },
            { 0.6, "veh:ConstructionWorkerTruckBed" },
            { 0.6, "veh:RangerTruckBed" },
            { 0.4, "proc:ArmyStorageElectronics" },
            { 0.2, "proc:CrateElectronics" },
            { 0.2, "proc:JunkHoard" },
            { 48, "proc:RenewableEnergySolarKit" },
        }),
    },
    {
        fullType = "RenewableEnergy.PowerInverter",
        option = "LRMMisc",
        entries = weighted({ { 1, SURVIVOR_CRATES } }, {
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
        entries = weighted({ { 0.8, SURVIVOR_CRATES } }, {
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
        entries = weighted({ { 0.5, SURVIVOR_CRATES } }, {
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
        entries = weighted({ { 0.3, SURVIVOR_CRATES } }, {
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
        entries = weighted({ { 0.2, SURVIVOR_CRATES } }, {
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
    {
        -- Wind: rebuilt alternators on the shelves of mechanics and auto parts stores, less often
        -- than the engine parts, brakes and batteries vanilla stocks there, which wear out sooner.
        fullType = RenewableEnergy.CarAlternator.ITEM,
        option = "LRMMisc",
        entries = {
            { 3, "proc:MechanicShelfElectric" },
            { 2, "proc:CarSupplyBatteries" },
            { 3, "proc:CrateMechanics" },
            { 1, "proc:MechanicShelfBrakes" },
            { 1, "proc:MechanicShelfMufflers" },
            { 1, "proc:MechanicShelfSuspension" },
            { 1, "proc:MechanicSpecial" },
            { 0.5, "proc:GarageMechanics" },
        },
    },
}

return items
