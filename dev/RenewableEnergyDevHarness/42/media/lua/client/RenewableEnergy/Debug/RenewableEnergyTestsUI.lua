require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/Menu"
require "RenewableEnergy/UI/Needs"
require "RenewableEnergy/UI/StatusWindow"

-- The right-click menus, the actions they start and the status window. The wiring and repair
-- rules belong to the authority's tests in RenewableEnergyTestsPower.lua; these check what the UI
-- adds: the option, the reason it shows, and the action it queues, on this client's copies of the
-- banks and panels the server holds, and that what the action does reaches the server and comes
-- back. See RenewableEnergyTestLib.lua for the runner and the helpers.

local T = RenewableEnergyTest
local test, expect, expectNear, player, stateItem, copyItem = T.test, T.expect, T.expectNear, T.player, T.stateItem, T.copyItem

local Action = RenewableEnergyAction
local Specs = RenewableEnergy.Specs
local Sprites = RenewableEnergy.Sprites
local PowerBank = RenewableEnergy.PowerBank
local Format = RenewableEnergy.Format
local Menu = RenewableEnergy.Menu
local Needs = RenewableEnergy.Needs
local StatusWindow = RenewableEnergy.StatusWindow

local POWER_INVERTER = "RenewableEnergy.PowerInverter"

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

-- The option in `menu` that acts on `item` (the bank part menus pass it as the third parameter),
-- by id, since a server's sync can replace this client's item objects.
local function optionFor(menu, item)
    for _, option in ipairs(menu and menu.options or {}) do
        if instanceof(option.param3, "InventoryItem") and option.param3:getID() == item:getID() then
            return option
        end
    end
end

local function newContext()
    return ISContextMenu.get(0, 0, 0)
end

-- Menus ---------------------------------------------------------------------------------------

-- Right-clicking a bank in the world builds the bank's submenu through vanilla's own menu
-- builder and its menu events, without vanilla's generator submenu (fuel, plug in), which would
-- otherwise show for the bank's IsoGenerator.
test("renewable_energy_ui_context_menu_opens_bank_menu", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
    end,
    validate = function(self)
        local bank = self.bank.object
        local context = ISWorldObjectContextMenu.createMenu(0, { bank }, 0, 0)
        if not expect(type(context) == "table", "right-clicking a bank built no menu") then return end
        local option = optionNamed(context, Menu.bankLabel(bank))
        expect(option ~= nil and option.subOption ~= nil, "right-clicking a bank shows no bank submenu")
        expect(optionNamed(context, getText("ContextMenu_Generator")) == nil, "right-clicking a bank shows vanilla's generator submenu")
        context:hideAndChildren()
    end,
})

