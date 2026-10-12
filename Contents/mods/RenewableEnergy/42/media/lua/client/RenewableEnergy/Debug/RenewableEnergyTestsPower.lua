require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/PowerBank"

-- Server Lua loads after client Lua, so a server file can only be required once the game
-- runs, when require hands back the loaded file's table.
local function Loads()
    return require "RenewableEnergy/PowerBank/Loads"
end

local function Bank()
    return require "RenewableEnergy/PowerBank/Bank"
end

-- Power tests: the sun model against measured insolation, and banks charging, powering,
-- cutting out, wiring parts in and wearing. Single player runs the server's bank system in the
-- same Lua state, so the tests drive banks through the same perform() and OnClientCommand a
-- server runs, and check what reaches the client's copy. See RenewableEnergyTestLib.lua for how
-- the runner works.

local test, expect, expectNear, player = RenewableEnergyTest.test, RenewableEnergyTest.expect,
    RenewableEnergyTest.expectNear, RenewableEnergyTest.player
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local Battery, Wear, PowerBank = RenewableEnergy.Battery, RenewableEnergy.Wear, RenewableEnergy.PowerBank

local FRIDGE = "appliances_refrigeration_01_0"
local MINI_FRIDGE = "appliances_refrigeration_01_25"
local CLEAR = Sun.CLEAR_WEATHER

-- Sun ------------------------------------------------------------------------------------

-- Light on each mount summed over a year at latitude 38, with a mix of clear, broken and
-- overcast days standing in for Kentucky's weather.
local function yearTotals(months)
    local mix = { { 0.4, 0 }, { 0.3, 0.5 }, { 0.3, 1 } }
    local mounts = { flat = { "flat" }, rack = { "rack", "S" }, wall = { "wall", "S" } }
    local totals = { flat = 0, rack = 0, wall = 0 }
    local step = 0.25
    for day = 1, 365 do
        local month = math.min(12, math.floor((day - 1) / 30.42) + 1)
        if not months or months[month] then
            for hour = -12, 12 - step, step do
                local sun = Sun.position(day, hour, 38)
                for name, mount in pairs(mounts) do
                    for _, part in ipairs(mix) do
                        local weather = { cloud = part[2], fog = 0, rain = 0, snowing = false, groundSnow = 0 }
                        totals[name] = totals[name] + part[1] * Sun.planeIrradiance(sun, mount[1], mount[2], weather) * step
                    end
                end
            end
        end
    end
    return totals
end

-- Over a year, a flat panel and a south wall make what Louisville's measured insolation says
-- they make against a 38° rack (design §2.2: 4.11 and 2.96 against 4.59 kWh/m²/day), and the
-- wall beats the flat panel in December.
test("renewable_energy_power_sun_year_matches_measured_insolation", {
    run = function(self)
        self.year = yearTotals(nil)
        self.december = yearTotals({ [12] = true })
    end,
    validate = function(self)
        local year, december = self.year, self.december
        expectNear("flat / rack over a year", year.flat / year.rack, 0.90, 0.04)
        expectNear("south wall / rack over a year", year.wall / year.rack, 0.64, 0.04)
        expectNear("rack kWh/m² a day in clear-to-overcast weather", year.rack / 365 / 1000, 4.6, 0.8)
        expect(december.wall > december.flat, "a south wall makes less than a flat panel in December")
    end,
})

-- The sun stands at 90 - 38 + 23.44 degrees at noon on the June solstice, sits on the horizon
-- at the end of the half day, and makes nothing at night. The game's own dawn is sunrise.
test("renewable_energy_power_sun_noon_dawn_night", {
    run = function(self)
        local solstice = 172
        self.noon = math.deg(math.asin(Sun.position(solstice, 0, 38).up))
        local halfDay = Sun.halfDayHours(solstice, 38)
        self.sunset = Sun.position(solstice, halfDay, 38).up
        self.night = Sun.planeIrradiance(Sun.position(solstice, 12, 38), "flat", nil, CLEAR)
        local season = getClimateManager():getSeason()
        local hoursSinceDawn = getGameTime():getTimeOfDay() - season:getDawn()
        self.dawn = Sun.positionNow(hoursSinceDawn).up
        self.noonWatts = Sun.planeIrradiance(Sun.position(solstice, 0, 38), "flat", nil, CLEAR)
    end,
    validate = function(self)
        expectNear("noon elevation on the solstice", self.noon, 75.44, 0.1)
        expectNear("sun height at sunset", self.sunset, 0, 0.001)
        expectNear("light at midnight", self.night, 0, 0)
        expectNear("sun height at the game's dawn", self.dawn, 0, 0.01)
        expect(self.noonWatts > 900 and self.noonWatts < 1000, "noon light on a flat panel is " .. self.noonWatts .. " W/m²")
    end,
})

-- Overcast leaves a quarter of the light, all of it diffuse, so it costs a tilted rack less.
test("renewable_energy_power_sun_clouds", {
    run = function(self)
        local sun = Sun.position(172, 0, 38)
        local overcast = { cloud = 1, fog = 0, rain = 0, snowing = false, groundSnow = 0 }
        self.flat = Sun.planeIrradiance(sun, "flat", nil, overcast) / Sun.planeIrradiance(sun, "flat", nil, CLEAR)
        self.rack = Sun.planeIrradiance(sun, "rack", "S", overcast) / Sun.planeIrradiance(sun, "rack", "S", CLEAR)
    end,
    validate = function(self)
        expectNear("overcast / clear on a flat panel", self.flat, 0.25, 0.005)
        expect(self.rack < self.flat, "clouds cost a rack less than a flat panel")
    end,
})

-- The Sunlight Multiplier scales what a panel makes, snow on it blocks it, and a roof over a
-- square leaves a garden light's cell nothing.
test("renewable_energy_power_sunlight_multiplier_and_snow", {
    sandbox = { SunlightMultiplier = 1 },
    run = function(self)
        self.real = Sun.wattsFrom(50, 1000, 0)
        SandboxVars.RenewableEnergy.SunlightMultiplier = 3
        self.boosted = Sun.wattsFrom(50, 1000, 0)
        self.snowed = Sun.wattsFrom(50, 1000, 1)
        self.indoors = Sun.squareWatts(nil, 50)
    end,
    validate = function(self)
        -- 50 W at full sun less 20% system losses.
        expectNear("a 50 W module at 1000 W/m² and x1", self.real, 40, 0.01)
        expectNear("the same at x3", self.boosted, 120, 0.01)
        expectNear("the same under snow", self.snowed, 0, 0)
        expectNear("a cell with no square", self.indoors, 0, 0)
    end,
})

