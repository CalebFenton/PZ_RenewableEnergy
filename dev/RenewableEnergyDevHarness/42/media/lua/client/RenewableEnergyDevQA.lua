-- Development only. The setup of the Renewable Energy QA debug scenario, for playing through the
-- mod by hand: an invisible, invulnerable character with every recipe and skill the mod reads and
-- the small tools in toolboxes, and nearby, in rows by system, a square to each item type: the
-- mod's items, enough inputs to make each recipe once, what the menu jobs take, the crafting
-- stations, a treadmill, and a car towing the arrow board trailer.
local Debug = require "RenewableEnergy/Debug/RenewableEnergyDebug"
local Stage = require "RenewableEnergyDevStage"
local Harness = require "PZHarness/Stage"
require "PZHarness/StageLots"
local HarnessQA = require "PZHarness/QA"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local DigesterJobs = require "RenewableEnergy/Biogas/DigesterJobs"
local GasHeater = require "RenewableEnergy/Biogas/GasHeater"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local GasifierJobs = require "RenewableEnergy/WoodGas/GasifierJobs"
local FireAsh = require "RenewableEnergy/WoodGas/FireAsh"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local VehicleJobs = require "RenewableEnergy/Gadgets/VehicleJobs"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local Wear = require "RenewableEnergy/PowerBank/Wear"

local QA = {}

-- Where the scenario starts: beside a farm's barn, a building for banks with open ground around it
-- for the layout, panels and wind chargers.
QA.START = { x = 10469, y = 10121, z = 0 }

local MARK = "REQA"
-- Squares a row of the layout spans east, and the most rows it may take before giving up.
local ROW, MAX_ROWS = 20, 60
-- The rows of open ground looked for at the layout's head; the layout runs on south past them,
-- around whatever stands there.
local LOT_ROWS = 20
-- The batteries and modules among the materials come worn, so that every repair recipe takes them.
local WORN_BATTERY, CRACKED_MODULE = 40, 30

-- The job modules (cf_commonlib's Jobs) whose rows' materials the scenario hands out.
local JOB_MODULES = {
    DigesterJobs, GasHeater, GasKit, GasifierJobs, FireAsh, BankJobs, SourceJobs, Treadmill, VehicleJobs, SolarGardenLight,
}

-- Every item type a bank takes as a part, sorted so the layout comes out the same each run.
local function bankPartTypes()
    local types = {}
    for _, part in pairs(PowerBank.PARTS) do
        for fullType in pairs(part.types) do
            table.insert(types, fullType)
        end
    end
    table.sort(types)
    return types
end

-- The rows whose materials depend on what the job works on, as lists of materials lists read for
-- representative ones: a cold gasifier's lighting, and wiring in each bank part (Unwire takes the
-- tools Wire In does). Connect Gas Line reads its line off a placed source, so its line is given:
-- hoses for a digester at the farthest reach, and a gasifier's pipe; the wrench is Install Kit's.
local QUERIED = {
    [GasifierJobs.JOBS[GasifierJobs.LIGHT]] = function(player)
        return { GasifierJobs.materials(player, GasifierJobs.LIGHT, { cold = true }) }
    end,
    [BankJobs.JOBS[BankJobs.WIRE_IN]] = function(player)
        local lists = {}
        for _, fullType in ipairs(bankPartTypes()) do
            table.insert(lists, BankJobs.materials(player, BankJobs.WIRE_IN, nil, instanceItem(fullType)))
        end
        return lists
    end,
    [BankJobs.JOBS[BankJobs.UNWIRE]] = function() return {} end,
    [GasKit.JOBS[GasKit.CONNECT]] = function()
        return { { { item = GasKit.HOSE, need = math.ceil(GasKit.REACH / GasKit.HOSE_SQUARES) }, GasKit.SOURCES.gasifier.line() } }
    end,
}

