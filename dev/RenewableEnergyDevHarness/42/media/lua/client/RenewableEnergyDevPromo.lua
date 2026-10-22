-- Development only; dev/run-debug-client.sh --promo runs it instead of the tests. It builds the
-- setups near the scenario start and saves the raw art that art/promo/compose.py lays out:
-- promo_<shot>.png screenshots, and REPromo.json naming each screenshot's regions and the item,
-- recipe and skill names in the game's language.
-- PROMO=<group>,... shoots only those groups, building only the setups they need. Shots of
-- anything but the world are taken on black and on white (PZHarness/Capture.lua), and the empty
-- floor too, so that art/promo/extract.py can find each item by difference.
-- The run draws frames as fast as it can, so steps wait on conditions, not frame counts.

require "PZHarness/TestLib"
local Capture = require "PZHarness/Capture"
require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Debug/RenewableEnergyDebug"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/UI/StatusWindow"
require "RenewableEnergy/UI/Menu"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/UI/DigesterWindow"
require "RenewableEnergy/UI/GasifierWindow"
require "RenewableEnergy/TimedActions/RenewableEnergyTreadmillAction"
local Stage = require "RenewableEnergyDevStage"

local Promo = {}

local Sprites = RenewableEnergy.Sprites
local PowerBank = RenewableEnergy.PowerBank

local DRAW_FRAMES = Capture.DRAW_FRAMES

-- The world shots are as wide as the README's images, in UI units.
local WORLD_W = 1260
-- The banks charge through the morning, so the window shows a day's figures at noon.
local MORNING, NOON = 8, 12
-- Inputs that take any item with a tag show this one.
local PREFER = { "Base.Hammer", "Base.Screwdriver", "Base.Pliers", "Base.Wrench", "Base.HandDrill", "Base.WeldingMask",
    "Base.Saw", "Base.Matches", "Base.Charcoal", "Base.KitchenKnife", "Base.SmithingHammer", "Base.Tongs",
    "Base.NormalBrake1", "Base.Bucket", "Base.Garbagebag", "Base.Shovel2", "Base.MasonsTrowel", "Base.BucketConcreteFull" }
-- A recipe line that takes or fills any fluid container shows this one, by the fluid's type.
local FLUID_CONTAINERS = { Acid = "RenewableEnergy.BatteryElectrolyte", Water = "Base.WaterBottle",
    RenewableEnergy_WoodVinegar = "Base.BottleCrafted" }
-- The literature that teaches the mod's recipes, the build menu's among them.
local MAGAZINES = { "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2",
    "RenewableEnergy.HomesteadPowerMag3", "RenewableEnergy.FemaPamphlet", "RenewableEnergy.HomesteadPowerMag4" }
-- Banks take vanilla car batteries as they are, so the item sheet shows one.
local VANILLA_ITEMS = { "Base.CarBattery1" }

-- Every setup is a place (newPlace): a square its positions are measured from, and a frame, the
-- directions a position's two numbers run in, `along` and `out`. An area of a place is the
-- squares from along[1] to along[2] and out[1] to out[2]; with `sum` and `half`, only those whose
-- along + out is within `half` of `sum`, a band across the screen.
-- The frame of places measured in (east, south) squares.
local GRID = { along = { 1, 0 }, out = { 0, 1 } }
-- Both setups stand at an outside wall that the camera sees: the north edge of a square south of
-- a building (preferred: wall panels face south), or the west edge of one east of it. Positions
-- are (along, out) from the square outside the wall: `along` runs along the wall, `out` away
-- from it, so out -1 is indoors; panels face `out`.
local SITES = {
    { wallNorth = true, along = { 1, 0 }, out = { 0, 1 }, facing = "S" },
    { wallNorth = false, along = { 0, 1 }, out = { 1, 0 }, facing = "E" },
}
-- The homestead. Banks stand indoors, so the bank is in the room behind the wall the wall panels
-- hang on (`inside` is the square behind it), out of the yard shots, against the room's north wall
-- with the character off to its side for a shot of its own (bankPlace). Outdoors, the character
-- stands beside the last wall panel, where nothing is behind them, and the backup generator is
-- within a failsafe's reach of the bank. An insulated digester beside the generator feeds it gas
-- through its kit, and a propeller wind charger stands at the far end of the wall, where its
-- mast rises in front of the house rather than over the panels.
local HOMESTEAD = {
    inside = { 0, -1 },
    generator = { -1, 1 },
    digester = { -2, 1 },
    windCharger = { 5, 1 },
    wallPanels = { { 0, 0, "wood" }, { 1, 0, "wood" }, { 2, 0, "metal" } },
    player = { 3, 1 },
    racks = { { -1, 3, "wood" }, { 0, 3, "wood" }, { 1, 3, "metal" }, { 2, 3, "metal" } },
    flatPanels = { { 0, 5 }, { 1, 5 }, { 2, 5 }, { 3, 5 } },
    -- Where the character looks around first, out in the yard the shots also show.
    scouts = { { -4, 3 }, { -3, 8 }, { 2, 9 } },
}
-- The ground that must be clear (grass and weeds are cleared), and the plain wall the wall panels
-- hang on.
local OPEN = { along = { -2, 5 }, out = { 1, 5 } }
local AT_WALL = { 0, 2 }
-- The rack with a cracked module, connected early so that its row shows in the status window: the
-- modules of HOMESTEAD.racks by index.
local MODULE = RenewableEnergy.Specs.factoryModule
local HOMESTEAD_MODULES = { [1] = { { type = MODULE, condition = 30 }, { type = MODULE, condition = 100 } } }
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
-- What the character wears at the homestead, a settler long into the apocalypse: road leathers,
-- armour pieced together from scrap metal and tyres, goggles, a scarf against the dust, and a
-- sawn-off in hand. Elsewhere it wears the clothes it came with.
local SETTLER = {
    clothes = {
        "Base.Tshirt_DefaultTEXTURE", "Base.Jacket_LeatherBlack", "Base.Trousers_LeatherBlack",
        "Base.Shoes_BlackBoots", "Base.Gloves_FingerlessLeatherGloves_Black", "Base.ShemaghScarf",
        "Base.Glasses_SkiGoggles", "Base.Shoulderpad_MetalSpikeScrap_L", "Base.Shoulderpad_Tire_R",
        "Base.VambraceScrap_Left", "Base.VambraceScrap_Right", "Base.GreaveScrap_Left", "Base.GreaveScrap_Right",
        "Base.Bag_ALICE_BeltSus",
    },
    weapon = "Base.ShotgunSawnoff",
}

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
    open = { along = { -3, 3 }, out = { -3, 3 } },
    floor = { along = { -5, 5 }, out = { -5, 5 } },
    zoom = 25,
    player = { -1, 1 },
    -- What extract.py searches for the item, in UI units around its square's floor centre: room
    -- for the tallest models, and clear of the character.
    window = { half = 360, up = 700, down = 300 },
    -- Turned so that the long side of most models faces the camera.
    rotation = 315,
}

-- The trailer shot, on a road: positions are (ahead, side) squares from the car, `side` towards
-- the far side of the road from the camera, so a heading's frame runs `along` ahead and `out` to
-- the side. Road cones taper across the lane behind the trailer, and the character stands on the
-- far side of the trailer's battery box, where the arrow board hides none of them.
local ROAD = {
    -- The car faces north on a north-south road, else west on an east-west one, so that the
    -- arrow board on the trailer's back faces the camera.
    headings = { { facing = "N", along = { 0, -1 }, out = { -1, 0 } }, { facing = "W", along = { -1, 0 }, out = { 0, -1 } } },
    -- The open road the setup needs: room on the near side keeps hedges and fences there from
    -- hiding the car.
    open = { along = { -11, 3 }, out = { -3, 3 } },
    trailer = { -5, 0 },
    cones = { { -8, 1 }, { -9, 0 }, { -10, -1 } },
    cone = "street_decoration_01_26",
    player = { -3, 3 },
    -- Other vehicles this close to the car go, so that only the car and trailer are in the shot.
    clearRadius = 14,
}

