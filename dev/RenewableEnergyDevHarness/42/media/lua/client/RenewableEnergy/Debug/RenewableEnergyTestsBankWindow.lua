require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Specs = require "RenewableEnergy/Specs"
local Sun = require "RenewableEnergy/Sun"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local Format = require "RenewableEnergy/UI/Format"
local StatusRows = require "RenewableEnergy/UI/StatusRows"
local Items = require "cf_commonlib/Items"
local Sprites = require "RenewableEnergy/Sprites"
local Yardsticks = require "RenewableEnergy/Debug/RenewableEnergyYardsticks"
local GeneratorReach = require "cf_commonlib/GeneratorReach"

-- Power bank tests: the status window (UI/StatusWindow.lua, UI/StatusRows.lua).
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectEqual, expectNear, player = T.test, T.expect, T.expectEqual, T.expectNear, T.player

-- The watts appliances of the kinds `names` draw together, at vanilla's figures.
local function loadW(names)
    local watts = 0
    for _, name in ipairs(names) do
        watts = watts + Yardsticks.applianceWatts(name)
    end
    return watts
end

-- `base` and then as many `kind` appliances as a bank limited to `limitW` carries, with `over` one
-- more. Sums as the load does, so "carries" holds at the boundary.
local function loadUpTo(base, kind, limitW, over)
    local names = { unpack(base) }
    while loadW(names) + Yardsticks.applianceWatts(kind) <= limitW do
        table.insert(names, kind)
    end
    if over then table.insert(names, kind) end
    return names
end

-- Status window --------------------------------------------------------------------------------

-- A bank's status window stays open while the character stands at the bank and closes once they
-- walk away, as vanilla's animal windows do: one left open would watch the bank's status forever.
test("renewable_energy_bank_window_closes_once_walked_away", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY })
        if not self.bank then return end
        T.openWindow(self, self.bank)
        local function isOpen() return UIManager.getUI():contains(self.window.javaObject) end
        T.step(function()
            self.openAtBank = isOpen()
            local square = self.bank.square
            PZHarness.Fixtures.teleportToMiddle(player(), square:getX() + 8, square:getY(), square:getZ())
        end)
        T.waitFor(self, function() return not isOpen() end, "the status window closing once the character walked away")
    end,
    validate = function(self)
        expect(self.openAtBank, "the status window closed with the character beside the bank")
    end,
})

-- A bank with nothing in it says it has no batteries, no inverter and no parts, and that it must
-- go inside.
test("renewable_energy_bank_window_empty_bank_lists_whats_missing", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if self.bank then T.openWindow(self, self.bank) end
    end,
    validate = function(self)
        local window = self.window
        expect(T.hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_NoBatteries")), "an empty bank does not say it has no batteries")
        expect(T.hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_NoWorkingInverter")), "an empty bank does not say it has no inverter")
        expect(T.hasLine(window.summaryLines, getText("IGUI_RenewableEnergy_StateOutdoors")), "a bank outdoors doesn't say it must go inside")
        expect(T.rowLabelled(window.left, getText("IGUI_RenewableEnergy_NoParts")) ~= nil, "an empty bank doesn't say nothing is wired in")
    end,
})

-- Grid power reaching a bank shows whatever the bank's state, with whether its chargers fill the
-- batteries from it, and goes once the grid is off.
test("renewable_energy_bank_window_shows_grid_power", {
    run = function(self)
        T.setGrid(self, true)
        local bare = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY })
        local charging = bare and T.bank(self, "batteryRackWood", { T.CAR_BATTERY, Specs.charger }, { charge = 0.5 })
        if not charging then return end
        self.at = T.at(bare)
        T.batch(function()
            T.bankPass(self, bare, 0, { label = "bare" })
            T.bankPass(self, charging, 0, { hours = 1, label = "charging" })
        end)
        T.step(function() T.setGrid(self, false) end)
        T.bankPass(self, charging, 0, { label = "off" })
    end,
    validate = function(self)
        local label = getText("IGUI_RenewableEnergy_Grid")
        local function gridRow(key)
            return T.rowLabelled((StatusRows.rows(self.reads[key].status, self.at)), label)
        end
        local bare, charging = gridRow("bare"), gridRow("charging")
        expectEqual("the grid row of a bank without an inverter or a charger", bare and bare.value,
            getText("IGUI_RenewableEnergy_GridNoCharger"))
        -- Room for more than an hour of it: the charger fills at its rating.
        expectEqual("the grid row of a bank charging from the grid", charging and charging.value,
            getText("IGUI_RenewableEnergy_GridCharging", Format.watts(Specs.chargerWatts)))
        expect(gridRow("off") == nil, "the grid row stays once the grid is off")
    end,
})

