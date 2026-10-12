-- Development only; dev/run-debug-client.sh --promo runs it instead of the tests. It builds two
-- working setups near the scenario start at a clear noon, a homestead (a metal battery bank
-- indoors against an outside wall, wall panels on that wall, racks, flat panels and a backup
-- generator in the yard) and a stage-0 wooden battery box indoors by a window with its panels
-- outside, and saves the raw art that art/promo/compose.py lays out for the README and the
-- Workshop page: screenshots named promo_<shot>.png in <cachedir>/Screenshots, and
-- <cachedir>/Lua/REPromo.json, which names the regions of every screenshot and holds the item,
-- recipe and skill names in the game's language.
-- Shots of anything but the world are taken twice, on black (promo_<shot>_k.png) and on white
-- (promo_<shot>_w.png), so that art/promo/extract.py can recover how transparent each pixel is.
require "RenewableEnergy/Debug/RenewableEnergyDebug"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/UI/RenewableEnergyMenu"
require "RenewableEnergy/UI/RenewableEnergyStatusWindow"

RenewableEnergyDevPromo = {}

local Sprites = RenewableEnergy.Sprites

-- The world shots are as wide as the README's images, in UI units.
local WORLD_W = 1260
-- The character faces the camera last.
local LOOK_AROUND = { IsoDirections.N, IsoDirections.E, IsoDirections.S, IsoDirections.W, IsoDirections.SE }
-- How far from each setup the trees go: near a building, a tree out of the character's sight
-- draws as a black silhouette full of holes (IsoTree.render).
local TREE_RADIUS = 30
local SEARCH_RADIUS = 40
-- The banks charge through the morning, so the window shows a day's figures at noon.
local MORNING, NOON = 8, 12
-- Inputs that take any item with a tag show this one.
local PREFER = { "Base.Hammer", "Base.Screwdriver", "Base.Pliers", "Base.Wrench", "Base.HandDrill", "Base.WeldingMask",
    "Base.Saw", "Base.Matches", "Base.Charcoal" }
-- A recipe line that takes or fills any fluid container shows this one, by the fluid's type.
local FLUID_CONTAINERS = { Acid = "RenewableEnergy.BatteryElectrolyte", Water = "Base.WaterBottle" }
local MAGAZINES = { "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2" }
-- Banks take vanilla car batteries as they are, so the item sheet shows one.
local VANILLA_ITEMS = { "Base.CarBattery1" }

-- Both setups stand at an outside wall that the camera sees: the north edge of a square south of
-- a building (preferred: wall panels face south), or the west edge of one east of it. Positions
-- are (along, out) from the square outside the wall: `along` runs along the wall, `out` away
-- from it, so out -1 is indoors; panels face `out`.
local SITES = {
    { wallNorth = true, along = { 1, 0 }, out = { 0, 1 }, facing = "S" },
    { wallNorth = false, along = { 0, 1 }, out = { 1, 0 }, facing = "E" },
}
-- The homestead. Banks stand indoors, so the bank is behind the wall the wall panels hang on, out
-- of the yard shots; the character stands beside it for a shot of its own. Outdoors, the character
-- stands beside the last wall panel, where nothing is behind them, and the backup generator is
-- within a failsafe's reach of the bank.
local HOMESTEAD = {
    bank = { 0, -1 },
    indoors = { 1, -1 },
    generator = { -1, 1 },
    wallPanels = { { 0, 0, "wood" }, { 1, 0, "wood" }, { 2, 0, "metal" } },
    player = { 3, 1 },
    racks = { { -1, 3, "wood" }, { 0, 3, "wood" }, { 1, 3, "metal" }, { 2, 3, "metal" } },
    flatPanels = { { 0, 5 }, { 1, 5 }, { 2, 5 }, { 3, 5 } },
    -- Where the character looks around first, out in the yard the shots also show.
    scouts = { { -4, 3 }, { -3, 8 }, { 2, 9 } },
}
-- The ground that must be clear (grass and weeds are cleared), and the plain wall the wall panels
-- hang on.
local OPEN = { along = { -1, 4 }, out = { 1, 5 } }
local AT_WALL = { 0, 2 }
-- The rack with a cracked module, wired in early so that its row shows in the status window.
local CRACKED_RACK = 1
local CRACKED_CONDITION = 30
local MODULE = "RenewableEnergy.SolarModule"
local HOMESTEAD_BANK = {
    "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery",
    "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.DeepCycleBattery",
    "RenewableEnergy.InverterCharger", "RenewableEnergy.ChargeController", "RenewableEnergy.ChargeController",
    "Base.CarBatteryCharger",
}
-- Lights switched on in the homestead's building, nearest the bank first, so that the status
-- window lists what the bank powers.
local HOUSE_LIGHTS = 3
local LIGHT_SEARCH = 10
local MORNING_CHARGE = 0.55

