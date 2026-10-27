-- Development only; dev/run-debug-client.sh --promo runs it instead of the tests. It builds the
-- setups near the scenario start and saves the raw art that art/promo/compose.py lays out:
-- promo_<shot>.png screenshots, and <mark>.json naming each screenshot's regions and the item,
-- recipe and skill names in the game's language, which the harness's lib/capture.py turns into
-- art/promo/captures. PROMO=<group>,... shoots only those groups, building only the setups they
-- need. Shots of anything but the world are taken on black and on white (PZHarness/Capture.lua),
-- and the empty item floor too, so that lib/capture.py can find each item model by difference.

require "PZHarness/Fixtures"
local Specs = require "RenewableEnergy/Specs"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local SolarCellCharger = require "RenewableEnergy/Gadgets/SolarCellCharger"
local Digester = require "RenewableEnergy/Biogas/Digester"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local Capture = require "PZHarness/Capture"
local HarnessQA = require "PZHarness/QA"
require "ISUI/ISWorldObjectContextMenu"
local Debug = require "RenewableEnergy/Debug/RenewableEnergyDebug"
local Sprites = require "RenewableEnergy/Sprites"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local StatusWindow = require "RenewableEnergy/UI/StatusWindow"
local BankMenu = require "RenewableEnergy/UI/BankMenu"
require "RenewableEnergy/UI/SourceMenu"
require "RenewableEnergy/UI/GardenLightMenu"
local DigesterWindow = require "RenewableEnergy/UI/DigesterWindow"
local GasifierWindow = require "RenewableEnergy/UI/GasifierWindow"
require "RenewableEnergy/TimedActions/RenewableEnergyTreadmillAction"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Stage = require "RenewableEnergyDevStage"
local Harness = require "PZHarness/Stage"
require "PZHarness/StageLots"
local Squares = require "cf_commonlib/Squares"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local Places = require "RenewableEnergyDevPromoPlaces"
local Fixtures = require "RenewableEnergy/Debug/RenewableEnergyFixtures"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Wind = require "RenewableEnergy/Wind"

local Promo = {}

-- The run whose steps are being added, and the places it found (Places.PLACES by name);
-- Promo.capture makes them.
local run, places


local DRAW_FRAMES = Capture.DRAW_FRAMES

-- A recipe line that takes or fills any fluid container shows this one, by the fluid's type.
local FLUID_CONTAINERS = { Acid = "RenewableEnergy.BatteryElectrolyte", Water = "Base.WaterBottle",
    RenewableEnergy_WoodVinegar = "Base.BottleCrafted" }
-- Banks take vanilla car batteries as they are, so the item sheet shows one.
local VANILLA_ITEMS = { "Base.CarBattery1" }

-- What the character wears at the homestead, a settler long into the apocalypse: road leathers,
-- armour pieced together from scrap metal and tyres, goggles, a scarf against the dust, and a
-- sawn-off in hand. Elsewhere it wears the clothes it came with (OWN_CLOTHES).
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
local OWN_CLOTHES = { ownClothes = true }

-- Setups -------------------------------------------------------------------------------------------
-- The banks, their parts and sources, the generators, digesters, gasifiers and wind chargers, and
-- the squares each shot frames, built at the places RenewableEnergyDevPromoPlaces.lua finds.

-- The banks charge through the morning, so the window shows a day's figures at noon.
local MORNING, NOON = 8, 12

-- The rack with a cracked module, connected early so that its row shows in the status window: the
-- modules of HOMESTEAD.racks by index.
local MODULE = Specs.factoryModule
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

local STAGE0_BOX = { "Base.CarBattery1", "Base.CarBattery1", "RenewableEnergy.PlugInInverter", "Base.CarBatteryCharger" }
local CELL_BATTERIES = 4

-- A digester well into its working life: how long it has made gas, its warmth, the share of its
-- tier's potential cap it holds, its sludge, and the manure waiting in its hopper.
local WORKING_DIGESTER = { gasHours = 24 * 30, temp = 32, potential = 0.6, sludge = 30,
    feed = { "Base.Dung_Cow", "Base.Dung_Cow", "Base.Dung_Pig" } }
-- A gasifier at work: wood in its hopper, its filter packed with hay, a little of it already
-- tarry, a fire going if lit, its ash pit part full and some condensate waiting.
local WORKING_GASIFIER = { wood = { "Base.Firewood", 6 },
    packing = { { "Base.HayTuft", 8 }, { "RenewableEnergy.TarryPacking", 2 } }, fireKg = 2, ash = 35, condensate = 0.8 }