-- Batteries ------------------------------------------------------------------------------

test("renewable_energy_power_battery_wear", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        local deepCycle = Specs.batteries["RenewableEnergy.DeepCycleBattery"]
        self.deepAt80 = 1 / Battery.cycleWear(deepCycle, 0.8)
        local battery = instanceItem("Base.CarBattery1")
        if not battery then return end
        local car = Specs.batteries["Base.CarBattery1"]
        -- Four days at 50%: 1.25 points a day for a car battery's 80 cycles.
        for _ = 1, 4 do
            Battery.wear(battery, Battery.cycleWear(car, 0.5))
        end
        self.condition = battery:getCondition()
        -- A repair starts afresh: the quarter point still pending is forgotten.
        Battery.wear(battery, Battery.cycleWear(car, 0.5) * 0.6)
        Wear.setCondition(battery, 60)
        Battery.wear(battery, Battery.cycleWear(car, 0.5) * 0.6)
        self.repaired = battery:getCondition()
    end,
    validate = function(self)
        expect(self.deepAt80 > 300 and self.deepAt80 < 450, "a deep-cycle battery lasts " .. tostring(self.deepAt80) .. " cycles at 80%")
        expectNear("car battery condition after four 50% days", self.condition, 95, 0)
        expectNear("condition after a repair and less than a point of wear", self.repaired, 60, 0)
    end,
})

-- Banks in the world ---------------------------------------------------------------------

local function system()
    return PowerBank.serverSystem
end

local function position(object)
    return { x = object:getX(), y = object:getY(), z = object:getZ() }
end

