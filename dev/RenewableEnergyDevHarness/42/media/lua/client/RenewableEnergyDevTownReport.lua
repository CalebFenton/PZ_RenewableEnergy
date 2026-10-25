-- Development only; the --loot mode (RenewableEnergyDevHarness.lua) prints these reports. The
-- modules and batteries a thorough player finds in each town of RenewableEnergyDevTownCensus,
-- and the yardsticks that turn them into power. Client Lua: it reads WorldSpawns, SolarSites and
-- ArrowBoard as they run, which a single player game, the only one --loot runs, has.

require "RenewableEnergy/Recipes"
require "RenewableEnergy/Sun"
require "RenewableEnergy/Debug/RenewableEnergyLoot"

local Loot = RenewableEnergy.Loot
local TownReport = {}

-- Module-watts report ------------------------------------------------------------------------------
-- How many solar modules a thorough player finds in a town, with their summed condition, which
-- --loot turns into watts: dev/loot/census.py's counts of the town's container tiles, rooms and
-- vehicle stalls, each times its expected modules, plus the world crates of its rooms and the
-- solar sites in its bounds. Expectations come from the loot tables' weights the way the game
-- rolls them (ItemPickerJava.getActualSpawnChance), so the report is exact for the lists and
-- approximate where the game picks among them: a procedural container picks a list by
-- weightChance, at most `max` per room, and lists forced by zone, tile or room are left out.
-- "Repaired" is after one Seal Cracked Module on every module it helps.

local MODULE = RenewableEnergy.Specs.factoryModule

-- Adds every figure of `part`, `times` over if given, to `total`, and returns it.
local function add(total, part, times)
    for key, value in pairs(part) do
        total[key] = (total[key] or 0) + value * (times or 1)
    end
    return total
end

-- A count of modules with their condition summed over them, as found and as repaired.
local function haul(count, condition, repaired)
    return { count = count, condition = condition, repaired = repaired }
end

local function emptyHaul()
    return haul(0, 0, 0)
end

-- The mean of a { min, max } range whose every whole number is as likely.
local function midpoint(range)
    return (range.min + range.max) / 2
end

-- One module whose condition is uniform over the range: { count = 1, condition, repaired }. A
-- scratch module takes each condition, so Seal Cracked Module's own test and result price it.
local function moduleOver(range)
    local Recipes = RenewableEnergy.Recipes
    local module = instanceItem(MODULE)
    local sum, repairedSum, n = 0, 0, 0
    for condition = range.min, range.max do
        RenewableEnergy.Wear.setCondition(module, condition)
        sum = sum + condition
        repairedSum = repairedSum + (Recipes.isModuleBelowRepairCap(module) and Recipes.repairedCondition(module) or condition)
        n = n + 1
    end
    return haul(1, sum / n, repairedSum / n)
end

-- One module that is `a` with chance `share`, else `b`.
local function mix(share, a, b)
    return haul(1, share * a.condition + (1 - share) * b.condition, share * a.repaired + (1 - share) * b.repaired)
end

