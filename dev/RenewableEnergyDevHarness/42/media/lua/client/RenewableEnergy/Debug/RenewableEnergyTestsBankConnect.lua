require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local BankMenu = require "RenewableEnergy/UI/BankMenu"
local Squares = require "cf_commonlib/Squares"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sprites = require "RenewableEnergy/Sprites"

-- Power bank tests: connecting banks, and sources to them.
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectEqual, player = T.test, T.expect, T.expectEqual, T.player

-- Connecting -----------------------------------------------------------------------------------

-- A bank starts unconnected, like a generator: switched on it powers nothing, nor a square near it,
-- and its status says so, until it is connected; then both have power, here too. As vanilla's
-- generator, a connected bank that is on offers no Disconnect and the authority refuses one, so a
-- running bank can't be unplugged into a state where it powers what it no longer feeds.
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
        T.waitFor(self, function() return bank.object:isConnected() end, "this client's copy of the connected bank")
        T.step(function()
            self.disconnectWhileOn = T.menuOption(BankMenu.addBankOptions, bank.object,
                getText("ContextMenu_RenewableEnergy_DisconnectBank"))
        end)
        T.job(self, "bank", BankJobs.DISCONNECT, bank, nil, "disconnectedOn")
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
        expect(self.disconnectWhileOn == nil, "the menu offers to disconnect a bank that is on")
        T.expectRefused(self.reads.disconnectedOn, "already on", "the authority disconnected a bank that is on")
    end,
})

-- Vanilla's recipe of the generator magazine.
local GENERATOR = { "Generator" }

-- Connecting a bank takes what connecting a generator does in vanilla: the Electricity level or
-- the "Generator" recipe, enforced by the authority.
test("renewable_energy_bank_connect_needs_generator_skill", {
    run = function(self)
        self.unskilled = T.bank(self, "batteryBoxWood", {}, { connected = false })
        self.magazine = self.unskilled and T.bank(self, "batteryBoxWood", {}, { connected = false, near = self.unskilled })
        if not self.magazine then return end
        T.knowRecipes(self, GENERATOR, false)
        T.setPerk(self, Perks.Electricity, 2)
        T.job(self, "bank", BankJobs.CONNECT, self.unskilled, nil, "refused")
        -- T.setPerk sets the level when called, so the later levels wait for their turn.
        T.step(function() T.setPerk(self, Perks.Electricity, 3) end)
        T.job(self, "bank", BankJobs.CONNECT, self.unskilled, nil, "skilled")
        T.step(function() T.setPerk(self, Perks.Electricity, 2) end)
        T.knowRecipes(self, GENERATOR)
        T.job(self, "bank", BankJobs.CONNECT, self.magazine, nil, "withRecipe")
    end,
    validate = function(self)
        T.expectRefused(self.reads.refused, "ContextMenu_GeneratorPlugTT",
            "the authority connected a bank at Electricity 2 without the Generator recipe")
        T.expectOk(self.reads.skilled, "connecting a bank at Electricity 3")
        T.expectOk(self.reads.withRecipe, "connecting a bank with the Generator recipe")
    end,
})