-- Stage 0, at another building: a battery box indoors beside a window, the character at the
-- window, and the panels, a solar battery charger and a garden light outside in their sight.
-- Positions are (along, out) from the square outside the window, as the homestead's.
local STAGE0 = {
    box = { 1, -1 },
    player = { 0, -1 },
    flatPanels = { { 0, 1 }, { 1, 2 } },
    cellCharger = { -1, 1 },
    gardenLight = { 2, 1 },
    -- Where the character looks around first, among the panels.
    scout = { 0, 2 },
    open = { along = { -1, 2 }, out = { 1, 2 } },
}
local STAGE0_BOX = { "Base.CarBattery1", "Base.CarBattery1", "RenewableEnergy.PlugInInverter", "Base.CarBatteryCharger" }
local STAGE0_DISTANCE = 12
local CELL_BATTERIES = 4

-- JSON -------------------------------------------------------------------------------------------

-- Kahlua has no next(), so an empty table is the one whose pairs() yields nothing.
local function isArray(value)
    if value[1] ~= nil then
        return true
    end
    for _ in pairs(value) do
        return false
    end
    return true
end

local function encode(value, out)
    local kind = type(value)
    if kind == "table" then
        if isArray(value) then
            table.insert(out, "[")
            for i, element in ipairs(value) do
                if i > 1 then
                    table.insert(out, ",")
                end
                encode(element, out)
            end
            table.insert(out, "]")
        else
            local keys = {}
            for key in pairs(value) do
                table.insert(keys, tostring(key))
            end
            table.sort(keys)
            table.insert(out, "{")
            for i, key in ipairs(keys) do
                if i > 1 then
                    table.insert(out, ",")
                end
                encode(key, out)
                table.insert(out, ":")
                encode(value[key], out)
            end
            table.insert(out, "}")
        end
    elseif kind == "string" then
        local escaped = string.gsub(value, '[%c"\\]', function(c)
            return string.format("\\u%04x", string.byte(c))
        end)
        table.insert(out, '"' .. escaped .. '"')
    elseif kind == "number" or kind == "boolean" then
        table.insert(out, tostring(value))
    else
        table.insert(out, "null")
    end
end

local function writeJson(fileName, value)
    local out = {}
    encode(value, out)
    local writer = getFileWriter(fileName, true, false)
    writer:write(table.concat(out))
    writer:close()
end

-- Steps ------------------------------------------------------------------------------------------

local steps = {}
local shots = {}
local tinted = {}

local function add(step)
    table.insert(steps, step)
end

-- Runs each step on its own tick, then waits the number of ticks it returns.
local function runSteps(onDone)
    local index, wait = 1, 0
    local function onTick()
        if wait > 0 then
            wait = wait - 1
            return
        end
        local step = steps[index]
        if not step then
            Events.OnTick.Remove(onTick)
            onDone()
            return
        end
        index = index + 1
        wait = step() or 0
    end
    Events.OnTick.Add(onTick)
end

local function region(name, x, y, w, h)
    return { name = name, x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h) }
end

local function elementRegion(name, element)
    return region(name, element:getAbsoluteX(), element:getAbsoluteY(), element:getWidth(), element:getHeight())
end

local function screenshot(file)
    getCore():TakeFullScreenshot(file .. ".png")
    print("REPromo saved " .. file .. ".png")
end

-- Every tinted element, the backdrop first, takes the backdrop colour.
local function setLevel(level)
    for _, element in ipairs(tinted) do
        element.backgroundColor = { r = level, g = level, b = level, a = 1 }
    end
end

-- Takes the shot on black and on white. regions() runs once the shot is laid out.
local function addMatted(name, regions)
    add(function()
        setLevel(0)
        return 10
    end)
    add(function()
        screenshot("promo_" .. name .. "_k")
        return 10
    end)
    add(function()
        setLevel(1)
        return 10
    end)
    add(function()
        screenshot("promo_" .. name .. "_w")
        table.insert(shots, { name = name, matte = true, regions = regions() })
        return 10
    end)
end

local function addOpaque(name, regions)
    add(function()
        screenshot("promo_" .. name)
        table.insert(shots, { name = name, matte = false, regions = regions() })
        return 10
    end)
end

local function newBackdrop()
    local backdrop = ISPanel:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    backdrop:initialise()
    backdrop:addToUIManager()
    backdrop:setVisible(true)
    tinted = { backdrop }
    return backdrop
end

local function removeBackdrop()
    add(function()
        tinted[1]:removeFromUIManager()
        return 1
    end)
end

-- Names ------------------------------------------------------------------------------------------

local icons = {}
local iconOrder = {}