local function hasContainerOrGenerator(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object:getContainer() or instanceof(object, "IsoGenerator") or PowerBank.sourceKind(object) then
            return true
        end
    end
    return false
end

-- Free squares around `center` (the character's square by default), nearest first: indoors
-- where a bank may stand, or outdoors.
local function freeSquares(self, count, indoors, center)
    self.used = self.used or {}
    local found = {}
    center = center or player():getCurrentSquare()
    if not center then return found end
    for radius = 1, 30 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local square = math.max(math.abs(dx), math.abs(dy)) == radius
                    and getCell():getGridSquare(center:getX() + dx, center:getY() + dy, center:getZ())
                if #found < count and square and not self.used[square] and square:isFree(false)
                    and not square:getVehicleContainer() and PowerBank.canPlaceBank(square) == indoors
                    and (indoors or square:isOutside()) and not hasContainerOrGenerator(square) then
                    self.used[square] = true
                    table.insert(found, square)
                end
            end
        end
    end
    return found
end

-- Every object a test placed, removed again the way the game does so the mod's removal handler
-- runs; nothing else on the squares is touched.
local function placed(self, object)
    self.placed = self.placed or {}
    table.insert(self.placed, object)
    return object
end

local function removePlaced(self)
    for i = #(self.placed or {}), 1, -1 do
        local object = self.placed[i]
        if object:getObjectIndex() ~= -1 then
            if instanceof(object, "IsoGenerator") and object:isActivated() then
                object:setActivated(false)
            end
            object:getSquare():transmitRemoveItemFromSquare(object)
        end
    end
    self.placed = {}
end

-- The scenario starts with the grid on, which powers squares without a generator.
local function setGrid(self, on)
    local option = getSandboxOptions():getOptionByName("ElecShutModifier")
    if not self.savedGrid then
        self.savedGrid = { hydro = getWorld():isHydroPowerOn(), shut = option and option:getValue() }
    end
    if option then option:setValue(on and 100000 or -1) end
    getWorld():setHydroPowerOn(on)
end

local function restoreGrid(self)
    local saved = self.savedGrid
    if not saved then return end
    local option = getSandboxOptions():getOptionByName("ElecShutModifier")
    if option and saved.shut then option:setValue(saved.shut) end
    getWorld():setHydroPowerOn(saved.hydro)
    self.savedGrid = nil
end

--- A bank of Sprites field `kind` on a free square (indoors unless `outdoors`) holding
--- `items` (full types), its batteries charged to `charge`. Returns the generator and the
--- bank's global object.
local function newBank(self, kind, items, charge, outdoors)
    local square = freeSquares(self, 1, not outdoors)[1]
    if not square then return nil end
    local generator = placed(self, PowerBank.place(square, Sprites[kind], -1))
    local container = generator and generator:getContainer()
    if not container then return generator, nil end
    for _, fullType in ipairs(items) do
        local item = container:AddItem(fullType)
        if item and Battery.isBattery(item) then
            Battery.setCharge(item, charge or 1)
        end
    end
    PowerBank.perform(nil, "refresh", { bank = position(generator) })
    return generator, system():getLuaObjectOnSquare(square)
end

--- A placed panel tile on a free outdoor square near `bankObject`, holding `modules`
--- ({ { type, condition } }) if given.
local function newPanel(self, spriteName, bankObject, modules)
    local square = freeSquares(self, 1, false, bankObject and bankObject:getSquare())[1]
    if not square then return nil end
    local panel = placed(self, IsoObject.new(square, spriteName, "Solar", false))
    if modules then
        panel:getModData()[PowerBank.MODULES] = modules
    end
    square:AddTileObject(panel)
    return panel
end

local function connect(bankObject, panel)
    return PowerBank.perform(player(), "connectSource", { bank = position(bankObject), source = position(panel) })
end

local function cleanup(self)
    removePlaced(self)
    restoreGrid(self)
end

-- A pass with the weather fixed: `light` W/m² on every mount, clear, 25 °C, no snow or storm.
local function passContext(light, stormHours)
    local function irradiance() return light end
    return {
        weather = CLEAR, precipitation = 0, airC = 25, elevation = light > 0 and 45 or -10,
        stormHours = stormHours or 0, irradiance = irradiance, clearIrradiance = irradiance,
    }
end

local function loadOf(names)
    local load = Loads().new()
    for _, name in ipairs(names) do
        Loads().add(load, name)
    end
    return load
end

-- The measured load replaced by `names`, as if the scan had found them, and the bank's
-- reaction to it.
local function applyLoad(bank, names)
    local load = loadOf(names)
    bank.loadW, bank.averageLoadW, bank.loadByKind = load.watts, load.averageWatts, Loads().byKind(load)
    bank:checkOverload()
    bank:switchGenerator()
end

-- A placed bank is a registered generator whose container refuses every transfer: parts go in
-- only by being wired in.
test("renewable_energy_power_bank_refuses_transfers", {
    run = function(self)
        local box = newBank(self, "batteryBoxWood", {})
        if not box then return end
        self.registered = system():getLuaObjectOnSquare(box:getSquare()) ~= nil and PowerBank.isBank(box)
        local battery = instanceItem("Base.CarBattery1")
        self.allowsBattery = battery ~= nil and box:getContainer():isItemAllowed(battery)
        self.powered = box:isActivated()
    end,
    validate = function(self)
        if not expect(self.registered ~= nil, "no indoor square for a bank, or place() made none") then return end
        expect(self.registered, "the bank system did not register the placed bank")
        expect(not self.allowsBattery, "a battery can be dropped into a bank without wiring it in")
        expect(not self.powered, "a bank that was never switched on powers its area")
    end,
    cleanup = cleanup,
})

-- Banks stand indoors only: placement is refused outdoors, and a bank found outdoors won't
-- switch on.
test("renewable_energy_power_bank_refused_outdoors", {
    run = function(self)
        setGrid(self, false)
        local indoor = freeSquares(self, 1, true)[1]
        local outdoor = freeSquares(self, 1, false)[1]
        if not (indoor and outdoor) then return end
        self.indoorOk = PowerBank.canPlaceBank(indoor)
        self.outdoorOk, self.reason = PowerBank.canPlaceBank(outdoor)
        local generator, bank = newBank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 1, true)
        if not bank then return end
        PowerBank.perform(player(), "setBankOn", { bank = position(generator), on = true })
        self.outdoorPowered = generator:isActivated()
        self.state = bank.status.state
    end,
    validate = function(self)
        if not expect(self.indoorOk ~= nil, "no indoor and outdoor squares near the character") then return end
        expect(self.indoorOk, "a bank is refused inside a building")
        expect(not self.outdoorOk and self.reason == "Tooltip_RenewableEnergy_BankIndoorsOnly",
            "a bank may stand outdoors (reason " .. tostring(self.reason) .. ")")
        expect(not self.outdoorPowered and self.state == "outdoors", "a bank outdoors switched on (state " .. tostring(self.state) .. ")")
    end,
    cleanup = cleanup,
})

-- Every bank tile switches with a click, not a gas generator's pull-start and shutdown: the
-- generator plays its tile's GeneratorSound prefix + Starting or Stopping.
test("renewable_energy_power_bank_switch_sounds", {
    validate = function()
        for _, kind in ipairs({ "batteryBoxWood", "batteryBoxMetal", "batteryRackWood", "batteryRackMetal", "batteryBankWood", "batteryBankMetal" }) do
            local sprite = getSprite(Sprites[kind])
            local prefix = sprite and sprite:getProperties():get("GeneratorSound")
            if expect(prefix ~= nil, kind .. " has no GeneratorSound and plays the gas generator's") then
                for _, suffix in ipairs({ "Starting", "Stopping" }) do
                    expect(GameSounds.isKnownSound(prefix .. suffix), kind .. "'s sound " .. prefix .. suffix .. " is not defined")
                end
            end
        end
    end,
})

-- Noon on a connected panel charges the bank by what the panel makes, and the batteries carry
-- the charge.
test("renewable_energy_power_panel_charges_bank", {
    run = function(self)
        local generator, bank = newBank(self, "batteryBoxWood", { "Base.CarBattery1" }, 0.5)
        local panel = generator and newPanel(self, Sprites.flat, generator)
        if not (bank and panel) then return end
        self.connected = connect(generator, panel)
        local before = bank.charge * bank.nominalWh
        bank:update(1, passContext(1000))
        self.gained = bank.charge * bank.nominalWh - before
        self.solarW = bank.status.solarW
        self.fullSun = bank.status.sources[1] and bank.status.sources[1].fullSunPct
        local battery = generator:getContainer():getFirstType("Base.CarBattery1")
        self.batteryCharge = battery and Battery.getCharge(battery)
        self.bankCharge = bank.charge
        self.source = PowerBank.bankOfSource(panel:getX(), panel:getY(), panel:getZ())
    end,
    validate = function(self)
        if not expect(self.connected, "connecting the panel failed") then return end
        -- One whole 50 W module at x3 (the default) in full sun.
        expectNear("solar watts", self.solarW, 120, 0.5)
        expectNear("Wh gained in an hour", self.gained, self.solarW, 0.5)
        expectNear("percent of full sun", self.fullSun, 100, 0)
        expectNear("the battery's charge", self.batteryCharge, self.bankCharge, 0.001)
        expect(self.source ~= nil, "bankOfSource doesn't know the panel")
    end,
    cleanup = cleanup,
})

-- A module makes its rating times its condition: a cracked module less, a homemade one at its
-- best 60%, a rack the sum of its two. The cracked panel says why it is low.
test("renewable_energy_power_module_condition_sets_watts", {
    run = function(self)
        local generator, bank = newBank(self, "batteryRackMetal", { "Base.CarBattery1", "RenewableEnergy.ChargeController" }, 0.1)
        if not bank then return end
        local cracked = newPanel(self, Sprites.flat, generator, { { type = "RenewableEnergy.SolarModule", condition = 50 } })
        local homemade = newPanel(self, Sprites.flat, generator, { { type = "RenewableEnergy.HomemadeSolarModule", condition = 60 } })
        local rack = newPanel(self, Sprites.rack.metal.S, generator, {
            { type = "RenewableEnergy.SolarModule", condition = 100 }, { type = "RenewableEnergy.SolarModule", condition = 0 },
        })
        if not (cracked and homemade and rack) then return end
        self.connected = connect(generator, cracked) and connect(generator, homemade) and connect(generator, rack)
        bank:update(1, passContext(1000))
        local sources = bank.status.sources
        self.cracked, self.homemade, self.rack = sources[1], sources[2], sources[3]
    end,
    validate = function(self)
        if not expect(self.connected, "no bank and panels, or connecting them failed") then return end
        if not expect(self.cracked and self.homemade and self.rack, "the status lists fewer than three panels") then return end
        expectNear("a module at condition 50", self.cracked.watts, 60, 0.5)
        expectNear("a homemade module at 60", self.homemade.watts, 72, 0.5)
        expectNear("a rack with a whole and a shattered module", self.rack.watts, 120, 0.5)
        expect(self.cracked.reason == "cracked", "the half-cracked panel's reason is " .. tostring(self.cracked.reason))
        expect(self.cracked.modules[1] and self.cracked.modules[1].condition == 50, "the status lost the module's condition")
    end,
    cleanup = cleanup,
})

-- A bank takes two panels with no controller and seven more per controller; a third panel is
-- refused, and panels past the slots of a controller taken out stay wired but make nothing.
test("renewable_energy_power_panel_slots", {
    run = function(self)
        local box = newBank(self, "batteryBoxWood", { "Base.CarBattery1" }, 0.1)
        local rackGenerator, rack = newBank(self, "batteryRackWood", { "Base.CarBattery1", "RenewableEnergy.ChargeController" }, 0.1)
        if not (box and rack) then return end
        self.box = {}
        for i = 1, 3 do
            local panel = newPanel(self, Sprites.flat, box)
            if panel then
                self.box[i], self.boxReason = connect(box, panel)
            end
        end
        local wired = 0
        for _ = 1, 3 do
            local panel = newPanel(self, Sprites.flat, rackGenerator)
            if panel and connect(rackGenerator, panel) then
                wired = wired + 1
            end
        end
        self.rackWired = wired
        local container = rackGenerator:getContainer()
        container:Remove(container:getFirstType(Specs.controller))
        rack:update(1, passContext(1000))
        local sources = rack.status.sources
        self.slots = rack.status.panelSlots
        self.third = sources[3]
        self.second = sources[2]
    end,
    validate = function(self)
        if not expect(self.box, "no room for two banks") then return end
        expect(self.box[1] and self.box[2], "a battery box refused its first two panels")
        expect(not self.box[3] and self.boxReason == "Tooltip_RenewableEnergy_NoPanelSlot",
            "a battery box took a third panel without a controller (" .. tostring(self.boxReason) .. ")")
        expectNear("panels a rack with a controller took", self.rackWired, 3, 0)
        if not expect(self.third ~= nil, "the third panel was unwired when the controller left") then return end
        expect(self.slots.used == 3 and self.slots.total == Specs.freePanels, "panel slots read " .. self.slots.used .. " of " .. self.slots.total)
        expect(self.third.watts == 0 and self.third.reason == "noController",
            "a panel past the slots makes " .. self.third.watts .. " W, reason " .. tostring(self.third.reason))
        expect(self.second.watts > 0, "a panel within the free slots stopped making power")
    end,
    cleanup = cleanup,
})

-- The bank's limit is its working inverters' ratings together. A Plug-in Inverter runs a TV and
-- a lamp, or a mini fridge, but not a full fridge.
test("renewable_energy_power_inverter_limits", {
    run = function(self)
        local _, box = newBank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 1)
        local generator, bank = newBank(self, "batteryBankWood",
            { "Base.CarBattery1", "RenewableEnergy.PowerInverter", "RenewableEnergy.PowerInverter" }, 1)
        if not (box and bank) then return end
        local limit = box:limitW()
        local function fits(names)
            return loadOf(names).watts <= limit
        end
        self.tvAndLamp = fits({ "television", "light" })
        self.miniFridge = fits({ "miniFridge" })
        self.fridge = fits({ "fridge" })
        self.fridgeFreezer = fits({ "fridgeFreezer" })
        self.twoInverters = bank:limitW()
        local broken = generator:getContainer():getFirstType("RenewableEnergy.PowerInverter")
        Wear.setCondition(broken, 0)
        bank:recount()
        self.oneWorking = bank:limitW()
    end,
    validate = function(self)
        if not expect(self.tvAndLamp ~= nil, "no room for two banks") then return end
        expect(self.tvAndLamp, "a Plug-in Inverter can't run a TV and a lamp")
        expect(self.miniFridge, "a Plug-in Inverter can't run a mini fridge")
        expect(not self.fridge and not self.fridgeFreezer, "a Plug-in Inverter runs a full fridge")
        expectNear("limit of two 600 W inverters", self.twoInverters, 1200, 0)
        expectNear("limit with one of them broken", self.oneWorking, 600, 0)
    end,
    cleanup = cleanup,
})

