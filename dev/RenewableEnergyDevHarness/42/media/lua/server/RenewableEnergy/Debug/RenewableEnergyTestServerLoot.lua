-- The authority's half of the loot tests: the server's loot tables alone hold the mod's entries.
-- Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerChecks"
require "PZHarness/Fixtures"
require "PZHarness/Loot"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Stash"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local check, saveOptions, countPairs = PZHarness.checkHandler, PZHarness.Fixtures.saveOptions, PZHarness.Fixtures.countPairs
local squareAt, removePlaced = PZHarness.Fixtures.squareAt, PZHarness.Fixtures.removePlaced
local Sprites = RenewableEnergy.Sprites

-- The VehicleDistributions tables some vehicle's Normal or Specific distribution fills from.
local function vehicleTablesInUse()
    local used = {}
    local function addSet(set)
        for _, containerTable in pairs(set or {}) do
            if type(containerTable) == "table" then
                used[containerTable] = true
            end
        end
    end
    for _, vehicle in pairs(VehicleDistributions[1]) do
        addSet(vehicle.Normal)
        for _, specific in ipairs(vehicle.Specific or {}) do
            addSet(specific)
        end
    end
    return used
end

-- The spawn tables of every stash house, vanilla's and the mod's, registered or not.
local function stashSpawnTables()
    local tables = {}
    for description in pairs(RenewableEnergy.Stash.descriptions) do
        tables[description.spawnTable] = true
    end
    for _, description in ipairs(StashDescriptions or {}) do
        if description.spawnTable then
            tables[description.spawnTable] = true
        end
    end
    return tables
end

local function checkSubList(expect, where, name, stashTables)
    local room, container = string.match(name, "^([^.]+)%.(.+)$")
    local containerTable = room and SuburbsDistributions[room] and SuburbsDistributions[room][container]
    if not expect(containerTable ~= nil and not containerTable.procedural, where .. ": not a plain container table") then
        return
    end
    -- Corpses roll SuburbsDistributions.all.Outfit_<outfit> (ItemPickerJava.fillContainer).
    expect(stashTables[room] or (room == "all" and string.find(container, "^Outfit_") ~= nil),
        where .. ": neither a stash house nor a corpse rolls it")
    expect(ItemPickerJava.getItemContainer(room, container, nil, false) ~= nil, where .. ": the game has no " .. name)
end

-- ItemPickerJava.tryAddItemToContainer hands out nothing for an unknown item or one heavier than
-- the container holds, and getActualSpawnChance nothing at a loot multiplier of 0. An obsolete,
-- disabled or debug-only script never loads (ScriptBucket), so it is no item either. The loot
-- multipliers are the default settings', as RenewableEnergy.Loot.MEASURE_OPTIONS sets them.
local function checkHandedOut(expect, spec, capacity)
    local option = getSandboxOptions():getOptionByName("RenewableEnergy." .. spec.option)
    if expect(option ~= nil, spec.fullType .. ": no sandbox option " .. tostring(spec.option)) then
        local multiplier = option:getDefaultValue()
        for _, entry in ipairs(spec.entries) do
            expect(entry[1] * multiplier > 0, spec.fullType .. " in " .. entry[2] .. " has no weight at the default options")
        end
    end
    local script = getScriptManager():FindItem(spec.fullType)
    if expect(script ~= nil, spec.fullType .. " is no item") then
        expect(ItemPickerJava.getLootModifier(spec.fullType) > 0,
            spec.fullType .. "'s loot category is off at the default loot settings")
        local weight = script:getActualWeight() * script:getCount()
        expect(weight <= capacity, spec.fullType .. " weighs " .. weight .. ", more than a crate's " .. capacity)
    end
end

check("lootListsInUse", function(expect)
    local D = RenewableEnergy.Distributions
    local procUsers = PZHarness.Loot.procListUsers()
    local vehicleTables = vehicleTablesInUse()
    local stashTables = stashSpawnTables()
    local capacity = ItemContainer.new("crate", nil, nil):getCapacity()
    PZHarness.Loot.withMeasureOptions(RenewableEnergy.Loot.MEASURE_OPTIONS, function()
        for _, spec in ipairs(D.items) do
            checkHandedOut(expect, spec, capacity)
        end
    end)
    for _, spec in ipairs(D.items) do
        for _, entry in ipairs(spec.entries) do
            local reference = entry[2]
            local where = spec.fullType .. " in " .. reference
            local items = D.resolveItemList(reference)
            expect(items ~= nil, where .. ": no such list")
            local kind, name = string.match(reference, "^(%a+):(.+)$")
            if kind == "proc" then
                local listName = string.gsub(name, "%.junk$", "")
                local user = procUsers[listName]
                if expect(user ~= nil, where .. ": no room picks " .. listName) then
                    expect(ItemPickerJava.getItemContainer(user.room, user.container, listName, false) ~= nil,
                        where .. ": the game has no " .. user.room .. "." .. user.container .. " -> " .. listName)
                end
            elseif kind == "veh" then
                expect(VehicleDistributions[name] ~= nil and vehicleTables[VehicleDistributions[name]] == true,
                    where .. ": no vehicle fills from it")
            elseif kind == "sub" then
                checkSubList(expect, where, name, stashTables)
            else
                expect(false, where .. ": unknown kind of list")
            end
        end
    end
end)

