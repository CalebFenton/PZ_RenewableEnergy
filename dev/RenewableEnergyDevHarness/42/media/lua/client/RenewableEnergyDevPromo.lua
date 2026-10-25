-- Development only; dev/run-debug-client.sh --promo runs it instead of the tests. It builds the
-- setups near the scenario start and saves the raw art that art/promo/compose.py lays out:
-- promo_<shot>.png screenshots, and REPromo.json naming each screenshot's regions and the item,
-- recipe and skill names in the game's language.
-- PROMO=<group>,... shoots only those groups, building only the setups they need. Shots of
-- anything but the world are taken on black and on white (PZHarness/Capture.lua), and the empty
-- floor too, so that art/promo/extract.py can find each item by difference.

require "PZHarness/Fixtures"
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
local Harness = require "PZHarness/Stage"
require "PZHarness/StageLots"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local Jobs = require "cf_commonlib/Jobs"
local Squares = require "cf_commonlib/Squares"
local Places = require "RenewableEnergyDevPromoPlaces"

local Promo = {}

local Sprites = RenewableEnergy.Sprites
local PowerBank = RenewableEnergy.PowerBank

local MARK = "REPromo"
local DRAW_FRAMES = Capture.DRAW_FRAMES
local HOMESTEAD, OPEN, STAGE0, STUDIO, ROAD, WALK, POSTER, LAYOUTS = Places.HOMESTEAD, Places.OPEN, Places.STAGE0,
    Places.STUDIO, Places.ROAD, Places.WALK, Places.POSTER, Places.LAYOUTS
local places, at, squaresAt, loadedSquares = Places.places, Places.at, Places.squaresAt, Places.loadedSquares
local everyAreaSquare, eachShotSquare, isOnWall = Places.everyAreaSquare, Places.eachShotSquare, Places.isOnWall

-- The banks charge through the morning, so the window shows a day's figures at noon.
local MORNING, NOON = 8, 12
-- A recipe line that takes or fills any fluid container shows this one, by the fluid's type.
local FLUID_CONTAINERS = { Acid = "RenewableEnergy.BatteryElectrolyte", Water = "Base.WaterBottle",
    RenewableEnergy_WoodVinegar = "Base.BottleCrafted" }
-- The literature that teaches the mod's recipes, the build menu's among them.
local MAGAZINES = { "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2",
    "RenewableEnergy.HomesteadPowerMag3", "RenewableEnergy.FemaPamphlet", "RenewableEnergy.HomesteadPowerMag4" }
-- Banks take vanilla car batteries as they are, so the item sheet shows one.
local VANILLA_ITEMS = { "Base.CarBattery1" }

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

local STAGE0_BOX = { "Base.CarBattery1", "Base.CarBattery1", "RenewableEnergy.PlugInInverter", "Base.CarBatteryCharger" }
local CELL_BATTERIES = 4

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
-- A digester well into its working life: how long it has made gas, its warmth, the share of its
-- potential it holds, its sludge, and the manure waiting in its hopper.
local WORKING_DIGESTER = { ageHours = 24 * 30, temp = 32, potential = 0.6, sludge = 30,
    feed = { "Base.Dung_Cow", "Base.Dung_Cow", "Base.Dung_Pig" } }
-- A gasifier at work: wood in its hopper, its filter packed with hay, a little of it already
-- tarry, a fire going if lit, its ash pit part full and some condensate waiting.
local WORKING_GASIFIER = { wood = { "Base.Firewood", 6 },
    packing = { { "Base.HayTuft", 8 }, { "RenewableEnergy.TarryPacking", 2 } }, fireKg = 2, ash = 35, condensate = 0.8 }

-- Steps ------------------------------------------------------------------------------------------

-- The run whose steps are being added, and the item and recipe names its data holds; Promo.capture
-- makes them.
local run, catalog

-- The items the item sheet shows: the mod's, but the annotated maps, which are loot rather than
-- something to build with, and VANILLA_ITEMS.
local function sheetItems()
    local fullTypes = {}
    for _, fullType in ipairs(RenewableEnergy.Debug.ITEMS) do
        if getScriptManager():getItem(fullType):getMapID() == nil then
            table.insert(fullTypes, fullType)
        end
    end
    for _, fullType in ipairs(VANILLA_ITEMS) do
        table.insert(fullTypes, fullType)
    end
    return fullTypes
