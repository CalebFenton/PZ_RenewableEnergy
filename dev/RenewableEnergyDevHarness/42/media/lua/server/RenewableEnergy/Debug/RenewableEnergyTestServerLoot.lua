-- The authority's half of the loot tests: the server's loot tables alone hold the mod's entries.
-- Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Checks"
require "PZHarness/Fixtures"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler
local newCheck, countPairs = PZHarness.Checks.new, PZHarness.Fixtures.countPairs
local squareAt, removeObject = Helpers.squareAt, Helpers.removeObject
local Sprites = RenewableEnergy.Sprites

local function distributions(expect)
    local D = RenewableEnergy.Distributions
    return expect(D ~= nil, "RenewableEnergy.Distributions did not load") and D
end

-- Calls fn(items, path) for every items list of every room, bag, procedural and vehicle table.
local function forEachItemsList(fn)
    local seen = {}
    local function walk(t, path, depth)
        if seen[t] or depth > 6 then
            return
        end
        seen[t] = true
        if type(t.items) == "table" then
            fn(t.items, path)
        end
        for key, value in pairs(t) do
            if type(value) == "table" and key ~= "items" and key ~= "procList" then
                walk(value, path .. "." .. tostring(key), depth + 1)
            end
        end
    end
    walk(SuburbsDistributions, "SuburbsDistributions", 0)
    walk(ProceduralDistributions.list, "ProceduralDistributions", 0)
    walk(VehicleDistributions, "VehicleDistributions", 0)
end

-- The first room and container type whose procList names each ProceduralDistributions list.
local function procListUsers()
    local users = {}
    for roomName, room in pairs(SuburbsDistributions) do
        if type(room) == "table" and room.rolls == nil then
            for containerType, containerTable in pairs(room) do
                if type(containerTable) == "table" and type(containerTable.procList) == "table" then
                    for _, choice in ipairs(containerTable.procList) do
                        if choice.name and not users[choice.name] then
                            users[choice.name] = { room = roomName, container = containerType }
                        end
                    end
                end
            end
        end
    end
    return users
end

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

-- The spawn tables of every stash house, vanilla's and the mod's.
local function stashSpawnTables()
    local tables = { RenewableEnergyStashCache = true }
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

-- Every entry names an item that exists, since the game drops an unknown item silently, and sits
-- once in a list the game rolls: a room's procList, a vehicle's container, a stash house's spawn
-- table or a corpse's outfit list.
handler("lootListsInUse", function()
    local expect, _, failures = newCheck()
    local D = distributions(expect)
    if not D then
        return { failures = failures }
    end
    local procUsers = procListUsers()
    local vehicleTables = vehicleTablesInUse()
    local stashTables = stashSpawnTables()
    for _, spec in ipairs(D.items) do
        expect(getScriptManager():FindItem(spec.fullType) ~= nil, spec.fullType .. " is no item")
        for _, entry in ipairs(spec.entries) do
            local reference = entry[2]
            local where = spec.fullType .. " in " .. reference
            local items = D.resolveItemList(reference)
            if expect(items ~= nil, where .. ": no such list") then
                expect(countPairs(items, spec.fullType) == 1, where .. ": not listed exactly once")
            end
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
    return { failures = failures }
end)

-- Every list actually hands out every item it lists, through the game's own rolls. The loot
-- rarity options are at their maximum, so a few rolls are enough even for the rarest entries.
handler("lootItemsSpawn", function()
    local expect, _, failures = newCheck()
    if not distributions(expect) then
        return { failures = failures }
    end
    local Loot = RenewableEnergy.Loot
    local targets = Loot.targets()
    Loot.withMeasureOptions(function()
        local function build()
            return Loot.tablesFor(targets, false)
        end
        Loot.withLoot(100, build, function(parsed)
            local container = Loot.newContainer(nil)
            for i, target in ipairs(targets) do
                local list = parsed["t" .. i]
                if expect(list ~= nil, target.reference .. ": the game didn't parse it") then
                    local missing, remaining = {}, 0
                    for fullType in pairs(target.items) do
                        missing[fullType] = true
                        remaining = remaining + 1
                    end
                    for _ = 1, 200 do
                        for fullType in pairs(Loot.rollOnce(list, container)) do
                            if missing[fullType] then
                                missing[fullType] = nil
                                remaining = remaining - 1
                            end
                        end
                        if remaining == 0 then
                            break
                        end
                    end
                    for fullType in pairs(missing) do
                        expect(false, fullType .. " never spawned from " .. target.reference)
                    end
                end
            end
        end)
    end)
    return { failures = failures }
end)