-- A load beyond the inverters cuts the bank's power, and the power comes back by itself once
-- the load fits again.
test("renewable_energy_power_overload_cuts_and_returns", {
    run = function(self)
        setGrid(self, false)
        local generator, bank = newBank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 1)
        if not bank then return end
        PowerBank.perform(player(), "setBankOn", { bank = position(generator), on = true })
        applyLoad(bank, { "television", "light" })
        self.fitting = generator:isActivated()
        applyLoad(bank, { "television", "light", "fridge" })
        bank:sendStatus()
        self.cut = not generator:isActivated()
        self.status = bank.status
        applyLoad(bank, { "television" })
        self.back = generator:isActivated() and not bank.overloaded
    end,
    validate = function(self)
        if not expect(self.fitting ~= nil, "no indoor square for a bank") then return end
        expect(self.fitting, "a TV and a lamp didn't run on a charged bank with a Plug-in Inverter")
        expect(self.cut, "a fridge on top of them didn't cut the power")
        local status = self.status
        expect(status.overloaded and status.state == "overloaded", "the status doesn't read overloaded (state " .. tostring(status.state) .. ")")
        expectNear("load in the status", status.loadW, Specs.loads.television.watts + Specs.loads.light.watts + Specs.loads.fridge.watts, 0)
        expectNear("limit in the status", status.limitW, Specs.inverters["RenewableEnergy.PlugInInverter"].watts, 0)
        expect(self.back, "the power didn't come back once the load fit")
    end,
    cleanup = cleanup,
})