-- Waits until this client's status of each bank in `banks` has what the server's last answer gave.
local function waitForCharge(self, banks)
    for _, bank in ipairs(banks) do
        T.waitForStatus(self, bank, function(status)
            return status.storedWh == bank.state.status.storedWh and status.solarW == bank.state.status.solarW
        end, "this client's status with the charge the server's pass left")
    end
end

-- The charge a car battery starts at below, and the hour of full sun it then takes in.
local START_CHARGE, SUN_HOURS = 0.25, 1

-- The summary says how long the batteries take to fill at what comes in, and once they are full
-- how much of it goes spare. Catches a time to full counted from the wrong end or at the wrong
-- watts, or a full bank shown as charging.
test("renewable_energy_bank_window_says_time_to_full", {
    run = function(self)
        T.setGrid(self, false)
        local charging = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { charge = START_CHARGE })
        local full = charging and T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { charge = 1 })
        self.chargingPanel = full and T.panel(self, Sprites.flat, { near = charging, connect = true })
        self.fullPanel = self.chargingPanel and T.panel(self, Sprites.flat, { near = full, connect = true })
        if not self.fullPanel then return end
        self.charging, self.full = charging, full
        T.watch(self, charging)
        T.watch(self, full)
        T.batch(function()
            T.bankPass(self, charging, Sun.FULL_SUN, { hours = SUN_HOURS })
            T.bankPass(self, full, Sun.FULL_SUN, { hours = SUN_HOURS })
        end)
        waitForCharge(self, { charging, full })
    end,
    validate = function(self)
        if not (T.expectConnected(self.chargingPanel) and T.expectConnected(self.fullPanel)) then return end
        local panelW = T.flatPanelW()
        -- (600 Wh - 0.25 × 600 Wh - 320 W × 1 h) / 320 W = 0.40625 h at the default Sunlight
        -- Multiplier: clear of a whole minute, so the line's rounding down can't tip.
        local capacityWh = Specs.batteries[T.CAR_BATTERY].wh
        local hours = (capacityWh * (1 - START_CHARGE) - panelW * SUN_HOURS) / panelW
        local charging = T.clientStatus(self.charging)
        expectNear("the hours the charging bank says it takes to fill", charging.charging.hours, hours, 0.001)
        local line = StatusRows.summary(charging)[1]
        expectEqual("the charging bank's first line", line.text,
            getText("IGUI_RenewableEnergy_ChargingFullIn", Format.signedWatts(panelW), Format.duration(hours)))
        expectEqual("the colour of the charging bank's first line", line.color, "good")
        local full = T.clientStatus(self.full)
        expect(full.charging.hours == nil, "the full bank says it fills in " .. tostring(full.charging.hours) .. " hours")
        expectEqual("the full bank's first line", StatusRows.summary(full)[1].text,
            getText("IGUI_RenewableEnergy_FullSpare", Format.watts(panelW)))
    end,
})