-- Whether `list` has every vanilla item of `vanilla`; the mod's own entries differ between them.
local function listsContainAll(list, vanilla)
    for i = 1, #vanilla.items - 1, 2 do
        local fullType = vanilla.items[i]
        if not string.find(fullType, "^RenewableEnergy%.") and countPairs(list.items, fullType) == 0 then
            return false
        end
    end
    return true
end

check("lootVehicleTables", function(expect)
    local byVehicle = VehicleDistributions[1]
    local vanillaBed = VehicleDistributions.ConstructionWorkerTruckBed
    for vehicle, listName in pairs({ VanKnoxCom = "RenewableEnergyTelecomTruckBed", VanDeerValley = "RenewableEnergyUtilityTruckBed" }) do
        local list = VehicleDistributions[listName]
        local normal = byVehicle[vehicle] and byVehicle[vehicle].Normal
        if expect(list ~= nil and normal ~= nil, vehicle .. " or " .. listName .. " is missing") then
            expect(normal.TruckBed == list, vehicle .. " does not fill its truck bed from " .. listName)
            expect(normal.GloveBox == VehicleDistributions.ConstructionWorker.GloveBox, vehicle .. " lost its glove box loot")
            expect(listsContainAll(list, vanillaBed), listName .. " lacks vanilla builder's items")
        end
    end
    local trailerTrunk = VehicleDistributions.RenewableEnergyCamperTrailerTrunk
    for _, trailer in ipairs({ "Trailer", "TrailerCover" }) do
        local found = false
        for _, specific in ipairs(byVehicle[trailer].Specific) do
            found = found or specific.TrailerTrunk == trailerTrunk
        end
        expect(found, trailer .. " never rolls the camper trailer loot")
    end
    expect(trailerTrunk ~= nil and listsContainAll(trailerTrunk, VehicleDistributions.CamperTruckBed),
        "the camper trailer lacks the camper's vanilla items")
end)

-- For each row of `args.rows`, applied twice: see renewable_energy_loot_rarity_options_scale_weights.
check("lootRarityOptions", function(expect, expectNear, _, args, defer)
    local D = RenewableEnergy.Distributions
    local options, names = SandboxVars.RenewableEnergy, {}
    for option in pairs(args.rows[1]) do
        table.insert(names, option)
    end
    local restoreOptions = saveOptions(defer, names, D.apply)
    for _, row in ipairs(args.rows) do
        local label = string.format("at %s/%s/%s", row.LRMSolarPanels, row.LRMBatteries, row.LRMMisc)
        for option, value in pairs(row) do
            options[option] = value
        end
        D.apply()
        D.apply()
        local removed = {}
        for _, spec in ipairs(D.items) do
            local multiplier = row[spec.option]
            if multiplier == 0 then
                removed[spec.fullType] = true
            else
                for _, entry in ipairs(spec.entries) do
                    local where = label .. ": " .. spec.fullType .. " in " .. entry[2]
                    local items = D.resolveItemList(entry[2])
                    local count, weight = 0, nil
                    if items then
                        count, weight = countPairs(items, spec.fullType)
                    end
                    if expect(count == 1, where .. " " .. count .. " times") then
                        expectNear(where .. " weight", weight, entry[1] * multiplier)
                    end
                end
            end
        end
        PZHarness.Loot.forEachItemsList(function(items, path)
            for i = 1, #items - 1, 2 do
                if removed[items[i]] then
                    expect(false, label .. ": " .. items[i] .. " is still in " .. path)
                end
            end
        end)
    end
    restoreOptions()
end)

-- A container type that "all" rolls the mod's batteries into for certain: a weight this high is
-- past the game's 10,000 in 10,000 at any loot multiplier above a tenth.
local PROBE_CONTAINER = "RenewableEnergyTestBatteries"
local PROBE_LOOT = { rolls = 2, items = { "RenewableEnergy.DeepCycleBattery", 1000, "RenewableEnergy.L16Battery", 1000 } }

