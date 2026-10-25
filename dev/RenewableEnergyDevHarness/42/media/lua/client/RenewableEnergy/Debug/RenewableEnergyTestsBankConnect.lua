require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "ISUI/ISContextMenu"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/Menu"

-- Power bank tests: connecting banks, and sources to them.
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, player = T.test, T.expect, T.player
local Action = RenewableEnergyAction
local Sprites = RenewableEnergy.Sprites
local PowerBank = RenewableEnergy.PowerBank
local Format, Menu = RenewableEnergy.Format, RenewableEnergy.Menu
local CAR_BATTERY = RenewableEnergy.VehicleBattery.CAR_BATTERY
local PLUG_IN_INVERTER, INVERTER_CHARGER, L16 = T.PLUG_IN_INVERTER, T.INVERTER_CHARGER, T.L16

-- Connecting -----------------------------------------------------------------------------------

-- A bank starts unconnected, like a generator: switched on it powers nothing, nor a square near it,
-- and its status says so, until it is connected; then both have power, here too.
test("renewable_energy_bank_needs_connecting", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { L16, INVERTER_CHARGER }, { connected = false })
        if not bank then return end
        self.bank = bank
        self.near = T.square(self, { near = bank }, "a square near the bank")
        if not self.near then return end
        T.switchOn(self, bank)
        T.bankState(self, bank)
        T.step(function()
            self.before = bank.state
            self.nearBefore = self.near:haveElectricity()
        end)
        T.performInto(self, "connected", "setBankConnected", { bank = bank.position, connected = true })
        T.waitFor(self, function() return bank.square:haveElectricity() and self.near:haveElectricity() end,
            "power on the connected bank's square and the square near it here")
        T.bankState(self, bank)
    end,
    validate = function(self)
        local before, after = self.before, self.bank.state
        expect(before.on and not before.activated and not before.powered, "an unconnected bank that is on powered its square")
        expect(not self.nearBefore, "an unconnected bank that is on powered a square near it")
        expect(before.status.state == "disconnected", "the unconnected bank's status says " .. tostring(before.status.state))
        T.expectOk(self.connected, "connecting the bank")
        expect(after.activated and after.powered, "the connected bank doesn't power its square")
        expect(after.status.state == "on", "the connected bank's status says " .. tostring(after.status.state))
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

-- Makes the character know vanilla's "Generator" recipe (the generator magazine's) or not, on both
-- sides. This client's copy goes back when the test ends; the server undoes no recipe change, so the
-- test sets the server's back itself.
local function knowGenerator(self, known)
    local p, names = player(), { "Generator" }
    local function apply(learn)
        if learn then
            PZHarness.Fixtures.learnRecipes(p, names)
        else
            PZHarness.Fixtures.forgetRecipes(p, names)
        end
    end
    local was = p:getKnownRecipes():contains("Generator")
    apply(known)
    T.defer(self, function() apply(was) end)
    if isClient() then
        T.server(self, known and "PZHarness.learnRecipes" or "PZHarness.forgetRecipes", { names = names })
    end
end

