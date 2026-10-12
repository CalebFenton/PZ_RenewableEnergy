require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/RenewableEnergyMenu"
require "RenewableEnergy/UI/RenewableEnergyStatusWindow"

-- Menus, timed actions and the status window. See RenewableEnergyTestLib.lua for how the runner
-- works. Each test builds its own banks and panels on open ground next to the character and
-- removes them again, since world objects outlive a test.

local test = RenewableEnergyTest.test
local expect, expectNear, player = RenewableEnergyTest.expect, RenewableEnergyTest.expectNear, RenewableEnergyTest.player

local Action = RenewableEnergyAction
local Sprites = RenewableEnergy.Sprites
local PowerBank = RenewableEnergy.PowerBank
local Menu = RenewableEnergy.Menu
local StatusWindow = RenewableEnergy.StatusWindow

-- Fixtures ------------------------------------------------------------------------------------

-- Free outdoor squares around the character, nearest first, enough for `count` objects.
local function outdoorSquares(count)
    local p = player()
    local found = {}
    for radius = 1, 8 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = getSquare(p:getX() + dx, p:getY() + dy, p:getZ())
                    if square and square:isOutside() and square:isFree(false) and not square:getVehicleContainer() then
                        table.insert(found, square)
                        if #found == count then
                            return found
                        end
                    end
                end
            end
        end
    end
    return found
end

local function placeObject(square, spriteName)
    local object = IsoObject.new(square, spriteName, "RenewableEnergyTest")
    square:AddTileObject(object)
    return object
end

local function placeBank(square, spriteName)
    return PowerBank.place(square, spriteName or Sprites.batteryBank)
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

local function removeAll(self)
    for _, object in ipairs(self.objects or {}) do
        removeObject(object)
    end
    if self.vehicle then
        self.vehicle:permanentlyRemove()
    end
    local window = StatusWindow.windows[0]
    if window then
        window:close()
    end
end

local function position(object)
    return { x = object:getX(), y = object:getY(), z = object:getZ() }
end

local function samePosition(a, b)
    return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.z == b.z
end

-- Waits on the action queue for `ticks` ticks, so the runner validates only after the world has
-- caught up (statuses arrive a tick after a change) and the windows have drawn. `onTick(n)`
-- runs every tick.
local Wait = ISBaseTimedAction:derive("RenewableEnergyTestWait")

function Wait:isValid()
    return true
end

function Wait:update()
    self.ticks = self.ticks + 1
    if self.onTick then
        self.onTick(self.ticks)
    end
    if self.ticks >= self.total then
        self:forceComplete()
    end
end

function Wait:new(character, total, onTick)
    local o = ISBaseTimedAction.new(self, character)
    o.total = total
    o.onTick = onTick
    o.ticks = 0
    o.stopOnWalk = false
    o.stopOnRun = false
    o.stopOnAim = false
    o.maxTime = -1
    return o
end

local function wait(total, onTick)
    ISTimedActionQueue.add(Wait:new(player(), total, onTick))
end

local function optionNamed(menu, name)
    return menu and menu:getOptionFromName(name)
end

local function hasEnabledOption(menu)
    for _, option in ipairs(menu and menu.options or {}) do
        if option.onSelect and not option.notAvailable then
            return true
        end
    end
    return false
end

-- Menus ---------------------------------------------------------------------------------------

-- A bank's menu lists its window, its switch and the panels around it; vanilla's own generator
-- options (fuel, plug in) must not appear for it.
test("renewable_energy_client_menu_bank", {
    run = function(self)
        local squares = outdoorSquares(1)
        if #squares < 1 then return end
        self.bank = placeBank(squares[1])
        self.objects = { self.bank }
        wait(5)
    end,
    validate = function(self)
        if not expect(self.bank ~= nil, "no open ground for a bank next to the character") then return end
        local fetch = ISWorldObjectContextMenu.fetchVars
        fetch.generator = self.bank
        local context = ISContextMenu.get(0, 0, 0)
        Menu.onPreFill(0, context, { self.bank }, false)
        expect(fetch.generator == nil, "the bank stayed in fetchVars.generator, so vanilla offers generator options for it")
        Menu.onFill(0, context, { self.bank }, false)
        local option = optionNamed(context, Menu.nameOf(self.bank))
        expect(option ~= nil and option.subOption ~= nil, "right-clicking a bank shows no bank submenu")
        local submenu = Menu.addBankOptions(0, context, self.bank)
        expect(optionNamed(submenu, getText("ContextMenu_RenewableEnergy_Status")) ~= nil, "the bank menu has no status option")
        local turnOn = optionNamed(submenu, getText("ContextMenu_Turn_On"))
        expect(turnOn ~= nil, "a bank that is off offers no Turn On")
        expect(turnOn == nil or turnOn.notAvailable, "a bank without an inverter offers to turn on")
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
        local context = ISContextMenu.get(0, 0, 0)
        local before = context.numOptions
        Menu.onFill(0, context, { floor }, false)
        expect(context.numOptions == before, "a plain floor got " .. (context.numOptions - before) .. " options")
        context:hideAndChildren()
    end,
})

