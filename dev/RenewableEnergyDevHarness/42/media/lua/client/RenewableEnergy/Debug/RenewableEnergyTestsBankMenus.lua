require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Specs = require "RenewableEnergy/Specs"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local BankMenu = require "RenewableEnergy/UI/BankMenu"
local SourceMenu = require "RenewableEnergy/UI/SourceMenu"
local GardenLightMenu = require "RenewableEnergy/UI/GardenLightMenu"
local RenameBank = require "RenewableEnergy/UI/RenameBank"
local Wiring = require "RenewableEnergy/PowerBank/Wiring"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sprites = require "RenewableEnergy/Sprites"

-- Power bank tests: the bank's context menu (UI/BankMenu.lua), wiring, repair and renaming from it.
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectEqual = T.test, T.expect, T.expectEqual
local player, stateItem, copyItem = T.player, T.stateItem, T.copyItem

-- Whether the option's tooltip lists the item `fullType` in the colour for what the character is
-- short of.
local function marksShort(option, fullType)
    local text = T.tooltipOf(option)
    return text:find(ISVehicleMechanics.bhs .. getItemNameFromFullType(fullType), 1, true) ~= nil
end

-- Menus ----------------------------------------------------------------------------------------

-- Right-clicking a bank builds its submenu through vanilla's menu builder, without vanilla's
-- generator submenu that its IsoGenerator would otherwise get.
test("renewable_energy_bank_context_menu_opens_bank_menu", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
    end,
    validate = function(self)
        local bank = self.bank.object
        local context = T.worldMenu(bank)
        if not expect(context ~= nil, "right-clicking a bank built no menu") then return end
        local option = T.optionNamed(context, BankMenu.bankLabel(bank))
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
        local submenu = BankMenu.addBankOptions(0, context, self.bank.object)
        expect(T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_Status")) ~= nil, "the bank menu has no status option")
        expect(T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_Rename")) ~= nil, "the bank menu has no Rename")
        T.noteOption(self, "Turn On without an inverter", T.optionNamed(submenu, getText("ContextMenu_Turn_On")))
        T.expectOptionRefused(self, "Turn On without an inverter")
        T.noteOption(self, "Wire In with no part carried", T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_WireIn")))
        T.expectOptionRefused(self, "Wire In with no part carried")
        expectEqual("Wire In with no part carried's tooltip", self.menu["Wire In with no part carried"].tooltip,
            getText("Tooltip_RenewableEnergy_NothingToWire"))
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
        for _, onFill in ipairs({ BankMenu.onFill, SourceMenu.onFill, GardenLightMenu.onFill }) do
            onFill(0, context, { floor }, false)
        end
        expectEqual("options a plain floor added", context.numOptions - before, 0)
        context:hideAndChildren()
    end,
})

-- Wire In offers each carried part type once, listing every part of it with its condition, greys
-- out one that can't go in listing everything it lacks, and offers it once it can.
test("renewable_energy_bank_menu_wire_in_options", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {})
        if not self.bank then return end
        T.give(self, "parts", { { type = "Base.CarBattery2", condition = 80 }, { type = "Base.CarBattery2", condition = 30 },
            { type = "RenewableEnergy.PlugInInverter" } })
        T.step(function()
            local context = T.newContext()
            local menu = BankMenu.addWireInOptions(0, context, self.bank.object)
            self.batteryTypes, self.labels = 0, {}
            for _, option in ipairs(menu.options or {}) do
                if option.name == getItemNameFromFullType("Base.CarBattery2") then
                    self.batteryTypes = self.batteryTypes + 1
                    local batteries = T.subMenu(menu, option)
                    for _, battery in ipairs(batteries and batteries.options or {}) do
                        table.insert(self.labels, battery.name)
                    end
                end
            end
            local plugIn = T.optionFor(menu, self.items.parts[3])
            T.noteOption(self, "Wire In of the inverter without tools", plugIn)
            self.short = { screwdriver = marksShort(plugIn, "Base.Screwdriver"), wire = marksShort(plugIn, Wiring.WIRE) }
            context:hideAndChildren()
        end)
        local wire = Wiring.forPart("RenewableEnergy.PlugInInverter").wire
        T.give(self, "tools", { { type = "Base.Screwdriver" }, { type = Wiring.WIRE, count = wire } })
        T.step(function()
            local context = T.newContext()
            T.noteOption(self, "Wire In of the inverter with tools",
                T.optionFor(BankMenu.addWireInOptions(0, context, self.bank.object), self.items.parts[3]))
            context:hideAndChildren()
        end)
    end,
    validate = function(self)
        expectEqual("Wire In options for two batteries of one type", self.batteryTypes, 1)
        local name = getItemNameFromFullType("Base.CarBattery2")
        local wanted = { getText("ContextMenu_RenewableEnergy_WithShare", name, "80%"),
            getText("ContextMenu_RenewableEnergy_WithShare", name, "30%") }
        expectEqual("the battery type's list", table.concat(self.labels, " | "), table.concat(wanted, " | "))
        T.expectOptionRefused(self, "Wire In of the inverter without tools")
        expect(self.short.screwdriver and self.short.wire,
            "Wire In doesn't mark both the screwdriver and the wire short for the inverter")
        T.expectOffered(self, "Wire In of the inverter with tools")
    end,
})