local function moduleKinds()
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local cracked, weathered = moduleOver(WorldSpawns.CRACKED), moduleOver(WorldSpawns.WEATHERED)
    return {
        intact = haul(1, 100, 100),
        cracked = cracked,
        weathered = weathered,
        site = mix(WorldSpawns.SITE_CRACKED_SHARE, cracked, weathered),
        secondOnArrowBoard = mix(RenewableEnergy.ArrowBoard.STOCK.secondCrackedChance, cracked, weathered),
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

-- Expected items of `fullType` in `count` containers of `containerType` spread over `rooms` rooms
-- named `roomName`.
local function expectedInContainers(roomName, containerType, count, rooms, fullType)
    local room = SuburbsDistributions[roomName]
    local entry = room and room[containerType] or SuburbsDistributions.all[containerType]
    if type(entry) ~= "table" then
        return 0
    end
    if not entry.procedural then
        return count * expectedIn(entry, fullType)
    end
    local procList = entry.procList or {}
    local totalWeight = 0
    for _, pick in ipairs(procList) do
        if not isForced(pick) then
            totalWeight = totalWeight + pickWeight(pick)
        end
    end
    local perRoom = count / rooms
    local total = 0
    for _, pick in ipairs(procList) do
        local list = ProceduralDistributions.list[pick.name]
        if not isForced(pick) and list then
            local picked = perRoom * pickWeight(pick) / totalWeight
            total = total + rooms * math.min(picked, pick.max or picked) * expectedIn(list, fullType)
        end
    end
    return total
end

-- Expected items of `fullType` in the room loot of a town of the census.
local function expectedInTown(town, fullType)
    local total = 0
    for roomName, byType in pairs(town.containers) do
        local rooms = math.max(1, town.rooms[roomName] or 0)
        for containerType, count in pairs(byType) do
            total = total + expectedInContainers(roomName, containerType, count, rooms, fullType)
        end
    end
    return total
end

-- Expected count of a CRATE_STOCK line, as WorldSpawns.stockCrate rolls and scales it.
local function crateLineCount(line)
    return (line[2] + line[3]) / 2 * (line[4] and SandboxVars.RenewableEnergy[line[4]] or 1)
end

-- Expected modules in a world crate stocked from WorldSpawns.CRATE_STOCK[name].
local function crateModules(name)
    local modules = 0
    for _, line in ipairs(RenewableEnergy.WorldSpawns.CRATE_STOCK[name]) do
        if line[1] == MODULE then
            modules = modules + crateLineCount(line)
        end
    end
    return modules
end

-- What WorldSpawns' OnSeeNewRoom puts in a town's rooms on average: `banks`, by BANK_ROOMS room
-- name, { placed, stock }; and `crates`, which it stocks as kits. None with Battery Bank Spawn off.
local function roomSpawns(town)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local spawns = { banks = {}, crates = 0 }
    local rarity = WorldSpawns.RARITY[SandboxVars.RenewableEnergy.BatteryBankSpawn]
    if rarity then
        for roomName, bank in pairs(WorldSpawns.BANK_ROOMS) do
            spawns.banks[roomName] = { placed = (town.rooms[roomName] or 0) / (bank.odds * rarity), stock = bank.stock }
        end
        for roomName, odds in pairs(WorldSpawns.CRATE_ROOMS) do
            spawns.crates = spawns.crates + (town.rooms[roomName] or 0) / (odds * rarity)
        end
    end
    return spawns
end

-- What the rooms of a town hold: list modules (whole), cracked modules, world crates, and the
-- modules beside the world banks that lay them (WorldSpawns.layModulesBeside).
local function roomsHaul(town, kinds)
    local Distributions, WorldSpawns = RenewableEnergy.Distributions, RenewableEnergy.WorldSpawns
    local cracked, besideBanks = 0, 0
    for roomName, byType in pairs(town.containers) do
        for containerType, count in pairs(byType) do
            local weight = Distributions.crackedModuleRoomWeight(roomName, containerType)
            if weight > 0 then
                cracked = cracked + count * Distributions.crackedModuleChance(weight)
            end
        end
    end
    local spawns = roomSpawns(town)
    for _, bank in pairs(spawns.banks) do
        local spec = WorldSpawns.BANK_STOCK[bank.stock].modules
        if spec then
            besideBanks = besideBanks + bank.placed * spec.chance * midpoint(spec) * SandboxVars.RenewableEnergy.LRMSolarPanels
        end
    end
    return {
        listed = add(emptyHaul(), kinds.intact, expectedInTown(town, MODULE)),
        cracked = add(emptyHaul(), kinds.cracked, cracked),
        crates = add(emptyHaul(), kinds.site, spawns.crates * crateModules("kit")),
        besideBanks = add(emptyHaul(), kinds.site, besideBanks),
    }
end

-- An arrow board's modules: as many as the panel rarity option gives, one a panel at most.
local function arrowBoardHaul(kinds)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local total = emptyHaul()
    local modules = math.min(#ArrowBoard.PANELS, ArrowBoard.STOCK.modules * SandboxVars.RenewableEnergy.LRMSolarPanels)
    add(total, kinds.weathered, math.min(1, modules))
    add(total, kinds.secondOnArrowBoard, math.max(0, modules - 1))
    return total
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

-- The cracked modules one vehicle of the script holds in the vehicle zone `zoneName`: each of its
-- containers that BaseVehicle.randomizeContainers fills rolls Distributions.addCrackedModules
-- once. A part counts as a container when the script's loot names it, which leaves out its doors.
local function vehicleCrackedModules(script, zoneName)
    local Distributions = RenewableEnergy.Distributions
    local distribution = distributionOf(script)
    local vehicleScript = getScriptManager():getVehicle(script)
    if not (distribution and distribution.Normal and vehicleScript) then
        return 0
    end
    local total = 0
    for i = 0, vehicleScript:getPartCount() - 1 do
        local partId = vehicleScript:getPart(i):getId()
        if distribution.Normal[partId] then
            total = total + Distributions.crackedModuleChance(Distributions.crackedModuleVehicleWeight(zoneName, partId))
        end
    end
    return total
end

local function vehiclesHaul(stalls, kinds)
    local arrowBoard = RenewableEnergy.ArrowBoard.SCRIPT
    local total, arrowBoards = emptyHaul(), 0
    local cache = {}
    for zoneName, count in pairs(stalls) do
        for script, perStall in pairs(zoneVehicles(zoneName)) do
            local vehicles = count * perStall
            if script == arrowBoard then
                arrowBoards = arrowBoards + vehicles
                add(total, arrowBoardHaul(kinds), vehicles)
            else
                cache[script] = cache[script] or vehicleExpected(script, MODULE)
                add(total, kinds.intact, vehicles * cache[script])
                add(total, kinds.cracked, vehicles * vehicleCrackedModules(script, zoneName))
            end
        end
    end
    return total, arrowBoards
end

local function siteSpot(site)
    local spot = (site.panels and site.panels[1]) or site.bank or site.arrowBoard or site.generator
    return spot[1], spot[2]
end

-- Expected modules of a site once placed.
local function siteHaul(site, kinds)
    local SolarSites = RenewableEnergy.SolarSites
    local kind = SolarSites.KINDS[site.kind]
    local total = emptyHaul()
    if kind.panels then
        local placedPanels = (kind.panels.min + math.min(kind.panels.max, #site.panels)) / 2
        local moduleSum = 0
        for _, panel in ipairs(site.panels) do
            local mount = SolarSites.mountKind(panel[4])
            moduleSum = moduleSum + (kind.modules and midpoint(kind.modules) or RenewableEnergy.Specs.mounts[mount].modules)
        end
        add(total, kinds.site, placedPanels * moduleSum / #site.panels)
    end
    if kind.crate then
        add(total, kinds.site, crateModules(kind.crate))
    end
    if site.arrowBoard then
        add(total, arrowBoardHaul(kinds))
    end
    return total
end

local function inTown(town, x, y)
    return x >= town.x1 and x <= town.x2 and y >= town.y1 and y <= town.y2
end

-- A row for each town of the census: rowOf(town) with the town's `name`, `sites`, the hauls of
-- `sites` ({ site, haul, chance }) in the town at their chance, and `total`, the sum of the row's
-- parts named in `partNames`. zero() makes an empty haul.
local function townRows(census, sites, rowOf, zero, partNames)
    local rows = {}
    for _, town in ipairs(census.towns) do
        local row = rowOf(town)
        row.name = town.name
        row.sites = zero()
        for _, entry in ipairs(sites) do
            if inTown(town, siteSpot(entry.site)) then
                add(row.sites, entry.haul, entry.chance)
            end
        end
        row.total = zero()
        for _, name in ipairs(partNames) do
            add(row.total, row[name])
        end
        table.insert(rows, row)
    end
    return rows
end

-- build(census) at the default loot settings and loot rarity options 1.
local function atDefaultLoot(build, census)
    return PZHarness.Loot.withMeasureOptions(Loot.MEASURE_OPTIONS, function()
        return Loot.withLootRarity(1, function()
            return build(census)
        end)
    end)
end

local function buildModuleReport(census)
    local SolarSites = RenewableEnergy.SolarSites
    local kinds = moduleKinds()
    local report = { sites = {} }
    for _, site in ipairs(SolarSites.sites()) do
        table.insert(report.sites, { name = site.name, kind = site.kind, haul = siteHaul(site, kinds), site = site,
            chance = SolarSites.siteChance(site) })
    end
    report.towns = townRows(census, report.sites, function(town)
        local row = roomsHaul(town, kinds)
        row.vehicles, row.arrowBoards = vehiclesHaul(town.vehicleStalls, kinds)
        return row
    end, emptyHaul, { "listed", "cracked", "crates", "besideBanks", "vehicles", "sites" })
    local siteBoards = 0
    for _, entry in ipairs(report.sites) do
        if entry.site.arrowBoard then
            siteBoards = siteBoards + entry.chance
        end
    end
    -- The census's last town is the whole map.
    report.arrowBoards = { zones = report.towns[#report.towns].arrowBoards, sites = siteBoards }
    return report
end

--- The module report: for each town of the census, { name, listed, cracked, crates, besideBanks, vehicles,
--- sites, total } hauls ({ count, condition, repaired }, condition summed over the modules);
--- `sites`, each { name, kind, haul, chance }, the haul once placed; `arrowBoards`, the expected
--- number on the map, { zones, sites }. At the default loot settings and loot rarity
--- options 1.
function TownReport.moduleReport(census)
    return atDefaultLoot(buildModuleReport, census)
end

-- Battery report ---------------------------------------------------------------------------------
-- How many batteries a thorough player finds in a town, and their watt-hours as found, from the
-- same census as the module report: the mod's deep cycles and L-16s in room loot and vehicles
-- (whole, as loot spawns them), the world banks and kit crates WorldSpawns' OnSeeNewRoom puts in
-- rooms (each room kind's count over its odds), the solar sites in the town, and arrow boards. Car
-- batteries in room loot are counted apart: vanilla's, and every car carries one besides.

local LOOSE_BATTERIES = { "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery" }
local CAR_BATTERIES = { "Base.CarBattery1", "Base.CarBattery2", "Base.CarBattery3" }

local function batteries(count, wh)
    return { count = count, wh = wh }
end

local function noBatteries()
    return batteries(0, 0)
end

local function batteryWh(fullType)
    return RenewableEnergy.Specs.batteries[fullType].wh
end

-- Rolls per side of the grid wearShare averages the three wear rolls over.
local WEAR_GRID = 20

-- The mean share of full condition the BATTERY_WEAR profile `wearName` leaves a battery, duds
-- included: WorldSpawns.foundPercent averaged over a grid of midpoints of its three rolls.
local function wearShare(wearName)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local wear, dud = WorldSpawns.BATTERY_WEAR[wearName], WorldSpawns.DUD
    local sum = 0
    for a = 0, WEAR_GRID - 1 do
        for b = 0, WEAR_GRID - 1 do
            for c = 0, WEAR_GRID - 1 do
                sum = sum + WorldSpawns.foundPercent(wear, (a + 0.5) / WEAR_GRID, (b + 0.5) / WEAR_GRID,
                    (c + 0.5) / WEAR_GRID)
            end
        end
    end
    local chance = wear.dud or 0
    return ((1 - chance) * sum / WEAR_GRID ^ 3 + chance * midpoint(dud)) / 100
end

-- The batteries a bank stocked as BANK_STOCK[stockName] holds on average.
local function stockBatteries(stockName)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local stock = WorldSpawns.BANK_STOCK[stockName]
    local cap = RenewableEnergy.PowerBank.bankOfSprite(RenewableEnergy.Sprites[stock.sprite].S).spec.maxBatteries
    local counts, count = 0, 0
    for rolled = stock.batteries.min, stock.batteries.max do
        count = count + math.min(cap, rolled * SandboxVars.RenewableEnergy.LRMBatteries)
        counts = counts + 1
    end
    count = count / counts
    local weights, wh = 0, 0
    for _, entry in ipairs(stock.batteries.types) do
        weights = weights + entry[2]
        wh = wh + entry[2] * batteryWh(entry[1])
    end
    return batteries(count, count * wh / weights * wearShare(stock.batteries.wear))
end

-- The batteries a world crate stocked from CRATE_STOCK[name] holds on average.
local function crateBatteries(name)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local total = noBatteries()
    for _, line in ipairs(WorldSpawns.CRATE_STOCK[name]) do
        if RenewableEnergy.Specs.batteries[line[1]] then
            local count = crateLineCount(line)
            add(total, batteries(count, count * batteryWh(line[1]) * wearShare(WorldSpawns.CRATE_WEAR)))
        end
    end
    return total
end

-- An arrow board's battery box on average: its count, worn from years on the road.
local function arrowBoardBatteries()
    local stock = RenewableEnergy.ArrowBoard.STOCK
    local count = midpoint(stock.batteries) * SandboxVars.RenewableEnergy.LRMBatteries
    local condition = midpoint(stock.batteryCondition) / 100
    return batteries(count, count * batteryWh(stock.battery) * condition)
end

-- What the rooms of a town hold: the mod's batteries in room loot, car batteries in room loot,
-- world banks (with how many) and kit crates.
local function roomsBatteries(town)
    local listed, cars = noBatteries(), 0
    for _, fullType in ipairs(LOOSE_BATTERIES) do
        local found = expectedInTown(town, fullType)
        add(listed, batteries(found, found * batteryWh(fullType)))
    end
    for _, fullType in ipairs(CAR_BATTERIES) do
        cars = cars + expectedInTown(town, fullType)
    end
    local spawns = roomSpawns(town)
    local banks, bankCount, banksByRoom = noBatteries(), 0, {}
    for roomName, bank in pairs(spawns.banks) do
        bankCount = bankCount + bank.placed
        banksByRoom[roomName] = bank.placed
        add(banks, stockBatteries(bank.stock), bank.placed)
    end
    return { listed = listed, cars = cars, banks = banks, bankCount = bankCount, banksByRoom = banksByRoom,
        crates = add(noBatteries(), crateBatteries("kit"), spawns.crates) }
end

-- The mod's batteries in the vehicles of `stalls`, arrow boards' boxes included.
local function vehiclesBatteries(stalls)
    local arrowBoard = RenewableEnergy.ArrowBoard.SCRIPT
    local total, cache = noBatteries(), {}
    for zoneName, count in pairs(stalls) do
        for script, perStall in pairs(zoneVehicles(zoneName)) do
            local vehicles = count * perStall
            if script == arrowBoard then
                add(total, arrowBoardBatteries(), vehicles)
            else
                for _, fullType in ipairs(LOOSE_BATTERIES) do
                    local key = script .. fullType
                    cache[key] = cache[key] or vehicleExpected(script, fullType)
                    add(total, batteries(cache[key], cache[key] * batteryWh(fullType)), vehicles)
                end
            end
        end
    end
    return total
end

-- The batteries of a site once placed: its bank, its crate and its arrow board's box.
local function siteBatteries(site)
    local kind = RenewableEnergy.SolarSites.KINDS[site.kind]
    local total = noBatteries()
    local stock = site.bank and (kind.bank or kind.wind)
    if stock then
        add(total, stockBatteries(stock))
    end
    if kind.crate then
        add(total, crateBatteries(kind.crate))
    end
    if site.arrowBoard then
        add(total, arrowBoardBatteries())
    end
    return total
end

local function buildBatteryReport(census)
    local sites = {}
    local SolarSites = RenewableEnergy.SolarSites
    for _, site in ipairs(SolarSites.sites()) do
        table.insert(sites, { site = site, haul = siteBatteries(site), chance = SolarSites.siteChance(site) })
    end
    local report = {}
    report.towns = townRows(census, sites, function(town)
        local row = roomsBatteries(town)
        row.vehicles = vehiclesBatteries(town.vehicleStalls)
        return row
    end, noBatteries, { "listed", "banks", "crates", "vehicles", "sites" })
    report.stocks = {}
    for name in pairs(RenewableEnergy.WorldSpawns.BANK_STOCK) do
        report.stocks[name] = stockBatteries(name)
    end
    return report
end

--- The battery report: for each town of the census, { name, listed, banks, crates, vehicles,
--- sites, total } batteries ({ count, wh }, wh as found), `bankCount`, the world banks, and
--- `banksByRoom` them by room name, `cars`, car batteries in room loot; and `stocks`, each
--- BANK_STOCK's batteries on average. At the default loot settings and loot rarity options 1.
function TownReport.batteryReport(census)
    return atDefaultLoot(buildBatteryReport, census)
end

-- Yardsticks ------------------------------------------------------------------------------------

local CLEAR_ONLY = { { 1, Loot.WEATHER_MIX[1][2] } }
-- The 15th of July and of December, as days of the year.
local MONTH_DAYS = { july = 196, december = 349 }

-- Watt-hours a factory module at full condition on `mount` banks over the day `dayOfYear` under
-- `mix`, in half-hour steps, at the save's Sunlight Multiplier.
local function moduleDayWh(dayOfYear, mount, mix)
    local Sun = RenewableEnergy.Sun
    local rated = RenewableEnergy.Specs.modules[MODULE].watts
    local latitude = getClimateManager():getSeason():getLat()
    local step, wh = 0.5, 0
    for hour = -12, 12 - step, step do
        local sun = Sun.position(dayOfYear, hour + step / 2, latitude)
        for _, part in ipairs(mix) do
            wh = wh + part[1] * Sun.wattsFrom(rated, Sun.planeIrradiance(sun, mount[1], mount[2], part[2]), 0) * step
        end
    end
    return wh
end

-- Each kind of battery a bank holds; the three car batteries are alike, so one stands for them.
local LIFE_BATTERIES = { "Base.CarBattery1", "RenewableEnergy.JarBattery", "RenewableEnergy.DeepCycleBattery",
    "RenewableEnergy.L16Battery" }

-- Nights a new battery of `fullType` takes to fall to half capacity carrying a load of `depth` of
-- its new capacity every night, worn as a bank wears it (Battery.cycleWear at the Battery Wear
-- option): the same load is a deeper share of what a worn battery holds. nil if wear is off.
local function nightsToHalf(fullType, depth)
    local Battery = RenewableEnergy.Battery
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

--- What turns the hauls into hours: `moduleWh[month][mount]`, { average, clear }, watt-hours a
--- day one new factory module banks mid-July and mid-December; `applianceW`, each appliance's
--- watts as a bank bills it; `sunlight`, the Sunlight Multiplier they assume; `batteryLife`, for
--- each of LIFE_BATTERIES in order, { fullType, half, quarter }, the nights it lasts to half
--- capacity under a nightly load of half and of a quarter its new capacity (nil with wear off);
--- `batteryWear`, the Battery Wear option they assume.
function TownReport.yardsticks()
    local moduleWh = {}
    for month, day in pairs(MONTH_DAYS) do
        moduleWh[month] = {}
        for name, mount in pairs(Loot.SOUTH_MOUNTS) do
            moduleWh[month][name] = { average = moduleDayWh(day, mount, Loot.WEATHER_MIX), clear = moduleDayWh(day, mount, CLEAR_ONLY) }
        end
    end
    local applianceW = {}
    for name in pairs(Loot.APPLIANCE_FUEL) do
        applianceW[name] = Loot.applianceWatts(name)
    end
    local batteryLife = {}
    for _, fullType in ipairs(LIFE_BATTERIES) do
        table.insert(batteryLife, { fullType = fullType, half = nightsToHalf(fullType, 0.5), quarter = nightsToHalf(fullType, 0.25) })
    end
    return { moduleWh = moduleWh, applianceW = applianceW, sunlight = SandboxVars.RenewableEnergy.SunlightMultiplier,
        batteryLife = batteryLife, batteryWear = SandboxVars.RenewableEnergy.BatteryWear }
end

return TownReport