-- The garden lights shot, at night: lights on both sides of a house's front walk, the character
-- at the door. Positions are (along, out) from the square outside the door, as the homestead's.
local WALK = {
    -- The door stands on the square at out 0, so the open ground starts past it. It reaches a
    -- square past the lights, so that no fence stands between them and the camera.
    open = { along = { -1, 1 }, out = { 1, 4 } },
    -- Each with its own bulb, to show the colours a light takes.
    lights = {
        { -1, 1, bulb = "Base.LightBulb" }, { 1, 1, bulb = "Base.LightBulbBlue" },
        { -1, 3, bulb = "Base.LightBulbRed" }, { 1, 3, bulb = "Base.LightBulbGreen" },
    },
    -- On the walk between the far pair of lights, clear of the door: a square nearer it would
    -- stand straight in front of a near light.
    player = { 0, 3 },
    scout = { 0, 4 },
    -- Late enough for the sky to be dark in any season.
    hour = 23,
}
-- The poster and the Workshop preview, after dark: a house with every light on, run by a bank
-- indoors behind a window and fed by racks, flat panels and a propeller wind charger in its yard,
-- with a kitted generator on a digester's gas beside them, while the neighbours' houses, with the
-- grid gone, stand dark. Positions are (along, out) from the square outside the window, as the
-- homestead's.
local POSTER = {
    -- Lit windows sell it, so the wall the camera sees needs several, and the house some rooms.
    windows = { along = { -4, 4 }, count = 2 },
    rooms = 3,
    bank = { 0, -1 },
    open = { along = { -2, 3 }, out = { 1, 3 } },
    racks = { { -1, 2, "metal" }, { 0, 2, "metal" }, { 1, 2, "metal" }, { 2, 2, "metal" } },
    flatPanels = { { -1, 3 }, { 0, 3 }, { 1, 3 } },
    generator = { -2, 1 },
    digester = { -2, 2 },
    windCharger = { 3, 1 },
    player = { 2, 3 },
    -- Where the character looks around first, by day, so that the house, its rooms behind the
    -- windows and its neighbours are drawn rather than left black as unseen: indoors where the
    -- floor is free, then outdoors.
    indoors = { { -3, -2 }, { 0, -2 }, { 3, -2 } },
    scouts = { { -4, 4 }, { 0, 8 }, { 6, 4 }, { 6, 0 } },
    -- Past 24 the clock rolls over into the next morning: darker than the garden lights' hour, so
    -- the lit house stands out of the street.
    hour = 25,
    -- Out far enough for the whole house and the dark around it.
    zoomOut = 3,
}

-- The Release 2 setups (`yards`: biogas, wood gas, wind), each on open ground of its own, and the
-- treadmill indoors (`gym`): positions are (east, south) squares from the place found, and `shot`
-- names the positions the shot frames. A yard lays its things out along a line across the screen,
-- nearest the camera in front, so `open` is the band of squares that must be clear (trees may
-- stand there; they go).
local R2 = {
    yards = { "biogas", "woodgas", "wind" },
    -- Every digester, working and full of gas, the brick dome feeding a kitted generator through
    -- its hose, and a lit gas heater warming the steel barrel.
    biogas = {
        open = { along = { -2, 6 }, out = { -1, 6 }, sum = 4, half = 3 },
        barrelSteel = { 0, 4 },
        heater = { -1, 4 },
        barrelOrange = { 1, 3 },
        insulated = { 2, 2 },
        dome = { 3, 1 },
        generator = { 4, 1 },
        player = { 5, 0 },
        scout = { 2, 4 },
        shot = { "barrelSteel", "heater", "barrelOrange", "insulated", "dome", "generator", "player" },
    },
    -- The gasifier and the advanced gasifier lit, each piped to a kitted generator to its east, and
    -- the primitive gasifier with wood and charcoal beside it.
    woodgas = {
        open = { along = { -1, 6 }, out = { -1, 6 }, sum = 5, half = 3 },
        primitive = { 0, 4 },
        fuel = { 1, 4 },
        standard = { 1, 3 },
        standardGenerator = { 2, 3 },
        advanced = { 3, 1 },
        advancedGenerator = { 4, 1 },
        player = { 4, 3 },
        scout = { 2, 5 },
        shot = { "primitive", "fuel", "standard", "standardGenerator", "advanced", "advancedGenerator", "player" },
        -- On the ground beside the primitive gasifier, what it burns, as a player brings it: where
        -- each lies on its square, as fractions of it, and which way it is turned.
        fuelItems = {
            { "Base.Log", 0.3, 0.3, 20 }, { "Base.Log", 0.62, 0.36, 110 }, { "Base.Firewood", 0.36, 0.66, 300 },
            { "Base.Firewood", 0.7, 0.7, 200 }, { "Base.Charcoal", 0.5, 0.5, 45 },
        },
    },
    -- The wind chargers in a row across the screen, smallest first, every rotor facing south.
    wind = {
        open = { along = { -1, 8 }, out = { -1, 8 }, sum = 6, half = 3 },
        chargers = {
            { 0, 6, sprite = Sprites.windScoop }, { 2, 4, sprite = Sprites.windPropeller.wood.S },
            { 4, 2, sprite = Sprites.windPropeller.pipe.S }, { 6, 0, sprite = Sprites.windAlternator.S },
        },
        player = { 2, 6 },
        scout = { 4, 5 },
        shot = { "player" },
    },
    -- The treadmill, wired to a battery box beside it, the character running on it across the
    -- screen, side on to the camera. The treadmill's two tiles, by the way its runner faces
    -- (RenewableEnergy.Sprites): the rear tile the runner stands on, and the console in front. The
    -- box stands past the rear end, and the character waits beside the belt.
    gym = {
        rear = { 1, 0 },
        console = { 0, 0 },
        box = { 2, 0 },
        stand = { 1, 1 },
        facing = "W",
        shot = { "rear", "console", "box", "stand" },
        -- Floor of the same room between the treadmill and the camera, where furniture or the
        -- room's near walls, drawn see-through, would stand in front of the runner.
        front = { { -1, 1 }, { 0, 1 }, { 2, 1 }, { 3, 1 }, { -1, 2 }, { 0, 2 }, { 1, 2 }, { 2, 2 }, { 3, 2 },
            { 0, 3 }, { 1, 3 }, { 2, 3 } },
        -- Real time the run plays before the shot, past the blend into the run.
        runMs = 2500,
    },
    -- The wind every shot is taken in, as the climate's wind intensity (ClimateManager: 120 km/h at
    -- 1): a fresh breeze, past every charger's cut-in and below the storms that break blades.
    windIntensity = 0.3,
    -- A digester well into its working life: how long it has made gas, its warmth, the share of
    -- its potential it holds, its sludge, and the manure waiting in its hopper.
    digester = { ageHours = 24 * 30, temp = 32, potential = 0.6, sludge = 30,
        feed = { "Base.Dung_Cow", "Base.Dung_Cow", "Base.Dung_Pig" } },
    -- A gasifier at work: wood in its hopper, its filter packed with hay, a little of it already
    -- tarry, a fire going if lit, its ash pit part full and some condensate waiting.
    gasifier = { wood = { "Base.Firewood", 6 }, packing = { { "Base.HayTuft", 8 }, { "RenewableEnergy.TarryPacking", 2 } },
        fireKg = 2, ash = 35, condensate = 0.8 },
}
-- How far around each setup radios and televisions are switched off, since their captions
-- float over the shots.
local QUIET_RADIUS = 25

-- Steps ------------------------------------------------------------------------------------------

-- The run whose steps are being added; Promo.capture makes it.
local run
local region, elementRegion = Capture.region, Capture.elementRegion

-- Names ------------------------------------------------------------------------------------------

local icons = {}
local iconOrder = {}

-- Registers an item for the icon sheet and returns its key in captures/.
local function iconFor(fullType)
    local key = "icon_" .. string.gsub(fullType, "%.", "_")
    if not icons[key] then
        local item = instanceItem(fullType)
        icons[key] = { fullType = fullType, name = item:getDisplayName(), texture = Stage.iconTexture(fullType) }
        table.insert(iconOrder, key)
    end
    return key
end

local function itemEntry(fullType, count)
    local key = iconFor(fullType)
    return { icon = key, name = icons[key].name, fullType = fullType, count = count }
end

-- What the build menu's recipe `name` builds (an entity of Entities.txt): its build menu icon,
-- registered for the icon sheet, and its name.
local function buildEntry(name)
    local key = "icon_build_" .. name
    if not icons[key] then
        local script = getScriptManager():getGameEntityScript("Base." .. name)
        local component = script:getComponentScriptFor(ComponentType.CraftRecipe)
        icons[key] = { name = getRecipeDisplayName(name), texture = component:getIconTexture() }
        table.insert(iconOrder, key)
    end
    return { icon = key, name = icons[key].name }
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
        names = { FLUID_CONTAINERS[fluidType] or PZHarness.Test.inputItem(input, PREFER):getFullName() }
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