-- Repair offers each inverter, greyed out with the scrap marked short while there is none, and
-- once there is, walks over and mends the inverter in place with one scrap, on the server and this
-- client's copy.
local WORN_INVERTER = 50
local REPAIRED_INVERTER = WORN_INVERTER + Specs.partRepair.condition
test("renewable_energy_bank_menu_repair_part", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.POWER_INVERTER }, { outdoors = true })
        if not bank then return end
        self.bank = bank
        T.bankPart(self, bank, T.POWER_INVERTER, { condition = WORN_INVERTER })
        T.waitFor(self, function()
            local inverter = copyItem(bank, T.POWER_INVERTER)
            return inverter ~= nil and inverter:getCondition() == WORN_INVERTER
        end, "this client's copy of the worn inverter")
        T.step(function()
            local context = T.newContext()
            local option = T.optionFor(BankMenu.addRepairOptions(0, context, bank.object), copyItem(bank, T.POWER_INVERTER))
            T.noteOption(self, "Repair without scrap", option)
            self.scrapShort = marksShort(option, Wiring.SCRAP)
            context:hideAndChildren()
        end)
        T.give(self, "scrap", { { type = Wiring.SCRAP } })
        T.step(function()
            local context = T.newContext()
            local option = T.optionFor(BankMenu.addRepairOptions(0, context, bank.object), copyItem(bank, T.POWER_INVERTER))
            context:hideAndChildren()
            if not T.chooseOption(self, "Repair with scrap", option, bank.square) then return end
            T.waitFor(self, function()
                local inverter = copyItem(bank, T.POWER_INVERTER)
                return inverter ~= nil and inverter:getCondition() == REPAIRED_INVERTER
            end, "this client's copy of the repaired inverter")
            T.readRecord(self, bank)
            T.count(self, "scrap", { Wiring.SCRAP })
        end)
    end,
    validate = function(self)
        T.expectOptionRefused(self, "Repair without scrap")
        expect(self.scrapShort, "Repair doesn't mark the scrap short")
        if not T.expectOffered(self, "Repair with scrap") then return end
        local inverter = stateItem(self.bank.state, T.POWER_INVERTER)
        if not expect(inverter ~= nil, "repairing took the inverter out of the bank") then return end
        expectEqual("inverter condition after the repair", inverter.condition, REPAIRED_INVERTER)
        expectEqual("scrap left", self.counts.scrap[Wiring.SCRAP], 0)
        expectEqual("scrap left on this client", player():getInventory():getCountTypeRecurse(Wiring.SCRAP), 0)
    end,
})

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
        T.give(self, "parts", { { type = T.CAR_BATTERY }, { type = "Base.Screwdriver" }, { type = Wiring.WIRE } })
        T.step(function()
            local battery = self.items.parts[1]
            self.batteryId = battery:getID()
            -- An action takes its duration when it is made, so these two are made with the instant
            -- cheat off and never queued.
            p:setTimedActionInstantCheat(false)
            if not T.need(self, not p:isTimedActionInstant(),
                "the debug option Cheats > Timed Action > Instant off, which makes every action instant") then return end
            local function wiringTime(level)
                T.setPerk(self, Perks.Electricity, level)
                return RenewableEnergyAction:new(p, "bank", BankJobs.WIRE_IN, bank.object, battery).maxTime
            end
            self.unskilled, self.skilled = wiringTime(0), wiringTime(10)
            p:setTimedActionInstantCheat(true)
            local context = T.newContext()
            local option = T.optionFor(BankMenu.addWireInOptions(0, context, bank.object), battery)
            context:hideAndChildren()
            if not T.chooseOption(self, "Wire In", option) then return end
            T.waitForStatus(self, bank, function(status)
                return #status.batteries == 1 and bank.object:getContainer():getItemWithID(self.batteryId) ~= nil
            end, "this client's copy of the bank with the battery wired in")
            T.readRecord(self, bank)
        end)
    end,
    validate = function(self)
        expect(self.skilled < self.unskilled, string.format(
            "wiring takes %s at Electricity 10 and %s at 0", self.skilled, self.unskilled))
        if not T.expectOffered(self, "Wire In") then return end
        local bank = self.bank.object
        local held = {}
        for _, item in ipairs(self.bank.state.items) do
            table.insert(held, item.type)
        end
        expect(stateItem(self.bank.state, T.CAR_BATTERY) ~= nil, "the wired battery isn't in the server's bank, which holds "
            .. (#held > 0 and table.concat(held, ", ") or "nothing"))
        local battery = bank:getContainer():getItemWithID(self.batteryId)
        expect(battery ~= nil, "the wired battery isn't in this client's copy of the bank")
        local status = T.clientStatus(self.bank)
        expect(status ~= nil and #status.batteries == 1, "the bank's status doesn't list the wired battery")
        if not battery then return end
        local context = T.newContext()
        T.noteOption(self, "Unwire of the battery wired in", T.optionFor(BankMenu.addUnwireOptions(0, context, bank), battery))
        T.expectOffered(self, "Unwire of the battery wired in")
        context:hideAndChildren()
    end,
})

-- Unwire's All Batteries takes out every battery and leaves the inverter wired; with room left for
-- one battery, the other lands at the character's feet, past the inventory's capacity.
test("renewable_energy_bank_menu_unwire_all_batteries", {
    instant = true,
    run = function(self)
        local p = player()
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.CAR_BATTERY, T.PLUG_IN_INVERTER }, { outdoors = true })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        -- A screwdriver to unwire with, and one-kilogram stones up to room for one and a half
        -- batteries: one fits, the second doesn't.
        local inventory = p:getInventory()
        local batteryKg = getScriptManager():FindItem(T.CAR_BATTERY):getActualWeight()
        local screwdriverKg = getScriptManager():FindItem("Base.Screwdriver"):getActualWeight()
        local room = inventory:getEffectiveCapacity(p) - inventory:getCapacityWeight() - screwdriverKg
        T.give(self, "filler", { { type = "Base.Screwdriver" }, { type = "Base.Stone2", count = math.floor(room - 1.5 * batteryKg) } })
        T.step(function()
            local all = T.menuOption(BankMenu.addUnwireOptions, bank.object, getText("ContextMenu_RenewableEnergy_AllBatteries", 2))
            if not T.chooseOption(self, "Unwire > All Batteries", all) then return end
            T.waitForStatus(self, bank, function(status) return #status.batteries == 0 end,
                "this client's status of the bank with no battery left")
            T.readRecord(self, bank)
            T.count(self, "carried", { T.CAR_BATTERY })
            T.count(self, "carriedOrDropped", { T.CAR_BATTERY }, { dropped = true })
        end)
    end,
    validate = function(self)
        if not T.expectOffered(self, "Unwire > All Batteries") then return end
        local state = self.bank.state
        expect(stateItem(state, T.CAR_BATTERY) == nil, "a battery is still wired in")
        expect(stateItem(state, T.PLUG_IN_INVERTER) ~= nil, "All Batteries unwired the inverter too")
        local carried, total = self.counts.carried[T.CAR_BATTERY], self.counts.carriedOrDropped[T.CAR_BATTERY]
        expectEqual("batteries unwired into the inventory with room for one", carried, 1)
        expectEqual("batteries unwired onto the floor with room for one", total - carried, 1)
    end,
})