-- The icon the crafting window draws: the script's, which for a moveable is not the tile the
-- inventory shows.
local function iconTexture(fullType, item)
    local icon = getScriptManager():getItem(fullType):getIcon()
    return icon and getTexture("Item_" .. icon) or item:getTex()
end

-- Registers an item for the icon sheet and returns its key in captures/.
local function iconFor(fullType)
    local key = "icon_" .. string.gsub(fullType, "%.", "_")
    if not icons[key] then
        local item = instanceItem(fullType)
        icons[key] = { fullType = fullType, name = item:getDisplayName(), texture = iconTexture(fullType, item) }
        table.insert(iconOrder, key)
    end
    return key
end

local function itemEntry(fullType, count)
    local key = iconFor(fullType)
    return { icon = key, name = icons[key].name, fullType = fullType, count = count }
end

local function pickInputItem(possible)
    for _, wanted in ipairs(PREFER) do
        for j = 0, possible:size() - 1 do
            if possible:get(j):getFullName() == wanted then
                return wanted
            end
        end
    end
    return possible:get(0):getFullName()
end

-- The fluid of a recipe line's fluid part and the litres it takes or gives: { name, litres }, and
-- the fluid's type.
local function fluidEntry(fluid, litres)
    return { name = fluid:getTranslatedName(), litres = litres }, fluid:getFluidTypeString()
end

