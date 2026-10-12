-- Development only; dev/run-debug-client.sh --promo runs it instead of the tests. It builds two
-- working setups near the scenario start at a clear noon, a homestead bank against a house and a
-- stage-0 battery box on open ground, and saves the raw art that art/promo/compose.py lays out
-- for the README and the Workshop page: screenshots named promo_<shot>.png in
-- <cachedir>/Screenshots, and <cachedir>/Lua/REPromo.json, which names the regions of every
-- screenshot and holds the item, recipe and skill names in the game's language.
-- Shots of anything but the world are taken twice, on black (promo_<shot>_k.png) and on white
-- (promo_<shot>_w.png), so that art/promo/extract.py can recover how transparent each pixel is.
require "RenewableEnergy/Debug/RenewableEnergyDebug"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Gadgets/SolarCellCharger"
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
local PREFER = { "Base.Hammer", "Base.Screwdriver", "Base.Pliers", "Base.Wrench", "Base.HandDrill", "Base.WeldingMask" }
local MAGAZINES = { "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2" }
-- Banks take vanilla car batteries as they are, so the item sheet shows one.
local VANILLA_ITEMS = { "Base.CarBattery1" }

-- The homestead: a battery bank against a building wall with open ground in front of it, in
-- either direction the camera sees the outside of: the north edge of a square south of a
-- building (preferred: the wall panels face south), or the west edge of one east of it.
-- `along` runs along the wall and `out` away from it; panels face `out`.
local SITES = {
    { wallNorth = true, along = { 1, 0 }, out = { 0, 1 }, facing = "S" },
    { wallNorth = false, along = { 0, 1 }, out = { 1, 0 }, facing = "E" },
}
-- Where everything goes, as (along, out) from the bank's square. The character stands beside the
-- last wall panel, where nothing is behind them, and the backup generator in front of the bank.
local HOMESTEAD = {
    generator = { -1, 1 },
    bank = { 0, 0 },
    wallPanels = { { 1, 0 }, { 2, 0 } },
    player = { 3, 1 },
    racks = { { -1, 3 }, { 0, 3 }, { 1, 3 }, { 2, 3 } },
    flatPanels = { { 0, 5 }, { 1, 5 }, { 2, 5 }, { 3, 5 } },
    -- Where the character looks around first, out in the yard the shots also show.
    scouts = { { -4, 3 }, { -3, 8 }, { 2, 9 } },
}
-- The ground that must be clear (grass and weeds are cleared), and the squares against the wall.
local OPEN = { along = { -1, 4 }, out = { 1, 5 } }
local AT_WALL = { 0, 2 }
local HOMESTEAD_BANK = {
    "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery",
    "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.DeepCycleBattery",
    "RenewableEnergy.InverterCharger", "RenewableEnergy.ChargeController", "RenewableEnergy.ChargeController",
}
local MORNING_CHARGE = 0.55

-- Stage 0, in a yard away from the homestead: squares east and south of the lot's north-west
-- corner. The lot is grass with a free square all round, since anything that blocks the
-- character's sight draws the ground behind it dark.
local STAGE0 = {
    area = { w = 7, h = 7 },
    box = { 2, 2 },
    flatPanel = { 3, 1 },
    cellCharger = { 3, 3 },
    -- Beside the box rather than in front of it.
    player = { 1, 2 },
}
local NATURAL_FLOOR = "^blends_natural"
local STAGE0_BOX = { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }
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

-- One input line: the items it names (every one, as alternatives), or for a tag the preferred
-- item that carries it.
local function inputEntry(input)
    local names = {}
    local listed = input:getItems()
    for i = 0, listed:size() - 1 do
        local fullType = listed:get(i)
        if not string.find(fullType, "%.") then
            fullType = "Base." .. fullType
        end
        table.insert(names, fullType)
    end
    if #names == 0 then
        names = { pickInputItem(input:getPossibleInputItems()) }
    end
    local first = getScriptManager():getItem(names[1])
    local entry = {
        items = {},
        count = input:getIntAmount(),
        keep = input:isKeep(),
        -- A drainable input counts uses unless it says ItemCount.
        uses = first:isItemType(ItemType.DRAINABLE) and not input:isItemCount(),
    }
    for _, fullType in ipairs(names) do
        table.insert(entry.items, itemEntry(fullType))
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
        -- Expanded recipes are listed only while their sandbox option is on.
        expanded = recipe:getOnAddToMenu() ~= nil,
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

