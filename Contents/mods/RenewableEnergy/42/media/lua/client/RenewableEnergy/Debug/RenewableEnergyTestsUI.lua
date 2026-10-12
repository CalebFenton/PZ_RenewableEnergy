require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/Menu"
require "RenewableEnergy/UI/StatusWindow"

-- The right-click menus, the actions they start and the status window. The wiring and repair
-- rules belong to the authority's tests in RenewableEnergyTestsPower.lua; these check what the UI
-- adds: the option, the reason it shows, and the action it queues. See RenewableEnergyTestLib.lua
-- for the runner and the helpers.

local T = RenewableEnergyTest
local test, expect, expectNear, player = T.test, T.expect, T.expectNear, T.player

local Action = RenewableEnergyAction
local Specs = RenewableEnergy.Specs
local Sprites = RenewableEnergy.Sprites
local PowerBank = RenewableEnergy.PowerBank
local Wear = RenewableEnergy.Wear
local Format = RenewableEnergy.Format
local Menu = RenewableEnergy.Menu
local StatusWindow = RenewableEnergy.StatusWindow

-- The longest a test waits for a bank's status to reach the client's copy.
local STATUS_FRAMES = 10
-- The longest a test waits for the status window to draw.
local DRAW_FRAMES = 30

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

-- The option in `menu` that acts on `item` (the bank part menus pass it as the third parameter).
local function optionFor(menu, item)
    for _, option in ipairs(menu and menu.options or {}) do
        if option.param3 == item then
            return option
        end
    end
end

-- Chooses an option the way a click does.
local function choose(option)
    option.onSelect(option.target, option.param1, option.param2, option.param3, option.param4)
end

local function newContext()
    return ISContextMenu.get(0, 0, 0)
end

local function waitForStatus(bank)
    T.waitUntil(function() return PowerBank.statusOf(bank) ~= nil end, STATUS_FRAMES)
end

-- Menus ---------------------------------------------------------------------------------------

-- Right-clicking a bank in the world builds the bank's submenu through vanilla's own menu
-- builder and its menu events, without vanilla's generator submenu (fuel, plug in), which would
-- otherwise show for the bank's IsoGenerator.
test("renewable_energy_ui_context_menu_opens_bank_menu", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if self.bank then waitForStatus(self.bank) end
    end,
    validate = function(self)
        local context = ISWorldObjectContextMenu.createMenu(0, { self.bank }, 0, 0)
        if not expect(type(context) == "table", "right-clicking a bank built no menu") then return end
        local option = optionNamed(context, Menu.bankLabel(self.bank))
        expect(option ~= nil and option.subOption ~= nil, "right-clicking a bank shows no bank submenu")
        expect(optionNamed(context, getText("ContextMenu_Generator")) == nil, "right-clicking a bank shows vanilla's generator submenu")
        context:hideAndChildren()
    end,
})

-- A bank's submenu lists its window, its switch, renaming and wiring.
test("renewable_energy_ui_menu_bank", {
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        if self.bank then waitForStatus(self.bank) end
    end,
    validate = function(self)
        local context = newContext()
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
        context:hideAndChildren()
    end,
})

-- Objects that aren't the mod's add nothing to the menu.
test("renewable_energy_ui_menu_ignores_other_objects", {
    validate = function(self)
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

-- A panel offers to connect only to a bank in reach: with none, the option is there but
-- unavailable and says why; with one, the option connects to it.
test("renewable_energy_ui_menu_panel_connect", {
    run = function(self)
        local panel = T.panel(self, Sprites.rack.wood.S)
        if not panel then return end
        self.panel = panel
        self.banksBefore = #PowerBank.banksInReach(panel:getX(), panel:getY(), panel:getZ())
        local context = newContext()
        local submenu = Menu.addSourceOptions(0, context, panel)
        local option = optionNamed(submenu, getText("ContextMenu_RenewableEnergy_ConnectToBank"))
        self.alone = { offered = option ~= nil, unavailable = option ~= nil and option.notAvailable,
            reason = tooltipOf(option), enabled = hasEnabledOption(submenu) }
        context:hideAndChildren()
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true, near = panel })
        if self.bank then waitForStatus(self.bank) end
    end,
    validate = function(self)
        local panel, alone = self.panel, self.alone
        if expect(self.banksBefore == 0, "a bank left by an earlier test is in reach of the panel") then
            expect(alone.offered and alone.unavailable, "a panel with no bank in reach shows no unavailable connect option")
            expect(alone.reason == getText("Tooltip_RenewableEnergy_NoBankInReach"),
                "the unavailable connect option says " .. tostring(alone.reason))
            expect(not alone.enabled, "a panel with no bank in reach offers something to do")
        end
        local context = newContext()
        local submenu = Menu.addSourceOptions(0, context, panel)
        local here, bankPosition = PowerBank.positionOf(panel), PowerBank.positionOf(self.bank)
        local connect = optionNamed(submenu, getText("ContextMenu_RenewableEnergy_ConnectPanel", Menu.bankLabel(self.bank),
            Format.away(here, bankPosition)))
        expect(connect ~= nil and not connect.notAvailable, "a panel next to a bank offers no connection to it")
        expect(optionNamed(submenu, getText("ContextMenu_RenewableEnergy_DisconnectPanel")) == nil,
            "a panel that isn't connected offers to disconnect")
        context:hideAndChildren()
    end,
})