-- Does `job` of `feature` as the character, the way the action's complete() does it, saying why
-- the job module refused it if it did.
local function doJob(feature, job, target, with)
    local Action, player = RenewableEnergyAction, getPlayer()
    if not Action.completeJob(player, feature, job, target, with) then
        print(run.mark .. " " .. job .. " refused: " .. tostring(Action.jobsOf(feature).refusal(player, job, target, with)))
    end
end

local function switchOn(bank)
    doJob("bank", BankJobs.TURN_ON, bank)
end

local function removeTrees(place)
    local origin = place.origin
    Harness.removeTrees(origin:getX(), origin:getY(), origin:getZ())
end

-- Clears the ground cover off `area` of `place`, and with `fromWall` off the row along its wall
-- (out 0) too.
local function clearArea(place, area, fromWall)
    Harness.everyAreaSquare(place, area, function(square)
        Harness.clearGroundCover(square)
        return true
    end, fromWall and 0 or nil)
end

-- Sets the room in the bank shot: takes the furniture, and anything else standing on the floor,
-- off it, so that nothing stands beside the bank or in front of it or the character, and the back
-- wall's doors off their hinges, since the game draws them standing open into the room even once
-- shut. Walls, what hangs on them, light switches and windows stay.
local function clearBankShot(bank, player)
    Places.eachShotSquare(bank, player, function(square)
        Harness.clearToFloor(square, function(object)
            return not instanceof(object, "IsoDoor") and (Places.isOnWall(object) or instanceof(object, "IsoWindow")
                or instanceof(object, "IsoLightSwitch"))
        end)
    end)
end

-- Places a bank and puts the parts straight into its container, as world spawns stock a bank.
local function placeBank(square, sprite, items, charge)
    local BankSystem = require "RenewableEnergy/PowerBank/BankSystem"
    return BankSystem.place(square, sprite, nil, function(container)
        for _, fullType in ipairs(items) do
            local item = container:AddItem(fullType)
            if Battery.isBattery(item) then
                Battery.setCharge(item, charge)
            end
        end
    end)
end

-- Set out the way garden light spawns set one out, charged and unlit by day.
local function placeGardenLight(square, bulb)
    local Place = require "RenewableEnergy/World/Place"
    Place.moveable(square, Sprites.gardenLight.off,
        { [SolarGardenLight.CHARGE_KEY] = SolarGardenLight.SPEC.wh, [SolarGardenLight.BULB_KEY] = bulb })
end

local function connect(bank, source)
    doJob("source", SourceJobs.CONNECT, source, bank)
end

-- Places a panel on each of `spots` ({ along, out, material }) of `place` and connects it to
-- `bank`, in order: a `mount` ("wall" or "rack") of the spot's material facing the place's way, or
-- without one a flat panel. A mount holds the modules (a Panel.MODULES_KEY list) of its index in
-- `modules` if given, else whole factory modules.
local function placePanels(bank, place, spots, mount, modules)
    for i, spot in ipairs(spots) do
        local sprite = mount and Sprites[mount][spot[3]][place.frame.facing] or Sprites.flat
        local held = modules and modules[i]
        connect(bank, Harness.placeTile(Harness.at(place, spot), sprite, held and { [Panel.MODULES_KEY] = held } or nil))
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
        GeneratorReach.eachSquare(bankSquare:getX(), bankSquare:getY(), bankSquare:getZ(), function(square)
            local objects = square:getObjects()
            for i = objects:size() - 1, 0, -1 do
                local object = objects:get(i)
                if instanceof(object, "IsoLightSwitch") then
                    lights = lights + (switchLight(object, false) and 1 or 0)
                elseif bankSquare == stage0Square and object:getContainerByEitherType("fridge", "freezer") then
                    square:RemoveTileObject(object)
                    fridges = fridges + 1
                end
            end
        end)
    end
    print(string.format("%s switched off %d lights and took away %d fridges", run.mark, lights, fridges))
end

-- Switches on lights in the building around `square`, nearest first, out of reach of the bank
-- on `otherBank`. They draw on the bank, which is the only power with the grid off.
local function switchOnLights(square, otherBank)
    local building = square:getBuilding()
    local bankX, bankY, bankZ = otherBank:getX(), otherBank:getY(), otherBank:getZ()
    local switched = 0
    for radius = 0, LIGHT_SEARCH do
        for x, y in PZHarness.Fixtures.ring(square:getX(), square:getY(), radius) do
            local near = getCell():getGridSquare(x, y, square:getZ())
            local objects = near and building and near:getBuilding() == building
                and not GeneratorReach.covers(bankX, bankY, bankZ, x, y, square:getZ()) and near:getObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local object = objects:get(i)
                if switched < HOUSE_LIGHTS and instanceof(object, "IsoLightSwitch") and switchLight(object, true) then
                    switched = switched + 1
                end
            end
        end
    end
    print(run.mark .. " switched on " .. switched .. " lights")
