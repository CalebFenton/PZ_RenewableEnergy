require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Menu"
require "RenewableEnergy/UI/StatusWindow"

-- Power bank tests: the bank's context menu (UI/Menu.lua), wiring, repair and renaming from it.
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectNear, player, stateItem, copyItem = T.test, T.expect, T.expectNear, T.player, T.stateItem, T.copyItem
local Action = RenewableEnergyAction
local Specs = RenewableEnergy.Specs
local PowerBank = RenewableEnergy.PowerBank
local Menu, StatusWindow = RenewableEnergy.Menu, RenewableEnergy.StatusWindow
local CAR_BATTERY = RenewableEnergy.VehicleBattery.CAR_BATTERY
local PLUG_IN_INVERTER, POWER_INVERTER = T.PLUG_IN_INVERTER, T.POWER_INVERTER

-- Whether the option's tooltip lists the item `fullType` in the colour for what the character is
-- short of.
local function marksShort(option, fullType)
    local text = T.tooltipOf(option) or ""
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
            local menu = Menu.addWireInOptions(0, context, self.bank.object)
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
            self.withoutTools = { unavailable = plugIn ~= nil and plugIn.notAvailable, reason = T.tooltipOf(plugIn),
                screwdriverShort = marksShort(plugIn, "Base.Screwdriver"), wireShort = marksShort(plugIn, PowerBank.WIRE) }
            context:hideAndChildren()
        end)
        local wire = PowerBank.wiringFor("RenewableEnergy.PlugInInverter").wire
        T.give(self, "tools", { { type = "Base.Screwdriver" }, { type = PowerBank.WIRE, count = wire } })
        T.step(function()
            local context = T.newContext()
            local plugIn = T.optionFor(Menu.addWireInOptions(0, context, self.bank.object), self.items.parts[3])
            self.withTools = { available = plugIn ~= nil and not plugIn.notAvailable, reason = T.tooltipOf(plugIn) }
            context:hideAndChildren()
        end)
    end,
    validate = function(self)
        expectNear("Wire In options for two batteries of one type", self.batteryTypes, 1, 0)
        local name = getItemNameFromFullType("Base.CarBattery2")
        local wanted = { getText("ContextMenu_RenewableEnergy_PartCondition", name, "80%"),
            getText("ContextMenu_RenewableEnergy_PartCondition", name, "30%") }
        expect(#self.labels == 2 and self.labels[1] == wanted[1] and self.labels[2] == wanted[2],
            "the battery type lists " .. table.concat(self.labels, ", ") .. ", not " .. table.concat(wanted, ", "))
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
local WORN_INVERTER = 50
local REPAIRED_INVERTER = WORN_INVERTER + Specs.partRepair.condition
test("renewable_energy_bank_menu_repair_part", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { POWER_INVERTER }, { outdoors = true })
        if not bank then return end
        self.bank = bank
        T.setPartCondition(self, bank, POWER_INVERTER, WORN_INVERTER)
        T.waitFor(self, function()
            local inverter = copyItem(bank, POWER_INVERTER)
            return inverter ~= nil and inverter:getCondition() == WORN_INVERTER
        end, "this client's copy of the worn inverter")
        T.step(function()
            local context = T.newContext()
            local option = T.optionFor(Menu.addRepairOptions(0, context, bank.object), copyItem(bank, POWER_INVERTER))
            self.withoutScrap = { unavailable = option ~= nil and option.notAvailable, reason = T.tooltipOf(option),
                scrapShort = marksShort(option, PowerBank.SCRAP) }
            context:hideAndChildren()
        end)
        T.give(self, "scrap", { { type = PowerBank.SCRAP } })
        T.step(function()
            local context = T.newContext()
            local option = T.optionFor(Menu.addRepairOptions(0, context, bank.object), copyItem(bank, POWER_INVERTER))
            context:hideAndChildren()
            self.offered = option ~= nil and not option.notAvailable
            if not self.offered then return end
            T.standNextTo(bank.square)
            T.choose(option)
            T.waitFor(self, function()
                local inverter = copyItem(bank, POWER_INVERTER)
                return inverter ~= nil and inverter:getCondition() == REPAIRED_INVERTER
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
        expectNear("inverter condition after the repair", inverter.condition, REPAIRED_INVERTER, 0)
        expectNear("scrap left", self.counts.scrap[PowerBank.SCRAP], 0, 0)
        expectNear("scrap left on this client", player():getInventory():getCountTypeRecurse(PowerBank.SCRAP), 0, 0)
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
        T.give(self, "parts", { { type = CAR_BATTERY }, { type = "Base.Screwdriver" }, { type = PowerBank.WIRE } })
        T.step(function()
            local battery = self.items.parts[1]
            self.batteryId = battery:getID()
            -- An action takes its duration when it is made, so these two are made with the instant
            -- cheat off and never queued.
            p:setTimedActionInstantCheat(false)
            if not T.needActionTime(self) then return end
            local function wiringTime(level)
                T.setPerk(self, Perks.Electricity, level)
                return Action:new(p, Action.WIRE_IN, nil, bank.object, nil, battery).maxTime
            end
            self.unskilled, self.skilled = wiringTime(0), wiringTime(10)
            p:setTimedActionInstantCheat(true)
            local context = T.newContext()
            local option = T.optionFor(Menu.addWireInOptions(0, context, bank.object), battery)
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
        expect(stateItem(self.bank.state, CAR_BATTERY) ~= nil, "the wired battery isn't in the server's bank, which holds "
            .. (#held > 0 and table.concat(held, ", ") or "nothing"))
        local battery = bank:getContainer():getItemWithID(self.batteryId)
        expect(battery ~= nil, "the wired battery isn't in this client's copy of the bank")
        local status = T.clientStatus(self.bank)
        expect(status ~= nil and #status.batteries == 1, "the bank's status doesn't list the wired battery")
        if not battery then return end
        local context = T.newContext()
        local unwire = T.optionFor(Menu.addUnwireOptions(0, context, bank), battery)
        expect(unwire ~= nil and not unwire.notAvailable, "the bank doesn't offer to unwire the battery wired in")
        context:hideAndChildren()
    end,
})

-- Unwire's All Batteries takes out every battery and leaves the inverter wired; with room left for
-- one battery, the other lands at the character's feet, past the inventory's capacity.
test("renewable_energy_bank_menu_unwire_all_batteries", {
    instant = true,
    run = function(self)
        local p = player()
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, CAR_BATTERY, PLUG_IN_INVERTER }, { outdoors = true })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        -- A screwdriver to unwire with, and one-kilogram stones up to room for one and a half
        -- batteries: one fits, the second doesn't.
        local inventory = p:getInventory()
        local batteryKg = getScriptManager():FindItem(CAR_BATTERY):getActualWeight()
        local screwdriverKg = getScriptManager():FindItem("Base.Screwdriver"):getActualWeight()
        local room = inventory:getEffectiveCapacity(p) - inventory:getCapacityWeight() - screwdriverKg
        T.give(self, "filler", { { type = "Base.Screwdriver" }, { type = "Base.Stone2", count = math.floor(room - 1.5 * batteryKg) } })
        T.step(function()
            local all = T.menuOption(Menu.addUnwireOptions, bank.object, getText("ContextMenu_RenewableEnergy_AllBatteries", 2))
            self.offered = all ~= nil and not all.notAvailable
            if not self.offered then return end
            T.choose(all)
            T.waitFor(self, function()
                local status = T.clientStatus(bank)
                return status ~= nil and #status.batteries == 0
            end, "this client's status of the bank with no battery left")
            T.bankState(self, bank)
            T.count(self, "carried", { CAR_BATTERY })
            T.count(self, "carriedOrDropped", { CAR_BATTERY }, { dropped = true })
        end)
    end,
    validate = function(self)
        if not expect(self.offered, "a bank with two batteries doesn't offer Unwire > All Batteries") then return end
        local state = self.bank.state
        expect(stateItem(state, CAR_BATTERY) == nil, "a battery is still wired in")
        expect(stateItem(state, PLUG_IN_INVERTER) ~= nil, "All Batteries unwired the inverter too")
        local carried, total = self.counts.carried[CAR_BATTERY], self.counts.carriedOrDropped[CAR_BATTERY]
        expect(carried == 1 and total == 2, "with room for one battery, " .. tostring(carried) .. " went into the inventory and "
            .. tostring(total - carried) .. " onto the floor")
    end,
})

-- Wire In's All Batteries fills the bank's free battery slots from what the character carries,
-- best condition first, taking a battery's wire for each: three batteries for a box's two slots
-- leave the worst one carried.
test("renewable_energy_bank_menu_wire_in_all_batteries", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        self.slots = Specs.banks["RenewableEnergy.BatteryBoxWood"].maxBatteries
        if not T.need(self, self.slots == 2, "a battery box of two slots, which the three batteries overfill by one") then return end
        T.watch(self, bank)
        T.give(self, "parts", { { type = CAR_BATTERY, condition = 60 }, { type = CAR_BATTERY, condition = 20 },
            { type = CAR_BATTERY, condition = 90 }, { type = "Base.Screwdriver" },
            { type = PowerBank.WIRE, count = 3 * PowerBank.wiringFor(CAR_BATTERY).wire } })
        T.step(function()
            local all = T.menuOption(Menu.addWireInOptions, bank.object, getText("ContextMenu_RenewableEnergy_AllBatteries", self.slots))
            self.offered = all ~= nil and not all.notAvailable
            if not self.offered then
                self.refused = tostring(all and T.tooltipOf(all))
                return
            end
            T.choose(all)
            T.waitFor(self, function()
                local status = T.clientStatus(bank)
                return status ~= nil and #status.batteries == self.slots
            end, "this client's status of the bank with its battery slots full")
            T.bankState(self, bank)
            T.count(self, "left", { CAR_BATTERY, PowerBank.WIRE })
        end)
    end,
    validate = function(self)
        if not expect(self.offered, "carrying three batteries, Wire In doesn't offer All Batteries ("
            .. tostring(self.slots) .. "): " .. tostring(self.refused)) then return end
        local wired = {}
        for _, item in ipairs(self.bank.state.items) do
            table.insert(wired, item.condition)
        end
        table.sort(wired)
        expect(#wired == 2 and wired[1] == 60 and wired[2] == 90, "All Batteries wired in batteries at "
            .. table.concat(wired, ", ") .. ", not the two best, at 60 and 90")
        expectNear("batteries left carried", self.counts.left[CAR_BATTERY], 1, 0)
        expectNear("wire left", self.counts.left[PowerBank.WIRE], PowerBank.wiringFor(CAR_BATTERY).wire, 0)
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
            ISTimedActionQueue.add(Action:new(player(), Action.RENAME, nil, bank.object, nil, nil, "  Cellar  "))
            T.waitFor(self, function() return Menu.bankLabel(bank.object) == "Cellar" end, "this client's label of the renamed bank")
            T.step(function()
                -- The wait for "Cellar" is the menu's check; the window's title is read off the same copy.
                local window = StatusWindow:openOn(0, bank.object)
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
        T.expectOk(self.named, "renaming the bank Shed")
        expect(not self.long.ok, "the authority took a name longer than " .. PowerBank.NAME_LENGTH .. " characters")
        expect(not self.twoLines.ok, "the authority took a name on two lines")
        expect(self.refusedState.name == "Shed", "the refused names left the bank called " .. tostring(self.refusedState.name))
        expect(self.fullLength.ok and self.bank.state.name == self.full, "a name of " .. PowerBank.NAME_LENGTH
            .. " characters left the bank called " .. tostring(self.bank.state.name))
        expect(#self.typed == PowerBank.NAME_LENGTH, "the rename box holds " .. #self.typed .. " characters, expected "
            .. PowerBank.NAME_LENGTH)
    end,
})