-- What the menu jobs work on and with, which no materials list names: bank parts, the generator,
-- vessels to fill, digester feed and sacks for its sludge, gasifier fuel and filter packing, scrubber
-- packings, bulbs and cells, and what mends the gas bag.
local WORKED_ON = {
    { "Base.CarBatteryCharger", 2 }, { "Base.CarBattery1", 1 }, { "Base.CarBattery2", 1 }, { "Base.CarBattery3", 1 },
    { "Base.Generator", 1 }, { "Base.PropaneTank", 1 }, { "Base.BlowTorch", 1 }, { "Base.DuctTape", 2 },
    { "Base.Dung_Cow", 10 }, { "Base.Dung_Pig", 5 }, { "Base.Dung_Sheep", 5 }, { "Base.Dung_Chicken", 5 },
    { "Base.Dung_Turkey", 5 }, { "Base.Dung_Deer", 5 }, { "Base.GrassTuft", 10 }, { "Base.CompostBag", 2 },
    { "Base.Quicklime", 1 }, { "Base.BakingSoda", 2 }, { "Base.EmptySandbag", 4 },
    { "Base.Log", 4 }, { "Base.FirewoodBundle", 4 }, { "Base.TwigsBundle", 2 }, { "Base.Twigs", 10 },
    { "Base.LargeBranch", 4 }, { "Base.Pinecone", 10 }, { "Base.Splinters", 10 }, { "Base.Charcoal", 10 },
    { "Base.Straw2", 10 }, { "RenewableEnergy.TarpGasBag", 1 }, { "RenewableEnergy.IronSponge", 1 },
    { "RenewableEnergy.SpentIronSponge", 1 }, { "Base.IronScrap", 4 },
    { "Base.LightBulb", 4 }, { "Base.Battery", 6 }, { "Base.Thread", 2 },
}

-- The tools jobs are worked with in hand, or that stand in for the named one, which no materials
-- list names.
local HELD_TOOLS = { "Base.Needle", "Base.LargeBellows", "Base.Broom", "Base.SnowShovel", "Base.BoltCutters" }

-- The layout's groups, in order, each from a row of its own. An item type goes in the group
-- GROUP_TYPES lists it under, else in that of the longest prefix there (an entry ending in "*")
-- it starts with, else in UNSORTED, which the summary lists. Stations has only the stations.
local UNSORTED = "unsorted"
local GROUPS = {
    "solar", "wind", "treadmill", "bank", "batteries", "biogas", "woodgas", "gadgets", "vehicle", "reading",
    "materials", UNSORTED, "stations",
}
local GROUP_TYPES = {
    -- Modules, mounts, making and mending modules, and clearing snow off them.
    solar = {
        "RenewableEnergy.SolarModule", "RenewableEnergy.HomemadeSolarModule", "RenewableEnergy.SolarCells",
        "RenewableEnergy.SolarFlat", "RenewableEnergy.SolarWall*", "RenewableEnergy.SolarRack*",
        "Base.GlassPanel", "Base.Epoxy", "Base.Glue", "Base.Calculator", "Base.Broom", "Base.SnowShovel",
    },
    -- Blades and alternators for the wind chargers.
    wind = {
        "RenewableEnergy.WoodenBlades", "RenewableEnergy.PipeBlades", "RenewableEnergy.SteelBlades",
        "RenewableEnergy.HomemadeAlternator", "Base.Speaker", "Base.RadioRed", "Base.RadioBlack",
        "Base.NormalBrake*", "Base.OldBrake*", "Base.ModernBrake*", "Base.KitchenKnife",
    },
    treadmill = { "RenewableEnergy.TreadmillMotor" },
    -- Storage, and the parts wired into a bank.
    bank = {
        "RenewableEnergy.BatteryBox*", "RenewableEnergy.BatteryRack*", "RenewableEnergy.BatteryBank*",
        "RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter", "RenewableEnergy.InverterCharger",
        "RenewableEnergy.MakeshiftInverter", "RenewableEnergy.HomemadeInverter", "RenewableEnergy.MicrowaveTransformer",
        "RenewableEnergy.ChargeController", "RenewableEnergy.SolarFailsafe", "Base.CarBatteryCharger",
        "Base.Amplifier", "Base.RemoteCraftedV3",
    },
    -- Batteries, and servicing, stripping, casting and rebuilding them.
    batteries = {
        "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery", "RenewableEnergy.JarBattery",
        "RenewableEnergy.CarBatteryCase", "RenewableEnergy.DeepCycleBatteryCase", "RenewableEnergy.L16BatteryCase",
        "RenewableEnergy.WornBatteryPlates", "RenewableEnergy.BatteryPlate*", "RenewableEnergy.WoodenBatteryPlatePattern",
        "RenewableEnergy.BatteryElectrolyte", "Base.CarBattery*", "Base.EmptyJar", "Base.JarCrafted",
        "Base.ClayJarGlazed", "Base.Sandbag", "Base.Clay", "Base.LeadPipe", "Base.BakingSoda", "Base.RippedSheets",
        "Base.Gloves_Dish",
    },
    -- Digesters, their feed and upkeep, filling tanks, and the gas kit, heater and generator the gas
    -- goes to.
    biogas = {
        "Base.Dung_*", "Base.HayTuft", "Base.GrassTuft", "Base.CompostBag", "Base.Quicklime", "Base.Garbagebag",
        "Base.EmptySandbag", "Base.Tarp", "Base.Thread", "Base.MetalDrum", "Base.Bucket", "Base.SteelWool",
        "Base.Funnel", "Base.ClayBrick", "Base.BucketConcreteFull", "Base.MasonsTrowel", "Base.TirePump",
        "Base.PropaneTank", "Base.Propane_Refill", "Base.Generator", "RenewableEnergy.FridgeCompressor",
        "RenewableEnergy.GasConversionKit", "RenewableEnergy.GasHeater", "RenewableEnergy.TarpGasBag",
        "RenewableEnergy.IronSponge", "RenewableEnergy.SpentIronSponge", "Base.IronScrap", "Base.File",
    },
    -- Gasifiers, their fuel and filter, cleaning them out, and wood vinegar.
    woodgas = {
        "RenewableEnergy.WoodAsh", "RenewableEnergy.TarryPacking", "Base.Log", "Base.FirewoodBundle",
        "Base.TwigsBundle", "Base.Twigs", "Base.LargeBranch", "Base.Pinecone", "Base.Splinters", "Base.Straw2",
        "Base.Charcoal", "Base.LargeBellows", "Base.Shovel", "Base.Mov_BinRound", "Base.Strainer",
        "Base.NutsBolts", "Base.GardeningSprayEmpty",
    },
    gadgets = {
        "RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger", "RenewableEnergy.SolarGardenLight",
        "Base.LightBulb", "Base.Battery",
    },
    -- The arrow board trailer follows its items.
    vehicle = { "Base.BoltCutters" },
    reading = {
        "RenewableEnergy.HomesteadPowerMag*", "RenewableEnergy.CrowcallRoadMap",
        "RenewableEnergy.DixieTrailerParkMap", "RenewableEnergy.FemaPamphlet",
    },
    -- What every system is built from.
    materials = {
        "Base.Plank", "Base.Nails", "Base.Screws", "Base.ElectricWire", "Base.ElectronicsScrap",
        "Base.SmallSheetMetal", "Base.SheetMetal", "Base.MetalBar", "Base.IronBar", "Base.MetalPipe", "Base.Pipe",
        "Base.RubberHose", "Base.DuctTape", "Base.BlowTorch", "Base.WeldingRods", "Base.Matches",
        "Base.WaterBottle", "Base.HandDrill",
    },
}