end

-- World ------------------------------------------------------------------------------------------

local function perform(name, args)
    local ok, reason = PowerBank.perform(getPlayer(), name, args)
    if not ok then
        print(MARK .. " " .. name .. " failed: " .. tostring(reason))
    end
end

local function setBankOn(bank, on)
    perform("setBankOn", { bank = PowerBank.positionOf(bank), on = on })
end

local clearGroundCover = Harness.clearGroundCover

local function removeTrees(place)
    local origin = place.origin
    Harness.removeTrees(origin:getX(), origin:getY(), origin:getZ())
end

-- Clears the ground cover off `area` of `place`, and with `fromWall` off the row along its wall
-- (out 0) too.
local function clearArea(place, area, fromWall)
    everyAreaSquare(place, area, function(square)
        clearGroundCover(square)
        return true
    end, fromWall and 0 or nil)
end

-- Sets the room in the bank shot: takes the furniture, and anything else standing on the floor,
-- off it, so that nothing stands beside the bank or in front of it or the character, and the back
-- wall's doors off their hinges, since the game draws them standing open into the room even once
-- shut. Walls, what hangs on them, light switches and windows stay.
local function clearBankShot(bank, player)
    eachShotSquare(bank, player, function(square)
        Harness.clearToFloor(square, function(object)
            return not instanceof(object, "IsoDoor") and (isOnWall(object) or instanceof(object, "IsoWindow")
                or instanceof(object, "IsoLightSwitch"))
        end)
    end)
end

-- Places a bank and puts the parts straight into its container, as world spawns stock a bank.
local function placeBank(square, sprite, items, charge)
    return RenewableEnergy.WorldSpawns.placeBankWith(square, sprite, function(container)
        for _, fullType in ipairs(items) do
            local item = container:AddItem(fullType)
            if RenewableEnergy.Battery.isBattery(item) then
                RenewableEnergy.Battery.setCharge(item, charge)
            end
        end
    end)
end

-- Set out the way garden light spawns set one out, charged and unlit by day.
local function placeGardenLight(square, bulb)
    local SolarGardenLight = RenewableEnergy.SolarGardenLight
    RenewableEnergy.WorldSpawns.placeMoveable(square, Sprites.gardenLight.off,
        { [SolarGardenLight.CHARGE_KEY] = RenewableEnergy.Specs.gardenLight.wh, [SolarGardenLight.BULB_KEY] = bulb })
end

local function connect(bank, source)
    perform("connectSource", { bank = PowerBank.positionOf(bank), source = PowerBank.positionOf(source) })
end

-- Places a panel on each of `spots` ({ along, out, material }) of `place` and connects it to
-- `bank`, in order: a `mount` ("wall" or "rack") of the spot's material facing the place's way, or
-- without one a flat panel. A mount holds the modules (a PowerBank.MODULES_KEY list) of its index in
-- `modules` if given, else whole factory modules.
local function placePanels(bank, place, spots, mount, modules)
    for i, spot in ipairs(spots) do
        local sprite = mount and Sprites[mount][spot[3]][place.frame.facing] or Sprites.flat
        local held = modules and modules[i]
        connect(bank, Harness.placeTile(at(place, spot), sprite, held and { [PowerBank.MODULES_KEY] = held } or nil))
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
    print(string.format("%s switched off %d lights and took away %d fridges", MARK, lights, fridges))
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
    print(MARK .. " switched on " .. switched .. " lights")
end

-- Gas, wind and treadmill ------------------------------------------------------------------------

-- A generator plugged in on `square` with `fuel` of a full tank.
local function placeGenerator(square, fuel)
    clearGroundCover(square)
    local generator = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), square)
    generator:setConnected(true)
    generator:setFuel(generator:getMaxFuel() * fuel)
    return generator
end

-- A record of Helpers.RECORD_KINDS kind `kind` built on its Sprites tile `tile` on `square` by
-- Helpers.placeRecord, as the build menu builds one, clear of ground cover. Helpers is server Lua,
-- which loads after this file, so it is required here.
local function placeRecord(kind, tile, square)
    clearGroundCover(square)
    local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
    local thumpable, missing = Helpers.placeRecord(kind, tile, square)
    if not thumpable then
        print(MARK .. " no " .. kind .. ": " .. tostring(missing))
    end
    return thumpable
