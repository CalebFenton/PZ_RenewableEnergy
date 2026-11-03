require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibCraft"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
local Specs = require "RenewableEnergy/Specs"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Format = require "RenewableEnergy/UI/Format"
local SourceMenu = require "RenewableEnergy/UI/SourceMenu"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Clock = require "cf_commonlib/Clock"
local Squares = require "cf_commonlib/Squares"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Sprites = require "RenewableEnergy/Sprites"

-- Solar menus: the panel menus, actions and highlight (UI/SourceMenu.lua, UI/StatusWindow.lua) and the
-- connect action's XP and time (TimedActions/RenewableEnergyAction.lua).

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual, player = T.test, T.expect, T.expectNear, T.expectEqual, T.player
local MODULES_KEY = Panel.MODULES_KEY

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
        local function job(name, label) T.job(self, "source", name, panel, bank, label, { xp = { "Electricity" } }) end
        T.batch(function()
            job(SourceJobs.CONNECT, "connected")
            job(SourceJobs.DISCONNECT, "disconnected")
            job(SourceJobs.CONNECT, "reconnected")
            T.read(self, "panelState", T.at(panel), "panel")
            -- What the game gives this character for one module's award, through the call
            -- CraftRecipe.addXP makes.
            T.xpAward(self, "Electricity", Specs.connectXp, "award")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        if not T.expectOk(reads.connected, "connecting the rack") then return end
        local award, gained = reads.award.gained, reads.connected.xpAfter.Electricity - reads.connected.xpBefore.Electricity
        -- An award retuned to nothing would match a connection that gives nothing.
        expect(Specs.connectXp > 0 and award > 0, "a module's first connection is worth " .. award .. " Electricity XP")
        expectNear("Electricity XP from connecting a rack with one new module", gained, award, 0.01)
        T.expectOk(reads.disconnected, "disconnecting the rack")
        T.expectOk(reads.reconnected, "connecting the rack again")
        expectEqual("Electricity XP from connecting the rack again",
            reads.reconnected.xpAfter.Electricity - reads.reconnected.xpBefore.Electricity, 0)
        local modules = reads.panel.modules or {}
        expect(#modules == 2 and modules[1].connected == true and modules[2].connected == true,
            "the rack's record doesn't mark both modules connected")
    end,
})

-- Panel menus and actions ---------------------------------------------------------------------

local function hasEnabledOption(menu)
    for _, option in ipairs(menu and menu.options or {}) do
        if option.onSelect and T.offered(option) then
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
            local submenu = SourceMenu.addSourceOptions(0, context, panel)
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
            expectEqual("the unavailable connect option's tooltip", alone.reason, getText("Tooltip_RenewableEnergy_NoBankInReach"))
            expect(not alone.enabled, "a panel with no bank in reach offers something to do")
        end
        local connect = T.connectOptions(self.bank, self.panel, 1).one
        expect(connect.shown and not connect.greyed, "a panel next to a bank offers no connection to it")
        expect(T.menuOption(SourceMenu.addSourceOptions, panel, getText("ContextMenu_RenewableEnergy_DisconnectSource")) == nil,
            "a panel that isn't connected offers to disconnect")
    end,
})

-- A connected panel names its bank, by the name a player gave it, and how far away it stands.
test("renewable_energy_solar_menu_panel_wired_to", {
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        if not self.panel then return end
        T.job(self, "bank", BankJobs.RENAME, self.bank, "Shed Bank")
        T.waitForSummary(self, self.bank, function(summary) return summary.name == "Shed Bank" end,
            "this client's summary of the renamed bank")
    end,
    validate = function(self)
        local wiredTo = T.menuOption(SourceMenu.addSourceOptions, self.panel.object, getText("ContextMenu_RenewableEnergy_WiredTo",
            "Shed Bank", Format.away(self.panel, self.bank)))
        expect(wiredTo ~= nil, "a connected panel's menu doesn't name its renamed bank and how far away it stands")
    end,
})

