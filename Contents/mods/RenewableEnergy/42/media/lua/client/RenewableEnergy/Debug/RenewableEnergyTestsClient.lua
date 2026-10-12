require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "TimedActions/ISInventoryTransferAction"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/Menu"
require "RenewableEnergy/UI/StatusWindow"

-- Menus, timed actions and the status window. See RenewableEnergyTestLib.lua for how the runner
-- works. Each test builds its own banks and panels next to the character and removes them
-- again, since world objects outlive a test.

local test = RenewableEnergyTest.test
local expect, expectNear, player = RenewableEnergyTest.expect, RenewableEnergyTest.expectNear, RenewableEnergyTest.player

-- Server Lua loads after client Lua, so a server file can only be required once the game
-- runs, when require hands back the loaded file's table.
local function Loads()
    return require "RenewableEnergy/PowerBank/Loads"
end

local Action = RenewableEnergyAction
local Specs = RenewableEnergy.Specs
local Sprites = RenewableEnergy.Sprites
local PowerBank = RenewableEnergy.PowerBank
local Battery = RenewableEnergy.Battery
local Wear = RenewableEnergy.Wear
local Format = RenewableEnergy.Format
local Menu = RenewableEnergy.Menu
local StatusWindow = RenewableEnergy.StatusWindow

-- Fixtures ------------------------------------------------------------------------------------

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

