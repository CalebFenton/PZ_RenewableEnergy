require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Format = require "RenewableEnergy/UI/Format"
local BankMenu = require "RenewableEnergy/UI/BankMenu"
local SourceMenu = require "RenewableEnergy/UI/SourceMenu"
local Squares = require "cf_commonlib/Squares"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Sprites = require "RenewableEnergy/Sprites"

-- Power bank tests: connecting banks, and sources to them.
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectEqual, player = T.test, T.expect, T.expectEqual, T.player

-- Connecting -----------------------------------------------------------------------------------

-- A bank starts unconnected, like a generator: switched on it powers nothing, nor a square near it,
-- and its status says so, until it is connected; then both have power, here too.
test("renewable_energy_bank_needs_connecting", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.L16, T.INVERTER_CHARGER }, { connected = false })
        if not bank then return end
        self.bank = bank
        self.near = T.square(self, { near = bank }, "a square near the bank")
        if not self.near then return end
        T.switchOn(self, bank)
        T.readRecord(self, bank, "before")
        T.step(function() self.nearBefore = self.near:haveElectricity() end)
        T.job(self, "bank", BankJobs.CONNECT, bank, nil, "connected")
        T.waitFor(self, function() return bank.square:haveElectricity() and self.near:haveElectricity() end,
            "power on the connected bank's square and the square near it here")
        T.readRecord(self, bank)
    end,
    validate = function(self)
        local before, after = self.reads.before, self.bank.state
        expect(before.on and not before.activated and not before.powered, "an unconnected bank that is on powered its square")
        expect(not self.nearBefore, "an unconnected bank that is on powered a square near it")
        expectEqual("the unconnected bank's state", before.status.state, "disconnected")
        T.expectOk(self.reads.connected, "connecting the bank")
        expect(after.activated and after.powered, "the connected bank doesn't power its square")
        expectEqual("the connected bank's state", after.status.state, "on")
    end,
})

-- A bank tile a player places becomes a working bank that isn't connected yet, as a generator
-- set down isn't.
test("renewable_energy_bank_placed_bank_starts_unconnected", {
    instant = true,
    run = function(self)
        local square = T.square(self, { indoors = true }, "a free indoor square for a bank")
        if not square then return end
        self.square = square
        -- Placing a bank tile needs the Electrician tool.
        T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
        T.placeAsPlayer(self, square, "RenewableEnergy.BatteryBoxWood", Sprites.batteryBoxWood.S)
        T.waitFor(self, function()
            local bank = PowerBank.findOn(square)
            return bank ~= nil and PowerBank.summaryOf(bank) ~= nil
        end, "this client's copy of the placed bank, working")
    end,
    validate = function(self)
        local bank = PowerBank.findOn(self.square)
        expect(not bank:isConnected(), "a bank the player placed starts connected")
    end,
})

-- Vanilla's recipe of the generator magazine.
local GENERATOR = { "Generator" }

-- Connecting a bank takes what connecting a generator does in vanilla: the Electricity level or
-- the "Generator" recipe, enforced by the menu, the action and the authority.
test("renewable_energy_bank_connect_needs_generator_skill", {
    run = function(self)
        self.unskilled = T.bank(self, "batteryBoxWood", {}, { connected = false })
        self.magazine = self.unskilled and T.bank(self, "batteryBoxWood", {}, { connected = false, near = self.unskilled })
        if not self.magazine then return end
        T.knowRecipes(self, GENERATOR, false)
        T.setPerk(self, Perks.Electricity, 2)
        T.step(function()
            self.connect = T.optionState(T.menuOption(BankMenu.addBankOptions, self.unskilled.object,
                getText("ContextMenu_RenewableEnergy_ConnectBank")))
            self.canStart = RenewableEnergyAction:new(player(), "bank", BankJobs.CONNECT, self.unskilled.object):canPerform()
        end)
        T.job(self, "bank", BankJobs.CONNECT, self.unskilled, nil, "refused")
        -- T.setPerk sets the level when called, so the later levels wait for their turn.
        T.step(function() T.setPerk(self, Perks.Electricity, 3) end)
        T.job(self, "bank", BankJobs.CONNECT, self.unskilled, nil, "skilled")
        T.step(function() T.setPerk(self, Perks.Electricity, 2) end)
        T.knowRecipes(self, GENERATOR)
        T.job(self, "bank", BankJobs.CONNECT, self.magazine, nil, "withRecipe")
    end,
    validate = function(self)
        expect(self.connect.greyed, "at Electricity 2 Connect Bank isn't greyed out")
        expectEqual("Connect Bank's tooltip at Electricity 2", self.connect.reason, getText("ContextMenu_GeneratorPlugTT"))
        expect(not self.canStart, "Connect Bank can start at Electricity 2 without the Generator recipe")
        T.expectRefused(self.reads.refused, "ContextMenu_GeneratorPlugTT",
            "the authority connected a bank at Electricity 2 without the Generator recipe")
        T.expectOk(self.reads.skilled, "connecting a bank at Electricity 3")
        T.expectOk(self.reads.withRecipe, "connecting a bank with the Generator recipe")
    end,
})