-- A bank's submenu lists its window, its switch, renaming and wiring.
test("renewable_energy_ui_menu_bank", {
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
    end,
    validate = function(self)
        local context = newContext()
        local submenu = Menu.addBankOptions(0, context, self.bank.object)
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
        self.panel = T.panel(self, Sprites.rack.wood.S)
        if not self.panel then return end
        T.step(function()
            local panel = self.panel.object
            self.banksBefore = #PowerBank.banksInReach(panel:getX(), panel:getY(), panel:getZ())
            local context = newContext()
            local submenu = Menu.addSourceOptions(0, context, panel)
            local option = optionNamed(submenu, getText("ContextMenu_RenewableEnergy_ConnectToBank"))
            self.alone = { offered = option ~= nil, unavailable = option ~= nil and option.notAvailable,
                reason = tooltipOf(option), enabled = hasEnabledOption(submenu) }
            context:hideAndChildren()
        end)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true, near = self.panel })
    end,
    validate = function(self)
        local panel, alone = self.panel.object, self.alone
        if expect(self.banksBefore == 0, "a bank left by an earlier test is in reach of the panel") then
            expect(alone.offered and alone.unavailable, "a panel with no bank in reach shows no unavailable connect option")
            expect(alone.reason == getText("Tooltip_RenewableEnergy_NoBankInReach"),
                "the unavailable connect option says " .. tostring(alone.reason))
            expect(not alone.enabled, "a panel with no bank in reach offers something to do")
        end
        local context = newContext()
        local submenu = Menu.addSourceOptions(0, context, panel)
        local connect = optionNamed(submenu, getText("ContextMenu_RenewableEnergy_ConnectPanel", Menu.bankLabel(self.bank.object),
            Format.away(self.panel.position, self.bank.position)))
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
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        if not self.panel then return end
        T.perform(self, "rename", { bank = self.bank.position, name = "Shed Bank" })
        T.waitForCopy(function()
            local summary = T.clientSummary(self.bank)
            return summary ~= nil and summary.name == "Shed Bank"
        end)
    end,
    validate = function(self)
        local context = newContext()
        local submenu = Menu.addSourceOptions(0, context, self.panel.object)
        local wiredTo
        for _, option in ipairs(submenu.options) do
            if option.name:find("Shed Bank", 1, true) then
                wiredTo = option.name
            end
        end
        local bank, panel = self.bank.position, self.panel.position
        local dx, dy = bank.x - panel.x, bank.y - panel.y
        local tiles = round(math.sqrt(dx * dx + dy * dy))
        expect(wiredTo ~= nil, "a connected panel's menu doesn't name its renamed bank")
        expect(wiredTo == nil or wiredTo:find(tostring(tiles), 1, true) ~= nil,
            "the panel menu says " .. tostring(wiredTo) .. ", but the bank is " .. tiles .. " tiles away")
        context:hideAndChildren()
    end,
})

-- Whether the tooltip's list of `needs` marks the need of `kind` as short (Needs.met).
local function marksShort(needs, kind)
    for _, need in ipairs(needs) do
        if need.kind == kind and not Needs.met(need) then
            return true
        end
    end
    return false
end

-- Wire In offers each carried part type once, greys out one that can't go in and marks what it
-- lacks as short, and offers it once it can.
test("renewable_energy_ui_menu_wire_in_options", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {})
        if not self.bank then return end
        T.give(self, "parts", { { type = "Base.CarBattery2", count = 2 }, { type = "RenewableEnergy.PlugInInverter" } })
        T.step(function()
            local context = newContext()
            local menu = Menu.addWireInOptions(0, context, self.bank.object)
            self.batteries = 0
            for _, option in ipairs(menu.options or {}) do
                if option.name == getItemNameFromFullType("Base.CarBattery2") then
                    self.batteries = self.batteries + 1
                end
            end
            local plugIn = optionFor(menu, self.items.parts[3])
            self.withoutTools = { unavailable = plugIn ~= nil and plugIn.notAvailable, reason = tooltipOf(plugIn),
                toolShort = marksShort(PowerBank.wiringNeeds(player(), "RenewableEnergy.PlugInInverter"), "tool") }
            context:hideAndChildren()
        end)
        local wire = PowerBank.wiringFor("RenewableEnergy.PlugInInverter").wire
        T.give(self, "tools", { { type = "Base.Screwdriver" }, { type = PowerBank.WIRE, count = wire } })
        T.step(function()
            local context = newContext()
            local plugIn = optionFor(Menu.addWireInOptions(0, context, self.bank.object), self.items.parts[3])
            self.withTools = { available = plugIn ~= nil and not plugIn.notAvailable, reason = tooltipOf(plugIn) }
            context:hideAndChildren()
        end)
    end,
    validate = function(self)
        expectNear("Wire In options for two batteries of one type", self.batteries, 1, 0)
        expect(self.withoutTools.unavailable and self.withoutTools.toolShort,
            "Wire In doesn't grey out an inverter and mark the screwdriver short (" .. tostring(self.withoutTools.reason) .. ")")
        expect(self.withTools.available, "with a screwdriver and wire, the inverter can't be wired in ("
            .. tostring(self.withTools.reason) .. ")")
    end,
})