-- The scan sees what is switched on whether or not the bank powers it, so a cut bank knows when
-- the load fits again; and it tells a mini fridge from a full one.
test("renewable_energy_power_scan_sees_load_while_cut", {
    run = function(self)
        setGrid(self, false)
        local generator, bank = newBank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 1)
        if not bank then return end
        self.without = Loads().scan(generator:getSquare())
        local squares = freeSquares(self, 2, true, generator:getSquare())
        if #squares < 2 then return end
        local fridge = placed(self, IsoObject.new(squares[1], FRIDGE, "Fridge", false))
        squares[1]:AddTileObject(fridge)
        local mini = placed(self, IsoObject.new(squares[2], MINI_FRIDGE, "Fridge", false))
        squares[2]:AddTileObject(mini)
        self.unpowered = not generator:isActivated()
        self.with = Loads().scan(generator:getSquare())
    end,
    validate = function(self)
        if not expect(self.with ~= nil, "no bank or free squares for the fridges") then return end
        expect(self.unpowered, "the bank was on while scanning")
        local function count(load, kind)
            return load.kinds[kind] and load.kinds[kind].count or 0
        end
        expectNear("fridge-freezers found", count(self.with, "fridgeFreezer") - count(self.without, "fridgeFreezer"), 1, 0)
        expectNear("mini fridges found", count(self.with, "miniFridge") - count(self.without, "miniFridge"), 1, 0)
        expectNear("watts added", self.with.watts - self.without.watts, Specs.loads.fridgeFreezer.watts + Specs.loads.miniFridge.watts, 0)
    end,
    cleanup = cleanup,
})

-- A generator within `reach` tiles of `near`, outdoors if it can be, since a running one makes
-- a building toxic, with a failsafe beside it if asked.
local function newGenerator(self, near, running, failsafe, reach)
    local square
    for _, indoors in ipairs({ false, true }) do
        local candidate = square == nil and freeSquares(self, 1, indoors, near)[1]
        if candidate and IsoUtils.DistanceToSquared(candidate:getX(), candidate:getY(), near:getX(), near:getY()) <= reach * reach then
            square = candidate
        end
    end
    if not square then return nil end
    local item = instanceItem("Base.Generator")
    local generator = item and IsoGenerator.new(item, square:getCell(), square)
    if not generator then return nil end
    placed(self, generator)
    generator:setConnected(true)
    generator:setFuel(10)
    generator:setCondition(100)
    if failsafe then
        square:AddTileObject(placed(self, IsoObject.new(square, Sprites.failsafe, "Failsafe", false)))
    end
    if running then
        generator:setActivated(true)
    end
    return generator
end

-- Chargers charge only from the grid or a running generator other than a bank, which burns fuel
-- for them; never from the bank's own power.
test("renewable_energy_power_charger_sources", {
    run = function(self)
        setGrid(self, false)
        local generator, bank = newBank(self, "batteryRackWood",
            { "Base.CarBattery1", "Base.CarBattery2", Specs.charger, Specs.charger, "RenewableEnergy.InverterCharger" }, 0.2)
        if not bank then return end
        PowerBank.perform(player(), "setBankOn", { bank = position(generator), on = true })
        bank:update(1, passContext(0))
        self.alone = bank.status.chargerW
        self.ownPower = generator:isActivated()
        local backup = newGenerator(self, generator:getSquare(), true, false, SandboxVars.GeneratorTileRange - 1)
        if not backup then return end
        local fuel = backup:getFuel()
        bank.charge = 0.2
        bank:update(1, passContext(0))
        self.fromGenerator = bank.status.chargerW
        self.generatorSource = bank.status.chargers[1] and bank.status.chargers[1].charging
        self.fuelUsed = fuel - backup:getFuel()
        setGrid(self, true)
        fuel = backup:getFuel()
        bank:update(1, passContext(0))
        self.fromGrid = bank.status.chargeSource
        self.gridFuel = fuel - backup:getFuel()
        self.gridPowered = generator:isActivated()
    end,
    validate = function(self)
        if not expect(self.alone ~= nil, "no indoor square for a bank") then return end
        local chargers = 2 * Specs.chargerWatts + Specs.inverters["RenewableEnergy.InverterCharger"].chargerWatts
        expectNear("charger watts with no grid or generator" .. (self.ownPower and " while the bank powers itself" or ""), self.alone, 0, 0)
        if not expect(self.fromGenerator ~= nil, "no square for a generator next to the bank") then return end
        expectNear("charger watts from a running generator", self.fromGenerator, chargers, 0)
        expect(self.generatorSource == "generator", "a charger says it charges from " .. tostring(self.generatorSource))
        expectNear("fuel the chargers burned in an hour", self.fuelUsed,
            chargers / Specs.loads.other.wattsPerConsumption * SandboxVars.GeneratorFuelConsumption, 0.001)
        expect(self.fromGrid == "grid", "with the grid on the chargers charge from " .. tostring(self.fromGrid))
        expectNear("fuel the chargers burned on grid power", self.gridFuel, 0, 0)
        expect(not self.gridPowered, "the bank ran its own generator while the grid powered its square")
    end,
    cleanup = cleanup,
})

