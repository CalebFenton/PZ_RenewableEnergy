-- Development only. Builds the promo setups in the world: the banks, their parts and sources, the
-- generators, digesters, gasifiers and wind chargers, and the squares each shot frames, at the
-- places RenewableEnergyDevPromoPlaces.lua finds. RenewableEnergyDevPromo.lua shoots them.

require "PZHarness/Fixtures"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/GasLine/GasKit"
local Harness = require "PZHarness/Stage"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local Jobs = require "cf_commonlib/Jobs"
local Places = require "RenewableEnergyDevPromoPlaces"

local Scenes = {}

local Sprites = RenewableEnergy.Sprites
local PowerBank = RenewableEnergy.PowerBank

-- What the promo prints its progress under.
local MARK = "REPromo"
local HOMESTEAD, OPEN, STAGE0, LAYOUTS = Places.HOMESTEAD, Places.OPEN, Places.STAGE0, Places.LAYOUTS
local places, at, squaresAt = Places.places, Places.at, Places.squaresAt
local everyAreaSquare, eachShotSquare, isOnWall = Places.everyAreaSquare, Places.eachShotSquare, Places.isOnWall

-- The banks charge through the morning, so the window shows a day's figures at noon.
local MORNING, NOON = 8, 12

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

local STAGE0_BOX = { "Base.CarBattery1", "Base.CarBattery1", "RenewableEnergy.PlugInInverter", "Base.CarBatteryCharger" }
local CELL_BATTERIES = 4

-- A digester well into its working life: how long it has made gas, its warmth, the share of its
-- potential it holds, its sludge, and the manure waiting in its hopper.
local WORKING_DIGESTER = { ageHours = 24 * 30, temp = 32, potential = 0.6, sludge = 30,
    feed = { "Base.Dung_Cow", "Base.Dung_Cow", "Base.Dung_Pig" } }
-- A gasifier at work: wood in its hopper, its filter packed with hay, a little of it already
-- tarry, a fire going if lit, its ash pit part full and some condensate waiting.
local WORKING_GASIFIER = { wood = { "Base.Firewood", 6 },
    packing = { { "Base.HayTuft", 8 }, { "RenewableEnergy.TarryPacking", 2 } }, fireKg = 2, ash = 35, condensate = 0.8 }

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

-- What the shots show besides the setups' places, by name; buildHomestead and buildStage0 set
-- Scenes.homesteadBank and Scenes.stage0Box.
local shown = {}

local function buildHomestead()
    local home = places.homestead
    quietNeighbourhood(home.bank, at(places.stage0, STAGE0.box))
    clearArea(home, OPEN, true)
    clearBankShot(home.bank, home.beside)
    Scenes.homesteadBank = placeBank(home.bank, Sprites.batteryBankMetal.S, HOMESTEAD_BANK, MORNING_CHARGE)
    placePanels(Scenes.homesteadBank, home, HOMESTEAD.wallPanels, "wall")
    placePanels(Scenes.homesteadBank, home, HOMESTEAD.racks, "rack", HOMESTEAD_MODULES)
    placePanels(Scenes.homesteadBank, home, HOMESTEAD.flatPanels)
    -- A backup generator with a failsafe outside the bank's wall, plugged in and waiting, with a
    -- gas kit on the insulated digester beside it.
    local generator = placeKittedGenerator(home, HOMESTEAD, "insulated")
    Harness.placeTile(generator:getSquare(), Sprites.failsafe)
    shown.homesteadCharger = placeWindCharger(at(home, HOMESTEAD.windCharger), Sprites.windCharger.propeller.wood[home.frame.facing])
    connect(Scenes.homesteadBank, shown.homesteadCharger)
    setBankOn(Scenes.homesteadBank, true)
    switchOnLights(Scenes.homesteadBank:getSquare(), at(places.stage0, STAGE0.box))
end

local function buildStage0()
    local stage0 = places.stage0
    clearArea(stage0, STAGE0.open)
    Scenes.stage0Box = placeBank(at(stage0, STAGE0.box), Sprites.batteryBoxWood.S, STAGE0_BOX, MORNING_CHARGE)
    placePanels(Scenes.stage0Box, stage0, STAGE0.flatPanels)
    local charger = Harness.placeTile(at(stage0, STAGE0.cellCharger), Sprites.cellCharger)
    if not charger:getContainer() then
        charger:createContainersFromSpriteProperties()
    end
    for _ = 1, CELL_BATTERIES do
        local battery = charger:getContainer():AddItem(RenewableEnergy.SolarCellCharger.BATTERY)
        battery:setCurrentUsesFloat(0.5)
    end
    placeGardenLight(at(stage0, STAGE0.gardenLight))
    setBankOn(Scenes.stage0Box, true)
end

-- Bank passes hour by hour from the morning to noon, as the game's own passes would have run,
-- then one of a minute: the window shows the sun averaged over the last pass, which would
-- otherwise be the last hour of the morning.
local function chargeThroughMorning()
    -- Server Lua, which loads after this file.
    local BankSystem = require "RenewableEnergy/PowerBank/BankSystem"
    local system = PowerBank.serverSystem
    local banks = { system:getLuaObjectOnSquare(Scenes.homesteadBank:getSquare()), system:getLuaObjectOnSquare(Scenes.stage0Box:getSquare()) }
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

Scenes.MARK, Scenes.MORNING, Scenes.NOON, Scenes.MORNING_CHARGE = MARK, MORNING, NOON, MORNING_CHARGE
Scenes.HOMESTEAD_BANK, Scenes.STAGE0_BOX = HOMESTEAD_BANK, STAGE0_BOX
Scenes.shown, Scenes.connect, Scenes.setBankOn = shown, connect, setBankOn
Scenes.clearGroundCover, Scenes.removeTrees, Scenes.clearArea = clearGroundCover, removeTrees, clearArea
Scenes.placeBank, Scenes.placeGardenLight, Scenes.placePanels = placeBank, placeGardenLight, placePanels
Scenes.placeGenerator, Scenes.placeDigester = placeGenerator, placeDigester
Scenes.placeGasifier, Scenes.fitGasKit = placeGasifier, fitGasKit
Scenes.placeKittedGenerator, Scenes.placeWindCharger = placeKittedGenerator, placeWindCharger
Scenes.buildHomestead, Scenes.buildStage0 = buildHomestead, buildStage0
Scenes.chargeThroughMorning, Scenes.FRAMING = chargeThroughMorning, FRAMING
Scenes.homesteadSquares, Scenes.placeSquares = homesteadSquares, placeSquares
Scenes.stage0Squares = stage0Squares

return Scenes
