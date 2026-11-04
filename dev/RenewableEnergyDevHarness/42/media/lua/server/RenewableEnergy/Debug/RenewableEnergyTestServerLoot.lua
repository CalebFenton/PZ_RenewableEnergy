-- The authority's half of the loot tests: the server's loot tables alone hold the mod's entries.

require "PZHarness/ServerChecks"
require "PZHarness/Fixtures"
require "PZHarness/Loot"
local Sprites = require "RenewableEnergy/Sprites"
local Stash = require "RenewableEnergy/Stash"
local Loot = require "RenewableEnergy/Debug/RenewableEnergyLoot"
local LibLoot = require "cf_commonlib/Loot"
require "PZHarness/ServerFixtures"
require "PZHarness/Rolls"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local Distributions = require "RenewableEnergy/Items/Distributions"
local Finds = require "RenewableEnergy/Items/Finds"
local ModFixtures = require "RenewableEnergy/Debug/RenewableEnergyFixtures"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Recipes = require "RenewableEnergy/Recipes"
local Specs = require "RenewableEnergy/Specs"
local Wear = require "RenewableEnergy/PowerBank/Wear"

local check, saveOptions, countPairs = PZHarness.checkHandler, PZHarness.Fixtures.saveOptions, PZHarness.Fixtures.countPairs
local removePlaced = PZHarness.Fixtures.removePlaced

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
    for _, description in ipairs(Stash.descriptions) do
        tables[description.spawnTable] = true
    end
    for _, description in ipairs(StashDescriptions or {}) do
        if description.spawnTable then
            tables[description.spawnTable] = true
        end
    end
    return tables
end

-- Corpses roll their outfit's SuburbsDistributions.all.Outfit_<outfit> and, unless that says
-- otherwise, all.inventorymale or all.inventoryfemale (ItemPickerJava.fillContainer).
local CORPSE_INVENTORIES = { inventorymale = true, inventoryfemale = true }

-- A "sub:" list is a stash house's or a corpse's container table, or a bag's table, which the game
-- rolls into a bag of that item type.
local function checkSubList(expect, where, name, stashTables)
    local room, container = string.match(name, "^([^.]+)%.(.+)$")
    if not room then
        local bag = SuburbsDistributions[name]
        expect(type(bag) == "table" and bag.rolls ~= nil and getScriptManager():FindItem(name) ~= nil,
            where .. ": no bag rolls it")
        return
    end
    local containerTable = SuburbsDistributions[room] and SuburbsDistributions[room][container]
    if not expect(containerTable ~= nil and not containerTable.procedural, where .. ": not a plain container table") then
        return
    end
    local corpse = room == "all" and (string.find(container, "^Outfit_") ~= nil or CORPSE_INVENTORIES[container])
    expect(stashTables[room] or corpse, where .. ": neither a stash house nor a corpse rolls it")
    expect(ItemPickerJava.getItemContainer(room, container, nil, false) ~= nil, where .. ": the game has no " .. name)
end

-- ItemPickerJava.tryAddItemToContainer hands out nothing for an unknown item or one heavier than
-- the container holds, and getActualSpawnChance nothing at a loot multiplier of 0. An obsolete,
-- disabled or debug-only script never loads (ScriptBucket), so it is no item either. The loot
-- multipliers are the default settings', as Loot.MEASURE_OPTIONS sets them; a stash map's
-- multiplier is the Stash Houses option's, which lootOptions checks.
local function checkHandedOut(expect, spec, capacity)
    if spec.option then
        local option = getSandboxOptions():getOptionByName("RenewableEnergy." .. spec.option)
        if expect(option ~= nil, spec.fullType .. ": no sandbox option " .. tostring(spec.option)) then
            local multiplier = option:getDefaultValue()
            for _, entry in ipairs(spec.entries) do
                expect(entry[1] * multiplier > 0, spec.fullType .. " in " .. entry[2] .. " has no weight at the default options")
            end
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

-- The utility vans fill like any builder's van, glove box and vanilla truck bed items included,
-- from truck beds of their own; trailers may roll a camper's trunk, with its vanilla items.
local function expectVehicleTables(expect)
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
end

-- The prepper's map drops from survivalist and bandit corpses whichever outfit variant they wear,
-- a variant a game update adds included.
local PREPPER_MAP = "RenewableEnergy.CrowcallRoadMap"
local PREPPER_OUTFITS = { "^Outfit_Survivalist", "^Outfit_Bandit" }