-- The queued connection completes on the authority and reaches this client's bank state.
-- The mod's duration/skill rule is checked separately, without timing the game's action runner.
test("renewable_energy_solar_connect_panel", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank })
        if not self.panel then return end
        T.setPerk(self, Perks.Electricity, 3)
        local function connect()
            return RenewableEnergyAction:new(player(), "source", SourceJobs.CONNECT, self.panel.object, self.bank.object)
        end
        T.step(function() self.valid = connect():canPerform() end)
        T.actionJob(self, "source", self.panel, SourceJobs.CONNECT, self.bank)
        T.waitFor(self, function()
            return Squares.samePosition(PowerBank.connectedBank(self.panel.object), self.bank)
        end, "this client's copy of the connection")
        T.readRecord(self, self.bank)
        T.step(function() self.again = connect():canPerform() end)
    end,
    validate = function(self)
        expect(self.valid, "connecting a panel next to a bank is refused")
        expectEqual("panels the server's bank lists", self.bank.state.sources, 1)
        expect(Squares.samePosition(PowerBank.connectedBank(self.panel.object), self.bank),
            "this client's status of the bank does not list the connected panel")
        expect(not self.again, "a panel already on this bank can be connected again")
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
            local option = T.menuOption(SourceMenu.addSourceOptions, self.panel.object, getText("ContextMenu_RenewableEnergy_DisconnectSource"))
            if not T.chooseOption(self, "Disconnect", option, self.panel.square) then return end
            T.waitFor(self, function() return PowerBank.connectedBank(self.panel.object) == nil end, "this client's copy of the disconnection")
            T.readRecord(self, self.bank)
        end)
    end,
    validate = function(self)
        if not (T.expectConnected(self.panel) and T.expectOffered(self, "Disconnect")) then return end
        expectEqual("panels the server's bank lists after disconnecting", self.bank.state.sources, 0)
        expect(PowerBank.connectedBank(self.panel.object) == nil, "this client still sees the panel connected after disconnecting it")
    end,
})

-- Seal Cracked Module, chosen from a connected rack's menu, seals the one cracked module still on
-- its mount as the recipe seals one in hand (ModuleRepair.sealed), counting the seal and still
-- showing cracked. The whole module isn't offered, and the bank's record takes the sealed module at
-- once. Its tooltip names both adhesives, and with both carried the seal takes the glue twin's uses
-- of glue and leaves the epoxy (ModuleRepair.SEAL, a cf_commonlib Materials craft).
test("renewable_energy_solar_seal_module_in_place", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        -- Sealed once already, so its lowered cap, not a whole seal's worth, decides how far it goes.
        local cracked = { type = T.FACTORY_MODULE, condition = 30, repaired = 1 }
        self.cracked = cracked
        self.panel = self.bank and T.panel(self, Sprites.rack.wood.S, { near = self.bank, connect = true,
            modules = { { type = T.FACTORY_MODULE, condition = 100 }, cracked } })
        if not self.panel then return end
        local bank = self.bank
        T.setRecipeSkills(self, ModuleRepair.sealRecipe())
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" }, { type = "Base.Glue" } })
        T.step(function()
            self.items.inputs[1]:setFavorite(true, true)
            local context = T.newContext()
            local menu = SourceMenu.addSourceOptions(0, context, self.panel.object)
            local whole = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_SealModule", 1,
                Format.condition(T.FACTORY_MODULE, 100)))
            local option = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_SealModule", 2,
                Format.condition(cracked.type, cracked.condition)))
            context:hideAndChildren()
            self.wholeOffered = whole ~= nil
            if not T.chooseOption(self, "Seal Cracked Module", option, self.panel.square) then return end
            T.waitFor(self, function()
                local modules = self.panel.object:getModData()[MODULES_KEY]
                return modules and modules[2] and modules[2].condition ~= cracked.condition
            end, "this client's copy of the sealed module")
            T.read(self, "panelState", T.at(self.panel), "panel")
            T.readRecord(self, bank)
            T.readCarried(self, { "Base.Glue", "Base.Epoxy" })
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        expect(not self.wholeOffered, "the whole module is offered a seal")
        if not T.expectOffered(self, "Seal Cracked Module") then return end
        local modules, tooltip = self.reads.panel.modules, self.menu["Seal Cracked Module"].tooltip
        local condition, seals = ModuleRepair.sealed(self.cracked.type, self.cracked.condition, self.cracked.repaired)
        expectEqual("the whole module's condition", modules[1].condition, 100)
        expectEqual("the sealed module's condition", modules[2].condition, condition)
        expectEqual("the sealed module's seals", modules[2].repaired, seals)
        expect(#self.reads.panel.overlays > 0, "the sealed module shows whole")
        local listed = self.bank.state.status.sources[1]
        expectEqual("the bank's record of the sealed module", listed and listed.modules[2] and listed.modules[2].condition, condition)
        for _, adhesive in ipairs({ "Base.Glue", "Base.Epoxy" }) do
            expect(tooltip:find(getItemNameFromFullType(adhesive), 1, true) ~= nil,
                "the seal's tooltip doesn't name " .. adhesive .. ": " .. tooltip)
        end
        -- One full tube of each was given; T.readCarried's `uses` is the fraction of it left.
        local glue, epoxy = T.carriedFirst(self, "Base.Glue"), T.carriedFirst(self, "Base.Epoxy")
        expectNear("the glue left of a full tube", glue and glue.uses or 0,
            1 - 2 * getScriptManager():FindItem("Base.Glue"):getUseDelta(), 0.001)
        expectNear("the epoxy left of a full tube", epoxy and epoxy.uses or 0, 1, 0.001)
    end,
})

