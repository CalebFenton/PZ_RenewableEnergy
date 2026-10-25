require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/Menu"
require "RenewableEnergy/UI/StatusWindow"
local Clock = require "cf_commonlib/Clock"

-- Solar menus: the panel menus, actions and highlight (UI/Menu.lua, UI/StatusWindow.lua) and the
-- connect action's XP and time (TimedActions/RenewableEnergyAction.lua).

local T = RenewableEnergyTest
local test, expect, expectNear, player = T.test, T.expect, T.expectNear, T.player
local Action = RenewableEnergyAction
local Specs, Sprites, Recipes = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Recipes
local PowerBank, Sources, Format = RenewableEnergy.PowerBank, RenewableEnergy.Sources, RenewableEnergy.Format
local Menu = RenewableEnergy.Menu
local MODULES_KEY = PowerBank.MODULES_KEY
local CAR_BATTERY = "Base.CarBattery1"
local FACTORY = "RenewableEnergy.SolarModule"

-- Connecting a panel gives Electricity XP once per module, the first time that module is ever
-- connected: a rack holding one module connected before gives the other one's share and marks
-- both, and connecting it again after disconnecting gives nothing.
test("renewable_energy_solar_connect_xp_once_per_module", {
    run = function(self)
        T.setPerk(self, Perks.Electricity, 3)
        local module = Specs.factoryModule
        local bank = T.bank(self, "batteryBoxWood", {})
        local panel = bank and T.panel(self, Sprites.rack.wood.S, { near = bank,
            modules = { { type = module, condition = 90, connected = true }, { type = module, condition = 90 } } })
        if not panel then return end
        local args = { bank = bank.position, source = panel.position }
        T.batch(function()
            T.performInto(self, "connected", "connectSource", args)
            T.performInto(self, "disconnected", "disconnectSource", args)
            T.performInto(self, "reconnected", "connectSource", args)
            T.server(self, "panelState", panel.position)
            -- What the game gives this character for one module's award, through the call
            -- CraftRecipe.addXP makes.
            T.server(self, "electricityAward", { xp = Specs.connectXp })
        end)
    end,
    validate = function(self)
        if not T.expectOk(self.connected, "connecting the rack") then return end
        local award, gained = self.server.electricityAward.gained, self.connected.xpAfter - self.connected.xpBefore
        -- An award retuned to nothing would match a connection that gives nothing.
        expect(Specs.connectXp > 0 and award > 0, "a module's first connection is worth " .. award .. " Electricity XP")
        expectNear("Electricity XP from connecting a rack with one new module", gained, award, 0.01)
        T.expectOk(self.disconnected, "disconnecting the rack")
        T.expectOk(self.reconnected, "connecting the rack again")
        expectNear("Electricity XP from connecting the rack again", self.reconnected.xpAfter - self.reconnected.xpBefore, 0, 0)
        local modules = self.server.panelState.modules or {}
        expect(#modules == 2 and modules[1].connected == true and modules[2].connected == true,
            "the rack's record doesn't mark both modules connected")
    end,
})

-- Panel menus and actions ---------------------------------------------------------------------

local function hasEnabledOption(menu)
    for _, option in ipairs(menu and menu.options or {}) do
        if option.onSelect and not option.notAvailable then
            return true
        end
    end
    return false
end

-- A panel offers to connect only to a bank in reach: with none, the option is there but
-- unavailable and says why; with one, the option connects to it.
test("renewable_energy_solar_menu_panel_connect", {
    run = function(self)
        self.panel = T.panel(self, Sprites.rack.wood.S)
        if not self.panel then return end
        T.step(function()
            local panel = self.panel.object
            self.banksBefore = #Sources.banksInReach(panel:getX(), panel:getY(), panel:getZ(), Sources.kindOf(panel))
            local context = T.newContext()
            local submenu = Menu.addSourceOptions(0, context, panel)
            local option = T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_ConnectToBank"))
            self.alone = T.optionState(option)
            self.alone.enabled = hasEnabledOption(submenu)
            context:hideAndChildren()
        end)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true, near = self.panel })
    end,
    validate = function(self)
        local panel, alone = self.panel.object, self.alone
        if expect(self.banksBefore == 0, "a bank left by an earlier test is in reach of the panel") then
            expect(alone.shown and alone.greyed, "a panel with no bank in reach shows no unavailable connect option")
            expect(alone.reason == getText("Tooltip_RenewableEnergy_NoBankInReach"),
                "the unavailable connect option says " .. tostring(alone.reason))
            expect(not alone.enabled, "a panel with no bank in reach offers something to do")
        end
        local connect = T.connectOptions(self.bank, self.panel, 1).one
        expect(connect.shown and not connect.greyed, "a panel next to a bank offers no connection to it")
        expect(T.menuOption(Menu.addSourceOptions, panel, getText("ContextMenu_RenewableEnergy_DisconnectSource")) == nil,
            "a panel that isn't connected offers to disconnect")
    end,
})