end

-- Gas, wind and treadmill ------------------------------------------------------------------------

-- A generator plugged in on `square` with `fuel` of a full tank.
local function placeGenerator(square, fuel)
    Harness.clearGroundCover(square)
    local generator = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), square)
    generator:setConnected(true)
    generator:setFuel(generator:getMaxFuel() * fuel)
    return generator
end

-- A record of the record kind `kind` built on its Sprites tile `tile` on `square` by its kind's
-- build (RenewableEnergyTestKinds), as the build menu builds one, clear of ground cover.
local function placeRecord(kind, tile, square)
    Harness.clearGroundCover(square)
    return require("RenewableEnergy/Debug/RenewableEnergyTestKinds").RECORDS[kind].build(square, tile)
end

-- A digester of the Sprites.digester tile `tile` ("barrel.MetalDrum", "dome", ...) built on
-- `square`. It is made a mature one at work (Fixtures.matureDigester with WORKING_DIGESTER), its
-- record's `fields` set over that, a day passed so that it eats from its hopper and says what it
-- makes a day, and its holder `full` of what it takes.
local function placeDigester(square, tile, full, fields)
    local thumpable = placeRecord("digester", tile, square)
    local record, working = Digester.recordOf(thumpable), WORKING_DIGESTER
    for _, fullType in ipairs(working.feed) do
        thumpable:getContainer():AddItem(fullType)
    end
    local state = Fixtures.matureDigester(record.tier, { gasHours = working.gasHours, temp = working.temp,
        potential = record:tierSpec().potentialCap * working.potential, sludge = working.sludge })
    for key, value in pairs(state) do
        record[key] = value
    end
    for key, value in pairs(fields or {}) do
        record[key] = value
    end
    record.lastHour = getGameTime():getWorldAgeHours() - 24
    record:update()
    record.gas = full * record:capacity()
    record:afterChange()
    return thumpable
end

-- A gasifier of `tier` built on `square`, at work (WORKING_GASIFIER), lit if `lit`.
local function placeGasifier(square, tier, lit)
    local working = WORKING_GASIFIER
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