-- Reglaze Module, chosen from a connected flat panel's menu, brings its heavily cracked, sealed
-- module back to new while it stays on the mount: its seals clear, the tile shows no cracks, the
-- bank's record takes it at once, and it takes Reglaze Module's inputs, keeping the screwdriver.
-- A module at new isn't offered it.
test("renewable_energy_solar_reglaze_module_in_place", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        local cracked = { type = T.FACTORY_MODULE, condition = 30, repaired = 2 }
        self.cracked = cracked
        self.panel = self.bank and T.panel(self, Sprites.rack.wood.S, { near = self.bank, connect = true,
            modules = { { type = T.FACTORY_MODULE, condition = 100 }, cracked } })
        if not self.panel then return end
        local bank = self.bank
        T.setRecipeSkills(self, ModuleRepair.reglazeRecipe())
        T.knowRecipes(self, { ModuleRepair.REGLAZE_RECIPE })
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.GlassPanel" }, { type = "Base.Epoxy" },
            { type = "Base.ElectricWire" } })
        T.step(function()
            local context = T.newContext()
            local menu = SourceMenu.addSourceOptions(0, context, self.panel.object)
            local whole = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_ReglazeModule", 1,
                Format.condition(T.FACTORY_MODULE, 100)))
            local option = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_ReglazeModule", 2,
                Format.condition(cracked.type, cracked.condition)))
            context:hideAndChildren()
            self.wholeOffered = whole ~= nil
            if not T.chooseOption(self, "Reglaze Module", option, self.panel.square) then return end
            T.waitFor(self, function()
                local modules = self.panel.object:getModData()[MODULES_KEY]
                return modules and modules[2] and modules[2].condition ~= cracked.condition
            end, "this client's copy of the reglazed module")
            T.read(self, "panelState", T.at(self.panel), "panel")
            T.readRecord(self, bank)
            T.count(self, "left", { "Base.Screwdriver", "Base.GlassPanel", "Base.ElectricWire" })
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        expect(not self.wholeOffered, "the module at new is offered Reglaze Module")
        if not T.expectOffered(self, "Reglaze Module") then return end
        local modules = self.reads.panel.modules
        expectEqual("the reglazed module's condition", modules[2].condition, 100)
        expectEqual("the reglazed module's seals", modules[2].repaired or 0, 0)
        expectEqual("crack overlays on the reglazed panel", #self.reads.panel.overlays, 0)
        local listed = self.bank.state.status.sources[1]
        expectEqual("the bank's record of the reglazed module", listed and listed.modules[2] and listed.modules[2].condition, 100)
        local left = self.counts.left
        expectEqual("screwdrivers left", left["Base.Screwdriver"], 1)
        expectEqual("glass panes left", left["Base.GlassPanel"], 0)
        expectEqual("electric wire left", left["Base.ElectricWire"], 0)
    end,
})