-- A connected panel names its bank, by the name a player gave it, and how far away it stands.
test("renewable_energy_ui_menu_panel_wired_to", {
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        if not self.bank then return end
        self.panel = T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        PowerBank.perform(player(), "rename", { bank = PowerBank.positionOf(self.bank), name = "Shed Bank" })
    end,
    validate = function(self)
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
        expect(wiredTo ~= nil, "a connected panel's menu doesn't name its renamed bank")
        expect(wiredTo == nil or wiredTo:find(tostring(tiles), 1, true) ~= nil,
            "the panel menu says " .. tostring(wiredTo) .. ", but the bank is " .. tiles .. " tiles away")
        context:hideAndChildren()
    end,
})

-- Wire In offers each carried part type once, shows why one can't go in, and offers it once it
-- can.
test("renewable_energy_ui_menu_wire_in_options", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {})
    end,
    validate = function(self)
        local inventory = player():getInventory()
        inventory:AddItem("Base.CarBattery2")
        inventory:AddItem("Base.CarBattery2")
        local inverter = inventory:AddItem("RenewableEnergy.PlugInInverter")
        local context = newContext()
        local menu = Menu.addWireInOptions(0, context, self.bank)
        local batteries = 0
        for _, option in ipairs(menu.options or {}) do
            if option.name == getItemNameFromFullType("Base.CarBattery2") then
                batteries = batteries + 1
            end
        end
        expectNear("Wire In options for two batteries of one type", batteries, 1, 0)
        local plugIn = optionFor(menu, inverter)
        local needScrewdriver = getText("Tooltip_RenewableEnergy_NeedTool", getItemNameFromFullType("Base.Screwdriver"))
        expect(plugIn ~= nil and plugIn.notAvailable and tooltipOf(plugIn) == needScrewdriver,
            "Wire In doesn't say an inverter needs a screwdriver (" .. tostring(tooltipOf(plugIn)) .. ")")
        inventory:AddItem("Base.Screwdriver")
        inventory:AddItems(PowerBank.WIRE, PowerBank.wiringFor(inverter:getFullType()).wire)
        plugIn = optionFor(Menu.addWireInOptions(0, context, self.bank), inverter)
        expect(plugIn ~= nil and not plugIn.notAvailable, "with a screwdriver and wire, the inverter can't be wired in ("
            .. tostring(tooltipOf(plugIn)) .. ")")
        context:hideAndChildren()
    end,
})

-- In the dark nothing can be wired in or out: the menu says why, the action won't start, and
-- the authority refuses it too.
test("renewable_energy_ui_wiring_refused_in_the_dark", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PowerInverter" })
        if self.bank then T.makeDark(self) end
    end,
    validate = function(self)
        local p = player()
        if not expect(p:tooDarkToRead(), "midnight with the grid off isn't dark where the character stands") then return end
        local inventory = p:getInventory()
        local battery = inventory:AddItem("Base.CarBattery2")
        inventory:AddItem("Base.Wrench")
        inventory:AddItem(PowerBank.WIRE)
        local context = newContext()
        local wireIn = optionFor(Menu.addWireInOptions(0, context, self.bank), battery)
        local dark = getText("Tooltip_RenewableEnergy_TooDark")
        expect(wireIn ~= nil and wireIn.notAvailable and tooltipOf(wireIn) == dark,
            "Wire In doesn't say it's too dark (" .. tostring(tooltipOf(wireIn)) .. ")")
        local unwire = Menu.addUnwireOptions(0, context, self.bank)
        local allDark = unwire ~= nil and #unwire.options > 0
        for _, option in ipairs(unwire and unwire.options or {}) do
            allDark = allDark and option.notAvailable and tooltipOf(option) == dark
        end
        expect(allDark, "a part can be unwired in the dark")
        context:hideAndChildren()
        expect(not Action:new(p, Action.WIRE_IN, nil, self.bank, nil, battery):isValid(), "the Wire In action runs in the dark")
        local wired, reason = PowerBank.perform(p, "wireIn", { bank = PowerBank.positionOf(self.bank), itemId = battery:getID() })
        expect(not wired and reason == "Tooltip_RenewableEnergy_TooDark", "the authority wired a battery in in the dark ("
            .. tostring(reason) .. ")")
    end,
})