-- One input line: the items it names (every one, as alternatives, with what each takes), or for
-- a tag or any item the preferred one. A line that takes a fluid from a container (`fluid`), or
-- pours one into an empty container the player keeps (`fills`), says which and how much; `tag`
-- marks a line whose item only stands for the many it takes.
local function inputEntry(input)
    local names, counts = {}, {}
    local listed = input:getItems()
    for i = 0, listed:size() - 1 do
        local fullType = listed:get(i)
        if not string.find(fullType, "%.") then
            fullType = "Base." .. fullType
        end
        table.insert(names, fullType)
        table.insert(counts, input:getIntAmount(i))
    end
    local entry = { items = {}, count = input:getIntAmount(), keep = input:isKeep(), tag = #names == 0 }
    local fluidType
    if input:hasConsumeFromItem() then
        local consume = input:getConsumeFromItemScript()
        local fluids = consume:getPossibleInputFluids()
        if fluids:size() > 0 then
            entry.fluid, fluidType = fluidEntry(fluids:get(0), consume:getAmount())
        end
    elseif input:hasCreateToItem() then
        local create = input:getCreateToItemScript()
        if create:getFluid() then
            entry.fills, fluidType = fluidEntry(create:getFluid(), create:getAmount())
        end
    end
    if #names == 0 then
        names = { FLUID_CONTAINERS[fluidType] or pickInputItem(input:getPossibleInputItems()) }
        counts = { entry.count }
    end
    local first = getScriptManager():getItem(names[1])
    -- A drainable input counts uses unless it says ItemCount.
    entry.uses = first:isItemType(ItemType.DRAINABLE) and not input:isItemCount()
    for i, fullType in ipairs(names) do
        table.insert(entry.items, itemEntry(fullType, counts[i]))
    end
    return entry
end

local function skillList(count, get)
    local skills = {}
    for i = 0, count - 1 do
        local skill = get(i)
        table.insert(skills, { name = skill:getPerk():getName(), level = skill:getLevel() })
    end
    return skills
end

-- The magazines that teach a recipe.
local function magazinesTeaching(name)
    local found = {}
    for _, fullType in ipairs(MAGAZINES) do
        local learned = getScriptManager():getItem(fullType):getLearnedRecipes()
        for i = 0, (learned and learned:size() or 0) - 1 do
            if learned:get(i) == name then
                table.insert(found, getItemNameFromFullType(fullType))
            end
        end
    end
    return found
end

local function recipeEntry(name)
    local recipe = getScriptManager():getCraftRecipe(name)
    local entry = {
        id = name,
        name = getRecipeDisplayName(name),
        skills = skillList(recipe:getRequiredSkillCount(), function(i) return recipe:getRequiredSkill(i) end),
        learn = {
            needed = recipe:needToBeLearn(),
            magazines = magazinesTeaching(name),
            auto = skillList(recipe:getAutoLearnAnySkillCount(), function(i) return recipe:getAutoLearnAnySkill(i) end),
        },
        inputs = {},
        outputs = {},
    }
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        table.insert(entry.inputs, inputEntry(inputs:get(i)))
    end
    local outputs = recipe:getOutputs()
    for i = 0, outputs:size() - 1 do
        local output = outputs:get(i)
        table.insert(entry.outputs, itemEntry(output:getPossibleResultItems():get(0):getFullName(), output:getIntAmount()))
    end
    return entry
end

local function itemsList()
    local items = {}
    for _, fullType in ipairs(RenewableEnergyDebug.ITEMS) do
        -- The annotated maps are loot, not something to build with.
        if getScriptManager():getItem(fullType):getMapID() == nil then
            table.insert(items, itemEntry(fullType))
        end
    end
    for _, fullType in ipairs(VANILLA_ITEMS) do
        table.insert(items, itemEntry(fullType))
    end
    return items
end

-- Icons ------------------------------------------------------------------------------------------

local IconSheet = ISPanel:derive("RenewableEnergyDevPromoIconSheet")

function IconSheet:render()
    for _, icon in ipairs(self.icons) do
        self:drawTextureScaled(icon.texture, icon.x, icon.y, icon.w, icon.h, 1, 1, 1, 1)
    end
end

local function addIcons()
    local sheet
    add(function()
        local backdrop = newBackdrop()
        sheet = IconSheet:new(100, 100, getCore():getScreenWidth() - 200, getCore():getScreenHeight() - 200)
        sheet:noBackground()
        sheet.icons = {}
        local x, y, rowHeight = 0, 0, 0
        for _, key in ipairs(iconOrder) do
            local texture = icons[key].texture
            local w, h = texture:getWidthOrig(), texture:getHeightOrig()
            if x + w > sheet.width then
                x, y, rowHeight = 0, y + rowHeight + 32, 0
            end
            table.insert(sheet.icons, { name = key, texture = texture, x = x, y = y, w = w, h = h })
            x = x + w + 32
            rowHeight = math.max(rowHeight, h)
        end
        backdrop:addChild(sheet)
        return 10
    end)
    addMatted("icons", function()
        local regions = {}
        for _, icon in ipairs(sheet.icons) do
            table.insert(regions, region(icon.name, sheet:getAbsoluteX() + icon.x, sheet:getAbsoluteY() + icon.y, icon.w, icon.h))
        end
        return regions
    end)
    removeBackdrop()
end

-- World ------------------------------------------------------------------------------------------

local function position(object)
    return { x = object:getX(), y = object:getY(), z = object:getZ() }
end

local function perform(name, args)
    local ok, reason = RenewableEnergy.PowerBank.perform(getPlayer(), name, args)
    if not ok then
        print("REPromo " .. name .. " failed: " .. tostring(reason))
    end
end

-- Grass, weeds and bushes a character could pull up (as vanilla's remove-grass and building code
-- tell them from other objects). The setups clear them off their squares.
local function isGroundCover(object)
    local props = object:getProperties()
    return props ~= nil and (props:has(IsoFlagType.canBeRemoved)
        or (props:has(IsoFlagType.vegitation) and object:getType() ~= IsoObjectType.tree))
end

local function clearGroundCover(square)
    local objects = square and square:getObjects()
    for i = (objects and objects:size() or 0) - 1, 0, -1 do
        if isGroundCover(objects:get(i)) then
            square:RemoveTileObject(objects:get(i))
        end
    end
end

-- Outdoors on solid floor, with no tree or vehicle, and nothing but the floor, ground cover and
-- the objects `allowed` accepts. A square's walls are objects on it, so walls count too.
local function isClear(square, allowed)
    if not (square and square:isOutside() and square:isSolidFloor() and not square:HasTree()
        and square:getVehicleContainer() == nil) then
        return false
    end
    local floor = square:getFloor()
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object ~= floor and not isGroundCover(object) and not (allowed and allowed(object)) then
            return false
        end
    end
    return true
end

local function isOpen(square, player)
    return isClear(square) and square ~= player:getCurrentSquare()
end

-- Walls, their trim and what hangs on them: lamps, pipes, signs.
local WALL_FLAGS = { IsoFlagType.cutN, IsoFlagType.cutW, IsoFlagType.WallOverlay, IsoFlagType.attachedN,
    IsoFlagType.attachedW, IsoFlagType.attachedS, IsoFlagType.attachedE }

local function isOnWall(object)
    local props = object:getProperties()
    for _, flag in ipairs(WALL_FLAGS) do
        if props and props:has(flag) then
            return true
        end
    end
    return false
end

local function siteSquare(site, origin, along, out)
    return getCell():getGridSquare(origin:getX() + along * site.along[1] + out * site.out[1],
        origin:getY() + along * site.along[2] + out * site.out[2], origin:getZ())
end

-- Outdoors, against a wall of a room. A panel hangs on a `plain` wall: not a door, a garage door
-- or a window.
local function isAtWall(site, origin, along, plain)
    local square, inside = siteSquare(site, origin, along, 0), siteSquare(site, origin, along, -1)
    if not (square and inside and inside:getRoom() and square:getWall(site.wallNorth) and isClear(square, isOnWall)) then
        return false
    end
    return not plain or (square:getDoorOrWindow(site.wallNorth) == nil and square:getGarageDoor(site.wallNorth) == nil)
end

-- Whether the outside wall at `along` has a window into a room.
local function hasWindow(site, origin, along)
    local square, inside = siteSquare(site, origin, along, 0), siteSquare(site, origin, along, -1)
    return square ~= nil and inside ~= nil and inside:getRoom() ~= nil and square:isOutside()
        and instanceof(square:getDoorOrWindow(site.wallNorth), "IsoWindow")
end

local function hasContainerOrGenerator(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object:getContainer() or instanceof(object, "IsoGenerator") or RenewableEnergy.PowerBank.sourceKind(object) then
            return true
        end
    end
    return false
end

-- Indoors where a bank may stand, with nothing in the way, as the tests find one.
local function isFreeIndoors(square)
    return square ~= nil and RenewableEnergy.PowerBank.canPlaceBank(square) and square:isFree(false)
        and square:getVehicleContainer() == nil and not hasContainerOrGenerator(square)
end

local function isFreeIndoorsAt(site, origin, position)
    return isFreeIndoors(siteSquare(site, origin, position[1], position[2]))
end

local function isOpenArea(site, origin, player, area)
    for along = area.along[1], area.along[2] do
        for out = area.out[1], area.out[2] do
            if not isOpen(siteSquare(site, origin, along, out), player) then
                return false
            end
        end
    end
    return true
end

local function fits(site, origin, player)
    for along = AT_WALL[1], AT_WALL[2] do
        if not isAtWall(site, origin, along, true) then
            return false
        end
    end
    return isFreeIndoorsAt(site, origin, HOMESTEAD.bank) and isFreeIndoorsAt(site, origin, HOMESTEAD.indoors)
        and isOpenArea(site, origin, player, OPEN)
end

-- At a window if `needWindow`, else at any outside wall.
local function fitsStage0(site, origin, player, needWindow)
    local window = hasWindow(site, origin, 0)
    if (needWindow and not window) or not (window or isAtWall(site, origin, 0, false)) then
        return false
    end
    return isFreeIndoorsAt(site, origin, STAGE0.box) and isFreeIndoorsAt(site, origin, STAGE0.player)
        and isOpenArea(site, origin, player, STAGE0.open)
end

-- The square closest to the character for which `accepts(origin)` holds, or nil.
local function closest(player, accepts)
    local here = player:getCurrentSquare()
    local best, bestDistance
    for dx = -SEARCH_RADIUS, SEARCH_RADIUS do
        for dy = -SEARCH_RADIUS, SEARCH_RADIUS do
            local distance = dx * dx + dy * dy
            if not bestDistance or distance < bestDistance then
                local origin = getCell():getGridSquare(here:getX() + dx, here:getY() + dy, here:getZ())
                if origin and accepts(origin) then
                    best, bestDistance = origin, distance
                end
            end
        end
    end
    return best
end

-- The closest place to the character that takes the whole homestead, facing south if any does.
local function findSite(player)
    for _, site in ipairs(SITES) do
        local best = closest(player, function(origin)
            return fits(site, origin, player)
        end)
        if best then
            return site, best
        end
    end
    return nil
end

-- The closest place for stage 0 clear of the homestead: at a window if any, facing south first.
local function findStage0(player, homestead)
    for _, needWindow in ipairs({ true, false }) do
        for _, site in ipairs(SITES) do
            local best = closest(player, function(origin)
                local clear = math.abs(origin:getX() - homestead:getX()) >= STAGE0_DISTANCE
                    or math.abs(origin:getY() - homestead:getY()) >= STAGE0_DISTANCE
                return clear and fitsStage0(site, origin, player, needWindow)
            end)
            if best then
                return site, best, needWindow
            end
        end
    end
    return nil
end

local function removeTrees(center)
    for dx = -TREE_RADIUS, TREE_RADIUS do
        for dy = -TREE_RADIUS, TREE_RADIUS do
            local square = getCell():getGridSquare(center:getX() + dx, center:getY() + dy, center:getZ())
            local tree = square and square:getTree()
            if tree then
                square:RemoveTileObject(tree)
            end
        end
    end
end

-- A placed tile, as the tests place one. A panel mount holds `modules` (a PowerBank.MODULES list),
-- or without them whole factory modules.
local function placeTile(square, spriteName, modules)
    local object = IsoObject.new(square, spriteName, spriteName)
    if modules then
        object:getModData()[RenewableEnergy.PowerBank.MODULES] = modules
    end
    square:AddTileObject(object)
    square:RecalcAllWithNeighbours(true)
    return object
end

-- Puts the parts straight into the bank's container, as world spawns stock a bank, then has the
-- bank count them.
local function fillBank(bank, items, charge)
    local container = bank:getContainer()
    for _, fullType in ipairs(items) do
        local item = container:AddItem(fullType)
        if RenewableEnergy.Battery.isBattery(item) then
            RenewableEnergy.Battery.setCharge(item, charge)
        end
    end
    perform("refresh", { bank = position(bank) })
end

local function connect(bank, panel)
    perform("connectSource", { bank = position(bank), source = position(panel) })
end

-- A clear, still day: no cloud, fog or rain however the weather turns while the shots run.
local function clearWeather()
    local climate = getClimateManager()
    climate:stopWeatherAndThunder()
    for _, id in ipairs({ ClimateManager.FLOAT_CLOUD_INTENSITY, ClimateManager.FLOAT_FOG_INTENSITY,
        ClimateManager.FLOAT_PRECIPITATION_INTENSITY }) do
        local float = climate:getClimateFloat(id)
        float:setEnableAdmin(true)
        float:setAdminValue(0)
    end
end

-- Switches on lights in the building around `square`, nearest first. They draw on the bank,
-- which is the only power with the grid off.
local function switchOnLights(square)
    local building = square:getBuilding()
    local switched = 0
    for radius = 0, LIGHT_SEARCH do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local near = math.max(math.abs(dx), math.abs(dy)) == radius
                    and getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                local objects = near and building and near:getBuilding() == building and near:getObjects()
                for i = 0, (objects and objects:size() or 0) - 1 do
                    local object = objects:get(i)
                    if switched < HOUSE_LIGHTS and instanceof(object, "IsoLightSwitch") and not object:isActivated()
                        and object:setActive(true, false, true) then
                        switched = switched + 1
                    end
                end
            end
        end
    end
    print("REPromo switched on " .. switched .. " lights")
end

local site, origin, stage0Site, stage0Origin
local homesteadBank, stage0Box

local function at(position)
    return siteSquare(site, origin, position[1], position[2])
end

local function atStage0(position)
    return siteSquare(stage0Site, stage0Origin, position[1], position[2])
end

local function buildHomestead()
    for along = OPEN.along[1], OPEN.along[2] do
        for out = 0, OPEN.out[2] do
            clearGroundCover(at({ along, out }))
        end
    end
    homesteadBank = RenewableEnergy.PowerBank.place(at(HOMESTEAD.bank), Sprites.batteryBankMetal, -1)
    fillBank(homesteadBank, HOMESTEAD_BANK, MORNING_CHARGE)
    for _, spot in ipairs(HOMESTEAD.wallPanels) do
        connect(homesteadBank, placeTile(at(spot), Sprites.wall[spot[3]][site.facing]))
    end
    for i, spot in ipairs(HOMESTEAD.racks) do
        local modules = i == CRACKED_RACK
            and { { type = MODULE, condition = CRACKED_CONDITION }, { type = MODULE, condition = 100 } } or nil
        connect(homesteadBank, placeTile(at(spot), Sprites.rack[spot[3]][site.facing], modules))
    end
    for _, spot in ipairs(HOMESTEAD.flatPanels) do
        connect(homesteadBank, placeTile(at(spot), Sprites.flat))
    end
    -- A backup generator with a failsafe outside the bank's wall, plugged in and waiting.
    local generatorSquare = at(HOMESTEAD.generator)
    local generator = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), generatorSquare)
    generator:setConnected(true)
    generator:setFuel(generator:getMaxFuel() * 0.7)
    placeTile(generatorSquare, Sprites.failsafe)
    perform("setBankOn", { bank = position(homesteadBank), on = true })
    switchOnLights(homesteadBank:getSquare())
