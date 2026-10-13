-- Development only; dev/run-debug-client.sh --promo runs it instead of the tests. It builds two
-- working setups near the scenario start at a clear noon, a homestead (a metal battery bank
-- indoors against an outside wall, wall panels on that wall, racks, flat panels and a backup
-- generator in the yard) and a stage-0 wooden battery box indoors by a window with its panels
-- outside. Around them it lays a plain floor where every item is shot alone, hitches the arrow
-- board trailer to a car at road works, and at night lines a house's front walk with lit garden
-- lights. It saves the raw art that art/promo/compose.py lays out for the README and the
-- Workshop page: screenshots named promo_<shot>.png in <cachedir>/Screenshots, and
-- <cachedir>/Lua/REPromo.json, which names the regions of every screenshot and holds the item,
-- recipe and skill names in the game's language.
-- The shots come in groups (GROUP_NAMES), and PROMO=<group>,... shoots only those, building only
-- the setups they need, so art/promo/extract.py replaces only their captures.
-- Shots of anything but the world are taken twice, on black (promo_<shot>_k.png) and on white
-- (promo_<shot>_w.png), so that art/promo/extract.py can recover how transparent each pixel is.
-- The empty floor is shot too, so that extract.py can find each item by comparing its shot with
-- the floor's.
-- The run draws as many frames a second as it can, so its steps wait for what they need, such as
-- the lighting settling, and count frames only for drawing.

require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Debug/RenewableEnergyDebug"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/UI/StatusWindow"
require "RenewableEnergy/UI/Menu"
local Stage = require "RenewableEnergyDevStage"

local Promo = {}

local Sprites = RenewableEnergy.Sprites
local PowerBank = RenewableEnergy.PowerBank

-- The groups of shots, in the order a run takes them: the status window first, so that it reads
-- the same noon figures whatever else the run shoots, and the garden lights last, since they are
-- at night. run-debug-client.sh reads this line to refuse an unknown PROMO name before the game
-- starts.
local GROUP_NAMES = { "status", "menu", "world", "icons", "models", "trailer", "gardenlights" }
-- Frames for a change to reach the screen, where the screenshot reads it.
local DRAW_FRAMES = 10

-- The world shots are as wide as the README's images, in UI units.
local WORLD_W = 1260
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
-- The rack with a cracked module, connected early so that its row shows in the status window.
local CRACKED_RACK = 1
local CRACKED_CONDITION = 30
local MODULE = RenewableEnergy.Specs.factoryModule
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
local CELL_BATTERIES = 4
-- Every setup stands at least this far from the others along x or y, out of each other's shots.
local SITE_DISTANCE = 12

-- The menu shot: the homestead bank's right-click menu with the bank's submenu and its Wire In
-- submenu open, while the character carries these parts, and the tools, wire and scrap that
-- wiring them in takes, so that only what the bank has no room for is refused.
local MENU_ITEMS = { "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery", "Base.CarBattery1",
    "RenewableEnergy.ChargeController", "RenewableEnergy.PowerInverter", "Base.Screwdriver", "Base.Wrench",
    "Base.ElectricWire", "Base.ElectricWire", "Base.ElectricWire", "Base.ElectronicsScrap" }
local MENU_AT = 100

-- The item shots, on a patch of the road's own asphalt laid around the studio square that each
-- item lies on alone, at the closest zoom the game offers, which the zoom options leave out by
-- default. The character stands off to the side, (east, south) squares from the item, to its
-- left on the screen.
local STUDIO = {
    -- The open ground the patch needs, and how far around the studio square the asphalt goes
    -- where the ground is clear, and the plants go anyway, since the bigger items' shots reach
    -- past the patch.
    reach = 3,
    floorReach = 5,
    zoom = 25,
    player = { -1, 1 },
    -- What extract.py searches for the item, in UI units around its square's floor centre: room
    -- for the tallest models, and clear of the character.
    window = { half = 360, up = 700, down = 300 },
    -- Turned so that the long side of most models faces the camera.
    rotation = 315,
}

-- The trailer shot, on a road: positions are (ahead, side) squares from the car, `side` towards
-- the far side of the road from the camera. Road cones taper across the lane behind the
-- trailer, and the character stands at the trailer's battery box.
local ROAD = {
    -- The car faces north on a north-south road, else west on an east-west one, so that the
    -- arrow board on the trailer's back faces the camera.
    headings = { { facing = "N", ahead = { 0, -1 }, side = { -1, 0 } }, { facing = "W", ahead = { -1, 0 }, side = { 0, -1 } } },
    -- The open road the setup needs: room on the near side keeps hedges and fences there from
    -- hiding the car.
    ahead = { -11, 3 },
    side = { -3, 2 },
    trailer = { -5, 0 },
    cones = { { -8, 1 }, { -9, 0 }, { -10, -1 } },
    cone = "street_decoration_01_26",
    player = { -3, 1 },
    -- Other vehicles this close to the car go, so that only the car and trailer are in the shot.
    clearRadius = 14,
}