-- All Batteries selects the best two, combines their wire, and requires the L-16's extra wrench
-- without demanding a screwdriver for each battery. The worst carried battery stays out.
test("renewable_energy_bank_menu_wire_in_all_batteries", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        self.slots = Specs.banks["RenewableEnergy.BatteryBoxWood"].maxBatteries
        if not T.need(self, self.slots == 2, "a battery box of two slots, which the three batteries overfill by one") then return end
        T.watch(self, bank)
        T.give(self, "parts", { { type = T.CAR_BATTERY, condition = 60 }, { type = T.CAR_BATTERY, condition = 20 },
            { type = T.L16, condition = 90 }, { type = "Base.Screwdriver" },
            { type = Wiring.WIRE, count = 1 + Wiring.forPart(T.CAR_BATTERY).wire + Wiring.forPart(T.L16).wire } })
        T.step(function()
            T.noteOption(self, "without wrench", T.menuOption(BankMenu.addWireInOptions, bank.object,
                getText("ContextMenu_RenewableEnergy_AllBatteries", self.slots)))
        end)
        T.give(self, "wrench", { { type = "Base.Wrench" } })
        T.step(function()
            local all = T.menuOption(BankMenu.addWireInOptions, bank.object, getText("ContextMenu_RenewableEnergy_AllBatteries", self.slots))
            if not T.chooseOption(self, "Wire In > All Batteries", all) then return end
            T.waitForStatus(self, bank, function(status) return #status.batteries == self.slots end,
                "this client's status of the bank with its battery slots full")
            T.readRecord(self, bank)
            T.count(self, "left", { T.CAR_BATTERY, T.L16, Wiring.WIRE, "Base.Screwdriver", "Base.Wrench" })
        end)
    end,
    validate = function(self)
        if not T.expectOffered(self, "Wire In > All Batteries") then return end
        T.expectOptionRefused(self, "without wrench")
        local wired = {}
        for _, item in ipairs(self.bank.state.items) do
            table.insert(wired, item.condition)
        end
        table.sort(wired)
        expectEqual("the conditions of the batteries All Batteries wired in", table.concat(wired, ", "), "60, 90")
        expectEqual("batteries left carried", self.counts.left[T.CAR_BATTERY], 1)
        expectEqual("L-16 batteries left carried", self.counts.left[T.L16], 0)
        expectEqual("wire left after both jobs", self.counts.left[Wiring.WIRE], 1)
        expectEqual("screwdrivers kept", self.counts.left["Base.Screwdriver"], 1)
        expectEqual("wrenches kept", self.counts.left["Base.Wrench"], 1)
    end,
})