-- A bank tile a player places becomes a working bank that isn't connected yet, as a generator set
-- down isn't. Connect Bank from the menu connects it, Disconnect Bank undoes it, and only a
-- disconnected bank can be picked up, as with a generator.
test("renewable_energy_bank_connect_and_disconnect", {
    instant = true,
    run = function(self)
        local square = T.square(self, { indoors = true }, "a free indoor square for a bank")
        if not square then return end
        -- Light to connect by, which an unlit room lacks.
        T.holdLight(self)
        -- Placing and picking up a bank tile need the Electrician tool.
        T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
        T.placeAsPlayer(self, square, "RenewableEnergy.BatteryBoxWood", Sprites.batteryBoxWood.S)
        local bank = { square = square }
        T.waitFor(self, function()
            bank.object = PowerBank.findOn(square)
            return bank.object ~= nil and PowerBank.summaryOf(bank.object) ~= nil
        end, "this client's copy of the placed bank, working")
        local function canPickUp()
            local object = bank.object
            return ISMoveableSpriteProps.new(object:getSprite():getName()):canPickUpMoveable(player(), bank.square, object)
        end
        T.step(function()
            self.placedConnected = bank.object:isConnected()
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
        expect(not self.placedConnected, "a bank the player placed starts connected")
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
            expect(option.shown and option.greyed and tostring(option.reason):find(getText(key), 1, true) ~= nil,
                name .. " isn't greyed out saying the bank isn't connected (" .. tostring(option.reason) .. ")")
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

-- A source is offered every bank in its reach, a battery box and a battery rack alike, each by its
-- own Connect. One already on a bank doesn't offer that bank again but still offers the other, to
-- move over; neither bank's Connect Sources in Reach counts it, as it moves only by its own
-- Connect.
test("renewable_energy_bank_source_offered_every_bank_in_reach", {
    run = function(self)
        self.box = T.bank(self, "batteryBoxWood", {})
        self.rack = self.box and T.bank(self, "batteryRackWood", {}, { near = self.box })
        self.wired = self.rack and T.panel(self, Sprites.rack.wood.S, { near = self.box, connect = true })
        self.loose = self.wired and T.panel(self, Sprites.flat, { near = self.box })
        if not self.loose then return end
        local box, rack, wired, loose = self.box, self.rack, self.wired, self.loose
        T.holdLight(self)
        T.step(function()
            local function inReach(bank, panel) return PowerBank.inSourceReach(bank, panel.x, panel.y, panel.z) end
            if not T.need(self, inReach(box, wired) and inReach(rack, wired) and inReach(box, loose) and inReach(rack, loose),
                "both panels in reach of the box and the rack") then
                return
            end
            -- Each fresh context reuses the player's one context menu, so each read is taken whole.
            self.offers = {
                looseBox = T.connectOptions(box, loose, 1), looseRack = T.connectOptions(rack, loose, 1),
                wiredBox = T.connectOptions(box, wired, 1), wiredRack = T.connectOptions(rack, wired, 1),
            }
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.wired) then return end
        local function open(option) return option.shown and not option.greyed end
        local offers = self.offers
        for name, option in pairs({ box = offers.looseBox.one, rack = offers.looseRack.one }) do
            expect(open(option), "a loose panel isn't offered the " .. name .. " (" .. tostring(option.reason) .. ")")
        end
        expect(not offers.wiredBox.one.shown, "a panel on the box offers to connect to the box again")
        expect(open(offers.wiredRack.one), "a panel on the box isn't offered the rack (" .. tostring(offers.wiredRack.one.reason) .. ")")
        -- Found by its count: one that counted the panel on the box would read 2.
        expect(open(offers.looseBox.all), "the box's Connect Sources in Reach doesn't count only the loose panel")
        expect(open(offers.looseRack.all), "the rack's Connect Sources in Reach doesn't count only the loose panel")
    end,
})

-- Whether the moveables cursor would pick up and turn the object drawn as `sprite` on `handle`,
-- and whether its panel says to disconnect it first.
local function takeable(handle, sprite)
    local object = PZHarness.Fixtures.objectWithSprite(handle.square, sprite)
    local props = ISMoveableSpriteProps.fromObject(object)
    local refusal = "- " .. getText("Tooltip_RenewableEnergy_DisconnectFirst")
    local says = false
    for _, line in ipairs(props:getInfoPanelDescription(handle.square, object, player(), "pickup")) do
        says = says or line[1].txt == refusal
    end
    return { pickUp = props:canPickUpMoveable(player(), handle.square, object),
        rotate = props:canRotateMoveable(handle.square, object, props), says = says }
end

-- Like a connected generator, a source connected to a bank can't be picked up or turned, and the
-- cursor's panel says to disconnect it first; a treadmill's unwired tile counts as its wired one.
-- Disconnected, a rack picks up, and put back down where it stood it feeds nothing. Catches a
-- source taken or turned while connected, which drops it from its bank unseen, and one that comes
-- back connected.
test("renewable_energy_bank_connected_source_stays_put", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {})
        self.rack = self.bank and T.panel(self, Sprites.rack.wood.S, { near = self.bank, connect = true })
        self.treadmill = self.rack and T.panel(self, Sprites.treadmill.W.rear, { near = self.bank, connect = true, wired = true })
        local square = self.treadmill and self.treadmill.square
        self.console = square and T.panel(self, Sprites.treadmill.W.console,
            { square = getSquare(square:getX() - 1, square:getY(), square:getZ()) })
        if not self.console then return end
        local rack = self.rack
        -- The tiles' Electrician pick-up tool, and light to disconnect by.
        T.setPerk(self, Perks.Electricity, 10)
        T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
        T.holdLight(self)
        T.step(function()
            self.connectedRack = takeable(rack, Sprites.rack.wood.S)
            self.connectedTreadmill = takeable(self.console, Sprites.treadmill.W.console)
        end)
        T.job(self, "source", SourceJobs.DISCONNECT, rack, nil, "disconnected")
        T.waitFor(self, function() return PowerBank.bankOfSource(rack.x, rack.y, rack.z) == nil end,
            "this client's summary of the bank without the rack")
        T.step(function() self.disconnectedRack = takeable(rack, Sprites.rack.wood.S) end)
        T.pickUpAsPlayer(self, rack, Sprites.rack.wood.S)
        T.placeAsPlayer(self, rack.square, "RenewableEnergy.SolarRackWood", Sprites.rack.wood.S, nil, true)
        T.readRecord(self, self.bank, "putBack")
        T.step(function() self.clientPutBack = PowerBank.bankOfSource(rack.x, rack.y, rack.z) end)
    end,
    validate = function(self)
        expect(self.rack.connected and self.treadmill.connected, "the bank refused a source: " .. tostring(self.rack.reason or self.treadmill.reason))
        local rack, treadmill, loose = self.connectedRack, self.connectedTreadmill, self.disconnectedRack
        expect(not rack.pickUp, "a connected rack can be picked up")
        expect(not rack.rotate, "a connected rack can be turned")
        expect(rack.says, "the cursor's panel doesn't say to disconnect the connected rack first")
        expect(not treadmill.pickUp, "a connected treadmill can be picked up by its unwired tile")
        expect(treadmill.says, "the cursor's panel doesn't say to disconnect the treadmill first")
        T.expectOk(self.reads.disconnected, "disconnecting the rack")
        expect(loose.pickUp and loose.rotate, "a disconnected rack can't be picked up or turned")
        expect(not loose.says, "the cursor's panel says to disconnect a disconnected rack")
        local listed = false
        for _, source in ipairs(self.reads.putBack.summary.sources) do
            listed = listed or Squares.samePosition(source, self.rack)
        end
        expect(not listed, "the bank feeds from the rack put back where it stood")
        expect(self.clientPutBack == nil, "this client sees the rack put back connected")
    end,
})