-- Gives `player` what the materials list `list` (cf_commonlib's Materials) asks for: its skill
-- levels, each with its restore added to `restores`, and its items, each added to `given`. An item
-- counted in uses comes as one whole item.
local function giveMaterials(player, list, given, restores)
    local inventory = player:getInventory()
    for _, material in ipairs(list) do
        if material.perk then
            table.insert(restores, PZHarness.Fixtures.setPerk(player, Perks[material.perk], material.need))
        elseif material.item then
            for _ = 1, material.uses and 1 or material.need or 1 do
                table.insert(given, inventory:AddItem(material.item))
            end
        end
    end
end

-- Fits the gas kit to `generator` and runs its line to `source`, a digester or a gasifier, by
-- the jobs a player does, the character holding what they take meanwhile.
local function fitGasKit(generator, source)
    local player = getPlayer()
    local given, restores = {}, {}
    for _, job in ipairs({ GasKit.INSTALL, GasKit.CONNECT }) do
        giveMaterials(player, GasKit.materials(player, job, generator, source), given, restores)
        doJob("kit", job, generator, source)
    end
    local inventory = player:getInventory()
    for _, item in ipairs(given) do
        if item:getContainer() == inventory then
            inventory:Remove(item)
        end
    end
    for i = #restores, 1, -1 do
        restores[i]()
    end
end

-- A generator plugged in and waiting at `layout.generator` of `place`, with a gas kit on a digester
-- of the Sprites.digester tile `tile` at `layout.digester`. Returns the generator.
local function placeKittedGenerator(place, layout, tile)
    local generator = placeGenerator(Harness.at(place, layout.generator), 0.7)
    fitGasKit(generator, (placeDigester(Harness.at(place, layout.digester), tile, 1)))
    return generator
end

-- The squares wind chargers stand on, which the shots frame taller (FRAMING).
local tallSquares = {}

-- A wind charger's tile on `square`, turning in the wind as one built does.
local function placeWindCharger(square, spriteName)
    Harness.clearGroundCover(square)
    local object = Harness.placeTile(square, spriteName)
    Wind.OnCreate({ thumpable = object })
    tallSquares[square] = true
    return object
end

-- What the shots show besides the setups' places, by name, the banks buildHomestead and buildStage0
-- place among them.
local shown = {}

local function buildHomestead()
    local home = places.homestead
    quietNeighbourhood(home.bank, Harness.at(places.stage0, Places.STAGE0.box))
    clearArea(home, Places.OPEN, true)
    clearBankShot(home.bank, home.beside)
    shown.homesteadBank = placeBank(home.bank, Sprites.batteryBankMetal.S, HOMESTEAD_BANK, MORNING_CHARGE)
    placePanels(shown.homesteadBank, home, Places.HOMESTEAD.wallPanels, "wall")
    placePanels(shown.homesteadBank, home, Places.HOMESTEAD.racks, "rack", HOMESTEAD_MODULES)
    placePanels(shown.homesteadBank, home, Places.HOMESTEAD.flatPanels)
    -- A backup generator with a failsafe outside the bank's wall, plugged in and waiting, with a
    -- gas kit on the insulated digester beside it.
    local generator = placeKittedGenerator(home, Places.HOMESTEAD, "insulated")
    Harness.placeTile(generator:getSquare(), Sprites.failsafe)
    shown.homesteadCharger = placeWindCharger(Harness.at(home, Places.HOMESTEAD.windCharger), Sprites.windCharger.propeller.wood[home.frame.facing])
    connect(shown.homesteadBank, shown.homesteadCharger)
    switchOn(shown.homesteadBank)
    switchOnLights(shown.homesteadBank:getSquare(), Harness.at(places.stage0, Places.STAGE0.box))
end

local function buildStage0()
    local stage0 = places.stage0
    clearArea(stage0, Places.STAGE0.open)
    shown.stage0Box = placeBank(Harness.at(stage0, Places.STAGE0.box), Sprites.batteryBoxWood.S, STAGE0_BOX, MORNING_CHARGE)
    placePanels(shown.stage0Box, stage0, Places.STAGE0.flatPanels)
    local charger = Harness.placeTile(Harness.at(stage0, Places.STAGE0.cellCharger), Sprites.cellCharger)
    if not charger:getContainer() then
        charger:createContainersFromSpriteProperties()
    end
    for _ = 1, CELL_BATTERIES do
        local battery = charger:getContainer():AddItem(SolarCellCharger.BATTERY)
        battery:setCurrentUsesFloat(0.5)
    end
    placeGardenLight(Harness.at(stage0, Places.STAGE0.gardenLight))
    switchOn(shown.stage0Box)
end

-- Bank passes hour by hour from the morning to noon, as the game's own passes would have run,
-- then one of a minute: the window shows the sun averaged over the last pass, which would
-- otherwise be the last hour of the morning.
local function chargeThroughMorning()
    local system = PowerBank.serverSystem
    local banks = { system:getLuaObjectOnSquare(shown.homesteadBank:getSquare()), system:getLuaObjectOnSquare(shown.stage0Box:getSquare()) }
    local hours = {}
    -- The first pass only starts the clock of a bank that has never run one.
    for hour = MORNING, NOON do
        table.insert(hours, hour)
    end
    table.insert(hours, NOON + 1 / 60)
    for _, hour in ipairs(hours) do
        getGameTime():setTimeOfDay(hour)
        for _, bank in ipairs(banks) do
            bank:update()
        end
    end
end

-- How far above its floor's centre a wind charger's rotor reaches at zoom 1, in UI units: it is
-- drawn as a model about two storeys tall.
local TALL_TOP = 560

-- The framing every world shot uses: the wind chargers' squares reach TALL_TOP.
local FRAMING = {
    top = function(square)
        return tallSquares[square] and TALL_TOP or nil
    end,
}

-- What the yard shots show; the bank stands indoors behind the wall, out of them.
local function homesteadSquares()
    return Harness.squaresAt(places.homestead, { Places.HOMESTEAD.generator, Places.HOMESTEAD.player, Places.HOMESTEAD.digester, Places.HOMESTEAD.windCharger },
        Places.HOMESTEAD.wallPanels, Places.HOMESTEAD.racks, Places.HOMESTEAD.flatPanels)
end

-- What the shot of the place `name` of LAYOUTS frames: its wind chargers and its `shot` positions.
local function placeSquares(name)
    local layout, shot = Places.LAYOUTS[name], {}
    for _, key in ipairs(layout.shot) do
        table.insert(shot, layout[key])
    end
    return Harness.squaresAt(places[name], layout.chargers or {}, shot)
end

local function stage0Squares()
    return Harness.squaresAt(places.stage0, { Places.STAGE0.box, Places.STAGE0.player, Places.STAGE0.cellCharger, Places.STAGE0.gardenLight }, Places.STAGE0.flatPanels)
end


-- The menu shot: the homestead bank's right-click menu with the bank's submenu and its Wire In
-- submenu open, while the character carries these parts, and the tools, wire and scrap that
-- wiring them in takes, so that only what the bank has no room for is refused.
local MENU_ITEMS = { "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery", "Base.CarBattery1",
    "RenewableEnergy.ChargeController", "RenewableEnergy.PowerInverter", "Base.Screwdriver", "Base.Wrench",
    "Base.ElectricWire", "Base.ElectricWire", "Base.ElectricWire", "Base.ElectronicsScrap" }
local MENU_AT = 100

-- The wind every shot is taken in, as the climate's wind intensity: a fresh breeze, past every
-- charger's cut-in and below the storms that break blades.
local WIND_INTENSITY = 0.3

-- Steps ------------------------------------------------------------------------------------------

-- The items the item sheet shows: the mod's, but those that only sit in a vehicle part and the
-- annotated maps, which are loot rather than something to build with, and VANILLA_ITEMS.
local function sheetItems()
    local fullTypes = {}
    for _, fullType in ipairs(HarnessQA.itemsOfModule("RenewableEnergy")) do
        if not Debug.PART_ITEMS[fullType] and getScriptManager():getItem(fullType):getMapID() == nil then
            table.insert(fullTypes, fullType)
        end
    end
    for _, fullType in ipairs(VANILLA_ITEMS) do
        table.insert(fullTypes, fullType)
    end
    return fullTypes
end

-- Adds the step that dresses the character as the settler, or with `settler` false back in the
-- clothes it came with and empty-handed.
local function addOutfit(settler)
    Harness.addOutfit(run, getPlayer(), settler and SETTLER or OWN_CLOTHES)
end

-- Logs each bank's status as the window would read it. The promo runs single player, where the
-- banks' records are at hand; the status itself goes only to players watching a bank.
local function logBanks()
    for name, bank in pairs({ homestead = shown.homesteadBank, ["stage 0"] = shown.stage0Box }) do
        local status = PowerBank.serverSystem:getLuaObjectAt(bank:getX(), bank:getY(), bank:getZ()):buildStatus()
        local reasons, kinds = {}, {}
        for _, source in ipairs(status.sources) do
            table.insert(reasons, tostring(source.reason))
        end
        for _, kind in ipairs(status.loadByKind) do
            table.insert(kinds, string.format("%d %s %.0f W", kind.count, kind.kind, kind.watts))
        end
        print(string.format("%s %s bank: %s, %.0f W in, %.0f W load of %.0f W (%s), %.0f%% charged,"
            .. " %d of %d input slots, source reasons %s", run.mark, name, status.state, status.inW, status.loadW, status.limitW,
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
    local scouts = Harness.loadedSquares(home, Places.HOMESTEAD.scouts)
    table.insert(scouts, Harness.at(home, Places.HOMESTEAD.player))
    addOutfit(true)
    -- A step out from the closest zoom, which leaves too little of the house around the panels.
    Harness.addGoTo(run, getPlayer(), scouts, 1)
    run:addOpaque("homestead", function()
        return { Harness.centred("homestead", homesteadSquares(), FRAMING) }
    end)
    -- The banner shows the whole homestead a step further out.
    run:add(function()
        getCore():doZoomScroll(0, 1)
        return Capture.zoomSettled()
    end)
    run:addOpaque("world", function()
        return { Harness.rightAligned("world", homesteadSquares(), FRAMING) }
    end)
    -- Indoors beside the bank, where the building's near walls are cut away, at the closest zoom.
    -- The wind charger goes first: its rotor, drawn two storeys tall outside the wall, would stand
    -- over the room once the wall is cut away. The status and menu groups, which list it, come
    -- before this one in MODE_GROUPS_promo.
    run:add(function()
        local charger = shown.homesteadCharger
        charger:getSquare():transmitRemoveItemFromSquare(charger)
    end)
    Harness.addGoTo(run, getPlayer(), { home.beside }, 0)
    run:addOpaque("bank", function()
        return { Harness.cropped("bank", { home.bank, home.beside }, FRAMING) }
    end)
    -- Stage 0 is small, so it gets the closest zoom too. The character sees the panels first from
    -- among them, then from the window, early on, in the clothes it came with.
    addOutfit(false)
    Harness.addGoTo(run, getPlayer(), Harness.squaresAt(places.stage0, { Places.STAGE0.scout, Places.STAGE0.player }), 0)
    run:addOpaque("stage0", function()
        return { Harness.centred("stage0", stage0Squares(), FRAMING) }
    end)
end

-- Adds the steps that shoot `windowClass`'s window on `objectOf()` as `name` once `ready(window)`
-- holds. The character stands beside the object meanwhile, as the window closes out of its reach
-- (cf_commonlib's OpenAction.inReach).
local function addWindowShot(name, windowClass, objectOf, ready)
    Harness.addWindowShot(run, name, {
        open = function()
            return windowClass:openOn(0, objectOf())
        end,
        ready = ready,
        near = function()
            return objectOf():getSquare()
        end,
    })
end

-- The homestead bank's status window, once it has laid its rows out from the bank's status.
local function addStatus()
    addWindowShot("status", StatusWindow, function()
        return PowerBank.findOn(places.homestead.bank)
    end, function(window)
        return window.status ~= nil
    end)
end

-- The homestead bank's right-click menu, with the bank's submenu and its Wire In submenu open and
-- the first part the bank takes highlighted, while the character carries MENU_ITEMS.
local function addMenu()
    local carried = {}
    Harness.addMenuShot(run, "menu", function()
        local inventory = getPlayer():getInventory()
        for _, fullType in ipairs(MENU_ITEMS) do
            table.insert(carried, inventory:AddItem(fullType))
        end
        local context = ISWorldObjectContextMenu.createMenu(0, { shown.homesteadBank }, MENU_AT, MENU_AT)
        -- A light switch on the bank's wall adds its own option above the bank's.
        local switch = Squares.findObjectOn(shown.homesteadBank:getSquare(), function(object)
            return instanceof(object, "IsoLightSwitch")
        end)
        if switch then
            context:removeOptionByName(switch:getTileName())
        end
        local bankLabel = BankMenu.bankLabel(shown.homesteadBank)
        local wireInLabel = getText("ContextMenu_RenewableEnergy_WireIn")
        local bankMenu = Harness.openSubMenu(context, bankLabel)
        local wireIn = Harness.openSubMenu(bankMenu, wireInLabel)
        if not wireIn then
            return nil, "the bank's menu has no " .. (bankMenu and wireInLabel or bankLabel)
        end
        wireIn.mouseOver = -1
        for i, option in ipairs(wireIn.options) do
            if not option.notAvailable then
                wireIn.mouseOver = i
                break
            end
        end
        return { context, bankMenu, wireIn }
    end)
    run:add(function()
        for _, item in ipairs(carried) do
            getPlayer():getInventory():Remove(item)
        end
    end)
end

-- The arrow board trailer hitched to a car on the road, cones behind it, a step out from the
-- closest zoom.
local function addTrailer()
    local road = places.road
    local pair
    addOutfit(false)
    run:add(function()
        local carSquare = road.origin
        local x, y, z, reach = carSquare:getX(), carSquare:getY(), carSquare:getZ(), Places.ROAD.clearRadius
        removeTrees(road)
        Harness.removeVehicles(x - reach, y - reach, x + reach, y + reach, z)
        for _, spot in ipairs(Places.ROAD.cones) do
            Harness.placeTile(Harness.at(road, spot), Places.ROAD.cone)
        end
        pair = Stage.spawnTrailer(carSquare, road.frame.facing)
        return Stage.vehiclesAtRest(pair, false)
    end)
    run:add(function()
        Stage.hitchTrailer(pair, getPlayer())
        -- Its arrow lit, as work zones leave them.
        Stage.holdLampsLit(pair.trailer)
        return Stage.vehiclesAtRest(pair, true)
    end)
    -- From the item floor first, as a full run's character has by now: the hedges and fences along
    -- a road hide what lies past them from the road itself.
    Harness.addGoTo(run, getPlayer(), { Harness.at(places.studio, Harness.STUDIO.player), Harness.at(road, Places.ROAD.player) }, 1)
    run:addOpaque("trailer", function()
        -- The car's nose, the trailer, the character and the cones.
        return { Harness.centred("trailer", Harness.squaresAt(road, { { 2, 0 }, Places.ROAD.trailer, Places.ROAD.player }, Places.ROAD.cones), FRAMING) }
    end)
end

-- Garden lights along a house's front walk, charged and lit at night, at the closest zoom.
local function addGardenLights()
    local walk = places.walk
    addOutfit(false)
    run:add(function()
        removeTrees(walk)
        clearArea(walk, Places.WALK.open)
        for _, spot in ipairs(Places.WALK.lights) do
            placeGardenLight(Harness.at(walk, spot), spot.bulb)
        end
        getGameTime():setTimeOfDay(Places.WALK.hour)
        -- The lighting takes most of a second to follow the clock.
        return Harness.lightingSettled(getPlayer(), true)
    end)
    run:add(function()
        -- Lit now, rather than at the next minute's pass. Their light shows while the character
        -- looks around.
        SolarGardenLight.updateAll(0)
    end)
    Harness.addGoTo(run, getPlayer(), Harness.squaresAt(walk, { Places.WALK.scout, Places.WALK.player }), 0)
    run:addOpaque("gardenlights", function()
        return { Harness.centred("gardenlights", Harness.squaresAt(walk, { { 0, -1 }, Places.WALK.player }, Places.WALK.lights), FRAMING) }
    end)
end

-- The poster's setup: the bank indoors, full, running what it reaches, with the yard's racks, turbine
-- and kitted generator on a brick dome's gas. What stands in the band in front of the yard goes
-- down to the floor, as a clothesline or a shrub there would stand over the racks in the shot.
local function buildPoster()
    local poster = places.poster
    Harness.everyAreaSquare(poster, Places.POSTER.front, function(square)
        Harness.clearToFloor(square)
        return true
    end)
    clearArea(poster, Places.POSTER.open, true)
    local posterBank = placeBank(Harness.at(poster, Places.POSTER.bank), Sprites.batteryBankMetal.S, HOMESTEAD_BANK, 1)
    placePanels(posterBank, poster, Places.POSTER.racks, "rack")
    connect(posterBank, placeWindCharger(Harness.at(poster, Places.POSTER.windCharger), Sprites.windCharger.alternator.steel[poster.frame.facing]))
    placeKittedGenerator(poster, Places.POSTER, "dome")
    switchOn(posterBank)
end

local function addPoster()
    local poster = places.poster
    -- The settler in the yard at noon, after the garden lights' night.
    addOutfit(true)
    run:add(function()
        removeTrees(poster)
        getGameTime():setTimeOfDay(NOON)
        buildPoster()
    end)
    local scouts = Harness.loadedSquares(poster, Places.POSTER.indoors, function(square)
        return Debug.isFreeSquare(square, true)
    end)
    for _, square in ipairs(Harness.loadedSquares(poster, Places.POSTER.scouts)) do
        table.insert(scouts, square)
    end
    table.insert(scouts, Harness.at(poster, Places.POSTER.player))
    Harness.addGoTo(run, getPlayer(), scouts, Places.POSTER.zoomOut)
    -- The clock turned before the looking around, which outlasts the lighting's change.
    run:add(function()
        return Harness.lightingSettled(getPlayer())
    end)
    run:addOpaque("poster", function()
        -- The smallest square around the yard, kept on the screen.
        return { Harness.squareRegion("poster", Harness.squaresAt(places.poster, Places.POSTER.racks,
            { Places.POSTER.player, Places.POSTER.generator, Places.POSTER.digester, Places.POSTER.windCharger }), FRAMING) }
    end)
end

-- Gas, wind and treadmill shots ------------------------------------------------------------------

-- A function giving the square of the place `name` at its LAYOUTS position `key`.
local function spotsOf(name)
    local place, layout = places[name], Places.LAYOUTS[name]
    return function(key)
        return Harness.at(place, layout[key])
    end
end

-- Clears the trees around the place `name` and the ground cover of its band.
local function clearYard(name)
    removeTrees(places[name])
    clearArea(places[name], Places.LAYOUTS[name].open)
end

-- Has the character look around the place `name` from its scout square, if it has one,
-- then stand on its `standAt` square (its player square by default), `stepsOut` from the closest
-- zoom.
local function goToPlace(name, stepsOut, standAt)
    local layout = Places.LAYOUTS[name]
    local squares = { Harness.at(places[name], layout[standAt or "player"]) }
    if layout.scout then
        table.insert(squares, 1, Harness.at(places[name], layout.scout))
    end
    Harness.addGoTo(run, getPlayer(), squares, stepsOut)
end

-- The window of `windowClass` (DigesterWindow or GasifierWindow) on what the shots
-- show under `key`, which lays its rows out from the summary as it draws.
local function addGasWindow(name, windowClass, key)
    addWindowShot(name, windowClass, function()
        return shown[key]
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
        Harness.placeTile(here("heater"), Sprites.gasHeater.lit.S)
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
        return { Harness.centred("biogas", placeSquares("biogas"), FRAMING) }
    end)
    addGasWindow("digester", DigesterWindow, "digester")
end

-- The gasifiers, the lit ones piped to running generators, a step out from the closest zoom,
-- then the gasifier's window.
local function addWoodgas()
    addOutfit(true)
    run:add(function()
        local here = spotsOf("woodgas")
        clearYard("woodgas")
        placeGasifier(here("primitive"), "primitive", false)
        for _, fuel in ipairs(Places.LAYOUTS.woodgas.fuelItems) do
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
        return { Harness.centred("woodgas", placeSquares("woodgas"), FRAMING) }
    end)
    addGasWindow("gasifier", GasifierWindow, "standard")
end

-- The wind chargers turning in the breeze, a step out from the closest zoom.
local function addWind()
    addOutfit(true)
    run:add(function()
        clearYard("wind")
        for _, spot in ipairs(Places.LAYOUTS.wind.chargers) do
            placeWindCharger(Harness.at(places.wind, spot), spot.sprite)
        end
        return DRAW_FRAMES
    end)
    goToPlace("wind", 1)
    run:addOpaque("wind", function()
        return { Harness.centred("wind", placeSquares("wind"), FRAMING) }
    end)
end

-- The treadmill wired to a battery box of car batteries beside it, as stage 0's, then the
-- character running on it, indoors at the closest zoom, in the clothes it came with.
local function addTreadmill()
    local layout = Places.LAYOUTS.gym
    addOutfit(false)
    run:add(function()
        local here = spotsOf("gym")
        local box = placeBank(here("box"), Sprites.batteryBoxWood.S, STAGE0_BOX, MORNING_CHARGE)
        local tiles = Sprites.treadmill[layout.facing]
        Harness.placeTile(here("rear"), tiles.rear)
        shown.treadmill = Harness.placeTile(here("console"), tiles.console, { [Treadmill.WIRED_KEY] = true })
        connect(box, shown.treadmill)
        switchOn(box)
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
        return { Harness.centred("treadmill", placeSquares("gym"), FRAMING) }
    end)
    run:add(function()
        ISTimedActionQueue.clear(getPlayer())
        return DRAW_FRAMES
    end)
end

-- Whether this run has built both setups: the first group that needs them builds them.
local setupsBuilt

-- `add` (a group's), after both setups are built.
local function withSetups(add)
    return function(data)
        if not setupsBuilt then
            addSetups()
            setupsBuilt = true
        end
        add(data)
    end
end

-- The groups of dev/harness.conf's MODE_GROUPS_promo but the harness's `icons`: the places of
-- Places.PLACES their steps use, and what adds their steps.
local GROUPS = {
    world = { places = { "homestead", "stage0" }, add = withSetups(addWorld) },
    status = { places = { "homestead", "stage0" }, add = withSetups(addStatus) },
    menu = { places = { "homestead", "stage0" }, add = withSetups(addMenu) },
    -- The item floor is the road's asphalt.
    models = {
        places = { "road", "studio" },
        add = function(data)
            Harness.addFloorModels(run, places.studio, data.items, data.models,
                places.road.origin:getFloor():getSprite():getName())
        end,
    },
    -- The character looks around from the item floor first, as a full run's has by then.
    trailer = { places = { "road", "studio" }, add = addTrailer },
    biogas = { places = { "biogas" }, add = addBiogas },
    woodgas = { places = { "woodgas" }, add = addWoodgas },
    wind = { places = { "wind" }, add = addWind },
    treadmill = { places = { "gym" }, add = addTreadmill },
    gardenlights = { places = { "walk" }, add = addGardenLights },
    poster = { places = { "poster" }, add = addPoster },
}

--- Shoots the groups named in `selection`, comma-separated in the order to shoot them, which
--- run-client.sh gives every group of MODE_GROUPS_promo when PROMO names none, and calls onDone.
--- Every shot is taken at noon without grid power, in a breeze that turns the wind chargers.
function Promo.capture(selection, onDone)
    run, setupsBuilt = Capture.new(), false
    Harness.runGroups(run, selection, {
        groups = GROUPS,
        places = Places.PLACES,
        gap = Places.GAP,
        catalog = Capture.newCatalog({ prefer = Debug.PREFERRED_INPUTS, fluidContainers = FLUID_CONTAINERS }),
        items = sheetItems(),
        data = { models = {}, strings = { modName = getText("Sandbox_RenewableEnergy") } },
        prepare = function(_, found, origins)
            places = found
            run:add(function()
                -- The grid would power the squares and leave the bank nothing to run.
                PZHarness.Fixtures.setGrid(false)
            end)
            Harness.addWorldSettings(run, { hour = NOON, wind = WIND_INTENSITY, origins = origins })
        end,
    }, onDone)
end

return Promo