-- In the dark nothing can be wired in or out: the menu greys them out and the action won't start.
-- In single player the authority refuses it too; a server can't tell whether a remote player
-- stands in the dark (IsoPlayer.tooDarkToRead), so in multiplayer the player's own side is what
-- refuses.
test("renewable_energy_ui_wiring_refused_in_the_dark", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", POWER_INVERTER })
        if not self.bank then return end
        T.give(self, "parts", { { type = "Base.CarBattery2" }, { type = "Base.Wrench" }, { type = PowerBank.WIRE } })
        T.makeDark(self)
        if not isClient() then
            T.perform(self, "wireIn", function()
                return { bank = self.bank.position, itemId = self.items.parts[1]:getID() }
            end)
        end
    end,
    validate = function(self)
        local p = player()
        if not expect(p:tooDarkToRead(), "midnight with the grid off isn't dark where the character stands") then return end
        local bank, battery = self.bank.object, self.items.parts[1]
        local context = newContext()
        local wireIn = optionFor(Menu.addWireInOptions(0, context, bank), battery)
        local dark = getText("Tooltip_RenewableEnergy_TooDark")
        expect(wireIn ~= nil and wireIn.notAvailable and PowerBank.wiringBlocker(p, bank, battery) == "Tooltip_RenewableEnergy_TooDark",
            "Wire In isn't greyed out for the dark (" .. tostring(tooltipOf(wireIn)) .. ")")
        local unwire = Menu.addUnwireOptions(0, context, bank)
        local allDark = unwire ~= nil and #unwire.options > 0
        for _, option in ipairs(unwire and unwire.options or {}) do
            allDark = allDark and option.notAvailable and tooltipOf(option) == dark
        end
        expect(allDark, "a part can be unwired in the dark")
        context:hideAndChildren()
        expect(not Action:new(p, Action.WIRE_IN, nil, bank, nil, battery):isValid(), "the Wire In action runs in the dark")
        local refused = self.server.perform
        if refused then
            expect(not refused.ok and refused.reason == "Tooltip_RenewableEnergy_TooDark",
                "the authority wired a battery in in the dark (" .. tostring(refused.reason) .. ")")
        end
    end,
})

-- Repair offers each inverter, greyed out and marking the scrap short while there is none, and
-- once there is, walks over and mends the inverter in place with one scrap, on the server and this
-- client's copy.
local WORN = 50
local REPAIRED = WORN + Specs.partRepair.condition
test("renewable_energy_ui_repair_part", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { POWER_INVERTER }, { outdoors = true })
        if not bank then return end
        self.bank = bank
        T.setPartCondition(self, bank, POWER_INVERTER, WORN)
        T.waitForCopy(function() return copyItem(bank, POWER_INVERTER):getCondition() == WORN end)
        T.step(function()
            local context = newContext()
            local option = optionFor(Menu.addRepairOptions(0, context, bank.object), copyItem(bank, POWER_INVERTER))
            self.withoutScrap = { unavailable = option ~= nil and option.notAvailable, reason = tooltipOf(option),
                scrapShort = marksShort(PowerBank.repairNeeds(player()), "scrap") }
            context:hideAndChildren()
        end)
        T.give(self, "scrap", { { type = PowerBank.SCRAP } })
        T.step(function()
            local context = newContext()
            local option = optionFor(Menu.addRepairOptions(0, context, bank.object), copyItem(bank, POWER_INVERTER))
            context:hideAndChildren()
            self.offered = option ~= nil and not option.notAvailable
            if not self.offered then return end
            T.choose(option)
            T.waitForCopy(function() return copyItem(bank, POWER_INVERTER):getCondition() == REPAIRED end)
            T.bankState(self, bank)
            T.count(self, "scrap", { PowerBank.SCRAP })
        end)
    end,
    validate = function(self)
        expect(self.withoutScrap.unavailable and self.withoutScrap.scrapShort,
            "Repair isn't greyed out with the scrap marked short (" .. tostring(self.withoutScrap.reason) .. ")")
        if not expect(self.offered, "with scrap in hand, Repair isn't offered for a worn inverter") then return end
        local inverter = stateItem(self.bank.state, POWER_INVERTER)
        if not expect(inverter ~= nil, "repairing took the inverter out of the bank") then return end
        expectNear("inverter condition after the repair", inverter.condition, REPAIRED, 0)
        expectNear("this client's copy of the inverter's condition", copyItem(self.bank, POWER_INVERTER):getCondition(), REPAIRED, 0)
        expectNear("scrap left", self.counts.scrap[PowerBank.SCRAP], 0, 0)
        expectNear("scrap left on this client", player():getInventory():getCountTypeRecurse(PowerBank.SCRAP), 0, 0)
    end,
})

