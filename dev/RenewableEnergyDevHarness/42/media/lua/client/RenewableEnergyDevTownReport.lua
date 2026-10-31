-- Development only; the --loot mode (RenewableEnergyDevHarness.lua) prints this report. The
-- modules, batteries and PART_TYPES a thorough player finds in each town of
-- RenewableEnergyDevTownCensus, and the yardsticks that turn them into power. Client Lua: it
-- requires WorldSpawns, SolarSites and Finds as it runs, which a single player game, the only one
-- --loot runs, has. It reads the mod's own spawn rules (stocking functions, Finds, the loot tables)
-- rather than copies of their numbers, so a change to one reaches the report without an edit here.

local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Sun = require "RenewableEnergy/Sun"
local Battery = require "RenewableEnergy/PowerBank/Battery"
require "PZHarness/Loot"
local Yardsticks = require "RenewableEnergy/Debug/RenewableEnergyYardsticks"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Trailer"
local Specs = require "RenewableEnergy/Specs"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local Wind = require "RenewableEnergy/Wind"

local PZLoot = PZHarness.Loot
local TownReport = {}

local MODULE = Specs.factoryModule
local LOOSE_BATTERIES = { "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery" }
local CAR_BATTERIES = { "Base.CarBattery1", "Base.CarBattery2", "Base.CarBattery3" }

-- The parts and magazines counted by full type alongside the modules and batteries, each with the
-- sources most of a town's come from. Corpses, stash houses and RuralFinds aren't counted.
local PART_TYPES = {
    "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2", "RenewableEnergy.HomesteadPowerMag3",
    "RenewableEnergy.HomesteadPowerMag4", "RenewableEnergy.FemaPamphlet", "RenewableEnergy.PlugInInverter",
    "RenewableEnergy.PowerInverter", "RenewableEnergy.ChargeController", "RenewableEnergy.InverterCharger",
    "RenewableEnergy.SolarFailsafe", "RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger",
}
local IS_PART = {}
for _, fullType in ipairs(PART_TYPES) do
    IS_PART[fullType] = true
end
-- How many of a part's largest sources in a town its line names.
local PART_SOURCES = 5

-- The rooms of a home. The report gives what they hold together per kitchen, one to a home.
local HOME_ROOMS = {
    "bathroom", "bedroom", "closet", "diningroom", "garage", "garagestorage", "hall", "kidsbedroom", "kitchen", "laundry",
    "livingroom",
}
-- The shops and storerooms the report gives what one of holds on average.
local VISIT_ROOMS = {
    "electronicsstore", "electronicsstorage", "camping", "campingstorage", "toolstore", "toolstorestorage", "carsupply",
    "gardenstore", "mechanic", "farmstorage", "warehouse", "storageunit", "garagestorage",
}

-- What a source holds on average: modules with their condition summed, as found and after one
-- Seal Cracked Module on every module it helps, and batteries with their watt-hours as found.
local function none()
    return { modules = 0, condition = 0, repaired = 0, batteries = 0, wh = 0 }
end

-- Adds every figure of `part`, `times` over if given, to `total`, and returns it.
local function add(total, part, times)
    for key, value in pairs(part) do
        total[key] = (total[key] or 0) + value * (times or 1)
    end
    return total
end

-- The mean of a { min, max } range whose every whole number is as likely.
local function midpoint(range)
    return (range.min + range.max) / 2
end

-- `count` new batteries of `fullType`.
local function batteriesOf(fullType, count)
    return { batteries = count, wh = count * Specs.batteries[fullType].wh }
end

-- What Seal Cracked Module brings the module item `item` to, or its condition where a seal can't
-- help it.
local function sealedCondition(item)
    local fullType, condition, repaired = item:getFullType(), item:getCondition(), item:getHaveBeenRepaired()
    if not ModuleRepair.sealable(fullType, condition, repaired) then
        return condition
    end
    return (ModuleRepair.sealed(fullType, condition, repaired))
end

-- One module whose condition is uniform over the range. A scratch module takes each condition, so
-- Seal Cracked Module's own rule prices it.
local function moduleOver(range)
    local module = instanceItem(MODULE)
    local sum, repairedSum, n = 0, 0, 0
    for condition = range.min, range.max do
        Wear.setCondition(module, condition)
        sum = sum + condition
        repairedSum = repairedSum + sealedCondition(module)
        n = n + 1
    end
    return { modules = 1, condition = sum / n, repaired = repairedSum / n }
end

-- One module that is `a` with chance `share`, else `b`.
local function mix(share, a, b)
    return { modules = 1, condition = share * a.condition + (1 - share) * b.condition,
        repaired = share * a.repaired + (1 - share) * b.repaired }
end

--- What one fill of a container holds, as a reader for PZHarness.Loot.sample: its modules with
--- their condition as found and after Seal Cracked Module, its batteries with their watt-hours
--- after wear, and each of PART_TYPES by full type.
function TownReport.findsIn(container)
    local finds = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == MODULE then
            local condition = item:getCondition()
            add(finds, { modules = 1, condition = condition, repaired = sealedCondition(item) })
        elseif Battery.isBattery(item) then
            add(finds, { batteries = 1, wh = Battery.nominalWh(item) })
        elseif IS_PART[item:getFullType()] then
            add(finds, { [item:getFullType()] = 1 })
        end
    end
    return finds