-- Repair offers each inverter, says what a repair lacks, and once it has it, walks over and
-- mends the inverter in place with one scrap.
test("renewable_energy_ui_repair_part", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { "RenewableEnergy.PowerInverter" }, { outdoors = true })
        if not self.bank then return end
        self.inverter = self.bank:getContainer():getFirstType("RenewableEnergy.PowerInverter")
        Wear.setCondition(self.inverter, 50)
        local context = newContext()
        local option = optionFor(Menu.addRepairOptions(0, context, self.bank), self.inverter)
        self.withoutScrap = { unavailable = option ~= nil and option.notAvailable, reason = tooltipOf(option) }
        player():getInventory():AddItem(PowerBank.SCRAP)
        option = optionFor(Menu.addRepairOptions(0, context, self.bank), self.inverter)
        context:hideAndChildren()
        self.offered = option ~= nil and not option.notAvailable
        if self.offered then
            choose(option)
        end
    end,
    validate = function(self)
        local needScrap = getText("Tooltip_RenewableEnergy_NeedScrap", 1, getItemNameFromFullType(PowerBank.SCRAP))
        expect(self.withoutScrap.unavailable and self.withoutScrap.reason == needScrap,
            "Repair doesn't say it needs scrap (" .. tostring(self.withoutScrap.reason) .. ")")
        if not expect(self.offered, "with scrap in hand, Repair isn't offered for a worn inverter") then return end
        -- A repair mends 10 points.
        expectNear("inverter condition after the repair", self.inverter:getCondition(), 60, 0)
        expectNear("scrap left", player():getInventory():getCountTypeRecurse(PowerBank.SCRAP), 0, 0)
        expect(self.bank:getContainer():contains(self.inverter), "repairing took the inverter out of the bank")
    end,
})

-- Actions -------------------------------------------------------------------------------------

local CONNECT_MINUTES = 4
-- Game speed while connecting: an action and the clock speed up alike, so the in-game minutes
-- stay what they measure, and a tick stays a small part of a minute.
local CONNECT_SPEED = 10

local INSTANT_OFF = "the debug option Cheats > Timed Action > Instant off, which makes every action instant"

local function worldMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

-- Connecting a panel takes the ConnectPanelMin sandbox option's in-game minutes at Electricity
-- 3, from the moment the action starts, and leaves the bank listing the panel. The runner
-- validates on the first tick the action queue is empty, so validate reads the clock at the end.
test("renewable_energy_ui_connect_panel", {
    sandbox = { ConnectPanelMin = CONNECT_MINUTES },
    run = function(self)
        local p = player()
        if not T.need(self, not p:isTimedActionInstant(), INSTANT_OFF) then return end
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank })
        if not self.panel then return end
        T.setPerk(self, Perks.Electricity, 3)
        T.setMultiplier(self, CONNECT_SPEED)
        local action = Action:new(p, Action.CONNECT_SOURCE, self.panel, self.bank)
        self.action, self.valid = action, action:canPerform()
        T.onTick(self, function()
            if not self.started and action:isStarted() then
                self.started = worldMinutes()
            end
        end)
        ISTimedActionQueue.add(action)
    end,
    validate = function(self)
        expect(self.valid, "connecting a panel next to a bank is refused")
        expect(PowerBank.samePosition(Action.connectedBank(self.panel), PowerBank.positionOf(self.bank)),
            "the bank does not list the connected panel")
        expect(not self.action:canPerform(), "a panel already on this bank can be connected again")
        if not expect(self.started ~= nil, "the connect action never started") then return end
        local elapsed = worldMinutes() - self.started
        expect(elapsed >= CONNECT_MINUTES * 0.95 and elapsed <= CONNECT_MINUTES * 1.05,
            string.format("connecting took %.2f in-game minutes, expected %d", elapsed, CONNECT_MINUTES))
    end,
})