end

-- A digester of the Sprites.digester tile `tile` ("barrel.MetalDrum", "dome", ...) built on
-- `square`. It is made one at work (WORKING_DIGESTER), its record's `fields` set over that, a day
-- passed so that it eats from its hopper and says what it makes a day, and its holder `full` of
-- what it takes.
local function placeDigester(square, tile, full, fields)
    local thumpable = placeRecord("digester", tile, square)
    local record, working = RenewableEnergy.Digester.recordOf(thumpable), WORKING_DIGESTER
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

-- A gasifier of `tier` built on `square`, at work (WORKING_GASIFIER), lit if `lit`.
local function placeGasifier(square, tier, lit)
    local Gasifier, working = RenewableEnergy.Gasifier, WORKING_GASIFIER
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
-- the jobs a player does (Jobs.perform), the character holding what they take meanwhile.
local function fitGasKit(generator, source)
    local GasKit, site = RenewableEnergy.GasKit, RenewableEnergy.GasLines.jobSite
    local player = getPlayer()
    local given, restores = {}, {}
    for _, job in ipairs({ GasKit.INSTALL, GasKit.CONNECT }) do
        giveMaterials(player, GasKit.materials(player, job, generator, source), given, restores)
        if not Jobs.perform(GasKit, site, player, job, generator, source) then
            print(MARK .. " gas kit " .. job .. " refused: " .. tostring(GasKit.refusal(player, job, generator, source)))
        end
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
    local generator = placeGenerator(at(place, layout.generator), 0.7)
    fitGasKit(generator, (placeDigester(at(place, layout.digester), tile, 1)))
    return generator
end

-- The squares wind chargers stand on, which the shots frame taller (FRAMING).
local tallSquares = {}

-- A wind charger's tile on `square`, turning in the wind as one built does.
local function placeWindCharger(square, spriteName)
    clearGroundCover(square)
    local object = Harness.placeTile(square, spriteName)
    RenewableEnergy.Wind.OnCreate({ thumpable = object })
    tallSquares[square] = true
    return object
end

-- What the shots show besides the setups' places, by name.
local shown = {}
local homesteadBank, stage0Box

local function buildHomestead()
    local home = places.homestead
    quietNeighbourhood(home.bank, at(places.stage0, STAGE0.box))
    clearArea(home, OPEN, true)
    clearBankShot(home.bank, home.beside)
    homesteadBank = placeBank(home.bank, Sprites.batteryBankMetal.S, HOMESTEAD_BANK, MORNING_CHARGE)
    placePanels(homesteadBank, home, HOMESTEAD.wallPanels, "wall")
    placePanels(homesteadBank, home, HOMESTEAD.racks, "rack", HOMESTEAD_MODULES)
    placePanels(homesteadBank, home, HOMESTEAD.flatPanels)
    -- A backup generator with a failsafe outside the bank's wall, plugged in and waiting, with a
    -- gas kit on the insulated digester beside it.
    local generator = placeKittedGenerator(home, HOMESTEAD, "insulated")
    Harness.placeTile(generator:getSquare(), Sprites.failsafe)
    shown.homesteadCharger = placeWindCharger(at(home, HOMESTEAD.windCharger), Sprites.windCharger.propeller.wood[home.frame.facing])
    connect(homesteadBank, shown.homesteadCharger)
    setBankOn(homesteadBank, true)
    switchOnLights(homesteadBank:getSquare(), at(places.stage0, STAGE0.box))
end

local function buildStage0()
    local stage0 = places.stage0
    clearArea(stage0, STAGE0.open)
    stage0Box = placeBank(at(stage0, STAGE0.box), Sprites.batteryBoxWood.S, STAGE0_BOX, MORNING_CHARGE)
    placePanels(stage0Box, stage0, STAGE0.flatPanels)
    local charger = Harness.placeTile(at(stage0, STAGE0.cellCharger), Sprites.cellCharger)
    if not charger:getContainer() then
        charger:createContainersFromSpriteProperties()
    end
    for _ = 1, CELL_BATTERIES do
        local battery = charger:getContainer():AddItem(RenewableEnergy.SolarCellCharger.BATTERY)
        battery:setCurrentUsesFloat(0.5)
    end
    placeGardenLight(at(stage0, STAGE0.gardenLight))
    setBankOn(stage0Box, true)