-- At night a bank that is on powers its squares and pays its load and the inverter's idle draw.
test("renewable_energy_power_bank_powers_at_night", {
    run = function(self)
        setGrid(self, false)
        local generator, bank = newBank(self, "batteryRackWood",
            { "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", "RenewableEnergy.InverterCharger" }, 1)
        if not bank then return end
        PowerBank.perform(player(), "setBankOn", { bank = position(generator), on = true })
        self.powered = generator:isActivated() and generator:getSquare():haveElectricity()
        self.overloaded = bank.overloaded
        local before = bank.charge * bank.nominalWh
        bank:update(1, passContext(0))
        self.drawW = bank.status.drawW
        self.loadW = bank.averageLoadW
        self.used = before - bank.charge * bank.nominalWh
        self.charging = bank.status.charging
    end,
    validate = function(self)
        if not expect(self.powered ~= nil, "no bank was placed") then return end
        if self.overloaded then
            print("RETest NOTE renewable_energy_power_bank_powers_at_night: the house's appliances overload a 2,500 W inverter")
            return
        end
        expect(self.powered, "switching on a charged bank with an inverter did not power its square")
        local idle = Specs.inverters["RenewableEnergy.InverterCharger"].idle
        expectNear("draw: the load through the inverter and its idle", self.drawW, self.loadW / 0.9 + idle, 0.01)
        expectNear("Wh used in an hour", self.used, self.drawW, 0.5)
        expect(self.charging.watts < 0 and self.charging.hours ~= nil, "the status doesn't say the bank is draining")
    end,
    cleanup = cleanup,
})

-- A day's deepest discharge wears the batteries when the day turns.
test("renewable_energy_power_depth_of_discharge_wears_batteries", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        local generator, bank = newBank(self, "batteryBoxWood", { "Base.CarBattery1" }, 1)
        if not bank then return end
        bank.cycleHigh = 1
        bank.charge = 0.5
        bank:trackCycle()
        self.depth = bank.cycleDepth
        bank.day = bank.day and bank.day - 1 or 0
        bank:newDay(generator:getContainer(), bank.day + 1)
        local battery = generator:getContainer():getFirstType("Base.CarBattery1")
        self.condition = battery and battery:getCondition()
        self.depthAfter = bank.cycleDepth
    end,
    validate = function(self)
        if not expect(self.depth ~= nil, "no bank was placed") then return end
        expectNear("cycle depth", self.depth, 0.5, 0.0001)
        expectNear("car battery condition after a 50% day", self.condition, 99, 0)
        expectNear("cycle depth on the new day", self.depthAfter, 0, 0)
    end,
    cleanup = cleanup,
})

-- Storms crack modules by mount: wall panels never, wooden racks most, metal racks least. A
-- crack takes 30 condition, never below 0, and reaches the panel's own record.
test("renewable_energy_power_storms_crack_by_mount", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local mounts = {
            flat = { kind = "flat" }, wall = { kind = "wall", material = "wood" },
            woodRack = { kind = "rack", material = "wood" }, metalRack = { kind = "rack", material = "metal" },
        }
        self.cracks = {}
        for name, mount in pairs(mounts) do
            local count = 0
            for _ = 1, 2000 do
                local source = { kind = mount.kind, material = mount.material,
                    modules = { { type = "RenewableEnergy.SolarModule", condition = 100 } } }
                if Bank().stormCrack(source, 20) then
                    count = count + 1
                end
            end
            self.cracks[name] = count
        end
        local nearlyGone = { kind = "flat", modules = { { type = "RenewableEnergy.SolarModule", condition = 10 } } }
        SandboxVars.RenewableEnergy.StormDamageRate = 1000
        Bank().stormCrack(nearlyGone, 1000)
        self.floor = nearlyGone.modules[1].condition
        SandboxVars.RenewableEnergy.StormDamage = false
        local sheltered = { kind = "flat", modules = { { type = "RenewableEnergy.SolarModule", condition = 100 } } }
        self.disabled = Bank().stormCrack(sheltered, 1000)
        SandboxVars.RenewableEnergy.StormDamage = true

        local generator, bank = newBank(self, "batteryBoxWood", { "Base.CarBattery1" }, 0.5)
        local panel = generator and newPanel(self, Sprites.flat, generator, { { type = "RenewableEnergy.SolarModule", condition = 100 } })
        if not (panel and connect(generator, panel)) then return end
        bank:update(1, passContext(1000, 1000))
        local record = panel:getModData()[PowerBank.MODULES]
        self.recorded = record and record[1] and record[1].condition
    end,
    validate = function(self)
        local cracks = self.cracks
        expectNear("wall panels cracked", cracks.wall, 0, 0)
        expect(cracks.woodRack > cracks.flat and cracks.flat > cracks.metalRack and cracks.metalRack > 0,
            string.format("cracks in 2000 storms of 20 hours: wooden rack %d, flat %d, metal rack %d",
                cracks.woodRack, cracks.flat, cracks.metalRack))
        expectNear("a module at 10 after a crack", self.floor, 0, 0)
        expect(not self.disabled, "a storm cracked a module with Storm Damage off")
        if not expect(self.recorded ~= nil, "no bank and panel for the storm pass") then return end
        expectNear("the panel's recorded condition after a sure crack", self.recorded, 100 - Specs.storm.crack, 0)
    end,
    cleanup = cleanup,
})