local GROUP_OF, GROUP_PREFIXES = {}, {}
for group, types in pairs(GROUP_TYPES) do
    for _, entry in ipairs(types) do
        if entry:sub(-1) == "*" then
            GROUP_PREFIXES[entry:sub(1, -2)] = group
        else
            GROUP_OF[entry] = group
        end
    end
end

-- The crafting stations the recipes' tags ask for, as their entities and tiles; the forge's tiles
-- run east from its first, as its SpriteConfig's south face lays them out.
local STATIONS = {
    { entity = "Base.Hand_Press", sprites = { "crafted_01_72" } },
    { entity = "Base.Kiln_Small", sprites = { "crafted_01_56" } },
    { entity = "Base.Primitive_Furnace", sprites = { "crafted_01_112" } },
    { entity = "Base.Forge", sprites = { "crafted_01_42", "crafted_01_116", "crafted_01_38" } },
}

-- Where the layout may lay an item: open ground a character can walk onto (Stage.isOpenGround),
-- whatever stands there but a tree or a wall.
local function isLayable(object)
    local square = object:getSquare()
    return object:getType() ~= IsoObjectType.tree and object ~= square:getWall(true) and object ~= square:getWall(false)
end
local OPEN_GROUND = { free = true, allows = isLayable }

local function isWalkableGround(square)
    return Harness.isOpenGround(square, OPEN_GROUND)
end

-- The layout's north-west corner: the closest whose whole lot is open, else the closest open row,
-- from which the layout skips what stands in its way; and whether the whole lot is open.
local function layoutOrigin(player)
    local lot = Harness.findLot(player, ROW, LOT_ROWS, OPEN_GROUND)
    local row = lot or Harness.findLot(player, ROW, 1, OPEN_GROUND)
    return row and Harness.lotSquare(row, 0, 0), lot ~= nil