end

-- What a container holds on average, from PZHarness.Loot.sample's result with TownReport.findsIn.
local function meanFinds(sampled)
    local means = none()
    for key, measured in pairs(sampled) do
        means[key] = measured.share * measured.perContainer
    end
    return means
end

-- An arrow board's panel modules, as many as the panel rarity option gives, one cracked at most.
-- ArrowBoard stocks them straight into the trailer's panel parts, which a scratch container can't
-- stand in for, so they are counted from its STOCK.
local function arrowBoardPanels(weathered, second)
    local modules = math.min(#ArrowBoard.PANELS, ArrowBoard.STOCK.modules * SandboxVars.RenewableEnergy.LRMSolarPanels)
    local total = add(none(), weathered, math.min(1, modules))
    return add(total, second, math.max(0, modules - 1))
end

-- The finds each source holds on average; banks and crates by their BANK_STOCK and CRATE_STOCK
-- names, from `stocks` (TownReport.print).
local function findKinds(stocks)
    local Finds = require "RenewableEnergy/Items/Finds"
    local cracked, weathered = moduleOver(Finds.CRACKED), moduleOver(Finds.WEATHERED)
    local banks, crates = {}, {}
    for name, sampled in pairs(stocks.banks) do
        banks[name] = meanFinds(sampled.finds)
    end
    for name, sampled in pairs(stocks.crates) do
        crates[name] = meanFinds(sampled.finds)
    end
    local panels = arrowBoardPanels(weathered, mix(ArrowBoard.STOCK.secondCrackedChance, cracked, weathered))
    return {
        intact = { modules = 1, condition = 100, repaired = 100 },
        cracked = cracked,
        site = mix(Finds.SITE_CRACKED_SHARE, cracked, weathered),
        arrowBoard = add(panels, meanFinds(stocks.arrowBoard.finds)),
        banks = banks,
        crates = crates,
    }
end

-- ItemPickerJava.getBaseChanceMultiplier: a junk entry rolls at its weight times this.
local JUNK_WEIGHT_MULTIPLIER = 1.4

-- The chance one roll of an entry of `weight` hits: ItemPickerJava rolls Rand.Next(10000) below
-- getActualSpawnChance, which is weight * 100 * the loot multiplier.
local function chancePerRoll(weight, multiplier)
    return math.min(1, math.ceil(weight * 100 * multiplier) / 10000)
end

-- Expected count of `fullType` in one fill of `list`'s items, with each weight times `weightFactor`.
-- Vanilla's lists name Base items without their module.
local function expectedInItems(list, fullType, weightFactor, multiplier)
    local total = 0
    local items = list.items or {}
    local short = fullType:match("^Base%.(.+)$")
    for i = 1, #items - 1, 2 do
        if items[i] == fullType or items[i] == short then
            total = total + (list.rolls or 1) * chancePerRoll(items[i + 1] * weightFactor, multiplier)
        end
    end
    return total
end

-- Expected count of `fullType` in one fill of a loot table, junk included, at the loot multipliers
-- ItemPickerJava.getLootModifier gives an entry and a junk entry.
local function expectedIn(lootTable, fullType)
    if type(lootTable) ~= "table" then
        return 0
    end
    local total = expectedInItems(lootTable, fullType, 1, ItemPickerJava.getLootModifier(fullType))
    if lootTable.junk then
        total = total + expectedInItems(lootTable.junk, fullType, JUNK_WEIGHT_MULTIPLIER,
            ItemPickerJava.getLootModifier(fullType, true))
    end
    return total
end

local function isForced(pick)
    return pick.forceForZones or pick.forceForTiles or pick.forceForRooms or pick.forceForItems
end

local function pickWeight(pick)
    return math.max(1, pick.weightChance or 1)
end

-- Whether the room's first containers take `pick` before any other: rollProceduralItemInternal
-- picks among the lists of min 1 that the room hasn't spawned yet, by weight, before the rest.
local function isFirst(pick)
    return not isForced(pick) and pick.min == 1
end

-- Container types that never take a room's `other` table (ItemPickerJava.initNoGenericLootContainers).
local NO_GENERIC_LOOT = {}
for _, containerType in ipairs({
    "barbecue", "barbecuepropane", "bin", "brazier", "campfire", "cashregister", "clothingdryer", "clothingdryerbasic",
    "clothingrack", "clothingwasher", "coffeemaker", "coffin", "composter", "dishwasher", "doghouse", "dumpster",
    "fireplace", "freezer", "fridge", "icecream", "logs", "Mannequin", "medicine", "microwave", "newspaper_dispatch",
    "newspaper_herald", "newspaper_knews", "newspaper_times", "plankstash", "postbox", "shelter", "stonefurnace", "stove",
    "SurvivorCrate", "tent", "toaster", "trough", "vendingGt", "vendingpop", "vendingsnack", "woodstove",
}) do
    NO_GENERIC_LOOT[containerType] = true
end

-- The table a container of `containerType` in a room named `roomName` fills from, as
-- ItemPickerJava.fillContainer chooses it: the room's own for the type, else the room's `other`,
-- else the room's `all`; in a room with none of them, or none of its own, `all`'s for the type,
-- else `all`'s `other`.
local function containerTable(roomName, containerType)
    local function from(room)
        return room[containerType] or (not NO_GENERIC_LOOT[containerType] and room.other) or nil
    end
    local room = SuburbsDistributions[roomName]
    return room and (from(room) or room.all) or from(SuburbsDistributions.all)
end

-- Expected items of `fullType` in `count` containers that fill from the table `entry`, spread over
-- `rooms` rooms. A room counts what its containers picked from a procedural table together, so a
-- room's containers go first to the table's lists of min 1, one each, as far as they reach; the
-- rest pick by weight, each list up to its max.
local function expectedInTable(entry, count, rooms, fullType)
    if not entry.procedural then
        return count * expectedIn(entry, fullType)
    end
    local procList = entry.procList or {}
    local totalWeight, firsts = 0, 0
    for _, pick in ipairs(procList) do
        if not isForced(pick) then
            totalWeight = totalWeight + pickWeight(pick)
        end
        if isFirst(pick) then
            firsts = firsts + 1
        end
    end
    local perRoom = count / rooms
    local firstShare = firsts > 0 and math.min(1, perRoom / firsts) or 0
    local rest = math.max(0, perRoom - firsts)
    local total = 0
    for _, pick in ipairs(procList) do
        local list = ProceduralDistributions.list[pick.name]
        if not isForced(pick) and list then
            local first = isFirst(pick) and firstShare or 0
            local picked = first + math.min(rest * pickWeight(pick) / totalWeight, (pick.max or math.huge) - first)
            total = total + rooms * picked * expectedIn(list, fullType)
        end
    end
    return total
end

-- Expected items of `fullType` in the containers of `byType` (container type -> count) of `rooms`
-- rooms named `roomName`, those that fill from the same table counted together.
local function expectedInRooms(roomName, byType, rooms, fullType)
    local byTable = {}
    for containerType, count in pairs(byType) do
        local entry = containerTable(roomName, containerType)
        if type(entry) == "table" then
            byTable[entry] = (byTable[entry] or 0) + count
        end
    end
    local total = 0
    for entry, count in pairs(byTable) do
        total = total + expectedInTable(entry, count, math.max(1, rooms), fullType)
    end
    return total
end

-- Expected items of `fullType` in the room loot of a town of the census, by room name.
local function expectedInTownByRoom(town, fullType)
    local byRoom = {}
    for roomName, byType in pairs(town.containers) do
        byRoom[roomName] = expectedInRooms(roomName, byType, town.rooms[roomName] or 0, fullType)
    end
    return byRoom
end

-- Expected items of `fullType` in the room loot of a town of the census.
local function expectedInTown(town, fullType)
    local total = 0
    for _, count in pairs(expectedInTownByRoom(town, fullType)) do
        total = total + count
    end
    return total
end

-- The expected number of chances fn() comes up on: Chance.hit adds each chance it is asked
-- instead of rolling it, and answers no, so fn adds nothing.
local function expectedHits(fn)
    local Chance = require "cf_commonlib/Chance"
    local hit, expected = Chance.hit, 0
    Chance.hit = function(chance)
        expected = expected + math.max(0, math.min(1, chance))
        return false
    end
    PZLoot.restoring(fn, function() Chance.hit = hit end)
    return expected
end

-- The cracked modules a container of `containerType` in a room named `roomName` gets on average.
local function roomCrackedModules(roomName, containerType, container)
    local Finds = require "RenewableEnergy/Items/Finds"
    return expectedHits(function() Finds.addCrackedModules(roomName, containerType, container) end)
end

-- What OnSeeNewRoom places, on average, in `rooms` rooms named `roomName`: `banks`, how many world
-- banks (nil in a room it places none in), `bankFinds`, what they hold and the modules it lays
-- beside them (WorldSpawns.layModulesBeside), and `crates`, what its garage kit crates hold. nil
-- with Battery Bank Spawn off.
local function roomSpawns(roomName, rooms, kinds)
    local WorldSpawns = require "RenewableEnergy/World/WorldSpawns"
    local rarity = WorldSpawns.RARITY[SandboxVars.RenewableEnergy.BatteryBankSpawn]
    if not rarity then
        return nil
    end
    local spawns = { bankFinds = none(), crates = none() }
    local bank = WorldSpawns.BANK_ROOMS[roomName]
    if bank then
        spawns.banks = rooms / (bank.odds * rarity)
        add(spawns.bankFinds, kinds.banks[bank.stock], spawns.banks)
        local beside = WorldSpawns.BANK_STOCK[bank.stock].modules
        if beside then
            add(spawns.bankFinds, kinds.site,
                spawns.banks * beside.chance * midpoint(beside) * SandboxVars.RenewableEnergy.LRMSolarPanels)
        end
    end
    local crateOdds = WorldSpawns.CRATE_ROOMS[roomName]
    if crateOdds then
        add(spawns.crates, kinds.crates.garageKit, rooms / (crateOdds * rarity))
    end
    return spawns
end

-- What the rooms of a town hold: `listed`, the mod's items in room loot; `cracked`, cracked
-- modules; `banks`, the world banks OnSeeNewRoom places, their batteries and the modules they lay
-- beside them (WorldSpawns.layModulesBeside), `banksByRoom` how many by room name; `crates`, the
-- garage kit crates it places; and `cars`, car batteries in room loot. Banks and crates need
-- Battery Bank Spawn on.
local function roomFinds(town, kinds)
    local WorldSpawns = require "RenewableEnergy/World/WorldSpawns"
    local row = { listed = add(none(), kinds.intact, expectedInTown(town, MODULE)), cracked = none(), banks = none(),
        banksByRoom = {}, crates = none(), cars = 0 }
    for _, fullType in ipairs(LOOSE_BATTERIES) do
        add(row.listed, batteriesOf(fullType, expectedInTown(town, fullType)))
    end
    for _, fullType in ipairs(CAR_BATTERIES) do
        row.cars = row.cars + expectedInTown(town, fullType)
    end
    local container = PZLoot.scratchContainer(nil)
    for roomName, byType in pairs(town.containers) do
        for containerType, count in pairs(byType) do
            add(row.cracked, kinds.cracked, count * roomCrackedModules(roomName, containerType, container))
        end
    end
    local spawnRooms = {}
    for roomName in pairs(WorldSpawns.BANK_ROOMS) do
        spawnRooms[roomName] = true
    end
    for roomName in pairs(WorldSpawns.CRATE_ROOMS) do
        spawnRooms[roomName] = true
    end
    for roomName in pairs(spawnRooms) do
        local spawns = roomSpawns(roomName, town.rooms[roomName] or 0, kinds)
        if spawns then
            row.banksByRoom[roomName] = spawns.banks
            add(row.banks, spawns.bankFinds)
            add(row.crates, spawns.crates)
        end
    end
    return row
end

-- BaseVehicle.randomizeContainers' special loot chance for a script whose own is 0 or less. It
-- rolls Rand.Next(100) <= chance, so a chance of n is n + 1 in 100.
local DEFAULT_SPECIAL_LOOT_CHANCE = 8

-- The loot of the vehicle script `script`. Vanilla VehicleDistributions.lua inserts its table by
-- vehicle script name at index 1.
local function distributionOf(script)
    return VehicleDistributions[1][(string.gsub(script, "^Base%.", ""))]
end

-- Expected items of `fullType` in one vehicle of a script: its Normal loot, or one of its Specific
-- sets at the vehicle's special loot chance.
local function vehicleExpected(script, fullType)
    local distribution = distributionOf(script)
    if not distribution then
        return 0
    end
    local vehicleScript = getScriptManager():getVehicle(script)
    local chance = vehicleScript and vehicleScript:getSpecialLootChance() or 0
    local specialShare = ((chance > 0 and chance or DEFAULT_SPECIAL_LOOT_CHANCE) + 1) / 100
    local function inSet(set)
        local total = 0
        for part, lootTable in pairs(set or {}) do
            if part ~= "specificId" then
                total = total + expectedIn(lootTable, fullType)
            end
        end
        return total
    end
    local specific = distribution.Specific or {}
    if #specific == 0 then
        return inSet(distribution.Normal)
    end
    local specificTotal = 0
    for _, set in ipairs(specific) do
        specificTotal = specificTotal + inSet(set)
    end
    return (1 - specialShare) * inSet(distribution.Normal) + specialShare * specificTotal / #specific
end

-- The chance a traffic jam's slot takes a car (Rand.Next(100) <= 80), and that a chunk of an
-- rtrafficjam zone jams at all (IsoChunk.AddVehicles).
local JAM_SLOT_TAKEN, RANDOM_JAM_CHUNK = 0.81, 0.1
-- VehicleType's spawnRate and chanceToSpawnNormal for a zone that sets none.
local DEFAULT_SPAWN_RATE, DEFAULT_CHANCE_TO_SPAWN_NORMAL = 16, 80

-- The vehicles a stall of the zone holds, by script: the chance a stall holds one, as
-- IsoChunk.AddVehicles_OnZone and VehicleType.getRandomVehicleType roll them, leaving out the
-- special vehicles a few stalls of an ordinary zone turn into. A traffic jam's slots, which
-- census.py counts as IsoChunk.AddVehicles_TrafficJam_* lays them out, take a car far more often
-- than a stall does.
local function zoneVehicles(zoneName)
    local randomJam = zoneName:match("^r(trafficjam%a)$")
    local zone = VehicleZoneDistribution[randomJam or zoneName]
    if not zone or not zone.vehicles then
        return {}
    end
    local spawn
    if randomJam then
        spawn = JAM_SLOT_TAKEN * RANDOM_JAM_CHUNK
    elseif zoneName:match("^trafficjam%a$") then
        spawn = JAM_SLOT_TAKEN
    else
        spawn = math.min(1, ((zone.spawnRate or DEFAULT_SPAWN_RATE) + 1) / 100)
    end
    spawn = spawn * (1 - (zone.chanceToSpawnBurnt or 0) / 100)
    local result = {}
    local function addFrom(vehicles, share)
        local total = 0
        for _, entry in pairs(vehicles) do
            total = total + entry.spawnChance
        end
        for script, entry in pairs(vehicles) do
            result[script] = (result[script] or 0) + share * entry.spawnChance / total
        end
    end
    local normal = zone.specialCar and (zone.chanceToSpawnNormal or DEFAULT_CHANCE_TO_SPAWN_NORMAL) / 100 or 0
    addFrom(zone.vehicles, spawn * (1 - normal))
    if normal > 0 then
        addFrom(VehicleZoneDistribution.parkingstall.vehicles, spawn * normal)
    end
    return result
end

-- Stands in for the container of the part `partId` of a vehicle in the zone `zoneName`: all
-- Finds.addCrackedModules asks of it, its vehicle's zone and its part's id.
local function partContainer(zoneName, partId)
    local vehicle = { getZone = function() return zoneName end }
    local part = { getId = function() return partId end }
    return { getVehicle = function() return vehicle end, getVehiclePart = function() return part end }
end

-- The cracked modules one vehicle of the script holds in the vehicle zone `zoneName`: each of its
-- containers that BaseVehicle.randomizeContainers fills rolls Finds.addCrackedModules
-- once. A part counts as a container when the script's loot names it, which leaves out its doors.
local function vehicleCrackedModules(script, zoneName)
    local distribution = distributionOf(script)
    local vehicleScript = getScriptManager():getVehicle(script)
    if not (distribution and distribution.Normal and vehicleScript) then
        return 0
    end
    local Finds = require "RenewableEnergy/Items/Finds"
    local roomName = string.gsub(script, "^Base%.", "")
    local total = 0
    for i = 0, vehicleScript:getPartCount() - 1 do
        local partId = vehicleScript:getPart(i):getId()
        if distribution.Normal[partId] then
            total = total + expectedHits(function()
                Finds.addCrackedModules(roomName, partId, partContainer(zoneName, partId))
            end)
        end
    end
    return total
end

-- What the vehicles of `stalls` hold, arrow boards included, and how many arrow boards they are.
local function vehicleFinds(stalls, kinds)
    local arrowBoard = ArrowBoard.SCRIPT
    local total, arrowBoards, loot = none(), 0, {}
    for zoneName, count in pairs(stalls) do
        for script, perStall in pairs(zoneVehicles(zoneName)) do
            local vehicles = count * perStall
            if script == arrowBoard then
                arrowBoards = arrowBoards + vehicles
                add(total, kinds.arrowBoard, vehicles)
            else
                if not loot[script] then
                    loot[script] = add(none(), kinds.intact, vehicleExpected(script, MODULE))
                    for _, fullType in ipairs(LOOSE_BATTERIES) do
                        add(loot[script], batteriesOf(fullType, vehicleExpected(script, fullType)))
                    end
                    for _, fullType in ipairs(PART_TYPES) do
                        loot[script][fullType] = vehicleExpected(script, fullType)
                    end
                end
                add(total, loot[script], vehicles)
                add(total, kinds.cracked, vehicles * vehicleCrackedModules(script, zoneName))
            end
        end
    end
    return total, arrowBoards
end

-- What a site holds once placed: its panels' modules, its bank's batteries and its arrow board.
local function siteFinds(site, kinds)
    local SolarSites = require "RenewableEnergy/World/SolarSites"
    local kind = SolarSites.KINDS[site.kind]
    local total = none()
    if kind.panels then
        local placedPanels = (kind.panels.min + math.min(kind.panels.max, #site.panels)) / 2
        local moduleSum = 0
        for _, panel in ipairs(site.panels) do
            local mount = SolarSites.mountKind(panel[4])
            moduleSum = moduleSum + (kind.modules and midpoint(kind.modules) or Specs.mounts[mount].modules)
        end
        add(total, kinds.site, placedPanels * moduleSum / #site.panels)
    end
    local stock = site.bank and (kind.bank or kind.wind)
    if stock then
        add(total, kinds.banks[stock])
    end
    if site.arrowBoard then
        add(total, kinds.arrowBoard)
    end
    return total
end

local function siteSpot(site)
    local spot = (site.panels and site.panels[1]) or site.bank or site.arrowBoard or site.generator
    return spot[1], spot[2]
end

local function inTown(town, x, y)
    return x >= town.x1 and x <= town.x2 and y >= town.y1 and y <= town.y2
end

-- Yardsticks ------------------------------------------------------------------------------------

local CLEAR_ONLY = { { 1, Sun.CLEAR_WEATHER } }
-- The 15th of July and of December, as days of the year.
local MONTH_DAYS = { july = 196, december = 349 }
-- Hours between the sun's positions a day is added up over.
local SUN_STEP = 0.5

-- Watt-hours a factory module at full condition on `mount` banks over the day `dayOfYear` under
-- `weather` (Yardsticks.WEATHER_MIX's shape) at the save's latitude and Sunlight Multiplier.
-- Sun.wattsFrom is proportional to the light, so it takes the day's light at once.
local function moduleDayWh(dayOfYear, mount, weather)
    local latitude = getClimateManager():getSeason():getLat()
    local light = Yardsticks.dayIrradiance(dayOfYear, mount, weather, latitude, SUN_STEP)
    return Sun.wattsFrom(Specs.modules[MODULE].watts, light, 0)
end

-- Wind chargers in the order the wind yardstick lists them, with the names players know them by.
local WIND_KINDS = {
    { "scoop", "scoop rotor" }, { "propeller", "treadmill wind charger" },
    { "carAlternator", "car alternator wind charger" }, { "alternator", "homebuilt wind turbine" },
}
local MONTH_LENGTHS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
-- Years of the game's wind the yardstick averages: its noise wanders over weeks, so one July
-- can be still and the next one gusty.
local WIND_YEARS = 10

-- The game's wind each hour of WIND_YEARS years from the save's, in km/h, by month (1 to 12):
-- ClimateValues.pollDate's wind intensity × 120 (ClimateManager.getWindspeedKph). That leaves out
-- the wind a weather front's storm adds while it blows, so it reads low.
local function windByMonth()
    local values = getClimateManager():getClimateValuesCopy()
    local first = getGameTime():getYear()
    local months = {}
    for month = 1, 12 do
        local hours = {}
        for year = first, first + WIND_YEARS - 1 do
            for day = 1, MONTH_LENGTHS[month] do
                for hour = 0, 23 do
                    values:pollDate(year, month - 1, day, hour)
                    table.insert(hours, values:getWindIntensity() * 120)
                end
            end
        end
        months[month] = hours
    end
    return months
end

-- The mean of `list`, each value through of(value) if given.
local function mean(list, of)
    local total = 0
    for _, value in ipairs(list) do
        total = total + (of and of(value) or value)
    end
    return total / #list
end

-- Prints under `mark` the watts each wind charger averages on open ground, standing on the ground,
-- in July, December and over the year.
local function printWindYardsticks(mark)
    local months = windByMonth()
    local year = {}
    for _, hours in ipairs(months) do
        for _, kph in ipairs(hours) do
            table.insert(year, kph)
        end
    end
    print(string.format("%s yardstick: the game's wind, storms left out, averages %.1f km/h in July, %.1f in December, %.1f over the year",
        mark, mean(months[7]), mean(months[12]), mean(year)))
    local function dayKwh(watts) return watts * 24 / 1000 end
    for _, row in ipairs(WIND_KINDS) do
        local spec = Wind.SPEC.turbines[row[1]]
        local function watts(value) return Wind.watts(spec, value, 0, 0) end
        local july, december, average = mean(months[7], watts), mean(months[12], watts), mean(year, watts)
        print(string.format("%s yardstick: a %s (%.0f W at %d km/h, %d input slots) on open ground averages %.0f W (%.1f kWh a day) in July, %.0f W (%.1f) in December, %.0f W (%.1f) over the year at Wind Multiplier %.2f",
            mark, row[2], Wind.ratedWatts(spec), spec.ratedKph, spec.slots, july, dayKwh(july), december, dayKwh(december),
            average, dayKwh(average), SandboxVars.RenewableEnergy.WindMultiplier))
    end
end

-- Each kind of battery a bank holds; the three car batteries are alike, so one stands for them.
local LIFE_BATTERIES = { "Base.CarBattery1", "RenewableEnergy.JarBattery", "RenewableEnergy.DeepCycleBattery",
    "RenewableEnergy.L16Battery" }

-- Nights a new battery of `fullType` takes to fall to half capacity carrying a load of `depth` of
-- its new capacity every night, worn as a bank wears it (Battery.cycleWear at the Battery Wear
-- option): the same load is a deeper share of what a worn battery holds. nil if wear is off.
local function nightsToHalf(fullType, depth)
    local scale = Battery.wearScale()
    if scale <= 0 then
        return nil
    end
    local item = instanceItem(fullType)
    local full = item:getConditionMax()
    local nights = 0
    while item:getCondition() > full / 2 do
        Battery.wear(item, Battery.cycleWear(item, math.min(1, depth * full / item:getCondition())) * scale)
        nights = nights + 1
    end
    return nights
end

-- Prints under `mark` what turns the finds into hours, and returns the average watt-hours a new
-- module banks on a south rack in a day of each of MONTH_DAYS.
local function printYardsticks(mark)
    local options = SandboxVars.RenewableEnergy
    local rackWh = {}
    for _, month in ipairs({ "july", "december" }) do
        local wh = {}
        for name, mount in pairs(Yardsticks.SOUTH_MOUNTS) do
            wh[name] = { average = moduleDayWh(MONTH_DAYS[month], mount, Yardsticks.WEATHER_MIX),
                clear = moduleDayWh(MONTH_DAYS[month], mount, CLEAR_ONLY) }
        end
        rackWh[month] = wh.rack.average
        print(string.format("%s yardstick: a new module banks a day in mid-%s, average (clear): flat %.0f (%.0f), south rack %.0f (%.0f), south wall %.0f (%.0f) Wh at Sunlight Multiplier %.2f",
            mark, month, wh.flat.average, wh.flat.clear, wh.rack.average, wh.rack.clear, wh.wall.average, wh.wall.clear,
            options.SunlightMultiplier))
    end
    local appliances = {}
    for name in pairs(Yardsticks.APPLIANCE_FUEL) do
        table.insert(appliances, string.format("%s %.0f", name, Yardsticks.applianceWatts(name)))
    end
    table.sort(appliances)
    print(mark .. " yardstick: appliance watts as a bank bills them: " .. table.concat(appliances, ", "))
    printWindYardsticks(mark)
    local function years(nights) return nights and string.format("%.1f", nights / 365) or "never" end
    local lives = {}
    for _, fullType in ipairs(LIFE_BATTERIES) do
        table.insert(lives, string.format("%s %s (%s)", fullType:match("[^.]+$"), years(nightsToHalf(fullType, 0.5)),
            years(nightsToHalf(fullType, 0.25))))
    end
    print(string.format("%s yardstick: years a new battery lasts to half capacity under a nightly load of half (a quarter) its new capacity, at Battery Wear %d%%: %s",
        mark, options.BatteryWear, table.concat(lives, ", ")))
    return rackWh
end

-- Report -----------------------------------------------------------------------------------------

-- The row parts a town's total sums.
local PARTS = { "listed", "cracked", "crates", "banks", "vehicles", "sites" }

-- Modules as "count (watts as found / repaired)".
local function modulesText(finds)
    local watts = Specs.modules[MODULE].watts / 100
    return string.format("%.1f (%.0f / %.0f W)", finds.modules, finds.condition * watts, finds.repaired * watts)
end

-- Batteries as "count (kWh as found)".
local function batteriesText(finds)
    return string.format("%.1f (%.1f kWh)", finds.batteries, finds.wh / 1000)
end

-- Prints under `mark` how many of each of PART_TYPES the town holds on average, with its
-- PART_SOURCES largest sources: room loot by room name, world banks, garage kit crates, vehicles
-- (arrow boards' battery boxes included) and sites. `row` is the town's report row.
local function printParts(mark, town, row)
    for _, fullType in ipairs(PART_TYPES) do
        local sources = expectedInTownByRoom(town, fullType)
        sources["world banks"] = row.banks[fullType]
        sources["garage kit crates"] = row.crates[fullType]
        sources.vehicles = row.vehicles[fullType]
        sources.sites = row.sites[fullType]
        local total, ranked = 0, {}
        for source, count in pairs(sources) do
            if count > 0 then
                total = total + count
                table.insert(ranked, { source = source, count = count })
            end
        end
        table.sort(ranked, function(a, b) return a.count > b.count end)
        local largest = {}
        for i = 1, math.min(PART_SOURCES, #ranked) do
            table.insert(largest, string.format("%s %.2f", ranked[i].source, ranked[i].count))
        end
        print(string.format("%s %s in %s: %.1f; most from %s", mark, (string.gsub(fullType, "^[^.]+%.", "")),
            town.name, total, table.concat(largest, ", ")))
    end
end

-- What the rooms named `roomNames` of `town` hold altogether, room loot and what OnSeeNewRoom
-- places alike: `modules`, `batteries` (deep cycles and L-16s, a bank's car batteries too) and
-- each of PART_TYPES by full type.
local function roomsHold(town, roomNames, kinds)
    local total = none()
    for _, roomName in ipairs(roomNames) do
        local rooms = town.rooms[roomName] or 0
        local function inLoot(fullType)
            return expectedInRooms(roomName, town.containers[roomName] or {}, rooms, fullType)
        end
        total.modules = total.modules + inLoot(MODULE)
        for _, fullType in ipairs(LOOSE_BATTERIES) do
            total.batteries = total.batteries + inLoot(fullType)
        end
        for _, fullType in ipairs(PART_TYPES) do
            total[fullType] = (total[fullType] or 0) + inLoot(fullType)
        end
        local spawns = roomSpawns(roomName, rooms, kinds)
        if spawns then
            add(total, spawns.bankFinds)
            add(total, spawns.crates)
        end
    end
    return total
end

-- Prints under `mark` what `total` holds over `count` of `what`, as each item's count per one and
-- how many it takes on average to find one.
local function printPerOne(mark, what, count, total)
    local parts = {}
    local keys = { "modules", "batteries" }
    for _, fullType in ipairs(PART_TYPES) do
        table.insert(keys, fullType)
    end
    for _, key in ipairs(keys) do
        local each = (total[key] or 0) / count
        if each > 0.0005 then
            table.insert(parts, string.format("%s %.3f (1 in %.0f)", (string.gsub(key, "^[^.]+%.", "")), each, 1 / each))
        end
    end
    print(string.format("%s per %s (%d): %s", mark, what, count, table.concat(parts, ", ")))
end

-- Prints under `mark` what a home of the whole map holds on average, and one of each of
-- VISIT_ROOMS.
local function printPerVisit(mark, map, kinds)
    printPerOne(mark, "home", map.rooms.kitchen, roomsHold(map, HOME_ROOMS, kinds))
    for _, roomName in ipairs(VISIT_ROOMS) do
        local rooms = map.rooms[roomName] or 0
        if rooms > 0 then
            printPerOne(mark, roomName, rooms, roomsHold(map, { roomName }, kinds))
        end
    end
end

--- Prints the report under `mark`, with what world banks, crates and battery boxes hold from
--- `stocks` (RenewableEnergyLoot's sampleWorldStocks with a `finds` reader of TownReport.findsIn).
--- The caller sets the measuring options (RenewableEnergyLoot's MEASURE_OPTIONS) and loot rarity
--- options 1.
function TownReport.print(mark, stocks)
    local census = require "RenewableEnergyDevTownCensus"
    local SolarSites = require "RenewableEnergy/World/SolarSites"
    local options = SandboxVars.RenewableEnergy
    local kinds = findKinds(stocks)
    local sites, siteBoards = {}, 0
    print(mark .. " modules a thorough player finds, as count (watts as found / after Seal Cracked Module), and batteries, as count (kWh as found)")
    print(string.format("%s Battery Bank Spawn %d, Solar Sites %d%%", mark, options.BatteryBankSpawn, options.SolarSites))
    for _, site in ipairs(SolarSites.sites()) do
        local entry = { site = site, finds = siteFinds(site, kinds), chance = SolarSites.siteChance(site) }
        table.insert(sites, entry)
        if site.arrowBoard then
            siteBoards = siteBoards + entry.chance
        end
        print(string.format("%s site %s (%s) when placed: modules %s, batteries %s; %.0f%% of worlds", mark, site.name,
            site.kind, modulesText(entry.finds), batteriesText(entry.finds), entry.chance * 100))
    end
    local rows, zoneBoards = {}, 0
    for _, town in ipairs(census.towns) do
        local row = roomFinds(town, kinds)
        -- The census's last town is the whole map.
        row.vehicles, zoneBoards = vehicleFinds(town.vehicleStalls, kinds)
        row.sites = none()
        for _, entry in ipairs(sites) do
            if inTown(town, siteSpot(entry.site)) then
                add(row.sites, entry.finds, entry.chance)
            end
        end
        row.total = none()
        for _, part in ipairs(PARTS) do
            add(row.total, row[part])
        end
        rows[town.name] = row
        print(string.format("%s modules in %s: room loot %s, cracked %s, garage kit crates %s, beside world banks %s, vehicles %s, sites %s; total %s",
            mark, town.name, modulesText(row.listed), modulesText(row.cracked), modulesText(row.crates), modulesText(row.banks),
            modulesText(row.vehicles), modulesText(row.sites), modulesText(row.total)))
        local banks, byRoom = 0, {}
        for roomName, placed in pairs(row.banksByRoom) do
            banks = banks + placed
            table.insert(byRoom, string.format("%s %.1f", roomName, placed))
        end
        table.sort(byRoom)
        print(string.format("%s batteries in %s: room loot %s, world banks %.1f holding %s, garage kit crates %s, vehicles %s, sites %s; total %s; car batteries in room loot %.1f",
            mark, town.name, batteriesText(row.listed), banks, batteriesText(row.banks), batteriesText(row.crates),
            batteriesText(row.vehicles), batteriesText(row.sites), batteriesText(row.total), row.cars))
        print(string.format("%s world banks in %s by room: %s", mark, town.name, table.concat(byRoom, ", ")))
        printParts(mark, town, row)
    end
    print(string.format("%s arrow boards per map: %.1f from vehicle zones, %.1f at sites", mark, zoneBoards, siteBoards))
    printPerVisit(mark, census.towns[#census.towns], kinds)
    local stocks = {}
    for name in pairs(kinds.banks) do
        table.insert(stocks, name)
    end
    table.sort(stocks)
    for _, name in ipairs(stocks) do
        print(string.format("%s batteries in a %s bank: %s", mark, name, batteriesText(kinds.banks[name])))
    end
    local rackWh = printYardsticks(mark)
    for _, town in ipairs(census.towns) do
        local total = rows[town.name].total
        local newModules = total.condition / 100
        print(string.format("%s power in %s: batteries store %.1f kWh; modules as found are %.1f new ones, banking %.1f kWh a day on south racks in July, %.1f in December",
            mark, town.name, total.wh / 1000, newModules, newModules * rackWh.july / 1000, newModules * rackWh.december / 1000))
    end
end

return TownReport
