require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "TimedActions/ISInventoryTransferAction"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/Menu"
require "RenewableEnergy/UI/StatusWindow"
require "RenewableEnergy/Recipes"

-- Power bank tests (PowerBank/*, World/Failsafe.lua, UI/Menu.lua, UI/StatusWindow.lua, the bank
-- rows of Specs.lua and the bank recipes of Recipes.lua). Banks live on the authority: the
-- helpers drive and read its record through T.server; what players see is checked on this
-- client's copies.

local T = RenewableEnergyTest
local test, craftTest, expect, expectNear, player, stateItem, copyItem = T.test, T.craftTest, T.expect, T.expectNear, T.player, T.stateItem, T.copyItem
local Action = RenewableEnergyAction
local Specs, Sprites, Sun, Recipes = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun, RenewableEnergy.Recipes
local PowerBank = RenewableEnergy.PowerBank
local SolarGardenLight = RenewableEnergy.SolarGardenLight
local Format, Menu, StatusWindow = RenewableEnergy.Format, RenewableEnergy.Menu, RenewableEnergy.StatusWindow
local function craftName(recipe, behavior) return T.craftName("bank", recipe, behavior) end
local FRIDGE = "appliances_refrigeration_01_0"
local MINI_FRIDGE = "appliances_refrigeration_01_25"
local PLUG_IN_INVERTER = "RenewableEnergy.PlugInInverter"
local INVERTER = "RenewableEnergy.InverterCharger"
local POWER_INVERTER = "RenewableEnergy.PowerInverter"

-- `base` and then as many `kind` appliances as a bank limited to `limitW` carries, with `over` one
-- more. Sums as the load does, so "carries" holds at the boundary.
local function loadUpTo(base, kind, limitW, over)
    local names = { unpack(base) }
    while T.applianceWatts(names) + T.applianceWatts({ kind }) <= limitW do
        table.insert(names, kind)
    end
    if over then table.insert(names, kind) end
    return names
end

-- The refusal reason in the command answer self[key], as a string.
local function reason(self, key)
    return tostring(self[key].reason)
end

-- Queues reading the backup generator on `square` into self[key]: { running, fuel, ... }
-- (RenewableEnergyTestServerGas.lua).
local function generatorState(self, square, key)
    T.server(self, "generatorRead", T.at(square))
    T.step(function() self[key] = self.server.generatorRead end)
end

local CHARGED_BATTERY = "Base.CarBattery1"

-- A free square within `reach` tiles of `near` for a backup generator: outdoors if there is one,
-- since a running generator makes a building toxic.
local function backupSquare(self, near, reach)
    local square
    for _, indoors in ipairs({ false, true }) do
        local candidate = not square and (T.squares(self, 1, { indoors = indoors, near = near }) or {})[1]
        if candidate and IsoUtils.DistanceToSquared(candidate:getX(), candidate:getY(), near:getX(), near:getY()) <= reach * reach then
            square = candidate
        end
    end
    return T.need(self, square, "a free square for a generator within " .. reach .. " tiles of the bank")
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

-- Whether the option's tooltip lists the item `fullType` in the colour for what the character is
-- short of.
local function marksShort(option, fullType)
    local text = T.tooltipOf(option) or ""
    return text:find(ISVehicleMechanics.bhs .. getItemNameFromFullType(fullType), 1, true) ~= nil
end

-- Charging and loads ---------------------------------------------------------------------------

-- An hour of full sun on a connected panel charges the bank by what the panel makes, and the
-- charge, the status and the tile's battery overlays reach this client's copies.
test("renewable_energy_bank_panel_charges_bank", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.2 })
        self.panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not self.panel then return end
        self.bank = bank
        T.watch(self, bank)
        T.bankState(self, bank)
        T.step(function() self.before = bank.state end)
        T.bankPass(self, bank, Sun.FULL_SUN)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return math.abs(T.copyUses(bank, "Base.CarBattery1") - bank.state.charge) < 0.001
                and status ~= nil and status.solarW == bank.state.status.solarW
                and T.overlays(bank.object) == table.concat(bank.state.overlays, ",")
        end, "this client's copies of the charged battery, the status and the overlays")
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        local after = self.bank.state
        local status, here = after.status, self.panel.position
        -- How watts follow the sun is sunlight_multiplier_and_snow's.
        expect(status.solarW > 0, "a connected panel in full sun makes nothing")
        expectNear("Wh gained in an hour", after.storedWh - self.before.storedWh, status.solarW, 0.5)
        expectNear("percent of full sun", status.sources[1] and status.sources[1].fullSunPct, 100, 0)
        local battery = stateItem(after, "Base.CarBattery1")
        expectNear("the battery's charge", battery and battery.uses, after.charge, 0.001)
        expectNear("this client's copy of the battery's charge", T.copyUses(self.bank, "Base.CarBattery1"), after.charge, 0.001)
        local copy = T.clientStatus(self.bank)
        expectNear("solar watts in this client's status", copy and copy.solarW, status.solarW, 0)
        expect(PowerBank.samePosition(PowerBank.bankOfSource(here.x, here.y, here.z), self.bank.position),
            "bankOfSource doesn't name the bank the panel was connected to")
        local overlays = table.concat(after.overlays, ",")
        expect(overlays ~= "", "the charged bank's tile shows no batteries")
        expect(T.overlays(self.bank.object) == overlays, "this client's copy of the bank shows " .. T.overlays(self.bank.object)
            .. ", the server's " .. overlays)
    end,
})

-- At night a bank that is on powers its squares, here too, and pays its inverter's idle draw and
-- losses on top of the appliances its pass finds; the pass takes that draw from the batteries.
test("renewable_energy_bank_powers_at_night", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", INVERTER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.bankState(self, bank)
        T.waitFor(self, function() return bank.square:haveElectricity() end, "power on the switched-on bank's square here")
        T.step(function() self.powered = bank.state.activated and bank.state.powered end)
        T.bankPass(self, bank, 0)
        T.step(function() self.without = bank.state end)
        -- A step, since single player places a tile at once.
        T.step(function() T.placeTile(self, fridge, MINI_FRIDGE) end)
        T.batch(function()
            T.bankPass(self, bank, 0)
            T.step(function() self.with = bank.state end)
            T.bankPass(self, bank, 0)
        end)
    end,
    validate = function(self)
        local after, without, with = self.bank.state, self.without.status, self.with.status
        expect(self.powered, "switching on a charged bank with an inverter did not power its square")
        local fridgeW = T.applianceWatts({ "fridgeFreezer" })
        expect(without.drawW > 0, "a bank that is on with nothing switched on draws nothing for its inverter")
        expect(with.drawW - without.drawW > fridgeW, string.format(
            "a fridge drawing %.1f W adds %.1f W to the draw, no inverter losses", fridgeW, with.drawW - without.drawW))
        expectNear("Wh used in an hour", self.with.storedWh - after.storedWh, after.status.drawW, 0.5)
        local charging = after.status.charging
        expect(charging.watts < 0 and charging.hours ~= nil, "the status doesn't say the bank is draining")
    end,
})

-- The scan sees what is switched on whether or not the bank powers it, so a cut bank knows when
-- the load fits again; and, as vanilla bills them, a mini fridge with its ice box is a fridge-freezer.
test("renewable_energy_bank_scan_sees_load_while_cut", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        if not bank then return end
        self.bank = bank
        local squares = T.need(self, T.squares(self, 2, { indoors = true, near = bank.square }), "two free indoor squares for fridges")
        if not squares then return end
        T.server(self, "scanLoad", bank.position)
        T.step(function()
            self.without = self.server.scanLoad
            T.placeTile(self, squares[1], FRIDGE)
            T.placeTile(self, squares[2], MINI_FRIDGE)
            T.bankState(self, bank)
            T.server(self, "scanLoad", bank.position)
        end)
    end,
    validate = function(self)
        local with, without = self.server.scanLoad, self.without
        expect(not self.bank.state.activated, "the bank was on while scanning")
        local function count(load, kind)
            return load.counts[kind] or 0
        end
        expectNear("fridge-freezers found, the mini fridge among them",
            count(with, "fridgeFreezer") - count(without, "fridgeFreezer"), 2, 0)
        expect(with.watts > without.watts, "the fridges added no watts to the scan's load")
    end,
})

-- Banks stand indoors only: placement is refused outdoors, and a bank found outdoors won't
-- switch on.
test("renewable_energy_bank_refused_outdoors", {
    run = function(self)
        T.setGrid(self, false)
        local indoor = T.square(self, { indoors = true }, "a free indoor square")
        local outdoor = T.square(self, {}, "a free outdoor square")
        if not (indoor and outdoor) then return end
        self.indoorOk = PowerBank.canPlaceBank(indoor)
        self.outdoorOk, self.reason = PowerBank.canPlaceBank(outdoor)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER }, { square = outdoor })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.perform(self, "setBankOn", { bank = bank.position, on = true })
        T.bankState(self, bank)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and status.state == "outdoors"
        end, "this client's status of the outdoor bank saying it must go inside")
    end,
    validate = function(self)
        local state = self.bank.state
        expect(self.indoorOk, "a bank is refused inside a building")
        expect(not self.outdoorOk and self.reason == "Tooltip_RenewableEnergy_BankIndoorsOnly",
            "a bank may stand outdoors (reason " .. tostring(self.reason) .. ")")
        expect(not state.activated and state.status.state == "outdoors",
            "a bank outdoors switched on (state " .. tostring(state.status.state) .. ")")
    end,
})

-- A removed running bank leaves nothing powered, on this client too, and is forgotten.
test("renewable_energy_bank_removed_bank_leaves_no_power", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "RenewableEnergy.L16Battery", INVERTER })
        if not bank then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.bankState(self, bank)
        T.waitFor(self, function() return bank.square:haveElectricity() end, "power on the switched-on bank's square here")
        T.server(self, "removeBank", { bank = bank.position })
        T.waitFor(self, function() return not bank.square:haveElectricity() and PowerBank.bankOn(bank.square) == nil end,
            "the removed bank and its power gone from this client")
    end,
    validate = function(self)
        local removed, square = self.server.removeBank, self.bank.square
        expect(self.bank.state.powered, "the switched-on bank didn't power its square")
        expect(not removed.powered, "the removed bank's square still has power")
        expect(not square:haveElectricity(), "the removed bank's square still has power on this client")
        expect(not removed.registered, "the removed bank is still registered")
        expect(PowerBank.bankOn(square) == nil and PowerBank.summaryOf(square) == nil, "this client still has the removed bank")
    end,
})

-- Inverters and overload -----------------------------------------------------------------------

-- A bank's limit is its working inverters' ratings together: a broken one drops out, on this
-- client's summary too.
test("renewable_energy_bank_limit_sums_working_inverters", {
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", { "Base.CarBattery1", POWER_INVERTER, POWER_INVERTER })
        if not self.bank then return end
        T.batch(function()
            T.bankState(self, self.bank)
            T.step(function() self.twoInverters = self.bank.state.limitW end)
            T.setPartCondition(self, self.bank, POWER_INVERTER, 0, true)
        end)
        T.waitFor(self, function()
            local summary = T.clientSummary(self.bank)
            return summary ~= nil and summary.limitW == self.bank.state.limitW
        end, "this client's summary with the broken inverter's limit")
    end,
    validate = function(self)
        local inverterW = Specs.inverters[POWER_INVERTER].watts
        expectNear("limit of two Power Inverters", self.twoInverters, 2 * inverterW, 0)
        expectNear("limit with one of them broken", self.bank.state.limitW, inverterW, 0)
        local summary = T.clientSummary(self.bank)
        expectNear("limit in this client's summary", summary and summary.limitW, inverterW, 0)
    end,
})

-- The inverter's condition in a bank state, or nil.
local function conditionOf(state, fullType)
    local item = stateItem(state, fullType)
    return item and item.condition
end

-- Fridges the inverter carries beside what the house already draws run; one more cuts the bank's
-- power at the next pass, which strains the inverter and shows in this client's status, and the
-- power comes back by itself at the pass after one is taken away.
test("renewable_energy_bank_overload_cuts_and_returns", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", INVERTER })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.switchOn(self, bank)
        T.bankPass(self, bank, 0)
        -- Steps, since single player places a tile at once.
        T.step(function()
            local status = bank.state.status
            local fit = math.floor((status.limitW - status.loadW) / T.applianceWatts({ "fridgeFreezer" }))
            local squares = T.need(self, fit >= 0 and T.squares(self, fit + 1, { indoors = true, near = bank.square }),
                fit + 1 .. " free indoor squares for fridges beside the " .. status.loadW .. " W the house draws")
            if not squares then return end
            for i = 1, fit do
                T.placeTile(self, squares[i], MINI_FRIDGE)
            end
            local last = squares[fit + 1]
            T.bankPass(self, bank, 0)
            T.step(function()
                self.fitting = bank.state
                T.placeTile(self, last, MINI_FRIDGE)
                T.bankPass(self, bank, 0)
                T.step(function() self.cut = bank.state end)
                T.waitFor(self, function()
                    local copy = T.clientStatus(bank)
                    return copy ~= nil and copy.overloaded == true
                end, "this client's status of the overloaded bank")
                T.step(function() self.copyCut = T.clientStatus(bank).state end)
                T.batch(function()
                    T.server(self, "removeTile", { x = last:getX(), y = last:getY(), z = last:getZ(), sprite = MINI_FRIDGE })
                    T.bankPass(self, bank, 0)
                end)
            end)
        end)
    end,
    validate = function(self)
        local fitting, cut, back = self.fitting, self.cut, self.bank.state
        expect(fitting.activated and not fitting.overloaded, string.format("fridges and the house, %.1f W in all, on a %.1f W"
            .. " inverter didn't run", fitting.status.loadW, fitting.status.limitW))
        local status = cut.status
        expect(not cut.activated and cut.overloaded and status.state == "overloaded",
            "a fridge over the limit didn't cut the power (state " .. tostring(status.state) .. ")")
        expect(status.loadW > status.limitW, "the cut bank's status shows " .. tostring(status.loadW) .. " W of load on a "
            .. tostring(status.limitW) .. " W limit")
        expect(self.copyCut == "overloaded", "this client's status of the cut bank reads " .. tostring(self.copyCut))
        -- The overload's strain, and the two hours on before it, which make no whole point.
        local wear = Specs.partWear
        expectNear("inverter condition before the overload", conditionOf(fitting, INVERTER), 100, 0)
        expectNear("inverter condition after the overload", conditionOf(cut, INVERTER),
            100 - math.floor(wear.perOverload.inverter + 2 * wear.perHour.inverter), 0)
        expect(back.activated and not back.overloaded, "the power didn't come back once the load fit")
    end,
})

-- Turn On without a working inverter is refused by every layer: the window's switch, the action
-- and the authority's command.
test("renewable_energy_bank_turn_on_refused_without_inverter", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" })
        if not self.bank then return end
        T.step(function() T.openWindow(self) end)
        T.perform(self, "setBankOn", { bank = self.bank.position, on = true })
        T.step(function() self.refused = self.server.perform end)
        T.bankState(self, self.bank)
    end,
    validate = function(self)
        local bank, button, why = self.bank.object, self.window.switchButton, getText("Tooltip_RenewableEnergy_NoInverter")
        expect(not Action:new(player(), Action.TURN_ON, nil, bank):canPerform(), "Turn On can start on a bank without an inverter")
        expect(not self.refused.ok and self.refused.reason == "Tooltip_RenewableEnergy_NoInverter",
            "the authority switched on a bank without an inverter (" .. tostring(self.refused.reason) .. ")")
        expect(not self.bank.state.on, "the bank without an inverter is on")
        expect(not button.enable and button.tooltip == why,
            "the window's switch isn't greyed out saying there's no inverter (" .. tostring(button.tooltip) .. ")")
    end,
})

-- Turn On with nothing to store a charge in is refused by every layer, as without an inverter: a
-- bank holding only an inverter, and one whose only battery is dead. Switched on, either would
-- power its area from nothing until its next pass.
test("renewable_energy_bank_turn_on_refused_without_batteries", {
    run = function(self)
        T.setGrid(self, false)
        self.empty = T.bank(self, "batteryBoxWood", { PLUG_IN_INVERTER })
        self.dead = self.empty and T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        if not self.dead then return end
        self.bank = self.empty
        T.setPartCondition(self, self.dead, "Base.CarBattery1", 0, true)
        T.waitFor(self, function()
            local battery = copyItem(self.dead, "Base.CarBattery1")
            return battery ~= nil and battery:getCondition() == 0
        end, "this client's copy of the dead battery")
        T.step(function() T.openWindow(self) end)
        T.batch(function()
            T.performInto(self, "emptyRefused", "setBankOn", { bank = self.empty.position, on = true })
            T.performInto(self, "deadRefused", "setBankOn", { bank = self.dead.position, on = true })
            T.bankState(self, self.empty)
            T.bankState(self, self.dead)
        end)
    end,
    validate = function(self)
        local key = "Tooltip_RenewableEnergy_NoBatteries"
        for _, case in ipairs({ { self.empty, self.emptyRefused, "holding no battery" },
            { self.dead, self.deadRefused, "whose only battery is dead" } }) do
            local bank, refused, what = case[1], case[2], case[3]
            expect(not Action:new(player(), Action.TURN_ON, nil, bank.object):canPerform(), "Turn On can start on a bank " .. what)
            expect(not refused.ok and refused.reason == key,
                "the authority switched on a bank " .. what .. " (" .. tostring(refused.reason) .. ")")
            expect(not bank.state.on and not bank.state.activated, "the bank " .. what .. " is on")
        end
        local button = self.window.switchButton
        expect(not button.enable and button.tooltip == getText(key),
            "the window's switch isn't greyed out saying there are no batteries (" .. tostring(button.tooltip) .. ")")
    end,
})

-- Parts: wiring and wear -----------------------------------------------------------------------

-- A bank's container refuses every transfer in and out, on this client's copy where the player
-- drags: parts move only by being wired. Other transfers still work.
test("renewable_energy_bank_container_refuses_transfers", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" })
        if not self.bank then return end
        T.give(self, "carried", { { type = "Base.Bag_Schoolbag" }, { type = "Base.Hammer" } })
        T.bankState(self, self.bank)
        -- Last: the queue drops everything after an action that turns out invalid when it starts.
        T.step(function()
            local p, container = player(), self.bank.object:getContainer()
            self.allowsBattery = container:isItemAllowed(instanceItem("Base.CarBattery2"))
            self.battery = container:getFirstType("Base.CarBattery1")
            local dragOut = ISInventoryTransferAction:new(p, self.battery, container, p:getInventory())
            self.dragValid = dragOut:isValid()
            ISTimedActionQueue.add(dragOut)
        end)
    end,
    validate = function(self)
        local p, bank, state = player(), self.bank.object, self.bank.state
        expect(PowerBank.isBank(bank), "the placed bank is not a bank")
        expect(not bank:isActivated() and not state.activated, "a bank that was never switched on powers its area")
        expect(not self.allowsBattery, "a battery can be dropped into a bank without wiring it in")
        expect(not self.dragValid, "moving a wired battery out of the bank is a valid transfer")
        expect(stateItem(state, "Base.CarBattery1") ~= nil and bank:getContainer():contains(self.battery)
            and not p:getInventory():contains(self.battery), "a wired battery was dragged out of the bank")
        local bag, hammer = self.items.carried[1], self.items.carried[2]
        expect(ISInventoryTransferAction:new(p, hammer, p:getInventory(), bag:getInventory()):isValid(),
            "moving a hammer into a bag is refused too")
    end,
})

-- Wiring a part in takes its tool, wire and skill, and a free slot; Electricity XP comes only
-- the first time an item is ever wired in; unwiring gives back the part and the wire.
test("renewable_energy_bank_wiring_needs_tool_wire_skill_and_slot", {
    run = function(self)
        local batteryWire, inverterWiring = PowerBank.wiringFor("Base.CarBattery1").wire, PowerBank.wiringFor(INVERTER)
        self.maxBatteries = Specs.banks["RenewableEnergy.BatteryBoxWood"].maxBatteries
        T.setPerk(self, Perks.Electricity, inverterWiring.skill - 1)
        local bank = T.bank(self, "batteryBoxWood", {})
        if not bank then return end
        self.bank = bank
        local function wire(key, fullType)
            T.performInto(self, key, "wireIn", { bank = bank.position }, { type = fullType })
        end
        -- A call with table args goes to the server ahead of T.give's wait for this client's
        -- copies, so a wire-in could use them up before they arrive; the step holds the calls
        -- after it.
        local function give(key, items)
            T.give(self, key, items)
            T.step(function() end)
        end
        give("first", { { type = "Base.CarBattery1" }, { type = "Base.Hammer" } })
        wire("hammer", "Base.Hammer")
        wire("noTool", "Base.CarBattery1")
        give("wrench", { { type = "Base.Wrench" } })
        wire("noWire", "Base.CarBattery1")
        give("wire", { { type = PowerBank.WIRE, count = batteryWire } })
        wire("wired", "Base.CarBattery1")
        T.count(self, "wired", { PowerBank.WIRE })
        T.performInto(self, "unwired", "unwire", { bank = bank.position }, { type = "Base.CarBattery1", inBank = true })
        T.count(self, "unwired", { PowerBank.WIRE, "Base.CarBattery1" })
        wire("rewired", "Base.CarBattery1")
        give("inverter", { { type = "Base.Screwdriver" }, { type = PowerBank.WIRE, count = inverterWiring.wire }, { type = INVERTER } })
        wire("skill", INVERTER)
        -- The rest of the slots, and one battery more.
        give("batteries", { { type = PowerBank.WIRE, count = self.maxBatteries * batteryWire },
            { type = "Base.CarBattery2", count = self.maxBatteries } })
        self.filled = {}
        for i = 2, self.maxBatteries do
            wire("fill" .. i, "Base.CarBattery2")
            T.step(function() table.insert(self.filled, self["fill" .. i]) end)
        end
        wire("full", "Base.CarBattery2")
        T.bankState(self, bank)
    end,
    validate = function(self)
        expect(reason(self, "hammer") == "Tooltip_RenewableEnergy_NotAPart", "a hammer was wired in (" .. reason(self, "hammer") .. ")")
        expect(reason(self, "noTool") == "tool", "a battery was wired in without a wrench (" .. reason(self, "noTool") .. ")")
        expect(reason(self, "noWire") == "wire", "a battery was wired in without wire (" .. reason(self, "noWire") .. ")")
        expect(self.wired.ok, "wiring a battery in with a wrench and wire failed (" .. reason(self, "wired") .. ")")
        expect(self.wired.xpAfter > self.wired.xpBefore, "the first wiring gave no Electricity XP")
        expectNear("wire left after wiring a battery in", self.counts.wired[PowerBank.WIRE], 0, 0)
        expect(self.unwired.ok and self.counts.unwired["Base.CarBattery1"] == 1, "unwiring didn't give the battery back")
        expectNear("wire back after unwiring", self.counts.unwired[PowerBank.WIRE], PowerBank.wiringFor("Base.CarBattery1").wire, 0)
        expect(self.rewired.ok, "wiring the battery in again failed (" .. reason(self, "rewired") .. ")")
        expectNear("XP for wiring the same battery again", self.rewired.xpAfter - self.rewired.xpBefore, 0, 0)
        expect(reason(self, "skill") == "skill", "an Inverter/Charger was wired in a level below its skill (" .. reason(self, "skill") .. ")")
        for i, answer in ipairs(self.filled) do
            expect(answer.ok, "a battery box refused battery " .. (i + 1) .. " of " .. self.maxBatteries .. " (" .. tostring(answer.reason) .. ")")
        end
        expect(reason(self, "full") == "Tooltip_RenewableEnergy_NoSlot", "a full battery box took another battery (" .. reason(self, "full") .. ")")
        expectNear("batteries in the full box", self.bank.state.batteries, self.maxBatteries, 0)
    end,
})

-- In the dark nothing can be wired in or out: the menu greys them out and the action, the rule
-- since a server can't tell whether a remote player stands in the dark, won't start.
test("renewable_energy_bank_wiring_refused_in_the_dark", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", POWER_INVERTER })
        if not self.bank then return end
        T.give(self, "parts", { { type = "Base.CarBattery2" }, { type = "Base.Wrench" }, { type = PowerBank.WIRE } })
        T.makeDark(self)
    end,
    validate = function(self)
        local p = player()
        if not expect(p:tooDarkToRead(), "midnight with the grid off isn't dark where the character stands") then return end
        local bank, battery = self.bank.object, self.items.parts[1]
        local context = T.newContext()
        local wireIn = optionFor(Menu.addWireInOptions(0, context, bank), battery)
        local dark = getText("Tooltip_RenewableEnergy_TooDark")
        expect(wireIn ~= nil and wireIn.notAvailable and T.tooltipOf(wireIn) == dark,
            "Wire In isn't greyed out saying it's too dark (" .. tostring(T.tooltipOf(wireIn)) .. ")")
        local unwire = Menu.addUnwireOptions(0, context, bank)
        local allDark = unwire ~= nil and #unwire.options > 0
        for _, option in ipairs(unwire and unwire.options or {}) do
            allDark = allDark and option.notAvailable and T.tooltipOf(option) == dark
        end
        expect(allDark, "a part can be unwired in the dark")
        context:hideAndChildren()
        expect(not Action:new(p, Action.WIRE_IN, nil, bank, nil, battery):isValid(), "the Wire In action runs in the dark")
    end,
})

-- Queues repairing the first Inverter/Charger in `bank` as the server's character, leaving the
-- answer in self[key].
local function repair(self, key, bank)
    T.performInto(self, key, "repairPart", { bank = bank.position }, { type = INVERTER, inBank = true })
end

-- Hours of a wear pass: long enough for an inverter's wear to make whole points.
local WEAR_HOURS = 20
-- Inverters and controllers wear in proportion to the hours their bank powers its area and not
-- while it is off, a part at 0 does nothing, and Electronics Scrap repairs a part only at its skill
-- and only if worn.
test("renewable_energy_bank_part_wear_and_repair", {
    run = function(self)
        T.setGrid(self, false)
        T.setPerk(self, Perks.Electricity, Specs.partRepair.skill - 1)
        local parts = { INVERTER, Specs.controller }
        for _ = 1, Specs.banks["RenewableEnergy.BatteryRackMetal"].maxBatteries do
            table.insert(parts, "RenewableEnergy.L16Battery")
        end
        local bank = T.bank(self, "batteryRackMetal", parts)
        if not bank then return end
        self.bank = bank
        T.switchOn(self, bank)
        -- Charged full before each pass, so that what the houses around draw doesn't run the bank
        -- empty, which would stop its parts' wear.
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = WEAR_HOURS })
            T.step(function() self.once = bank.state end)
            T.setCharge(self, bank, 1)
            T.bankPass(self, bank, 0, { hours = WEAR_HOURS })
            T.step(function() self.twice = bank.state end)
            T.perform(self, "setBankOn", { bank = bank.position, on = false })
            T.bankPass(self, bank, 0, { hours = WEAR_HOURS })
            T.step(function() self.off = bank.state end)
            T.perform(self, "setBankOn", { bank = bank.position, on = true })
            T.setPartCondition(self, bank, INVERTER, 50)
            T.give(self, "scrap", { { type = PowerBank.SCRAP } })
            repair(self, "unskilled", bank)
        end)
        T.step(function() T.setPerk(self, Perks.Electricity, Specs.partRepair.skill) end)
        T.batch(function()
            repair(self, "repaired", bank)
            T.bankState(self, bank)
            T.count(self, "scrap", { PowerBank.SCRAP })
            T.step(function()
                local inverter = stateItem(bank.state, INVERTER)
                self.repairedCondition = inverter and inverter.condition
            end)
            repair(self, "noScrap", bank)
            -- Past ConditionMax, which the setter keeps it to.
            T.setPartCondition(self, bank, INVERTER, 1000)
            T.give(self, "moreScrap", { { type = PowerBank.SCRAP } })
            repair(self, "whole", bank)
            T.setPartCondition(self, bank, INVERTER, 0)
            T.performInto(self, "refreshed", "refresh", { bank = bank.position })
            T.bankState(self, bank)
        end)
    end,
    validate = function(self)
        for _, pass in ipairs({ { self.once, "first" }, { self.twice, "second" } }) do
            local status = pass[1].status
            expect(status.state == "on", string.format("the bank stopped carrying its %.1f W load in its %s pass (%s)",
                status.loadW, pass[2], tostring(status.state)))
        end
        -- What WEAR_HOURS on and twice that take, in whole points of condition (Wear.take keeps
        -- the fractions for later).
        local perHour = Specs.partWear.perHour
        for _, part in ipairs({ { INVERTER, perHour.inverter }, { Specs.controller, perHour.controller } }) do
            local fullType, rate = part[1], part[2]
            expectNear(fullType .. " after " .. WEAR_HOURS .. " hours on", conditionOf(self.once, fullType),
                100 - math.floor(rate * WEAR_HOURS), 0)
            expectNear(fullType .. " after " .. 2 * WEAR_HOURS .. " hours on", conditionOf(self.twice, fullType),
                100 - math.floor(rate * 2 * WEAR_HOURS), 0)
            expectNear(fullType .. " after " .. WEAR_HOURS .. " more hours off", conditionOf(self.off, fullType),
                conditionOf(self.twice, fullType), 0)
        end
        expect(conditionOf(self.twice, INVERTER) < 100, "an inverter on for " .. 2 * WEAR_HOURS .. " hours didn't wear")
        expect(reason(self, "unskilled") == "skill", "a part was repaired below Electricity "
            .. Specs.partRepair.skill .. " (" .. reason(self, "unskilled") .. ")")
        expect(self.repaired.ok, "repairing a worn inverter with scrap failed (" .. reason(self, "repaired") .. ")")
        expectNear("condition after one scrap", self.repairedCondition, 50 + Specs.partRepair.condition, 0)
        expectNear("scrap left", self.counts.scrap[PowerBank.SCRAP], 0, 0)
        expect(reason(self, "noScrap") == "scrap", "a part was repaired without scrap (" .. reason(self, "noScrap") .. ")")
        expect(reason(self, "whole") == "Tooltip_RenewableEnergy_NoRepairNeeded", "a whole part took a repair (" .. reason(self, "whole") .. ")")
        local broken = self.bank.state
        expect(broken.on, "the bank was switched off before its inverter broke")
        expectNear("limit with the only inverter at 0", broken.limitW, 0, 0)
        expect(not broken.activated, "a bank whose only inverter is broken powers its area")
    end,
})

-- Chargers and generator charging --------------------------------------------------------------

-- With the grid off, a rack bank with batteries, car battery chargers and an Inverter/Charger,
-- and a square for a backup generator in reach of it; nil if either can't be had.
local function chargerBank(self, opts)
    T.setGrid(self, false)
    local bank = T.bank(self, "batteryRackWood",
        { CHARGED_BATTERY, CHARGED_BATTERY, Specs.charger, Specs.charger, INVERTER }, opts)
    local backup = bank and backupSquare(self, bank.square, SandboxVars.GeneratorTileRange - 1)
    if backup then return bank, backup end
end

-- The watts chargerBank's chargers make together.
local function chargerBankWatts()
    return 2 * Specs.chargerWatts + Specs.inverters[INVERTER].chargerWatts
end

-- Chargers charge only from the grid or a running generator other than the bank itself, at their
-- full watts while the batteries have room, and burn no generator fuel on the grid.
test("renewable_energy_bank_chargers_charge_only_from_grid_or_generator", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        local charge = 0.2
        local bank, backup = chargerBank(self, { charge = charge })
        if not bank then return end
        -- For half the time the room left in the batteries takes to fill.
        self.chargersW = chargerBankWatts()
        local roomWh = (1 - charge) * 2 * Specs.batteries[CHARGED_BATTERY].wh
        self.hours = roomWh / 2 / self.chargersW
        T.switchOn(self, bank)
        T.batch(function()
            T.bankPass(self, bank, 0)
            T.step(function() self.alone, self.ownPower = bank.state.status.chargerW, bank.state.activated end)
            T.generator(self, { square = backup, running = true })
            T.setCharge(self, bank, charge)
            T.bankPass(self, bank, 0, { hours = self.hours })
            T.step(function()
                local status = bank.state.status
                self.fromGenerator = status.chargerW
                self.generatorSource = status.chargers[1] and status.chargers[1].charging
            end)
            generatorState(self, backup, "fuelAfter")
        end)
        T.step(function() T.setGrid(self, true) end)
        T.batch(function()
            T.bankPass(self, bank, 0)
            T.step(function() self.fromGrid, self.gridPowered = bank.state.status.chargeSource, bank.state.activated end)
            generatorState(self, backup, "fuelOnGrid")
        end)
    end,
    validate = function(self)
        expectNear("charger watts with no grid or generator" .. (self.ownPower and " while the bank powers itself" or ""), self.alone, 0, 0)
        expect(self.chargersW > 0, "the bank's chargers are rated for no watts")
        expectNear("charger watts from a running generator", self.fromGenerator, self.chargersW, 0)
        expect(self.generatorSource == "generator", "a charger says it charges from " .. tostring(self.generatorSource))
        expect(self.fromGrid == "grid", "with the grid on the chargers charge from " .. tostring(self.fromGrid))
        expectNear("fuel the chargers burned on grid power", self.fuelAfter.fuel - self.fuelOnGrid.fuel, 0, 0)
        expect(not self.gridPowered, "the bank ran its own generator while the grid powered its square")
    end,
})

-- A running generator bills the chargers only for what the batteries take: nothing for a full bank
-- or one without batteries, the room's fuel for one with room.
test("renewable_energy_bank_generator_fuel_follows_battery_room", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        local bank, backup = chargerBank(self)
        if not bank then return end
        self.bank = bank
        self.chargersW = chargerBankWatts()
        self.low = 0.2
        local function pass(key)
            generatorState(self, backup, key .. "Before")
            T.bankPass(self, bank, 0)
            T.step(function() self[key] = bank.state end)
            generatorState(self, backup, key .. "After")
        end
        -- The bank stays out: its copy waits for every part, and the batteries leave.
        T.batch(function()
            T.generator(self, { square = backup, running = true })
            pass("full")
            T.setCharge(self, bank, self.low)
            pass("room")
            T.server(self, "removePart", { bank = bank.position, type = CHARGED_BATTERY })
            T.server(self, "removePart", { bank = bank.position, type = CHARGED_BATTERY })
            pass("empty")
        end)
    end,
    validate = function(self)
        local function burned(key)
            return self[key .. "Before"].fuel - self[key .. "After"].fuel
        end
        for _, key in ipairs({ "full", "room", "empty" }) do
            local source = self[key].status.chargeSource
            expect(source == "generator", "the " .. key .. " bank's chargers charge from " .. tostring(source))
        end
        expectNear("fuel the chargers burned on a full bank", burned("full"), 0, 0)
        expectNear("charger watts into a full bank", self.full.status.chargerW, 0, 0)
        -- A bank pass lasts an hour unless told otherwise. Vanilla bills a generator a unit of fuel an
        -- hour for each Specs.wattsPerFuel watts, times the fuel consumption option.
        local roomWh = (1 - self.low) * self.room.nominalWh
        local filledWh = math.min(self.chargersW, roomWh)
        local fuel = filledWh / Specs.wattsPerFuel * SandboxVars.GeneratorFuelConsumption
        expect(self.chargersW > 0 and roomWh > 0 and fuel > 0, "the bank with room in its batteries bills no fuel")
        expectNear("fuel the chargers burned filling the room", burned("room"), fuel, fuel * 0.01)
        expectNear("the bank's charge after the chargers filled it", self.room.charge,
            self.low + filledWh / self.room.nominalWh, 0.0001)
        expect(self.empty.batteries == 0, "the bank still holds " .. self.empty.batteries .. " batteries")
        expectNear("fuel the chargers burned on a bank without batteries", burned("empty"), 0, 0)
        expectNear("charger watts into a bank without batteries", self.empty.status.chargerW, 0, 0)
    end,
})

-- A gas line counts the chargers of a bank charging from its generator into what the generator
-- delivers (GasLines.loadOf), and still does once the world is saved and loaded again, which keeps
-- only a bank's saved fields: otherwise a generator stalled on that load restarts on load, to
-- stall again at the bank's next pass.
test("renewable_energy_bank_charging_generator_kept_through_save", {
    run = function(self)
        local bank, backup = chargerBank(self, { charge = 0.2 })
        if not bank then return end
        self.bank = bank
        T.generator(self, { square = backup, running = true })
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.server(self, "saveAndLoadBank", { bank = bank.position, generator = T.at(backup) })
        end)
    end,
    validate = function(self)
        local reply = self.server.saveAndLoadBank
        expect(self.bank.state.status.chargeSource == "generator",
            "the bank's chargers charge from " .. tostring(self.bank.state.status.chargeSource))
        expect(reply.loadBefore >= reply.chargerW and reply.chargerW > 0, string.format(
            "the generator delivers %.1f W, short of the %.1f W of the bank's chargers", reply.loadBefore, reply.chargerW))
        expectNear("what the generator delivers after a save and load", reply.loadAfter, reply.loadBefore, 0.001)
    end,
})

-- Failsafe -------------------------------------------------------------------------------------

-- The failsafe starts its generator below FailsafeStartCharge and stops it at FailsafeStopCharge,
-- checked a percent either side of each.
test("renewable_energy_bank_failsafe_starts_generator", {
    sandbox = { FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        local backup = bank and backupSquare(self, bank.square, 3)
        if not backup then return end
        local start, stop = SandboxVars.RenewableEnergy.FailsafeStartCharge / 100, SandboxVars.RenewableEnergy.FailsafeStopCharge / 100
        -- The failsafe acts on the charge before the pass's own drain, which the next setCharge undoes.
        local function at(key, charge)
            T.setCharge(self, bank, charge)
            T.bankPass(self, bank, 0, { hours = 0.01 })
            T.step(function()
                local generator = bank.state.status.generator
                self.found = self.found or (generator and generator.failsafe)
            end)
            generatorState(self, backup, key)
        end
        T.batch(function()
            T.generator(self, { square = backup, failsafe = true })
            T.perform(self, "setBankOn", { bank = bank.position, on = true })
            at("atStart", start)
            at("belowStart", start - 0.01)
            at("belowStop", stop - 0.01)
            at("atStop", stop)
        end)
    end,
    validate = function(self)
        if not expect(self.found, "the bank didn't find the failsafe generator") then return end
        expect(not self.atStart.running, "the failsafe started the generator at exactly its start charge")
        expect(self.belowStart.running, "the failsafe didn't start the generator a percent below its start charge")
        expect(self.belowStop.running, "the failsafe stopped the generator a percent below its stop charge")
        expect(not self.atStop.running, "the failsafe didn't stop the generator at exactly its stop charge")
    end,
})

local function distanceSquared(a, b)
    return IsoUtils.DistanceToSquared(a:getX(), a:getY(), b:getX(), b:getY())
end

-- The charge just under the failsafe's start.
local function belowFailsafeStart()
    return SandboxVars.RenewableEnergy.FailsafeStartCharge / 100 - 0.05
end

-- What the status window's Failsafe row reads for the bank status `status`, or nil without one.
local function failsafeRow(status)
    local label = getText("IGUI_RenewableEnergy_Failsafe")
    for _, rows in ipairs({ StatusWindow.rows(status) }) do
        for _, r in ipairs(rows) do
            if r.label == label then return r.value end
        end
    end
end

local function failsafeRange()
    local options = SandboxVars.RenewableEnergy
    return getText("IGUI_RenewableEnergy_FailsafeRange", options.FailsafeStartCharge, options.FailsafeStopCharge)
end

-- A switched-on bank that can't carry its load, its only inverter broken, leaves its failsafe
-- generator stopped however low it runs, and the status says the failsafe is idle; repaired, the
-- bank has it started.
test("renewable_energy_bank_failsafe_waits_for_a_working_bank", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        local backup = bank and backupSquare(self, bank.square, 3)
        if not backup then return end
        local function lowPass(key)
            T.setCharge(self, bank, belowFailsafeStart())
            T.bankPass(self, bank, 0, { hours = 0.01 })
            T.step(function() self[key .. "Status"] = bank.state.status end)
            generatorState(self, backup, key)
        end
        T.batch(function()
            T.generator(self, { square = backup, failsafe = true })
            T.perform(self, "setBankOn", { bank = bank.position, on = true })
            T.setPartCondition(self, bank, PLUG_IN_INVERTER, 0, true)
            lowPass("broken")
            T.setPartCondition(self, bank, PLUG_IN_INVERTER, 100, true)
            lowPass("repaired")
        end)
    end,
    validate = function(self)
        expect(not self.broken.running, "the failsafe started its generator for a bank with a broken inverter")
        local idle = getText("IGUI_RenewableEnergy_FailsafeIdle")
        expect(failsafeRow(self.brokenStatus) == idle, "the status reads " .. tostring(failsafeRow(self.brokenStatus))
            .. " for the failsafe of a bank with a broken inverter, not " .. idle)
        expect(self.repaired.running, "the failsafe didn't start its generator once the inverter was repaired")
        expect(failsafeRow(self.repairedStatus) == failsafeRange(), "the status reads "
            .. tostring(failsafeRow(self.repairedStatus)) .. " for the failsafe of a working bank, not " .. failsafeRange())
    end,
})

-- Two banks have one failsafe generator in backup reach: it answers to the nearer, so the farther,
-- run low, doesn't start it while the nearer is full, and its status says another bank runs it.
test("renewable_energy_bank_failsafe_answers_to_nearest_bank", {
    run = function(self)
        T.setGrid(self, false)
        local parts = { "Base.CarBattery1", PLUG_IN_INVERTER }
        local first = T.bank(self, "batteryBoxWood", parts)
        local backup = first and backupSquare(self, first.square, 3)
        local otherSquare = backup and T.square(self, { indoors = true, near = backup }, "a free indoor square for a second bank")
        if not otherSquare then return end
        local dx, dy = otherSquare:getX() - backup:getX(), otherSquare:getY() - backup:getY()
        local dFirst, dOther = distanceSquared(first.square, backup), distanceSquared(otherSquare, backup)
        if not T.need(self, math.abs(dx) <= 3 and math.abs(dy) <= 3 and dFirst ~= dOther,
            "a second bank square in the generator's backup reach, nearer or farther than the first") then return end
        local second = T.bank(self, "batteryBoxWood", parts, { square = otherSquare })
        if not second then return end
        local near, far = first, second
        if dOther < dFirst then near, far = second, first end
        T.batch(function()
            T.generator(self, { square = backup, failsafe = true })
            T.perform(self, "setBankOn", { bank = near.position, on = true })
            T.perform(self, "setBankOn", { bank = far.position, on = true })
            T.setCharge(self, far, belowFailsafeStart())
            T.bankPass(self, near, 0, { hours = 0.01 })
            T.bankPass(self, far, 0, { hours = 0.01 })
            T.step(function()
                self.nearStatus, self.farStatus = near.state.status, far.state.status
            end)
            generatorState(self, backup, "after")
        end)
    end,
    validate = function(self)
        expect(not self.after.running, "the farther bank started the failsafe generator the nearer bank keeps stopped")
        local other = getText("IGUI_RenewableEnergy_FailsafeOtherBank")
        expect(failsafeRow(self.nearStatus) == failsafeRange(), "the nearer bank's status reads "
            .. tostring(failsafeRow(self.nearStatus)) .. " for the failsafe, not " .. failsafeRange())
        expect(failsafeRow(self.farStatus) == other, "the farther bank's status reads "
            .. tostring(failsafeRow(self.farStatus)) .. " for the failsafe, not " .. other)
    end,
})

-- Squares in a line for the relay test, every one free: a bank B, failsafe generators one and two
-- squares on from it, and a bank A three squares past the farther. B and A stand indoors. Both
-- generators are nearer B than A, the farther one is in A's backup reach and the nearer isn't.
-- Nil, and missing, without such a line near the character.
local function relayLine(self)
    local isFree, origin = RenewableEnergy.Debug.isFreeSquare, player():getSquare()
    local z = origin:getZ()
    for radius = 1, 30 do
        for x, y in PZHarness.Fixtures.ring(origin:getX(), origin:getY(), radius) do
            for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
                local line = {}
                for name, steps in pairs({ b = 0, near = 1, far = 2, a = 5 }) do
                    local square = getSquare(x + d[1] * steps, y + d[2] * steps, z)
                    local indoors = name == "b" or name == "a"
                    if square and not self.used[square] and (isFree(square, indoors) or not indoors and isFree(square, true)) then
                        line[name] = square
                    end
                end
                if line.b and line.near and line.far and line.a then
                    for _, square in pairs(line) do
                        self.used[square] = true
                    end
                    return line
                end
            end
        end
    end
    return T.need(self, nil, "a line of free squares for two banks and two failsafe generators")
end

-- Two failsafe generators both answer to the bank nearer them, B, which runs both once it runs low;
-- a bank A that has only the farther one in reach says another bank runs it.
test("renewable_energy_bank_failsafe_runs_every_relay_answering_to_it", {
    run = function(self)
        T.setGrid(self, false)
        local line = relayLine(self)
        if not line then return end
        local parts = { "Base.CarBattery1", PLUG_IN_INVERTER }
        local b = T.bank(self, "batteryBoxWood", parts, { square = line.b })
        local a = b and T.bank(self, "batteryBoxWood", parts, { square = line.a })
        if not a then return end
        T.batch(function()
            T.generator(self, { square = line.near, failsafe = true })
            T.generator(self, { square = line.far, failsafe = true })
            T.perform(self, "setBankOn", { bank = b.position, on = true })
            T.perform(self, "setBankOn", { bank = a.position, on = true })
            T.setCharge(self, b, belowFailsafeStart())
            T.bankPass(self, b, 0, { hours = 0.01 })
            T.bankPass(self, a, 0, { hours = 0.01 })
            T.step(function() self.bStatus, self.aStatus = b.state.status, a.state.status end)
            generatorState(self, line.near, "near")
            generatorState(self, line.far, "far")
        end)
    end,
    validate = function(self)
        expect(self.near.running, "the low bank didn't start the failsafe generator beside it")
        expect(self.far.running, "the low bank didn't start the farther failsafe generator, which answers to it")
        expect(failsafeRow(self.bStatus) == failsafeRange(), "the low bank's status reads "
            .. tostring(failsafeRow(self.bStatus)) .. " for the failsafe, not " .. failsafeRange())
        local other = getText("IGUI_RenewableEnergy_FailsafeOtherBank")
        expect(failsafeRow(self.aStatus) == other, "the other bank's status reads "
            .. tostring(failsafeRow(self.aStatus)) .. " for the failsafe, not " .. other)
    end,
})

-- While a backup generator carries a switched-on bank's load, the bank's day figure counts none of
-- it, the generator's share is kept apart, and the batteries keep their charge.
test("renewable_energy_bank_backup_load_kept_apart", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        local backup = fridge and backupSquare(self, bank.square, 3)
        if not backup then return end
        T.placeTile(self, fridge, MINI_FRIDGE)
        T.generator(self, { square = backup, running = true })
        T.batch(function()
            T.performInto(self, "switched", "setBankOn", { bank = bank.position, on = true })
            T.bankState(self, bank)
            T.step(function() self.before = bank.state end)
            T.bankPass(self, bank, 0)
            T.step(function() self.after = bank.state end)
        end)
    end,
    validate = function(self)
        if not expect(self.switched.ok, "switching the bank on failed (" .. reason(self, "switched") .. ")") then return end
        local before, after = self.before, self.after
        expectNear("load Wh the bank carried while the generator ran", after.loadWhToday - before.loadWhToday, 0, 0)
        local backupWh = (after.status.backupWhToday or 0) - (before.status.backupWhToday or 0)
        expect(backupWh > 0, "an hour of the generator carrying the load counted " .. backupWh .. " Wh")
        expectNear("Wh in the batteries while the generator carried the load", after.storedWh, before.storedWh, 0.01)
    end,
})

-- Sharing a reach ------------------------------------------------------------------------------

-- A free square for a source that reaches `fridge` and lies farther from it than `nearer`.
local function fartherSquare(self, fridge, nearer, opts)
    local square = T.square(self, { indoors = opts.indoors, near = fridge, minDistance = opts.minDistance },
        "a free square for a second source")
    return T.need(self, square and distanceSquared(square, fridge) > distanceSquared(nearer, fridge)
        and distanceSquared(square, fridge) <= SandboxVars.GeneratorTileRange ^ 2 and square,
        "a square for a second source farther from the fridge than the first, in its reach")
end

-- What a fridge adds: to a bank's load in watts, and to a generator's bill in fuel an hour. The
-- tests' area has appliances of its own, so each test reads what one fridge it places adds.
local function fridgeW()
    return T.applianceWatts({ "fridgeFreezer" })
end

local function fridgeFuel()
    return fridgeW() / Specs.wattsPerFuel * SandboxVars.GeneratorFuelConsumption
end

-- Banks that carry the area's own appliances besides the fridges.
local SHARING_PARTS = { CHARGED_BATTERY, CHARGED_BATTERY, INVERTER }

local function passBoth(self, near, far, key)
    T.batch(function()
        T.bankPass(self, near, 0, { hours = 0.01 })
        T.bankPass(self, far, 0, { hours = 0.01 })
        T.step(function()
            self[key] = { near = near.state.status.loadW, far = far.state.status.loadW,
                ran = near.state.activated and far.state.activated }
        end)
    end)
end

-- Two switched-on banks reach a fridge: the nearer pays for it, and the other once the nearer stops.
test("renewable_energy_bank_nearest_bank_pays_shared_appliance", {
    run = function(self)
        T.setGrid(self, false)
        local near = T.bank(self, "batteryBoxWood", SHARING_PARTS, { charge = 1 })
        local fridges = near and T.need(self, T.squares(self, 2, { indoors = true, near = near.square }), "two free indoor squares for fridges")
        local farSquare = fridges and fartherSquare(self, fridges[1], near.square, { indoors = true, minDistance = 4 })
        if not (farSquare and T.need(self, distanceSquared(farSquare, fridges[2]) > distanceSquared(near.square, fridges[2]),
            "a square for the second bank farther from both fridges")) then return end
        local far = T.bank(self, "batteryBoxWood", SHARING_PARTS, { charge = 1, square = farSquare })
        if not far then return end
        T.switchOn(self, near)
        T.switchOn(self, far)
        passBoth(self, near, far, "before")
        T.step(function() T.placeTile(self, fridges[1], MINI_FRIDGE) end)
        passBoth(self, near, far, "shared")
        T.perform(self, "setBankOn", { bank = near.position, on = false })
        T.bankPass(self, far, 0, { hours = 0.01 })
        T.step(function() self.farAlone = far.state.status.loadW end)
        T.step(function() T.placeTile(self, fridges[2], MINI_FRIDGE) end)
        T.bankPass(self, far, 0, { hours = 0.01 })
        T.step(function() self.farAloneWithFridge = far.state.status.loadW end)
    end,
    validate = function(self)
        if not expect(self.before.ran and self.shared.ran, "a bank wasn't powering its squares while both were on") then return end
        expectNear("watts the fridge added to the nearer bank", self.shared.near - self.before.near, fridgeW(), 0.01)
        expectNear("watts the fridge added to the farther bank", self.shared.far - self.before.far, 0, 0.01)
        expectNear("watts a fridge added to the farther bank once the nearer stopped",
            self.farAloneWithFridge - self.farAlone, fridgeW(), 0.01)
    end,
})

-- Two running generators reach a fridge: the nearer one's bill counts it and the farther one's
-- doesn't, also after vanilla rebuilds both bills.
test("renewable_energy_bank_nearest_generator_pays_shared_appliance", {
    run = function(self)
        T.setGrid(self, false)
        local fridge = T.square(self, { indoors = true }, "a free indoor square for a fridge")
        local nearSquare = fridge and T.square(self, { near = fridge }, "a free outdoor square for a generator")
        local farSquare = nearSquare and fartherSquare(self, fridge, nearSquare, { minDistance = 6 })
        if not farSquare then return end
        local near = T.generator(self, { square = nearSquare, running = true })
        local far = T.generator(self, { square = farSquare, running = true })
        local function read(key)
            T.readGenerator(self, near, "near" .. key)
            T.readGenerator(self, far, "far" .. key)
        end
        T.server(self, "billGenerators", {})
        read("Before")
        T.step(function() T.placeTile(self, fridge, MINI_FRIDGE) end)
        T.server(self, "billGenerators", {})
        read("Shared")
        T.setGenerator(self, near, { rebuild = true })
        T.wait(10)
        read("Rebuilt")
    end,
    validate = function(self)
        local reads = self.reads
        for _, when in ipairs({ "Shared", "Rebuilt" }) do
            local after = when == "Shared" and "" or " after vanilla rebuilt the bills"
            expectNear("fuel the fridge added to the nearer generator's bill" .. after,
                reads["near" .. when].bill - reads.nearBefore.bill, fridgeFuel(), 0.0001)
            expectNear("fuel the fridge added to the farther generator's bill" .. after,
                reads["far" .. when].bill - reads.farBefore.bill, 0, 0.0001)
        end
    end,
})

-- A running generator and a switched-on bank reach a fridge nearer the bank: the bank pays for it,
-- and once the bank is off the generator pays for one.
test("renewable_energy_bank_and_generator_nearest_pays", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", SHARING_PARTS, { charge = 1 })
        local fridges = bank and T.need(self, T.squares(self, 2, { indoors = true, near = bank.square }), "two free indoor squares for fridges")
        local generatorSquare = fridges and fartherSquare(self, fridges[1], bank.square, { minDistance = 6 })
        -- Out of the bank's backup reach, where it would carry the bank's load instead.
        if not (generatorSquare and T.need(self, distanceSquared(generatorSquare, bank.square) > 18,
            "a square for the generator out of the bank's backup reach")) then return end
        T.switchOn(self, bank)
        local generator = T.generator(self, { square = generatorSquare, running = true })
        local function pass(key)
            T.batch(function()
                T.bankPass(self, bank, 0, { hours = 0.01 })
                T.step(function() self[key] = { bankW = bank.state.status.loadW, ran = bank.state.activated } end)
                T.server(self, "billGenerators", {})
                T.readGenerator(self, generator, key)
            end)
        end
        pass("before")
        T.step(function() T.placeTile(self, fridges[1], MINI_FRIDGE) end)
        pass("shared")
        T.perform(self, "setBankOn", { bank = bank.position, on = false })
        T.readGenerator(self, generator, "alone")
        T.step(function() T.placeTile(self, fridges[2], MINI_FRIDGE) end)
        T.setGenerator(self, generator, { rebuild = true })
        T.wait(10)
        T.readGenerator(self, generator, "aloneWithFridge")
    end,
    validate = function(self)
        local reads = self.reads
        if not expect(self.before.ran and self.shared.ran, "the bank wasn't powering its squares while on") then return end
        expectNear("watts the fridge added to the bank", self.shared.bankW - self.before.bankW, fridgeW(), 0.01)
        expectNear("fuel the fridge added to the generator's bill while the bank ran",
            reads.shared.bill - reads.before.bill, 0, 0.0001)
        expectNear("fuel a fridge added to the generator's bill once the bank was off",
            reads.aloneWithFridge.bill - reads.alone.bill, fridgeFuel(), 0.0001)
    end,
})

-- Commands and permissions ---------------------------------------------------------------------

-- A command from a timed action's complete() survives forged arguments and changes nothing for
-- them; real ones change the server's record and reach this client's summary.
test("renewable_energy_bank_commands_refuse_forged_arguments", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        local panel = bank and T.panel(self, Sprites.rack.wood.S, { near = bank, connect = true })
        if not panel then return end
        self.bank, self.panel = bank, panel
        local function sourceSnowy()
            local summary = T.clientSummary(bank)
            return summary and summary.sources[1] and summary.sources[1].snowy == true
        end
        T.snowfall(self, bank)
        T.waitFor(self, sourceSnowy, "this client's summary with the panel snowy")
        local forged = {
            { "noSuchCommand", { bank = bank.position } },
            { "setBankOn", { bank = "nonsense" } },
            { "wireIn", { bank = bank.position, itemId = "nonsense" } },
            { "rename", { bank = bank.position, name = 7 } },
            { "connectSource", { bank = bank.position, source = bank.position } },
            { "connectSource" },
        }
        self.accepted = {}
        -- The forged commands change nothing this client sees, so they and the clear go together.
        T.batch(function()
            for _, call in ipairs(forged) do
                T.perform(self, call[1], call[2])
                T.step(function()
                    if self.server.perform.ok then
                        table.insert(self.accepted, call[1])
                    end
                end)
            end
            T.perform(self, "clearSnow", { source = panel.position })
        end)
        T.waitFor(self, function() return not sourceSnowy() end, "this client's summary with the snow cleared")
        T.bankState(self, bank)
        T.step(function() self.afterForged = bank.state end)
        T.batch(function()
            T.perform(self, "disconnectSource", { source = panel.position })
            T.perform(self, "rename", { bank = bank.position, name = "  Shed bank  " })
            T.perform(self, "setBankOn", { bank = bank.position, on = true })
        end)
        T.waitFor(self, function()
            local summary = T.clientSummary(bank)
            return summary ~= nil and summary.on == true and summary.name == "Shed bank" and #summary.sources == 0
        end, "this client's summary of the renamed bank, switched on with no panel")
        T.bankState(self, bank)
    end,
    validate = function(self)
        local forged, state = self.afterForged, self.bank.state
        expect(#self.accepted == 0, "the bank system accepted forged commands: " .. table.concat(self.accepted, ", "))
        expect(forged.sources == 1 and forged.batteries == 1 and forged.name == "" and not forged.on,
            string.format("forged commands changed the bank: %d panels, %d batteries, name %q, on %s",
                forged.sources, forged.batteries, forged.name, tostring(forged.on)))
        -- The waits already failed the test if this client never saw the snow come and go.
        expect(state.sources == 0, "disconnecting the panel left " .. state.sources .. " panels")
        expect(state.on, "setBankOn didn't switch the server's bank on")
        expect(state.name == "Shed bank", "the server names the bank " .. tostring(state.name))
        -- This client's summary already matched the server's (the last wait).
    end,
})

-- The server takes no bank job as a client command, only the status window's watch, whose
-- refresh still brings the status up to date.
test("renewable_energy_bank_client_commands_ignored", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", "Base.CarBattery1", PLUG_IN_INVERTER })
        if not bank then return end
        self.bank = bank
        T.bankState(self, bank)
        T.step(function() self.before = bank.state end)
        -- A battery taken out past the bank's commands shows in the status only once something makes
        -- the bank look again: here the watch sent after the forged commands, which the server
        -- handles in the order they came.
        T.server(self, "removePart", { bank = bank.position, type = "Base.CarBattery1" })
        T.step(function()
            local p, part = player(), stateItem(self.before, PLUG_IN_INVERTER)
            local system = PowerBank.clientSystem
            system:sendCommand(p, "setBankOn", { bank = bank.position, on = true })
            system:sendCommand(p, "rename", { bank = bank.position, name = "Forged" })
            system:sendCommand(p, "unwire", { bank = bank.position, itemId = part and part.id or -1 })
            PowerBank.watchStatus(p, bank.object)
            T.defer(self, function() PowerBank.unwatchStatus(p, bank.object) end)
        end)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and #status.batteries == 1
        end, "this client's status after the watch, with the battery taken out")
        T.bankState(self, bank)
    end,
    validate = function(self)
        local before, after = self.before, self.bank.state
        expect(not after.on, "a client command switched the bank on")
        expect(after.name == before.name, "a client command renamed the bank " .. tostring(after.name))
        expect(stateItem(after, PLUG_IN_INVERTER) ~= nil, "a client command unwired the inverter")
    end,
})

-- Every client keeps a bank's summary, resent only when it changes; the whole status goes only to
-- the players watching the bank, until they stop.
test("renewable_energy_bank_status_only_to_watchers", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.bank = bank
        T.step(function() self.summary = T.clientSummary(bank) end)
        T.bankPass(self, bank, 1000)
        T.step(function()
            self.unwatched = { status = T.clientStatus(bank), watchers = bank.state.watchers,
                resent = T.clientSummary(bank) ~= self.summary }
        end)
        T.watch(self, bank)
        T.bankPass(self, bank, 0)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and status.solarW == 0
        end, "this client's status of the watched bank's dark pass")
        T.step(function()
            self.watchers = bank.state.watchers
            PowerBank.unwatchStatus(player(), bank.object)
        end)
        T.waitFor(self, function() return T.clientStatus(bank) == nil end, "this client letting go of the status it stopped watching")
        -- The unwatch and the pass's call are separate packets, which a server may take in either order.
        T.serverUntil(self, "bankState", bank.position, function(state) return state.watchers == 0 end)
        T.bankPass(self, bank, 1000)
        T.step(function() self.stopped = { status = T.clientStatus(bank), watchers = bank.state.watchers } end)
    end,
    validate = function(self)
        local unwatched, stopped = self.unwatched, self.stopped
        if not expect(unwatched and stopped, "the queue stopped before the bank was watched and let go") then return end
        expect(unwatched.status == nil, "this client has the status of a bank nobody here watches")
        expect(unwatched.watchers == 0, unwatched.watchers .. " players watch a bank nobody opened")
        expect(not unwatched.resent, "a pass that changed nothing in the summary sent it again")
        expect(self.watchers == 1, tostring(self.watchers) .. " players watch the bank this client watches, expected 1")
        -- The wait after the unwatch already failed the test if this client kept the status.
        expect(stopped.watchers == 0, stopped.watchers .. " players still watch the bank after this client stopped")
        expect(stopped.status == nil, "a pass sent this client the status of a bank it stopped watching")
    end,
})

-- Squares between the character and the far bank, counted ring by ring: well past where the menu's
-- walk leaves a character, and the slack the server allows on top of it.
local FAR_TILES = 8

-- On a multiplayer server a bank job counts only within the character's reach: a rename far away
-- changes nothing, one beside it goes through. The server finishes them, so that no refusal
-- clears the client's queue.
test("renewable_energy_bank_far_action_refused", {
    mpOnly = "only a multiplayer server checks the reach of a client's action; single player trusts its own character",
    instant = true,
    run = function(self)
        local far = T.square(self, { minDistance = FAR_TILES }, "an outdoor square far from the character")
        self.far = far and T.bank(self, "batteryBoxWood", {}, { square = far, outdoors = true })
        self.near = self.far and T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not self.near then return end
        T.batch(function()
            for _, bank in ipairs({ self.far, self.near }) do
                T.server(self, "completeRename", { bank = bank.position, name = bank == self.far and "Far" or "Near" })
                T.step(function() bank.done = self.server.completeRename and self.server.completeRename.done end)
                T.bankState(self, bank)
            end
        end)
    end,
    validate = function(self)
        local far, near = self.far and self.far.state, self.near and self.near.state
        if not expect(far ~= nil and near ~= nil, "the server never reported the banks' states") then
            return
        end
        expect(not self.far.done and far.name == "", "an action from " .. FAR_TILES .. " squares away renamed the bank "
            .. tostring(far.name))
        expect(self.near.done and near.name == "Near", "renaming the bank beside the character left it called "
            .. tostring(near.name))
    end,
})

-- The record and the clock ---------------------------------------------------------------------

-- A bank tile that loads without its container is rebuilt into a working bank that keeps its name
-- and panels, on the server and in this client's summary.
test("renewable_energy_bank_rebuilt_bank_keeps_its_record", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {})
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.bank, self.panel = bank, panel
        T.batch(function()
            T.perform(self, "rename", { bank = bank.position, name = "Cellar" })
            T.server(self, "rebuildBank", { bank = bank.position })
        end)
        T.waitFor(self, function()
            local rebuilt, summary = PowerBank.bankOn(bank.square), PowerBank.summaryOf(bank.square)
            return rebuilt ~= nil and rebuilt ~= bank.object and summary ~= nil and summary.name == "Cellar"
        end, "this client's copy of the rebuilt bank, named")
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        local state, summary = self.server.rebuildBank, PowerBank.summaryOf(self.bank.square)
        expect(state.name == "Cellar", "the rebuilt bank is named " .. string.format("%q", tostring(state.name)))
        expect(state.sources == 1, "the rebuilt bank has " .. tostring(state.sources) .. " panels")
        expect(summary ~= nil and summary.name == "Cellar" and #summary.sources == 1,
            "this client's summary of the rebuilt bank names it " .. tostring(summary and summary.name)
            .. " with " .. tostring(summary and #summary.sources) .. " panels")
    end,
})

-- Connecting a panel brings the bank up to now first: the hour before the connect earns nothing for
-- it, the pass after does.
test("renewable_energy_bank_connect_credits_from_connection", {
    hour = 12,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank })
        if not panel then return end
        T.batch(function()
            T.server(self, "ageBank", { bank = bank.position, hours = 1 })
            T.performInto(self, "connected", "connectSource", { bank = bank.position, source = panel.position })
            T.bankState(self, bank)
            T.step(function() self.afterConnect = bank.state end)
            T.bankPass(self, bank, 1000)
            T.step(function() self.afterPass = bank.state end)
        end)
    end,
    validate = function(self)
        if not expect(self.connected.ok, "connecting the panel failed (" .. reason(self, "connected") .. ")") then return end
        local connected, passed = self.afterConnect, self.afterPass
        expectNear("hours between the connect and the bank's last pass", connected.age - connected.lastHour, 0, 0.01)
        expectNear("solar Wh today credited for the hour before the connect", connected.solarWhToday, 0, 0)
        expect(passed.solarWhToday > 0, "the pass after the connect credited the panel nothing")
    end,
})

-- Switching a bank on brings it up to now first: the hour it stood off bills no load, the pass
-- after does. The Inverter/Charger carries whatever the house around switches on.
test("renewable_energy_bank_switch_on_bills_from_switch", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "Base.CarBattery1", INVERTER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        T.placeTile(self, fridge, MINI_FRIDGE)
        T.batch(function()
            T.server(self, "ageBank", { bank = bank.position, hours = 1 })
            T.performInto(self, "switched", "setBankOn", { bank = bank.position, on = true })
            T.bankState(self, bank)
            T.step(function() self.afterSwitch = bank.state end)
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.step(function() self.afterPass = bank.state end)
        end)
    end,
    validate = function(self)
        if not expect(self.switched.ok, "switching the bank on failed (" .. reason(self, "switched") .. ")") then return end
        local switched, passed = self.afterSwitch, self.afterPass
        expect(switched.on, "setBankOn left the bank off")
        expectNear("hours between the switch and the bank's last pass", switched.age - switched.lastHour, 0, 0.01)
        expectNear("load Wh today billed for the hour the bank was off", switched.loadWhToday, 0, 0)
        expect(passed.loadWhToday > 0, "the pass after the switch billed the mini fridge nothing")
    end,
})

-- A pass the batteries can't last bills the load they carried: more than nothing, no more than
-- the energy they held less the inverter's losses.
test("renewable_energy_bank_empty_pass_bills_what_it_carried", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "Base.CarBattery1", INVERTER }, { charge = 0.02 })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        T.placeTile(self, fridge, MINI_FRIDGE)
        T.batch(function()
            T.performInto(self, "switched", "setBankOn", { bank = bank.position, on = true })
            T.bankState(self, bank)
            T.step(function() self.before = bank.state end)
            T.bankPass(self, bank, 0)
            T.step(function() self.after = bank.state end)
        end)
    end,
    validate = function(self)
        if not expect(self.switched.ok, "switching the bank on failed (" .. reason(self, "switched") .. ")") then return end
        local before, after = self.before, self.after
        expect(after.storedWh == 0 and after.status.state == "empty",
            "an hour of load left the bank at " .. after.storedWh .. " Wh, " .. after.status.state)
        local billed, most = after.loadWhToday - before.loadWhToday, before.storedWh * Specs.inverterEfficiency
        expect(billed > 0 and billed <= most + 1e-6, "the pass that emptied the bank billed " .. billed
            .. " Wh of load, expected more than 0 and at most the " .. most .. " Wh the batteries could give")
    end,
})

-- A sledgehammer brings the bank up to now first: its batteries land with at least the inverter's
-- idle draw since the last pass taken.
test("renewable_energy_bank_sledgehammer_settles_batteries", {
    instant = true,
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "Base.CarBattery1", INVERTER }, { charge = 0.9 })
        if not bank then return end
        T.give(self, "sledgehammer", { { type = "Base.Sledgehammer", equip = "primary" } })
        T.switchOn(self, bank)
        T.batch(function()
            T.server(self, "ageBank", { bank = bank.position, hours = 1 })
            T.bankState(self, bank)
        end)
        T.step(function() self.before = bank.state end)
        T.doJob(self, bank.square, function() return ISDestroyStuffAction:new(T.player(), bank.object) end)
        T.waitFor(self, function() return PowerBank.bankOn(bank.square) == nil end, "the destroyed bank gone from this client")
        T.server(self, "takeFloorItems", { squares = { T.at(bank.square) } })
    end,
    validate = function(self)
        local battery
        for _, item in ipairs(self.server.takeFloorItems.items) do
            if item.type == "Base.CarBattery1" then
                battery = item
            end
        end
        if not expect(battery, "the destroyed bank left no battery on the floor") then return end
        local most = self.before.charge - Specs.inverters[INVERTER].idle / self.before.nominalWh
        expect(battery.uses <= most + 1e-4, "the battery left the destroyed bank at " .. battery.uses
            .. " after an hour on since its last pass at " .. self.before.charge .. ", expected at most " .. most)
    end,
})

-- How far the clock jumps. EveryTenMinutes fires on the next tick when the minute of the hour
-- lands in another ten (GameTime.update), which a jump of more than ten minutes past whole hours
-- always does; the gadget pass makes up for at most an hour.
local CLOCK_JUMP_HOURS = 1.25

-- The game's clock runs banks and gadgets on the authority: each fixture charges by more than
-- nothing and no more than full sun on its rating over the time its passes covered.
test("renewable_energy_bank_clock_drives_banks_and_gadgets", {
    hour = 12,
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        local squares = T.need(self, T.squares(self, 2, { bare = true }), "two bare outdoor squares for the gadgets")
        if not (panel and squares) then return end
        self.bank = bank
        T.watch(self, bank)
        local car = T.placeVehicle(self, "Base.CarNormal", { battery = "Base.CarBattery1", charge = 0.5 })
        local trailer = T.placeVehicle(self, RenewableEnergy.ArrowBoard.SCRIPT)
        local charger = T.placeAsPlayer(self, squares[1], RenewableEnergy.SolarCellCharger.ITEM, Sprites.cellCharger)
        local light = T.placeAsPlayer(self, squares[2], SolarGardenLight.ITEM, Sprites.gardenLight.off)
        local function fixtures()
            return { bank = bank.position, car = T.vehicleArgs(car), trailer = T.vehicleArgs(trailer),
                charger = { x = charger.x, y = charger.y, z = charger.z },
                light = { x = light.x, y = light.y, z = light.z } }
        end
        T.server(self, "stockGadgets", fixtures)
        T.step(function()
            if not T.need(self, panel.connected, "a panel connected to the bank") then return end
            self.before = self.server.stockGadgets
            T.setTime(self, getGameTime():getTimeOfDay() + CLOCK_JUMP_HOURS)
        end)
        -- The bank's pass and the gadgets' run on the same tick; the bank's status coming back an
        -- hour on from its last pass says both have.
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and status.hour >= self.before.bankPassAge + 1
        end, "this client's status of the bank's pass an hour on")
        T.server(self, "gadgetCharges", fixtures)
    end,
    validate = function(self)
        local before, after = self.before, self.server.gadgetCharges
        if not expect(before and after, "the clock test's gadgets were never read before and after") then return end
        local function charged(name, what, ratedW, hours)
            local gain, most = after[name] - before[name], Sun.wattsFrom(ratedW, Sun.FULL_SUN, 0) * hours
            expect(gain > 0 and gain <= most, string.format(
                "%s gained %.4f Wh as the clock moved on %.2f hours, expected more than 0 and at most %.4f", what, gain, hours, most))
        end
        local bankHours, gadgetHours = after.bankPassAge - before.bankPassAge, after.age - before.age
        charged("bank", "the bank with a connected panel", Specs.mounts.flat.modules * Specs.modules[Specs.factoryModule].watts, bankHours)
        charged("car", "the car with a maintainer", Specs.maintainerWatts, gadgetHours)
        charged("charger", "the solar battery charger", Specs.cellChargerWatts, gadgetHours)
        charged("light", "the garden light", Specs.gardenLight.watts, gadgetHours)
        -- A storm during the passes may have cracked a panel since.
        charged("trailer", "the arrow board's battery box", math.max(before.trailerWatts, after.trailerWatts), gadgetHours)
    end,
})

-- Unloaded ---------------------------------------------------------------------------------------

local JAR, L16 = "RenewableEnergy.JarBattery", "RenewableEnergy.L16Battery"
-- Hours of the pass while the bank is away, long enough for its inverter's wear to make a point.
local AWAY_HOURS = 20
-- The condition each part of the away test's bank comes back with. A battery's discharge costs it
-- (depth / 0.5)² over its type's half-depth cycles of its condition (SAND2004-3149): the day's 70%
-- is 1.96 / 150 of a jar battery's 100, 1.3 points, one of them whole, and 1.96 / 2500 of an L16's,
-- less than one. The inverter wears 0.06 an hour on: 1.2 points in the hours away.
local CAME_BACK = { [JAR] = 99, [L16] = 100, [INVERTER] = 99 }

-- This client's copy of the bank at `position`, found afresh: a chunk loaded again brings new
-- objects.
local function bankHere(position)
    return PowerBank.bankOn(getSquare(position.x, position.y, position.z))
end

-- While its chunk is unloaded a switched-on bank carries on from what it last knew: a pass across
-- midnight draws on its charge, turns its day on the depth of yesterday's deepest discharge, and
-- counts the hours its inverter powered. When the chunk loads, the batteries take the charge it
-- reached and that discharge's wear, and the inverter those hours' wear, on the server's items and
-- this client's copies. Single player only, as the digester's. Batteries enough to carry what the
-- houses around draw through the hours away, so the inverter powers them all.
test("renewable_energy_bank_unloaded_bank_writes_back_on_load", {
    spOnly = "the server keeps chunks loaded after the character leaves",
    timeoutSeconds = 120,
    sandbox = { BatteryWear = 100 },
    run = function(self)
        T.setGrid(self, false)
        local parts = { JAR, INVERTER }
        for _ = 2, Specs.banks["RenewableEnergy.BatteryRackMetal"].maxBatteries do
            table.insert(parts, L16)
        end
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local bank = stand and T.bank(self, "batteryRackMetal", parts, { near = stand })
        if not bank then return end
        self.bank, self.parts = bank, parts
        local at = bank.position
        T.step(function() T.setTime(self, 23.5) end)
        T.switchOn(self, bank)
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.setCharge(self, bank, 0.3)
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.setCharge(self, bank, 1)
            T.step(function() self.left = bank.state end)
        end)
        T.awayAndBack(self, T.at(stand), at.x, at.y, at.z, function()
            T.step(function() T.setTime(self, 24.01) end)
            T.serverUntil(self, "bankState", at, function(state)
                return state ~= nil and state.calendarDay ~= self.left.calendarDay
            end)
            T.bankPass(self, bank, 0, { hours = AWAY_HOURS })
            T.step(function() self.away = bank.state end)
        end)
        T.bankState(self, bank)
        T.waitFor(self, function()
            local copy = bankHere(at)
            local inverter = copy and copy:getContainer():getFirstType(INVERTER)
            return inverter ~= nil and inverter:getCondition() == conditionOf(bank.state, INVERTER)
        end, "this client's copy of the bank loaded again")
    end,
    validate = function(self)
        local away, back = self.away, self.bank.state
        expect(#away.items == 0, "the bank's chunk stayed loaded while the character was away")
        expect(away.calendarDay ~= self.left.calendarDay, "the day never turned while the bank was away")
        expect(away.status.state == "on" and away.charge < 1, string.format(
            "the bank away drew it to %.3f in %d hours, %s", away.charge, AWAY_HOURS, tostring(away.status.state)))
        local function check(what, fullType, condition, uses)
            expectNear(what .. "'s condition", condition, CAME_BACK[fullType], 0)
            if fullType ~= INVERTER then
                expectNear(what .. "'s charge", uses, away.charge, 0.001)
            end
        end
        expect(#back.items == #self.parts, "the bank came back holding " .. #back.items .. " of its " .. #self.parts .. " parts")
        for _, item in ipairs(back.items) do
            check("the server's " .. item.type, item.type, item.condition, item.uses)
        end
        local copy = bankHere(self.bank.position)
        if not expect(copy ~= nil, "this client has no copy of the bank loaded again") then return end
        local items = copy:getContainer():getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            check("this client's " .. item:getFullType(), item:getFullType(), item:getCondition(), item:getCurrentUsesFloat())
        end
    end,
})

-- Menus ----------------------------------------------------------------------------------------

-- Right-clicking a bank builds its submenu through vanilla's menu builder, without vanilla's
-- generator submenu that its IsoGenerator would otherwise get.
test("renewable_energy_bank_context_menu_opens_bank_menu", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
    end,
    validate = function(self)
        local bank = self.bank.object
        local context = ISWorldObjectContextMenu.createMenu(0, { bank }, 0, 0)
        if not expect(type(context) == "table", "right-clicking a bank built no menu") then return end
        local option = T.optionNamed(context, Menu.bankLabel(bank))
        expect(option ~= nil and option.subOption ~= nil, "right-clicking a bank shows no bank submenu")
        expect(T.optionNamed(context, getText("ContextMenu_Generator")) == nil, "right-clicking a bank shows vanilla's generator submenu")
        context:hideAndChildren()
    end,
})

-- A bank's submenu lists its window, its switch, renaming and wiring.
test("renewable_energy_bank_menu_lists_bank_options", {
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
    end,
    validate = function(self)
        local context = T.newContext()
        local submenu = Menu.addBankOptions(0, context, self.bank.object)
        expect(T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_Status")) ~= nil, "the bank menu has no status option")
        expect(T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_Rename")) ~= nil, "the bank menu has no Rename")
        local turnOn = T.optionNamed(submenu, getText("ContextMenu_Turn_On"))
        expect(turnOn ~= nil, "a bank that is off offers no Turn On")
        expect(turnOn == nil or turnOn.notAvailable, "a bank without an inverter offers to turn on")
        local wireIn = T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_WireIn"))
        expect(wireIn ~= nil and wireIn.notAvailable and T.tooltipOf(wireIn) == getText("Tooltip_RenewableEnergy_NothingToWire"),
            "with no part carried, Wire In isn't unavailable with the reason")
        expect(T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_Unwire")) == nil, "an empty bank offers to unwire something")
        context:hideAndChildren()
    end,
})

-- Objects that aren't the mod's add nothing to the menu.
test("renewable_energy_bank_menu_ignores_other_objects", {
    validate = function(self)
        local square = player():getSquare()
        local floor = square and square:getFloor()
        if not expect(floor ~= nil, "the character stands on no floor") then return end
        local context = T.newContext()
        local before = context.numOptions
        Menu.onFill(0, context, { floor }, false)
        expect(context.numOptions == before, "a plain floor got " .. (context.numOptions - before) .. " options")
        context:hideAndChildren()
    end,
})

-- Wire In offers each carried part type once, greys out one that can't go in listing everything
-- it lacks, and offers it once it can.
test("renewable_energy_bank_menu_wire_in_options", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {})
        if not self.bank then return end
        T.give(self, "parts", { { type = "Base.CarBattery2", count = 2 }, { type = "RenewableEnergy.PlugInInverter" } })
        T.step(function()
            local context = T.newContext()
            local menu = Menu.addWireInOptions(0, context, self.bank.object)
            self.batteries = 0
            for _, option in ipairs(menu.options or {}) do
                if option.name == getItemNameFromFullType("Base.CarBattery2") then
                    self.batteries = self.batteries + 1
                end
            end
            local plugIn = optionFor(menu, self.items.parts[3])
            self.withoutTools = { unavailable = plugIn ~= nil and plugIn.notAvailable, reason = T.tooltipOf(plugIn),
                screwdriverShort = marksShort(plugIn, "Base.Screwdriver"), wireShort = marksShort(plugIn, PowerBank.WIRE) }
            context:hideAndChildren()
        end)
        local wire = PowerBank.wiringFor("RenewableEnergy.PlugInInverter").wire
        T.give(self, "tools", { { type = "Base.Screwdriver" }, { type = PowerBank.WIRE, count = wire } })
        T.step(function()
            local context = T.newContext()
            local plugIn = optionFor(Menu.addWireInOptions(0, context, self.bank.object), self.items.parts[3])
            self.withTools = { available = plugIn ~= nil and not plugIn.notAvailable, reason = T.tooltipOf(plugIn) }
            context:hideAndChildren()
        end)
    end,
    validate = function(self)
        expectNear("Wire In options for two batteries of one type", self.batteries, 1, 0)
        expect(self.withoutTools.unavailable and self.withoutTools.screwdriverShort and self.withoutTools.wireShort,
            "Wire In doesn't grey out an inverter marking both the screwdriver and the wire short ("
            .. tostring(self.withoutTools.reason) .. ")")
        expect(self.withTools.available, "with a screwdriver and wire, the inverter can't be wired in ("
            .. tostring(self.withTools.reason) .. ")")
    end,
})

-- Repair offers each inverter, greyed out with the scrap marked short while there is none, and
-- once there is, walks over and mends the inverter in place with one scrap, on the server and this
-- client's copy.
local WORN = 50
local REPAIRED = WORN + Specs.partRepair.condition
test("renewable_energy_bank_menu_repair_part", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { POWER_INVERTER }, { outdoors = true })
        if not bank then return end
        self.bank = bank
        T.setPartCondition(self, bank, POWER_INVERTER, WORN)
        T.waitFor(self, function()
            local inverter = copyItem(bank, POWER_INVERTER)
            return inverter ~= nil and inverter:getCondition() == WORN
        end, "this client's copy of the worn inverter")
        T.step(function()
            local context = T.newContext()
            local option = optionFor(Menu.addRepairOptions(0, context, bank.object), copyItem(bank, POWER_INVERTER))
            self.withoutScrap = { unavailable = option ~= nil and option.notAvailable, reason = T.tooltipOf(option),
                scrapShort = marksShort(option, PowerBank.SCRAP) }
            context:hideAndChildren()
        end)
        T.give(self, "scrap", { { type = PowerBank.SCRAP } })
        T.step(function()
            local context = T.newContext()
            local option = optionFor(Menu.addRepairOptions(0, context, bank.object), copyItem(bank, POWER_INVERTER))
            context:hideAndChildren()
            self.offered = option ~= nil and not option.notAvailable
            if not self.offered then return end
            T.standNextTo(bank.square)
            T.choose(option)
            T.waitFor(self, function()
                local inverter = copyItem(bank, POWER_INVERTER)
                return inverter ~= nil and inverter:getCondition() == REPAIRED
            end, "this client's copy of the repaired inverter")
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

local INSTANT_OFF = "the debug option Cheats > Timed Action > Instant off, which makes every action instant"

-- Wire In from the menu walks over and wires the part in, on the server and this client's copy,
-- which then offers to unwire it; Electricity shortens the wiring.
test("renewable_energy_bank_menu_wire_in_and_unwire", {
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
            local context = T.newContext()
            local option = optionFor(Menu.addWireInOptions(0, context, bank.object), battery)
            context:hideAndChildren()
            if not option or option.notAvailable then
                self.refused = tostring(T.tooltipOf(option))
                return
            end
            T.choose(option)
            T.waitFor(self, function()
                local status = T.clientStatus(bank)
                return bank.object:getContainer():getItemWithID(self.batteryId) ~= nil and status ~= nil and #status.batteries == 1
            end, "this client's copy of the bank with the battery wired in")
            T.bankState(self, bank)
        end)
    end,
    validate = function(self)
        expect(self.skilled < self.unskilled, string.format(
            "wiring takes %s at Electricity 10 and %s at 0", tostring(self.skilled), tostring(self.unskilled)))
        if not expect(self.refused == nil, "Wire In was refused: " .. tostring(self.refused)) then return end
        local bank = self.bank.object
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
        local context = T.newContext()
        local unwire = optionFor(Menu.addUnwireOptions(0, context, bank), battery)
        expect(unwire ~= nil and not unwire.notAvailable, "the bank doesn't offer to unwire the battery wired in")
        context:hideAndChildren()
    end,
})

-- Renaming goes through the bank, shows in its menu and window, and an empty name gives the
-- tier's name back.
test("renewable_energy_bank_rename_trims_and_empty_restores_tier_name", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryRackMetal", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        T.step(function()
            if not T.walkTo(self, bank.square, "the bank") then return end
            ISTimedActionQueue.add(Action:new(player(), Action.RENAME, nil, bank.object, nil, nil, "  Cellar  "))
            T.waitFor(self, function() return Menu.bankLabel(bank.object) == "Cellar" end, "this client's label of the renamed bank")
            T.step(function()
                -- The wait for "Cellar" is the menu's check; the window's title is read off the same copy.
                local window = StatusWindow.open(0, bank.object)
                T.defer(self, function() window:close() end)
                T.waitFor(self, function() return window.status ~= nil end, "the window's status of the renamed bank")
                T.step(function()
                    self.title = window.title
                    window:close()
                    local action = Action:new(player(), Action.RENAME, nil, bank.object, nil, nil, "")
                    self.emptyAllowed = action:canPerform()
                    ISTimedActionQueue.add(action)
                    T.waitFor(self, function() return Menu.bankLabel(bank.object) ~= "Cellar" end,
                        "this client's label of the bank renamed to nothing")
                    T.bankState(self, bank)
                end)
            end)
        end)
    end,
    validate = function(self)
        expect(self.title == "Cellar", "the window of the renamed bank is titled " .. tostring(self.title))
        expect(self.emptyAllowed, "renaming to an empty name was refused")
        local tier = getItemNameFromFullType("RenewableEnergy.BatteryRackMetal")
        local label = Menu.bankLabel(self.bank.object)
        expect(label == tier, "an empty name left the bank called " .. tostring(label))
        expect(self.bank.state.name == "", "an empty name left the server's bank called " .. tostring(self.bank.state.name))
    end,
})

-- The rename box stops typing at the longest name a bank takes, and the authority refuses a longer
-- name, or one on more than one line, leaving the name as it was; a name of the full length goes.
test("renewable_energy_bank_rename_refuses_long_or_multiline_names", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        local longest = PowerBank.NAME_LENGTH
        self.full = string.rep("y", longest)
        T.batch(function()
            T.performInto(self, "named", "rename", { bank = bank.position, name = "Shed" })
            T.performInto(self, "long", "rename", { bank = bank.position, name = string.rep("x", longest + 1) })
            T.performInto(self, "twoLines", "rename", { bank = bank.position, name = "Shed\nbank" })
            T.bankState(self, bank)
            T.step(function() self.refusedState = bank.state end)
            T.performInto(self, "fullLength", "rename", { bank = bank.position, name = self.full })
            T.bankState(self, bank)
        end)
        T.step(function()
            local box = Menu.askName(0, bank.object)
            T.defer(self, function() box:destroy() end)
            box.entry:setText(string.rep("z", longest + 5))
            -- The box cuts what was typed past its limit when it next updates.
            T.wait(2)
            T.step(function() self.typed = box.entry:getText() end)
        end)
    end,
    validate = function(self)
        expect(self.named.ok, "renaming the bank Shed failed (" .. reason(self, "named") .. ")")
        expect(not self.long.ok, "the authority took a name longer than " .. PowerBank.NAME_LENGTH .. " characters")
        expect(not self.twoLines.ok, "the authority took a name on two lines")
        expect(self.refusedState.name == "Shed", "the refused names left the bank called " .. tostring(self.refusedState.name))
        expect(self.fullLength.ok and self.bank.state.name == self.full, "a name of " .. PowerBank.NAME_LENGTH
            .. " characters left the bank called " .. tostring(self.bank.state.name))
        expect(#self.typed == PowerBank.NAME_LENGTH, "the rename box holds " .. #self.typed .. " characters, expected "
            .. PowerBank.NAME_LENGTH)
    end,
})

-- Status window --------------------------------------------------------------------------------

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

-- A bank with nothing in it says it has no batteries, no inverter and no parts, and that it must
-- go inside.
test("renewable_energy_bank_window_empty_bank_lists_whats_missing", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if self.bank then T.step(function() T.openWindow(self) end) end
    end,
    validate = function(self)
        local window = self.window
        expect(hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_NoBatteries")), "an empty bank does not say it has no batteries")
        expect(hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_NoWorkingInverter")), "an empty bank does not say it has no inverter")
        expect(hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_StateOutdoors")), "a bank outdoors doesn't say it must go inside")
        expect(rowLabelled(window.left, getText("IGUI_RenewableEnergy_NoParts")) ~= nil, "an empty bank doesn't say nothing is wired in")
    end,
})

-- Queues a wait until this client's status of `bank` has the load the server's last answer gave.
local function waitForLoad(self, bank)
    T.waitFor(self, function()
        local status = T.clientStatus(bank)
        return status ~= nil and status.loadW == bank.state.status.loadW and status.solarW == bank.state.status.solarW
    end, "this client's status with the load the server measured")
end

-- The window's lines follow the bank: the overload with its load and limit, the panel slots with
-- the controller count, what draws by kind, a broken part, each battery's repair (a rebuild once
-- its repairs have brought its limit down to its condition), and a panel left without a slot when
-- its controller goes.
test("renewable_energy_bank_window_reflects_status", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood",
            { "Base.CarBattery1", "Base.CarBattery1", "RenewableEnergy.JarBattery", PLUG_IN_INVERTER,
                Specs.controller, Specs.charger },
            { charge = 0.5 })
        if not bank then return end
        self.bank = bank
        -- Further below its repair limit than a Service reaches.
        self.reconditionAt = Recipes.repairLimit(0) - Recipes.SERVICE_REPAIR - 1
        self.rebuildAt = Recipes.repairLimit(2)
        self.panelCount = Specs.freeSlots + 1
        self.load = loadUpTo({ "light", "light" }, "television", Specs.inverters[PLUG_IN_INVERTER].watts, true)
        T.watch(self, bank)
        T.batch(function()
            T.setPartCondition(self, bank, Specs.charger, 0)
            T.setPartCondition(self, bank, "Base.CarBattery1", self.reconditionAt)
            T.setPartCondition(self, bank, "RenewableEnergy.JarBattery", self.rebuildAt, false, 2)
            for _ = 1, self.panelCount do
                if not T.panel(self, Sprites.rack.metal.S, { near = bank, connect = true }) then return end
            end
        end)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and #status.sources == self.panelCount
        end, "this client's status listing the panels")
        T.step(function() self.withControllerSummary = StatusWindow.summary(T.clientStatus(bank)) end)
        T.batch(function()
            T.server(self, "removePart", { bank = bank.position, type = Specs.controller })
            T.perform(self, "setBankOn", { bank = bank.position, on = true })
            T.bankPass(self, bank, 1000)
            T.applyLoad(self, bank, self.load)
        end)
        waitForLoad(self, bank)
    end,
    validate = function(self)
        local inputs = self.panelCount * Specs.mounts.rack.slots
        expect(self.withControllerSummary ~= nil and hasLine(self.withControllerSummary,
            getText("IGUI_RenewableEnergy_InputSlotsOneController", inputs, Specs.freeSlots + Specs.slotsPerController)),
            "the slots line doesn't read " .. inputs .. " inputs of " .. (Specs.freeSlots + Specs.slotsPerController) .. " with 1 controller")
        local status = T.clientStatus(self.bank)
        if not expect(status ~= nil, "the bank sent no status") then return end
        local summary = StatusWindow.summary(status)
        local load, limit = T.applianceWatts(self.load), Specs.inverters[PLUG_IN_INVERTER].watts
        expect(hasLine(summary, getText("IGUI_RenewableEnergy_Overloaded", Format.watts(load), Format.watts(limit))),
            "the window doesn't say the bank is overloaded with " .. load .. " W on " .. limit .. " W")
        expect(hasLine(summary, getText("IGUI_RenewableEnergy_InputSlots", inputs, Specs.freeSlots)),
            "without its controller the slots line doesn't read " .. inputs .. " inputs of " .. Specs.freeSlots)
        local left, right = StatusWindow.rows(status, self.bank.position)
        local lights = rowLabelled(left, getText("IGUI_RenewableEnergy_LoadCount", getText("IGUI_RenewableEnergy_LoadLight"), 2))
        expect(lights ~= nil and lights.value == Format.watts(T.applianceWatts({ "light", "light" })), "the window doesn't list 2 lights and their watts")
        local charger = rowLabelled(left, getItemNameFromFullType(Specs.charger))
        expect(charger ~= nil and charger.color == "bad" and charger.value == getText("IGUI_RenewableEnergy_PartBroken", "0%"),
            "a broken charger doesn't read broken (" .. tostring(charger and charger.value) .. ")")
        local function repairValue(fullType, condition, repair)
            return getText("IGUI_RenewableEnergy_BatteryValueRepair", Format.percent(status.charge),
                Format.condition(fullType, condition), getText(repair))
        end
        local batteryName = getItemNameFromFullType("Base.CarBattery1")
        local recondition = repairValue("Base.CarBattery1", self.reconditionAt, "IGUI_RenewableEnergy_RepairRecondition")
        local repairs, found, panels = {}, false, {}
        for _, r in ipairs(right) do
            if r.label == batteryName then
                table.insert(repairs, r.value)
                found = found or r.value == recondition
            elseif r.source then
                table.insert(panels, r)
            end
        end
        expect(found, "a battery further below its repair limit than a Service reaches doesn't suggest Recondition ("
            .. table.concat(repairs, "; ") .. ")")
        local jar = rowLabelled(right, getItemNameFromFullType("RenewableEnergy.JarBattery"))
        local rebuild = repairValue("RenewableEnergy.JarBattery", self.rebuildAt, "IGUI_RenewableEnergy_RepairRebuild")
        expect(jar ~= nil and jar.value == rebuild,
            "a battery at its twice-repaired limit reads " .. tostring(jar and jar.value) .. ", expected " .. rebuild)
        if not expect(#panels == self.panelCount, #panels .. " panel rows, expected " .. self.panelCount) then return end
        local noSlot = getText("IGUI_RenewableEnergy_ReasonNoController")
        local last = panels[#panels]
        expect(last.value:find(noSlot, 1, true) ~= nil and last.color == "bad", "the panel past the slots reads " .. last.value)
        expect(panels[1].value:find(noSlot, 1, true) == nil and status.sources[1].watts > 0,
            "a panel within the slots reads " .. panels[1].value)
        expect(panels[1].label:find(getText("IGUI_RenewableEnergy_MountRackMetal"), 1, true) ~= nil,
            "a metal rack's row reads " .. panels[1].label)
    end,
})

local function headers(rows)
    local found = {}
    for _, r in ipairs(rows or {}) do
        if r.header then
            found[r.header] = true
        end
    end
    return found
end

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
test("renewable_energy_bank_window_lists_every_part", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBankMetal", FULL_BANK, { charge = 0.7 })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.batch(function()
            T.setPartCondition(self, bank, "RenewableEnergy.L16Battery", 45)
            for _, source in ipairs(FULL_BANK_SOURCES) do
                if not T.panel(self, source.sprite, { near = bank, modules = source.modules, connect = true }) then return end
            end
            T.perform(self, "setBankOn", { bank = bank.position, on = true })
            T.bankPass(self, bank, 650)
            T.applyLoad(self, bank, { "fridge", "television", "light", "light", "light", "radio" })
        end)
        waitForLoad(self, bank)
        T.step(function() T.openWindow(self) end)
    end,
    validate = function(self)
        local window = self.window
        local status = window.status
        local found = headers(window.right)
        local batteries = 0
        for _, fullType in ipairs(FULL_BANK) do
            if Specs.batteries[fullType] then batteries = batteries + 1 end
        end
        expect(found[getText("IGUI_RenewableEnergy_Batteries", batteries)],
            "the window does not list " .. batteries .. " batteries; the status holds " .. #status.batteries)
        expect(found[getText("IGUI_RenewableEnergy_Sources", #FULL_BANK_SOURCES)],
            "the window does not list " .. #FULL_BANK_SOURCES .. " sources; the status holds " .. #status.sources)
        for _, fullType in ipairs({ INVERTER, POWER_INVERTER, Specs.controller, Specs.charger }) do
            expect(rowLabelled(window.left, getItemNameFromFullType(fullType)) ~= nil, "the window does not list the " .. fullType)
        end
        expect(window.switchButton.enable, "the switch is disabled on a bank with an inverter")
    end,
})

-- Connecting -----------------------------------------------------------------------------------

-- A bank starts unconnected, like a generator: switched on it powers nothing, nor a square near it,
-- and its status says so, until it is connected; then both have power, here too.
test("renewable_energy_bank_needs_connecting", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "RenewableEnergy.L16Battery", INVERTER }, { connected = false })
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
        T.perform(self, "setBankConnected", { bank = bank.position, connected = true })
        T.step(function() self.connected = self.server.perform end)
        T.waitFor(self, function() return bank.square:haveElectricity() and self.near:haveElectricity() end,
            "power on the connected bank's square and the square near it here")
        T.bankState(self, bank)
    end,
    validate = function(self)
        local before, after = self.before, self.bank.state
        expect(before.on and not before.activated and not before.powered, "an unconnected bank that is on powered its square")
        expect(not self.nearBefore, "an unconnected bank that is on powered a square near it")
        expect(before.status.state == "disconnected", "the unconnected bank's status says " .. tostring(before.status.state))
        expect(self.connected.ok, "the authority refused to connect the bank (" .. tostring(self.connected.reason) .. ")")
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
        T.placeAsPlayer(self, square, "RenewableEnergy.BatteryBoxWood", Sprites.batteryBoxWood)
        T.waitFor(self, function()
            local bank = PowerBank.bankOn(square)
            return bank ~= nil and PowerBank.summaryOf(bank) ~= nil
        end, "this client's copy of the placed bank, working")
    end,
    validate = function(self)
        local bank = PowerBank.bankOn(self.square)
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

-- The bank's Connect Bank option on this client, read from a fresh menu.
local function connectBankOption(bank)
    local context = T.newContext()
    local option = T.optionNamed(Menu.addBankOptions(0, context, bank.object), getText("ContextMenu_RenewableEnergy_ConnectBank"))
    context:hideAndChildren()
    return option
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
            local option = connectBankOption(self.unskilled)
            self.greyed = option ~= nil and option.notAvailable == true
            self.why = T.tooltipOf(option)
            self.canStart = Action:new(player(), Action.CONNECT_BANK, nil, self.unskilled.object):canPerform()
        end)
        T.perform(self, "setBankConnected", { bank = self.unskilled.position, connected = true })
        T.step(function() self.refused = self.server.perform end)
        -- T.setPerk sets the level when called, so the later levels wait for their turn.
        T.step(function() T.setPerk(self, Perks.Electricity, 3) end)
        T.perform(self, "setBankConnected", { bank = self.unskilled.position, connected = true })
        T.step(function() self.skilled = self.server.perform end)
        T.step(function()
            T.setPerk(self, Perks.Electricity, 2)
            knowGenerator(self, true)
        end)
        T.perform(self, "setBankConnected", { bank = self.magazine.position, connected = true })
        T.step(function() self.withRecipe = self.server.perform end)
        T.step(function() knowGenerator(self, self.knewGenerator) end)
    end,
    validate = function(self)
        expect(self.greyed and self.why == getText("ContextMenu_GeneratorPlugTT"),
            "at Electricity 2 Connect Bank isn't greyed out with vanilla's reason (" .. tostring(self.why) .. ")")
        expect(not self.canStart, "Connect Bank can start at Electricity 2 without the Generator recipe")
        expect(not self.refused.ok and self.refused.reason == "ContextMenu_GeneratorPlugTT",
            "the authority connected a bank at Electricity 2 without the Generator recipe (" .. tostring(self.refused.reason) .. ")")
        expect(self.skilled.ok, "the authority refused to connect a bank at Electricity 3 (" .. tostring(self.skilled.reason) .. ")")
        expect(self.withRecipe.ok,
            "the authority refused to connect a bank with the Generator recipe (" .. tostring(self.withRecipe.reason) .. ")")
    end,
})

-- Connect Bank from the menu connects the bank, Disconnect Bank undoes it, and only a
-- disconnected bank can be picked up, as with a generator.
test("renewable_energy_bank_connect_and_disconnect", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { connected = false })
        if not self.bank then return end
        -- Picking up a bank tile needs the Electrician tool.
        T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
        local bank = self.bank
        local function canPickUp()
            local object = bank.object
            return ISMoveableSpriteProps.new(object:getSprite():getName()):canPickUpMoveable(player(), bank.square, object)
        end
        T.step(function()
            local option = connectBankOption(bank)
            self.offered = option ~= nil and not option.notAvailable
            if not self.offered then return end
            T.standNextTo(bank.square)
            T.choose(option)
            T.waitFor(self, function() return bank.object:isConnected() end, "this client's copy of the connected bank")
            T.step(function()
                self.connectedPickUp = canPickUp()
                local context = T.newContext()
                local option = T.optionNamed(Menu.addBankOptions(0, context, bank.object), getText("ContextMenu_RenewableEnergy_DisconnectBank"))
                context:hideAndChildren()
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

-- Crafting tiers and parts ---------------------------------------------------------------------

-- Each recipe makes one item and uses up what its script takes, but the tools it keeps. A craft
-- starts from the material a player right-clicks.
local MAKES = {
    { "RenewableEnergy_MakeBatteryBoxWood", "RenewableEnergy.BatteryBoxWood", "Base.Plank" },
    { "RenewableEnergy_MakeBatteryBoxMetal", "RenewableEnergy.BatteryBoxMetal", "Base.SmallSheetMetal" },
    { "RenewableEnergy_BuildBatteryRackWood", "RenewableEnergy.BatteryRackWood", "Base.Plank" },
    { "RenewableEnergy_BuildBatteryRackMetal", "RenewableEnergy.BatteryRackMetal", "Base.SmallSheetMetal" },
    { "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy.BatteryBankWood", "Base.Plank" },
    { "RenewableEnergy_BuildBatteryBankMetal", "RenewableEnergy.BatteryBankMetal", "Base.SheetMetal" },
    { "RenewableEnergy_MakeChargeController", "RenewableEnergy.ChargeController", "Base.ElectronicsScrap" },
    { "RenewableEnergy_MakeSolarFailsafe", "RenewableEnergy.SolarFailsafe", "Base.RemoteCraftedV3" },
    { "RenewableEnergy_WeldMetalDrum", "Base.MetalDrum", "Base.SheetMetal" },
}

-- The items one craft of `recipe` uses up: those T.recipeInputs gives for the inputs it neither
-- keeps nor takes only some uses of, as a blowtorch's.
local function usedUp(recipe)
    local types = {}
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        local item = not input:isKeep() and T.inputItem(input)
        if item and (input:isItemCount() or not item:isItemType(ItemType.DRAINABLE)) then
            table.insert(types, item:getFullName())
        end
    end
    return types
end

for _, entry in ipairs(MAKES) do
    local recipe, result, from = entry[1], entry[2], entry[3]
    craftTest(craftName(recipe), {
        recipe = recipe,
        from = from,
        counts = { [result] = 1 },
        after = function(self) T.count(self, "usedUp", usedUp(getScriptManager():getCraftRecipe(recipe))) end,
        validate = function(self)
            local checked = 0
            for fullType, count in pairs(self.counts.usedUp or {}) do
                checked = checked + 1
                expect(count == 0, count .. " " .. fullType .. " left after the craft, which uses it up")
            end
            expect(checked > 0, "the craft uses up nothing")
        end,
    })
end