-- The Seal Cracked Module option for each module of the placed panel `object`, by slot, as its
-- menu offers them now; nil for a module not offered.
local function sealOptions(object)
    local context = T.newContext()
    local menu = SourceMenu.addSourceOptions(0, context, object)
    local options = {}
    for slot, module in ipairs(object:getModData()[MODULES_KEY] or {}) do
        options[slot] = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_SealModule", slot,
            Format.condition(module.type, module.condition)))
    end
    context:hideAndChildren()
    return options
end

-- Repair inputs follow the crafting window's protection flags. A favorite kept tool is legal;
-- a favorite adhesive or a tool excluded from recipes must disable the actual repair option.
test("renewable_energy_solar_seal_respects_protected_inputs", {
    run = function(self)
        local panel = T.panel(self, Sprites.flat, { modules = T.factoryModules(20) })
        if not panel then return end
        T.setRecipeSkills(self, ModuleRepair.sealRecipe())
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" } })
        T.step(function()
            local tool, epoxy = self.items.inputs[1], self.items.inputs[2]
            tool:setFavorite(true)
            self.kept = T.optionState(sealOptions(panel.object)[1])
            epoxy:setFavorite(true)
            self.protected = T.optionState(sealOptions(panel.object)[1])
            epoxy:setFavorite(false)
            tool:setNoRecipes(player(), true)
            self.excluded = T.optionState(sealOptions(panel.object)[1])
        end)
    end,
    validate = function(self)
        expect(self.kept.shown and not self.kept.greyed, "a favorite kept screwdriver disables sealing")
        expect(self.protected.shown and self.protected.greyed, "sealing offers to consume favorite epoxy")
        expect(self.excluded.shown and self.excluded.greyed, "sealing uses a screwdriver excluded from recipes")
    end,
})

-- A rack with both modules cracked offers to seal each. Once one is sealed as far as sealing goes
-- the menu built again still offers the other, which seals in turn, and keeps the sealed one's
-- option greyed out saying to reglaze it, since its glass still looks cracked: each module keeps
-- its own option. The tooltip keeps a gap on both sides of the "or" between the adhesives.
test("renewable_energy_solar_seal_each_module_in_place", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.conditions, self.order = { 30, 40 }, { 2, 1 }
        self.panel = self.bank and T.panel(self, Sprites.rack.wood.S, { near = self.bank, connect = true,
            modules = T.factoryModules(self.conditions[1], self.conditions[2]) })
        if not self.panel then return end
        T.setRecipeSkills(self, ModuleRepair.sealRecipe())
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" }, { type = "Base.Glue" } })
        -- The options before each seal, and after the last.
        self.offers = {}
        for round = 1, #self.order + 1 do
            T.step(function()
                local options = sealOptions(self.panel.object)
                self.offers[round] = { T.optionState(options[1]), T.optionState(options[2]) }
                local slot = self.order[round]
                local option = slot and options[slot]
                if not T.chooseOption(self, "seal " .. round, option, self.panel.square) then return end
                T.waitFor(self, function()
                    local modules = self.panel.object:getModData()[MODULES_KEY]
                    return modules and modules[slot] and modules[slot].condition ~= self.conditions[slot]
                end, "this client's copy of sealed module " .. slot)
            end)
        end
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        local sealedFully, sealed = getText("Tooltip_RenewableEnergy_ModuleSealedFully"), {}
        for round = 1, #self.order + 1 do
            for slot = 1, #self.conditions do
                local offer = self.offers[round] and self.offers[round][slot] or { shown = false }
                local what = "module " .. slot .. (sealed[slot] and ", sealed," or "") .. " before seal " .. round .. ": "
                if not expect(offer.shown, what .. "no Seal Cracked Module") then return end
                if sealed[slot] then
                    expect(offer.greyed, what .. "not greyed out")
                    expectEqual(what .. "the tooltip", offer.reason, sealedFully)
                else
                    expect(not offer.greyed, what .. "greyed out (" .. tostring(offer.reason) .. ")")
                    local touching = T.runTogether(offer.reason or "")
                    expect(#touching == 0, what .. "the tooltip runs words together: " .. table.concat(touching, ", "))
                end
            end
            sealed[self.order[round] or 0] = true
        end
    end,
})