local function expectPrepperMapOnOutfits(expect)
    local lists
    for _, spec in ipairs(Distributions.items) do
        if spec.fullType == PREPPER_MAP then
            lists = {}
            for _, entry in ipairs(spec.entries) do
                lists[entry[2]] = true
            end
        end
    end
    if not expect(lists ~= nil, "no " .. PREPPER_MAP .. " in the loot") then
        return
    end
    for key in pairs(SuburbsDistributions.all) do
        for _, pattern in ipairs(PREPPER_OUTFITS) do
            if string.find(key, pattern) then
                expect(lists["sub:all." .. key], PREPPER_MAP .. " does not drop from " .. key)
            end
        end
    end
end

check("lootListsInUse", function(expect)
    local procUsers = PZHarness.Loot.procListUsers()
    local vehicleTables = vehicleTablesInUse()
    local stashTables = stashSpawnTables()
    local capacity = PZHarness.Loot.scratchContainer(nil):getCapacity()
    PZHarness.Loot.withMeasureOptions(Loot.MEASURE_OPTIONS, function()
        for _, spec in ipairs(Distributions.items) do
            checkHandedOut(expect, spec, capacity)
        end
    end)
    for _, spec in ipairs(Distributions.items) do
        for _, entry in ipairs(spec.entries) do
            local reference = entry[2]
            local where = spec.fullType .. " in " .. reference
            expect(LibLoot.resolveItemList(reference) ~= nil, where .. ": no such list")
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
    expectVehicleTables(expect)
    expectPrepperMapOnOutfits(expect)
end)