end

-- Whether items of `fullType` come worn when asked for worn: batteries and modules.
local function wears(fullType)
    return Specs.batteries[fullType] ~= nil or Specs.modules[fullType] ~= nil
end

-- A new item of a layGroups entry (PZHarness.QA.newItem), worn if `worn`.
local function newStockItem(entry)
    local item = HarnessQA.newItem(entry.type, entry.fluid)
    if item and entry.worn and Specs.batteries[entry.type] then
        Wear.setCondition(item, WORN_BATTERY)
    elseif item and entry.worn then
        Wear.setCondition(item, CRACKED_MODULE)
    end
    return item
end

-- Adds to `stock` (a list of what the scenario hands out, in the order first asked for) `used`
-- items of `fullType` that a job uses up and `kept` that one keeps, filled with `fluid` and worn if
-- given. Asked for again alike, it adds the used and keeps the most kept: the mod's items, the
-- recipes' needs and the jobs' materials name some types alike.
local function addStock(stock, fullType, used, kept, fluid, worn)
    worn = worn and wears(fullType) or false
    local key = fullType .. "+" .. (fluid and fluid:getFluidTypeString() or "") .. "+" .. tostring(worn)
    local entry = stock.byKey[key]
    if not entry then
        entry = { type = fullType, fluid = fluid, worn = worn, used = 0, kept = 0 }
        stock.byKey[key] = entry
        table.insert(stock, entry)
    end
    entry.used = entry.used + used
    entry.kept = math.max(entry.kept, kept)
end