test("renewable_energy_ui_disconnect_panel", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        if not self.bank then return end
        self.panel, self.connected = T.panel(self, Sprites.wall.wood.S, { near = self.bank, connect = true })
        if not self.panel then return end
        ISTimedActionQueue.add(Action:new(player(), Action.DISCONNECT_SOURCE, self.panel))
    end,
    validate = function(self)
        expect(self.connected, "the bank refused to connect a wall panel next to it")
        expect(Action.connectedBank(self.panel) == nil, "the panel is still connected after disconnecting it")
    end,
})

-- Clearing snow needs a broom or snow shovel in hand, and only flat panels hold snow.
test("renewable_energy_ui_clear_snow_requirements", {
    run = function(self)
        self.flat = T.panel(self, Sprites.flat)
        self.wall = T.panel(self, Sprites.wall.wood.E)
    end,
    validate = function(self)
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
})

-- Wire In from the menu walks over and wires the part into the bank, which then lists it and
-- offers to unwire it. Wiring takes about a quarter of the time at Electricity 10 as at 0. The
-- bank stands on the open ground next to the character, which a walk always reaches.
test("renewable_energy_ui_wire_in_and_unwire", {
    instant = true,
    run = function(self)
        local p = player()
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not self.bank then return end
        local inventory = p:getInventory()
        self.battery = inventory:AddItem("Base.CarBattery1")
        inventory:AddItem("Base.Wrench")
        inventory:AddItem(PowerBank.WIRE)
        -- An action takes its duration when it is made, so these two are made with the instant
        -- cheat off and never queued.
        p:setTimedActionInstantCheat(false)
        if not T.need(self, not p:isTimedActionInstant(), INSTANT_OFF) then return end
        local function wiringTime(level)
            T.setPerk(self, Perks.Electricity, level)
            return Action:new(p, Action.WIRE_IN, nil, self.bank, nil, self.battery).maxTime
        end
        self.unskilled, self.skilled = wiringTime(0), wiringTime(10)
        p:setTimedActionInstantCheat(true)
        local context = newContext()
        local option = optionFor(Menu.addWireInOptions(0, context, self.bank), self.battery)
        context:hideAndChildren()
        if not option or option.notAvailable then
            self.refused = tostring(tooltipOf(option))
            return
        end
        choose(option)
        local queue = ISTimedActionQueue.getTimedActionQueue(p).queue
        self.action = queue[#queue]
    end,
    validate = function(self)
        expectNear("wiring time at Electricity 10 over the time at 0", self.skilled / self.unskilled, 0.25, 0.03)
        if not expect(self.refused == nil, "Wire In was refused: " .. tostring(self.refused)) then return end
        expect(self.action ~= nil and self.action.mode == Action.WIRE_IN, "choosing Wire In queued no Wire In action")
        expect(self.bank:getContainer():contains(self.battery), "the wired battery isn't in the bank")
        local status = PowerBank.statusOf(self.bank)
        expect(status ~= nil and #status.batteries == 1, "the bank's status doesn't list the wired battery")
        local context = newContext()
        local unwire = optionFor(Menu.addUnwireOptions(0, context, self.bank), self.battery)
        expect(unwire ~= nil and not unwire.notAvailable, "the bank doesn't offer to unwire the battery wired in")
        context:hideAndChildren()
    end,
})

-- Renaming goes through the bank, shows in its menu and window, and an empty name gives the
-- tier's name back.
test("renewable_energy_ui_rename_bank", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryRackMetal", {})
        if not self.bank then return end
        ISTimedActionQueue.add(Action:new(player(), Action.RENAME, nil, self.bank, nil, nil, "  Cellar  "))
    end,
    validate = function(self)
        expect(Menu.bankLabel(self.bank) == "Cellar", "the renamed bank's menu reads " .. tostring(Menu.bankLabel(self.bank)))
        local window = StatusWindow.open(0, self.bank)
        window:setStatus(PowerBank.statusOf(self.bank))
        expect(window.title == "Cellar", "the window of the renamed bank is titled " .. tostring(window.title))
        window:close()
        local action = Action:new(player(), Action.RENAME, nil, self.bank, nil, nil, "")
        expect(action:canPerform() and action:complete(), "renaming to an empty name was refused")
        local tier = getItemNameFromFullType("RenewableEnergy.BatteryRackMetal")
        expect(Menu.bankLabel(self.bank) == tier, "an empty name left the bank called " .. tostring(Menu.bankLabel(self.bank)))
    end,
})

-- Maintainer ------------------------------------------------------------------------------------

-- The maintainer option shows only when the character carries one, and attaching needs it.
test("renewable_energy_ui_maintainer_menu", {
    run = function(self)
        self.vehicle = T.vehicle(self, "Base.PickUpTruck")
    end,
    validate = function(self)
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

-- Opens the bank's window, closed again when the test ends, and waits until it has drawn its
-- rows `frames` times.
local function openWindow(self, frames)
    local window = StatusWindow.open(0, self.bank)
    self.window = window
    T.defer(self, function() window:close() end)
    T.waitUntil(function() return (window.renderedFrames or 0) >= (frames or 1) end, DRAW_FRAMES)
end

-- A bank with nothing in it still draws every section, and says it has no batteries.
test("renewable_energy_ui_window_empty_bank", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if self.bank then openWindow(self) end
    end,
    validate = function(self)
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
})

-- The window's lines follow the bank: the overload with its load and limit, the panel slots with
-- the controller count, what draws by kind, a broken part, a battery's repair, and a panel left
-- without a controller slot when its controller goes.
test("renewable_energy_ui_window_reflects_status", {
    run = function(self)
        T.setGrid(self, false)
        local bank, record = T.bank(self, "batteryRackWood",
            { "Base.CarBattery1", "Base.CarBattery1", "RenewableEnergy.PlugInInverter", Specs.controller, "Base.CarBatteryCharger" },
            { charge = 0.5 })
        if not bank then return end
        self.bank = bank
        local container = bank:getContainer()
        Wear.setCondition(container:getFirstType("Base.CarBatteryCharger"), 0)
        Wear.setCondition(container:getFirstType("Base.CarBattery1"), 70)
        for _ = 1, 3 do
            T.panel(self, Sprites.rack.metal.S, { near = bank, connect = true })
        end
        local withController = PowerBank.statusOf(bank)
        self.withControllerSummary = withController and StatusWindow.summary(withController)
        container:Remove(container:getFirstType(Specs.controller))
        record.on = true
        record:update(1, T.passContext(1000))
        T.applyLoad(record, { "television", "light", "light", "fridge" })
        self.status = PowerBank.statusOf(bank)
    end,
    validate = function(self)
        expect(self.withControllerSummary ~= nil and hasLine(self.withControllerSummary,
            getText("IGUI_RenewableEnergy_PanelSlotsOneController", 3, Specs.freePanels + Specs.panelsPerController)),
            "the slots line doesn't read 3 panels of " .. (Specs.freePanels + Specs.panelsPerController) .. " with 1 controller")
        local status = self.status
        if not expect(status ~= nil, "the bank sent no status") then return end
        local summary = StatusWindow.summary(status)
        local load = Specs.loads.television.watts + 2 * Specs.loads.light.watts + Specs.loads.fridge.watts
        local limit = Specs.inverters["RenewableEnergy.PlugInInverter"].watts
        expect(hasLine(summary, getText("IGUI_RenewableEnergy_Overloaded", Format.watts(load), Format.watts(limit))),
            "the window doesn't say the bank is overloaded with " .. load .. " W on " .. limit .. " W")
        expect(hasLine(summary, getText("IGUI_RenewableEnergy_PanelSlots", 3, Specs.freePanels)),
            "without its controller the slots line doesn't read 3 panels of " .. Specs.freePanels)
        local left, right = StatusWindow.rows(status, PowerBank.positionOf(self.bank))
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
})

-- Clicking a panel's row highlights the panel in the world, until the window closes.
test("renewable_energy_ui_window_highlights_panel", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        if self.panel then openWindow(self) end
    end,
    validate = function(self)
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
-- Frames the window draws before the screenshot, so the shot shows it settled.
local SCREENSHOT_FRAMES = 5

-- A working bank with batteries, inverters, controllers, a charger and panels lists every one
-- of them, and the screenshot (renewable_energy_status_window.png in the cache's Screenshots)
-- shows the layout.
test("renewable_energy_ui_window_full_bank", {
    run = function(self)
        T.setGrid(self, false)
        local bank, record = T.bank(self, "batteryBankMetal", FULL_BANK, { charge = 0.7 })
        if not bank then return end
        self.bank = bank
        Wear.setCondition(bank:getContainer():getFirstType("RenewableEnergy.L16Battery"), 45)
        for _, source in ipairs(FULL_BANK_SOURCES) do
            T.panel(self, source.sprite, { near = bank, modules = source.modules, connect = true })
        end
        record.on = true
        record:update(1, T.passContext(650))
        T.applyLoad(record, { "fridge", "television", "light", "light", "light", "radio" })
        openWindow(self, SCREENSHOT_FRAMES)
        T.step(function() getCore():TakeFullScreenshot("renewable_energy_status_window.png") end)
        -- The shot is taken when the next frame is drawn.
        T.wait(2)
    end,
    validate = function(self)
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
})