end

local function buildStage0()
    for along = STAGE0.open.along[1], STAGE0.open.along[2] do
        for out = STAGE0.open.out[1], STAGE0.open.out[2] do
            clearGroundCover(atStage0({ along, out }))
        end
    end
    stage0Box = RenewableEnergy.PowerBank.place(atStage0(STAGE0.box), Sprites.batteryBoxWood, -1)
    fillBank(stage0Box, STAGE0_BOX, MORNING_CHARGE)
    for _, spot in ipairs(STAGE0.flatPanels) do
        connect(stage0Box, placeTile(atStage0(spot), Sprites.flat))
    end
    local charger = placeTile(atStage0(STAGE0.cellCharger), Sprites.cellCharger)
    if not charger:getContainer() then
        charger:createContainersFromSpriteProperties()
    end
    for _ = 1, CELL_BATTERIES do
        local battery = charger:getContainer():AddItem(RenewableEnergy.SolarCellCharger.BATTERY)
        battery:setCurrentUsesFloat(0.5)
    end
    -- Set out the way garden light spawns set one out, charged and unlit by day.
    RenewableEnergy.WorldSpawns.placeMoveable(atStage0(STAGE0.gardenLight), Sprites.gardenLight.off,
        { [RenewableEnergy.SolarGardenLight.CHARGE_KEY] = RenewableEnergy.Specs.gardenLight.wh })
    perform("setBankOn", { bank = position(stage0Box), on = true })