-- Free squares around `center` (the character's square by default), nearest first, enough for
-- `count` objects: indoors where a bank may stand, or outdoors.
local function freeSquares(self, count, indoors, center)
    self.used = self.used or {}
    local found = {}
    center = center or player():getCurrentSquare()
    if not center then return found end
    for radius = 1, 30 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local square = math.max(math.abs(dx), math.abs(dy)) == radius
                    and getSquare(center:getX() + dx, center:getY() + dy, center:getZ())
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

local function outdoorSquares(self, count)
    return freeSquares(self, count, false)
end

local function placed(self, object)
    self.objects = self.objects or {}
    table.insert(self.objects, object)
    return object
end

local function placeObject(self, square, spriteName, modules)
    local object = IsoObject.new(square, spriteName, "RenewableEnergyTest")
    if modules then
        object:getModData()[PowerBank.MODULES] = modules
    end
    square:AddTileObject(object)
    return placed(self, object)
end

local function placeBank(self, square, spriteName)
    return placed(self, PowerBank.place(square, spriteName or Sprites.batteryBankWood))
end

local function position(object)
    return { x = object:getX(), y = object:getY(), z = object:getZ() }
end

local function samePosition(a, b)
    return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.z == b.z
end

-- The server's own record of a placed bank (single player runs both sides in one state).
local function bankRecord(bankObject)
    return PowerBank.serverSystem:getLuaObjectOnSquare(bankObject:getSquare())
end

--- A bank of Sprites field `kind` indoors holding `items` (full types), its batteries charged to
--- `charge`, the way world spawns fill one: straight into the container.
local function indoorBank(self, kind, items, charge)
    local square = freeSquares(self, 1, true)[1]
    if not square then return nil end
    local bank = placeBank(self, square, Sprites[kind])
    local container = bank and bank:getContainer()
    if not container then return bank end
    for _, fullType in ipairs(items) do
        local item = container:AddItem(fullType)
        if item and Battery.isBattery(item) then
            Battery.setCharge(item, charge or 1)
        end
    end
    PowerBank.perform(nil, "refresh", { bank = position(bank) })
    return bank
end

--- A panel on a free outdoor square near `bank`, wired to it.
local function wiredPanel(self, bank, spriteName, modules)
    local square = freeSquares(self, 1, false, bank:getSquare())[1]
    if not square then return nil end
    local panel = placeObject(self, square, spriteName, modules)
    PowerBank.perform(player(), "connectSource", { bank = position(bank), source = position(panel) })
    return panel
end

local function removeObject(object)
    if not object or object:getObjectIndex() == -1 then
        return
    end
    if PowerBank.isBank(object) then
        PowerBank.remove(object)
    else
        object:getSquare():transmitRemoveItemFromSquare(object)
    end
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

local function setElectricity(self, level)
    local p = player()
    self.savedLevel = self.savedLevel or p:getPerkLevel(Perks.Electricity)
    p:setPerkLevelDebug(Perks.Electricity, level)
end

local function removeAll(self)
    for i = #(self.objects or {}), 1, -1 do
        removeObject(self.objects[i])
    end
    self.objects = {}
    if self.vehicle then
        self.vehicle:permanentlyRemove()
    end
    local window = StatusWindow.windows[0]
    if window then
        window:close()
    end
    restoreGrid(self)
    if self.savedHour then
        getGameTime():setTimeOfDay(self.savedHour)
        self.savedHour = nil
    end
    if self.savedLevel then
        player():setPerkLevelDebug(Perks.Electricity, self.savedLevel)
        self.savedLevel = nil
    end
end

-- A pass with the weather fixed: `light` W/m² on every mount, clear, 25 °C, no snow or storm.
local function passContext(light)
    local function irradiance() return light end
    return {
        weather = RenewableEnergy.Sun.CLEAR_WEATHER, precipitation = 0, airC = 25, elevation = light > 0 and 45 or -10,
        stormHours = 0, irradiance = irradiance, clearIrradiance = irradiance,
    }
end

-- The measured load replaced by Specs.loads names, as if the scan had found them, and the
-- bank's reaction to it.
local function applyLoad(record, names)
    local load = Loads().new()
    for _, name in ipairs(names) do
        Loads().add(load, name)
    end
    record.loadW, record.averageLoadW, record.loadByKind = load.watts, load.averageWatts, Loads().byKind(load)
    record:checkOverload()
    record:switchGenerator()
    record:sendStatus()
end

local Wait = RenewableEnergyTest.Wait

local function wait(total, onTick)
    ISTimedActionQueue.add(Wait:new(player(), total, onTick))
end

-- Midnight with the grid off: dark where the character stands. The light needs a moment to
-- follow the clock.
local function makeDark(self)
    setGrid(self, false)
    self.savedHour = getGameTime():getTimeOfDay()
    getGameTime():setTimeOfDay(0)
    wait(60)
end

local function optionNamed(menu, name)
    return menu and menu.getOptionFromName and menu:getOptionFromName(name)
end

local function hasEnabledOption(menu)
    for _, option in ipairs(menu and menu.options or {}) do
        if option.onSelect and not option.notAvailable then
            return true
        end
    end
    return false
end

local function tooltipOf(option)
    return option and option.toolTip and option.toolTip.description
end

-- Chooses an option the way a click does.
local function choose(option)
    option.onSelect(option.target, option.param1, option.param2, option.param3, option.param4)
end

local function newContext()
    return ISContextMenu.get(0, 0, 0)
end

-- Menus ---------------------------------------------------------------------------------------

-- A bank's menu lists its window, its switch, renaming and wiring; vanilla's own generator
-- options (fuel, plug in) must not appear for it.
test("renewable_energy_client_menu_bank", {
    run = function(self)
        local squares = outdoorSquares(self, 1)
        if #squares < 1 then return end
        self.bank = placeBank(self, squares[1])
        wait(5)
    end,
    validate = function(self)
        if not expect(self.bank ~= nil, "no open ground for a bank next to the character") then return end
        local fetch = ISWorldObjectContextMenu.fetchVars
        fetch.generator = self.bank
        local context = newContext()
        Menu.onPreFill(0, context, { self.bank }, false)
        expect(fetch.generator == nil, "the bank stayed in fetchVars.generator, so vanilla offers generator options for it")
        Menu.onFill(0, context, { self.bank }, false)
        local option = optionNamed(context, Menu.bankLabel(self.bank))
        expect(option ~= nil and option.subOption ~= nil, "right-clicking a bank shows no bank submenu")
        local submenu = Menu.addBankOptions(0, context, self.bank)
        expect(optionNamed(submenu, getText("ContextMenu_RenewableEnergy_Status")) ~= nil, "the bank menu has no status option")
        expect(optionNamed(submenu, getText("ContextMenu_RenewableEnergy_Rename")) ~= nil, "the bank menu has no Rename")
        local turnOn = optionNamed(submenu, getText("ContextMenu_Turn_On"))
        expect(turnOn ~= nil, "a bank that is off offers no Turn On")
        expect(turnOn == nil or turnOn.notAvailable, "a bank without an inverter offers to turn on")
        local wireIn = optionNamed(submenu, getText("ContextMenu_RenewableEnergy_WireIn"))
        expect(wireIn ~= nil and wireIn.notAvailable and tooltipOf(wireIn) == getText("Tooltip_RenewableEnergy_NothingToWire"),
            "with no part carried, Wire In isn't unavailable with the reason")
        expect(optionNamed(submenu, getText("ContextMenu_RenewableEnergy_Unwire")) == nil, "an empty bank offers to unwire something")
        fetch.generator = nil
        context:hideAndChildren()
    end,
    cleanup = removeAll,
})

-- Objects that aren't the mod's add nothing to the menu.
test("renewable_energy_client_menu_ignores_other_objects", {
    validate = function()
        local square = player():getSquare()
        local floor = square and square:getFloor()
        if not expect(floor ~= nil, "the character stands on no floor") then return end
        local context = newContext()
        local before = context.numOptions
        Menu.onFill(0, context, { floor }, false)
        expect(context.numOptions == before, "a plain floor got " .. (context.numOptions - before) .. " options")
        context:hideAndChildren()
    end,
})

-- A panel with no bank in reach says why it can't be connected rather than offering nothing.
test("renewable_energy_client_menu_panel_without_bank", {
    run = function(self)
        local squares = outdoorSquares(self, 1)
        if #squares < 1 then return end
        self.panel = placeObject(self, squares[1], Sprites.flat)
    end,
    validate = function(self)
        if not expect(self.panel ~= nil, "no open ground for a panel next to the character") then return end
        if not expect(#PowerBank.banksInReach(self.panel:getX(), self.panel:getY(), self.panel:getZ()) == 0,
            "a bank left by an earlier run is in reach") then return end
        local context = newContext()
        local submenu = Menu.addSourceOptions(0, context, self.panel)
        local option = optionNamed(submenu, getText("ContextMenu_RenewableEnergy_ConnectToBank"))
        expect(option ~= nil and option.notAvailable, "a panel with no bank in reach shows no unavailable connect option")
        expect(option == nil or option.toolTip ~= nil, "the unavailable connect option does not say why")
        expect(not hasEnabledOption(submenu), "a panel with no bank in reach offers something to do")
        context:hideAndChildren()
    end,
    cleanup = removeAll,
})

-- With a bank in reach the panel offers to connect to it, and only then.
test("renewable_energy_client_menu_panel_with_bank", {
    run = function(self)
        local squares = outdoorSquares(self, 2)
        if #squares < 2 then return end
        self.bank = placeBank(self, squares[1])
        self.panel = placeObject(self, squares[2], Sprites.rack.wood.S)
        wait(5)
    end,
    validate = function(self)
        if not expect(self.panel ~= nil, "no open ground for a bank and a panel") then return end
        local context = newContext()
        Menu.onFill(0, context, { self.panel }, false)
        expect(optionNamed(context, Menu.nameOf(self.panel)) ~= nil, "right-clicking a panel shows no panel submenu")
        local submenu = Menu.addSourceOptions(0, context, self.panel)
        expect(hasEnabledOption(submenu), "a panel next to a bank offers no connection")
        expect(optionNamed(submenu, getText("ContextMenu_RenewableEnergy_DisconnectPanel")) == nil,
            "a panel that isn't connected offers to disconnect")
        expect(optionNamed(submenu, getText("ContextMenu_RenewableEnergy_ClearSnow")) == nil, "a rack offers to clear snow")
        context:hideAndChildren()
    end,
    cleanup = removeAll,
})

-- A wired panel names its bank, by the name a player gave it, and how far away it stands.
test("renewable_energy_client_menu_panel_wired_to", {
    run = function(self)
        local squares = outdoorSquares(self, 2)
        if #squares < 2 then return end
        self.bank = placeBank(self, squares[1])
        self.panel = placeObject(self, squares[2], Sprites.flat)
        PowerBank.perform(player(), "connectSource", { bank = position(self.bank), source = position(self.panel) })
        PowerBank.perform(player(), "rename", { bank = position(self.bank), name = "Shed Bank" })
    end,
    validate = function(self)
        if not expect(self.panel ~= nil, "no open ground for a bank and a panel") then return end
        local context = newContext()
        local submenu = Menu.addSourceOptions(0, context, self.panel)
        local wiredTo
        for _, option in ipairs(submenu.options) do
            if option.name:find("Shed Bank", 1, true) then
                wiredTo = option.name
            end
        end
        local dx, dy = self.bank:getX() - self.panel:getX(), self.bank:getY() - self.panel:getY()
        local tiles = round(math.sqrt(dx * dx + dy * dy))
        expect(wiredTo ~= nil, "a wired panel's menu doesn't name its renamed bank")
        expect(wiredTo == nil or wiredTo:find(tostring(tiles), 1, true) ~= nil,
            "the panel menu says " .. tostring(wiredTo) .. ", but the bank is " .. tiles .. " tiles away")
        context:hideAndChildren()
    end,
    cleanup = removeAll,
})

-- Wire In offers each carried part type once, and says what stops it: a full bank, a missing
-- tool, too little wire, too low a level.
test("renewable_energy_client_menu_wire_in_refusals", {
    run = function(self)
        setElectricity(self, 2)
        self.bank = indoorBank(self, "batteryBoxWood", { "Base.CarBattery1", "Base.CarBattery1" })
    end,
    validate = function(self)
        if not expect(self.bank ~= nil, "no indoor square for a bank") then return end
        local inventory = player():getInventory()
        inventory:AddItem("Base.CarBattery2")
        inventory:AddItem("Base.CarBattery2")
        local inverter = inventory:AddItem("RenewableEnergy.PlugInInverter")
        inventory:AddItem("RenewableEnergy.InverterCharger")
        local context = newContext()
        local function wireInMenu()
            return Menu.addWireInOptions(0, context, self.bank)
        end
        local function optionFor(menu, item)
            return optionNamed(menu, item:getDisplayName())
        end
        local menu = wireInMenu()
        local batteries = 0
        for _, option in ipairs(menu.options or {}) do
            if option.name == getItemNameFromFullType("Base.CarBattery2") then
                batteries = batteries + 1
            end
        end
        expectNear("Wire In options for two batteries of one type", batteries, 1, 0)
        local battery = optionNamed(menu, getItemNameFromFullType("Base.CarBattery2"))
        expect(battery ~= nil and battery.notAvailable and tooltipOf(battery) == getText("Tooltip_RenewableEnergy_NoSlot"),
            "a full battery box offers to wire in a third battery (" .. tostring(tooltipOf(battery)) .. ")")
        local plugIn = optionFor(menu, inverter)
        local needScrewdriver = getText("Tooltip_RenewableEnergy_NeedTool", getItemNameFromFullType("Base.Screwdriver"))
        expect(plugIn ~= nil and plugIn.notAvailable and tooltipOf(plugIn) == needScrewdriver,
            "an inverter can be wired in without a screwdriver (" .. tostring(tooltipOf(plugIn)) .. ")")
        local charger = optionNamed(menu, getItemNameFromFullType("RenewableEnergy.InverterCharger"))
        local needSkill = getText("Tooltip_RenewableEnergy_NeedSkill", Perks.Electricity:getName(),
            Specs.inverters["RenewableEnergy.InverterCharger"].wireSkill)
        expect(charger ~= nil and charger.notAvailable and tooltipOf(charger) == needSkill,
            "an Inverter/Charger is offered at Electricity 2 (" .. tostring(tooltipOf(charger)) .. ")")

        inventory:AddItem("Base.Screwdriver")
        plugIn = optionFor(wireInMenu(), inverter)
        local wire = PowerBank.wiringFor(inverter:getFullType()).wire
        local needWire = getText("Tooltip_RenewableEnergy_NeedWire", wire, getItemNameFromFullType(PowerBank.WIRE))
        expect(plugIn ~= nil and plugIn.notAvailable and tooltipOf(plugIn) == needWire,
            "an inverter can be wired in without wire (" .. tostring(tooltipOf(plugIn)) .. ")")
        for _ = 1, wire do
            inventory:AddItem(PowerBank.WIRE)
        end
        plugIn = optionFor(wireInMenu(), inverter)
        expect(plugIn ~= nil and not plugIn.notAvailable, "with a screwdriver and wire, the inverter can't be wired in ("
            .. tostring(tooltipOf(plugIn)) .. ")")
        context:hideAndChildren()
    end,
    cleanup = removeAll,
})

-- In the dark nothing can be wired in or out, and the menu says why.
test("renewable_energy_client_menu_dark", {
    run = function(self)
        self.bank = indoorBank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PowerInverter" })
        if self.bank then makeDark(self) end
    end,
    validate = function(self)
        if not expect(self.bank ~= nil, "no indoor square for a bank") then return end
        local p = player()
        if not expect(p:tooDarkToRead(), "midnight with the grid off isn't dark where the character stands") then return end
        local inventory = p:getInventory()
        local battery = inventory:AddItem("Base.CarBattery2")
        inventory:AddItem("Base.Wrench")
        inventory:AddItem(PowerBank.WIRE)
        inventory:AddItem(PowerBank.SCRAP)
        local context = newContext()
        local wireIn = optionNamed(Menu.addWireInOptions(0, context, self.bank), battery:getDisplayName())
        local dark = getText("Tooltip_RenewableEnergy_TooDark")
        expect(wireIn ~= nil and wireIn.notAvailable and tooltipOf(wireIn) == dark,
            "a battery can be wired in in the dark (" .. tostring(tooltipOf(wireIn)) .. ")")
        local unwire = Menu.addUnwireOptions(0, context, self.bank)
        local allDark = unwire ~= nil and #unwire.options > 0
        for _, option in ipairs(unwire and unwire.options or {}) do
            allDark = allDark and option.notAvailable and tooltipOf(option) == dark
        end
        expect(allDark, "a part can be unwired in the dark")
        expect(not Action:new(p, Action.WIRE_IN, nil, self.bank, nil, battery):isValid(),
            "the Wire In action runs in the dark")
        context:hideAndChildren()
    end,
    cleanup = removeAll,
})

-- Repair lists each inverter and controller and refuses one in good condition or without scrap.
test("renewable_energy_client_menu_repair", {
    run = function(self)
        setElectricity(self, Specs.partRepair.skill)
        self.bank = indoorBank(self, "batteryRackWood", { "RenewableEnergy.PowerInverter", "RenewableEnergy.ChargeController" })
    end,
    validate = function(self)
        if not expect(self.bank ~= nil, "no indoor square for a bank") then return end
        local container = self.bank:getContainer()
        local inverter = container:getFirstType("RenewableEnergy.PowerInverter")
        local controller = container:getFirstType(Specs.controller)
        if not expect(inverter ~= nil and controller ~= nil, "the rack holds no inverter or controller") then return end
        Wear.setCondition(inverter, 50)
        local context = newContext()
        local function optionFor(item)
            local menu = Menu.addRepairOptions(0, context, self.bank)
            for _, option in ipairs(menu and menu.options or {}) do
                if option.param3 == item then
                    return option
                end
            end
        end
        local worn = optionFor(inverter)
        local needScrap = getText("Tooltip_RenewableEnergy_NeedScrap", 1, getItemNameFromFullType(PowerBank.SCRAP))
        expect(worn ~= nil and worn.notAvailable and tooltipOf(worn) == needScrap,
            "a worn inverter can be repaired without scrap (" .. tostring(tooltipOf(worn)) .. ")")
        local fine = optionFor(controller)
        expect(fine ~= nil and fine.notAvailable and tooltipOf(fine) == getText("Tooltip_RenewableEnergy_NoRepairNeeded"),
            "a controller in perfect condition is offered a repair (" .. tostring(tooltipOf(fine)) .. ")")
        player():getInventory():AddItem(PowerBank.SCRAP)
        worn = optionFor(inverter)
        expect(worn ~= nil and not worn.notAvailable, "a worn inverter can't be repaired with scrap in hand")
        context:hideAndChildren()
    end,
    cleanup = removeAll,
})

-- Actions -------------------------------------------------------------------------------------

local CONNECT_MINUTES = 4

-- Connecting goes through the bank: afterwards the bank lists the panel. The sandbox option is in
-- in-game minutes, and the action takes that long at Electricity 3.
test("renewable_energy_client_connect_panel", {
    sandbox = { ConnectPanelMin = CONNECT_MINUTES },
    run = function(self)
        local p = player()
        local squares = outdoorSquares(self, 2)
        if #squares < 2 then return end
        self.bank = placeBank(self, squares[1])
        self.panel = placeObject(self, squares[2], Sprites.flat)
        setElectricity(self, 3)
        self.instant = p:isTimedActionInstant()
        self.action = Action:new(p, Action.CONNECT_SOURCE, self.panel, self.bank)
        self.valid = self.action:canPerform()
        self.startMinutes = getGameTime():getWorldAgeHours() * 60
        ISTimedActionQueue.add(self.action)
        wait(2)
    end,
    validate = function(self)
        if not expect(self.action ~= nil, "no open ground for a bank and a panel") then return end
        expect(self.valid, "connecting a panel next to a bank is refused")
        expect(samePosition(Action.connectedBank(self.panel), position(self.bank)), "the bank does not list the connected panel")
        expect(not self.action:canPerform(), "a panel already on this bank can be connected again")
        if self.instant then
            expect(self.action.maxTime == 1, "instant actions are on but the action took " .. tostring(self.action.maxTime))
            return
        end
        expectNear("maxTime", self.action.maxTime, CONNECT_MINUTES * Action.unitsPerMinute(), 0.01)
        local elapsed = getGameTime():getWorldAgeHours() * 60 - self.startMinutes
        -- Starting, the trailing wait and the runner noticing the empty queue add a little.
        expect(elapsed >= CONNECT_MINUTES * 0.9 and elapsed <= CONNECT_MINUTES * 1.25,
            string.format("connecting took %.2f in-game minutes, expected %d", elapsed, CONNECT_MINUTES))
    end,
    cleanup = removeAll,
})

test("renewable_energy_client_disconnect_panel", {
    sandbox = { ConnectPanelMin = 1 },
    run = function(self)
        local p = player()
        local squares = outdoorSquares(self, 2)
        if #squares < 2 then return end
        self.bank = placeBank(self, squares[1])
        self.panel = placeObject(self, squares[2], Sprites.wall.wood.S)
        self.connected = PowerBank.perform(p, "connectSource", { bank = position(self.bank), source = position(self.panel) })
        ISTimedActionQueue.add(Action:new(p, Action.DISCONNECT_SOURCE, self.panel))
        wait(2)
    end,
    validate = function(self)
        if not expect(self.panel ~= nil, "no open ground for a bank and a panel") then return end
        expect(self.connected, "the bank refused to connect a wall panel next to it")
        expect(Action.connectedBank(self.panel) == nil, "the panel is still connected after disconnecting it")
    end,
    cleanup = removeAll,
})

-- Clearing snow needs a broom or snow shovel in hand, and only flat panels hold snow.
test("renewable_energy_client_clear_snow_requirements", {
    run = function(self)
        local squares = outdoorSquares(self, 2)
        if #squares < 2 then return end
        self.flat = placeObject(self, squares[1], Sprites.flat)
        self.wall = placeObject(self, squares[2], Sprites.wall.wood.E)
    end,
    validate = function(self)
        if not expect(self.flat ~= nil, "no open ground for two panels") then return end
        local p = player()
        local inventory = p:getInventory()
        local function canClear(panel, tool)
            return Action:new(p, Action.CLEAR_SNOW, panel, nil, nil, tool):canPerform()
        end
        local broom = inventory:AddItem("Base.Broom")
        expect(not canClear(self.flat, broom), "snow can be cleared with a broom left in the bag")
        p:setPrimaryHandItem(broom)
        expect(canClear(self.flat, broom), "a broom in hand can't clear a flat panel")
        expect(not canClear(self.wall, broom), "a wall panel, which holds no snow, can be cleared")
        broom:setCondition(0)
        expect(not canClear(self.flat, broom), "a broken broom can clear snow")
        local shovel = inventory:AddItem("Base.SnowShovel")
        p:setPrimaryHandItem(shovel)
        expect(canClear(self.flat, shovel), "a snow shovel in hand can't clear a flat panel")
        local hammer = inventory:AddItem("Base.Hammer")
        p:setPrimaryHandItem(hammer)
        expect(not canClear(self.flat, hammer), "a hammer clears snow")
        p:setPrimaryHandItem(nil)
    end,
    cleanup = removeAll,
})

-- Wire In from the menu walks over, takes the wiring's time, puts the part in the bank, uses up
-- the wire and teaches XP once; Unwire gives part and wire back. The bank stands on the open
-- ground next to the character, which a walk always reaches; wiring doesn't care where it is.
test("renewable_energy_client_wire_in_and_unwire", {
    run = function(self)
        local p = player()
        setElectricity(self, 10)
        local square = outdoorSquares(self, 1)[1]
        self.bank = square and placeBank(self, square, Sprites.batteryBoxWood)
        if not self.bank then return end
        local inventory = p:getInventory()
        self.battery = inventory:AddItem("Base.CarBattery1")
        inventory:AddItem("Base.Wrench")
        inventory:AddItem(PowerBank.WIRE)
        local context = newContext()
        local option = optionNamed(Menu.addWireInOptions(0, context, self.bank), self.battery:getDisplayName())
        context:hideAndChildren()
        if not option or option.notAvailable then
            self.refused = tostring(tooltipOf(option))
            return
        end
        self.xp = p:getXp():getXP(Perks.Electricity)
        choose(option)
        local queue = ISTimedActionQueue.getTimedActionQueue(p).queue
        self.action = queue[#queue]
        self.instant = p:isTimedActionInstant()
        wait(2)
    end,
    validate = function(self)
        if not expect(self.bank ~= nil, "no indoor square for a bank") then return end
        if not expect(self.refused == nil, "Wire In was refused: " .. tostring(self.refused)) then return end
        local p = player()
        local container = self.bank:getContainer()
        expect(self.action ~= nil and self.action.mode == Action.WIRE_IN, "choosing Wire In queued no Wire In action")
        if not expect(container:contains(self.battery), string.format("the wired battery isn't in the bank (refusal %s, dark %s, %s tiles away)",
            tostring(PowerBank.wiringRefusal(p, self.bank, self.battery)), tostring(p:tooDarkToRead()),
            tostring(round(IsoUtils.DistanceTo(p:getX(), p:getY(), self.bank:getX(), self.bank:getY()))))) then return end
        expectNear("wire left", p:getInventory():getCountTypeRecurse(PowerBank.WIRE), 0, 0)
        expect(self.battery:getModData()[PowerBank.WIRED_ONCE] == true, "the battery isn't marked as wired once")
        expect(p:getXp():getXP(Perks.Electricity) > self.xp, "the first wiring gave no Electricity XP")
        local status = PowerBank.getStatus(self.bank:getX(), self.bank:getY(), self.bank:getZ())
        expect(status ~= nil and #status.batteries == 1, "the bank's status doesn't list the wired battery")
        if self.action and not self.instant then
            local wiring = PowerBank.wiringFor(self.battery:getFullType())
            -- Electricity 10 takes a quarter of the time at 0.
            local seconds = wiring.seconds * (1 - 0.095 * 7) / (1 + 0.095 * 3)
            expectNear("Wire In maxTime", self.action.maxTime, seconds * 48, 0.5)
        end
        local unwire = Action:new(p, Action.UNWIRE, nil, self.bank, nil, self.battery)
        expect(unwire:isValid(), "unwiring the battery just wired in is refused")
        expect(unwire:complete(), "unwiring the battery failed")
        expect(p:getInventory():contains(self.battery) and not container:contains(self.battery), "unwiring didn't give the battery back")
        expectNear("wire back after unwiring", p:getInventory():getCountTypeRecurse(PowerBank.WIRE), 1, 0)
    end,
    cleanup = removeAll,
})

-- Repairing a worn inverter in the bank uses a scrap and gives it condition back.
test("renewable_energy_client_repair_part", {
    run = function(self)
        local p = player()
        setElectricity(self, Specs.partRepair.skill)
        self.bank = indoorBank(self, "batteryBoxWood", { "RenewableEnergy.PowerInverter" })
        if not self.bank then return end
        self.inverter = self.bank:getContainer():getFirstType("RenewableEnergy.PowerInverter")
        if not self.inverter then return end
        Wear.setCondition(self.inverter, 50)
        p:getInventory():AddItem(PowerBank.SCRAP)
        ISTimedActionQueue.add(Action:new(p, Action.REPAIR_PART, nil, self.bank, nil, self.inverter))
        wait(2)
    end,
    validate = function(self)
        if not expect(self.inverter ~= nil, "no indoor square for a bank with an inverter") then return end
        expectNear("inverter condition after one scrap", self.inverter:getCondition(), 50 + Specs.partRepair.condition, 0)
        expectNear("scrap left", player():getInventory():getCountTypeRecurse(PowerBank.SCRAP), 0, 0)
        expect(self.bank:getContainer():contains(self.inverter), "repairing took the inverter out of the bank")
    end,
    cleanup = removeAll,
})

-- Renaming goes through the bank, shows in its menu and window, and an empty name gives the
-- tier's name back.
test("renewable_energy_client_rename_bank", {
    run = function(self)
        self.bank = indoorBank(self, "batteryRackMetal", {})
        if not self.bank then return end
        ISTimedActionQueue.add(Action:new(player(), Action.RENAME, nil, self.bank, nil, nil, "  Cellar  "))
        wait(2)
    end,
    validate = function(self)
        if not expect(self.bank ~= nil, "no indoor square for a bank") then return end
        expect(Menu.bankLabel(self.bank) == "Cellar", "the renamed bank's menu reads " .. tostring(Menu.bankLabel(self.bank)))
        local status = PowerBank.getStatus(self.bank:getX(), self.bank:getY(), self.bank:getZ())
        local window = StatusWindow.open(0, self.bank)
        window:setStatus(status)
        expect(window.title == "Cellar", "the window of the renamed bank is titled " .. tostring(window.title))
        window:close()
        local action = Action:new(player(), Action.RENAME, nil, self.bank, nil, nil, "")
        expect(action:canPerform() and action:complete(), "renaming to an empty name was refused")
        local tier = getItemNameFromFullType("RenewableEnergy.BatteryRackMetal")
        expect(Menu.bankLabel(self.bank) == tier, "an empty name left the bank called " .. tostring(Menu.bankLabel(self.bank)))
    end,
    cleanup = removeAll,
})

-- Dragging a part out of a bank is refused; Unwire is the way out. Other transfers still work.
test("renewable_energy_client_drag_out_refused", {
    run = function(self)
        local p = player()
        self.bank = indoorBank(self, "batteryBoxWood", { "Base.CarBattery1" })
        if not self.bank then return end
        self.battery = self.bank:getContainer():getFirstType("Base.CarBattery1")
        if not self.battery then return end
        local action = ISInventoryTransferAction:new(p, self.battery, self.bank:getContainer(), p:getInventory())
        self.valid = action:isValid()
        ISTimedActionQueue.add(action)
        wait(30)
    end,
    validate = function(self)
        if not expect(self.battery ~= nil, "no indoor square for a bank with a battery") then return end
        local p = player()
        expect(not self.valid, "moving a wired battery out of the bank is a valid transfer")
        expect(self.bank:getContainer():contains(self.battery) and not p:getInventory():contains(self.battery),
            "a wired battery was dragged out of the bank")
        local bag = p:getInventory():AddItem("Base.Bag_Schoolbag")
        local hammer = p:getInventory():AddItem("Base.Hammer")
        expect(bag ~= nil and hammer ~= nil and ISInventoryTransferAction:new(p, hammer, p:getInventory(), bag:getInventory()):isValid(),
            "moving a hammer into a bag is refused too")
    end,
    cleanup = removeAll,
})

-- Maintainer ------------------------------------------------------------------------------------

local VEHICLE = "Base.PickUpTruck"
-- Spots tried for a vehicle, from a square. addVehicleDebug puts the vehicle on the square's
-- north-west corner and it settles a little, so these keep it well within 3 tiles of the
-- square's centre.
local VEHICLE_OFFSETS = { { 2, 0 }, { -1, 0 }, { 0, 2 }, { 0, -1 }, { 1, 1 }, { 2, 1 }, { -1, 1 }, { 1, -1 } }

-- A vehicle spawned near `object`. addVehicleDebug returns a vehicle even when it leaves it out
-- of the world, which it does where it would hit another vehicle (IsoChunk.
-- doSpawnedVehiclesInInvalidPosition). Only a vehicle added to the world gets an id
-- (BaseVehicle.createPhysics), so this tries the next spot until one has.
local function spawnVehicleNear(object)
    for _, offset in ipairs(VEHICLE_OFFSETS) do
        local square = getSquare(object:getX() + offset[1], object:getY() + offset[2], object:getZ())
        if square and square:isOutside() then
            local vehicle = addVehicleDebug(VEHICLE, IsoDirections.N, nil, square)
            if vehicle and vehicle:getId() ~= -1 then
                return vehicle
            end
        end
    end
end

-- The maintainer option shows only when the character carries one, and attaching needs it.
test("renewable_energy_client_maintainer_menu", {
    run = function(self)
        local square = player():getSquare()
        self.vehicle = square and spawnVehicleNear(square)
    end,
    validate = function(self)
        if not expect(self.vehicle ~= nil, "no room for a vehicle") then return end
        local p = player()
        local context = newContext()
        expect(Menu.addVehicleOptions(0, context, self.vehicle) == nil, "a vehicle offers a maintainer to someone without one")
        local maintainer = p:getInventory():AddItem(RenewableEnergy.SolarMaintainer.ITEM)
        local option = Menu.addVehicleOptions(0, context, self.vehicle)
        expect(option ~= nil and option.name == getText("ContextMenu_RenewableEnergy_AttachMaintainer"),
            "carrying a maintainer offers no Attach option on a vehicle")
        expect(Action:new(p, Action.ATTACH_MAINTAINER, nil, nil, self.vehicle, maintainer):canPerform(),
            "attaching a carried maintainer is refused")
        expect(not Action:new(p, Action.DETACH_MAINTAINER, nil, nil, self.vehicle):canPerform(),
            "a vehicle without a maintainer offers to detach one")
        context:hideAndChildren()
    end,
    cleanup = removeAll,
})

-- Status window -------------------------------------------------------------------------------

local function headers(rows)
    local found = {}
    for _, r in ipairs(rows or {}) do
        if r.header then
            found[r.header] = true
        end
    end
    return found
end

local function hasLine(lines, text)
    for _, line in ipairs(lines or {}) do
        if line.text == text then
            return true
        end
    end
    return false
end

local function rowLabelled(rows, label)
    for _, r in ipairs(rows or {}) do
        if r.label == label then
            return r
        end
    end
end

local function openWindow(self, onTick)
    self.window = StatusWindow.open(0, self.bank)
    wait(30, onTick)
end

-- A bank with nothing in it still draws every section, and says it has no batteries.
test("renewable_energy_client_window_empty_bank", {
    run = function(self)
        local squares = outdoorSquares(self, 1)
        if #squares < 1 then return end
        self.bank = placeBank(self, squares[1], Sprites.batteryBoxWood)
        openWindow(self)
    end,
    validate = function(self)
        if not expect(self.window ~= nil, "no open ground for a bank") then return end
        local window = self.window
        expect((window.renderedFrames or 0) > 0, "the window never drew its rows")
        expect(window.status ~= nil, "the window shows no status")
        local found = headers(window.left)
        for _, key in ipairs({ "IGUI_RenewableEnergy_Power", "IGUI_RenewableEnergy_Drawing", "IGUI_RenewableEnergy_Storage",
            "IGUI_RenewableEnergy_Parts" }) do
            expect(found[getText(key)], "the window has no " .. key .. " section")
        end
        expect(hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_NoBatteries")), "an empty bank does not say it has no batteries")
        expect(hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_NoWorkingInverter")), "an empty bank does not say it has no inverter")
        expect(hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_StateOutdoors")), "a bank outdoors doesn't say it must go inside")
        expect(rowLabelled(window.left, getText("IGUI_RenewableEnergy_NoParts")) ~= nil, "an empty bank doesn't say nothing is wired in")
    end,
    cleanup = removeAll,
})

-- The window's lines follow the bank: the overload with its load and limit, the panel slots with
-- the controller count, what draws by kind, a broken part, a battery's repair, and a panel left
-- without a controller slot when its controller goes.
test("renewable_energy_client_window_reflects_status", {
    run = function(self)
        setGrid(self, false)
        self.bank = indoorBank(self, "batteryRackWood",
            { "Base.CarBattery1", "Base.CarBattery1", "RenewableEnergy.PlugInInverter", Specs.controller, "Base.CarBatteryCharger" }, 0.5)
        if not self.bank then return end
        local container = self.bank:getContainer()
        Wear.setCondition(container:getFirstType("Base.CarBatteryCharger"), 0)
        Wear.setCondition(container:getFirstType("Base.CarBattery1"), 70)
        for _ = 1, 3 do
            wiredPanel(self, self.bank, Sprites.rack.metal.S)
        end
        self.withController = PowerBank.getStatus(self.bank:getX(), self.bank:getY(), self.bank:getZ())
        self.withControllerSummary = self.withController and StatusWindow.summary(self.withController)
        local record = bankRecord(self.bank)
        container:Remove(container:getFirstType(Specs.controller))
        record.on = true
        record:update(1, passContext(1000))
        applyLoad(record, { "television", "light", "light", "fridge" })
        self.status = PowerBank.getStatus(self.bank:getX(), self.bank:getY(), self.bank:getZ())
    end,
    validate = function(self)
        if not expect(self.status ~= nil, "no indoor square for a bank") then return end
        expect(self.withControllerSummary ~= nil and hasLine(self.withControllerSummary,
            getText("IGUI_RenewableEnergy_PanelSlotsOneController", 3, Specs.freePanels + Specs.panelsPerController)),
            "the slots line doesn't read 3 panels of " .. (Specs.freePanels + Specs.panelsPerController) .. " with 1 controller")
        local status = self.status
        local summary = StatusWindow.summary(status)
        local load = Specs.loads.television.watts + 2 * Specs.loads.light.watts + Specs.loads.fridge.watts
        local limit = Specs.inverters["RenewableEnergy.PlugInInverter"].watts
        expect(hasLine(summary, getText("IGUI_RenewableEnergy_Overloaded", Format.watts(load), Format.watts(limit))),
            "the window doesn't say the bank is overloaded with " .. load .. " W on " .. limit .. " W")
        expect(hasLine(summary, getText("IGUI_RenewableEnergy_PanelSlots", 3, Specs.freePanels)),
            "without its controller the slots line doesn't read 3 panels of " .. Specs.freePanels)
        local left, right = StatusWindow.rows(status, position(self.bank))
        local lights = rowLabelled(left, getText("IGUI_RenewableEnergy_LoadCount", getText("IGUI_RenewableEnergy_LoadLight"), 2))
        expect(lights ~= nil and lights.value == Format.watts(2 * Specs.loads.light.watts), "the window doesn't list 2 lights and their watts")
        local charger = rowLabelled(left, getItemNameFromFullType("Base.CarBatteryCharger"))
        expect(charger ~= nil and charger.color == "bad" and charger.value == getText("IGUI_RenewableEnergy_PartBroken", "0%"),
            "a broken charger doesn't read broken (" .. tostring(charger and charger.value) .. ")")
        local repairs = {}
        for _, r in ipairs(right) do
            if r.label == getItemNameFromFullType("Base.CarBattery1") then
                table.insert(repairs, r.value)
            end
        end
        local recondition = getText("IGUI_RenewableEnergy_BatteryValueRepair", Format.percent(status.charge), "70%",
            getText("IGUI_RenewableEnergy_RepairRecondition"))
        local found = false
        for _, value in ipairs(repairs) do
            found = found or value == recondition
        end
        expect(found, "a battery at 70 condition doesn't suggest Recondition (" .. table.concat(repairs, "; ") .. ")")
        local panels = {}
        for _, r in ipairs(right) do
            if r.source then
                table.insert(panels, r)
            end
        end
        if not expect(#panels == 3, #panels .. " panel rows, expected 3") then return end
        local noSlot = getText("IGUI_RenewableEnergy_ReasonNoController")
        expect(panels[3].value:find(noSlot, 1, true) ~= nil and panels[3].color == "bad",
            "the panel past the slots reads " .. panels[3].value)
        expect(panels[1].value:find(noSlot, 1, true) == nil and status.sources[1].watts > 0,
            "a panel within the slots reads " .. panels[1].value)
        expect(panels[1].label:find(getText("IGUI_RenewableEnergy_MountRackMetal"), 1, true) ~= nil,
            "a metal rack's row reads " .. panels[1].label)
    end,
    cleanup = removeAll,
})

-- Clicking a panel's row highlights the panel in the world, until the window closes.
test("renewable_energy_client_window_highlights_panel", {
    run = function(self)
        self.bank = indoorBank(self, "batteryBoxWood", { "Base.CarBattery1" })
        if not self.bank then return end
        self.panel = wiredPanel(self, self.bank, Sprites.flat)
        openWindow(self)
    end,
    validate = function(self)
        if not expect(self.panel ~= nil, "no squares for a bank and a panel") then return end
        local window = self.window
        local row
        for _, r in ipairs(window.right or {}) do
            row = row or (r.source and r)
        end
        if not expect(row ~= nil and row.top ~= nil, "the window drew no panel row") then return end
        window:onMouseDown(window.rightLayout.x + 4, row.top + 2)
        expect(self.panel:isHighlighted(0), "clicking the panel's row didn't highlight it")
        window:close()
        expect(not self.panel:isHighlighted(0), "the panel stayed highlighted after the window closed")
    end,
    cleanup = removeAll,
})

local FULL_BANK = {
    "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery",
    "RenewableEnergy.L16Battery", "Base.CarBattery1", "RenewableEnergy.InverterCharger", "RenewableEnergy.PowerInverter",
    "RenewableEnergy.ChargeController", "RenewableEnergy.ChargeController", "Base.CarBatteryCharger",
}
local MODULE = "RenewableEnergy.SolarModule"
local FULL_BANK_SOURCES = {
    { sprite = Sprites.flat, modules = { { type = MODULE, condition = 100 } } },
    { sprite = Sprites.wall.wood.S, modules = { { type = MODULE, condition = 80 } } },
    { sprite = Sprites.rack.wood.S, modules = { { type = MODULE, condition = 100 }, { type = MODULE, condition = 20 } } },
    { sprite = Sprites.rack.metal.E, modules = { { type = MODULE, condition = 90 }, { type = MODULE, condition = 90 } } },
}

-- A working bank with batteries, inverters, controllers, a charger and panels lists every one
-- of them, and the screenshot (renewable_energy_status_window.png in the cache's Screenshots)
-- shows the layout.
test("renewable_energy_client_window_full_bank", {
    run = function(self)
        setGrid(self, false)
        self.bank = indoorBank(self, "batteryBankMetal", FULL_BANK, 0.7)
        if not self.bank then return end
        Wear.setCondition(self.bank:getContainer():getFirstType("RenewableEnergy.L16Battery"), 45)
        for _, source in ipairs(FULL_BANK_SOURCES) do
            wiredPanel(self, self.bank, source.sprite, source.modules)
        end
        local record = bankRecord(self.bank)
        record.on = true
        record:update(1, passContext(650))
        applyLoad(record, { "fridge", "television", "light", "light", "light", "radio" })
        openWindow(self, function(tick)
            if tick == 20 then
                getCore():TakeFullScreenshot("renewable_energy_status_window.png")
            end
        end)
    end,
    validate = function(self)
        if not expect(self.window ~= nil, "no indoor square for a bank and its panels") then return end
        local window = self.window
        local status = window.status
        expect((window.renderedFrames or 0) > 0, "the window never drew its rows")
        if not expect(status ~= nil, "the window shows no status") then return end
        expect(#status.batteries == 5, #status.batteries .. " batteries in the status, expected 5")
        expect(#status.sources == #FULL_BANK_SOURCES, #status.sources .. " panels in the status, expected " .. #FULL_BANK_SOURCES)
        local found = headers(window.right)
        expect(found[getText("IGUI_RenewableEnergy_Batteries", 5)], "the window does not list the 5 batteries")
        expect(found[getText("IGUI_RenewableEnergy_Panels", #FULL_BANK_SOURCES)], "the window does not list the panels")
        for _, fullType in ipairs({ "RenewableEnergy.InverterCharger", "RenewableEnergy.PowerInverter", Specs.controller, "Base.CarBatteryCharger" }) do
            expect(rowLabelled(window.left, getItemNameFromFullType(fullType)) ~= nil, "the window does not list the " .. fullType)
        end
        expect(window.switchButton.enable, "the switch is disabled on a bank with an inverter")
        expect(window.renameButton.enable, "the rename button is disabled")
    end,
    cleanup = removeAll,
})
