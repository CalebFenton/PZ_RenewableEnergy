-- Development only. The setup of the Renewable Energy QA debug scenario
-- (RenewableEnergyDebugScenario.lua), for playing through the mod by hand: a character nothing can
-- see or hurt, who carries anything, knows every recipe of the mod and has every skill it reads,
-- with laid out on the ground nearby, a square to each item type, every item of the mod, enough of
-- every recipe's inputs to make each recipe once, what the menu jobs take, the crafting stations,
-- a treadmill, and a car with the arrow board trailer behind it.
require "RenewableEnergy/Debug/RenewableEnergyDebug"
local Stage = require "RenewableEnergyDevStage"

local QA = {}

-- Where the scenario starts: beside a farm's barn, a building for banks with open ground around it
-- for the layout, panels and wind chargers.
QA.START = { x = 10469, y = 10121, z = 0 }

local MARK = "REQA"
-- Squares a row of the layout spans east, and the most rows it may take before giving up.
local ROW, MAX_ROWS = 20, 60
-- The rows of open ground the whole layout takes, which the closest such lot is looked for with.
local LOT_ROWS = 20
-- Every perk the mod reads or trains (the tests' `perks` setting) goes to this level.
local SKILL = 10
-- The batteries and modules among the materials come worn, so that every repair recipe takes them.
local WORN_BATTERY, CRACKED_MODULE = 40, 30
-- Inputs naming several items take the first listed here, else the harness's pick (T.inputItem),
-- which for a tag can differ from run to run.
local PREFER = { "Base.EmptyJar", "Base.MetalDrum", "Base.Bucket", "Base.WaterBottle", "Base.Charcoal", "Base.HandDrill" }

-- What the mod's menu jobs take, beyond its recipes, and what they work on: wiring parts into a
-- bank, repairing parts, connecting a bank, the battery charger, feeding and tending digesters,
-- fuelling and cleaning gasifiers, the gas kit and its line, the cell charger and garden lights.
local JOB_ITEMS = {
    { "Base.ElectricWire", 40 }, { "Base.ElectronicsScrap", 10 }, { "Base.CarBatteryCharger", 2 },
    { "Base.CarBattery1", 1 }, { "Base.CarBattery2", 1 }, { "Base.CarBattery3", 1 }, { "Base.Generator", 1 },
    { "Base.Wrench", 1 }, { "Base.Screwdriver", 1 }, { "Base.Hammer", 1 }, { "Base.Saw", 1 },
    { "Base.RubberHose", 10 }, { "Base.MetalPipe", 4 }, { "Base.Pipe", 2 }, { "Base.PropaneTank", 1 },
    { "Base.TirePump", 1 }, { "Base.DuctTape", 2 },
    { "Base.Dung_Cow", 10 }, { "Base.Dung_Pig", 5 }, { "Base.Dung_Sheep", 5 }, { "Base.Dung_Chicken", 5 },
    { "Base.Dung_Turkey", 5 }, { "Base.Dung_Deer", 5 }, { "Base.HayTuft", 10 }, { "Base.GrassTuft", 10 },
    { "Base.CompostBag", 2 }, { "Base.Quicklime", 2 },
    { "Base.Log", 4 }, { "Base.FirewoodBundle", 4 }, { "Base.TwigsBundle", 2 }, { "Base.Twigs", 10 },
    { "Base.LargeBranch", 4 }, { "Base.Pinecone", 10 }, { "Base.Splinters", 10 }, { "Base.Charcoal", 10 },
    { "Base.SteelWool", 4 }, { "Base.Straw2", 10 }, { "Base.Matches", 2 }, { "Base.Bellows", 1 },
    { "Base.LargeBellows", 1 }, { "Base.Shovel", 1 }, { "Base.SnowShovel", 1 }, { "Base.Broom", 1 },
    { "Base.Tarp", 2 }, { "Base.Garbagebag", 4 }, { "Base.EmptySandbag", 4 }, { "Base.BoltCutters", 1 },
    { "Base.LightBulb", 4 }, { "Base.Battery", 6 }, { "Base.BakingSoda", 2 }, { "Base.Needle", 1 },
    { "Base.Thread", 2 },
}

-- The crafting stations the recipes' tags ask for, as their entities and tiles; the forge is three
-- tiles in a row, as its SpriteConfig's south face lays them out, east from its first.
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
    if not square then
        return false
    end
    for dx = 0, length - 1 do
        if not isOpen(getCell():getGridSquare(square:getX() + dx, square:getY(), square:getZ())) then
            return false
        end
    end
    return true
end

local function lotOpen(square)
    for dy = 0, LOT_ROWS - 1 do
        if not rowOpen(getCell():getGridSquare(square:getX(), square:getY() + dy, square:getZ()), ROW) then
            return false
        end
    end
    return true
end

-- The layout's north-west corner: the closest whose whole lot is open, else the closest open row,
-- from which the layout skips what stands in its way.
local function layoutOrigin(player)
    return Stage.closestSquare(player, lotOpen)
        or Stage.closestSquare(player, function(square) return rowOpen(square, ROW) end)
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
            Stage.clearGroundCover(square)
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

-- Every craftRecipe and build-menu recipe of the mod.
local function modRecipes()
    local recipes, prefix = {}, PZHarness.testSettings.recipePrefix
    for _, name in ipairs(PZHarness.Test.recipeNames()) do
        table.insert(recipes, getScriptManager():getCraftRecipe(name))
    end
    local buildable = getScriptManager():getAllBuildableRecipes()
    for i = 0, buildable:size() - 1 do
        if PZHarness.startsWith(buildable:get(i):getName(), prefix) then
            table.insert(recipes, buildable:get(i))
        end
    end
    return recipes
end

-- What making every recipe once takes, by item type and the fluid it holds: each kept tool as many
-- as one recipe needs, everything used up as many as all of them together, and a drainable whose
-- uses a recipe counts one full item per recipe. Also the inputs no item can meet.
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
                        need = { type = item:getFullName(), fluid = fluid, count = 0, kept = 0 }
                        needs[key] = need
                        table.insert(order, need)
                    end
                    if input:isKeep() then
                        need.kept = math.max(need.kept, count)
                    else
                        need.count = need.count + count
                    end
                else
                    table.insert(unmatched, recipe:getName() .. ": " .. input:getOriginalLine())
                end
            end
        end
    end
    for _, need in ipairs(order) do
        need.count = need.count + need.kept
    end
    table.sort(order, function(a, b)
        local ia, ib = getScriptManager():FindItem(a.type), getScriptManager():FindItem(b.type)
        local ca, cb = ia:getDisplayCategory() or "", ib:getDisplayCategory() or ""
        if ca ~= cb then return ca < cb end
        return a.type < b.type
    end)
    return order, unmatched
end

-- A new item of `fullType`, its fluid container filled with `fluid` if given, worn if it is a
-- battery or a module and `worn`.
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
    if worn and RenewableEnergy.Battery.isBattery(item) then
        item:setCondition(WORN_BATTERY)
    elseif worn and RenewableEnergy.Specs.modules[fullType] then
        item:setCondition(CRACKED_MODULE)
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
                Stage.clearGroundCover(square)
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
    PZHarness.Test.learnRecipes(player)
    PZHarness.Fixtures.learnRecipes(player, RenewableEnergy.Debug.buildRecipes())
end

--- Sets the scenario up around `player`, and prints what it laid out, and anything it couldn't,
--- under MARK. Returns that summary.
function QA.setup(player)
    getGameTime():setTimeOfDay(10)
    setUpCharacter(player)
    local summary = { types = 0, items = 0, stations = 0, unknown = {}, unplaced = {}, unmatched = {} }
    local origin = layoutOrigin(player)
    if not origin then
        print(MARK .. " no open row of " .. ROW .. " squares within " .. Stage.SEARCH_RADIUS .. " squares")
        return summary
    end
    summary.lot = lotOpen(origin)
    local layout = newLayout(origin)
    summary.origin = origin
    for _, fullType in ipairs(RenewableEnergy.Debug.ITEMS) do
        lay(layout, summary, fullType, 1)
    end
    nextGroup(layout)
    local needs
    needs, summary.unmatched = materials()
    for _, need in ipairs(needs) do
        lay(layout, summary, need.type, need.count, need.fluid, true)
    end
    -- One module shattered, for Take Apart Shattered Module.
    local shattered = nextSquare(layout)
    if shattered then
        local module = instanceItem(RenewableEnergy.Specs.factoryModule)
        module:setCondition(0)
        shattered:AddWorldInventoryItem(module, 0.5, 0.5, 0)
    end
    nextGroup(layout)
    for _, entry in ipairs(JOB_ITEMS) do
        lay(layout, summary, entry[1], entry[2])
    end
    nextGroup(layout)
    placeStations(layout, summary)
    placeTreadmill(layout, summary)
    placeTrailer(layout, summary)
    -- At the head of the layout, with a table to craft at beside it.
    PZHarness.Fixtures.teleportToMiddle(player, origin:getX(), origin:getY(), origin:getZ())
    PZHarness.Test.placeWorkTable(player)
    print(string.format("%s laid out %d items of %d types from %d,%d (whole lot open: %s), %d stations, trailer %s",
        MARK, summary.items, summary.types, origin:getX(), origin:getY(), tostring(summary.lot), summary.stations,
        tostring(summary.trailer == true)))
    for _, what in ipairs({ "unknown", "unplaced", "unmatched" }) do
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