-- Actions -------------------------------------------------------------------------------------

-- One in-game minute, the option's least: a multiplayer server times the action in real time at
-- normal speed (see connectSpeed), and 5% of a minute still dwarfs a round trip to a server on the
-- same machine.
local CONNECT_MINUTES = 1
-- Game speed while connecting: in single player an action and the clock speed up alike, so the
-- in-game minutes stay what they measure, and a tick stays a small part of a minute. A
-- multiplayer server times an action in real milliseconds whatever the game speed
-- (NetTimedAction.getDuration), so there it runs at normal speed.
local function connectSpeed()
    return isClient() and 1 or 10
end

local INSTANT_OFF = "the debug option Cheats > Timed Action > Instant off, which makes every action instant"

local function worldMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

-- Connecting a panel takes the ConnectPanelMin sandbox option's in-game minutes at Electricity
-- 3, from the moment the action starts to the moment it ends, and leaves the bank listing the
-- panel, on the server and in this client's status.
test("renewable_energy_ui_connect_panel", {
    sandbox = { ConnectPanelMin = CONNECT_MINUTES },
    run = function(self)
        local p = player()
        if not T.need(self, not p:isTimedActionInstant(), INSTANT_OFF) then return end
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank })
        if not self.panel then return end
        T.setPerk(self, Perks.Electricity, 3)
        T.step(function()
            T.setMultiplier(self, connectSpeed())
            local action = Action:new(p, Action.CONNECT_SOURCE, self.panel.object, self.bank.object)
            self.action, self.valid = action, action:canPerform()
            T.onTick(self, function()
                if not self.started and action:isStarted() then
                    self.started = worldMinutes()
                elseif self.started and not self.ended and ISTimedActionQueue.getTimedActionQueue(p).queue[1] ~= action then
                    self.ended = worldMinutes()
                end
            end)
            -- A player walks over first, as the menu does, and a multiplayer server refuses the job
            -- from afar; standing next to the panel leaves that walk no way to go.
            T.standNextTo(self.panel.square)
            if not T.need(self, luautils.walkAdj(p, self.panel.square, true), "a walk to the panel") then return end
            ISTimedActionQueue.add(action)
            T.waitForCopy(function()
                return PowerBank.samePosition(Action.connectedBank(self.panel.object), self.bank.position)
            end)
            T.bankState(self, self.bank)
        end)
    end,
    validate = function(self)
        expect(self.valid, "connecting a panel next to a bank is refused")
        expect(self.bank.state.sources == 1, "the server's bank lists " .. self.bank.state.sources .. " panels")
        expect(PowerBank.samePosition(Action.connectedBank(self.panel.object), self.bank.position),
            "this client's status of the bank does not list the connected panel")
        expect(not self.action:canPerform(), "a panel already on this bank can be connected again")
        if not expect(self.started ~= nil and self.ended ~= nil, "the connect action never started or ended") then return end
        local elapsed = self.ended - self.started
        expect(elapsed >= CONNECT_MINUTES * 0.95 and elapsed <= CONNECT_MINUTES * 1.05,
            string.format("connecting took %.2f in-game minutes, expected %d", elapsed, CONNECT_MINUTES))
    end,
})