local function fits(site, origin, player)
    for along = AT_WALL[1], AT_WALL[2] do
        -- The bank may stand in front of any wall; the wall panels hang beside it.
        if not isAtWall(site, origin, along, along ~= HOMESTEAD.bank[1]) then
            return false
        end
    end
    for along = OPEN.along[1], OPEN.along[2] do
        for out = OPEN.out[1], OPEN.out[2] do
            if not isOpen(siteSquare(site, origin, along, out), player) then
                return false
            end
        end
    end
    return true
end

-- The closest place to the character that takes the whole homestead, facing south if any does.
local function findSite(player)
    local here = player:getCurrentSquare()
    for _, site in ipairs(SITES) do
        local best, bestDistance
        for dx = -SEARCH_RADIUS, SEARCH_RADIUS do
            for dy = -SEARCH_RADIUS, SEARCH_RADIUS do
                local distance = dx * dx + dy * dy
                if not bestDistance or distance < bestDistance then
                    local origin = getCell():getGridSquare(here:getX() + dx, here:getY() + dy, here:getZ())
                    if origin and fits(site, origin, player) then
                        best, bestDistance = origin, distance
                    end
                end
            end
        end
        if best then
            return site, best
        end
    end
    return nil
end

-- The north-west corner of the closest grass lot for stage 0 that is clear of the homestead.
local function findLot(player, homestead)
    local here = player:getCurrentSquare()
    local best, bestDistance
    local function isGrass(square)
        local floor = isOpen(square, player) and square:getFloor()
        return floor and string.find(floor:getSprite():getName() or "", NATURAL_FLOOR) ~= nil
    end
    local function lotFits(cornerX, cornerY, z)
        for x = cornerX, cornerX + STAGE0.area.w - 1 do
            for y = cornerY, cornerY + STAGE0.area.h - 1 do
                if not isGrass(getCell():getGridSquare(x, y, z)) then
                    return false
                end
            end
        end
        return true
    end
    for dx = -SEARCH_RADIUS, SEARCH_RADIUS do
        for dy = -SEARCH_RADIUS, SEARCH_RADIUS do
            local x, y = here:getX() + dx, here:getY() + dy
            local distance = dx * dx + dy * dy
            local clear = math.abs(x - homestead:getX()) >= STAGE0_DISTANCE or math.abs(y - homestead:getY()) >= STAGE0_DISTANCE
            if clear and (not bestDistance or distance < bestDistance) and lotFits(x, y, here:getZ()) then
                best, bestDistance = getCell():getGridSquare(x, y, here:getZ()), distance
            end
        end
    end
    return best
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

local function placeTile(square, spriteName)
    local object = IsoObject.new(square, spriteName, spriteName)
    square:AddTileObject(object)
    square:RecalcAllWithNeighbours(true)
    return object
end

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

local site, origin, lot
local homesteadBank, stage0Box

local function at(position)
    return siteSquare(site, origin, position[1], position[2])
end

local function onLot(position)
    return getCell():getGridSquare(lot:getX() + position[1], lot:getY() + position[2], lot:getZ())
end

local function buildHomestead()
    for along = OPEN.along[1], OPEN.along[2] do
        for out = 0, OPEN.out[2] do
            clearGroundCover(at({ along, out }))
        end
    end
    homesteadBank = RenewableEnergy.PowerBank.place(at(HOMESTEAD.bank), Sprites.batteryBank, -1)
    fillBank(homesteadBank, HOMESTEAD_BANK, MORNING_CHARGE)
    for _, spot in ipairs(HOMESTEAD.wallPanels) do
        connect(homesteadBank, placeTile(at(spot), Sprites.wall[site.facing]))
    end
    for _, spot in ipairs(HOMESTEAD.racks) do
        connect(homesteadBank, placeTile(at(spot), Sprites.rack[site.facing]))
    end
    for _, spot in ipairs(HOMESTEAD.flatPanels) do
        connect(homesteadBank, placeTile(at(spot), Sprites.flat))
    end
    -- A backup generator with a failsafe beside the bank, plugged in and waiting.
    local generatorSquare = at(HOMESTEAD.generator)
    local generator = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), generatorSquare)
    generator:setConnected(true)
    generator:setFuel(generator:getMaxFuel() * 0.7)
    placeTile(generatorSquare, Sprites.failsafe)
    perform("setBankOn", { bank = position(homesteadBank), on = true })