-- Connect Bank from the menu connects the bank, Disconnect Bank undoes it, and only a
-- disconnected bank can be picked up, as with a generator.
test("renewable_energy_bank_connect_and_disconnect", {
    instant = true,
    run = function(self)
        -- Outdoors: connecting takes light to see by, which an unlit room lacks.
        self.bank = T.bank(self, "batteryBoxWood", {}, { connected = false, outdoors = true })
        if not self.bank then return end
        -- Picking up a bank tile needs the Electrician tool.
        T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
        local bank = self.bank
        local function canPickUp()
            local object = bank.object
            return ISMoveableSpriteProps.new(object:getSprite():getName()):canPickUpMoveable(player(), bank.square, object)
        end
        T.step(function()
            if not T.chooseOption(self, "Connect Bank", T.menuOption(BankMenu.addBankOptions, bank.object,
                getText("ContextMenu_RenewableEnergy_ConnectBank")), bank.square) then
                return
            end
            T.waitFor(self, function() return bank.object:isConnected() end, "this client's copy of the connected bank")
            T.step(function()
                self.connectedPickUp = canPickUp()
                if not T.chooseOption(self, "Disconnect Bank", T.menuOption(BankMenu.addBankOptions, bank.object,
                    getText("ContextMenu_RenewableEnergy_DisconnectBank"))) then
                    return
                end
                T.waitFor(self, function() return not bank.object:isConnected() end, "this client's copy of the disconnected bank")
                T.step(function() self.disconnectedPickUp = canPickUp() end)
            end)
        end)
    end,
    validate = function(self)
        if not T.expectOffered(self, "Connect Bank") then return end
        expect(not self.connectedPickUp, "a connected bank can be picked up")
        if not T.expectOffered(self, "Disconnect Bank") then return end
        expect(self.disconnectedPickUp, "a disconnected empty bank can't be picked up")
    end,
})

local function canConnect(panel, bank)
    return RenewableEnergyAction:new(player(), "source", SourceJobs.CONNECT, panel.object, bank.object):canPerform()
end