-- A connected panel names its bank, by the name a player gave it, and how far away it stands.
test("renewable_energy_solar_menu_panel_wired_to", {
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        if not self.panel then return end
        T.perform(self, "rename", { bank = self.bank.position, name = "Shed Bank" })
        T.waitFor(self, function()
            local summary = T.clientSummary(self.bank)
            return summary ~= nil and summary.name == "Shed Bank"
        end, "this client's summary of the renamed bank")
    end,
    validate = function(self)
        local wiredTo = T.menuOption(Menu.addSourceOptions, self.panel.object, getText("ContextMenu_RenewableEnergy_WiredTo",
            Format.bankName(PowerBank.summaryOf(self.bank.object)), Format.away(self.panel.position, self.bank.position)))
        expect(wiredTo ~= nil, "a connected panel's menu doesn't name its renamed bank and how far away it stands")
    end,
})

-- The option's minimum; the timing's tolerance still dwarfs a round trip to a local server.
local CONNECT_MINUTES = 1
-- A multiplayer server times actions in real milliseconds whatever the game speed
-- (NetTimedAction.getDuration); in single player the action and the clock speed up alike.
local function connectSpeed()
    return isClient() and 1 or 10
end

local function worldMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

-- Connecting a panel takes the ConnectPanelMin sandbox option's in-game minutes, from the action's
-- start to its end, and leaves the bank listing the panel, on the server and in this client's status.
test("renewable_energy_solar_connect_panel", {
    sandbox = { ConnectPanelMin = CONNECT_MINUTES },
    run = function(self)
        local p = player()
        if not T.needActionTime(self) then return end
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank })
        if not self.panel then return end
        -- At this level the option's minutes are taken as they are; skill shortens or lengthens them.
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
            if not T.walkTo(self, self.panel.square, "the panel") then return end
            ISTimedActionQueue.add(action)
            T.waitFor(self, function()
                return PowerBank.samePosition(PowerBank.connectedBank(self.panel.object), self.bank.position)
            end, "this client's copy of the connection")
            T.bankState(self, self.bank)
        end)
    end,
    validate = function(self)
        expect(self.valid, "connecting a panel next to a bank is refused")
        expect(self.bank.state.sources == 1, "the server's bank lists " .. self.bank.state.sources .. " panels")
        expect(PowerBank.samePosition(PowerBank.connectedBank(self.panel.object), self.bank.position),
            "this client's status of the bank does not list the connected panel")
        expect(not self.action:canPerform(), "a panel already on this bank can be connected again")
        if not expect(self.started ~= nil and self.ended ~= nil, "the connect action never started or ended") then return end
        local elapsed = self.ended - self.started
        expect(elapsed >= CONNECT_MINUTES * 0.95 and elapsed <= CONNECT_MINUTES * 1.05,
            string.format("connecting took %.2f in-game minutes, expected %d", elapsed, CONNECT_MINUTES))
    end,
})

-- Disconnect, chosen from a connected panel's menu, takes the panel off the bank on the server and
-- in this client's copy.
test("renewable_energy_solar_disconnect_panel", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.wall.wood.S, { near = self.bank, connect = true })
        if not self.panel then return end
        T.step(function()
            local option = T.menuOption(Menu.addSourceOptions, self.panel.object, getText("ContextMenu_RenewableEnergy_DisconnectSource"))
            self.offered = option ~= nil and not option.notAvailable
            if not self.offered then return end
            T.standNextTo(self.panel.square)
            T.choose(option)
            T.waitFor(self, function() return PowerBank.connectedBank(self.panel.object) == nil end, "this client's copy of the disconnection")
            T.bankState(self, self.bank)
        end)
    end,
    validate = function(self)
        expect(self.panel.connected, "the bank refused to connect a wall panel next to it (" .. tostring(self.panel.reason) .. ")")
        if not expect(self.offered, "a connected panel's menu offers no Disconnect") then return end
        expect(self.bank.state.sources == 0, "the server's bank still lists the panel after disconnecting it")
        expect(PowerBank.connectedBank(self.panel.object) == nil, "this client still sees the panel connected after disconnecting it")
    end,
})