-- Sum of an item's weights in vanilla lists: the mod's own kit and stock lists don't count,
-- since they are rolled only in a few store rooms.
local function vanillaWeight(D, fullType)
    local total = 0
    for _, spec in ipairs(D.items) do
        if spec.fullType == fullType then
            for _, entry in ipairs(spec.entries) do
                if not string.find(entry[2], "RenewableEnergy") then
                    total = total + entry[1]
                end
            end
        end
    end
    return total
end

-- Each ladder of `args.ladders` turns up less often at each step.
handler("lootLaterStagesRarer", function(_, args)
    local expect, _, failures = newCheck()
    local D = distributions(expect)
    if not D then
        return { failures = failures }
    end
    for _, ladder in ipairs(args.ladders) do
        for i = 2, #ladder do
            local earlier, later = vanillaWeight(D, ladder[i - 1]), vanillaWeight(D, ladder[i])
            expect(earlier > later, ladder[i] .. " (" .. later .. ") is not rarer than " .. ladder[i - 1] .. " (" .. earlier .. ")")
        end
    end
    return { failures = failures }
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

-- The utility vans keep every vanilla builder's item and get the mod's own truck bed; trailers
-- can roll a camper's.
handler("lootVehicleTables", function()
    local expect, _, failures = newCheck()
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
    return { failures = failures }
end)

-- Each loot rarity option scales the weights of its items in every list, the mod's own lists
-- included, for each row of `args.rows`. At 0 it takes its items out of every list rather than
-- leaving them at weight 0, because ItemPickerJava adds the zombie density bonus to every weight,
-- so they would still spawn in towns; the other options' items stay. Applying the options again,
-- as a second load does, replaces the entries instead of adding more.
handler("lootRarityOptions", function(_, args)
    local expect, expectNear, failures = newCheck()
    local D = distributions(expect)
    if not D then
        return { failures = failures }
    end
    local options = SandboxVars.RenewableEnergy
    local saved = {}
    for option in pairs(args.rows[1]) do
        saved[option] = options[option]
    end
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
        forEachItemsList(function(items, path)
            for i = 1, #items - 1, 2 do
                if removed[items[i]] then
                    expect(false, label .. ": " .. items[i] .. " is still in " .. path)
                end
            end
        end)
    end
    for option, value in pairs(saved) do
        options[option] = value
    end
    D.apply()
    return { failures = failures }
end)

-- A container type that "all" rolls the mod's batteries into for certain: a weight this high is
-- past the game's 10,000 in 10,000 at any loot multiplier above a tenth.
local PROBE_CONTAINER = "RenewableEnergyTestBatteries"
local PROBE_LOOT = { rolls = 2, items = { "RenewableEnergy.DeepCycleBattery", 1000, "RenewableEnergy.L16Battery", 1000 } }

-- The mod's batteries in the container, bags included.
local function modBatteries(container, found)
    found = found or {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:IsInventoryContainer() then
            modBatteries(item:getInventory(), found)
        elseif string.find(item:getFullType(), "^RenewableEnergy%.") and RenewableEnergy.Battery.isBattery(item) then
            table.insert(found, item)
        end
    end
    return found
end

-- A crate of container type `containerType` on the square, in the world, so that the game can send
-- its items' charges to the clients that see it. Removed when the test ends.
local function worldCrate(square, containerType, defer)
    local crate = IsoObject.new(square, "carpentry_01_16", "RenewableEnergyTest")
    crate:setContainer(ItemContainer.new(containerType, square, crate))
    square:AddTileObject(crate)
    if isServer() then
        crate:transmitCompleteItemToClients()
    end
    defer(function() removeObject(crate) end)
    return crate:getContainer()
end

-- Batteries that loot hands out hold a part charge, once: a refill of the container, as loot
-- respawn does, leaves a battery already there alone. Each container is filled the way the game
-- fills it (ItemPickerJava.fillContainer): one outside any room rolls the "all" table of its type,
-- here one that rolls the mod's batteries, and one of a corpse's type rolls the corpse lists; a
-- bag in each holds a battery, as a looted bag can. The arrow board tests cover vehicle fills,
-- which stock the trailer's battery box. `args` is a free outdoor square.
handler("lootFoundBatteries", function(_, args, defer)
    local expect, expectNear, failures = newCheck()
    if not distributions(expect) then
        return { failures = failures }
    end
    local square = squareAt(args)
    if not square or square:getRoom() then
        return nil, "an outdoor square loaded on the server"
    end
    local Battery = RenewableEnergy.Battery
    local range = RenewableEnergy.Specs.foundCharge
    expect(range.min > 0 and range.min < range.max and range.max <= 1,
        "found batteries hold " .. range.min .. " to " .. range.max .. " of a charge")
    SuburbsDistributions.all[PROBE_CONTAINER] = PROBE_LOOT
    ItemPickerJava.Parse()
    defer(function()
        SuburbsDistributions.all[PROBE_CONTAINER] = nil
        ItemPickerJava.Parse()
    end)
    for _, fill in ipairs({ { type = PROBE_CONTAINER, what = "a room's crate", rolled = true }, { type = "inventorymale", what = "a corpse" } }) do
        local container = worldCrate(square, fill.type, defer)
        local bag = container:AddItem("Base.Bag_DuffelBag")
        bag:getInventory():AddItem("RenewableEnergy.DeepCycleBattery")
        ItemPickerJava.fillContainer(container, nil)
        local batteries = modBatteries(container)
        -- The bag's battery and, from the probe table, at least one rolled.
        expect(#batteries >= (fill.rolled and 2 or 1), #batteries .. " batteries in " .. fill.what .. " after a fill")
        for _, battery in ipairs(batteries) do
            local charge = Battery.getCharge(battery)
            expect(charge >= range.min and charge <= range.max,
                battery:getFullType() .. " in " .. fill.what .. " holds " .. charge .. ", expected " .. range.min .. " to " .. range.max)
        end
        local stored = batteries[1]
        if stored then
            Battery.setCharge(stored, 1)
            ItemPickerJava.fillContainer(container, nil)
            expectNear("a stored battery's charge in " .. fill.what .. " after a refill", Battery.getCharge(stored), 1)
        end
    end
    return { failures = failures }
end)

-- Up to `wanted` loaded squares near the character in rooms that have a loot distribution, one per
-- room type, and one square outside any room.
local function sampleSquares(character, wanted)
    local squares, roomNames = {}, {}
    local cell = getCell()
    local px, py = math.floor(character:getX()), math.floor(character:getY())
    for dx = -60, 60 do
        for dy = -60, 60 do
            local square = cell:getGridSquare(px + dx, py + dy, 0)
            local room = square and square:getRoom()
            local name = room and room:getName()
            if name and not roomNames[name] and #squares < wanted and SuburbsDistributions[name] then
                roomNames[name] = true
                table.insert(squares, square)
            end
        end
    end
    local outside = RenewableEnergy.Loot.squareOutsideRooms(character)
    if outside then
        table.insert(squares, outside)
    end
    return squares
end

-- Loot respawn refills an explored, looted container that isn't an IsoThumpable by calling
-- ItemPickerJava.fillContainer(container, nil) (LootRespawn.respawnInContainer). A player's battery
-- bank is an IsoGenerator; if any room handed its container type a loot list, a bank someone took a
-- battery out of would refill with free batteries every respawn. The objects of `args.containers`
-- ({ { sprite, type } }) are built from the tiles, as placing them does, but never added to the
-- square.
handler("lootPlayerContainers", function(player, args)
    local expect, _, failures = newCheck()
    local squares = sampleSquares(player, 4)
    if not expect(#squares >= 2, "no loaded room near the character") then
        return { failures = failures }
    end
    for _, square in ipairs(squares) do
        local room = square:getRoom()
        local where = room and room:getName() or "outside"
        for _, spec in ipairs(args.containers) do
            local sprite = Sprites[spec.sprite]
            local object = IsoObject.new(square, sprite, spec.type)
            object:createContainersFromSpriteProperties()
            local container = object:getContainer()
            if expect(container ~= nil and container:getType() == spec.type, sprite .. " gives no " .. spec.type .. " container") then
                container:setExplored(true)
                container:setHasBeenLooted(true)
                for _ = 1, 20 do
                    ItemPickerJava.fillContainer(container, nil)
                end
                local count = container:getItems():size()
                expect(count == 0, "respawn put " .. count .. " items into a " .. spec.type .. " in " .. where)
                container:removeAllItems()
            end
        end
    end
    return { failures = failures }
end)