-- The recipe `name`, a craftRecipe or, with `build`, the build menu's recipe of an entity.
local function recipeEntry(name, build)
    local recipe = getScriptManager():getCraftRecipe(name)
    local entry = {
        id = name,
        name = getRecipeDisplayName(name),
        skills = skillList(recipe:getRequiredSkillCount(), function(i) return recipe:getRequiredSkill(i) end),
        learn = {
            needed = recipe:needToBeLearn(),
            magazines = magazinesTeaching(name),
            auto = skillList(recipe:getAutoLearnAnySkillCount(), function(i) return recipe:getAutoLearnAnySkill(i) end),
            autoAll = skillList(recipe:getAutoLearnAllSkillCount(), function(i) return recipe:getAutoLearnAllSkill(i) end),
            research = researchedBy(name),
        },
        inputs = {},
        outputs = {},
        build = build and buildEntry(name) or nil,
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
    run:add(function()
        local backdrop = run:newBackdrop()
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
    end)
    run:addMatted("icons", function()
        local regions = {}
        for _, icon in ipairs(sheet.icons) do
            table.insert(regions, region(icon.name, sheet:getAbsoluteX() + icon.x, sheet:getAbsoluteY() + icon.y, icon.w, icon.h))
        end
        return regions
    end)
    run:removeBackdrop()
end

-- World ------------------------------------------------------------------------------------------

local function perform(name, args)
    local ok, reason = PowerBank.perform(getPlayer(), name, args)
    if not ok then
        print("REPromo " .. name .. " failed: " .. tostring(reason))
    end
end

local function setBankOn(bank, on)
    perform("setBankOn", { bank = PowerBank.positionOf(bank), on = on })
end

local isGroundCover, clearGroundCover = Stage.isGroundCover, Stage.clearGroundCover

-- Outdoors on solid floor, with no vehicle, no tree unless `trees`, and nothing but the floor,
-- ground cover and the objects `allowed` accepts. A square's walls are objects on it, so walls
-- count too.
local function isClear(square, allowed, trees)
    if not (square and square:isOutside() and square:isSolidFloor() and (trees or not square:HasTree())
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
    if not props then
        return false
    end
    for _, flag in ipairs(WALL_FLAGS) do
        if props:has(flag) then
            return true
        end
    end
    return false
end

-- Places -----------------------------------------------------------------------------------------

-- The places found, by the names of findPlaces' PLACES.
local places = {}

-- A place (see GRID) on `origin` in `frame`: GRID, a SITES entry or a ROAD heading.
local function newPlace(origin, frame)
    return { origin = origin, frame = frame }
end

-- The square at `position` ({ along, out }) of `place`, or nil where none is loaded.
local function at(place, position)
    local origin, frame = place.origin, place.frame
    local along, out = position[1], position[2]
    return getCell():getGridSquare(origin:getX() + along * frame.along[1] + out * frame.out[1],
        origin:getY() + along * frame.along[2] + out * frame.out[2], origin:getZ())
end

-- The squares of `place` at the positions of each list of positions given, in order.
local function squaresAt(place, ...)
    local squares = {}
    for i = 1, select("#", ...) do
        for _, position in ipairs((select(i, ...))) do
            table.insert(squares, at(place, position))
        end
    end
    return squares
end

-- The squares of `place` at `positions` that are loaded and, if given, pass `accepts(square)`.
local function loadedSquares(place, positions, accepts)
    local squares = {}
    for _, position in ipairs(positions) do
        local square = at(place, position)
        if square and (not accepts or accepts(square)) then
            table.insert(squares, square)
        end
    end
    return squares
end

local function removeTrees(place)
    local origin = place.origin
    Stage.removeTrees(origin:getX(), origin:getY(), origin:getZ())
end

-- Whether fn(square) holds for every square of `area` (see GRID) of `place`, stopping at the first
-- that fails. From out `outFrom` rather than the area's own first if given.
local function everyAreaSquare(place, area, fn, outFrom)
    for along = area.along[1], area.along[2] do
        for out = outFrom or area.out[1], area.out[2] do
            local inBand = not area.sum or math.abs(along + out - area.sum) <= area.half
            if inBand and not fn(at(place, { along, out })) then
                return false
            end
        end
    end
    return true
end

local function isOpenArea(place, player, area)
    return everyAreaSquare(place, area, function(square)
        return isOpen(square, player)
    end)
end

-- Clears the ground cover off `area` of `place`, and with `fromWall` off the row along its wall
-- (out 0) too.
local function clearArea(place, area, fromWall)
    everyAreaSquare(place, area, function(square)
        clearGroundCover(square)
        return true
    end, fromWall and 0 or nil)
end

-- Outdoors, against a wall of a room. A panel hangs on a `plain` wall: not a door, a garage door
-- or a window.
local function isAtWall(place, along, plain)
    local square, inside, wallNorth = at(place, { along, 0 }), at(place, { along, -1 }), place.frame.wallNorth
    if not (square and inside and inside:getRoom() and square:getWall(wallNorth) and isClear(square, isOnWall)) then
        return false
    end
    return not plain or (square:getDoorOrWindow(wallNorth) == nil and square:getGarageDoor(wallNorth) == nil)
end

-- Whether the outside wall at `along` has a door or window of class `class` ("IsoDoor",
-- "IsoWindow") into a room.
local function hasOpening(place, along, class)
    local square, inside = at(place, { along, 0 }), at(place, { along, -1 })
    return square ~= nil and inside ~= nil and inside:getRoom() ~= nil and square:isOutside()
        and instanceof(square:getDoorOrWindow(place.frame.wallNorth), class)
end

local function isFreeIndoorsAt(place, position)
    return RenewableEnergy.Debug.isFreeSquare(at(place, position), true)
end

-- North from `square` through its room to the room's north wall: a bank faces south, so it stands
-- there with its back to the wall. Nil outside a room.
local function againstNorthWall(square)
    local room = square and square:getRoom()
    while square and room and square:getRoom() == room do
        if square:getWall(true) then
            return square
        end
        square = getCell():getGridSquare(square:getX(), square:getY() - 1, square:getZ())
    end
    return nil
end

-- Where along the panels' wall the bank's column may be, nearest the panels first.
local ALONG_PANELS = { 0, -1, 1, -2, 2 }
-- The character's square from the bank's, (east, south), the first that fits: in front of it and
-- far enough off to one side that the character hides none of it. In the shot a square south
-- moves the character left as far as a square west does, so a square further east it stands a
-- square further south.
local BESIDE_BANK = { { 0, 2 }, { 1, 3 }, { -2, 1 } }
-- How far east of the bank the room's floor runs on: the game draws the room's east wall faded
-- rather than cut away, and closer it stands over the bank.
local BANK_EAST_CLEAR = 4

-- The squares of the bank shot: from the bank to the character, a square around the character,
-- and the floor east of the bank.
local function eachShotSquare(bank, player, fn)
    for y = bank:getY(), player:getY() + 1 do
        for x = math.min(bank:getX(), player:getX() - 1), math.max(bank:getX() + BANK_EAST_CLEAR, player:getX() + 1) do
            fn(getCell():getGridSquare(x, y, bank:getZ()))
        end
    end
end

-- Whether the bank shot's squares are open floor of the bank's room, so that the character stands
-- clear of every wall: no wall between them, and no door or window but in the back wall beside the
-- bank. A room may have a wall through it, which the shot would show the character in.
local function isOpenShot(bank, player)
    local room, open = bank:getRoom(), true
    eachShotSquare(bank, player, function(square)
        local backWall = square and square:getY() == bank:getY() and square ~= bank
        if not (square and square:getRoom() == room) or square:getDoorOrWindow(false)
            or (square:getDoorOrWindow(true) and not backWall) then
            open = false
            return
        end
        local cell, x, y, z = getCell(), square:getX(), square:getY(), square:getZ()
        for _, beyond in ipairs({ cell:getGridSquare(x + 1, y, z), cell:getGridSquare(x, y + 1, z) }) do
            if beyond:getRoom() == room and square:isSomethingTo(beyond) then
                open = false
            end
        end
    end)
    return open
end

-- The homestead bank's square and the character's. The panels' wall faces south, so the bank
-- stands across the room from it, against the north wall, facing it, with open floor around it
-- and the character. Nil if the room has no such place.
local function bankPlace(place)
    if place.frame.facing ~= "S" then return nil end
    for _, along in ipairs(ALONG_PANELS) do
        local bank = againstNorthWall(at(place, { HOMESTEAD.inside[1] + along, HOMESTEAD.inside[2] }))
        if bank and PowerBank.canPlaceBank(bank) then
            for _, offset in ipairs(BESIDE_BANK) do
                local player = getCell():getGridSquare(bank:getX() + offset[1], bank:getY() + offset[2], bank:getZ())
                if player and isOpenShot(bank, player) then
                    return bank, player
                end
            end
        end
    end
    return nil
end

-- Sets the room in the bank shot: takes the furniture, and anything else standing on the floor,
-- off it, so that nothing stands beside the bank or in front of it or the character, and the back
-- wall's doors off their hinges, since the game draws them standing open into the room even once
-- shut. Walls, what hangs on them, light switches and windows stay.
local function clearBankShot(bank, player)
    eachShotSquare(bank, player, function(square)
        local floor, objects = square:getFloor(), square:getObjects()
        for i = objects:size() - 1, 0, -1 do
            local object = objects:get(i)
            if instanceof(object, "IsoDoor") or (object ~= floor and not isOnWall(object)
                and not instanceof(object, "IsoWindow") and not instanceof(object, "IsoLightSwitch")) then
                square:RemoveTileObject(object)
            end
        end
    end)
end

local function fitsHomestead(place, player)
    for along = AT_WALL[1], AT_WALL[2] do
        if not isAtWall(place, along, true) then
            return false
        end
    end
    return bankPlace(place) ~= nil and isOpenArea(place, player, OPEN)
end

-- At a window if `needWindow`, else at any outside wall.
local function fitsStage0(place, player, needWindow)
    local window = hasOpening(place, 0, "IsoWindow")
    if (needWindow and not window) or not (window or isAtWall(place, 0, false)) then
        return false
    end
    return isFreeIndoorsAt(place, STAGE0.box) and isFreeIndoorsAt(place, STAGE0.player)
        and isOpenArea(place, player, STAGE0.open)
end

-- A window into a house (a building with a bedroom and POSTER.rooms rooms), on a wall with
-- POSTER.windows.count windows near it, with free floor for the bank behind it and open ground for
-- the panels in front.
local function fitsPoster(place, player)
    if not (hasOpening(place, 0, "IsoWindow") and isFreeIndoorsAt(place, POSTER.bank)
        and isOpenArea(place, player, POSTER.open)) then
        return false
    end
    local building = at(place, { 0, -1 }):getBuilding()
    if not (building and building:isResidential() and building:getDef():getRooms():size() >= POSTER.rooms) then
        return false
    end
    local windows = 0
    for along = POSTER.windows.along[1], POSTER.windows.along[2] do
        windows = windows + (hasOpening(place, along, "IsoWindow") and 1 or 0)
    end
    return windows >= POSTER.windows.count
end

-- The markings and blends painted over a road's floor.
local function isRoadPaint(object)
    local sprite = object:getSprite()
    local name = sprite and sprite:getName()
    return name ~= nil and (PZHarness.startsWith(name, "floors_overlay") or PZHarness.startsWith(name, "blends_"))
end

local function isOpenRoad(square, player)
    local floor = square and square:getFloor()
    local name = floor and floor:getSprite() and floor:getSprite():getName()
    return name ~= nil and PZHarness.startsWith(name, "blends_street") and isClear(square, isRoadPaint)
        and square ~= player:getCurrentSquare()
end

-- Outdoors on natural ground (grass or dirt, not a road or a yard's paving) with nothing on it but
-- ground cover and trees, which the setups take away.
local function isYardSquare(square, player)
    local floor = square and square:getFloor()
    local name = floor and floor:getSprite() and floor:getSprite():getName()
    return name ~= nil and PZHarness.startsWith(name, "blends_natural")
        and isClear(square, function(object) return instanceof(object, "IsoTree") end, true)
        and square ~= player:getCurrentSquare()
end

-- Whether `square` is floor of `room` with nothing standing on it, such as furniture or a pot
-- plant: what lies flat, such as a rug, may.
local function isBareFloor(square, room)
    if not (square and square:getRoom() == room) then
        return false
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local props = objects:get(i):getProperties()
        if props and (props:has(IsoFlagType.solid) or props:has(IsoFlagType.solidtrans)) then
            return false
        end
    end
    return true
end

-- Indoors, with free floor of one room for the treadmill, its battery box and the character beside
-- it, nothing between them, and bare floor in front.
local function fitsGym(place)
    local gym, origin = R2.gym, place.origin
    local room = origin:getRoom()
    if not room then
        return false
    end
    for _, key in ipairs(gym.shot) do
        local square = at(place, gym[key])
        if not (square and square:getRoom() == room and RenewableEnergy.Debug.isFreeSquare(square, true)
            and not origin:isSomethingTo(square)) then
            return false
        end
    end
    for _, spot in ipairs(gym.front) do
        if not isBareFloor(at(place, spot), room) then
            return false
        end
    end
    return true
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

-- The place closest to the character, its origin clear of `others`, in the first of `frames` that
-- has one for which fits(place) holds; nil if none has.
local function findPlace(player, others, frames, fits)
    for _, frame in ipairs(frames) do
        local best = Stage.closestSquare(player, function(origin)
            return isApart(origin, others) and fits(newPlace(origin, frame))
        end)
        if best then
            return newPlace(best, frame)
        end
    end
    return nil
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

local function connect(bank, source)
    perform("connectSource", { bank = PowerBank.positionOf(bank), source = PowerBank.positionOf(source) })
end

-- Places a panel on each of `spots` ({ along, out, material }) of `place` and connects it to
-- `bank`, in order: a `mount` ("wall" or "rack") of the spot's material facing the place's way, or
-- without one a flat panel. A mount holds the modules (a PowerBank.MODULES list) of its index in
-- `modules` if given, else whole factory modules.
local function placePanels(bank, place, spots, mount, modules)
    for i, spot in ipairs(spots) do
        local sprite = mount and Sprites[mount][spot[3]][place.frame.facing] or Sprites.flat
        local held = modules and modules[i]
        connect(bank, Stage.placeTile(at(place, spot), sprite, held and { [PowerBank.MODULES] = held } or nil))
    end
end

-- Switches a light on or off; returns whether that changed it.
local function switchLight(light, on)
    return light:isActivated() ~= on and light:setActive(on, false, true) == on
end

-- Switches off every light in reach of the banks, which houses keep on once the grid goes, and
-- takes away the fridges and freezers in reach of the stage-0 box: nothing switches those off,
-- and one alone would overload its Plug-in Inverter.
local function quietNeighbourhood(homesteadSquare, stage0Square)
    local lights, fridges = 0, 0
    for _, bankSquare in ipairs({ homesteadSquare, stage0Square }) do
        RenewableEnergy.eachSquareInGeneratorReach(bankSquare, function(square)
            local objects = square:getObjects()
            for i = objects:size() - 1, 0, -1 do
                local object = objects:get(i)
                if instanceof(object, "IsoLightSwitch") then
                    lights = lights + (switchLight(object, false) and 1 or 0)
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

-- Switches off the radios and televisions around each of `origins`, which play with their
-- captions floating over them.
local function silenceRadios(origins)
    local silenced = 0
    for _, origin in ipairs(origins) do
        for x = origin:getX() - QUIET_RADIUS, origin:getX() + QUIET_RADIUS do
            for y = origin:getY() - QUIET_RADIUS, origin:getY() + QUIET_RADIUS do
                local square = getCell():getGridSquare(x, y, origin:getZ())
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
        for x, y in PZHarness.Fixtures.ring(square:getX(), square:getY(), radius) do
            local near = getCell():getGridSquare(x, y, square:getZ())
            local objects = near and building and near:getBuilding() == building
                and not RenewableEnergy.inGeneratorReach(otherBank, x, y, square:getZ()) and near:getObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local object = objects:get(i)
                if switched < HOUSE_LIGHTS and instanceof(object, "IsoLightSwitch") and switchLight(object, true) then
                    switched = switched + 1
                end
            end
        end
    end
    print("REPromo switched on " .. switched .. " lights")
end

-- Release 2 ------------------------------------------------------------------------------------

-- A generator plugged in on `square` with `fuel` of a full tank.
local function placeGenerator(square, fuel)
    clearGroundCover(square)
    local generator = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), square)
    generator:setConnected(true)
    generator:setFuel(generator:getMaxFuel() * fuel)
    return generator
end

-- A record of RECORD_KINDS kind `kind` built on its Sprites tile `tile` on `square` as the build
-- menu builds one (the tests' Helpers.placeRecord), clear of ground cover. Helpers is server Lua,
-- which loads after this file, so it is required here.
local function placeRecord(kind, tile, square)
    clearGroundCover(square)
    local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
    local thumpable, missing = Helpers.placeRecord(kind, tile, square)
    if not thumpable then
        print("REPromo no " .. kind .. ": " .. tostring(missing))
    end
    return thumpable
end

-- A digester of the Sprites.digester tile `tile` ("barrel.MetalDrum", "dome", ...) built on `square`.
-- It is made one at work (R2.digester), its record's `fields` set over that, a day passed so that
-- it eats from its hopper and says what it makes a day, and its holder `full` of what it takes.
local function placeDigester(square, tile, full, fields)
    local thumpable = placeRecord("digester", tile, square)
    local record, working = RenewableEnergy.Digester.recordOf(thumpable), R2.digester
    for _, fullType in ipairs(working.feed) do
        thumpable:getContainer():AddItem(fullType)
    end
    record.fed, record.started, record.gasHours = true, true, working.ageHours
    record.temp = working.temp
    record.potential = record:tierSpec().potentialCap * working.potential
    record.sludge = working.sludge
    for key, value in pairs(fields or {}) do
        record[key] = value
    end
    record.lastHour = getGameTime():getWorldAgeHours() - 24
    record:update()
    record.gas = full * record:capacity()
    record:afterChange()
    return thumpable
end

-- A gasifier of `tier` built on `square`, at work (R2.gasifier), lit if `lit`.
local function placeGasifier(square, tier, lit)
    local Gasifier, working = RenewableEnergy.Gasifier, R2.gasifier
    local thumpable = placeRecord("gasifier", tier, square)
    for _ = 1, working.wood[2] do
        Gasifier.hopperOf(thumpable):AddItem(working.wood[1])
    end
    for _, packing in ipairs(working.packing) do
        for _ = 1, packing[2] do
            Gasifier.filterOf(thumpable):AddItem(packing[1])
        end
    end
    local record = Gasifier.recordOf(thumpable)
    record.lit = lit
    record.fireKg = lit and working.fireKg or 0
    record.ash, record.condensate = working.ash, working.condensate
    record:afterChange()
    return thumpable
end

-- Fits the gas kit to `generator` and runs its line to `source`, a digester or a gasifier, by
-- the jobs a player does (GasLines.perform), the character holding what they take meanwhile.
local function fitGasKit(generator, source)
    local GasKit, GasLines = RenewableEnergy.GasKit, RenewableEnergy.GasLines
    local player = getPlayer()
    local inventory = player:getInventory()
    local restore = PZHarness.Fixtures.setPerk(player, Perks.Mechanics, 2)
    local given = { inventory:AddItem(GasKit.ITEM), inventory:AddItem("Base.Wrench"), inventory:AddItem(GasKit.PIPE) }
    for _ = 1, GasKit.REACH / GasKit.HOSE_SQUARES do
        table.insert(given, inventory:AddItem(GasKit.HOSE))
    end
    for _, job in ipairs({ GasKit.INSTALL, GasKit.CONNECT }) do
        if not GasLines.perform(player, job, generator, source) then
            print("REPromo gas kit " .. job .. " refused: " .. tostring(GasKit.refusal(player, job, generator, source)))
        end
    end
    for _, item in ipairs(given) do
        if item:getContainer() == inventory then
            inventory:Remove(item)
        end
    end
    restore()
end

-- A generator plugged in and waiting at `layout.generator` of `place`, with a gas kit on an
-- insulated digester at `layout.digester`. Returns the generator.
local function placeKittedGenerator(place, layout)
    local generator = placeGenerator(at(place, layout.generator), 0.7)
    fitGasKit(generator, (placeDigester(at(place, layout.digester), "insulated", 1)))
    return generator
end

-- The squares wind chargers stand on, which the shots frame taller (screenBox).
local tallSquares = {}

-- A wind charger's tile on `square`, turning in the wind as one built does.
local function placeWindCharger(square, spriteName)
    clearGroundCover(square)
    local object = Stage.placeTile(square, spriteName)
    -- As placing it does in multiplayer; single player fires no OnObjectAdded.
    triggerEvent("OnObjectAdded", object)
    tallSquares[square] = true
    return object
end

-- What the shots show besides the setups' places, by name.
local shown = {}
local homesteadBank, stage0Box, posterBank

local function buildHomestead()
    local home = places.homestead
    quietNeighbourhood(home.bank, at(places.stage0, STAGE0.box))
    clearArea(home, OPEN, true)
    clearBankShot(home.bank, home.beside)
    homesteadBank = PowerBank.place(home.bank, Sprites.batteryBankMetal, -1)
    fillBank(homesteadBank, HOMESTEAD_BANK, MORNING_CHARGE)
    placePanels(homesteadBank, home, HOMESTEAD.wallPanels, "wall")
    placePanels(homesteadBank, home, HOMESTEAD.racks, "rack", HOMESTEAD_MODULES)
    placePanels(homesteadBank, home, HOMESTEAD.flatPanels)
    -- A backup generator with a failsafe outside the bank's wall, plugged in and waiting, with a
    -- gas kit on the insulated digester beside it.
    local generator = placeKittedGenerator(home, HOMESTEAD)
    Stage.placeTile(generator:getSquare(), Sprites.failsafe)
    shown.homesteadCharger = placeWindCharger(at(home, HOMESTEAD.windCharger), Sprites.windPropeller.wood[home.frame.facing])
    connect(homesteadBank, shown.homesteadCharger)
    setBankOn(homesteadBank, true)
    switchOnLights(homesteadBank:getSquare(), at(places.stage0, STAGE0.box))
end

local function buildStage0()
    local stage0 = places.stage0
    clearArea(stage0, STAGE0.open)
    stage0Box = PowerBank.place(at(stage0, STAGE0.box), Sprites.batteryBoxWood, -1)
    fillBank(stage0Box, STAGE0_BOX, MORNING_CHARGE)
    placePanels(stage0Box, stage0, STAGE0.flatPanels)
    local charger = Stage.placeTile(at(stage0, STAGE0.cellCharger), Sprites.cellCharger)
    if not charger:getContainer() then
        charger:createContainersFromSpriteProperties()
    end
    for _ = 1, CELL_BATTERIES do
        local battery = charger:getContainer():AddItem(RenewableEnergy.SolarCellCharger.BATTERY)
        battery:setCurrentUsesFloat(0.5)
    end
    -- Set out the way garden light spawns set one out, charged and unlit by day.
    RenewableEnergy.WorldSpawns.placeMoveable(at(stage0, STAGE0.gardenLight), Sprites.gardenLight.off,
        { [RenewableEnergy.SolarGardenLight.CHARGE_KEY] = RenewableEnergy.Specs.gardenLight.wh })
    setBankOn(stage0Box, true)
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
-- diamond is 128 by 64 units at zoom 1, and its tile reaches this far above the floor's centre,
-- or a wind charger's rotor, which is drawn as a model about two storeys tall, TALL_TOP.
local TILE_TOP, TALL_TOP = 224, 560

local function screenBox(squares)
    local zoom = getCore():getZoom(0)
    local halfW, halfH = 64 / zoom, 32 / zoom
    local box = { left = math.huge, right = -math.huge, top = math.huge, bottom = -math.huge }
    for _, square in ipairs(squares) do
        local x, y = onScreen(square)
        box.left = math.min(box.left, x - halfW)
        box.right = math.max(box.right, x + halfW)
        box.top = math.min(box.top, y - (tallSquares[square] and TALL_TOP or TILE_TOP) / zoom)
        box.bottom = math.max(box.bottom, y + halfH)
    end
    return box
end

-- What the yard shots show; the bank stands indoors behind the wall, out of them.
local function homesteadSquares()
    return squaresAt(places.homestead, { HOMESTEAD.generator, HOMESTEAD.player, HOMESTEAD.digester, HOMESTEAD.windCharger },
        HOMESTEAD.wallPanels, HOMESTEAD.racks, HOMESTEAD.flatPanels)
end

-- What the shot of the Release 2 place `name` frames: its wind chargers and its `shot` positions.
local function placeSquares(name)
    local layout, shot = R2[name], {}
    for _, key in ipairs(layout.shot) do
        table.insert(shot, layout[key])
    end
    return squaresAt(places[name], layout.chargers or {}, shot)
end

local function stage0Squares()
    return squaresAt(places.stage0, { STAGE0.box, STAGE0.player, STAGE0.cellCharger, STAGE0.gardenLight }, STAGE0.flatPanels)
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

-- The clothes the character came with, and the settler's, each made once.
local ownClothes, settlerClothes, settlerWeapon

-- Adds the step that dresses the character as the settler, or with `settler` false back in the
-- clothes it came with and empty-handed.
local function addOutfit(settler)
    run:add(function()
        local player = getPlayer()
        if not ownClothes then
            ownClothes, settlerClothes = {}, {}
            local worn = player:getWornItems()
            for i = 0, worn:size() - 1 do
                table.insert(ownClothes, worn:get(i):getItem())
            end
            for _, fullType in ipairs(SETTLER.clothes) do
                table.insert(settlerClothes, player:getInventory():AddItem(fullType))
            end
            settlerWeapon = player:getInventory():AddItem(SETTLER.weapon)
        end
        player:clearWornItems()
        for _, item in ipairs(settler and settlerClothes or ownClothes) do
            player:setWornItem(item:IsClothing() and item:getBodyLocation() or item:canBeEquipped(), item)
        end
        local held = settler and settlerWeapon or nil
        player:setPrimaryHandItem(held)
        player:setSecondaryHandItem(held and held:isTwoHandWeapon() and held or nil)
        triggerEvent("OnClothingUpdated", player)
        player:resetModelNextFrame()
        return DRAW_FRAMES
    end)
end

-- The squares the character has looked around from so far in the run. What it saw stays seen.
local lookedFrom = {}

-- Has the character look around from each of `squares` and stay on the last, since squares they
-- never saw are drawn dark, and sets the zoom `stepsOut` steps out from the closest. Of the others,
-- it skips those it has looked around from already.
local function goTo(squares, stepsOut)
    for i, square in ipairs(squares) do
        if i == #squares or not lookedFrom[square] then
            Stage.addLookAround(run.steps, getPlayer(), square)
            lookedFrom[square] = true
        end
    end
    run:add(function()
        Stage.zoomOut(stepsOut)
        return Capture.zoomSettled()
    end)
end

-- What every group's shots share: noon without grid power, a breeze that turns the wind
-- chargers, and no radio captions around the `origins` of the places the run uses. The harness
-- clears the rest of the weather.
local function addWorldSettings(origins)
    run:add(function()
        -- The grid would power the squares and leave the bank nothing to run.
        PZHarness.Fixtures.setGrid(false)
        getGameTime():setTimeOfDay(NOON)
        local wind = getClimateManager():getClimateFloat(ClimateManager.FLOAT_WIND_INTENSITY)
        wind:setEnableAdmin(true)
        wind:setAdminValue(R2.windIntensity)
        silenceRadios(origins)
        -- The climate takes the wind on its next update.
        return function()
            return getClimateManager():getWindspeedKph() >= R2.windIntensity * 120 * 0.95
        end
    end)
end

-- Logs each bank's status as the window would read it. The promo runs single player, where the
-- banks' records are at hand; the status itself goes only to players watching a bank.
local function logBanks()
    for name, bank in pairs({ homestead = homesteadBank, ["stage 0"] = stage0Box }) do
        local status = PowerBank.serverSystem:getLuaObjectAt(bank:getX(), bank:getY(), bank:getZ()):buildStatus()
        local reasons, kinds = {}, {}
        for _, source in ipairs(status.sources) do
            table.insert(reasons, tostring(source.reason))
        end
        for _, kind in ipairs(status.loadByKind) do
            table.insert(kinds, string.format("%d %s %.0f W", kind.count, kind.kind, kind.watts))
        end
        print(string.format("REPromo %s bank: %s, %.0f W in, %.0f W load of %.0f W (%s), %.0f%% charged,"
            .. " %d of %d input slots, source reasons %s", name, status.state, status.inW, status.loadW, status.limitW,
            table.concat(kinds, ", "), status.charge * 100, status.inputSlots.used, status.inputSlots.total,
            table.concat(reasons, ",")))
    end
end

-- Both setups, charged through the morning; the world, status and menu shots need them.
local function addSetups()
    run:add(function()
        getGameTime():setTimeOfDay(MORNING)
        removeTrees(places.homestead)
        removeTrees(places.stage0)
        buildHomestead()
        buildStage0()
        chargeThroughMorning()
        logBanks()
        return DRAW_FRAMES
    end)
end

local function addWorld()
    local home = places.homestead
    local scouts = loadedSquares(home, HOMESTEAD.scouts)
    table.insert(scouts, at(home, HOMESTEAD.player))
    addOutfit(true)
    -- A step out from the closest zoom, which leaves too little of the house around the panels.
    goTo(scouts, 1)
    run:addOpaque("homestead", function()
        return { centred("homestead", homesteadSquares()) }
    end)
    -- The banner shows the whole homestead a step further out.
    run:add(function()
        getCore():doZoomScroll(0, 1)
        return Capture.zoomSettled()
    end)
    run:addOpaque("world", function()
        return { rightAligned("world", homesteadSquares()) }
    end)
    -- Indoors beside the bank, where the building's near walls are cut away, at the closest zoom.
    -- The wind charger goes first: its rotor, drawn two storeys tall outside the wall, would stand
    -- over the room once the wall is cut away. The status and menu groups, which list it, come
    -- before this one in MODE_GROUPS_promo.
    run:add(function()
        local charger = shown.homesteadCharger
        charger:getSquare():transmitRemoveItemFromSquare(charger)
    end)
    goTo({ home.beside }, 0)
    run:addOpaque("bank", function()
        return { cropped("bank", { home.bank, home.beside }) }
    end)
    -- Stage 0 is small, so it gets the closest zoom too. The character sees the panels first from
    -- among them, then from the window, early on, in the clothes it came with.
    addOutfit(false)
    goTo(squaresAt(places.stage0, { STAGE0.scout, STAGE0.player }), 0)
    run:addOpaque("stage0", function()
        return { centred("stage0", stage0Squares()) }
    end)
end

-- Adds the steps that open the window `open()` returns on a backdrop, wait until `ready(window)`
-- and the UI has drawn it again, shoot it as `name` and close it.
local function addWindowShot(name, open, ready)
    local window
    run:add(function()
        run:newBackdrop()
        window = open()
        window:setX(100)
        window:setY(100)
        return function()
            return ready(window)
        end
    end)
    run:add(function()
        return Capture.drawn(2)
    end)
    run:addMatted(name, function()
        return { elementRegion(name, window) }
    end)
    run:add(function()
        window:close()
    end)
    run:removeBackdrop()
end

-- The homestead bank's status window, which lays its rows out from the bank's status as it draws.
local function addStatus()
    addWindowShot("status", function()
        return RenewableEnergy.StatusWindow.open(0, PowerBank.bankOn(places.homestead.bank))
    end, function(window)
        return (window.renderedFrames or 0) >= 2
    end)
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
    run:add(function()
        run:newBackdrop()
        -- In debug mode vanilla adds its debug options to every world menu unless told not to.
        getDebugOptions():setBoolean("UI.HideDebugContextMenuOptions", true)
        local inventory = getPlayer():getInventory()
        for _, fullType in ipairs(MENU_ITEMS) do
            table.insert(carried, inventory:AddItem(fullType))
        end
        local context = ISWorldObjectContextMenu.createMenu(0, { homesteadBank }, MENU_AT, MENU_AT)
        -- A light switch on the bank's wall adds its own option above the bank's.
        local switch = RenewableEnergy.findObjectOn(homesteadBank:getSquare(), function(object)
            return instanceof(object, "IsoLightSwitch")
        end)
        if switch then
            context:removeOptionByName(switch:getTileName())
        end
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
    end)
    run:addMatted("menu", function()
        local left, top, right, bottom = math.huge, math.huge, 0, 0
        for _, menu in ipairs(menus) do
            left, top = math.min(left, menu:getAbsoluteX()), math.min(top, menu:getAbsoluteY())
            right = math.max(right, menu:getAbsoluteX() + menu:getWidth())
            bottom = math.max(bottom, menu:getAbsoluteY() + menu:getHeight())
        end
        return { region("menu", left, top, right - left, bottom - top) }
    end)
    run:add(function()
        menus[1]:hideAndChildren()
        for _, item in ipairs(carried) do
            getPlayer():getInventory():Remove(item)
        end
        return 1
    end)
    run:removeBackdrop()
end

-- Where extract.py looks for the item in a studio shot: STUDIO.window around the studio
-- square's floor centre, kept on the screen.
local function studioWindow(name)
    local x, y = onScreen(places.studio.origin)
    local window = STUDIO.window
    local left, top = math.max(0, x - window.half), math.max(0, y - window.up)
    local right = math.min(getCore():getScreenWidth(), x + window.half)
    local bottom = math.min(getCore():getScreenHeight(), y + window.down)
    return region(name, left, top, right - left, bottom - top)
end

-- Every item alone on the studio floor. `models` gets one entry per item.
local function addModels(items, models)
    local group = run.current
    local studio = places.studio
    local floorSquare = studio.origin
    local zoomLevels
    run:add(function()
        local asphalt = places.road.origin:getFloor():getSprite():getName()
        print("REPromo item floor " .. asphalt)
        everyAreaSquare(studio, STUDIO.floor, function(square)
            clearGroundCover(square)
            if isClear(square) then
                square:addFloor(asphalt)
            end
            return true
        end)
        zoomLevels = { getCore():getOptionZoomLevels1x(), getCore():getOptionZoomLevels2x() }
        getCore():setOptionZoomLevels1x(zoomLevels[1] .. ";" .. STUDIO.zoom)
        getCore():setOptionZoomLevels2x(zoomLevels[2] .. ";" .. STUDIO.zoom)
        getCore():zoomLevelsChanged()
        -- Every item at once, so that their models load while the character looks around: Lua
        -- can't tell when a model has loaded, and a loaded one draws on the next frame.
        for _, item in ipairs(items) do
            floorSquare:AddWorldInventoryItem(instanceItem(item.fullType), 0.5, 0.5, 0)
        end
    end)
    goTo({ at(studio, STUDIO.player) }, 0)
    local floor = run.prefix .. "models_floor"
    run:add(function()
        floorSquare:removeAllWorldObjects()
        return DRAW_FRAMES
    end)
    run:add(function()
        run:screenshot(floor)
    end)
    for _, item in ipairs(items) do
        local name = "model_" .. string.gsub(item.fullType, "%.", "_")
        run:add(function()
            local placed = instanceItem(item.fullType)
            placed:setWorldZRotation(STUDIO.rotation)
            floorSquare:AddWorldInventoryItem(placed, 0.5, 0.5, 0)
            return DRAW_FRAMES
        end)
        run:add(function()
            local file = run.prefix .. name
            run:screenshot(file)
            table.insert(models, { name = name, group = group, file = file, floor = floor, window = studioWindow(name) })
            floorSquare:removeAllWorldObjects()
        end)
    end
    run:add(function()
        getCore():setOptionZoomLevels1x(zoomLevels[1])
        getCore():setOptionZoomLevels2x(zoomLevels[2])
        getCore():zoomLevelsChanged()
    end)
end

-- The arrow board trailer hitched to a car on the road, cones behind it, a step out from the
-- closest zoom.
local function addTrailer()
    local road = places.road
    local pair
    addOutfit(false)
    run:add(function()
        local car = road.origin
        local x, y, z, reach = car:getX(), car:getY(), car:getZ(), ROAD.clearRadius
        removeTrees(road)
        Stage.removeVehicles(x - reach, y - reach, x + reach, y + reach, z)
        for _, spot in ipairs(ROAD.cones) do
            Stage.placeTile(at(road, spot), ROAD.cone)
        end
        pair = Stage.spawnTrailer(car, road.frame.facing)
        return Stage.vehiclesAtRest(pair, false)
    end)
    run:add(function()
        Stage.hitchTrailer(pair, getPlayer(), "REPromo")
        -- Its arrow lit, as work zones leave them.
        Stage.holdLampsLit(pair.trailer)
        return Stage.vehiclesAtRest(pair, true)
    end)
    -- From the item floor first, as a full run's character has by now: the hedges and fences along
    -- a road hide what lies past them from the road itself.
    goTo({ at(places.studio, STUDIO.player), at(road, ROAD.player) }, 1)
    run:addOpaque("trailer", function()
        -- The car's nose, the trailer, the character and the cones.
        return { centred("trailer", squaresAt(road, { { 2, 0 }, ROAD.trailer, ROAD.player }, ROAD.cones)) }
    end)
end

-- Garden lights along a house's front walk, charged and lit at night, at the closest zoom.
local function addGardenLights()
    local SolarGardenLight = RenewableEnergy.SolarGardenLight
    local walk = places.walk
    addOutfit(false)
    run:add(function()
        removeTrees(walk)
        clearArea(walk, WALK.open)
        for _, spot in ipairs(WALK.lights) do
            RenewableEnergy.WorldSpawns.placeMoveable(at(walk, spot), Sprites.gardenLight.off,
                { [SolarGardenLight.CHARGE_KEY] = RenewableEnergy.Specs.gardenLight.wh, [SolarGardenLight.BULB_KEY] = spot.bulb })
        end
        getGameTime():setTimeOfDay(WALK.hour)
        -- The lighting takes most of a second to follow the clock.
        return Stage.lightingSettled(getPlayer(), true)
    end)
    run:add(function()
        -- Lit now, rather than at the next minute's pass. Their light shows while the character
        -- looks around.
        SolarGardenLight.updateAll(0)
    end)
    goTo(squaresAt(walk, { WALK.scout, WALK.player }), 0)
    run:addOpaque("gardenlights", function()
        return { centred("gardenlights", squaresAt(walk, { { 0, -1 }, WALK.player }, WALK.lights)) }
    end)
end

-- The poster's setup, built after dark so that the bank's first pass starts its clock there rather
-- than running the house's lights through the evening. Every light in the house that the bank
-- reaches goes on, upstairs too, and every other light in its reach off; the other setups' banks
-- go off, so that this is the one lit house.
local function buildPoster()
    local poster = places.poster
    clearArea(poster, POSTER.open, true)
    posterBank = PowerBank.place(at(poster, POSTER.bank), Sprites.batteryBankMetal, -1)
    fillBank(posterBank, HOMESTEAD_BANK, 1)
    placePanels(posterBank, poster, POSTER.racks, "rack")
    placePanels(posterBank, poster, POSTER.flatPanels)
    connect(posterBank, placeWindCharger(at(poster, POSTER.windCharger), Sprites.windPropeller.wood[poster.frame.facing]))
    placeKittedGenerator(poster, POSTER)
    for _, bank in ipairs({ homesteadBank, stage0Box }) do
        setBankOn(bank, false)
    end
    setBankOn(posterBank, true)
    local building = posterBank:getSquare():getBuilding()
    local lit, unlit = 0, 0
    RenewableEnergy.eachSquareInGeneratorReach(posterBank:getSquare(), function(square)
        local inHouse = square:getBuilding() == building
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if instanceof(object, "IsoLightSwitch") and switchLight(object, inHouse) then
                lit, unlit = lit + (inHouse and 1 or 0), unlit + (inHouse and 0 or 1)
            end
        end
    end)
    print(string.format("REPromo poster: switched on %d lights in the house and off %d around it", lit, unlit))
end

-- A square as tall as the screen, centred across on the house and the panels.
local function posterRegion()
    local poster = places.poster
    local def = posterBank:getSquare():getBuilding():getDef()
    local squares = squaresAt(poster, { POSTER.player }, POSTER.racks, POSTER.flatPanels,
        { POSTER.generator, POSTER.digester, POSTER.windCharger })
    for _, corner in ipairs({ { def:getX(), def:getY() }, { def:getX2() - 1, def:getY() },
        { def:getX(), def:getY2() - 1 }, { def:getX2() - 1, def:getY2() - 1 } }) do
        local square = getCell():getGridSquare(corner[1], corner[2], poster.origin:getZ())
        if square then
            table.insert(squares, square)
        end
    end
    local box = screenBox(squares)
    local size = getCore():getScreenHeight()
    local left = math.max(0, math.min(getCore():getScreenWidth() - size, (box.left + box.right - size) / 2))
    return region("poster", left, 0, size, size)
end

local function addPoster()
    local poster = places.poster
    -- The homestead at night, its settler by the racks.
    addOutfit(true)
    run:add(function()
        removeTrees(poster)
    end)
    local scouts = loadedSquares(poster, POSTER.indoors, function(square)
        return RenewableEnergy.Debug.isFreeSquare(square, true)
    end)
    for _, square in ipairs(loadedSquares(poster, POSTER.scouts)) do
        table.insert(scouts, square)
    end
    table.insert(scouts, at(poster, POSTER.player))
    goTo(scouts, POSTER.zoomOut)
    run:add(function()
        getGameTime():setTimeOfDay(POSTER.hour)
        buildPoster()
        return Stage.lightingSettled(getPlayer(), true)
    end)
    run:addOpaque("poster", function()
        return { posterRegion() }
    end)
end

-- Release 2 shots ---------------------------------------------------------------------------------

-- A function giving the square of the Release 2 place `name` at its R2 layout's position `key`.
local function spotsOf(name)
    local place, layout = places[name], R2[name]
    return function(key)
        return at(place, layout[key])
    end
end

-- Clears the trees around the Release 2 place `name` and the ground cover of its band.
local function clearYard(name)
    removeTrees(places[name])
    clearArea(places[name], R2[name].open)
end

-- Has the character look around the Release 2 place `name` from its scout square, if it has one,
-- then stand on its `standAt` square (its player square by default), `stepsOut` from the closest
-- zoom.
local function goToPlace(name, stepsOut, standAt)
    local layout = R2[name]
    local squares = { at(places[name], layout[standAt or "player"]) }
    if layout.scout then
        table.insert(squares, 1, at(places[name], layout.scout))
    end
    goTo(squares, stepsOut)
end

-- The window of `windowClass` (RenewableEnergy.DigesterWindow or GasifierWindow) on what the shots
-- show under `key`, which lays its rows out from the summary as it draws.
local function addGasWindow(name, windowClass, key)
    addWindowShot(name, function()
        return windowClass.open(0, shown[key])
    end, function(window)
        return window.rowsToDraw ~= nil
    end)
end

-- Every digester at work, a step out from the closest zoom, then the brick dome's window.
local function addBiogas()
    addOutfit(true)
    run:add(function()
        local here = spotsOf("biogas")
        clearYard("biogas")
        -- The heater first: the barrel's pass reads whether it is heated from the lit heater tile
        -- beside it (DigesterObject:advance).
        Stage.placeTile(here("heater"), Sprites.gasHeater.lit)
        placeDigester(here("barrelSteel"), "barrel.MetalDrum", 1)
        placeDigester(here("barrelOrange"), "barrel.Mov_OrangeBarrel", 0.6, { holder = "tarp" })
        placeDigester(here("insulated"), "insulated", 0.8)
        shown.digester = placeDigester(here("dome"), "dome", 0.9)
        local generator = placeGenerator(here("generator"), 0.2)
        fitGasKit(generator, shown.digester)
        generator:setActivated(true)
        return DRAW_FRAMES
    end)
    goToPlace("biogas", 1)
    run:addOpaque("biogas", function()
        return { centred("biogas", placeSquares("biogas")) }
    end)
    addGasWindow("digester", RenewableEnergy.DigesterWindow, "digester")
end

-- The gasifiers, the lit ones piped to running generators, a step out from the closest zoom,
-- then the gasifier's window.
local function addWoodgas()
    addOutfit(true)
    run:add(function()
        local here = spotsOf("woodgas")
        clearYard("woodgas")
        placeGasifier(here("primitive"), "primitive", false)
        for _, fuel in ipairs(R2.woodgas.fuelItems) do
            local item = instanceItem(fuel[1])
            item:setWorldZRotation(fuel[4])
            here("fuel"):AddWorldInventoryItem(item, fuel[2], fuel[3], 0)
        end
        for _, tier in ipairs({ "standard", "advanced" }) do
            local gasifier = placeGasifier(here(tier), tier, true)
            local generator = placeGenerator(here(tier .. "Generator"), 0.2)
            fitGasKit(generator, gasifier)
            generator:setActivated(true)
            shown[tier] = gasifier
        end
        return DRAW_FRAMES
    end)
    goToPlace("woodgas", 1)
    run:addOpaque("woodgas", function()
        return { centred("woodgas", placeSquares("woodgas")) }
    end)
    addGasWindow("gasifier", RenewableEnergy.GasifierWindow, "standard")
end

-- The wind chargers turning in the breeze, a step out from the closest zoom.
local function addWind()
    addOutfit(true)
    run:add(function()
        clearYard("wind")
        for _, spot in ipairs(R2.wind.chargers) do
            placeWindCharger(at(places.wind, spot), spot.sprite)
        end
        return DRAW_FRAMES
    end)
    goToPlace("wind", 1)
    run:addOpaque("wind", function()
        return { centred("wind", placeSquares("wind")) }
    end)
end

-- The treadmill wired to a battery box of car batteries beside it, as stage 0's, then the
-- character running on it, indoors at the closest zoom, in the clothes it came with.
local function addTreadmill()
    local layout = R2.gym
    addOutfit(false)
    run:add(function()
        local here = spotsOf("gym")
        local box = PowerBank.place(here("box"), Sprites.batteryBoxWood, -1)
        fillBank(box, STAGE0_BOX, MORNING_CHARGE)
        local tiles = Sprites.treadmill[layout.facing]
        Stage.placeTile(here("rear"), tiles.rear)
        shown.treadmill = Stage.placeTile(here("console"), tiles.console, { [RenewableEnergy.Treadmill.WIRED] = true })
        connect(box, shown.treadmill)
        setBankOn(box, true)
        return DRAW_FRAMES
    end)
    goToPlace("gym", 0, "stand")
    run:add(function()
        ISTimedActionQueue.add(RenewableEnergyTreadmillAction:new(getPlayer(), shown.treadmill))
        local started = getTimestampMs()
        return function()
            return getTimestampMs() - started >= layout.runMs
        end
    end)
    run:addOpaque("treadmill", function()
        return { centred("treadmill", placeSquares("gym")) }
    end)
    run:add(function()
        ISTimedActionQueue.clear(getPlayer())
        return DRAW_FRAMES
    end)
end

-- Finding the places ------------------------------------------------------------------------------

-- A Release 2 yard: a band of natural ground (R2[name].open) clear for it.
local function yard(name)
    return {
        name = name,
        label = name,
        missing = "open ground for the " .. name .. " shot",
        frames = { GRID },
        fits = function(place, player)
            return everyAreaSquare(place, R2[name].open, function(square)
                return isYardSquare(square, player)
            end)
        end,
    }
end

-- Every place a group may need (GROUPS' `places`), in the order findPlaces looks for them: what the
-- log calls it, what is missing when there is none, and either the `frames` to try in order and
-- whether a place `fits(place, player)`, or `find(player, others)` returning the place or nil;
-- `detail(place)` adds to its line in the log.
local PLACES = {
    {
        name = "homestead",
        label = "homestead",
        missing = "plain building wall with open ground in front and a room behind it with open floor along its north wall",
        find = function(player, others)
            local place = findPlace(player, others, SITES, function(candidate)
                return fitsHomestead(candidate, player)
            end)
            if place then
                place.bank, place.beside = bankPlace(place)
            end
            return place
        end,
        detail = function(place)
            return string.format(", bank %d,%d, character beside it %d,%d", place.bank:getX(), place.bank:getY(),
                place.beside:getX(), place.beside:getY())
        end,
    },
    {
        name = "stage0",
        label = "stage 0",
        missing = "outside wall with free floor indoors behind it and open ground in front, for stage 0",
        -- At a window if any.
        find = function(player, others)
            for _, needWindow in ipairs({ true, false }) do
                local place = findPlace(player, others, SITES, function(candidate)
                    return fitsStage0(candidate, player, needWindow)
                end)
                if place then
                    place.atWindow = needWindow
                    return place
                end
            end
            return nil
        end,
        detail = function(place)
            return place.atWindow and ", at a window" or ", at a wall"
        end,
    },
    {
        name = "road",
        label = "trailer",
        missing = "stretch of open road for the trailer",
        frames = ROAD.headings,
        fits = function(place, player)
            return everyAreaSquare(place, ROAD.open, function(square)
                return isOpenRoad(square, player)
            end)
        end,
    },
    {
        name = "studio",
        label = "items",
        missing = "open ground for the item shots' floor",
        frames = { GRID },
        fits = function(place, player)
            return isOpenArea(place, player, STUDIO.open)
        end,
    },
    {
        name = "walk",
        label = "garden lights",
        missing = "door with open ground in front, for the garden lights",
        frames = SITES,
        fits = function(place, player)
            return hasOpening(place, 0, "IsoDoor") and isOpenArea(place, player, WALK.open)
        end,
    },
    {
        name = "poster",
        label = "poster",
        missing = "wall with " .. POSTER.windows.count .. " windows and open ground in front, for the poster",
        frames = SITES,
        fits = fitsPoster,
    },
    yard("biogas"),
    yard("woodgas"),
    yard("wind"),
    {
        name = "gym",
        label = "treadmill",
        missing = "room with free floor for the treadmill",
        frames = { GRID },
        fits = fitsGym,
    },
}

-- Finds the places in `needs` into `places`, each clear of those found before it, and returns
-- their origins, or nil and the first it can't find. A run of every group looks for all of them.
local function findPlaces(player, needs)
    local found, logged = {}, {}
    for _, spec in ipairs(PLACES) do
        if needs[spec.name] then
            local place
            if spec.find then
                place = spec.find(player, found)
            else
                place = findPlace(player, found, spec.frames, function(candidate)
                    return spec.fits(candidate, player)
                end)
            end
            if not place then
                return nil, spec.missing
            end
            places[spec.name] = place
            local origin, facing = place.origin, place.frame.facing
            table.insert(found, origin)
            table.insert(logged, string.format("%s %d,%d", spec.label, origin:getX(), origin:getY())
                .. (facing and " facing " .. facing or "") .. (spec.detail and spec.detail(place) or ""))
        end
    end
    if #logged > 0 then
        print("REPromo " .. table.concat(logged, "; "))
    end
    return found
end

-- The groups of dev/harness.conf's MODE_GROUPS_promo: the places of findPlaces their steps use,
-- whether they need both setups built, and what adds their steps. A run looks only for its groups'
-- places, so that one group can't fail for want of a place another needs.
local GROUPS = {
    world = { places = { "homestead", "stage0" }, setups = true, add = addWorld },
    status = { places = { "homestead", "stage0" }, setups = true, add = addStatus },
    menu = { places = { "homestead", "stage0" }, setups = true, add = addMenu },
    icons = { places = {}, add = addIcons },
    -- The item floor is the road's asphalt.
    models = { places = { "road", "studio" }, add = function(data) addModels(data.items, data.models) end },
    -- The character looks around from the item floor first, as a full run's has by then.
    trailer = { places = { "road", "studio" }, add = addTrailer },
    biogas = { places = { "biogas" }, add = addBiogas },
    woodgas = { places = { "woodgas" }, add = addWoodgas },
    wind = { places = { "wind" }, add = addWind },
    treadmill = { places = { "gym" }, add = addTreadmill },
    gardenlights = { places = { "walk" }, add = addGardenLights },
    poster = { places = { "poster" }, add = addPoster },
}

-- Adds a step that starts a clock, and returns a function that adds a step logging, under
-- "REPromo TIME", how long the steps added in between took.
local function addTimer(label)
    local started
    run:add(function()
        started = getTimestampMs()
    end)
    return function()
        run:add(function()
            print(string.format("REPromo TIME %s %.1f s", label, (getTimestampMs() - started) / 1000))
        end)
    end
end

--- Shoots the groups named in `selection`, comma-separated in the order to shoot them, which
--- run-client.sh gives every group of MODE_GROUPS_promo when PROMO names none, and calls onDone.
function Promo.capture(selection, onDone)
    print("REPromo START " .. selection)
    run = Capture.new("REPromo")
    local chosen, needs = Capture.names(selection), {}
    for _, name in ipairs(chosen) do
        if not GROUPS[name] then
            run:fail("MODE_GROUPS_promo names " .. name .. ", which GROUPS lacks")
            return
        end
        for _, place in ipairs(GROUPS[name].places) do
            needs[place] = true
        end
    end
    local origins, missing = findPlaces(getPlayer(), needs)
    if not origins then
        run:fail("within " .. Stage.SEARCH_RADIUS .. " squares, no " .. missing)
        return
    end
    -- Hides the HUD, the debug console and every other window; the shots add their own.
    ISUIHandler.setVisibleAllUI(false)
    -- In a corner, where it hovers over nothing the shots show: the world outlines what it is
    -- over, and menus follow it.
    setMouseXY(0, 0)
    -- The names come with every run, since they cost no shot.
    local data = { items = itemsList(), recipes = {}, models = {} }
    for _, name in ipairs(PZHarness.Test.recipeNames()) do
        table.insert(data.recipes, recipeEntry(name))
    end
    -- The build menu's, which recipeNames leaves out.
    for _, name in ipairs(RenewableEnergy.Debug.buildRecipes()) do
        table.insert(data.recipes, recipeEntry(name, true))
    end
    data.strings = {
        modName = getText("Sandbox_RenewableEnergy"),
    }
    local endTotal = addTimer("total")
    addWorldSettings(origins)
    local setupsBuilt = false
    for _, name in ipairs(chosen) do
        local group = GROUPS[name]
        run:group(name)
        local endGroup = addTimer(name)
        if group.setups and not setupsBuilt then
            addSetups()
            setupsBuilt = true
        end
        group.add(data)
        endGroup()
    end
    endTotal()
    run:run(data, onDone)
end

return Promo
