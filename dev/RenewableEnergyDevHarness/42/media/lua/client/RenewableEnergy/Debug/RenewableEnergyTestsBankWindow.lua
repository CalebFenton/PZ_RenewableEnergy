require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Specs = require "RenewableEnergy/Specs"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local Format = require "RenewableEnergy/UI/Format"
local StatusRows = require "RenewableEnergy/UI/StatusRows"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local Sprites = require "RenewableEnergy/Sprites"

-- Power bank tests: the status window (UI/StatusWindow.lua, UI/StatusRows.lua).
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectEqual, player = T.test, T.expect, T.expectEqual, T.player

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
        -- Back beside the bank, so the next test starts where this one did.
        T.step(function() T.standNextTo(self.bank.square) end)
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
        local bare, charging, status = gridRow("bare"), gridRow("charging"), self.reads.charging.status
        expectEqual("the grid row of a bank without an inverter or a charger", bare and bare.value,
            getText("IGUI_RenewableEnergy_GridNoCharger"))
        expect(status.chargerW > 0, "a bank's chargers on the grid make nothing")
        expectEqual("the grid row of a bank charging from the grid", charging and charging.value,
            getText("IGUI_RenewableEnergy_GridCharging", Format.watts(status.chargerW)))
        expect(gridRow("off") == nil, "the grid row stays once the grid is off")
    end,
})

-- Queues a wait until this client's status of `bank` has the load the server's last answer gave.
local function waitForLoad(self, bank)
    T.waitForStatus(self, bank, function(status)
        return status.loadW == bank.state.status.loadW and status.solarW == bank.state.status.solarW
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
            { T.CAR_BATTERY, T.CAR_BATTERY, T.JAR_BATTERY, T.PLUG_IN_INVERTER,
                Specs.controller, Specs.charger },
            { charge = 0.5 })
        if not bank then return end
        self.bank = bank
        -- Further below its repair limit than a Service reaches.
        self.reconditionAt = Battery.repairLimit(0) - Battery.SERVICE_REPAIR - 1
        self.rebuildAt = Battery.repairLimit(2)
        self.panelCount = Specs.freeSlots + 1
        self.load = loadUpTo({ "light", "light" }, "television", Specs.inverters[T.PLUG_IN_INVERTER].watts, true)
        T.watch(self, bank)
        T.batch(function()
            T.bankPart(self, bank, Specs.charger, { condition = 0 })
            T.bankPart(self, bank, T.CAR_BATTERY, { condition = self.reconditionAt })
            T.bankPart(self, bank, T.JAR_BATTERY, { condition = self.rebuildAt, repaired = 2 })
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
        local load, limit = T.applianceWatts(self.load), Specs.inverters[T.PLUG_IN_INVERTER].watts
        expect(T.hasLine(summary, getText("IGUI_RenewableEnergy_Overloaded", Format.watts(load), Format.watts(limit))),
            "the window doesn't say the bank is overloaded with " .. load .. " W on " .. limit .. " W")
        expect(T.hasLine(summary, getText("IGUI_RenewableEnergy_InputSlots", inputs, Specs.freeSlots)),
            "without its controller the slots line doesn't read " .. inputs .. " inputs of " .. Specs.freeSlots)
        local left, right = StatusRows.rows(status, self.bank)
        local lights = T.rowLabelled(left, getText("IGUI_RenewableEnergy_LoadCount", getText("IGUI_RenewableEnergy_LoadLight"), 2))
        expectEqual("the row of 2 lights", lights and lights.value, Format.watts(T.applianceWatts({ "light", "light" })))
        local charger = T.rowLabelled(left, getItemNameFromFullType(Specs.charger))
        expectEqual("the colour of a broken charger's row", charger and charger.color, "bad")
        expectEqual("a broken charger's row", charger and charger.value, getText("IGUI_RenewableEnergy_PartBroken", "0%"))
        local function repairValue(fullType, condition, repair)
            return getText("IGUI_RenewableEnergy_BatteryValueRepair", Format.percent(status.charge),
                Format.condition(fullType, condition), getText(repair))
        end
        local batteryName = getItemNameFromFullType(T.CAR_BATTERY)
        local recondition = repairValue(T.CAR_BATTERY, self.reconditionAt, "IGUI_RenewableEnergy_RepairRecondition")
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
        local jar = T.rowLabelled(right, getItemNameFromFullType(T.JAR_BATTERY))
        local rebuild = repairValue(T.JAR_BATTERY, self.rebuildAt, "IGUI_RenewableEnergy_RepairRebuild")
        expectEqual("the row of a battery at its twice-repaired limit", jar and jar.value, rebuild)
        if not expectEqual("panel rows", #panels, self.panelCount) then return end
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
    T.DEEP_CYCLE, T.DEEP_CYCLE, T.L16, T.L16, T.CAR_BATTERY, T.INVERTER_CHARGER, T.POWER_INVERTER,
    Specs.controller, Specs.controller, Specs.charger,
}
local FULL_BANK_SOURCES = {
    { sprite = Sprites.flat, modules = T.factoryModules(100) },
    { sprite = Sprites.wall.wood.S, modules = T.factoryModules(80) },
    { sprite = Sprites.rack.wood.S, modules = T.factoryModules(100, 20) },
    { sprite = Sprites.rack.metal.E, modules = T.factoryModules(90, 90) },
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
            T.bankPart(self, bank, T.L16, { condition = 45 })
            for _, source in ipairs(FULL_BANK_SOURCES) do
                if not T.panel(self, source.sprite, { near = bank, modules = source.modules, connect = true }) then return end
            end
            T.job(self, "bank", BankJobs.TURN_ON, bank)
            T.bankPass(self, bank, 650)
            T.applyLoad(self, bank, { "fridge", "television", "light", "light", "light", "radio" })
        end)
        waitForLoad(self, bank)
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