-- The garden lights shot, at night: lights on both sides of a house's front walk, the character
-- at the door. Positions are (along, out) from the square outside the door, as the homestead's.
local WALK = {
    -- The door stands on the square at out 0, so the open ground starts past it. It reaches a
    -- square past the lights, so that no fence stands between them and the camera.
    open = { along = { -1, 1 }, out = { 1, 4 } },
    lights = { { -1, 1 }, { 1, 1 }, { -1, 3 }, { 1, 3 } },
    player = { 0, 0 },
    scout = { 0, 4 },
    -- Late enough for the sky to be dark in any season.
    hour = 23,
}
-- How far around each setup radios and televisions are switched off, since their captions
-- float over the shots.
local QUIET_RADIUS = 25

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
-- The group whose steps are being added, which the shots name for extract.py.
local currentGroup

local function add(step)
    table.insert(steps, step)
end

local function region(name, x, y, w, h)
    return { name = name, x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h) }
end

local function elementRegion(name, element)
    return region(name, element:getAbsoluteX(), element:getAbsoluteY(), element:getWidth(), element:getHeight())
end

-- The game writes the file before the call returns (Core.TakeFullScreenshot), so no step waits
-- after a shot.
local function screenshot(file)
    Stage.screenshot("REPromo", file)
end

-- Every tinted element, the backdrop first, takes the backdrop colour. Returns a runSteps wait
-- until the backdrop has drawn DRAW_FRAMES times since: the UI redraws at its own rate
-- (Core.StartFrameUI, the uiRenderFPS option) and the frames in between show its last drawing, so
-- at an uncapped frame rate a count of frames can pass with no UI drawn at all.
local function setLevel(level)
    for _, element in ipairs(tinted) do
        element.backgroundColor = { r = level, g = level, b = level, a = 1 }
    end
    local backdrop = tinted[1]
    local start = backdrop.drawn
    return function()
        return backdrop.drawn - start >= DRAW_FRAMES
    end
end

-- Takes the shot on black and on white. regions() runs once the shot is laid out.
local function addMatted(name, regions)
    local group = currentGroup
    add(function()
        return setLevel(0)
    end)
    add(function()
        screenshot("promo_" .. name .. "_k")
        return setLevel(1)
    end)
    add(function()
        screenshot("promo_" .. name .. "_w")
        table.insert(shots, { name = name, group = group, matte = true, regions = regions() })
    end)
end

local function addOpaque(name, regions)
    local group = currentGroup
    add(function()
        return DRAW_FRAMES
    end)
    add(function()
        screenshot("promo_" .. name)
        table.insert(shots, { name = name, group = group, matte = false, regions = regions() })
    end)
end

local function newBackdrop()
    local backdrop = ISPanel:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    backdrop:initialise()
    -- Counts its drawings for setLevel.
    backdrop.drawn = 0
    local prerender = backdrop.prerender
    backdrop.prerender = function(self)
        self.drawn = self.drawn + 1
        prerender(self)
    end
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

-- The names of the items that research each recipe, by recipe: the ones whose script lists it
-- among its ResearchableRecipes, which the game extends with every recipe's own outputs
-- (OutputMapper). Built once, since it walks every item script.
local researchers

local function researchedBy(name)
    if not researchers then
        researchers = {}
        local scripts = getScriptManager():getAllItems()
        for i = 0, scripts:size() - 1 do
            local script = scripts:get(i)
            local recipes = script:hasResearchableRecipes() and script:getResearchableRecipes()
            for j = 0, (recipes and recipes:size() or 0) - 1 do
                local recipe = recipes:get(j)
                researchers[recipe] = researchers[recipe] or {}
                table.insert(researchers[recipe], getItemNameFromFullType(script:getFullName()))
            end
        end
        for _, names in pairs(researchers) do
            table.sort(names)
        end
    end
    return researchers[name] or {}
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
            research = researchedBy(name),
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
    for _, fullType in ipairs(RenewableEnergy.Debug.ITEMS) do
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

local function perform(name, args)
    local ok, reason = PowerBank.perform(getPlayer(), name, args)
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

local function isFreeIndoorsAt(site, origin, position)
    return RenewableEnergy.Debug.isFreeSquare(siteSquare(site, origin, position[1], position[2]), true)
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