-- Connect All is a sequence, not an atomic demand for enough slots for every candidate.
test("renewable_energy_bank_menu_connects_sources_that_fit", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        local sprites = Sprites
        self.large = T.panel(self, sprites.windCharger.alternator.steel.N, { near = bank })
        self.small = T.panel(self, sprites.flat, { near = bank })
        if not (self.large and self.small) then return end
        T.watch(self, bank)
        T.holdLight(self)
        T.step(function()
            local option = T.menuOption(BankMenu.addBankOptions, bank.object,
                getText("ContextMenu_RenewableEnergy_ConnectSourcesInReach", 2))
            if not T.chooseOption(self, "connect what fits", option) then return end
            T.waitForStatus(self, bank, function(status) return status.inputSlots.used == 1 end,
                "the panel connected without the oversized turbine")
            T.readRecord(self, bank)
        end)
    end,
    validate = function(self)
        if not T.expectOffered(self, "connect what fits") then return end
        expect(T.stateSource(self.bank.state, self.small) ~= nil, "the fitting panel was not connected")
        expect(T.stateSource(self.bank.state, self.large) == nil, "the oversized turbine was connected")
    end,
})

-- A rename goes through the bank trimmed and shows in its menu and window, and an empty name gives
-- the tier's name back.
test("renewable_energy_bank_rename_trims_and_empty_restores_tier_name", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryRackMetal", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        T.step(function()
            if not T.walkTo(self, bank.square, "the bank") then return end
            ISTimedActionQueue.add(RenewableEnergyAction:new(player(), "bank", BankJobs.RENAME, bank.object, "  Cellar  "))
            T.waitFor(self, function() return BankMenu.bankLabel(bank.object) == "Cellar" end, "this client's label of the renamed bank")
            -- The wait for "Cellar" is the menu's check; the window's title is read off the same copy.
            T.openWindow(self, bank)
            T.step(function()
                self.title = self.window.title
                self.window:close()
                local action = RenewableEnergyAction:new(player(), "bank", BankJobs.RENAME, bank.object, "")
                self.emptyAllowed = action:canPerform()
                ISTimedActionQueue.add(action)
                T.waitFor(self, function() return BankMenu.bankLabel(bank.object) ~= "Cellar" end,
                    "this client's label of the bank renamed to nothing")
                T.readRecord(self, bank)
            end)
        end)
    end,
    validate = function(self)
        expectEqual("the renamed bank's window title", self.title, "Cellar")
        expect(self.emptyAllowed, "renaming to an empty name was refused")
        expectEqual("this client's label of the bank renamed to nothing", BankMenu.bankLabel(self.bank.object),
            getItemNameFromFullType("RenewableEnergy.BatteryRackMetal"))
        expectEqual("the server's name of the bank renamed to nothing", self.bank.state.name, "")
    end,
})