end

-- Bank passes hour by hour from the morning to noon, as the game's own passes would have run,
-- then one of a minute: the window shows the sun averaged over the last pass, which would
-- otherwise be the last hour of the morning.
local function chargeThroughMorning()
    -- Server Lua, which loads after this file.
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
    return squaresAt(places.homestead, { HOMESTEAD.generator, HOMESTEAD.player, HOMESTEAD.digester, HOMESTEAD.windCharger },
        HOMESTEAD.wallPanels, HOMESTEAD.racks, HOMESTEAD.flatPanels)
end

-- What the shot of the place `name` of LAYOUTS frames: its wind chargers and its `shot` positions.
local function placeSquares(name)
    local layout, shot = LAYOUTS[name], {}
    for _, key in ipairs(layout.shot) do
        table.insert(shot, layout[key])
    end
    return squaresAt(places[name], layout.chargers or {}, shot)
end

local function stage0Squares()
    return squaresAt(places.stage0, { STAGE0.box, STAGE0.player, STAGE0.cellCharger, STAGE0.gardenLight }, STAGE0.flatPanels)
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
        print(string.format("%s %s bank: %s, %.0f W in, %.0f W load of %.0f W (%s), %.0f%% charged,"
            .. " %d of %d input slots, source reasons %s", MARK, name, status.state, status.inW, status.loadW, status.limitW,
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
    Harness.addGoTo(run, getPlayer(), squaresAt(places.stage0, { STAGE0.scout, STAGE0.player }), 0)
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

-- The homestead bank's status window, which lays its rows out from the bank's status as it draws.
local function addStatus()
    addWindowShot("status", RenewableEnergy.StatusWindow, function()
        return PowerBank.findOn(places.homestead.bank)
    end, function(window)
        return (window.renderedFrames or 0) >= 2
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
        local context = ISWorldObjectContextMenu.createMenu(0, { homesteadBank }, MENU_AT, MENU_AT)
        -- A light switch on the bank's wall adds its own option above the bank's.
        local switch = Squares.findObjectOn(homesteadBank:getSquare(), function(object)
            return instanceof(object, "IsoLightSwitch")
        end)
        if switch then
            context:removeOptionByName(switch:getTileName())
        end
        local bankLabel = RenewableEnergy.Menu.bankLabel(homesteadBank)
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

-- Where extract.py looks for the item in a studio shot: STUDIO.window around the studio
-- square's floor centre, kept on the screen.
local function studioWindow(name)
    local x, y = Harness.onScreen(places.studio.origin)
    local window = STUDIO.window
    return Harness.screenRegion(name, x - window.half, y - window.up, x + window.half, y + window.down)
end

-- Every item alone on the studio floor. `models` gets one entry per item.
local function addModels(items, models)
    local group = run.current
    local studio = places.studio
    local floorSquare = studio.origin
    run:add(function()
        local asphalt = places.road.origin:getFloor():getSprite():getName()
        print(MARK .. " item floor " .. asphalt)
        everyAreaSquare(studio, STUDIO.floor, function(square)
            clearGroundCover(square)
            if Harness.isOpenGround(square) then
                square:addFloor(asphalt)
            end
            return true
        end)
        Harness.pushClosestZoom()
        -- Every item at once, so that their models load while the character looks around: Lua
        -- can't tell when a model has loaded, and a loaded one draws on the next frame.
        for _, item in ipairs(items) do
            floorSquare:AddWorldInventoryItem(instanceItem(item.fullType), 0.5, 0.5, 0)
        end
    end)
    Harness.addGoTo(run, getPlayer(), { at(studio, STUDIO.player) }, 0)
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
    run:add(Harness.popClosestZoom)
end

-- The arrow board trailer hitched to a car on the road, cones behind it, a step out from the
-- closest zoom.
local function addTrailer()
    local road = places.road
    local pair
    addOutfit(false)
    run:add(function()
        local carSquare = road.origin
        local x, y, z, reach = carSquare:getX(), carSquare:getY(), carSquare:getZ(), ROAD.clearRadius
        removeTrees(road)
        Harness.removeVehicles(x - reach, y - reach, x + reach, y + reach, z)
        for _, spot in ipairs(ROAD.cones) do
            Harness.placeTile(at(road, spot), ROAD.cone)
        end
        pair = Stage.spawnTrailer(carSquare, road.frame.facing)
        return Stage.vehiclesAtRest(pair, false)
    end)
    run:add(function()
        Stage.hitchTrailer(pair, getPlayer(), MARK)
        -- Its arrow lit, as work zones leave them.
        Stage.holdLampsLit(pair.trailer)
        return Stage.vehiclesAtRest(pair, true)
    end)
    -- From the item floor first, as a full run's character has by now: the hedges and fences along
    -- a road hide what lies past them from the road itself.
    Harness.addGoTo(run, getPlayer(), { at(places.studio, STUDIO.player), at(road, ROAD.player) }, 1)
    run:addOpaque("trailer", function()
        -- The car's nose, the trailer, the character and the cones.
        return { Harness.centred("trailer", squaresAt(road, { { 2, 0 }, ROAD.trailer, ROAD.player }, ROAD.cones), FRAMING) }
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
            placeGardenLight(at(walk, spot), spot.bulb)
        end
        getGameTime():setTimeOfDay(WALK.hour)
        -- The lighting takes most of a second to follow the clock.
        return Harness.lightingSettled(getPlayer(), true)
    end)
    run:add(function()
        -- Lit now, rather than at the next minute's pass. Their light shows while the character
        -- looks around.
        SolarGardenLight.updateAll(0)
    end)
    Harness.addGoTo(run, getPlayer(), squaresAt(walk, { WALK.scout, WALK.player }), 0)
    run:addOpaque("gardenlights", function()
        return { Harness.centred("gardenlights", squaresAt(walk, { { 0, -1 }, WALK.player }, WALK.lights), FRAMING) }
    end)
end

-- The poster's setup: the bank indoors, full, running what it reaches, with the yard's racks, turbine
-- and kitted generator on a brick dome's gas. What stands in the band in front of the yard goes
-- down to the floor, as a clothesline or a shrub there would stand over the racks in the shot.
local function buildPoster()
    local poster = places.poster
    everyAreaSquare(poster, POSTER.front, function(square)
        Harness.clearToFloor(square)
        return true
    end)
    clearArea(poster, POSTER.open, true)
    local posterBank = placeBank(at(poster, POSTER.bank), Sprites.batteryBankMetal.S, HOMESTEAD_BANK, 1)
    placePanels(posterBank, poster, POSTER.racks, "rack")
    connect(posterBank, placeWindCharger(at(poster, POSTER.windCharger), Sprites.windCharger.alternator.steel[poster.frame.facing]))
    placeKittedGenerator(poster, POSTER, "dome")
    setBankOn(posterBank, true)
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
    local scouts = loadedSquares(poster, POSTER.indoors, function(square)
        return RenewableEnergy.Debug.isFreeSquare(square, true)
    end)
    for _, square in ipairs(loadedSquares(poster, POSTER.scouts)) do
        table.insert(scouts, square)
    end
    table.insert(scouts, at(poster, POSTER.player))
    Harness.addGoTo(run, getPlayer(), scouts, POSTER.zoomOut)
    -- The clock turned before the looking around, which outlasts the lighting's change.
    run:add(function()
        return Harness.lightingSettled(getPlayer())
    end)
    run:addOpaque("poster", function()
        -- The smallest square around the yard, kept on the screen.
        return { Harness.squareRegion("poster", squaresAt(places.poster, POSTER.racks,
            { POSTER.player, POSTER.generator, POSTER.digester, POSTER.windCharger }), FRAMING) }
    end)
end

-- Gas, wind and treadmill shots ------------------------------------------------------------------

-- A function giving the square of the place `name` at its LAYOUTS position `key`.
local function spotsOf(name)
    local place, layout = places[name], LAYOUTS[name]
    return function(key)
        return at(place, layout[key])
    end
end

-- Clears the trees around the place `name` and the ground cover of its band.
local function clearYard(name)
    removeTrees(places[name])
    clearArea(places[name], LAYOUTS[name].open)
end

-- Has the character look around the place `name` from its scout square, if it has one,
-- then stand on its `standAt` square (its player square by default), `stepsOut` from the closest
-- zoom.
local function goToPlace(name, stepsOut, standAt)
    local layout = LAYOUTS[name]
    local squares = { at(places[name], layout[standAt or "player"]) }
    if layout.scout then
        table.insert(squares, 1, at(places[name], layout.scout))
    end
    Harness.addGoTo(run, getPlayer(), squares, stepsOut)
end

-- The window of `windowClass` (RenewableEnergy.DigesterWindow or GasifierWindow) on what the shots
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
        for _, fuel in ipairs(LAYOUTS.woodgas.fuelItems) do
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
    addGasWindow("gasifier", RenewableEnergy.GasifierWindow, "standard")
end

-- The wind chargers turning in the breeze, a step out from the closest zoom.
local function addWind()
    addOutfit(true)
    run:add(function()
        clearYard("wind")
        for _, spot in ipairs(LAYOUTS.wind.chargers) do
            placeWindCharger(at(places.wind, spot), spot.sprite)
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
    local layout = LAYOUTS.gym
    addOutfit(false)
    run:add(function()
        local here = spotsOf("gym")
        local box = placeBank(here("box"), Sprites.batteryBoxWood.S, STAGE0_BOX, MORNING_CHARGE)
        local tiles = Sprites.treadmill[layout.facing]
        Harness.placeTile(here("rear"), tiles.rear)
        shown.treadmill = Harness.placeTile(here("console"), tiles.console, { [RenewableEnergy.Treadmill.WIRED_KEY] = true })
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
        return { Harness.centred("treadmill", placeSquares("gym"), FRAMING) }
    end)
    run:add(function()
        ISTimedActionQueue.clear(getPlayer())
        return DRAW_FRAMES
    end)
end

-- The groups of dev/harness.conf's MODE_GROUPS_promo: the places of Places.find their steps use,
-- whether they need both setups built, and what adds their steps. A run looks only for its groups'
-- places, so that one group can't fail for want of a place another needs.
local GROUPS = {
    world = { places = { "homestead", "stage0" }, setups = true, add = addWorld },
    status = { places = { "homestead", "stage0" }, setups = true, add = addStatus },
    menu = { places = { "homestead", "stage0" }, setups = true, add = addMenu },
    icons = { places = {}, add = function() run:addIconSheet("icons", catalog:iconList()) end },
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

-- Finds the places `chosen` groups need and adds the step that sets the world every shot is taken
-- in: noon without grid power, a breeze that turns the wind chargers, and no radio captions around
-- the places. Returns nil, or what it couldn't find.
local function prepare(chosen)
    local needs = Harness.groupNeeds(GROUPS, chosen, "places")
    local origins, missing = Places.find(getPlayer(), needs, MARK)
    if not origins then
        return "within " .. Harness.SEARCH_RADIUS .. " squares, no " .. missing
    end
    run:add(function()
        -- The grid would power the squares and leave the bank nothing to run.
        PZHarness.Fixtures.setGrid(false)
    end)
    Harness.addWorldSettings(run, { hour = NOON, wind = WIND_INTENSITY, origins = origins })
end

--- Shoots the groups named in `selection`, comma-separated in the order to shoot them, which
--- run-client.sh gives every group of MODE_GROUPS_promo when PROMO names none, and calls onDone.
function Promo.capture(selection, onDone)
    run = Capture.new(MARK)
    catalog = Capture.newCatalog({ prefer = RenewableEnergy.Debug.PREFERRED_INPUTS, fluidContainers = FLUID_CONTAINERS,
        literature = MAGAZINES })
    -- The names come with every run, since they cost no shot.
    local data = {
        items = catalog:items(sheetItems()),
        recipes = catalog:recipes(),
        models = {},
        strings = { modName = getText("Sandbox_RenewableEnergy") },
    }
    -- The first group that needs the setups builds them.
    local adders, setupsBuilt = {}, false
    for name, group in pairs(GROUPS) do
        adders[name] = function()
            if group.setups and not setupsBuilt then
                addSetups()
                setupsBuilt = true
            end
            group.add(data)
        end
    end
    Harness.runGroups(run, selection, adders, prepare, data, onDone)
end

return Promo