-- Seal Cracked Module, chosen from a connected rack's menu, seals the one cracked module still on
-- its mount as the recipe seals one in hand: up to its cap, lowered by the seal it already had,
-- counting the seal and still showing cracked. The whole module isn't offered, and the bank's
-- record takes the sealed module at once. Its tooltip names both adhesives, and with both
-- carried the seal takes the glue twin's uses of glue and leaves the epoxy (Recipes.lua,
-- MODULE_REPAIR_RECIPES).
test("renewable_energy_solar_seal_module_in_place", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        local cracked = { type = FACTORY, condition = 20, repaired = 1 }
        self.to = math.min(T.sealCap(FACTORY, cracked.repaired), cracked.condition + Recipes.MODULE_REPAIR)
        self.panel = self.bank and T.panel(self, Sprites.rack.wood.S, { near = self.bank, connect = true,
            modules = { { type = FACTORY, condition = 100 }, cracked } })
        if not self.panel then return end
        local bank = self.bank
        T.setRecipeSkills(self, Recipes.moduleRepairRecipe())
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" }, { type = "Base.Glue" } })
        T.step(function()
            local context = T.newContext()
            local menu = Menu.addSourceOptions(0, context, self.panel.object)
            local whole = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_SealModule", 1, 100))
            local option = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_SealModule", 2, cracked.condition))
            context:hideAndChildren()
            self.wholeOffered, self.offered = whole ~= nil, T.optionState(option)
            if not (option and not option.notAvailable) then return end
            T.standNextTo(self.panel.square)
            T.choose(option)
            T.waitFor(self, function()
                local modules = self.panel.object:getModData()[MODULES_KEY]
                return modules and modules[2] and modules[2].condition ~= cracked.condition
            end, "this client's copy of the sealed module")
            T.server(self, "panelState", self.panel.position)
            T.bankState(self, bank)
            T.readCarried(self, { "Base.Glue", "Base.Epoxy" })
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        expect(not self.wholeOffered, "the whole module is offered a seal")
        if not expect(self.offered.shown and not self.offered.greyed, "the cracked module's seal isn't offered ("
            .. tostring(self.offered.reason) .. ")") then return end
        local modules = self.server.panelState.modules
        expectNear("the whole module", modules[1].condition, 100, 0)
        expectNear("the sealed module", modules[2].condition, self.to, 0)
        expect(modules[2].repaired == 2, "the sealed module reads repaired " .. tostring(modules[2].repaired) .. "x, expected 2")
        expect(#self.server.panelState.overlays > 0, "the sealed module shows whole")
        local listed = self.bank.state.status.sources[1]
        expectNear("the bank's record of the sealed module", listed and listed.modules[2] and listed.modules[2].condition, self.to, 0)
        for _, adhesive in ipairs({ "Base.Glue", "Base.Epoxy" }) do
            expect(tostring(self.offered.reason):find(getItemNameFromFullType(adhesive), 1, true) ~= nil,
                "the seal's tooltip doesn't name " .. adhesive .. ": " .. tostring(self.offered.reason))
        end
        -- One full tube of each was given; T.readCarried's `uses` is the fraction of it left.
        local glue, epoxy = T.carriedFirst(self, "Base.Glue"), T.carriedFirst(self, "Base.Epoxy")
        expectNear("the glue left of a full tube", glue and glue.uses or 0,
            1 - 2 * getScriptManager():FindItem("Base.Glue"):getUseDelta(), 0.001)
        expectNear("the epoxy left of a full tube", epoxy and epoxy.uses or 0, 1, 0.001)
    end,
})

-- The Clear Snow option on `panel`'s menu: whether it shows, whether it is greyed out, and why.
local function clearSnowOption(panel)
    return T.optionState(T.menuOption(Menu.addSourceOptions, panel.object, getText("ContextMenu_RenewableEnergy_ClearSnow")))
end

-- A snowy flat panel offers Clear Snow, greyed out saying why until the character carries a broom
-- or snow shovel. The action then needs the tool in hand and unbroken, and only flat panels hold
-- snow.
test("renewable_energy_solar_clear_snow_requirements", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        self.flat = self.bank and T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        self.wall = self.flat and T.panel(self, Sprites.wall.wood.E)
        if not self.wall then return end
        T.snowfall(self, self.bank)
        T.waitFor(self, function()
            local summary = T.clientSummary(self.bank)
            return summary ~= nil and summary.sources[1] ~= nil and summary.sources[1].snowy == true
        end, "this client's summary with the panel snowy")
        T.step(function() self.withoutTool = clearSnowOption(self.flat) end)
        T.give(self, "tools", { { type = "Base.Broom" }, { type = "Base.SnowShovel" }, { type = "Base.Hammer" } })
        T.step(function() self.withTool = clearSnowOption(self.flat) end)
    end,
    validate = function(self)
        expect(self.withoutTool.greyed and self.withoutTool.reason == getText("Tooltip_RenewableEnergy_NeedSnowTool"),
            "with no broom or shovel, Clear Snow on a snowy panel isn't greyed out saying why ("
            .. tostring(self.withoutTool.shown) .. ", " .. tostring(self.withoutTool.reason) .. ")")
        expect(self.withTool.shown and not self.withTool.greyed,
            "carrying a broom, Clear Snow isn't offered on a snowy panel (" .. tostring(self.withTool.reason) .. ")")
        local p = player()
        local broom, shovel, hammer = self.items.tools[1], self.items.tools[2], self.items.tools[3]
        local function canClear(panel, tool)
            return Action:new(p, Action.CLEAR_SNOW, panel.object, nil, nil, tool):canPerform()
        end
        expect(not canClear(self.flat, broom), "snow can be cleared with a broom left in the bag")
        p:setPrimaryHandItem(broom)
        expect(canClear(self.flat, broom), "a broom in hand can't clear a flat panel")
        expect(not canClear(self.wall, broom), "a wall panel, which holds no snow, can be cleared")
        -- A broom broken in hand drops splinters (OnBreak.LongStick); clear them away.
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

-- A bank with every input slot taken greys out connecting another panel, from the bank's menu and
-- from the panel's, saying there's no slot; one slot freed, both offer it. Read on this client's
-- summary, which carries the free slots. Catches a menu that offers a connection the bank then
-- refuses, or still refuses once a slot is free.
test("renewable_energy_solar_connect_refused_without_free_slot", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        local wired = {}
        T.batch(function()
            for i = 1, Specs.freeSlots do
                wired[i] = T.panel(self, Sprites.flat, { near = bank, connect = true })
                if not wired[i] then return end
            end
            self.loose = T.panel(self, Sprites.flat, { near = bank })
        end)
        if not self.loose then return end
        local function freeSlots(count)
            T.waitFor(self, function()
                local summary = T.clientSummary(bank)
                return summary ~= nil and summary.freeSlots == count
            end, "this client's summary with " .. count .. " free input slots")
        end
        freeSlots(0)
        T.step(function() self.full = T.connectOptions(bank, self.loose, 1) end)
        T.perform(self, "disconnectSource", { bank = bank.position, source = wired[1].position })
        freeSlots(1)
        -- The disconnected panel is loose in reach now too.
        T.step(function() self.freed = T.connectOptions(bank, self.loose, 2) end)
    end,
    validate = function(self)
        local why = getText("Tooltip_RenewableEnergy_NoInputSlot")
        for name, option in pairs(self.full) do
            expect(option.greyed and option.reason == why, "with every slot taken, the " .. name
                .. " connect option isn't greyed out saying there's no slot (" .. tostring(option.reason) .. ")")
        end
        for name, option in pairs(self.freed) do
            expect(option.shown and not option.greyed, "with a slot free, the " .. name
                .. " connect option isn't offered (" .. tostring(option.reason) .. ")")
        end
    end,
})

-- Clicking a panel's row highlights the panel in the world, until the window closes.
test("renewable_energy_solar_window_highlights_panel", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        if self.panel then T.step(function() T.openWindow(self) end) end
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

-- A connect job takes ConnectPanelMin minutes at Electricity 3, a fixed share of that less for each
-- level above and more for each below (RenewableEnergyAction's skillFactor); the expected minutes
-- are worked by hand.
test("renewable_energy_solar_connect_time_by_electricity", {
    sandbox = { ConnectPanelMin = 10 },
    run = function(self)
        self.minutes = {}
        T.step(function()
            for _, level in ipairs({ 0, 3, 10 }) do
                T.setPerk(self, Perks.Electricity, level)
                local units = Action:new(player(), Action.CONNECT_SOURCE, nil, nil):units()
                self.minutes[level] = units / Clock.unitsPerMinute()
            end
        end)
    end,
    validate = function(self)
        expectNear("connect minutes at Electricity 3", self.minutes[3], 10, 1e-6)
        expectNear("connect minutes at Electricity 0", self.minutes[0], 12.85, 1e-6)
        expectNear("connect minutes at Electricity 10", self.minutes[10], 3.35, 1e-6)
    end,
})
