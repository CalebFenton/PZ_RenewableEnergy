require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
require "RenewableEnergy/Sprites"

-- Loot tests. See RenewableEnergyTestLib.lua for how the runner works. Distributions.lua puts the
-- loot in at OnInitGlobalModData; these tests check the result in the running game. Server Lua
-- loads after client Lua, so RenewableEnergy.Distributions is looked up when a test runs.

local test, expect, expectNear = RenewableEnergyTest.test, RenewableEnergyTest.expect, RenewableEnergyTest.expectNear

local function distributions()
    local D = RenewableEnergy.Distributions
    return expect(D ~= nil, "RenewableEnergy.Distributions did not load") and D
end

local function reapply()
    if RenewableEnergy.Distributions then
        RenewableEnergy.Distributions.apply()
    end
end

local countPairs = RenewableEnergyTest.countPairs

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

-- Lists ----------------------------------------------------------------------------------------

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

local function checkSubList(where, name, stashTables)
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

-- Entries once went to vanilla lists that no room or vehicle rolls, so those items never spawned
-- there. Every entry has to sit, once, in a list the game rolls: a room's procList, a vehicle's
-- container, a stash house's spawn table or a corpse's outfit list.
test("renewable_energy_loot_lists_in_use", {
    validate = function()
        local D = distributions()
        if not D then
            return
        end
        local procUsers = procListUsers()
        local vehicleTables = vehicleTablesInUse()
        local stashTables = stashSpawnTables()
        for _, spec in ipairs(D.items) do
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
                    checkSubList(where, name, stashTables)
                else
                    expect(false, where .. ": unknown kind of list")
                end
            end
        end
    end,
})