test("renewable_energy_ui_disconnect_panel", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.wall.wood.S, { near = self.bank, connect = true })
        if not self.panel then return end
        T.step(function()
            T.standNextTo(self.panel.square)
            if not T.need(self, luautils.walkAdj(player(), self.panel.square, true), "a walk to the panel") then return end
            ISTimedActionQueue.add(Action:new(player(), Action.DISCONNECT_SOURCE, self.panel.object))
            T.waitForCopy(function() return Action.connectedBank(self.panel.object) == nil end)
            T.bankState(self, self.bank)
        end)
    end,
    validate = function(self)
        expect(self.panel.connected, "the bank refused to connect a wall panel next to it (" .. tostring(self.panel.reason) .. ")")
        expect(self.bank.state.sources == 0, "the server's bank still lists the panel after disconnecting it")
        expect(Action.connectedBank(self.panel.object) == nil, "this client still sees the panel connected after disconnecting it")
    end,
})

-- Clearing snow needs a broom or snow shovel in hand, and only flat panels hold snow.
test("renewable_energy_ui_clear_snow_requirements", {
    run = function(self)
        self.flat = T.panel(self, Sprites.flat)
        self.wall = T.panel(self, Sprites.wall.wood.E)
        T.give(self, "tools", { { type = "Base.Broom" }, { type = "Base.SnowShovel" }, { type = "Base.Hammer" } })
    end,
    validate = function(self)
        local p = player()
        local broom, shovel, hammer = self.items.tools[1], self.items.tools[2], self.items.tools[3]
        local function canClear(panel, tool)
            return Action:new(p, Action.CLEAR_SNOW, panel.object, nil, nil, tool):canPerform()
        end
        expect(not canClear(self.flat, broom), "snow can be cleared with a broom left in the bag")
        p:setPrimaryHandItem(broom)
        expect(canClear(self.flat, broom), "a broom in hand can't clear a flat panel")
        expect(not canClear(self.wall, broom), "a wall panel, which holds no snow, can be cleared")
        -- Where the game breaks items (single player; a multiplayer client leaves it to the server),
        -- a broom that breaks in hand splinters as one broken in a fight does (OnBreak.LongStick),
        -- dropping splinters at the character's feet, which go again.
        local feet = p:getSquare()
        local lying, dropped = {}, feet:getWorldObjects()
        for i = 0, dropped:size() - 1 do
            lying[dropped:get(i)] = true
        end
        broom:setCondition(0)
        for i = dropped:size() - 1, 0, -1 do
            local object = dropped:get(i)
            if not lying[object] then
                feet:removeWorldObject(object)
            end
        end
        expect(not canClear(self.flat, broom), "a broken broom can clear snow")
        p:setPrimaryHandItem(shovel)
        expect(canClear(self.flat, shovel), "a snow shovel in hand can't clear a flat panel")
        p:setPrimaryHandItem(hammer)
        expect(not canClear(self.flat, hammer), "a hammer clears snow")
        p:setPrimaryHandItem(nil)
    end,
})