-- Connecting a bank takes what connecting a generator does in vanilla: the Electricity level or
-- the "Generator" recipe, enforced by the menu, the action and the authority.
test("renewable_energy_bank_connect_needs_generator_skill", {
    run = function(self)
        self.unskilled = T.bank(self, "batteryBoxWood", {}, { connected = false })
        self.magazine = self.unskilled and T.bank(self, "batteryBoxWood", {}, { connected = false, near = self.unskilled })
        if not self.magazine then return end
        self.knewGenerator = player():getKnownRecipes():contains("Generator")
        knowGenerator(self, false)
        T.setPerk(self, Perks.Electricity, 2)
        T.step(function()
            self.connect = T.optionState(T.menuOption(Menu.addBankOptions, self.unskilled.object,
                getText("ContextMenu_RenewableEnergy_ConnectBank")))
            self.canStart = Action:new(player(), Action.CONNECT_BANK, nil, self.unskilled.object):canPerform()
        end)
        T.performInto(self, "refused", "setBankConnected", { bank = self.unskilled.position, connected = true })
        -- T.setPerk sets the level when called, so the later levels wait for their turn.
        T.step(function() T.setPerk(self, Perks.Electricity, 3) end)
        T.performInto(self, "skilled", "setBankConnected", { bank = self.unskilled.position, connected = true })
        T.step(function()
            T.setPerk(self, Perks.Electricity, 2)
            knowGenerator(self, true)
        end)
        T.performInto(self, "withRecipe", "setBankConnected", { bank = self.magazine.position, connected = true })
        T.step(function() knowGenerator(self, self.knewGenerator) end)
    end,
    validate = function(self)
        expect(self.connect.greyed and self.connect.reason == getText("ContextMenu_GeneratorPlugTT"),
            "at Electricity 2 Connect Bank isn't greyed out with vanilla's reason (" .. tostring(self.connect.reason) .. ")")
        expect(not self.canStart, "Connect Bank can start at Electricity 2 without the Generator recipe")
        T.expectRefused(self.refused, "ContextMenu_GeneratorPlugTT",
            "the authority connected a bank at Electricity 2 without the Generator recipe")
        T.expectOk(self.skilled, "connecting a bank at Electricity 3")
        T.expectOk(self.withRecipe, "connecting a bank with the Generator recipe")
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
            local option = T.menuOption(Menu.addBankOptions, bank.object, getText("ContextMenu_RenewableEnergy_ConnectBank"))
            self.offered = option ~= nil and not option.notAvailable
            if not self.offered then return end
            T.standNextTo(bank.square)
            T.choose(option)
            T.waitFor(self, function() return bank.object:isConnected() end, "this client's copy of the connected bank")
            T.step(function()
                self.connectedPickUp = canPickUp()
                local option = T.menuOption(Menu.addBankOptions, bank.object, getText("ContextMenu_RenewableEnergy_DisconnectBank"))
                self.disconnectOffered = option ~= nil and not option.notAvailable
                if not self.disconnectOffered then return end
                T.choose(option)
                T.waitFor(self, function() return not bank.object:isConnected() end, "this client's copy of the disconnected bank")
                T.step(function() self.disconnectedPickUp = canPickUp() end)
            end)
        end)
    end,
    validate = function(self)
        if not expect(self.offered, "an unconnected bank's menu offers no Connect Bank") then return end
        expect(not self.connectedPickUp, "a connected bank can be picked up")
        if not expect(self.disconnectOffered, "a connected bank that is off offers no Disconnect Bank") then return end
        expect(self.disconnectedPickUp, "a disconnected empty bank can't be picked up")
    end,
})

local function canConnect(panel, bank)
    return Action:new(player(), Action.CONNECT_SOURCE, panel.object, bank.object):canPerform()
end

-- A source connects only to a bank that is connected itself. An unconnected bank in reach is still
-- listed, greyed saying why, as is its Connect Sources in Reach; the action won't start and the
-- authority refuses. Once the bank is connected all of them take the panel, and disconnecting the
-- bank afterwards leaves the panel on it.
test("renewable_energy_bank_sources_need_a_connected_bank", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, PLUG_IN_INVERTER }, { connected = false })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank })
        if not self.panel then return end
        local bank, panel = self.bank, self.panel
        local args = { bank = bank.position, source = panel.position }
        -- Light to work by indoors, and the level Connect Bank takes.
        T.holdLight(self)
        T.setPerk(self, Perks.Electricity, 3)
        T.step(function()
            self.unconnected = T.connectOptions(bank, panel, 1)
            self.unconnectedAction = canConnect(panel, bank)
        end)
        T.performInto(self, "refused", "connectSource", args)
        T.performInto(self, "bankConnected", "setBankConnected", { bank = bank.position, connected = true })
        T.waitFor(self, function() return bank.object:isConnected() end, "this client's copy of the connected bank")
        T.step(function()
            self.connected = T.connectOptions(bank, panel, 1)
            self.connectedAction = canConnect(panel, bank)
        end)
        T.performInto(self, "accepted", "connectSource", args)
        T.performInto(self, "bankDisconnected", "setBankConnected", { bank = bank.position, connected = false })
        T.bankState(self, bank)
    end,
    validate = function(self)
        local key = "Tooltip_RenewableEnergy_BankNotConnected"
        local before, after = self.unconnected, self.connected
        for name, option in pairs({ ["the panel's Connect"] = before.one, ["Connect Sources in Reach"] = before.all }) do
            expect(option.shown and option.greyed and option.reason == getText(key),
                name .. " isn't offered greyed out saying the bank isn't connected (" .. tostring(option.reason) .. ")")
        end
        expect(not self.unconnectedAction, "the Connect action starts for a bank that isn't connected")
        T.expectRefused(self.refused, key, "the authority connected a panel to a bank that isn't connected")
        if not T.expectOk(self.bankConnected, "connecting the bank") then
            return
        end
        for name, option in pairs({ ["the panel's Connect"] = after.one, ["Connect Sources in Reach"] = after.all }) do
            expect(option.shown and not option.greyed, name .. " isn't open for a connected bank (" .. tostring(option.reason) .. ")")
        end
        expect(self.connectedAction, "the Connect action doesn't start for a connected bank")
        T.expectOk(self.accepted, "putting a panel on a connected bank")
        T.expectOk(self.bankDisconnected, "disconnecting the bank")
        expect(T.stateSource(self.bank.state, self.panel.position) ~= nil, "disconnecting the bank dropped its panel")
    end,
})