end

-- Bank passes hour by hour from the morning to noon, as the game's own passes would have run.
local function chargeThroughMorning()
    local BankSystem = require "RenewableEnergy/PowerBank/BankSystem"
    local system = RenewableEnergy.PowerBank.serverSystem
    local banks = { system:getLuaObjectOnSquare(homesteadBank:getSquare()), system:getLuaObjectOnSquare(stage0Box:getSquare()) }
    -- The first pass only starts the clock of a bank that has never run one.
    for hour = MORNING, NOON do
        getGameTime():setTimeOfDay(hour)
        for _, bank in ipairs(banks) do
            BankSystem.updateBank(bank)
        end
    end
end

-- Where a square's floor centre is on the screen, in UI units.
local function onScreen(square)
    local x, y, z = square:getX() + 0.5, square:getY() + 0.5, square:getZ()
    return isoToScreenX(0, x, y, z), isoToScreenY(0, x, y, z)
end

-- The screen rectangle a set of squares and what stands on them take up, in UI units. A square's
-- diamond is 128 by 64 units at zoom 1, and its tile reaches this far above the floor's centre.
local TILE_TOP = 224

local function screenBox(squares)
    local zoom = getCore():getZoom(0)
    local halfW, halfH = 64 / zoom, 32 / zoom
    local box = { left = math.huge, right = -math.huge, top = math.huge, bottom = -math.huge }
    for _, square in ipairs(squares) do
        local x, y = onScreen(square)
        box.left = math.min(box.left, x - halfW)
        box.right = math.max(box.right, x + halfW)
        box.top = math.min(box.top, y - TILE_TOP / zoom)
        box.bottom = math.max(box.bottom, y + halfH)
    end
    return box