-- A panel with no bank in reach says why it can't be connected rather than offering nothing.
test("renewable_energy_client_menu_panel_without_bank", {
    run = function(self)
        local squares = outdoorSquares(1)
        if #squares < 1 then return end
        self.panel = placeObject(squares[1], Sprites.flat)
        self.objects = { self.panel }
    end,
    validate = function(self)
        if not expect(self.panel ~= nil, "no open ground for a panel next to the character") then return end
        if not expect(#PowerBank.banksInReach(self.panel:getX(), self.panel:getY(), self.panel:getZ()) == 0,
            "a bank left by an earlier run is in reach") then return end
        local context = ISContextMenu.get(0, 0, 0)
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
        local squares = outdoorSquares(2)
        if #squares < 2 then return end
        self.bank = placeBank(squares[1])
        self.panel = placeObject(squares[2], Sprites.rack.S)
        self.objects = { self.bank, self.panel }
        wait(5)
    end,
    validate = function(self)
        if not expect(self.panel ~= nil, "no open ground for a bank and a panel") then return end
        local context = ISContextMenu.get(0, 0, 0)
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

-- Actions -------------------------------------------------------------------------------------

local CONNECT_MINUTES = 4

-- Connecting goes through the bank: afterwards the bank lists the panel. The sandbox option is in
-- in-game minutes, and the action takes that long at Electricity 3.
test("renewable_energy_client_connect_panel", {
    sandbox = { ConnectPanelMin = CONNECT_MINUTES },
    run = function(self)
        local p = player()
        local squares = outdoorSquares(2)
        if #squares < 2 then return end
        self.bank = placeBank(squares[1])
        self.panel = placeObject(squares[2], Sprites.flat)
        self.objects = { self.bank, self.panel }
        self.prevLevel = p:getPerkLevel(Perks.Electricity)
        p:setPerkLevelDebug(Perks.Electricity, 3)
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
    cleanup = function(self)
        removeAll(self)
        if self.prevLevel then player():setPerkLevelDebug(Perks.Electricity, self.prevLevel) end
    end,
})

test("renewable_energy_client_disconnect_panel", {
    sandbox = { ConnectPanelMin = 1 },
    run = function(self)
        local p = player()
        local squares = outdoorSquares(2)
        if #squares < 2 then return end
        self.bank = placeBank(squares[1])
        self.panel = placeObject(squares[2], Sprites.wall.S)
        self.objects = { self.bank, self.panel }
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
        local squares = outdoorSquares(2)
        if #squares < 2 then return end
        self.flat = placeObject(squares[1], Sprites.flat)
        self.wall = placeObject(squares[2], Sprites.wall.E)
        self.objects = { self.flat, self.wall }
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

local function describeVehicle(vehicle, bank)
    local square = vehicle:getSquare()
    return string.format("vehicle id %d at %.1f,%.1f,%.1f, bank at %d,%d, own square holds it: %s",
        vehicle:getId(), vehicle:getX(), vehicle:getY(), vehicle:getZ(), bank:getX(), bank:getY(),
        tostring(square ~= nil and square:getVehicleContainer() == vehicle))
end

-- A vehicle beside a bank: the bank's menu offers it, and connecting needs a full set of wire.
test("renewable_energy_client_vehicle_needs_wire", {
    run = function(self)
        local squares = outdoorSquares(1)
        if #squares < 1 then return end
        self.bank = placeBank(squares[1])
        self.objects = { self.bank }
        self.vehicle = spawnVehicleNear(self.bank)
        wait(5)
    end,
    validate = function(self)
        if not expect(self.bank ~= nil and self.vehicle ~= nil, "no room for a bank and a vehicle") then return end
        local p = player()
        local inRange = Menu.vehiclesInReach(self.bank)
        expect(#inRange == 1 and inRange[1] == self.vehicle,
            "the bank's menu does not find the vehicle beside it (" .. describeVehicle(self.vehicle, self.bank) .. ")")
        local connect = Action:new(p, Action.CONNECT_VEHICLE, nil, self.bank, self.vehicle)
        local inventory = p:getInventory()
        for _ = 2, PowerBank.VEHICLE_WIRE_COUNT do
            inventory:AddItem(PowerBank.VEHICLE_WIRE)
        end
        expect(not connect:canPerform(), "a vehicle can be connected with one length of wire too few")
        local context = ISContextMenu.get(0, 0, 0)
        local submenu = Menu.addBankOptions(0, context, self.bank)
        local option = optionNamed(submenu, getText("ContextMenu_RenewableEnergy_ConnectVehicle", Menu.vehicleName(self.vehicle)))
        expect(option ~= nil and option.notAvailable, "without enough wire the vehicle is not offered as unavailable")
        context:hideAndChildren()
        inventory:AddItem(PowerBank.VEHICLE_WIRE)
        expect(connect:canPerform(), "a vehicle beside the bank can't be connected with enough wire")
    end,
    cleanup = removeAll,
})

-- The maintainer option shows only when the character carries one, and attaching needs it.
test("renewable_energy_client_maintainer_menu", {
    run = function(self)
        local square = player():getSquare()
        self.vehicle = square and spawnVehicleNear(square)
    end,
    validate = function(self)
        if not expect(self.vehicle ~= nil, "no room for a vehicle") then return end
        local p = player()
        local context = ISContextMenu.get(0, 0, 0)
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

local function openWindow(self, onTick)
    self.window = StatusWindow.open(0, self.bank)
    wait(30, onTick)
end

-- A bank with nothing in it still draws every section, and says it has no batteries.
test("renewable_energy_client_window_empty_bank", {
    run = function(self)
        local squares = outdoorSquares(1)
        if #squares < 1 then return end
        self.bank = placeBank(squares[1], Sprites.batteryBox)
        self.objects = { self.bank }
        openWindow(self)
    end,
    validate = function(self)
        if not expect(self.window ~= nil, "no open ground for a bank") then return end
        local window = self.window
        expect((window.renderedFrames or 0) > 0, "the window never drew its rows")
        expect(window.status ~= nil, "the window shows no status")
        local found = headers(window.left)
        for _, key in ipairs({ "IGUI_RenewableEnergy_Power", "IGUI_RenewableEnergy_Storage", "IGUI_RenewableEnergy_Inverter" }) do
            expect(found[getText(key)], "the window has no " .. key .. " section")
        end
        local noBatteries = false
        for _, r in ipairs(window.left or {}) do
            noBatteries = noBatteries or r.value == getText("IGUI_RenewableEnergy_NoBatteries")
        end
        expect(noBatteries, "an empty bank does not say it has no batteries")
        expect(not window.resetButton.enable, "Reset is enabled on a bank with no inverter")
    end,
    cleanup = removeAll,
})

local FULL_BANK = {
    "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery",
    "RenewableEnergy.L16Battery", "Base.CarBattery1", "RenewableEnergy.PowerInverter",
    "RenewableEnergy.ChargeController", "RenewableEnergy.ChargeController",
}
local FULL_BANK_SOURCES = { Sprites.flat, Sprites.wall.S, Sprites.rack.S, Sprites.rack.E }

-- A bank with batteries, an inverter, controllers and panels lists every one of them, and the
-- screenshot (renewable_energy_status_window.png in the cache's Screenshots) shows the layout.
test("renewable_energy_client_window_full_bank", {
    run = function(self)
        local p = player()
        local squares = outdoorSquares(1 + #FULL_BANK_SOURCES)
        if #squares < 1 + #FULL_BANK_SOURCES then return end
        self.bank = placeBank(squares[1])
        self.objects = { self.bank }
        local container = self.bank:getContainer()
        for _, fullType in ipairs(FULL_BANK) do
            container:AddItem(fullType)
        end
        for i, spriteName in ipairs(FULL_BANK_SOURCES) do
            local panel = placeObject(squares[i + 1], spriteName)
            table.insert(self.objects, panel)
            PowerBank.perform(p, "connectSource", { bank = position(self.bank), source = position(panel) })
        end
        PowerBank.perform(p, "refresh", { bank = position(self.bank) })
        openWindow(self, function(tick)
            if tick == 20 then
                getCore():TakeFullScreenshot("renewable_energy_status_window.png")
            end
        end)
    end,
    validate = function(self)
        if not expect(self.window ~= nil, "no open ground for a bank and its panels") then return end
        local window = self.window
        local status = window.status
        expect((window.renderedFrames or 0) > 0, "the window never drew its rows")
        if not expect(status ~= nil, "the window shows no status") then return end
        expect(#status.batteries == 5, #status.batteries .. " batteries in the status, expected 5")
        expect(#status.sources == #FULL_BANK_SOURCES, #status.sources .. " panels in the status, expected " .. #FULL_BANK_SOURCES)
        local found = headers(window.right)
        expect(found[getText("IGUI_RenewableEnergy_Batteries", 5)], "the window does not list the 5 batteries")
        expect(found[getText("IGUI_RenewableEnergy_Panels", #FULL_BANK_SOURCES)], "the window does not list the panels")
        local model = false
        for _, r in ipairs(window.left or {}) do
            model = model or r.value == getItemNameFromFullType("RenewableEnergy.PowerInverter")
        end
        expect(model, "the window does not name the inverter")
        expect(window.switchButton.enable, "the switch is disabled on a bank with an inverter")
    end,
    cleanup = removeAll,
})