-- The rename box stops typing at the longest name a bank takes, and the authority refuses a longer
-- name, or one on more than one line, leaving the name as it was; a name of the full length goes.
test("renewable_energy_bank_rename_refuses_long_or_multiline_names", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        local longest = BankJobs.NAME_LENGTH
        self.full = string.rep("y", longest)
        T.batch(function()
            T.job(self, "bank", BankJobs.RENAME, bank, "Shed", "named")
            T.job(self, "bank", BankJobs.RENAME, bank, string.rep("x", longest + 1), "long")
            T.job(self, "bank", BankJobs.RENAME, bank, "Shed\nbank", "twoLines")
            T.readRecord(self, bank, "refused")
            T.job(self, "bank", BankJobs.RENAME, bank, self.full, "fullLength")
            T.readRecord(self, bank)
        end)
        T.step(function()
            local box = RenameBank.ask(0, bank.object)
            T.defer(self, function() box:destroy() end)
            box.entry:setText(string.rep("z", longest + 5))
            -- The box cuts what was typed past its limit when it next updates.
            T.wait(2)
            T.step(function() self.typed = box.entry:getText() end)
        end)
    end,
    validate = function(self)
        local reads = self.reads
        T.expectOk(reads.named, "renaming the bank Shed")
        expect(not reads.long.ok, "the authority took a name longer than " .. BankJobs.NAME_LENGTH .. " characters")
        expect(not reads.twoLines.ok, "the authority took a name on two lines")
        expectEqual("the bank's name after the refused names", reads.refused.name, "Shed")
        T.expectOk(reads.fullLength, "renaming the bank with a name of " .. BankJobs.NAME_LENGTH .. " characters")
        expectEqual("the bank's name after a name of " .. BankJobs.NAME_LENGTH .. " characters", self.bank.state.name, self.full)
        expectEqual("characters in the rename box", #self.typed, BankJobs.NAME_LENGTH)
    end,
})