-- Wiring a part in takes its tool, wire and skill, and a free slot; Electricity XP comes only
-- the first time an item is ever wired in; unwiring gives back the part and the wire.
test("renewable_energy_power_wiring_parts", {
    run = function(self)
        local p = player()
        self.level = p:getPerkLevel(Perks.Electricity)
        p:setPerkLevelDebug(Perks.Electricity, 2)
        local generator, bank = newBank(self, "batteryBoxWood", {})
        if not bank then return end
        local bankPosition = position(generator)
        local inventory = p:getInventory()
        local function wire(item)
            return PowerBank.perform(p, "wireIn", { bank = bankPosition, itemId = item:getID() })
        end
        local battery = inventory:AddItem("Base.CarBattery1")
        local hammer = inventory:AddItem("Base.Hammer")
        self.hammer = select(2, wire(hammer))
        self.noTool = select(2, wire(battery))
        inventory:AddItem("Base.Wrench")
        self.noWire = select(2, wire(battery))
        inventory:AddItem(PowerBank.WIRE)
        local xp = p:getXp():getXP(Perks.Electricity)
        self.wired = wire(battery)
        self.firstXp = p:getXp():getXP(Perks.Electricity) - xp
        self.wireLeft = inventory:getCountTypeRecurse(PowerBank.WIRE)
        self.unwired = PowerBank.perform(p, "unwire", { bank = bankPosition, itemId = battery:getID() })
        self.batteryBack = inventory:contains(battery)
        self.wireBack = inventory:getCountTypeRecurse(PowerBank.WIRE)
        xp = p:getXp():getXP(Perks.Electricity)
        self.rewired = wire(battery)
        self.secondXp = p:getXp():getXP(Perks.Electricity) - xp
        inventory:AddItem("Base.Screwdriver")
        inventory:AddItem(PowerBank.WIRE)
        inventory:AddItem(PowerBank.WIRE)
        self.skill = select(2, wire(inventory:AddItem("RenewableEnergy.InverterCharger")))
        inventory:AddItem(PowerBank.WIRE)
        self.full = select(2, wire(inventory:AddItem("Base.CarBattery2"))) == nil
            and select(2, wire(inventory:AddItem("Base.CarBattery3")))
        self.batteries = #bank.batteries
    end,
    validate = function(self)
        if not expect(self.wired ~= nil, "no indoor square for a bank") then return end
        expect(self.hammer == "Tooltip_RenewableEnergy_NotAPart", "a hammer was wired in (" .. tostring(self.hammer) .. ")")
        expect(self.noTool == "Tooltip_RenewableEnergy_NeedTool", "a battery was wired in without a wrench (" .. tostring(self.noTool) .. ")")
        expect(self.noWire == "Tooltip_RenewableEnergy_NeedWire", "a battery was wired in without wire (" .. tostring(self.noWire) .. ")")
        expect(self.wired, "wiring a battery in with a wrench and wire failed")
        expect(self.firstXp > 0, "the first wiring gave no Electricity XP")
        expectNear("wire left after wiring a battery in", self.wireLeft, 0, 0)
        expect(self.unwired and self.batteryBack, "unwiring didn't give the battery back")
        expectNear("wire back after unwiring", self.wireBack, 1, 0)
        expect(self.rewired, "wiring the battery in again failed")
        expectNear("XP for wiring the same battery again", self.secondXp, 0, 0)
        expect(self.skill == "Tooltip_RenewableEnergy_NeedSkill", "an Inverter/Charger was wired in at Electricity 2 (" .. tostring(self.skill) .. ")")
        expect(self.full == "Tooltip_RenewableEnergy_NoSlot", "a battery box took a third battery (" .. tostring(self.full) .. ")")
        expectNear("batteries in the box", self.batteries, 2, 0)
    end,
    cleanup = function(self)
        cleanup(self)
        if self.level then player():setPerkLevelDebug(Perks.Electricity, self.level) end
    end,
})

-- Stands still for a moment, so the runner validates after the world has run some frames.
local Settle = ISBaseTimedAction:derive("RenewableEnergyTestSettle")

function Settle:new(character)
    local o = ISBaseTimedAction.new(self, character)
    o.maxTime = 60
    return o
end

function Settle:isValid()
    return true
end

-- Wiring needs light to see by.
test("renewable_energy_power_wiring_refused_in_the_dark", {
    run = function(self)
        setGrid(self, false)
        self.hour = getGameTime():getTimeOfDay()
        getGameTime():setTimeOfDay(0)
        local generator = newBank(self, "batteryBoxWood", {})
        self.generator = generator
        ISTimedActionQueue.add(Settle:new(player()))
    end,
    validate = function(self)
        local p, generator = player(), self.generator
        if not expect(generator ~= nil, "no indoor square for a bank") then return end
        local inventory = p:getInventory()
        inventory:AddItem("Base.Wrench")
        inventory:AddItem(PowerBank.WIRE)
        local battery = inventory:AddItem("Base.CarBattery1")
        if not expect(p:tooDarkToRead(), "midnight with the grid off isn't dark where the character stands") then return end
        local wired, reason = PowerBank.perform(p, "wireIn", { bank = position(generator), itemId = battery:getID() })
        expect(not wired and reason == "Tooltip_RenewableEnergy_TooDark", "a battery was wired in in the dark (" .. tostring(reason) .. ")")
    end,
    cleanup = function(self)
        if self.hour then getGameTime():setTimeOfDay(self.hour) end
        cleanup(self)
    end,
})

-- Inverters and controllers wear while the bank runs, an overload costs extra, a part at 0
-- does nothing, and Electronics Scrap repairs 10 points at Electricity 2.
test("renewable_energy_power_part_wear_and_repair", {
    run = function(self)
        setGrid(self, false)
        local p = player()
        self.level = p:getPerkLevel(Perks.Electricity)
        local generator, bank = newBank(self, "batteryRackWood",
            { "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", "RenewableEnergy.InverterCharger", Specs.controller }, 1)
        if not bank then return end
        local container = generator:getContainer()
        local inverter = container:getFirstType("RenewableEnergy.InverterCharger")
        local controller = container:getFirstType(Specs.controller)
        Wear.setCondition(inverter, 80)
        Wear.setCondition(controller, 80)
        PowerBank.perform(p, "setBankOn", { bank = position(generator), on = true })
        bank.overloaded = false
        bank:wearParts(container, 100, 0)
        self.inverterWorn = 80 - inverter:getCondition()
        self.controllerWorn = 80 - controller:getCondition()
        Wear.setCondition(inverter, 80)
        bank:wearParts(container, 0, 1)
        self.overloadWorn = 80 - inverter:getCondition()

        local bankPosition = position(generator)
        local function repair(item)
            return select(2, PowerBank.perform(p, "repairPart", { bank = bankPosition, itemId = item:getID() }))
        end
        Wear.setCondition(inverter, 50)
        p:getInventory():AddItem(PowerBank.SCRAP)
        p:setPerkLevelDebug(Perks.Electricity, 1)
        self.unskilled = repair(inverter)
        p:setPerkLevelDebug(Perks.Electricity, 2)
        self.repaired = repair(inverter) == nil and inverter:getCondition()
        self.scrapLeft = p:getInventory():getCountTypeRecurse(PowerBank.SCRAP)
        self.noScrap = repair(inverter)
        Wear.setCondition(inverter, inverter:getConditionMax())
        p:getInventory():AddItem(PowerBank.SCRAP)
        self.whole = repair(inverter)

        Wear.setCondition(inverter, 0)
        PowerBank.perform(p, "refresh", { bank = bankPosition })
        bank:powerUp()
        self.brokenLimit = bank:limitW()
        self.brokenPowered = generator:isActivated()
    end,
    validate = function(self)
        if not expect(self.inverterWorn ~= nil, "no indoor square for a bank") then return end
        expectNear("inverter condition lost in 100 hours on", self.inverterWorn, math.floor(Specs.partWear.inverterPerHour * 100), 0)
        expectNear("controller condition lost in 100 hours on", self.controllerWorn, math.floor(Specs.partWear.controllerPerHour * 100), 0)
        expectNear("inverter condition lost to one overload", self.overloadWorn, Specs.partWear.overload, 0)
        expect(self.unskilled == "Tooltip_RenewableEnergy_NeedSkill", "a part was repaired at Electricity 1 (" .. tostring(self.unskilled) .. ")")
        expectNear("condition after one scrap", self.repaired, 60, 0)
        expectNear("scrap left", self.scrapLeft, 0, 0)
        expect(self.noScrap == "Tooltip_RenewableEnergy_NeedScrap", "a part was repaired without scrap (" .. tostring(self.noScrap) .. ")")
        expect(self.whole == "Tooltip_RenewableEnergy_NoRepairNeeded", "a whole part took a repair (" .. tostring(self.whole) .. ")")
        expectNear("limit with the only inverter at 0", self.brokenLimit, 0, 0)
        expect(not self.brokenPowered, "a bank whose only inverter is broken powers its area")
    end,
    cleanup = function(self)
        cleanup(self)
        if self.level then player():setPerkLevelDebug(Perks.Electricity, self.level) end
    end,
})