-- Adds to `stock` what the materials list `materials` (cf_commonlib's Materials) takes: a tool or
-- a kept item to keep, and `need` (else one) of an item taken, by tag or for its uses too. Skills,
-- recipes and water take no item; of several types, the one the list names stands for them.
local function addMaterials(stock, materials)
    for _, material in ipairs(materials) do
        local fullType = material.item
        if fullType and (material.tool or material.keep) then
            addStock(stock, fullType, 0, material.need or 1)
        elseif fullType then
            addStock(stock, fullType, material.need or 1, 0)
        end
    end
end

-- Adds to `stock` what every row of JOB_MODULES takes, each module's rows by job name, a row whose
-- materials are a function as QUERIED reads it. Such a row QUERIED doesn't know goes in the
-- summary's `unqueried`.
local function addJobMaterials(stock, player, summary)
    for _, Module in ipairs(JOB_MODULES) do
        local names = {}
        for name in pairs(Module.JOBS) do
            table.insert(names, name)
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local row = Module.JOBS[name]
            if type(row.materials) == "table" then
                addMaterials(stock, row.materials)
            elseif QUERIED[row] then
                for _, materials in ipairs(QUERIED[row](player)) do
                    addMaterials(stock, materials)
                end
            elseif row.materials then
                table.insert(summary.unqueried, name)
            end
        end
    end
end

-- Everything the scenario hands out: every item of the mod a player can hold, what the recipes
-- take, the batteries and modules among them worn, and what the menu jobs take and work on.
local function collectStock(player, summary)
    local stock = { byKey = {} }
    for _, fullType in ipairs(HarnessQA.itemsOfModule("RenewableEnergy")) do
        if not Debug.PART_ITEMS[fullType] then
            addStock(stock, fullType, 1, 0)
        end
    end
    local needs
    needs, summary.unmatched = HarnessQA.materials(HarnessQA.modRecipeNames(), Debug.PREFERRED_INPUTS)
    for _, need in ipairs(needs) do
        addStock(stock, need.type, need.used, need.kept, need.fluid, true)
    end
    addJobMaterials(stock, player, summary)
    for _, entry in ipairs(WORKED_ON) do
        addStock(stock, entry[1], entry[2], 0)
    end
    for _, fullType in ipairs(HELD_TOOLS) do
        addStock(stock, fullType, 0, 1)
    end
    return stock
end

local function placeStations(layout, summary)
    for _, station in ipairs(STATIONS) do
        local first = layout:nextRun(#station.sprites)
        if not first then
            table.insert(summary.unplaced, station.entity)
        else
            for i, sprite in ipairs(station.sprites) do
                local square = getCell():getGridSquare(first:getX() + i - 1, first:getY(), first:getZ())
                Harness.clearGroundCover(square)
                local _, missing = PZHarness.Fixtures.newBench(square, station.entity, sprite, getPlayer())
                if missing and i == 1 then
                    table.insert(summary.unplaced, station.entity .. " (" .. missing .. ")")
                end
            end
            summary.stations = summary.stations + 1
        end
    end
end

-- A treadmill, its console west of its rear as the game lays it out facing west (Sprites.treadmill).
local function placeTreadmill(layout, summary)
    local console = layout:nextRun(2)
    if not console then
        table.insert(summary.unplaced, "treadmill")
        return
    end
    local rear = getCell():getGridSquare(console:getX() + 1, console:getY(), console:getZ())
    Harness.clearGroundCover(rear)
    Harness.placeTile(console, Sprites.treadmill.W.console)
    Harness.placeTile(rear, Sprites.treadmill.W.rear)
end

-- A car facing east with the arrow board trailer behind it (Stage.spawnTrailer), on a whole open
-- row of the layout.
local function placeTrailer(layout, summary)
    local start = layout:nextOpenRow()
    if not start then
        table.insert(summary.unplaced, "arrow board trailer")
        return
    end
    Stage.spawnTrailer(getCell():getGridSquare(start:getX() + layout.width - 4, start:getY(), start:getZ()), "E")
    summary.trailer = true
end

-- One module shattered, for Take Apart Shattered Module.
local function placeShattered(layout)
    local square = layout:nextSquare()
    if square then
        local module = instanceItem(Specs.factoryModule)
        Wear.setCondition(module, 0)
        square:AddWorldInventoryItem(module, 0.5, 0.5, 0)
    end
end

-- What each group sets after its items.
local PLACE = { solar = placeShattered, treadmill = placeTreadmill, vehicle = placeTrailer, stations = placeStations }

-- The group of an item type (GROUP_TYPES).
local function groupOf(fullType)
    local group, longest = GROUP_OF[fullType], 0
    if group then
        return group
    end
    for prefix, prefixGroup in pairs(GROUP_PREFIXES) do
        if #prefix > longest and luautils.stringStarts(fullType, prefix) then
            group, longest = prefixGroup, #prefix
        end
    end
    return group or UNSORTED
end

-- What the stock has left to lay, as PZHarness.QA.layGroups' groups in GROUPS' order, each group's
-- items in the order the stock has them.
local function stockGroups(stock, summary)
    local groups, byName = {}, {}
    for _, name in ipairs(GROUPS) do
        byName[name] = { name = name, items = {} }
        table.insert(groups, byName[name])
    end
    for _, entry in ipairs(stock) do
        if entry.used > 0 then
            local group = groupOf(entry.type)
            if group == UNSORTED then
                table.insert(summary.unsorted, entry.type)
            end
            table.insert(byName[group].items, { type = entry.type, count = entry.used, fluid = entry.fluid, worn = entry.worn })
        end
    end
    return groups
end

--- Sets the scenario up around `player`, and prints what it laid out, and anything it couldn't,
--- under MARK. Returns that summary.
function QA.setup(player)
    getGameTime():setTimeOfDay(10)
    HarnessQA.setUpCharacter(player)
    local summary = HarnessQA.newSummary()
    summary.stations, summary.unmatched, summary.unsorted, summary.unqueried = 0, {}, {}, {}
    local stock = collectStock(player, summary)
    HarnessQA.packToolboxes(player, stock, summary)
    local origin, wholeLot = layoutOrigin(player)
    if not origin then
        print(MARK .. " no open row of " .. ROW .. " squares within " .. Harness.SEARCH_RADIUS .. " squares")
        return summary
    end
    summary.lot = wholeLot
    HarnessQA.layGroups(origin, ROW, stockGroups(stock, summary), summary,
        { maxRows = MAX_ROWS, accepts = isWalkableGround, after = PLACE, newItem = newStockItem })
    -- At the head of the layout, with a table to craft at beside it.
    PZHarness.Fixtures.teleportToMiddle(player, origin:getX(), origin:getY(), origin:getZ())
    PZHarness.Test.placeWorkTable(player)
    HarnessQA.printSummary(MARK, string.format("laid out %d items of %d types in %d groups from %d,%d (whole lot"
        .. " open: %s), %d stations, trailer %s; %d tools of %d types in %d toolboxes", summary.items, summary.types,
        summary.groups, origin:getX(), origin:getY(), tostring(summary.lot), summary.stations,
        tostring(summary.trailer == true), summary.tools, #summary.toolboxes, summary.boxes), summary,
        { "toolboxes", "unknown", "unplaced", "unmatched", "unsorted", "unqueried" })
    return summary
end

return QA
