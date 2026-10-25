-- Where the mod's items spawn, 1993 style. apply() puts Distributions.items into the game's loot
-- tables in OnInitGlobalModData, scaled by the save's loot rarity options.

require "Items/Distributions"
require "Items/ProceduralDistributions"
require "Vehicles/VehicleDistributions"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Chance"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Stash"
require "RenewableEnergy/World/WorldSpawns"
require "RenewableEnergy/World/ArrowBoard"
require "RenewableEnergy/World/ArrowBoardPower"

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
local function unlist(items, fullType)
    for i = #items - 1, 1, -2 do
        if items[i] == fullType then
            table.remove(items, i + 1)
            table.remove(items, i)
        end
    end
end

-- Puts `fullType` into the loot list of each of `entries` at the entry's weight times
-- `multiplier`, replacing the entry an earlier call made; a multiplier of 0 leaves it out.
local function placeEntries(fullType, entries, multiplier)
    for _, entry in ipairs(entries) do
        local items = Distributions.resolveItemList(entry[2])
        if items then
            unlist(items, fullType)
            if multiplier > 0 then
                table.insert(items, fullType)
                table.insert(items, entry[1] * multiplier)
            end
        else
            print("RenewableEnergy: missing loot list " .. entry[2] .. " for " .. fullType .. ", skipped")
        end
    end
end

-- Puts each stash's map item into the loot lists its description names, if the Stash Houses
-- option drops maps.
local function applyStashMaps()
    local multiplier = Stash.mapsInLoot() and 1 or 0
    for description, extra in pairs(Stash.descriptions) do
        placeEntries(description.item, extra.loot or {}, multiplier)
    end
end

--- Puts every entry of Distributions.items into its list, weighted by the save's sandbox options,
--- and the stash maps into their lists, replacing the entries an earlier call made. An option at
--- 0 leaves its items out altogether: a zero weight would still spawn through the zombie density
--- bonus, which ItemPickerJava adds rather than multiplies. ItemPickerJava reads the Lua tables
--- only when it parses them, so ItemPickerJava.Parse() has to run afterwards.
function Distributions.apply()
    for _, spec in ipairs(Distributions.items) do
        placeEntries(spec.fullType, spec.entries, SandboxVars.RenewableEnergy[spec.option])
    end
    applyStashMaps()
end

-- Found items

local OWN_CONTAINER = {}
for _, containerType in ipairs(Distributions.OWN_CONTAINER_TYPES) do
    OWN_CONTAINER[containerType] = true
end

-- An inverter or controller as loot rolls it: with no condition of its own. Its condition may be
-- anything: the game rolls a uniform one for 40% of the tools it puts outside shops
-- (ItemPickerJava.doRollItemInternal, randomizeGeneralCondition), which PART_WEAR replaces.
local function isFreshPart(item)
    return WorldSpawns.isWornPart(item:getFullType()) and not RenewableEnergy.Wear.hasOwnCondition(item)
end

local function readyItems(container, wearParts)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:IsInventoryContainer() then
            readyItems(item:getInventory(), wearParts)
        elseif item:getModule() == "RenewableEnergy" then
            if Battery.isBattery(item) and not Battery.hasCharge(item) then
                Battery.setFoundCharge(item)
            elseif wearParts and isFreshPart(item) then
                WorldSpawns.wearFoundPart(item)
            end
        end
    end
end

--- Readies the mod's items in a freshly filled container, bags included: batteries get a part
--- charge, inverters and controllers their wear (WorldSpawns.wearFoundPart). A refill (loot
--- respawn) fires this again over what players left there, so it passes over a battery that has
--- a charge of its own and a part that has a condition of its own. The mod's own containers, banks
--- among them, roll no loot, so no part in one is worn, marked or not. The game sends the filled
--- items after this (RequestItemsForContainerPacket, LootRespawn), condition included.
---@param container ItemContainer
function Distributions.readyFoundItems(container)
    readyItems(container, not OWN_CONTAINER[container:getType()])
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

--- The cracked-module weight of a container of `containerType` in a room named `roomName`; 0 if
--- it keeps none.
function Distributions.crackedModuleRoomWeight(roomName, containerType)
    return Distributions.CRACKED_MODULE_CONTAINERS[containerType] and Distributions.CRACKED_MODULE_ROOMS[roomName] or 0
end

--- The cracked-module weight of the container of the part `partId` of a vehicle in the vehicle
--- zone `zoneName`; 0 if it keeps none.
function Distributions.crackedModuleVehicleWeight(zoneName, partId)
    local isCargo = string.find(partId, "Trunk") or string.find(partId, "TruckBed")
    return (zoneName == "junkyard" and isCargo) and Distributions.CRACKED_MODULE_JUNKYARD or 0
end

local function crackedModuleWeight(roomName, containerType, container)
    local vehicle = container:getVehicle()
    if vehicle then
        local part = container:getVehiclePart()
        return Distributions.crackedModuleVehicleWeight(vehicle:getZone(), part and part:getId() or "")
    end
    return Distributions.crackedModuleRoomWeight(roomName, containerType)
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
        Distributions.readyFoundItems(container)
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