-- The Clear Snow option on `panel`'s menu: whether it shows, whether it is greyed out, and why.
local function clearSnowOption(panel)
    return T.optionState(T.menuOption(SourceMenu.addSourceOptions, panel.object, getText("ContextMenu_RenewableEnergy_ClearSnow")))
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
        T.waitForSummary(self, self.bank, function(summary) return summary.sources[1] ~= nil and summary.sources[1].snowy end,
            "this client's summary with the panel snowy")
        T.step(function() self.withoutTool = clearSnowOption(self.flat) end)
        T.give(self, "tools", { { type = "Base.Broom" }, { type = "Base.SnowShovel" }, { type = "Base.Hammer" } })
        T.step(function() self.withTool = clearSnowOption(self.flat) end)
    end,
    validate = function(self)
        expect(self.withoutTool.greyed and tostring(self.withoutTool.reason):find(getText("Tooltip_RenewableEnergy_NeedSnowTool"), 1, true) ~= nil,
            "with no broom or shovel, Clear Snow on a snowy panel isn't greyed out saying it needs one ("
            .. tostring(self.withoutTool.reason) .. ")")
        expect(self.withTool.shown and not self.withTool.greyed,
            "carrying a broom, Clear Snow isn't offered on a snowy panel (" .. tostring(self.withTool.reason) .. ")")
        local p = player()
        local broom, shovel, hammer = self.items.tools[1], self.items.tools[2], self.items.tools[3]
        local function canClear(panel, tool)
            return RenewableEnergyAction:new(p, "source", SourceJobs.CLEAR_SNOW, panel.object, tool):canPerform()
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
            T.waitForSummary(self, bank, function(summary) return summary.freeSlots == count end,
                "this client's summary with " .. count .. " free input slots")
        end
        freeSlots(0)
        T.step(function() self.full = T.connectOptions(bank, self.loose, 1) end)
        T.job(self, "source", SourceJobs.DISCONNECT, wired[1])
        freeSlots(1)
        -- The disconnected panel is loose in reach now too.
        T.step(function() self.freed = T.connectOptions(bank, self.loose, 2) end)
    end,
    validate = function(self)
        local why = getText("Tooltip_RenewableEnergy_NoInputSlot")
        for name, option in pairs(self.full) do
            expect(option.greyed and tostring(option.reason):find(why, 1, true) ~= nil, "with every slot taken, the "
                .. name .. " connect option isn't greyed out saying there's no slot (" .. tostring(option.reason) .. ")")
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
        self.bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        if self.panel then T.openWindow(self, self.bank) end
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

-- A connect job takes ConnectPanelMin minutes at Electricity 3 and the same share of them less for
-- each level above, more for each below (RenewableEnergyAction's skillFactor). Catches skill left
-- out, counted the wrong way, anchored at another level, or not by equal steps.
test("renewable_energy_solar_connect_time_by_electricity", {
    sandbox = { ConnectPanelMin = 10 },
    run = function(self)
        self.minutes = {}
        T.step(function()
            for _, level in ipairs({ 0, 3, 10 }) do
                T.setPerk(self, Perks.Electricity, level)
                local units = RenewableEnergyAction:new(player(), "source", SourceJobs.CONNECT, nil, nil):units()
                self.minutes[level] = units / Clock.unitsPerMinute()
            end
        end)
    end,
    validate = function(self)
        local unskilled, base, master = self.minutes[0], self.minutes[3], self.minutes[10]
        expectNear("connect minutes at Electricity 3", base, 10, 1e-6)
        expect(unskilled > base and base > master and master > 0, string.format(
            "connecting takes %g minutes at Electricity 0, %g at 3, %g at 10", unskilled, base, master))
        expectNear("minutes saved by a level above 3 against those lost by a level below", (base - master) / 7,
            (unskilled - base) / 3, 1e-6)
    end,
})