end

-- What the yard shots show; the bank stands indoors behind the wall, out of them.
local function homesteadSquares()
    local squares = { at(HOMESTEAD.generator), at(HOMESTEAD.player) }
    for _, list in ipairs({ HOMESTEAD.wallPanels, HOMESTEAD.racks, HOMESTEAD.flatPanels }) do
        for _, spot in ipairs(list) do
            table.insert(squares, at(spot))
        end
    end
    return squares
end

local function bankSquares()
    return { at(HOMESTEAD.bank), at(HOMESTEAD.indoors) }
end

local function stage0Squares()
    local squares = { atStage0(STAGE0.box), atStage0(STAGE0.player), atStage0(STAGE0.cellCharger), atStage0(STAGE0.gardenLight) }
    for _, spot in ipairs(STAGE0.flatPanels) do
        table.insert(squares, atStage0(spot))
    end
    return squares
end

local CROP_MARGIN = 40

-- A crop of the README's width from `left`, around `box`, kept on the screen: what lies past
-- its edge comes out black.
local function worldRegion(name, left, box)
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local top = math.max(0, box.top - CROP_MARGIN)
    local bottom = math.min(screenH, box.bottom + CROP_MARGIN)
    return region(name, math.max(0, math.min(screenW - WORLD_W, left)), top, WORLD_W, bottom - top)
end

-- `squares` against the right edge, with room on the left for a title.
local function rightAligned(name, squares)
    local box = screenBox(squares)
    return worldRegion(name, box.right + CROP_MARGIN - WORLD_W, box)
end

-- `squares` in the middle.
local function centred(name, squares)
    local box = screenBox(squares)
    return worldRegion(name, (box.left + box.right - WORLD_W) / 2, box)
end

-- Just `squares`, for an inset.
local function cropped(name, squares)
    local box = screenBox(squares)
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local left, top = math.max(0, box.left - CROP_MARGIN), math.max(0, box.top - CROP_MARGIN)
    local right, bottom = math.min(screenW, box.right + CROP_MARGIN), math.min(screenH, box.bottom + CROP_MARGIN)
    return region(name, left, top, right - left, bottom - top)
end

-- Has the character look around from each of `squares` and stay on the last, since squares they
-- never saw are drawn dark, and sets the zoom `stepsOut` steps out from the closest.
local function goTo(squares, stepsOut)
    local player = getPlayer()
    for _, square in ipairs(squares) do
        add(function()
            player:teleportTo(square:getX() + 0.5, square:getY() + 0.5, square:getZ())
            return 30
        end)
        for _, direction in ipairs(LOOK_AROUND) do
            add(function()
                player:faceDirection(direction)
                return 40
            end)
        end
    end
    add(function()
        for _ = 1, 8 do
            getCore():doZoomScroll(0, -1)
        end
        for _ = 1, stepsOut do
            getCore():doZoomScroll(0, 1)
        end
        return 200
    end)
end