-- For each row of `args.rows` ({ options, maps }): the mod's loot options set to `options` and its
-- loot applied twice. Every row other than a stash map's is in each of its lists once, at its
-- weight × its rarity option, or nowhere at 0; a stash map's is there at its own weight when
-- `maps` says the Stash Houses option drops maps, else nowhere.
check("lootOptions", function(expect, expectNear, expectEqual, _, args, defer)
    local options, names = SandboxVars.RenewableEnergy, {}
    for option in pairs(args.rows[1].options) do
        table.insert(names, option)
    end
    local restoreOptions = saveOptions(defer, names, Distributions.apply)
    for _, row in ipairs(args.rows) do
        local labels = {}
        for option, value in pairs(row.options) do
            options[option] = value
            table.insert(labels, option .. " " .. tostring(value))
        end
        table.sort(labels)
        local label = "at " .. table.concat(labels, ", ")
        Distributions.apply()
        Distributions.apply()
        local removed = {}
        for _, spec in ipairs(Distributions.items) do
            local multiplier = spec.stashMap and (row.maps and 1 or 0) or row.options[spec.option]
            if multiplier == 0 then
                removed[spec.fullType] = true
            else
                for _, entry in ipairs(spec.entries) do
                    local where = label .. ": " .. spec.fullType .. " in " .. entry[2]
                    local items = LibLoot.resolveItemList(entry[2])
                    local count, weight = 0, nil
                    if items then
                        count, weight = countPairs(items, spec.fullType)
                    end
                    if expectEqual(where .. ", times listed", count, 1) then
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

-- The two ways the game hands a container's loot to the mod, each fired here with what the game
-- passes. A room's or corpse's fill fires OnFillContainer for the container once its loot is rolled
-- (ItemPickerJava.fillContainer). Safehouse and stash house fills (fillContainerType) fire nothing
-- and mark their containers explored, so the mod readies those when OnSeeNewRoom first shows their
-- room (IsoCell.ProcessSpottedRooms); here a room whose one square is the test's.
local HANDOVERS = {
    {
        what = "a fill",
        handOver = function(_, containers)
            for _, container in ipairs(containers) do
                triggerEvent("OnFillContainer", "all", container:getType(), container)
            end
        end,
    },
    {
        what = "its room seen",
        seesRoom = true,
        handOver = function(square)
            triggerEvent("OnSeeNewRoom", PZHarness.Fixtures.fakeRoom("bedroom", { square }))
        end,
    },
}

-- Each handover readies, once, the mod's finds in the containers it reaches, a bag's contents
-- included: a battery gets a part charge, FOUND_CHARGE spread evenly over the roll, an inverter or
-- controller PART_WEAR's wear at that roll, marked as its own. The roll is off the middle so a
-- charge range read backwards, or a wear left at the mean, shows; it is past PART_WEAR's dud
-- chance. Handed over again, as loot respawn refills a container or a room is seen again, it
-- passes over a battery or part that has a charge or condition of its own: a found one, an
-- emptied battery, a crafted controller (its recipe's OnCreate). A part in a bank, one of the
-- mod's own containers, is never worn. Seeing a room leaves an unexplored container to its own
-- fill. `args` is a free outdoor square.
check("lootFindsReadied", function(expect, expectNear, expectEqual, _, args, defer)
    local square = PZHarness.squareAt(args)
    local ROLL, range, wear = 0.2, Battery.FOUND_CHARGE, Finds.PART_WEAR
    local charge = range.min + (range.max - range.min) * ROLL
    -- Three equal rolls average to ROLL, spreading wear over mean ± halfWidth.
    local condition = math.floor(wear.mean + wear.halfWidth * (ROLL * 2 - 1) + 0.5)
    PZHarness.Rolls.force(defer, ROLL)
    for _, handover in ipairs(HANDOVERS) do
        local after = " after " .. handover.what
        local shelf = containerInWorld(square, "metal_shelves", defer)
        shelf:setExplored(true)
        local bag = shelf:AddItem("Base.Bag_DuffelBag"):getInventory()
        local batteries = { bag:AddItem("RenewableEnergy.DeepCycleBattery"), shelf:AddItem("RenewableEnergy.L16Battery") }
        local parts = { bag:AddItem("RenewableEnergy.PowerInverter"), shelf:AddItem("RenewableEnergy.PlugInInverter"),
            shelf:AddItem(Specs.controller) }
        -- Emptied, as unwiring it from a drained bank leaves a battery.
        local emptied = shelf:AddItem("RenewableEnergy.L16Battery")
        Battery.setCharge(emptied, 0)
        local crafted = shelf:AddItem(Specs.controller)
        Recipes.makeChargeController({ getFirstCreatedItem = function() return crafted end })
        local bank = containerInWorld(square, Distributions.OWN_CONTAINER_TYPES[1], defer)
        bank:setExplored(true)
        local installed = bank:AddItem("RenewableEnergy.PlugInInverter")
        local unexplored = handover.seesRoom and containerInWorld(square, "crate", defer):AddItem("RenewableEnergy.DeepCycleBattery")
        handover.handOver(square, { shelf, bank })
        for _, battery in ipairs(batteries) do
            expect(Battery.hasCharge(battery), "a found " .. battery:getFullType() .. " has no charge of its own" .. after)
            expectNear("a found " .. battery:getFullType() .. "'s charge" .. after, Battery.getCharge(battery), charge)
        end
        for _, part in ipairs(parts) do
            expect(part:getCondition() == condition and Wear.hasOwnCondition(part), string.format(
                "a found %s has condition %d, marked %s%s, not %d and marked", part:getFullType(), part:getCondition(),
                tostring(Wear.hasOwnCondition(part)), after, condition))
        end
        expectNear("an emptied battery's charge" .. after, Battery.getCharge(emptied), 0)
        expectEqual("a crafted controller's condition" .. after, crafted:getCondition(), crafted:getConditionMax())
        expect(installed:getCondition() == installed:getConditionMax() and not Wear.hasOwnCondition(installed),
            "an inverter in a bank has condition " .. installed:getCondition() .. after)
        if unexplored then
            expect(not Battery.hasCharge(unexplored), "a battery in an unexplored crate was charged" .. after)
        end
        -- Charged past the found range, and not through Battery.setCharge, so only what the first
        -- handover marked on it keeps the second off it.
        batteries[1]:setCurrentUsesFloat(1)
        Wear.setCondition(parts[1], parts[1]:getConditionMax())
        handover.handOver(square, { shelf, bank })
        expectNear("a found battery's charge after " .. handover.what .. " again", Battery.getCharge(batteries[1]), 1)
        expectEqual("the condition of a found part as good as new after " .. handover.what .. " again",
            parts[1]:getCondition(), parts[1]:getConditionMax())
        -- The next handover's room is the same square.
        local placed = { shelf, bank }
        if unexplored then
            table.insert(placed, unexplored:getContainer())
        end
        for _, container in ipairs(placed) do
            removePlaced(container:getParent())
        end
    end
end)

-- Rooms whose own "all" table vanilla rolls into every container in them
-- (ItemPickerJava.fillContainerTypeInternal), a player's too; the mod can't leave a player's
-- containers out of it without taking the room's loot away.
local VANILLA_ALL_ROOMS = { sodatruck = true }

-- How many fills the protection taken off gets to show the room's fallback loot: vanilla rolls it.
local CONTROL_FILLS = 20

-- What ItemPickerJava.fillContainer(container, nil), loot respawn's refill
-- (LootRespawn.respawnInContainer), adds to the container: its item count, bags' contents
-- included. Emptied afterwards.
local function respawnFill(container)
    container:removeAllItems()
    ItemPickerJava.fillContainer(container, nil)
    local added = 0
    for _, count in pairs(PZHarness.Loot.countItems(container)) do
        added = added + count
    end
    PZHarness.Loot.forgetItems(container)
    container:removeAllItems()
    return added
end

-- Tile `tile` on the square as a player has it: a bank as BankSystem places one, anything else
-- with its sprite's containers, as a moved-in tile gets them.
local function placeTile(square, tile)
    if PowerBank.bankOfSprite(tile) then
        return ModFixtures.placeBank(square, tile, {}, 1)
    end
    local object = IsoObject.new(square:getCell(), square, tile)
    object:createContainersFromSpriteProperties()
    square:AddTileObject(object)
    return object
end

-- Runs fn() with the tables the mod gives `containerType` in "all" and in `roomName` taken out
-- and the loot parsed so, then puts them back and parses again.
local function unprotected(containerType, roomName, fn)
    local tables = { SuburbsDistributions.all, roomName and SuburbsDistributions[roomName] }
    local saved = {}
    return PZHarness.Loot.restoring(function()
        for i, t in pairs(tables) do
            saved[i] = t[containerType]
            t[containerType] = nil
        end
        ItemPickerJava.Parse()
        return fn()
    end, function()
        for i, t in pairs(tables) do
            t[containerType] = saved[i]
        end
        ItemPickerJava.Parse()
    end)
end

-- An item of the generic fallback's list (ProceduralDistributions OtherGeneric), to tell the
-- containers that would take it: a bank takes only its parts (ItemSpawner.spawnItem, isItemAllowed).
local GENERIC_ITEM = "Base.BluePen"

-- Loot respawn refills a looted container that isn't an IsoThumpable, as a bank (an IsoGenerator)
-- and a moved tile are not, through ItemPickerJava.fillContainer: the room's table for the
-- container's type, else its "other" or "all", else SuburbsDistributions.all's; then
-- OnFillContainer. Each tile of `args.sprites` (Sprites fields, a bank's in every facing) on the
-- indoor square `args.indoor` and the outdoor one `args.outdoor` gets nothing from it, every mod
-- roll at 0 so a cracked module would come. With the mod's tables taken out for the first type
-- that takes generic loot, the same fill hands it loot, so the zero is the tables' doing. Data
-- checks cover what the two squares' rooms don't: every room's table for every type is empty
-- (the stash spawn table fills its crate on purpose, and only a stash house uses it), no room's
-- "all" fills everything, every tile's container type is the mod's own, and none gets cracked
-- modules.
check("lootPlayerContainers", function(expect, _, expectEqual, _, args, defer)
    PZHarness.Rolls.force(defer, 0)
    local generic = instanceItem(GENERIC_ITEM)
    PZHarness.Loot.withMeasureOptions(Loot.MEASURE_OPTIONS, function()
        for _, at in ipairs({ args.indoor, args.outdoor }) do
            local square = PZHarness.squareAt(at)
            local roomName = square:getRoom() and square:getRoom():getName()
            local where = " in " .. tostring(roomName or "no room")
            local controlled
            for _, field in ipairs(args.sprites) do
                local tiles = Sprites[field]
                for _, tile in pairs(type(tiles) == "table" and tiles or { tiles }) do
                    local object = placeTile(square, tile)
                    local container = object:getContainer()
                    if expect(container ~= nil, tile .. " has no container") then
                        local added = respawnFill(container)
                        expectEqual("items loot respawn put in " .. tile .. "'s " .. container:getType() .. where, added, 0)
                        if not controlled and container:isItemAllowed(generic) then
                            controlled = container:getType()
                            local control = 0
                            unprotected(controlled, roomName, function()
                                for _ = 1, CONTROL_FILLS do
                                    control = control + respawnFill(container)
                                    if control > 0 then break end
                                end
                            end)
                            expect(control > 0, string.format("%d fills of an unprotected %s%s added nothing", CONTROL_FILLS, controlled, where))
                        end
                    end
                    removePlaced(object)
                end
            end
            expect(controlled, "no tile's container takes a " .. GENERIC_ITEM .. where)
        end
    end)
    local own = {}
    for _, containerType in ipairs(Distributions.OWN_CONTAINER_TYPES) do
        own[containerType] = true
        expect(not Finds.CRACKED_MODULE_CONTAINERS[containerType], containerType .. " gets cracked modules")
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
            for _, containerType in ipairs(Distributions.OWN_CONTAINER_TYPES) do
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