-- The closest place to the character that takes the whole homestead, facing south if any does.
local function findSite(player)
    for _, site in ipairs(SITES) do
        local best = Stage.closestSquare(player, function(origin)
            return fits(site, origin, player)
        end)
        if best then
            return site, best
        end
    end
    return nil
end

-- Whether `square` stands at least SITE_DISTANCE from each of `others` along x or y.
local function isApart(square, others)
    for _, other in ipairs(others) do
        if math.abs(square:getX() - other:getX()) < SITE_DISTANCE and math.abs(square:getY() - other:getY()) < SITE_DISTANCE then
            return false
        end
    end
    return true
end

-- The closest place for stage 0 clear of the homestead: at a window if any, facing south first.
local function findStage0(player, homestead)
    for _, needWindow in ipairs({ true, false }) do
        for _, site in ipairs(SITES) do
            local best = Stage.closestSquare(player, function(origin)
                return isApart(origin, { homestead }) and fitsStage0(site, origin, player, needWindow)
            end)
            if best then
                return site, best, needWindow
            end
        end
    end
    return nil
end

local function studioSquare(studio, dx, dy)
    return getCell():getGridSquare(studio:getX() + dx, studio:getY() + dy, studio:getZ())
end

-- The closest square clear of `others` with open ground all over the studio's floor.
local function findStudio(player, others)
    return Stage.closestSquare(player, function(studio)
        if not isApart(studio, others) then
            return false
        end
        for dx = -STUDIO.reach, STUDIO.reach do
            for dy = -STUDIO.reach, STUDIO.reach do
                if not isOpen(studioSquare(studio, dx, dy), player) then
                    return false
                end
            end
        end
        return true
    end)
end