-- Every list actually hands out every item it lists, through the game's own rolls. The loot
-- rarity options are at their maximum, so a few rolls are enough even for the rarest entries.
test("renewable_energy_loot_items_spawn", {
    validate = function()
        if not distributions() then
            return
        end
        local targets = RenewableEnergy.Loot.targets()
        RenewableEnergy.Loot.withMeasureOptions(function()
            local function build()
                return RenewableEnergy.Loot.tablesFor(targets, false)
            end
            RenewableEnergy.Loot.withLoot(100, build, function(parsed)
                local container = RenewableEnergy.Loot.newContainer(nil)
                for i, target in ipairs(targets) do
                    local list = parsed["t" .. i]
                    if expect(list ~= nil, target.reference .. ": the game didn't parse it") then
                        local missing, remaining = {}, 0
                        for fullType in pairs(target.items) do
                            missing[fullType] = true
                            remaining = remaining + 1
                        end
                        for _ = 1, 200 do
                            for fullType in pairs(RenewableEnergy.Loot.rollOnce(list, container)) do
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
    end,
})

-- Every item the mod's scripts define as loot exists, so no entry is dropped silently by the game.
test("renewable_energy_loot_items_exist", {
    validate = function()
        local D = distributions()
        if not D then
            return
        end
        for _, spec in ipairs(D.items) do
            expect(getScriptManager():FindItem(spec.fullType) ~= nil, spec.fullType .. " is no item")
        end
    end,
})

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

-- Stage 0 gear turns up more often than stage 1 gear, and that more often than stage 2 gear.
test("renewable_energy_loot_later_stages_rarer", {
    validate = function()
        local D = distributions()
        if not D then
            return
        end
        local ladders = {
            { "RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter", "RenewableEnergy.InverterCharger" },
            { "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery" },
            { "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2" },
            { "RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarModule" },
        }
        for _, ladder in ipairs(ladders) do
            for i = 2, #ladder do
                local earlier, later = vanillaWeight(D, ladder[i - 1]), vanillaWeight(D, ladder[i])
                expect(earlier > later, ladder[i] .. " (" .. later .. ") is not rarer than " .. ladder[i - 1] .. " (" .. earlier .. ")")
            end
        end
    end,
})

-- Vehicles -------------------------------------------------------------------------------------

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
test("renewable_energy_loot_vehicle_tables", {
    validate = function()
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
    end,
})

-- Rarity options ------------------------------------------------------------------------------

-- At 0 an option used to leave its items in at weight 0, and the zombie density bonus, which
-- ItemPickerJava adds to the weight, still spawned them in towns.
test("renewable_energy_loot_lrm_zero_removes_items", {
    sandbox = { LRMSolarPanels = 0, LRMBatteries = 0, LRMMisc = 0 },
    validate = function()
        local D = distributions()
        if not D then
            return
        end
        D.apply()
        local managed = {}
        for _, spec in ipairs(D.items) do
            managed[spec.fullType] = true
        end
        forEachItemsList(function(items, path)
            for i = 1, #items - 1, 2 do
                if managed[items[i]] then
                    expect(false, items[i] .. " is still in " .. path)
                end
            end
        end)
    end,
    cleanup = reapply,
})

test("renewable_energy_loot_lrm_zero_keeps_other_items", {
    sandbox = { LRMSolarPanels = 0, LRMBatteries = 1, LRMMisc = 1 },
    validate = function()
        local D = distributions()
        if not D then
            return
        end
        D.apply()
        forEachItemsList(function(items, path)
            expect(countPairs(items, "RenewableEnergy.SolarModule") == 0, "RenewableEnergy.SolarModule is still in " .. path)
        end)
        for _, spec in ipairs(D.items) do
            if spec.option ~= "LRMSolarPanels" then
                for _, entry in ipairs(spec.entries) do
                    local items = D.resolveItemList(entry[2])
                    expect(items ~= nil and countPairs(items, spec.fullType) == 1, spec.fullType .. " is missing from " .. entry[2])
                end
            end
        end
    end,
    cleanup = reapply,
})

-- The options scale every weight, the mod's own lists included, and applying them again (as a
-- test or a second load would) replaces the entries instead of adding more.
test("renewable_energy_loot_lrm_scales_weights", {
    sandbox = { LRMSolarPanels = 2.5, LRMBatteries = 0.5, LRMMisc = 3 },
    validate = function()
        local D = distributions()
        if not D then
            return
        end
        D.apply()
        D.apply()
        for _, spec in ipairs(D.items) do
            local multiplier = SandboxVars.RenewableEnergy[spec.option]
            for _, entry in ipairs(spec.entries) do
                local items = D.resolveItemList(entry[2])
                local count, weight = 0, nil
                if items then
                    count, weight = countPairs(items, spec.fullType)
                end
                if expect(count == 1, spec.fullType .. " is in " .. entry[2] .. " " .. count .. " times") then
                    expectNear(spec.fullType .. " weight in " .. entry[2], weight, entry[1] * multiplier)
                end
            end
        end
    end,
    cleanup = reapply,
})

-- Found batteries -------------------------------------------------------------------------------

-- Batteries that rooms, vehicles and corpses hand out hold 30-80%, once: a refill of the container
-- by loot respawn leaves a battery already there alone.
test("renewable_energy_loot_found_batteries_part_charged", {
    validate = function()
        local D = distributions()
        if not D then
            return
        end
        local range = RenewableEnergy.Specs.foundCharge
        local container = RenewableEnergy.Loot.newContainer(nil)
        local bag = container:AddItem("Base.Bag_DuffelBag")
        local loose = container:AddItem("RenewableEnergy.DeepCycleBattery")
        local bagged = bag and bag:getInventory():AddItem("RenewableEnergy.L16Battery")
        local wire = container:AddItem("Base.ElectricWire")
        if not expect(loose ~= nil and bagged ~= nil and wire ~= nil, "could not build the container") then
            return
        end
        D.chargeFoundBatteries(container)
        for _, battery in ipairs({ loose, bagged }) do
            local charge = RenewableEnergy.Battery.getCharge(battery)
            expect(charge >= range.min and charge <= range.max,
                battery:getFullType() .. " holds " .. charge .. ", expected " .. range.min .. " to " .. range.max)
        end
        RenewableEnergy.Battery.setCharge(loose, 1)
        D.chargeFoundBatteries(container)
        expectNear("a stored battery's charge after a second fill", RenewableEnergy.Battery.getCharge(loose), 1)
        container:removeAllItems()
    end,
})

-- Containers the player owns -----------------------------------------------------------------------

local OWN_CONTAINERS = {
    { sprite = "batteryBoxWood", type = "RenewableEnergyBatteryBoxWood" },
    { sprite = "batteryBoxMetal", type = "RenewableEnergyBatteryBoxMetal" },
    { sprite = "batteryRackWood", type = "RenewableEnergyBatteryRackWood" },
    { sprite = "batteryRackMetal", type = "RenewableEnergyBatteryRackMetal" },
    { sprite = "batteryBankWood", type = "RenewableEnergyBatteryBankWood" },
    { sprite = "batteryBankMetal", type = "RenewableEnergyBatteryBankMetal" },
    { sprite = "cellCharger", type = "RenewableEnergyCellCharger" },
    { sprite = "crate", type = "RenewableEnergySolarBox" },
}

-- Up to `wanted` loaded squares near the player in rooms that have a loot distribution, one per
-- room type, and one square outside any room.
local function sampleSquares(wanted)
    local squares, roomNames = {}, {}
    local player, cell = RenewableEnergyTest.player(), getCell()
    local px, py = math.floor(player:getX()), math.floor(player:getY())
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
    local outside = RenewableEnergy.Loot.squareOutsideRooms()
    if outside then
        table.insert(squares, outside)
    end
    return squares
end

-- Loot respawn refills an explored, looted container that isn't an IsoThumpable by calling
-- ItemPickerJava.fillContainer(container, nil) (LootRespawn.respawnInContainer). A player's battery
-- bank is an IsoGenerator; if any room handed its container type a loot list, a bank someone took a
-- battery out of would refill with free batteries every respawn. The objects are built from the
-- tiles, as placing them does, but never added to the square.
test("renewable_energy_loot_player_containers_not_refilled", {
    validate = function()
        local squares = sampleSquares(4)
        if not expect(#squares >= 2, "no loaded room near the player") then
            return
        end
        for _, square in ipairs(squares) do
            local room = square:getRoom()
            local where = room and room:getName() or "outside"
            for _, spec in ipairs(OWN_CONTAINERS) do
                local sprite = RenewableEnergy.Sprites[spec.sprite]
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
    end,
})