-- A source connects only to a bank that is connected itself. An unconnected bank in reach is still
-- listed, greyed saying why, as is its Connect Sources in Reach; the action won't start and the
-- authority refuses. Once the bank is connected all of them take the panel, and disconnecting the
-- bank afterwards leaves the panel on it.
test("renewable_energy_bank_sources_need_a_connected_bank", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER }, { connected = false })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank })
        if not self.panel then return end
        local bank, panel = self.bank, self.panel
        -- Light to work by indoors, and the level Connect Bank takes.
        T.holdLight(self)
        T.setPerk(self, Perks.Electricity, 3)
        T.step(function()
            self.unconnected = T.connectOptions(bank, panel, 1)
            self.unconnectedAction = canConnect(panel, bank)
        end)
        T.job(self, "source", SourceJobs.CONNECT, panel, bank, "refused")
        T.job(self, "bank", BankJobs.CONNECT, bank, nil, "bankConnected")
        T.waitFor(self, function() return bank.object:isConnected() end, "this client's copy of the connected bank")
        T.step(function()
            self.connected = T.connectOptions(bank, panel, 1)
            self.connectedAction = canConnect(panel, bank)
        end)
        T.job(self, "source", SourceJobs.CONNECT, panel, bank, "accepted")
        T.job(self, "bank", BankJobs.DISCONNECT, bank, nil, "bankDisconnected")
        T.readRecord(self, bank)
    end,
    validate = function(self)
        local key = "Tooltip_RenewableEnergy_BankNotConnected"
        local before, after = self.unconnected, self.connected
        for name, option in pairs({ ["the panel's Connect"] = before.one, ["Connect Sources in Reach"] = before.all }) do
            expect(option.shown and option.greyed, name .. " isn't offered greyed out for a bank that isn't connected")
            expectEqual(name .. "'s tooltip", option.reason, getText(key))
        end
        expect(not self.unconnectedAction, "the Connect action starts for a bank that isn't connected")
        T.expectRefused(self.reads.refused, key, "the authority connected a panel to a bank that isn't connected")
        if not T.expectOk(self.reads.bankConnected, "connecting the bank") then
            return
        end
        for name, option in pairs({ ["the panel's Connect"] = after.one, ["Connect Sources in Reach"] = after.all }) do
            expect(option.shown and not option.greyed, name .. " isn't open for a connected bank (" .. tostring(option.reason) .. ")")
        end
        expect(self.connectedAction, "the Connect action doesn't start for a connected bank")
        T.expectOk(self.reads.accepted, "putting a panel on a connected bank")
        T.expectOk(self.reads.bankDisconnected, "disconnecting the bank")
        expect(T.stateSource(self.bank.state, self.panel) ~= nil, "disconnecting the bank dropped its panel")
    end,
})

-- A battery box and a battery rack in reach of a panel are both offered to it. A panel already on
-- one of them names that one as what it is connected to instead of offering it again.
test("renewable_energy_bank_box_and_rack_both_offered", {
    run = function(self)
        self.box = T.bank(self, "batteryBoxWood", {})
        self.rack = self.box and T.bank(self, "batteryRackWood", {}, { near = self.box })
        self.panel = self.rack and T.panel(self, Sprites.rack.wood.S, { near = self.box })
        if not self.panel then return end
        local box, rack, panel = self.box, self.rack, self.panel
        T.holdLight(self)
        T.step(function()
            if not T.need(self, Sources.isInReach(box, panel.x, panel.y, panel.z)
                and Sources.isInReach(rack, panel.x, panel.y, panel.z), "the box and the rack in reach of the panel") then
                return
            end
            self.offered = { box = T.connectOptions(box, panel, 1).one, rack = T.connectOptions(rack, panel, 1).one }
        end)
        T.job(self, "source", SourceJobs.CONNECT, panel, box, "onBox")
        T.waitFor(self, function() return Squares.samePosition(PowerBank.connectedBank(panel.object), box) end,
            "this client's summary of the box listing the panel")
        T.step(function()
            -- Each fresh context reuses the player's one context menu, so read this one first.
            local wiredTo = T.optionState(T.menuOption(SourceMenu.addSourceOptions, panel.object, getText("ContextMenu_RenewableEnergy_WiredTo",
                Format.bankName(PowerBank.summaryOf(box.object)), Format.away(panel, box))))
            self.wired = { wiredTo = wiredTo, box = T.connectOptions(box, panel, 1).one, rack = T.connectOptions(rack, panel, 1).one }
        end)
    end,
    validate = function(self)
        for name, option in pairs(self.offered) do
            expect(option.shown and not option.greyed, "the " .. name .. " isn't offered open (" .. tostring(option.reason) .. ")")
        end
        T.expectOk(self.reads.onBox, "putting the panel on the box")
        local wired = self.wired
        expect(wired.wiredTo.shown, "a panel on the box doesn't say it is connected to the box")
        expect(not wired.box.shown, "a panel on the box offers to connect to the box again")
        expect(wired.rack.shown and not wired.rack.greyed, "a panel on the box isn't offered the rack")
    end,
})