-- A failsafe starts its generator when the bank runs low and stops it once it's charged.
test("renewable_energy_power_failsafe_starts_generator", {
    sandbox = { FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        setGrid(self, false)
        local bankGenerator, bank = newBank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 0.1)
        if not bank then return end
        local backup = newGenerator(self, bankGenerator:getSquare(), false, true, 3)
        if not backup then return end
        bank.on = true
        bank:update(0.01, passContext(0))
        self.started = backup:isActivated()
        self.failsafe = bank.status.generator and bank.status.generator.failsafe
        bank.charge = 0.9
        bank:writeBatteries(bankGenerator:getContainer(), false)
        bank:update(0.01, passContext(0))
        self.stopped = not backup:isActivated()
    end,
    validate = function(self)
        if not expect(self.started ~= nil, "no bank or generator was placed") then return end
        expect(self.failsafe, "the bank didn't find the failsafe generator")
        expect(self.started, "the failsafe didn't start the generator at 10% charge")
        expect(self.stopped, "the failsafe didn't stop the generator at 90% charge")
    end,
    cleanup = cleanup,
})

-- Clients send commands through OnClientCommand, which must survive bad arguments and refuse
-- what the world doesn't allow; the status it sends reaches the client's copy of the bank.
test("renewable_energy_power_commands_from_clients", {
    run = function(self)
        local generator, bank = newBank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 1)
        if not bank then return end
        local sys = system()
        self.position = position(generator)
        sys:OnClientCommand("noSuchCommand", player(), { bank = self.position })
        sys:OnClientCommand("setBankOn", player(), { bank = "nonsense" })
        sys:OnClientCommand("wireIn", player(), { bank = self.position, itemId = "nonsense" })
        sys:OnClientCommand("rename", player(), { bank = self.position, name = 7 })
        self.badSource = PowerBank.perform(player(), "connectSource", { bank = self.position, source = self.position })
        self.noArgs = PowerBank.perform(player(), "connectSource", nil)
        local panel = newPanel(self, Sprites.rack.wood.S, generator)
        if panel then
            connect(generator, panel)
            local source = bank:findSource(panel:getX(), panel:getY(), panel:getZ())
            if source then source.snow = 0.8 end
            self.cleared = PowerBank.perform(player(), "clearSnow", { source = position(panel) })
            self.snow = source and source.snow
            self.disconnected = PowerBank.perform(player(), "disconnectSource", { source = position(panel) })
            self.sourcesLeft = #bank.sources
        end
        sys:OnClientCommand("rename", player(), { bank = self.position, name = "  Shed bank  " })
        sys:OnClientCommand("setBankOn", player(), { bank = self.position, on = true })
        self.serverOn = bank.on
    end,
    validate = function(self)
        if not expect(self.position ~= nil, "no bank was placed") then return end
        expect(not self.badSource, "a bank was connected to itself as a panel")
        expect(not self.noArgs, "a command without arguments succeeded")
        expect(self.cleared and self.snow == 0, "clearing snow left " .. tostring(self.snow))
        expect(self.disconnected and self.sourcesLeft == 0, "disconnecting the panel left " .. tostring(self.sourcesLeft) .. " sources")
        expect(self.serverOn, "setBankOn through OnClientCommand didn't switch the bank on")
        local client = PowerBank.clientSystem
        local copy = client and client.system:getObjectAt(self.position.x, self.position.y, self.position.z)
        local status = copy and copy:getModData().status
        expect(status and status.on == true and status.kind == "batteryBoxWood", "the client's copy of the status doesn't show the bank on")
        expect(status and status.name == "Shed bank", "the client's copy names the bank " .. tostring(status and status.name))
    end,
    cleanup = cleanup,
})

-- A removed running bank leaves nothing powered and is forgotten.
test("renewable_energy_power_removed_bank_leaves_no_power", {
    run = function(self)
        setGrid(self, false)
        local generator, bank = newBank(self, "batteryRackWood",
            { "RenewableEnergy.L16Battery", "RenewableEnergy.InverterCharger" }, 1)
        if not bank then return end
        local square = generator:getSquare()
        PowerBank.perform(player(), "setBankOn", { bank = position(generator), on = true })
        self.wasPowered = square:haveElectricity()
        PowerBank.remove(generator)
        self.powered = square:haveElectricity()
        self.registered = system():getLuaObjectOnSquare(square) ~= nil
    end,
    validate = function(self)
        if not expect(self.wasPowered ~= nil, "no bank was placed") then return end
        expect(self.wasPowered, "the switched-on bank didn't power its square")
        expect(not self.powered, "the removed bank's square still has power")
        expect(not self.registered, "the removed bank is still registered")
    end,
    cleanup = cleanup,
})