-- Queues a wait until this client's status of `bank` has the load the server's last answer gave.
local function waitForLoad(self, bank)
    T.waitForStatus(self, bank, function(status)
        return status.loadW == bank.state.status.loadW and status.solarW == bank.state.status.solarW
    end, "this client's status with the load the server measured")
end

-- The window's lines follow the bank: the overload with its load and limit, the panel slots with
-- the controller count, what draws by kind, a broken part, batteries of a type on one row with
-- their charge together and the most worn one's condition, and same-kind panels on one row with
-- their watts together, followed by a red row of its own for the panel left without a slot when
-- its controller goes.
test("renewable_energy_bank_window_reflects_status", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood",
            { T.CAR_BATTERY, T.CAR_BATTERY, T.JAR_BATTERY, T.PLUG_IN_INVERTER,
                Specs.controller, Specs.charger },
            { charge = 0.5 })
        if not bank then return end
        self.bank = bank
        self.wornAt = math.floor(Items.conditionMaxOf(T.CAR_BATTERY) / 2)
        self.jarAt = math.floor(Items.conditionMaxOf(T.JAR_BATTERY) / 3)
        self.panelCount = Specs.freeSlots + 1
        self.load = loadUpTo({ "light", "light" }, "television", Specs.inverters[T.PLUG_IN_INVERTER].watts, true)
        T.watch(self, bank)
        T.batch(function()
            T.bankPart(self, bank, Specs.charger, { condition = 0 })
            T.bankPart(self, bank, T.CAR_BATTERY, { condition = self.wornAt })
            T.bankPart(self, bank, T.JAR_BATTERY, { condition = self.jarAt })
            for _ = 1, self.panelCount do
                if not T.panel(self, Sprites.rack.metal.S, { near = bank, connect = true }) then return end
            end
        end)
        T.waitForStatus(self, bank, function(status) return #status.sources == self.panelCount end,
            "this client's status listing the panels")
        T.step(function() self.withControllerSummary = StatusRows.summary(T.clientStatus(bank)) end)
        T.batch(function()
            T.server(self, "bankPart", T.at(bank, { type = Specs.controller, remove = true }))
            T.job(self, "bank", BankJobs.TURN_ON, bank)
            T.bankPass(self, bank, 1000)
            T.applyLoad(self, bank, self.load)
        end)
        waitForLoad(self, bank)
    end,
    validate = function(self)
        local inputs = self.panelCount * Specs.mounts.rack.slots
        expect(self.withControllerSummary ~= nil and T.hasLine(self.withControllerSummary,
            getText("IGUI_RenewableEnergy_InputSlotsOneController", inputs, Specs.freeSlots + Specs.slotsPerController)),
            "the slots line doesn't read " .. inputs .. " inputs of " .. (Specs.freeSlots + Specs.slotsPerController) .. " with 1 controller")
        local status = T.clientStatus(self.bank)
        if not expect(status ~= nil, "the bank sent no status") then return end
        local summary = StatusRows.summary(status)
        local load, limit = loadW(self.load), Specs.inverters[T.PLUG_IN_INVERTER].watts
        expect(T.hasLine(summary, getText("IGUI_RenewableEnergy_Overloaded", Format.watts(load), Format.watts(limit))),
            "the window doesn't say the bank is overloaded with " .. load .. " W on " .. limit .. " W")
        expect(T.hasLine(summary, getText("IGUI_RenewableEnergy_InputSlots", inputs, Specs.freeSlots)),
            "without its controller the slots line doesn't read " .. inputs .. " inputs of " .. Specs.freeSlots)
        local left, right = StatusRows.rows(status, self.bank)
        local lights = T.rowLabelled(left, getText("IGUI_RenewableEnergy_Count", getText("IGUI_RenewableEnergy_LoadLight"), 2))
        expectEqual("the row of 2 lights", lights and lights.value, Format.watts(2 * Yardsticks.applianceWatts("light")))
        local charger = T.rowLabelled(left, getItemNameFromFullType(Specs.charger))
        expectEqual("the colour of a broken charger's row", charger and charger.color, "bad")
        expectEqual("a broken charger's row", charger and charger.value, getText("IGUI_RenewableEnergy_PartBroken", "0%"))
        local function batteryValue(fullType, condition)
            return getText("IGUI_RenewableEnergy_BatteryValue", Format.percent(status.charge),
                Format.condition(fullType, condition))
        end
        local cars = T.rowLabelled(right, getText("IGUI_RenewableEnergy_Count", getItemNameFromFullType(T.CAR_BATTERY), 2))
        expectEqual("the row of 2 car batteries, one worn", cars and cars.value, batteryValue(T.CAR_BATTERY, self.wornAt))
        local jar = T.rowLabelled(right, getItemNameFromFullType(T.JAR_BATTERY))
        expectEqual("the row of one jar battery", jar and jar.value, batteryValue(T.JAR_BATTERY, self.jarAt))
        local rackName = getText("IGUI_RenewableEnergy_MountRackMetal")
        local group = T.rowLabelled(right, getText("IGUI_RenewableEnergy_Count", rackName, self.panelCount))
        if not expect(group ~= nil, "no row of " .. self.panelCount .. " metal racks") then return end
        -- The racks within the slots make their modules' rating at the system efficiency in full sun.
        local inSlots = math.floor(Specs.freeSlots / Specs.mounts.rack.slots)
        local watts = T.fullSunW(inSlots * Specs.mounts.rack.modules * Specs.modules[T.FACTORY_MODULE].watts)
        expectEqual("the metal racks' watts", group.value, Format.watts(watts))
        expectEqual("the sources the metal racks' row highlights", #group.sources, self.panelCount)
        local sourceRows = {}
        for _, r in ipairs(right) do
            if r.sources then
                table.insert(sourceRows, r)
            end
        end
        if not expectEqual("source rows", #sourceRows, 2) then return end
        local noSlot, own = getText("IGUI_RenewableEnergy_ReasonNoController"), sourceRows[2]
        expect(sourceRows[1] == group, "the metal racks' row isn't first")
        expect(own.label:find(rackName, 1, true) ~= nil and own.value:find(noSlot, 1, true) ~= nil
            and own.color == "bad", "the panel past the slots reads " .. own.label .. ": " .. own.value)
        expectEqual("the sources the slotless panel's row highlights", #own.sources, 1)
    end,
})

-- The rows under the header `text` in `rows`, up to the next header; nil without that header.
local function rowsUnder(rows, text)
    local under
    for _, r in ipairs(rows) do
        if r.header then
            if under then return under end
            if r.header == text then under = {} end
        elseif under and r.label then
            table.insert(under, r)
        end
    end
    return under
end

-- Fridges in another building in the bank's reach are billed to it, as a generator in its spot
-- would bill them, and listed apart: enough of them overload the bank, the overload line says how
-- much of the load stands in other buildings, and this client's window lists them under a header
-- of their own. Catches a split that drops them from the bill, or a status that loses them on its
-- way to a client.
test("renewable_energy_bank_window_lists_other_buildings_apart", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.switchOn(self, bank)
        T.bankPass(self, bank, 0, { label = "without" })
        -- Steps, since single player places a tile at once.
        T.step(function()
            local status = self.reads.without.status
            local home = bank.square:getBuilding()
            local function inOtherBuilding(square)
                local building = square:getBuilding()
                return building ~= nil and (home == nil or building:getID() ~= home:getID())
                    and GeneratorReach.covers(bank.x, bank.y, bank.z, square:getX(), square:getY(), square:getZ())
            end
            self.count = math.floor((status.limitW - status.loadW) / T.fridgeW()) + 1
            local squares = T.need(self, self.count > 0
                and T.squares(self, self.count, { indoors = true, near = bank.square, accept = inOtherBuilding }),
                self.count .. " free indoor squares in another building in the bank's reach, for fridges")
            if not squares then return end
            for _, square in ipairs(squares) do
                T.placeTile(self, square, T.MINI_FRIDGE)
            end
            T.bankPass(self, bank, 0, { label = "with" })
            T.waitForStatus(self, bank, function(s) return s.overloaded == true end,
                "this client's status of the overloaded bank")
        end)
    end,
    validate = function(self)
        local without, with = self.reads.without.status, self.reads.with.status
        local function elsewhereW(status) return status.loadElsewhere and status.loadElsewhere.watts or 0 end
        -- The fridge-freezers the status lists in other buildings: other appliances may stand there.
        local function elsewhereFridges(status)
            local entry = status.loadElsewhere and T.findIn(status.loadElsewhere.byKind, "kind", "fridgeFreezer")
            return entry and entry.count or 0
        end
        local added = self.count * T.fridgeW()
        expect(with.overloaded, "fridges in another building didn't overload the bank")
        expectNear("the load the fridges in another building add", with.loadW - without.loadW, added, 0.01)
        expectNear("the load they add in other buildings", elsewhereW(with) - elsewhereW(without), added, 0.01)
        local status = T.clientStatus(self.bank)
        local elsewhere = status and status.loadElsewhere
        if not expect(elsewhere ~= nil, "this client's status holds nothing in other buildings") then return end
        local summary = StatusRows.summary(status)
        expect(T.hasLine(summary, getText("IGUI_RenewableEnergy_OverloadedElsewhere", Format.watts(status.loadW),
            Format.watts(status.limitW), Format.watts(elsewhere.watts))), "the overload doesn't say how much is in other buildings")
        local left = StatusRows.rows(status, self.bank)
        expect(rowsUnder(left, getText("IGUI_RenewableEnergy_DrawingHere")) ~= nil, "the window has no list for this building")
        local under = rowsUnder(left, getText("IGUI_RenewableEnergy_DrawingElsewhere", Format.away(self.bank, elsewhere)))
        if not expect(under ~= nil, "the window has no list for other buildings") then return end
        local fridges = T.findIn(elsewhere.byKind, "kind", "fridgeFreezer")
        if not expectEqual("fridge-freezers this client's status lists in other buildings", fridges and fridges.count,
            elsewhereFridges(without) + self.count) then
            return
        end
        local name = getText("IGUI_RenewableEnergy_LoadFridgeFreezer")
        local label = fridges.count > 1 and getText("IGUI_RenewableEnergy_Count", name, fridges.count) or name
        expect(T.rowLabelled(under, label) ~= nil, "the list for other buildings has no row " .. label)
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
    T.DEEP_CYCLE, T.DEEP_CYCLE, T.L16, T.L16, T.CAR_BATTERY, T.INVERTER_CHARGER, T.POWER_INVERTER,
    Specs.controller, Specs.controller, Specs.charger,
}
local FULL_BANK_SOURCES = { Sprites.flat, Sprites.wall.wood.S, Sprites.rack.wood.S, Sprites.rack.metal.E }

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
            for _, sprite in ipairs(FULL_BANK_SOURCES) do
                if not T.panel(self, sprite, { near = bank, modules = T.factoryModules(100), connect = true }) then return end
            end
            T.job(self, "bank", BankJobs.TURN_ON, bank)
        end)
        T.waitForStatus(self, bank, function(status) return #status.sources == #FULL_BANK_SOURCES end,
            "this client's status with every panel connected")
        T.openWindow(self, self.bank)
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
        for _, fullType in ipairs({ T.INVERTER_CHARGER, T.POWER_INVERTER, Specs.controller, Specs.charger }) do
            expect(T.rowLabelled(window.left, getItemNameFromFullType(fullType)) ~= nil, "the window does not list the " .. fullType)
        end
        expect(window.switchButton.enable, "the switch is disabled on a bank with an inverter")
    end,
})