local function startsWith(text, prefix)
    return string.sub(text, 1, #prefix) == prefix
end

local function roadSquare(heading, car, position)
    local ahead, side = position[1], position[2]
    return getCell():getGridSquare(car:getX() + ahead * heading.ahead[1] + side * heading.side[1],
        car:getY() + ahead * heading.ahead[2] + side * heading.side[2], car:getZ())
end

-- The markings and blends painted over a road's floor.
local function isRoadPaint(object)
    local sprite = object:getSprite()
    local name = sprite and sprite:getName()
    return name ~= nil and (startsWith(name, "floors_overlay") or startsWith(name, "blends_"))
end

local function isOpenRoad(square, player)
    local floor = square and square:getFloor()
    local name = floor and floor:getSprite() and floor:getSprite():getName()
    return name ~= nil and startsWith(name, "blends_street") and isClear(square, isRoadPaint)
        and square ~= player:getCurrentSquare()
end

-- The closest square clear of `others` for the car, with open road all around the car, the
-- trailer and the cones, on a north-south road if any.
local function findRoad(player, others)
    for _, heading in ipairs(ROAD.headings) do
        local best = Stage.closestSquare(player, function(car)
            if not isApart(car, others) then
                return false
            end
            for ahead = ROAD.ahead[1], ROAD.ahead[2] do
                for side = ROAD.side[1], ROAD.side[2] do
                    if not isOpenRoad(roadSquare(heading, car, { ahead, side }), player) then
                        return false
                    end
                end
            end
            return true
        end)
        if best then
            return heading, best
        end
    end
    return nil
end

-- Outdoors, at a door into a room.
local function hasDoor(site, origin)
    local square, inside = siteSquare(site, origin, 0, 0), siteSquare(site, origin, 0, -1)
    return square ~= nil and inside ~= nil and inside:getRoom() ~= nil and square:isOutside()
        and instanceof(square:getDoorOrWindow(site.wallNorth), "IsoDoor")
end

-- The closest door clear of `others` with open ground in front of it for the walk, facing south
-- first.
local function findWalk(player, others)
    for _, site in ipairs(SITES) do
        local best = Stage.closestSquare(player, function(origin)
            return isApart(origin, others) and hasDoor(site, origin) and isOpenArea(site, origin, player, WALK.open)
        end)
        if best then
            return site, best
        end
    end
    return nil
end

-- A placed tile, as the tests place one. A panel mount holds `modules` (a PowerBank.MODULES list),
-- or without them whole factory modules.
local function placeTile(square, spriteName, modules)
    local object = IsoObject.new(square, spriteName, spriteName)
    if modules then
        object:getModData()[PowerBank.MODULES] = modules
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
    perform("refresh", { bank = PowerBank.positionOf(bank) })
end

local function connect(bank, panel)
    perform("connectSource", { bank = PowerBank.positionOf(bank), source = PowerBank.positionOf(panel) })
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

-- Whether `square` is in reach of a bank on `bankSquare`, as RenewableEnergy.Loads measures it.
local function isInReach(bankSquare, square)
    local radius = SandboxVars.GeneratorTileRange
    return math.abs(square:getZ() - bankSquare:getZ()) <= SandboxVars.GeneratorVerticalPowerRange
        and IsoUtils.DistanceToSquared(square:getX(), square:getY(), bankSquare:getX(), bankSquare:getY()) <= radius * radius
end

local function forSquaresInReach(bankSquare, fn)
    local radius, levels = SandboxVars.GeneratorTileRange, SandboxVars.GeneratorVerticalPowerRange
    for z = bankSquare:getZ() - levels, bankSquare:getZ() + levels do
        for x = bankSquare:getX() - radius, bankSquare:getX() + radius do
            for y = bankSquare:getY() - radius, bankSquare:getY() + radius do
                local square = getCell():getGridSquare(x, y, z)
                if square and isInReach(bankSquare, square) then
                    fn(square)
                end
            end
        end
    end
end

-- Switches off every light in reach of the banks, which houses keep on once the grid goes, and
-- takes away the fridges and freezers in reach of the stage-0 box: nothing switches those off,
-- and one alone would overload its Plug-in Inverter.
local function quietNeighbourhood(homesteadSquare, stage0Square)
    local lights, fridges = 0, 0
    for _, bankSquare in ipairs({ homesteadSquare, stage0Square }) do
        forSquaresInReach(bankSquare, function(square)
            local objects = square:getObjects()
            for i = objects:size() - 1, 0, -1 do
                local object = objects:get(i)
                if instanceof(object, "IsoLightSwitch") and object:isActivated() then
                    object:setActive(false, false, true)
                    lights = lights + 1
                elseif bankSquare == stage0Square and object:getPipedFuelAmount() <= 0
                    and object:getContainerByEitherType("fridge", "freezer") then
                    square:RemoveTileObject(object)
                    fridges = fridges + 1
                end
            end
        end)
    end
    print(string.format("REPromo switched off %d lights and took away %d fridges", lights, fridges))
end

-- Switches off the radios and televisions around each of `places`, which play with their
-- captions floating over them.
local function silenceRadios(places)
    local silenced = 0
    for _, place in ipairs(places) do
        for x = place:getX() - QUIET_RADIUS, place:getX() + QUIET_RADIUS do
            for y = place:getY() - QUIET_RADIUS, place:getY() + QUIET_RADIUS do
                local square = getCell():getGridSquare(x, y, place:getZ())
                local objects = square and square:getObjects()
                for i = 0, (objects and objects:size() or 0) - 1 do
                    local object = objects:get(i)
                    if instanceof(object, "IsoWaveSignal") and object:getDeviceData():getIsTurnedOn() then
                        object:getDeviceData():setIsTurnedOn(false)
                        silenced = silenced + 1
                    end
                end
            end
        end
    end
    print("REPromo switched off " .. silenced .. " radios and televisions")
end

-- Switches on lights in the building around `square`, nearest first, out of reach of the bank
-- on `otherBank`. They draw on the bank, which is the only power with the grid off.
local function switchOnLights(square, otherBank)
    local building = square:getBuilding()
    local switched = 0
    for radius = 0, LIGHT_SEARCH do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local near = math.max(math.abs(dx), math.abs(dy)) == radius
                    and getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                local objects = near and building and near:getBuilding() == building and not isInReach(otherBank, near)
                    and near:getObjects()
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
local studio, roadHeading, roadCar, walkSite, walkOrigin
local homesteadBank, stage0Box

local function at(position)
    return siteSquare(site, origin, position[1], position[2])
end

local function atStage0(position)
    return siteSquare(stage0Site, stage0Origin, position[1], position[2])
end

local function atRoad(position)
    return roadSquare(roadHeading, roadCar, position)
end

local function atWalk(position)
    return siteSquare(walkSite, walkOrigin, position[1], position[2])
end

local function buildHomestead()
    quietNeighbourhood(at(HOMESTEAD.bank), atStage0(STAGE0.box))
    for along = OPEN.along[1], OPEN.along[2] do
        for out = 0, OPEN.out[2] do
            clearGroundCover(at({ along, out }))
        end
    end
    homesteadBank = PowerBank.place(at(HOMESTEAD.bank), Sprites.batteryBankMetal, -1)
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
    perform("setBankOn", { bank = PowerBank.positionOf(homesteadBank), on = true })
    switchOnLights(homesteadBank:getSquare(), atStage0(STAGE0.box))
end

local function buildStage0()
    for along = STAGE0.open.along[1], STAGE0.open.along[2] do
        for out = STAGE0.open.out[1], STAGE0.open.out[2] do
            clearGroundCover(atStage0({ along, out }))
        end
    end
    stage0Box = PowerBank.place(atStage0(STAGE0.box), Sprites.batteryBoxWood, -1)
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
    perform("setBankOn", { bank = PowerBank.positionOf(stage0Box), on = true })
end

-- Bank passes hour by hour from the morning to noon, as the game's own passes would have run,
-- then one of a minute: the window shows the sun averaged over the last pass, which would
-- otherwise be the last hour of the morning.
local function chargeThroughMorning()
    local BankSystem = require "RenewableEnergy/PowerBank/BankSystem"
    local system = PowerBank.serverSystem
    local banks = { system:getLuaObjectOnSquare(homesteadBank:getSquare()), system:getLuaObjectOnSquare(stage0Box:getSquare()) }
    local hours = {}
    -- The first pass only starts the clock of a bank that has never run one.
    for hour = MORNING, NOON do
        table.insert(hours, hour)
    end
    table.insert(hours, NOON + 1 / 60)
    for _, hour in ipairs(hours) do
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

-- The squares the character has looked around from so far in the run. What it saw stays seen.
local lookedFrom = {}

-- Has the character look around from each of `squares` and stay on the last, since squares they
-- never saw are drawn dark, and sets the zoom `stepsOut` steps out from the closest. Of the others,
-- it skips those it has looked around from already.
local function goTo(squares, stepsOut)
    for i, square in ipairs(squares) do
        if i == #squares or not lookedFrom[square] then
            Stage.addLookAround(steps, getPlayer(), square)
            lookedFrom[square] = true
        end
    end
    add(function()
        Stage.zoomOut(stepsOut)
        return Stage.zoomSettled()
    end)
end

-- What every group's shots share: a clear noon without grid power, and no radio captions.
local function addWorldSettings()
    add(function()
        -- The grid would power the squares and leave the bank nothing to run.
        local option = getSandboxOptions():getOptionByName("ElecShutModifier")
        if option then
            option:setValue(-1)
        end
        getWorld():setHydroPowerOn(false)
        clearWeather()
        getGameTime():setTimeOfDay(NOON)
        silenceRadios({ origin, stage0Origin, roadCar, studio, walkOrigin })
    end)
end

-- Logs each bank's status as the window reads it.
local function logBanks()
    for name, bank in pairs({ homestead = homesteadBank, ["stage 0"] = stage0Box }) do
        local status = PowerBank.statusOf(bank)
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
end

-- Both setups, charged through the morning; the world, status and menu shots need them.
local function addSetups()
    add(function()
        getGameTime():setTimeOfDay(MORNING)
        Stage.removeTrees(origin:getX(), origin:getY(), origin:getZ())
        Stage.removeTrees(stage0Origin:getX(), stage0Origin:getY(), stage0Origin:getZ())
        buildHomestead()
        buildStage0()
        chargeThroughMorning()
        logBanks()
        return DRAW_FRAMES
    end)
end

local function addWorld()
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
        return Stage.zoomSettled()
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
        window = RenewableEnergy.StatusWindow.open(0, PowerBank.bankOn(at(HOMESTEAD.bank)))
        window:setX(100)
        window:setY(100)
        -- The window lays its rows out from the bank's status as it draws.
        return function()
            return (window.renderedFrames or 0) >= 2
        end
    end)
    addMatted("status", function()
        return { elementRegion("status", window) }
    end)
    add(function()
        window:close()
    end)
    removeBackdrop()