-- Wire In from the menu walks over and wires the part into the bank, on the server and in this
-- client's copy, which then lists it and offers to unwire it. Wiring takes about a quarter of the
-- time at Electricity 10 as at 0. The bank stands on the open ground next to the character, which
-- a walk always reaches.
test("renewable_energy_ui_wire_in_and_unwire", {
    instant = true,
    run = function(self)
        local p = player()
        local bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.give(self, "parts", { { type = "Base.CarBattery1" }, { type = "Base.Wrench" }, { type = PowerBank.WIRE } })
        T.step(function()
            local battery = self.items.parts[1]
            self.batteryId = battery:getID()
            -- An action takes its duration when it is made, so these two are made with the instant
            -- cheat off and never queued.
            p:setTimedActionInstantCheat(false)
            if not T.need(self, not p:isTimedActionInstant(), INSTANT_OFF) then return end
            local function wiringTime(level)
                T.setPerk(self, Perks.Electricity, level)
                return Action:new(p, Action.WIRE_IN, nil, bank.object, nil, battery).maxTime
            end
            self.unskilled, self.skilled = wiringTime(0), wiringTime(10)
            p:setTimedActionInstantCheat(true)
            local context = newContext()
            local option = optionFor(Menu.addWireInOptions(0, context, bank.object), battery)
            context:hideAndChildren()
            if not option or option.notAvailable then
                self.refused = tostring(tooltipOf(option))
                return
            end
            T.choose(option)
            local queue = ISTimedActionQueue.getTimedActionQueue(p).queue
            self.action = queue[#queue]
            T.waitForCopy(function()
                local status = T.clientStatus(bank)
                return bank.object:getContainer():getItemWithID(self.batteryId) ~= nil and status ~= nil and #status.batteries == 1
            end)
            T.bankState(self, bank)
        end)
    end,
    validate = function(self)
        expectNear("wiring time at Electricity 10 over the time at 0", self.skilled / self.unskilled, 0.25, 0.03)
        if not expect(self.refused == nil, "Wire In was refused: " .. tostring(self.refused)) then return end
        local bank = self.bank.object
        expect(self.action ~= nil and self.action.mode == Action.WIRE_IN, "choosing Wire In queued no Wire In action")
        if not expect(self.bank.state ~= nil, "the queue stopped before the server's bank was read") then return end
        local held = {}
        for _, item in ipairs(self.bank.state.items) do
            table.insert(held, item.type)
        end
        expect(stateItem(self.bank.state, "Base.CarBattery1") ~= nil, "the wired battery isn't in the server's bank, which holds "
            .. (#held > 0 and table.concat(held, ", ") or "nothing"))
        local battery = bank:getContainer():getItemWithID(self.batteryId)
        expect(battery ~= nil, "the wired battery isn't in this client's copy of the bank")
        local status = T.clientStatus(self.bank)
        expect(status ~= nil and #status.batteries == 1, "the bank's status doesn't list the wired battery")
        if not battery then return end
        local context = newContext()
        local unwire = optionFor(Menu.addUnwireOptions(0, context, bank), battery)
        expect(unwire ~= nil and not unwire.notAvailable, "the bank doesn't offer to unwire the battery wired in")
        context:hideAndChildren()
    end,
})

-- Renaming goes through the bank, shows in its menu and window, and an empty name gives the
-- tier's name back. The bank stands on open ground, which the walk to it always reaches.
test("renewable_energy_ui_rename_bank", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryRackMetal", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        T.step(function()
            T.standNextTo(bank.square)
            if not T.need(self, luautils.walkAdj(player(), bank.square, true), "a walk to the bank") then return end
            ISTimedActionQueue.add(Action:new(player(), Action.RENAME, nil, bank.object, nil, nil, "  Cellar  "))
            T.waitForCopy(function() return Menu.bankLabel(bank.object) == "Cellar" end)
            T.step(function()
                self.renamed = Menu.bankLabel(bank.object)
                local window = StatusWindow.open(0, bank.object)
                T.defer(self, function() window:close() end)
                T.waitForCopy(function() return window.status ~= nil end)
                T.step(function()
                    self.title = window.title
                    window:close()
                    local action = Action:new(player(), Action.RENAME, nil, bank.object, nil, nil, "")
                    self.emptyAllowed = action:canPerform()
                    ISTimedActionQueue.add(action)
                    T.waitForCopy(function() return Menu.bankLabel(bank.object) ~= "Cellar" end)
                    T.bankState(self, bank)
                end)
            end)
        end)
    end,
    validate = function(self)
        expect(self.renamed == "Cellar", "the renamed bank's menu reads " .. tostring(self.renamed))
        expect(self.title == "Cellar", "the window of the renamed bank is titled " .. tostring(self.title))
        expect(self.emptyAllowed, "renaming to an empty name was refused")
        local tier = getItemNameFromFullType("RenewableEnergy.BatteryRackMetal")
        local label = Menu.bankLabel(self.bank.object)
        expect(label == tier, "an empty name left the bank called " .. tostring(label))
        expect(self.bank.state.name == "", "an empty name left the server's bank called " .. tostring(self.bank.state.name))
    end,
})

-- Maintainer ------------------------------------------------------------------------------------

-- The maintainer option shows only when the character carries one, and attaching needs it.
test("renewable_energy_ui_maintainer_menu", {
    run = function(self)
        self.truck = T.placeVehicle(self, "Base.PickUpTruck")
        T.step(function()
            local context = newContext()
            self.offeredEmptyHanded = Menu.addVehicleOptions(0, context, self.truck.vehicle) ~= nil
            context:hideAndChildren()
        end)
        T.give(self, "maintainer", { { type = RenewableEnergy.SolarMaintainer.ITEM } })
    end,
    validate = function(self)
        local p, vehicle = player(), self.truck.vehicle
        expect(not self.offeredEmptyHanded, "a vehicle offers a maintainer to someone without one")
        local context = newContext()
        local option = Menu.addVehicleOptions(0, context, vehicle)
        expect(option ~= nil and option.name == getText("ContextMenu_RenewableEnergy_AttachMaintainer"),
            "carrying a maintainer offers no Attach option on a vehicle")
        expect(Action:new(p, Action.ATTACH_MAINTAINER, nil, nil, vehicle, self.items.maintainer[1]):canPerform(),
            "attaching a carried maintainer is refused")
        expect(not Action:new(p, Action.DETACH_MAINTAINER, nil, nil, vehicle):canPerform(),
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

-- Opens the window of this client's copy of the bank, closed again when the test ends, and queues
-- a wait until the bank's status has come and the window has drawn it.
local function openWindow(self)
    local window = StatusWindow.open(0, self.bank.object)
    self.window = window
    T.defer(self, function() window:close() end)
    T.waitForCopy(function() return (window.renderedFrames or 0) > 0 end)
end

-- A bank with nothing in it says it has no batteries, no inverter and no parts, and that it must
-- go inside.
test("renewable_energy_ui_window_empty_bank", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if self.bank then T.step(function() openWindow(self) end) end
    end,
    validate = function(self)
        local window = self.window
        expect((window.renderedFrames or 0) > 0, "the window never drew its rows")
        expect(window.status ~= nil, "the window shows no status")
        expect(hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_NoBatteries")), "an empty bank does not say it has no batteries")
        expect(hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_NoWorkingInverter")), "an empty bank does not say it has no inverter")
        expect(hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_StateOutdoors")), "a bank outdoors doesn't say it must go inside")
        expect(rowLabelled(window.left, getText("IGUI_RenewableEnergy_NoParts")) ~= nil, "an empty bank doesn't say nothing is wired in")
    end,
})

-- Queues a wait until this client's status of `bank` has the load the server's last answer gave.
local function waitForLoad(bank)
    T.waitForCopy(function()
        local status = T.clientStatus(bank)
        return status ~= nil and status.loadW == bank.state.status.loadW and status.solarW == bank.state.status.solarW
    end)
end

-- The window's lines follow the bank: the overload with its load and limit, the panel slots with
-- the controller count, what draws by kind, a broken part, a battery's repair, and a panel left
-- without a controller slot when its controller goes.
test("renewable_energy_ui_window_reflects_status", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood",
            { "Base.CarBattery1", "Base.CarBattery1", "RenewableEnergy.PlugInInverter", Specs.controller, "Base.CarBatteryCharger" },
            { charge = 0.5 })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.setPartCondition(self, bank, "Base.CarBatteryCharger", 0)
        T.setPartCondition(self, bank, "Base.CarBattery1", 70)
        for _ = 1, 3 do
            if not T.panel(self, Sprites.rack.metal.S, { near = bank, connect = true }) then return end
        end
        T.waitForCopy(function()
            local status = T.clientStatus(bank)
            return status ~= nil and #status.sources == 3
        end)
        T.step(function() self.withControllerSummary = StatusWindow.summary(T.clientStatus(bank)) end)
        T.server(self, "removePart", { bank = bank.position, type = Specs.controller })
        T.bankSet(self, bank, { on = true })
        T.bankPass(self, bank, 1000)
        T.applyLoad(self, bank, { "television", "light", "light", "fridge" })
        waitForLoad(bank)
    end,
    validate = function(self)
        expect(self.withControllerSummary ~= nil and hasLine(self.withControllerSummary,
            getText("IGUI_RenewableEnergy_PanelSlotsOneController", 3, Specs.freePanels + Specs.panelsPerController)),
            "the slots line doesn't read 3 panels of " .. (Specs.freePanels + Specs.panelsPerController) .. " with 1 controller")
        local status = T.clientStatus(self.bank)
        if not expect(status ~= nil, "the bank sent no status") then return end
        local summary = StatusWindow.summary(status)
        local load = Specs.loads.television.watts + 2 * Specs.loads.light.watts + Specs.loads.fridge.watts
        local limit = Specs.inverters["RenewableEnergy.PlugInInverter"].watts
        expect(hasLine(summary, getText("IGUI_RenewableEnergy_Overloaded", Format.watts(load), Format.watts(limit))),
            "the window doesn't say the bank is overloaded with " .. load .. " W on " .. limit .. " W")
        expect(hasLine(summary, getText("IGUI_RenewableEnergy_PanelSlots", 3, Specs.freePanels)),
            "without its controller the slots line doesn't read 3 panels of " .. Specs.freePanels)
        local left, right = StatusWindow.rows(status, self.bank.position)
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
        if self.panel then T.step(function() openWindow(self) end) end
    end,
    validate = function(self)
        local window, panel = self.window, self.panel.object
        local row
        for _, r in ipairs(window.right or {}) do
            row = row or (r.source and r)
        end
        if not expect(row ~= nil and row.top ~= nil, "the window drew no panel row") then return end
        window:onMouseDown(window.rightLayout.x + 4, row.top + 2)
        expect(panel:isHighlighted(0), "clicking the panel's row didn't highlight it")
        window:close()
        expect(not panel:isHighlighted(0), "the panel stayed highlighted after the window closed")
    end,
})

local FULL_BANK = {
    "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery",
    "RenewableEnergy.L16Battery", "Base.CarBattery1", "RenewableEnergy.InverterCharger", POWER_INVERTER,
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
-- of them, and offers its switch.
test("renewable_energy_ui_window_full_bank", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBankMetal", FULL_BANK, { charge = 0.7 })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.setPartCondition(self, bank, "RenewableEnergy.L16Battery", 45)
        for _, source in ipairs(FULL_BANK_SOURCES) do
            if not T.panel(self, source.sprite, { near = bank, modules = source.modules, connect = true }) then return end
        end
        T.bankSet(self, bank, { on = true })
        T.bankPass(self, bank, 650)
        T.applyLoad(self, bank, { "fridge", "television", "light", "light", "light", "radio" })
        waitForLoad(bank)
        T.step(function() openWindow(self) end)
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
        for _, fullType in ipairs({ "RenewableEnergy.InverterCharger", POWER_INVERTER, Specs.controller, "Base.CarBatteryCharger" }) do
            expect(rowLabelled(window.left, getItemNameFromFullType(fullType)) ~= nil, "the window does not list the " .. fullType)
        end
        expect(window.switchButton.enable, "the switch is disabled on a bank with an inverter")
    end,
})