local function addWorld()
    add(function()
        -- The grid would power the squares and leave the bank nothing to run.
        local option = getSandboxOptions():getOptionByName("ElecShutModifier")
        if option then
            option:setValue(-1)
        end
        getWorld():setHydroPowerOn(false)
        clearWeather()
        getGameTime():setTimeOfDay(MORNING)
        removeTrees(origin)
        removeTrees(stage0Origin)
        buildHomestead()
        buildStage0()
        chargeThroughMorning()
        return 30
    end)
    -- A step out from the closest zoom, which leaves too little of the house around the panels.
    local scouts = {}
    for _, spot in ipairs(HOMESTEAD.scouts) do
        local square = at(spot)
        if square then
            table.insert(scouts, square)
        end
    end
    table.insert(scouts, at(HOMESTEAD.player))
    goTo(scouts, 1)
    addOpaque("homestead", function()
        return { centred("homestead", homesteadSquares()) }
    end)
    -- The banner shows the whole homestead a step further out.
    add(function()
        getCore():doZoomScroll(0, 1)
        return 200
    end)
    addOpaque("world", function()
        return { rightAligned("world", homesteadSquares()) }
    end)
    -- Indoors beside the bank, where the building's near walls are cut away, at the closest zoom.
    goTo({ at(HOMESTEAD.indoors) }, 0)
    addOpaque("bank", function()
        return { cropped("bank", bankSquares()) }
    end)
    -- Stage 0 is small, so it gets the closest zoom too. The character sees the panels first from
    -- among them, then from the window.
    goTo({ atStage0(STAGE0.scout), atStage0(STAGE0.player) }, 0)
    addOpaque("stage0", function()
        return { centred("stage0", stage0Squares()) }
    end)
end

-- The homestead bank's status window on a backdrop.
local function addStatus()
    local window
    add(function()
        newBackdrop()
        window = RenewableEnergy.StatusWindow.open(0, RenewableEnergy.Menu.bankOnSquare(at(HOMESTEAD.bank)))
        window:setX(100)
        window:setY(100)
        return 120
    end)
    addMatted("status", function()
        return { elementRegion("status", window) }
    end)
    add(function()
        window:close()
        return 1
    end)
    removeBackdrop()
end

function RenewableEnergyDevPromo.capture(onDone)
    print("REPromo START")
    local player = getPlayer()
    local atWindow
    site, origin = findSite(player)
    if site then
        stage0Site, stage0Origin, atWindow = findStage0(player, origin)
    end
    if not (site and stage0Site) then
        -- Without "REPromo DONE", run-debug-client.sh reports the run as failed.
        print("REPromo FAIL: within " .. SEARCH_RADIUS .. " squares, no " .. (site
            and "outside wall with free floor indoors behind it and open ground in front, for stage 0"
            or "plain building wall with free floor indoors behind it and open ground in front"))
        getCore():quitToDesktop()
        return
    end
    print(string.format("REPromo homestead %d,%d facing %s; stage 0 %d,%d facing %s, %s", origin:getX(), origin:getY(),
        site.facing, stage0Origin:getX(), stage0Origin:getY(), stage0Site.facing, atWindow and "at a window" or "at a wall"))
    -- Hides the HUD, the debug console and every other window; the shots add their own.
    ISUIHandler.setVisibleAllUI(false)
    local data = { items = itemsList(), recipes = {} }
    for _, name in ipairs(RenewableEnergyDebug.recipeNames()) do
        table.insert(data.recipes, recipeEntry(name))
    end
    data.strings = {
        modName = getText("Sandbox_RenewableEnergy"),
    }
    addWorld()
    addStatus()
    addIcons()
    runSteps(function()
        for name, bank in pairs({ homestead = homesteadBank, ["stage 0"] = stage0Box }) do
            local status = RenewableEnergy.PowerBank.getStatus(bank:getX(), bank:getY(), bank:getZ())
            local reasons, kinds = {}, {}
            for _, source in ipairs(status.sources) do
                table.insert(reasons, tostring(source.reason))
            end
            for _, kind in ipairs(status.loadByKind) do
                table.insert(kinds, string.format("%d %s %.0f W", kind.count, kind.kind, kind.watts))
            end
            print(string.format("REPromo %s bank: %s, %.0f W in, %.0f W load of %.0f W (%s), %.0f%% charged,"
                .. " %d of %d panel slots, panel reasons %s", name, status.state, status.inW, status.loadW, status.limitW,
                table.concat(kinds, ", "), status.charge * 100, status.panelSlots.used, status.panelSlots.total,
                table.concat(reasons, ",")))
        end
        data.screen = { w = getCore():getScreenWidth(), h = getCore():getScreenHeight() }
        data.shots = shots
        writeJson("REPromo.json", data)
        onDone()
    end)
end