end

-- The submenu of `menu`'s option named `name`, opened as if the mouse were over the option.
local function openSubMenu(menu, name)
    for i, option in ipairs(menu and menu.options or {}) do
        if option.name == name and option.subOption then
            menu.mouseOver = i
            return menu:getSubMenu(option.subOption)
        end
    end
    print("REPromo menu has no " .. name)
end

-- The homestead bank's right-click menu on a backdrop, with the bank's submenu and its Wire In
-- submenu open and the first part the bank takes highlighted.
local function addMenu()
    local menus, carried = {}, {}
    add(function()
        newBackdrop()
        -- In debug mode vanilla adds its debug options to every world menu unless told not to.
        getDebugOptions():setBoolean("UI.HideDebugContextMenuOptions", true)
        local inventory = getPlayer():getInventory()
        for _, fullType in ipairs(MENU_ITEMS) do
            table.insert(carried, inventory:AddItem(fullType))
        end
        local context = ISWorldObjectContextMenu.createMenu(0, { homesteadBank }, MENU_AT, MENU_AT)
        local bankMenu = openSubMenu(context, RenewableEnergy.Menu.bankLabel(homesteadBank))
        local wireIn = openSubMenu(bankMenu, getText("ContextMenu_RenewableEnergy_WireIn"))
        menus = { context, bankMenu, wireIn }
        wireIn.mouseOver = -1
        for i, option in ipairs(wireIn.options) do
            if not option.notAvailable then
                wireIn.mouseOver = i
                break
            end
        end
        -- The world menu was made when the game started, under the backdrop.
        context:bringToTop()
        return 30
    end)
    addMatted("menu", function()
        local left, top, right, bottom = math.huge, math.huge, 0, 0
        for _, menu in ipairs(menus) do
            left, top = math.min(left, menu:getAbsoluteX()), math.min(top, menu:getAbsoluteY())
            right = math.max(right, menu:getAbsoluteX() + menu:getWidth())
            bottom = math.max(bottom, menu:getAbsoluteY() + menu:getHeight())
        end
        return { region("menu", left, top, right - left, bottom - top) }
    end)
    add(function()
        menus[1]:hideAndChildren()
        for _, item in ipairs(carried) do
            getPlayer():getInventory():Remove(item)
        end
        return 1
    end)
    removeBackdrop()