-- A battery box and a battery rack in reach of a panel are both offered to it: greyed while they
-- aren't connected, open once they are. A panel already on one of them names that one as what it
-- is connected to instead of offering it again.
test("renewable_energy_bank_box_and_rack_both_offered", {
    run = function(self)
        self.box = T.bank(self, "batteryBoxWood", {}, { connected = false })
        self.rack = self.box and T.bank(self, "batteryRackWood", {}, { connected = false, near = self.box })
        self.panel = self.rack and T.panel(self, Sprites.rack.wood.S, { near = self.box })
        if not self.panel then return end
        local box, rack, panel = self.box, self.rack, self.panel
        T.holdLight(self)
        T.setPerk(self, Perks.Electricity, 3)
        T.step(function()
            local here = panel.position
            if not T.need(self, PowerBank.isInReach(box.position, here.x, here.y, here.z)
                and PowerBank.isInReach(rack.position, here.x, here.y, here.z), "the box and the rack in reach of the panel") then
                return
            end
            self.unconnected = { box = T.connectOptions(box, panel, 1).one, rack = T.connectOptions(rack, panel, 1).one }
        end)
        T.performInto(self, "boxConnected", "setBankConnected", { bank = box.position, connected = true })
        T.performInto(self, "rackConnected", "setBankConnected", { bank = rack.position, connected = true })
        T.waitFor(self, function() return box.object:isConnected() and rack.object:isConnected() end,
            "this client's copies of the connected box and rack")
        T.step(function()
            self.connected = { box = T.connectOptions(box, panel, 1).one, rack = T.connectOptions(rack, panel, 1).one }
        end)
        T.performInto(self, "onBox", "connectSource", { bank = box.position, source = panel.position })
        T.waitFor(self, function() return PowerBank.samePosition(PowerBank.connectedBank(panel.object), box.position) end,
            "this client's summary of the box listing the panel")
        T.step(function()
            -- Each fresh context reuses the player's one context menu, so read this one first.
            local wiredTo = T.optionState(T.menuOption(Menu.addSourceOptions, panel.object, getText("ContextMenu_RenewableEnergy_WiredTo",
                Format.bankName(PowerBank.summaryOf(box.object)), Format.away(panel.position, box.position))))
            self.wired = { wiredTo = wiredTo, box = T.connectOptions(box, panel, 1).one, rack = T.connectOptions(rack, panel, 1).one }
        end)
    end,
    validate = function(self)
        local notConnected = getText("Tooltip_RenewableEnergy_BankNotConnected")
        for name, option in pairs(self.unconnected) do
            expect(option.shown and option.greyed and option.reason == notConnected,
                "the unconnected " .. name .. " isn't offered greyed out saying it isn't connected (" .. tostring(option.reason) .. ")")
        end
        expect(self.boxConnected.ok and self.rackConnected.ok, "the authority refused to connect the box or the rack")
        for name, option in pairs(self.connected) do
            expect(option.shown and not option.greyed, "the connected " .. name .. " isn't offered open (" .. tostring(option.reason) .. ")")
        end
        T.expectOk(self.onBox, "putting the panel on the box")
        local wired = self.wired
        expect(wired.wiredTo.shown, "a panel on the box doesn't say it is connected to the box")
        expect(not wired.box.shown, "a panel on the box offers to connect to the box again")
        expect(wired.rack.shown and not wired.rack.greyed, "a panel on the box isn't offered the rack")
    end,
})
