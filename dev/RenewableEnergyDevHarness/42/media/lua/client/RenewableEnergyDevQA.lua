-- Development only. The setup of the Renewable Energy QA debug scenario, for playing through the
-- mod by hand: an invisible, invulnerable character with every recipe and skill the mod reads and
-- the small tools in toolboxes, and nearby, in rows by system, a square to each item type: the
-- mod's items, enough inputs to make each recipe once, what the menu jobs take, the crafting
-- stations, a treadmill, and a car towing the arrow board trailer.
require "RenewableEnergy/Debug/RenewableEnergyDebug"
local Stage = require "RenewableEnergyDevStage"
local Harness = require "PZHarness/Stage"

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
-- Every perk the mod reads or trains (the tests' `perks` setting) goes to this level.
local SKILL = 10
-- The batteries and modules among the materials come worn, so that every repair recipe takes them.
local WORN_BATTERY, CRACKED_MODULE = 40, 30
-- Inputs naming several items take the first listed here, else the harness's pick (T.inputItem),
-- which for a tag can differ from run to run; so every tag input the recipes have is listed, and
-- the layout and the toolboxes come out the same each run.
local PREFER = {
    "Base.EmptyJar", "Base.MetalDrum", "Base.Bucket", "Base.WaterBottle", "Base.Charcoal", "Base.HandDrill",
    "Base.Screwdriver", "Base.Wrench", "Base.Hammer", "Base.SmithingHammer", "Base.Saw", "Base.KitchenKnife",
    "Base.Pliers", "Base.Tongs", "Base.WeldingMask", "Base.Shovel", "Base.MasonsTrowel", "Base.Matches",
    "Base.Garbagebag", "Base.BucketConcreteFull", "Base.NormalBrake1",
}

-- What the mod's menu jobs take, beyond its recipes and tools, and what they work on.
local JOB_ITEMS = {
    { "Base.ElectricWire", 40 }, { "Base.ElectronicsScrap", 10 }, { "Base.CarBatteryCharger", 2 },
    { "Base.CarBattery1", 1 }, { "Base.CarBattery2", 1 }, { "Base.CarBattery3", 1 }, { "Base.Generator", 1 },
    { "Base.RubberHose", 10 }, { "Base.MetalPipe", 4 }, { "Base.Pipe", 2 }, { "Base.PropaneTank", 1 },
    { "Base.DuctTape", 2 },
    { "Base.Dung_Cow", 10 }, { "Base.Dung_Pig", 5 }, { "Base.Dung_Sheep", 5 }, { "Base.Dung_Chicken", 5 },
    { "Base.Dung_Turkey", 5 }, { "Base.Dung_Deer", 5 }, { "Base.HayTuft", 10 }, { "Base.GrassTuft", 10 },
    { "Base.CompostBag", 2 }, { "Base.Quicklime", 2 },
    { "Base.Log", 4 }, { "Base.FirewoodBundle", 4 }, { "Base.TwigsBundle", 2 }, { "Base.Twigs", 10 },
    { "Base.LargeBranch", 4 }, { "Base.Pinecone", 10 }, { "Base.Splinters", 10 }, { "Base.Charcoal", 10 },
    { "Base.SteelWool", 4 }, { "Base.Straw2", 10 }, { "Base.Matches", 2 },
    { "Base.Tarp", 2 }, { "Base.Garbagebag", 4 }, { "Base.EmptySandbag", 4 },
    { "Base.LightBulb", 4 }, { "Base.Battery", 6 }, { "Base.BakingSoda", 2 }, { "Base.Thread", 2 },
}

-- The tools the menu jobs take and keep, as their materials' `tool` and kept items name them.
local JOB_TOOLS = {
    "Base.Screwdriver", "Base.Wrench", "Base.Hammer", "Base.Saw", "Base.Needle", "Base.TirePump", "Base.Bellows",
    "Base.LargeBellows", "Base.Shovel", "Base.Broom", "Base.SnowShovel", "Base.BoltCutters",
}

-- The tools, those the recipes keep and JOB_TOOLS, go in vanilla toolboxes. A kept item goes in
-- only if vanilla files it as a tool and it fits a toolbox's MaxItemSize, which keeps the
-- toolboxes few enough to hold: the crafting window takes items only from the bags the character
-- holds or wears (ISInventoryPage:refreshBackpacks).
local TOOLBOX = "Base.Toolbox"

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
        "RenewableEnergy.GasConversionKit", "RenewableEnergy.GasHeater",
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

local function isOpen(square)
    return square ~= nil and square:isOutside() and square:isSolidFloor() and square:isFree(false)
        and not square:HasTree() and square:getWall(true) == nil and square:getWall(false) == nil
        and square:getVehicleContainer() == nil and not square:getProperties():has(IsoFlagType.water)
end

local function rowOpen(square, length)
    return Stage.isAreaOpen(square, length, 1, isOpen)
end

local function lotOpen(square)
    return Stage.isAreaOpen(square, ROW, LOT_ROWS, isOpen)
end

-- The layout's north-west corner: the closest whose whole lot is open, else the closest open row,
-- from which the layout skips what stands in its way.
local function layoutOrigin(player)
    return Harness.closestSquare(player, lotOpen)
        or Harness.closestSquare(player, function(square) return rowOpen(square, ROW) end)
end

-- The layout: rows ROW squares wide from `origin`, south one after the other, skipping squares
-- that aren't open, so items keep their order around a house or a tree.
local function newLayout(origin)
    return { x = origin:getX(), y = origin:getY(), z = origin:getZ(), column = 0, row = 0 }
end

local function nextSquare(layout)
    while layout.row < MAX_ROWS do
        local square = getCell():getGridSquare(layout.x + layout.column, layout.y + layout.row, layout.z)
        layout.column = layout.column + 1
        if layout.column == ROW then
            layout.column, layout.row = 0, layout.row + 1
        end
        if isOpen(square) then
            -- Out of the long grass and bushes, so what lies there shows.
            Harness.clearGroundCover(square)
            return square
        end
    end
    return nil
end

-- Ends the row, and leaves the next empty, between groups.
local function nextGroup(layout)
    layout.row = layout.row + (layout.column > 0 and 2 or 1)
    layout.column = 0
end

local function isKnown(fullType)
    return getScriptManager():FindItem(fullType) ~= nil
end

-- Every craftRecipe and build menu recipe of the mod.
local function modRecipes()
    local scripts, recipes = getScriptManager(), {}
    for _, name in ipairs(PZHarness.Test.recipeNames()) do
        table.insert(recipes, scripts:getCraftRecipe(name))
    end
    for _, name in ipairs(PZHarness.Test.buildRecipeNames()) do
        table.insert(recipes, scripts:getBuildableRecipe(name))
    end
    return recipes
end

-- What making every recipe once takes, by item type and the fluid it holds: `kept`, as many of a
-- kept tool as one recipe needs, and `used`, as many of what is used up as all of them together,
-- a drainable a recipe takes uses of counting as one full item. Also the inputs no item can meet.
local function materials()
    local needs, order, unmatched = {}, {}, {}
    for _, recipe in ipairs(modRecipes()) do
        local inputs = recipe:getInputs()
        for i = 0, inputs:size() - 1 do
            local input = inputs:get(i)
            if input:getResourceType() == ResourceType.Item then
                local item = PZHarness.Test.inputItem(input, PREFER)
                if item then
                    local count = input:getIntAmount()
                    if item:isItemType(ItemType.DRAINABLE) and not input:isItemCount() then
                        count = 1
                    end
                    local fluid
                    local drawn = input:hasConsumeFromItem() and input:getConsumeFromItemScript()
                    if drawn and drawn:getResourceType() == ResourceType.Fluid and drawn:getPossibleInputFluids():size() > 0 then
                        fluid = drawn:getPossibleInputFluids():get(0)
                    end
                    local key = item:getFullName() .. (fluid and "+" .. fluid:getFluidTypeString() or "")
                    local need = needs[key]
                    if not need then
                        need = { type = item:getFullName(), fluid = fluid, used = 0, kept = 0 }
                        needs[key] = need
                        table.insert(order, need)
                    end
                    if input:isKeep() then
                        need.kept = math.max(need.kept, count)
                    else
                        need.used = need.used + count
                    end
                else
                    table.insert(unmatched, recipe:getName() .. ": " .. input:getOriginalLine())
                end
            end
        end
    end
    table.sort(order, function(a, b)
        local ia, ib = getScriptManager():FindItem(a.type), getScriptManager():FindItem(b.type)
        local ca, cb = ia:getDisplayCategory() or "", ib:getDisplayCategory() or ""
        if ca ~= cb then return ca < cb end
        return a.type < b.type
    end)
    return order, unmatched
end

-- Whether items of `fullType` come worn when asked for worn: batteries and modules.
local function wears(fullType)
    return RenewableEnergy.Specs.batteries[fullType] ~= nil or RenewableEnergy.Specs.modules[fullType] ~= nil
end

-- A new item of `fullType`, its fluid container filled with `fluid` if given, worn if `worn`.
local function newItem(fullType, fluid, worn)
    local item = instanceItem(fullType)
    if not item then
        return nil
    end
    local container = fluid and item:getFluidContainer()
    if container then
        container:Empty()
        container:addFluid(fluid, container:getCapacity())
    end
    if worn and RenewableEnergy.Specs.batteries[fullType] then
        RenewableEnergy.Wear.setCondition(item, WORN_BATTERY)
    elseif worn then
        RenewableEnergy.Wear.setCondition(item, CRACKED_MODULE)
    end
    return item
end

-- Lays `count` items of `fullType` on the layout's next square, scattered over it so they show.
local function lay(layout, summary, fullType, count, fluid, worn)
    if not isKnown(fullType) then
        table.insert(summary.unknown, fullType)
        return
    end
    local square = nextSquare(layout)
    if not square then
        table.insert(summary.unplaced, fullType)
        return
    end
    for _ = 1, count do
        local item = newItem(fullType, fluid, worn)
        square:AddWorldInventoryItem(item, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
        summary.items = summary.items + 1
    end
    summary.types = summary.types + 1
end

-- Adds to `stock` (a list of what the scenario hands out, in the order first asked for) `used`
-- items of `fullType` that a job uses up and `kept` that one keeps, filled with `fluid` and worn if
-- given. Asked for again alike, it adds the used and keeps the most kept.
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

-- Everything the scenario hands out: every item of the mod, what the recipes take, the batteries
-- and modules among them worn, and what the menu jobs take.
local function collectStock(summary)
    local stock = { byKey = {} }
    for _, fullType in ipairs(RenewableEnergy.Debug.ITEMS) do
        addStock(stock, fullType, 1, 0)
    end
    local needs
    needs, summary.unmatched = materials()
    for _, need in ipairs(needs) do
        addStock(stock, need.type, need.used, need.kept, need.fluid, true)
    end
    for _, entry in ipairs(JOB_ITEMS) do
        addStock(stock, entry[1], entry[2], 0)
    end
    for _, fullType in ipairs(JOB_TOOLS) do
        addStock(stock, fullType, 0, 1)
    end
    return stock
end

-- Puts the stock's small tools in TOOLBOX toolboxes in `player`'s inventory, starting a new one
-- when the last has no room, and the first two in the hands. Room is counted with no character,
-- by the toolbox's own capacity, which the Organized and Disorganized traits would change
-- (ItemContainer.getEffectiveCapacity), so every character gets the same toolboxes. What a tool's
-- entry has left to lay out stays in `entry.used`.
local function packToolboxes(player, stock, summary)
    local boxes, container = {}, nil
    local maxSize = instanceItem(TOOLBOX):getMaxItemSize()
    for _, entry in ipairs(stock) do
        local script = entry.kept > 0 and PZHarness.startsWith(entry.type, "Base.") and getScriptManager():FindItem(entry.type)
        local category = script and script:getDisplayCategory()
        local weight = script and script:getActualWeight()
        if (category == "Tool" or category == "ToolWeapon") and weight < maxSize then
            for _ = 1, entry.kept do
                if not (container and container:hasRoomFor(nil, weight)) then
                    local box = player:getInventory():AddItem(instanceItem(TOOLBOX))
                    table.insert(boxes, box)
                    container = box:getItemContainer()
                end
                container:AddItem(newItem(entry.type))
                summary.tools = summary.tools + 1
            end
            table.insert(summary.toolTypes, entry.type)
            entry.kept = 0
        end
        entry.used = entry.used + entry.kept
    end
    summary.toolboxes = #boxes
    player:setPrimaryHandItem(boxes[1])
    player:setSecondaryHandItem(boxes[2])
    -- So the inventory window shows the held toolboxes at once.
    ISInventoryPage.dirtyUI()
end

local function placeStations(layout, summary)
    for _, station in ipairs(STATIONS) do
        local first
        repeat
            first = nextSquare(layout)
        until not first or rowOpen(first, #station.sprites)
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
            -- Past the station's other tiles, so nothing is laid on them.
            for _ = 2, #station.sprites do
                nextSquare(layout)
            end
            summary.stations = summary.stations + 1
        end
    end
end

-- A treadmill, its console west of its rear as the game lays it out facing west (Sprites.treadmill).
local function placeTreadmill(layout, summary)
    local console
    repeat
        console = nextSquare(layout)
    until not console or rowOpen(console, 2)
    if not console then
        table.insert(summary.unplaced, "treadmill")
        return
    end
    local rear = nextSquare(layout)
    Stage.placeTile(console, RenewableEnergy.Sprites.treadmill.W.console)
    Stage.placeTile(rear, RenewableEnergy.Sprites.treadmill.W.rear)
end

-- A car facing east with the arrow board trailer behind it (Stage.spawnTrailer), on a whole open
-- row of the layout.
local function placeTrailer(layout, summary)
    nextGroup(layout)
    local start
    repeat
        start = nextSquare(layout)
    until not start or (layout.column == 1 and rowOpen(start, ROW))
    if not start then
        table.insert(summary.unplaced, "arrow board trailer")
        return
    end
    Stage.spawnTrailer(getCell():getGridSquare(start:getX() + ROW - 4, start:getY(), start:getZ()), "E")
    summary.trailer = true
end

-- One module shattered, for Take Apart Shattered Module.
local function placeShattered(layout)
    local square = nextSquare(layout)
    if square then
        local module = instanceItem(RenewableEnergy.Specs.factoryModule)
        RenewableEnergy.Wear.setCondition(module, 0)
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
        if #prefix > longest and PZHarness.startsWith(fullType, prefix) then
            group, longest = prefixGroup, #prefix
        end
    end
    return group or UNSORTED
end

-- Lays out what the stock has left to lay, group by group in GROUPS' order, each group's items in
-- the order the stock has them.
local function layGroups(layout, stock, summary)
    local members = {}
    for _, group in ipairs(GROUPS) do
        members[group] = {}
    end
    for _, entry in ipairs(stock) do
        if entry.used > 0 then
            local group = groupOf(entry.type)
            if group == UNSORTED then
                table.insert(summary.unsorted, entry.type)
            end
            table.insert(members[group], entry)
        end
    end
    for _, group in ipairs(GROUPS) do
        if #members[group] > 0 or PLACE[group] then
            if summary.groups > 0 then
                nextGroup(layout)
            end
            for _, entry in ipairs(members[group]) do
                lay(layout, summary, entry.type, entry.used, entry.fluid, entry.worn)
            end
            if PLACE[group] then
                PLACE[group](layout, summary)
            end
            summary.groups = summary.groups + 1
        end
    end
end

local function setUpCharacter(player)
    player:setGodMod(true)
    player:setInvisible(true)
    player:setUnlimitedCarry(true)
    player:setUnlimitedEndurance(true)
    local levels = {}
    for _, perk in ipairs(PZHarness.testSettings.perks) do
        levels[perk:getId()] = SKILL
    end
    PZHarness.Fixtures.setPerkLevels(player, levels)
    RenewableEnergy.Debug.learnRecipes(player)
end

--- Sets the scenario up around `player`, and prints what it laid out, and anything it couldn't,
--- under MARK. Returns that summary.
function QA.setup(player)
    getGameTime():setTimeOfDay(10)
    setUpCharacter(player)
    local summary = { types = 0, items = 0, groups = 0, stations = 0, tools = 0, toolboxes = 0, toolTypes = {},
        unknown = {}, unplaced = {}, unmatched = {}, unsorted = {} }
    local stock = collectStock(summary)
    packToolboxes(player, stock, summary)
    local origin = layoutOrigin(player)
    if not origin then
        print(MARK .. " no open row of " .. ROW .. " squares within " .. Harness.SEARCH_RADIUS .. " squares")
        return summary
    end
    summary.lot = lotOpen(origin)
    summary.origin = origin
    layGroups(newLayout(origin), stock, summary)
    -- At the head of the layout, with a table to craft at beside it.
    PZHarness.Fixtures.teleportToMiddle(player, origin:getX(), origin:getY(), origin:getZ())
    PZHarness.Test.placeWorkTable(player)
    print(string.format("%s laid out %d items of %d types in %d groups from %d,%d (whole lot open: %s), %d stations,"
        .. " trailer %s; %d tools of %d types in %d toolboxes", MARK, summary.items, summary.types, summary.groups,
        origin:getX(), origin:getY(), tostring(summary.lot), summary.stations, tostring(summary.trailer == true),
        summary.tools, #summary.toolTypes, summary.toolboxes))
    print(MARK .. " toolboxes: " .. table.concat(summary.toolTypes, ", "))
    for _, what in ipairs({ "unknown", "unplaced", "unmatched", "unsorted" }) do
        if #summary[what] > 0 then
            print(MARK .. " " .. what .. ": " .. table.concat(summary[what], "; "))
        end
    end
    return summary
end

--- QA.setup on the first tick: a scenario's onStart runs during the world's start (OnGameStart),
--- before the global object systems exist, which clearing a square's ground cover reaches.
function QA.setupSoon()
    local function onTick()
        Events.OnTick.Remove(onTick)
        QA.setup(getPlayer())
    end
    Events.OnTick.Add(onTick)
end

return QA