end

local function buildStage0()
    for x = 0, STAGE0.area.w - 1 do
        for y = 0, STAGE0.area.h - 1 do
            clearGroundCover(onLot({ x, y }))
        end
    end
    stage0Box = RenewableEnergy.PowerBank.place(onLot(STAGE0.box), Sprites.batteryBox, -1)
    fillBank(stage0Box, STAGE0_BOX, MORNING_CHARGE)
    connect(stage0Box, placeTile(onLot(STAGE0.flatPanel), Sprites.flat))
    local charger = placeTile(onLot(STAGE0.cellCharger), Sprites.cellCharger)
    if not charger:getContainer() then
        charger:createContainersFromSpriteProperties()
    end
    for _ = 1, CELL_BATTERIES do
        local battery = charger:getContainer():AddItem(RenewableEnergy.SolarCellCharger.BATTERY)
        battery:setCurrentUsesFloat(0.5)
    end
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

local function homesteadSquares()
    local squares = { at(HOMESTEAD.generator), at(HOMESTEAD.bank), at(HOMESTEAD.player) }
    for _, list in ipairs({ HOMESTEAD.wallPanels, HOMESTEAD.racks, HOMESTEAD.flatPanels }) do
        for _, spot in ipairs(list) do
            table.insert(squares, at(spot))
        end
    end
    return squares
end

local function stage0Squares()
    local squares = {}
    for _, key in ipairs({ "box", "flatPanel", "cellCharger", "player" }) do
        table.insert(squares, onLot(STAGE0[key]))
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
        removeTrees(lot)
        buildHomestead()
        buildStage0()
        chargeThroughMorning()
        return 30
    end)
    -- A step out from the closest zoom, which leaves too little of the house around the bank.
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
    -- Stage 0 is small, so it gets the closest zoom.
    goTo({ onLot(STAGE0.player) }, 0)
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
    site, origin = findSite(player)
    lot = site and findLot(player, origin)
    if not (site and lot) then
        -- Without "REPromo DONE", run-debug-client.sh reports the run as failed.
        print("REPromo FAIL: within " .. SEARCH_RADIUS .. " squares, no "
            .. (site and "grass lot for stage 0" or "open ground against a plain building wall"))
        getCore():quitToDesktop()
        return
    end
    print(string.format("REPromo homestead %d,%d facing %s; stage 0 at %d,%d", origin:getX(), origin:getY(), site.facing,
        lot:getX(), lot:getY()))
    -- Hides the HUD, the debug console and every other window; the shots add their own.
    ISUIHandler.setVisibleAllUI(false)
    local data = { items = itemsList(), recipes = {} }
    for _, name in ipairs(RenewableEnergyDebug.recipeNames()) do
        table.insert(data.recipes, recipeEntry(name))
    end
    data.strings = {
        expandedOption = getText("Sandbox_RenewableEnergy_enableExpandedRecipes"),
        modName = getText("Sandbox_RenewableEnergy"),
    }
    addWorld()
    addStatus()
    addIcons()
    runSteps(function()
        local status = RenewableEnergy.PowerBank.getStatus(homesteadBank:getX(), homesteadBank:getY(), homesteadBank:getZ())
        print(string.format("REPromo homestead bank: %.0f W in, %.0f W load, %.0f%% charged, inverter %s", status.inW,
            status.loadW, status.charge * 100, status.inverter.state))
        data.screen = { w = getCore():getScreenWidth(), h = getCore():getScreenHeight() }
        data.shots = shots
        writeJson("REPromo.json", data)
        onDone()
    end)
end
