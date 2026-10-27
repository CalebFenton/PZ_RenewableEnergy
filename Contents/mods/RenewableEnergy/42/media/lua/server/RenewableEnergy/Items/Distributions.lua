-- Where the mod's items spawn, 1993 style. Distributions.items go into the game's loot tables once
-- the save's options are loaded (cf_commonlib's Loot), scaled by its loot rarity options.

require "Items/Distributions"
require "Items/ProceduralDistributions"
require "Vehicles/VehicleDistributions"
local Stash = require "RenewableEnergy/Stash"
local Loot = require "cf_commonlib/Loot"

local Distributions = {}

local subDist = SuburbsDistributions
local procLists = ProceduralDistributions.list
local vehDist = VehicleDistributions

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
Distributions.OWN_CONTAINER_TYPES = {
    "RenewableEnergyBatteryBoxWood", "RenewableEnergyBatteryBoxMetal", "RenewableEnergyBatteryRackWood",
    "RenewableEnergyBatteryRackMetal", "RenewableEnergyBatteryBankWood", "RenewableEnergyBatteryBankMetal",
    "RenewableEnergyCellCharger", Stash.CRATE_TYPE,
}
for _, containerType in ipairs(Distributions.OWN_CONTAINER_TYPES) do
    subDist.all[containerType] = { rolls = 0, items = {} }
end

-- The spawn table of the mod's stash houses (Stash.lua). StashSystem.doBuildingStash
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
        print("RenewableEnergy: missing loot table " .. roomPick[1] .. "." .. roomPick[2] .. ", skipped")
    end
end

-- Vehicles

-- A copy of a vehicle container table, so the mod's entries go into its own table only. The junk
-- list is shared (ClutterTables) and never changed.
local function copyVehicleTable(name)
    local vanilla = vehDist[name]
    return { rolls = vanilla.rolls, items = copyTable(vanilla.items), junk = vanilla.junk }
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
            for _, containerType in ipairs(Distributions.OWN_CONTAINER_TYPES) do
                room[containerType] = room[containerType] or all[containerType]
            end
        end
    end
end

Distributions.items = require "RenewableEnergy/Items/LootEntries"

-- Applying

--- Puts every entry of Distributions.items into their lists again at the save's options now,
--- replacing the entries a load put there (Loot.register). A row's multiplier: a stash map's is
--- all or nothing, by whether the Stash Houses option drops maps; every other row's its loot
--- rarity option.
Distributions.apply = Loot.register("RenewableEnergy", Distributions.items, function(spec)
    if spec.stashMap then
        return Stash.mapsInLoot() and 1 or 0
    end
    return SandboxVars.RenewableEnergy[spec.option]
end)

Events.OnPostDistributionMerge.Add(addOwnVehicleTables)
Events.OnPostDistributionMerge.Add(addOwnContainersToRooms)

return Distributions