end

-- Where extract.py looks for the item in a studio shot: STUDIO.window around the studio
-- square's floor centre, kept on the screen.
local function studioWindow(name)
    local x, y = onScreen(studio)
    local window = STUDIO.window
    local left, top = math.max(0, x - window.half), math.max(0, y - window.up)
    local right = math.min(getCore():getScreenWidth(), x + window.half)
    local bottom = math.min(getCore():getScreenHeight(), y + window.down)
    return region(name, left, top, right - left, bottom - top)
end

-- Every item alone on the studio floor. `models` gets one entry per item.
local function addModels(items, models)
    local group = currentGroup
    local zoomLevels
    add(function()
        local asphalt = roadCar:getFloor():getSprite():getName()
        print("REPromo item floor " .. asphalt)
        for dx = -STUDIO.floorReach, STUDIO.floorReach do
            for dy = -STUDIO.floorReach, STUDIO.floorReach do
                local square = studioSquare(studio, dx, dy)
                clearGroundCover(square)
                if isClear(square) then
                    square:addFloor(asphalt)
                end
            end
        end
        zoomLevels = { getCore():getOptionZoomLevels1x(), getCore():getOptionZoomLevels2x() }
        getCore():setOptionZoomLevels1x(zoomLevels[1] .. ";" .. STUDIO.zoom)
        getCore():setOptionZoomLevels2x(zoomLevels[2] .. ";" .. STUDIO.zoom)
        getCore():zoomLevelsChanged()
        -- Every item at once, so that their models load while the character looks around: Lua
        -- can't tell when a model has loaded, and a loaded one draws on the next frame.
        for _, item in ipairs(items) do
            studio:AddWorldInventoryItem(instanceItem(item.fullType), 0.5, 0.5, 0)
        end
        return 30
    end)
    goTo({ studioSquare(studio, STUDIO.player[1], STUDIO.player[2]) }, 0)
    local floor = "promo_models_floor"
    add(function()
        studio:removeAllWorldObjects()
        return DRAW_FRAMES
    end)
    add(function()
        screenshot(floor)
    end)
    for _, item in ipairs(items) do
        local name = "model_" .. string.gsub(item.fullType, "%.", "_")
        add(function()
            local placed = instanceItem(item.fullType)
            placed:setWorldZRotation(STUDIO.rotation)
            studio:AddWorldInventoryItem(placed, 0.5, 0.5, 0)
            return DRAW_FRAMES
        end)
        add(function()
            local file = "promo_" .. name
            screenshot(file)
            table.insert(models, { name = name, group = group, file = file, floor = floor, window = studioWindow(name) })
            studio:removeAllWorldObjects()
        end)
    end
    add(function()
        getCore():setOptionZoomLevels1x(zoomLevels[1])
        getCore():setOptionZoomLevels2x(zoomLevels[2])
        getCore():zoomLevelsChanged()
        return 30
    end)
end

-- What the trailer shot shows: the car's nose, the trailer, the character and the cones.
local function roadSquares()
    local squares = { atRoad({ 2, 0 }), atRoad(ROAD.trailer), atRoad(ROAD.player) }
    for _, spot in ipairs(ROAD.cones) do
        table.insert(squares, atRoad(spot))
    end
    return squares
end

