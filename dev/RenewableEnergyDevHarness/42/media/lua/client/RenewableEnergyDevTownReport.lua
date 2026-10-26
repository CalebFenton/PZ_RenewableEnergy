-- Development only; the --loot mode (RenewableEnergyDevHarness.lua) prints this report. The
-- modules and batteries a thorough player finds in each town of RenewableEnergyDevTownCensus,
-- and the yardsticks that turn them into power. Client Lua: it reads WorldSpawns, SolarSites and
-- ArrowBoard as they run, which a single player game, the only one --loot runs, has.
--
-- A town's finds are dev/loot/census.py's counts of its container tiles, rooms and vehicle stalls,
-- each times what it holds on average, plus what WorldSpawns' OnSeeNewRoom puts in its rooms
-- (each room kind's count over its odds) and the solar sites in its bounds. Expectations come
-- from the loot tables' weights the way the game rolls them (ItemPickerJava.getActualSpawnChance),
-- so they are exact for the lists and approximate where the game picks among them: a procedural
-- container picks a list by weightChance, at most `max` per room, and lists forced by zone, tile
-- or room are left out. Car batteries in room loot are counted apart: vanilla's, and every car
-- carries one besides.

require "RenewableEnergy/Recipes"
require "RenewableEnergy/Sun"
require "RenewableEnergy/Debug/RenewableEnergyLoot"

local Loot = RenewableEnergy.Loot
local TownReport = {}

local MODULE = RenewableEnergy.Specs.factoryModule
local LOOSE_BATTERIES = { "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery" }
local CAR_BATTERIES = { "Base.CarBattery1", "Base.CarBattery2", "Base.CarBattery3" }

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

local function batteryWh(fullType)
    return RenewableEnergy.Specs.batteries[fullType].wh
end

-- `count` batteries of `fullType` at `share` of full charge.
local function batteriesOf(fullType, count, share)
    return { batteries = count, wh = count * batteryWh(fullType) * (share or 1) }
end

-- One module whose condition is uniform over the range. A scratch module takes each condition, so
-- Seal Cracked Module's own test and result price it.
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
    return { modules = 1, condition = sum / n, repaired = repairedSum / n }
end

-- One module that is `a` with chance `share`, else `b`.
local function mix(share, a, b)
    return { modules = 1, condition = share * a.condition + (1 - share) * b.condition,
        repaired = share * a.repaired + (1 - share) * b.repaired }
end

-- An arrow board's modules, as many as the panel rarity option gives, one a panel at most, and
-- its battery box, worn from years on the road.
local function arrowBoardFinds(weathered, second)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local stock = ArrowBoard.STOCK
    local modules = math.min(#ArrowBoard.PANELS, stock.modules * SandboxVars.RenewableEnergy.LRMSolarPanels)
    local total = add(none(), weathered, math.min(1, modules))
    add(total, second, math.max(0, modules - 1))
    return add(total, batteriesOf(stock.battery, midpoint(stock.batteries) * SandboxVars.RenewableEnergy.LRMBatteries,
        midpoint(stock.batteryCondition) / 100))
end

local function findKinds()
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local cracked, weathered = moduleOver(WorldSpawns.CRACKED), moduleOver(WorldSpawns.WEATHERED)
    return {
        intact = { modules = 1, condition = 100, repaired = 100 },
        cracked = cracked,
        site = mix(WorldSpawns.SITE_CRACKED_SHARE, cracked, weathered),
        arrowBoard = arrowBoardFinds(weathered, mix(RenewableEnergy.ArrowBoard.STOCK.secondCrackedChance, cracked, weathered)),
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

-- A world crate stocked from WorldSpawns.CRATE_STOCK[name], each line as stockCrate rolls and
-- scales it.
local function crateFinds(name, kinds)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local total = none()
    for _, line in ipairs(WorldSpawns.CRATE_STOCK[name]) do
        local count = (line[2] + line[3]) / 2 * (line[4] and SandboxVars.RenewableEnergy[line[4]] or 1)
        if line[1] == MODULE then
            add(total, kinds.site, count)
        elseif RenewableEnergy.Specs.batteries[line[1]] then
            add(total, batteriesOf(line[1], count, wearShare(WorldSpawns.CRATE_WEAR)))
        end
    end
    return total
end

-- The batteries a bank stocked as BANK_STOCK[stockName] holds on average.
local function bankBatteries(stockName)
    local stock = RenewableEnergy.WorldSpawns.BANK_STOCK[stockName]
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
    return { batteries = count, wh = count * wh / weights * wearShare(stock.batteries.wear) }
end

-- What the rooms of a town hold: `listed`, the mod's items in room loot; `cracked`, cracked
-- modules; `banks`, the world banks OnSeeNewRoom places, their batteries and the modules they lay
-- beside them (WorldSpawns.layModulesBeside), `banksByRoom` how many by room name; `crates`, the
-- kit crates it places; and `cars`, car batteries in room loot. Banks and crates need Battery
-- Bank Spawn on.
local function roomFinds(town, kinds)
    local Distributions, WorldSpawns = RenewableEnergy.Distributions, RenewableEnergy.WorldSpawns
    local row = { listed = add(none(), kinds.intact, expectedInTown(town, MODULE)), cracked = none(), banks = none(),
        banksByRoom = {}, crates = none(), cars = 0 }
    for _, fullType in ipairs(LOOSE_BATTERIES) do
        add(row.listed, batteriesOf(fullType, expectedInTown(town, fullType)))
    end
    for _, fullType in ipairs(CAR_BATTERIES) do
        row.cars = row.cars + expectedInTown(town, fullType)
    end
    for roomName, byType in pairs(town.containers) do
        for containerType, count in pairs(byType) do
            local weight = Distributions.crackedModuleRoomWeight(roomName, containerType)
            if weight > 0 then
                add(row.cracked, kinds.cracked, count * Distributions.crackedModuleChance(weight))
            end
        end
    end
    local rarity = WorldSpawns.RARITY[SandboxVars.RenewableEnergy.BatteryBankSpawn]
    if rarity then
        for roomName, bank in pairs(WorldSpawns.BANK_ROOMS) do
            local placed = (town.rooms[roomName] or 0) / (bank.odds * rarity)
            row.banksByRoom[roomName] = placed
            add(row.banks, bankBatteries(bank.stock), placed)
            local beside = WorldSpawns.BANK_STOCK[bank.stock].modules
            if beside then
                add(row.banks, kinds.site, placed * beside.chance * midpoint(beside) * SandboxVars.RenewableEnergy.LRMSolarPanels)
            end
        end
        local kit = crateFinds("kit", kinds)
        for roomName, odds in pairs(WorldSpawns.CRATE_ROOMS) do
            add(row.crates, kit, (town.rooms[roomName] or 0) / (odds * rarity))
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

-- What the vehicles of `stalls` hold, arrow boards included, and how many arrow boards they are.
local function vehicleFinds(stalls, kinds)
    local arrowBoard = RenewableEnergy.ArrowBoard.SCRIPT
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
                end
                add(total, loot[script], vehicles)
                add(total, kinds.cracked, vehicles * vehicleCrackedModules(script, zoneName))
            end
        end
    end
    return total, arrowBoards
end

-- What a site holds once placed: its panels' modules, its bank's batteries, its crate and its
-- arrow board.
local function siteFinds(site, kinds)
    local SolarSites = RenewableEnergy.SolarSites
    local kind = SolarSites.KINDS[site.kind]
    local total = none()
    if kind.panels then
        local placedPanels = (kind.panels.min + math.min(kind.panels.max, #site.panels)) / 2
        local moduleSum = 0
        for _, panel in ipairs(site.panels) do
            local mount = SolarSites.mountKind(panel[4])
            moduleSum = moduleSum + (kind.modules and midpoint(kind.modules) or RenewableEnergy.Specs.mounts[mount].modules)
        end
        add(total, kinds.site, placedPanels * moduleSum / #site.panels)
    end
    local stock = site.bank and (kind.bank or kind.wind)
    if stock then
        add(total, bankBatteries(stock))
    end
    if kind.crate then
        add(total, crateFinds(kind.crate, kinds))
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

local CLEAR_ONLY = { { 1, Loot.WEATHER_MIX[1][2] } }
-- The 15th of July and of December, as days of the year.
local MONTH_DAYS = { july = 196, december = 349 }

-- Watt-hours a factory module at full condition on `mount` banks over the day `dayOfYear` under
-- `weather` (Loot.WEATHER_MIX's rows), in half-hour steps, at the save's Sunlight Multiplier.
local function moduleDayWh(dayOfYear, mount, weather)
    local Sun = RenewableEnergy.Sun
    local rated = RenewableEnergy.Specs.modules[MODULE].watts
    local latitude = getClimateManager():getSeason():getLat()
    local step, wh = 0.5, 0
    for hour = -12, 12 - step, step do
        local sun = Sun.position(dayOfYear, hour + step / 2, latitude)
        for _, part in ipairs(weather) do
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

-- Prints what turns the finds into hours, and returns the average watt-hours a new module banks
-- on a south rack in a day of each of MONTH_DAYS.
local function printYardsticks()
    local options = SandboxVars.RenewableEnergy
    local rackWh = {}
    for _, month in ipairs({ "july", "december" }) do
        local wh = {}
        for name, mount in pairs(Loot.SOUTH_MOUNTS) do
            wh[name] = { average = moduleDayWh(MONTH_DAYS[month], mount, Loot.WEATHER_MIX),
                clear = moduleDayWh(MONTH_DAYS[month], mount, CLEAR_ONLY) }
        end
        rackWh[month] = wh.rack.average
        print(string.format("RELootReport yardstick: a new module banks a day in mid-%s, average (clear): flat %.0f (%.0f), south rack %.0f (%.0f), south wall %.0f (%.0f) Wh at Sunlight Multiplier %.2f",
            month, wh.flat.average, wh.flat.clear, wh.rack.average, wh.rack.clear, wh.wall.average, wh.wall.clear,
            options.SunlightMultiplier))
    end
    local appliances = {}
    for name in pairs(Loot.APPLIANCE_FUEL) do
        table.insert(appliances, string.format("%s %.0f", name, Loot.applianceWatts(name)))
    end
    table.sort(appliances)
    print("RELootReport yardstick: appliance watts as a bank bills them: " .. table.concat(appliances, ", "))
    local function years(nights) return nights and string.format("%.1f", nights / 365) or "never" end
    local lives = {}
    for _, fullType in ipairs(LIFE_BATTERIES) do
        table.insert(lives, string.format("%s %s (%s)", fullType:match("[^.]+$"), years(nightsToHalf(fullType, 0.5)),
            years(nightsToHalf(fullType, 0.25))))
    end
    print(string.format("RELootReport yardstick: years a new battery lasts to half capacity under a nightly load of half (a quarter) its new capacity, at Battery Wear %d%%: %s",
        options.BatteryWear, table.concat(lives, ", ")))
    return rackWh
end

-- Report -----------------------------------------------------------------------------------------

-- The row parts a town's total sums.
local PARTS = { "listed", "cracked", "crates", "banks", "vehicles", "sites" }

-- Modules as "count (watts as found / repaired)".
local function modulesText(finds)
    local watts = RenewableEnergy.Specs.modules[MODULE].watts / 100
    return string.format("%.1f (%.0f / %.0f W)", finds.modules, finds.condition * watts, finds.repaired * watts)
end

-- Batteries as "count (kWh as found)".
local function batteriesText(finds)
    return string.format("%.1f (%.1f kWh)", finds.batteries, finds.wh / 1000)
end

local function printReport(census)
    local options, SolarSites = SandboxVars.RenewableEnergy, RenewableEnergy.SolarSites
    local kinds = findKinds()
    local sites, siteBoards = {}, 0
    print("RELootReport modules a thorough player finds, as count (watts as found / after Seal Cracked Module), and batteries, as count (kWh as found)")
    print(string.format("RELootReport Battery Bank Spawn %d, Solar Sites %d%%", options.BatteryBankSpawn, options.SolarSites))
    for _, site in ipairs(SolarSites.sites()) do
        local entry = { site = site, finds = siteFinds(site, kinds), chance = SolarSites.siteChance(site) }
        table.insert(sites, entry)
        if site.arrowBoard then
            siteBoards = siteBoards + entry.chance
        end
        print(string.format("RELootReport site %s (%s) when placed: modules %s, batteries %s; %.0f%% of worlds", site.name,
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
        print(string.format("RELootReport modules in %s: room loot %s, cracked %s, world crates %s, beside world banks %s, vehicles %s, sites %s; total %s",
            town.name, modulesText(row.listed), modulesText(row.cracked), modulesText(row.crates), modulesText(row.banks),
            modulesText(row.vehicles), modulesText(row.sites), modulesText(row.total)))
        local banks, byRoom = 0, {}
        for roomName, placed in pairs(row.banksByRoom) do
            banks = banks + placed
            table.insert(byRoom, string.format("%s %.1f", roomName, placed))
        end
        table.sort(byRoom)
        print(string.format("RELootReport batteries in %s: room loot %s, world banks %.1f holding %s, kit crates %s, vehicles %s, sites %s; total %s; car batteries in room loot %.1f",
            town.name, batteriesText(row.listed), banks, batteriesText(row.banks), batteriesText(row.crates),
            batteriesText(row.vehicles), batteriesText(row.sites), batteriesText(row.total), row.cars))
        print(string.format("RELootReport world banks in %s by room: %s", town.name, table.concat(byRoom, ", ")))
    end
    print(string.format("RELootReport arrow boards per map: %.1f from vehicle zones, %.1f at sites", zoneBoards, siteBoards))
    local stocks = {}
    for name in pairs(RenewableEnergy.WorldSpawns.BANK_STOCK) do
        table.insert(stocks, name)
    end
    table.sort(stocks)
    for _, name in ipairs(stocks) do
        print(string.format("RELootReport batteries in a %s bank: %s", name, batteriesText(bankBatteries(name))))
    end
    local rackWh = printYardsticks()
    for _, town in ipairs(census.towns) do
        local total = rows[town.name].total
        local newModules = total.condition / 100
        print(string.format("RELootReport power in %s: batteries store %.1f kWh; modules as found are %.1f new ones, banking %.1f kWh a day on south racks in July, %.1f in December",
            town.name, total.wh / 1000, newModules, newModules * rackWh.july / 1000, newModules * rackWh.december / 1000))
    end
end

--- Prints the report, at the default loot settings and loot rarity options 1.
function TownReport.print()
    local census = require "RenewableEnergyDevTownCensus"
    PZHarness.Loot.withMeasureOptions(Loot.MEASURE_OPTIONS, function()
        Loot.withLootRarity(1, function() printReport(census) end)
    end)
end

return TownReport