-- The items in the container, bags included, that `matches(item)` takes.
local function itemsIn(container, matches, found)
    found = found or {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:IsInventoryContainer() then
            itemsIn(item:getInventory(), matches, found)
        elseif matches(item) then
            table.insert(found, item)
        end
    end
    return found
end

-- Whether the item is one of the mod's batteries.
local function isModBattery(item)
    return string.find(item:getFullType(), "^RenewableEnergy%.") ~= nil and RenewableEnergy.Battery.isBattery(item)
end

-- Whether the item is an inverter or a controller a find wears.
local function isWornPart(item)
    return RenewableEnergy.WorldSpawns.isWornPart(item:getFullType())
end

-- A container of type `containerType` on a crate tile on the square, in the world, so that the game
-- can send its items' charges to the clients that see it. Removed when the test ends.
local function containerInWorld(square, containerType, defer)
    local crate = IsoObject.new(square, "carpentry_01_16", "RenewableEnergyTest")
    crate:setContainer(ItemContainer.new(containerType, square, crate))
    square:AddTileObject(crate)
    if isServer() then
        crate:transmitCompleteItemToClients()
    end
    defer(function() removePlaced(crate) end)
    return crate:getContainer()
end

-- Containers filled as the game fills them (ItemPickerJava.fillContainer): one outside any room
-- rolls its type's "all" table, here the probe's, and one of a corpse's type the corpse lists; a bag
-- in each holds a battery. Vehicle fills are the arrow board tests'. `args` is a free outdoor square.
check("lootFoundBatteries", function(expect, expectNear, _, args, defer)
    local square = squareAt(args)
    if not square or square:getRoom() then
        return "an outdoor square loaded on the server"
    end
    local Battery = RenewableEnergy.Battery
    local range = RenewableEnergy.Specs.foundCharge
    SuburbsDistributions.all[PROBE_CONTAINER] = PROBE_LOOT
    ItemPickerJava.Parse()
    defer(function()
        SuburbsDistributions.all[PROBE_CONTAINER] = nil
        ItemPickerJava.Parse()
    end)
    for _, fill in ipairs({ { type = PROBE_CONTAINER, what = "a room's crate", rolled = true }, { type = "inventorymale", what = "a corpse" } }) do
        local container = containerInWorld(square, fill.type, defer)
        local bag = container:AddItem("Base.Bag_DuffelBag")
        bag:getInventory():AddItem("RenewableEnergy.DeepCycleBattery")
        ItemPickerJava.fillContainer(container, nil)
        local batteries = itemsIn(container, isModBattery)
        -- The bag's battery and, from the probe table, at least one rolled.
        expect(#batteries >= (fill.rolled and 2 or 1), #batteries .. " batteries in " .. fill.what .. " after a fill")
        for _, battery in ipairs(batteries) do
            local charge = Battery.getCharge(battery)
            expect(charge >= range.min and charge <= range.max,
                battery:getFullType() .. " in " .. fill.what .. " holds " .. charge .. ", expected " .. range.min .. " to " .. range.max)
        end
        -- Emptied, as unwiring it from a drained bank or rebuilding it leaves a battery.
        local own = container:AddItem("RenewableEnergy.L16Battery")
        Battery.setCharge(own, 0)
        local stored = batteries[1]
        if stored then
            -- Charged past the found range, and not through Battery.setCharge, so only what the fill
            -- marked on it keeps a refill off it.
            stored:setCurrentUsesFloat(1)
        end
        ItemPickerJava.fillContainer(container, nil)
        if stored then
            expectNear("a stored battery's charge in " .. fill.what .. " after a refill", Battery.getCharge(stored), 1)
        end
        expectNear("an emptied battery's charge in " .. fill.what .. " after a refill", Battery.getCharge(own), 0)
    end
end)

-- With every Chance roll middling, the inverters and controllers a fill readies
-- (Distributions.readyFoundItems, which lootFoundBatteries shows a fill reaches), one in a bag
-- included, come at PART_WEAR's mean and marked. A refill leaves alone a found part that came out
-- as new and a crafted controller (its recipe's OnCreate); and a bank's container wears no part in
-- it, marked or not.
check("lootFoundParts", function(expect, _, _, _, defer)
    local WorldSpawns, Wear, D = RenewableEnergy.WorldSpawns, RenewableEnergy.Wear, RenewableEnergy.Distributions
    local mean = WorldSpawns.PART_WEAR.mean
    local restoreRoll = Helpers.forceRolls(defer, 0.5)
    local container = RenewableEnergy.Loot.newContainer(nil)
    container:AddItem("Base.Bag_DuffelBag"):getInventory():AddItem("RenewableEnergy.PowerInverter")
    container:AddItem("RenewableEnergy.PlugInInverter")
    container:AddItem(RenewableEnergy.Specs.controller)
    D.readyFoundItems(container)
    local found = itemsIn(container, isWornPart)
    expect(#found == 3, #found .. " parts in the container, not the 3 put there")
    for _, part in ipairs(found) do
        expect(part:getCondition() == mean and Wear.hasOwnCondition(part), string.format(
            "a found %s has condition %d, marked %s, not %d and marked", part:getFullType(), part:getCondition(),
            tostring(Wear.hasOwnCondition(part)), mean))
    end
    local asNew = found[1]
    if asNew then
        Wear.setCondition(asNew, asNew:getConditionMax())
    end
    local crafted = container:AddItem(RenewableEnergy.Specs.controller)
    RenewableEnergy.Recipes.makeChargeController({ getFirstCreatedItem = function() return crafted end })
    D.readyFoundItems(container)
    if asNew then
        expect(asNew:getCondition() == asNew:getConditionMax(), "a found part as good as new has condition " .. asNew:getCondition() .. " after a refill")
    end
    expect(crafted:getCondition() == crafted:getConditionMax(), "a crafted controller has condition " .. crafted:getCondition() .. " after a refill")
    local bank = ItemContainer.new("RenewableEnergyBatteryBoxWood", nil, nil)
    local installed = bank:AddItem("RenewableEnergy.PlugInInverter")
    D.readyFoundItems(bank)
    restoreRoll()
    expect(installed:getCondition() == installed:getConditionMax() and not Wear.hasOwnCondition(installed),
        "an unmarked inverter in a bank has condition " .. installed:getCondition() .. " after a fill")
end)

-- Rooms whose own "all" table vanilla rolls into every container in them
-- (ItemPickerJava.fillContainerTypeInternal), a player's too; the mod can't leave a player's
-- containers out of it without taking the room's loot away.
local VANILLA_ALL_ROOMS = { sodatruck = true }

-- Respawn calls ItemPickerJava.fillContainer(container, nil) on looted containers that aren't
-- IsoThumpables, as a bank is not. That rolls the room's "all" table, then its table for the
-- container's type, and fires OnFillContainer; outside any room, or in a room with no
-- distribution, it uses SuburbsDistributions.all. The stash spawn table fills its crate on purpose,
-- and a stash house is the only place that uses it. `args.sprites` are the Sprites fields of the
-- tiles a player builds, a bank's in every facing.
check("lootPlayerContainers", function(expect, _, _, args)
    local D = RenewableEnergy.Distributions
    local Stash = RenewableEnergy.Stash
    local own = {}
    for _, containerType in ipairs(D.OWN_CONTAINER_TYPES) do
        own[containerType] = true
        expect(not D.CRACKED_MODULE_CONTAINERS[containerType], containerType .. " gets cracked modules")
    end
    for _, field in ipairs(args.sprites) do
        local tiles = Sprites[field]
        for _, tile in pairs(type(tiles) == "table" and tiles or { tiles }) do
            local containerType = getSprite(tile):getProperties():get("container")
            expect(own[containerType], tile .. "'s container " .. tostring(containerType) .. " is not one of the mod's own")
        end
    end
    for roomName, room in pairs(SuburbsDistributions) do
        if type(room) == "table" and (room.rolls == nil or roomName == "all") then
            local all = room.all
            expect(VANILLA_ALL_ROOMS[roomName] or all == nil or (not all.procedural and #(all.items or {}) == 0),
                roomName .. "'s all table fills a player's containers")
            for _, containerType in ipairs(D.OWN_CONTAINER_TYPES) do
                local where = roomName .. "." .. containerType
                local containerTable = room[containerType]
                local stashCrate = roomName == Stash.SPAWN_TABLE and containerType == Stash.CRATE_TYPE
                if not stashCrate and expect(containerTable ~= nil, where .. " is missing, so the room's other table fills it") then
                    expect(not containerTable.procedural and #(containerTable.items or {}) == 0 and containerTable.junk == nil,
                        where .. " has loot")
                    expect(ItemPickerJava.getItemContainer(roomName, containerType, nil, false) ~= nil,
                        where .. ": the game didn't parse it")
                end
            end
        end
    end
end)