-- Physics runs in real time, so the trailer steps wait for the vehicles to stand still: spawned,
-- they settle onto their wheels, and a trailer hitched before then swings round as the hitch pulls
-- it up to the car's tow bar. Vehicles at rest report a creep of about a tenth of a metre a second
-- until their physics sleeps, seconds later.
local STILL_MS = 250
local STILL_SPEED = 0.2
local HITCH_GAP = 0.1

-- A runSteps wait until both of Stage.spawnTrailer's `pair` stand still on their squares, and with
-- `hitch`, with the trailer's tow point at the car's.
local function atRest(pair, hitch)
    local velocity, towing, towed = Vector3f.new(), Vector3f.new(), Vector3f.new()
    local since
    return function()
        local still = true
        for _, vehicle in ipairs({ pair.car, pair.trailer }) do
            local square = vehicle:getSquare()
            still = still and square ~= nil and square:getVehicleContainer() == vehicle
                and vehicle:getLinearVelocity(velocity):length() < STILL_SPEED
        end
        if still and hitch then
            local a = pair.car:getTowingWorldPos("trailer", towing)
            local b = pair.trailer:getTowedByWorldPos("trailer", towed)
            still = a ~= nil and b ~= nil and pair.trailer:getVehicleTowedBy() == pair.car
                and IsoUtils.DistanceToSquared(a:x(), a:y(), b:x(), b:y()) < HITCH_GAP * HITCH_GAP
        end
        if not still then
            since = nil
            return false
        end
        since = since or getTimestampMs()
        return getTimestampMs() - since >= STILL_MS
    end
end

-- The arrow board trailer hitched to a car on the road, cones behind it, a step out from the
-- closest zoom.
local function addTrailer()
    local pair
    add(function()
        Stage.removeTrees(roadCar:getX(), roadCar:getY(), roadCar:getZ())
        -- Found through the squares they stand on, since Lua can't walk the cell's set of them.
        local parked, seen = {}, {}
        for dx = -ROAD.clearRadius, ROAD.clearRadius do
            for dy = -ROAD.clearRadius, ROAD.clearRadius do
                local square = getCell():getGridSquare(roadCar:getX() + dx, roadCar:getY() + dy, roadCar:getZ())
                local vehicle = square and square:getVehicleContainer()
                if vehicle and not seen[vehicle] then
                    seen[vehicle] = true
                    table.insert(parked, vehicle)
                end
            end
        end
        for _, vehicle in ipairs(parked) do
            vehicle:permanentlyRemove()
        end
        for _, spot in ipairs(ROAD.cones) do
            placeTile(atRoad(spot), ROAD.cone)
        end
        pair = Stage.spawnTrailer(roadCar, roadHeading.facing)
        return atRest(pair, false)
    end)
    add(function()
        Stage.hitchTrailer(pair, getPlayer(), "REPromo")
        return atRest(pair, true)
    end)
    -- From the item floor first, as a full run's character has by now: the hedges and fences along
    -- a road hide what lies past them from the road itself.
    goTo({ studioSquare(studio, STUDIO.player[1], STUDIO.player[2]), atRoad(ROAD.player) }, 1)
    addOpaque("trailer", function()
        return { centred("trailer", roadSquares()) }
    end)
end

local function walkSquares()
    local squares = { atWalk({ 0, -1 }), atWalk(WALK.player) }
    for _, spot in ipairs(WALK.lights) do
        table.insert(squares, atWalk(spot))
    end
    return squares
end

-- Garden lights along a house's front walk, charged and lit at night, at the closest zoom.
local function addGardenLights()
    local SolarGardenLight = RenewableEnergy.SolarGardenLight
    add(function()
        Stage.removeTrees(walkOrigin:getX(), walkOrigin:getY(), walkOrigin:getZ())
        for along = WALK.open.along[1], WALK.open.along[2] do
            for out = WALK.open.out[1], WALK.open.out[2] do
                clearGroundCover(atWalk({ along, out }))
            end
        end
        for _, spot in ipairs(WALK.lights) do
            RenewableEnergy.WorldSpawns.placeMoveable(atWalk(spot), Sprites.gardenLight.off,
                { [SolarGardenLight.CHARGE_KEY] = RenewableEnergy.Specs.gardenLight.wh })
        end
        getGameTime():setTimeOfDay(WALK.hour)
        -- The lighting takes most of a second to follow the clock.
        return Stage.lightingSettled(getPlayer(), true)
    end)
    add(function()
        -- Lit now, rather than at the next minute's pass. Their light shows while the character
        -- looks around.
        for _, spot in ipairs(WALK.lights) do
            local light = SolarGardenLight.findOn(atWalk(spot))
            if light then
                SolarGardenLight.update(light, 0)
            end
        end
    end)
    goTo({ atWalk(WALK.scout), atWalk(WALK.player) }, 0)
    addOpaque("gardenlights", function()
        return { centred("gardenlights", walkSquares()) }
    end)
end

-- Finds every setup's place, each clear of the ones before it, or names the first it can't find.
local function findPlaces(player)
    local atWindow
    site, origin = findSite(player)
    if not site then
        return "plain building wall with free floor indoors behind it and open ground in front"
    end
    stage0Site, stage0Origin, atWindow = findStage0(player, origin)
    if not stage0Site then
        return "outside wall with free floor indoors behind it and open ground in front, for stage 0"
    end
    roadHeading, roadCar = findRoad(player, { origin, stage0Origin })
    if not roadHeading then
        return "stretch of open road for the trailer"
    end
    studio = findStudio(player, { origin, stage0Origin, roadCar })
    if not studio then
        return "open ground for the item shots' floor"
    end
    walkSite, walkOrigin = findWalk(player, { origin, stage0Origin, roadCar, studio })
    if not walkSite then
        return "door with open ground in front, for the garden lights"
    end
    print(string.format("REPromo homestead %d,%d facing %s; stage 0 %d,%d facing %s, %s; trailer %d,%d facing %s;"
        .. " items %d,%d; garden lights %d,%d facing %s", origin:getX(), origin:getY(), site.facing,
        stage0Origin:getX(), stage0Origin:getY(), stage0Site.facing, atWindow and "at a window" or "at a wall",
        roadCar:getX(), roadCar:getY(), roadHeading.facing, studio:getX(), studio:getY(), walkOrigin:getX(),
        walkOrigin:getY(), walkSite.facing))
end

-- The groups of GROUP_NAMES: whether they need both setups built, and what adds their steps.
local GROUPS = {
    world = { setups = true, add = addWorld },
    status = { setups = true, add = addStatus },
    menu = { setups = true, add = addMenu },
    icons = { add = addIcons },
    models = { add = function(data) addModels(data.items, data.models) end },
    trailer = { add = addTrailer },
    gardenlights = { add = addGardenLights },
}

-- Adds a step that starts a clock, and returns a function that adds a step logging, under
-- "REPromo TIME", how long the steps added in between took.
local function addTimer(label)
    local started
    add(function()
        started = getTimestampMs()
    end)
    return function()
        add(function()
            print(string.format("REPromo TIME %s %.1f s", label, (getTimestampMs() - started) / 1000))
        end)
    end
end

--- Shoots the groups named in `selection`, comma-separated, or every group if it is empty, and
--- calls onDone.
function Promo.capture(selection, onDone)
    selection = selection or ""
    print("REPromo START " .. (selection ~= "" and selection or "all"))
    local selected, any = {}, false
    for name in string.gmatch(selection, "[^,%s]+") do
        if not GROUPS[name] then
            print("REPromo FAIL: no group " .. name .. "; the groups are " .. table.concat(GROUP_NAMES, ","))
            getCore():quitToDesktop()
            return
        end
        selected[name], any = true, true
    end
    local player = getPlayer()
    local missing = findPlaces(player)
    if missing then
        -- Without "REPromo DONE", run-debug-client.sh reports the run as failed.
        print("REPromo FAIL: within " .. Stage.SEARCH_RADIUS .. " squares, no " .. missing)
        getCore():quitToDesktop()
        return
    end
    -- Hides the HUD, the debug console and every other window; the shots add their own.
    ISUIHandler.setVisibleAllUI(false)
    -- In a corner, where it hovers over nothing the shots show: the world outlines what it is
    -- over, and menus follow it.
    setMouseXY(0, 0)
    -- The names come with every run, since they cost no shot.
    local data = { items = itemsList(), recipes = {}, models = {}, groups = {} }
    for _, name in ipairs(PZHarness.Test.recipeNames()) do
        table.insert(data.recipes, recipeEntry(name))
    end
    data.strings = {
        modName = getText("Sandbox_RenewableEnergy"),
    }
    local endTotal = addTimer("total")
    addWorldSettings()
    local setupsBuilt = false
    for _, name in ipairs(GROUP_NAMES) do
        local group = GROUPS[name]
        if selected[name] or not any then
            table.insert(data.groups, name)
            currentGroup = name
            local endGroup = addTimer(name)
            if group.setups and not setupsBuilt then
                addSetups()
                setupsBuilt = true
            end
            group.add(data)
            endGroup()
        end
    end
    endTotal()
    Stage.runSteps(steps, function()
        data.screen = { w = getCore():getScreenWidth(), h = getCore():getScreenHeight() }
        data.shots = shots
        writeJson("REPromo.json", data)
        onDone()
    end, "REPromo")
end

return Promo
