require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibCraft"
require "TimedActions/ISInventoryTransferAction"
local Specs = require "RenewableEnergy/Specs"
local Wiring = require "RenewableEnergy/PowerBank/Wiring"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"

-- Power bank tests: wiring parts in and out, their wear and repair, and the crafted inverters.
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual = T.test, T.expect, T.expectNear, T.expectEqual
local player, stateItem = T.player, T.stateItem

-- Parts: wiring and wear -----------------------------------------------------------------------

-- A bank's container refuses every transfer in and out, on this client's copy where the player
-- drags: parts move only by being wired. Other transfers still work.
test("renewable_energy_bank_container_refuses_transfers", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY })
        if not self.bank then return end
        T.give(self, "carried", { { type = "Base.Bag_Schoolbag" }, { type = "Base.Hammer" } })
        T.readRecord(self, self.bank)
        -- Last: the queue drops everything after an action that turns out invalid when it starts.
        T.step(function()
            local p, container = player(), self.bank.object:getContainer()
            self.allowsBattery = container:isItemAllowed(instanceItem("Base.CarBattery2"))
            self.battery = container:getFirstType(T.CAR_BATTERY)
            local dragOut = ISInventoryTransferAction:new(p, self.battery, container, p:getInventory())
            self.dragValid = dragOut:isValid()
            ISTimedActionQueue.add(dragOut)
        end)
    end,
    validate = function(self)
        local p, bank, state = player(), self.bank.object, self.bank.state
        expect(not self.allowsBattery, "a battery can be dropped into a bank without wiring it in")
        expect(not self.dragValid, "moving a wired battery out of the bank is a valid transfer")
        expect(stateItem(state, T.CAR_BATTERY) ~= nil and bank:getContainer():contains(self.battery)
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
        local batteryWire, inverterWiring = Wiring.forPart(T.CAR_BATTERY).wire, Wiring.forPart(T.INVERTER_CHARGER)
        self.maxBatteries = Specs.banks["RenewableEnergy.BatteryBoxWood"].maxBatteries
        T.setPerk(self, Perks.Electricity, inverterWiring.skill - 1)
        local bank = T.bank(self, "batteryBoxWood", {})
        if not bank then return end
        self.bank = bank
        local function wire(label, fullType)
            T.job(self, "bank", BankJobs.WIRE_IN, bank, { type = fullType }, label, { xp = { "Electricity" } })
        end
        T.give(self, "first", { { type = T.CAR_BATTERY }, { type = "Base.Hammer" } })
        wire("hammer", "Base.Hammer")
        wire("noTool", T.CAR_BATTERY)
        T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
        wire("noWire", T.CAR_BATTERY)
        T.give(self, "wire", { { type = Wiring.WIRE, count = batteryWire } })
        wire("wired", T.CAR_BATTERY)
        T.count(self, "wired", { Wiring.WIRE })
        T.job(self, "bank", BankJobs.UNWIRE, bank, { type = T.CAR_BATTERY, inTarget = true }, "unwired")
        T.count(self, "unwired", { Wiring.WIRE, T.CAR_BATTERY })
        wire("rewired", T.CAR_BATTERY)
        T.give(self, "inverter", { { type = Wiring.WIRE, count = inverterWiring.wire }, { type = T.INVERTER_CHARGER } })
        wire("skill", T.INVERTER_CHARGER)
        -- The rest of the slots, and one battery more.
        T.give(self, "batteries", { { type = Wiring.WIRE, count = self.maxBatteries * batteryWire },
            { type = "Base.CarBattery2", count = self.maxBatteries } })
        for i = 2, self.maxBatteries do
            wire("fill" .. i, "Base.CarBattery2")
        end
        wire("full", "Base.CarBattery2")
        T.readRecord(self, bank)
    end,
    validate = function(self)
        local reads = self.reads
        T.expectRefused(reads.hammer, "Tooltip_RenewableEnergy_NotAPart", "a hammer was wired in")
        T.expectRefused(reads.noTool, "tool", "a battery was wired in without a screwdriver")
        T.expectRefused(reads.noWire, "item", "a battery was wired in without wire")
        T.expectOk(reads.wired, "wiring a battery in with a screwdriver and wire")
        expect(reads.wired.xpAfter.Electricity > reads.wired.xpBefore.Electricity, "the first wiring gave no Electricity XP")
        expectEqual("wire left after wiring a battery in", self.counts.wired[Wiring.WIRE], 0)
        T.expectOk(reads.unwired, "unwiring the battery")
        expectEqual("batteries back after unwiring", self.counts.unwired[T.CAR_BATTERY], 1)
        expectEqual("wire back after unwiring", self.counts.unwired[Wiring.WIRE], Wiring.forPart(T.CAR_BATTERY).wire)
        T.expectOk(reads.rewired, "wiring the battery in again")
        expectEqual("XP for wiring the same battery again", reads.rewired.xpAfter.Electricity - reads.rewired.xpBefore.Electricity, 0)
        T.expectRefused(reads.skill, "skill", "an Inverter/Charger was wired in a level below its skill")
        for i = 2, self.maxBatteries do
            T.expectOk(reads["fill" .. i], "a battery box taking battery " .. i .. " of " .. self.maxBatteries)
        end
        T.expectRefused(reads.full, "Tooltip_RenewableEnergy_NoSlot", "a full battery box took another battery")
        expectEqual("batteries in the full box", self.bank.state.batteries, self.maxBatteries)
    end,
})

-- A part comes out with the tools it went in with, as a car part does: a screwdriver for a car
-- battery, a screwdriver and a wrench for an L-16, which won't go in without the wrench either.
test("renewable_energy_bank_unwiring_needs_the_wiring_tools", {
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.L16 })
        if not bank then return end
        self.bank = bank
        local function unwire(label, fullType)
            T.job(self, "bank", BankJobs.UNWIRE, bank, { type = fullType, inTarget = true }, label)
        end
        unwire("carBare", T.CAR_BATTERY)
        T.give(self, "screwdriver", { { type = "Base.Screwdriver" }, { type = T.L16 },
            { type = Wiring.WIRE, count = Wiring.forPart(T.L16).wire } })
        T.job(self, "bank", BankJobs.WIRE_IN, bank, { type = T.L16 }, "l16InScrewdriver")
        unwire("l16Screwdriver", T.L16)
        unwire("carScrewdriver", T.CAR_BATTERY)
        T.give(self, "wrench", { { type = "Base.Wrench" } })
        unwire("l16Both", T.L16)
    end,
    validate = function(self)
        local reads = self.reads
        T.expectRefused(reads.carBare, "tool", "a car battery came out without a screwdriver")
        T.expectRefused(reads.l16InScrewdriver, "tool", "an L-16 went in without a wrench")
        T.expectRefused(reads.l16Screwdriver, "tool", "an L-16 came out without a wrench")
        T.expectOk(reads.carScrewdriver, "a car battery coming out with a screwdriver")
        T.expectOk(reads.l16Both, "an L-16 coming out with a screwdriver and a wrench")
    end,
})

-- Queues repairing the first Inverter/Charger in `bank` as the server's character, leaving the
-- answer in self.reads[label].
local function repair(self, label, bank)
    T.job(self, "bank", BankJobs.REPAIR, bank, { type = T.INVERTER_CHARGER, inTarget = true }, label)
end

-- A wear pass: enough passes of PASS_HOURS, each from a full charge so that what the houses around
-- draw can't run the bank empty, which would stop its parts' wear, for an inverter's wear to make
-- a whole point, with half a point to spare so the summed fractions can't fall short of it.
local PASS_HOURS = 20
local WEAR_PASSES = math.ceil(1.5 / (Specs.partWear.perHour.inverter * PASS_HOURS))
local WEAR_HOURS = WEAR_PASSES * PASS_HOURS
-- The last pass's state lands in self.reads[label].
local function wearPass(self, bank, label)
    for _ = 1, WEAR_PASSES do
        T.setCharge(self, bank, 1)
        T.bankPass(self, bank, 0, { hours = PASS_HOURS, label = label })
    end
end
-- Inverters and controllers wear in proportion to the hours their bank powers its area and not
-- while it is off, a part at 0 does nothing, and Electronics Scrap repairs a part only at its skill
-- and only if worn.
test("renewable_energy_bank_part_wear_and_repair", {
    run = function(self)
        T.setGrid(self, false)
        T.setPerk(self, Perks.Electricity, Specs.partRepair.skill - 1)
        local parts = { T.INVERTER_CHARGER, Specs.controller }
        for _ = 1, Specs.banks["RenewableEnergy.BatteryRackMetal"].maxBatteries do
            table.insert(parts, T.L16)
        end
        local bank = T.bank(self, "batteryRackMetal", parts)
        if not bank then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.batch(function()
            wearPass(self, bank, "once")
            wearPass(self, bank, "twice")
            T.job(self, "bank", BankJobs.TURN_OFF, bank)
            wearPass(self, bank, "off")
            T.job(self, "bank", BankJobs.TURN_ON, bank)
            T.bankPart(self, bank, T.INVERTER_CHARGER, { condition = 50 })
            T.give(self, "scrap", { { type = Wiring.SCRAP } })
            repair(self, "unskilled", bank)
        end)
        T.step(function() T.setPerk(self, Perks.Electricity, Specs.partRepair.skill) end)
        T.batch(function()
            repair(self, "repaired", bank)
            T.readRecord(self, bank, "afterRepair")
            T.count(self, "scrap", { Wiring.SCRAP })
            repair(self, "noScrap", bank)
            -- Past ConditionMax, which the setter keeps it to.
            T.bankPart(self, bank, T.INVERTER_CHARGER, { condition = 1000 })
            T.give(self, "moreScrap", { { type = Wiring.SCRAP } })
            repair(self, "whole", bank)
        end)
    end,
    validate = function(self)
        local reads = self.reads
        for _, pass in ipairs({ { reads.once, "first" }, { reads.twice, "second" } }) do
            local status = pass[1].status
            expectEqual(string.format("the state of the bank carrying its %.1f W load in its %s pass", status.loadW, pass[2]),
                status.state, "on")
        end
        -- What WEAR_HOURS on and twice that take, in whole points of condition (Wear.take keeps
        -- the fractions for later).
        local perHour = Specs.partWear.perHour
        for _, part in ipairs({ { T.INVERTER_CHARGER, perHour.inverter }, { Specs.controller, perHour.controller } }) do
            local fullType, rate = part[1], part[2]
            expectEqual(fullType .. " after " .. WEAR_HOURS .. " hours on", T.stateCondition(reads.once, fullType),
                100 - math.floor(rate * WEAR_HOURS))
            expectEqual(fullType .. " after " .. 2 * WEAR_HOURS .. " hours on", T.stateCondition(reads.twice, fullType),
                100 - math.floor(rate * 2 * WEAR_HOURS))
            expectEqual(fullType .. " after " .. WEAR_HOURS .. " more hours off", T.stateCondition(reads.off, fullType),
                T.stateCondition(reads.twice, fullType))
        end
        expect(T.stateCondition(reads.twice, T.INVERTER_CHARGER) < 100, "an inverter on for " .. 2 * WEAR_HOURS .. " hours didn't wear")
        T.expectRefused(reads.unskilled, "skill", "a part was repaired below Electricity " .. Specs.partRepair.skill)
        T.expectOk(reads.repaired, "repairing a worn inverter with scrap")
        expectEqual("condition after one scrap", T.stateCondition(reads.afterRepair, T.INVERTER_CHARGER),
            50 + Specs.partRepair.condition)
        expectEqual("scrap left", self.counts.scrap[Wiring.SCRAP], 0)
        T.expectRefused(reads.noScrap, "item", "a part was repaired without scrap")
        T.expectRefused(reads.whole, "Tooltip_RenewableEnergy_NoRepairNeeded", "a whole part took a repair")
    end,
})

-- A homemade inverter beside a found one: the two share the load by what each carries, each
-- wasting its own share, both idle, and the homemade one wears by its `wear` share. The hours on
-- make the homemade one's wear a whole point more than the found one's, with a tenth to spare.
local HOMEMADE_INVERTER = "RenewableEnergy.HomemadeInverter"
local HOMEMADE_HOURS = math.ceil(2.1 / (Specs.inverters[HOMEMADE_INVERTER].wear * Specs.partWear.perHour.inverter))
local HOMEMADE_PASSES = math.ceil(HOMEMADE_HOURS / PASS_HOURS)
test("renewable_energy_bank_homemade_inverter_wastes_and_wears_more", {
    run = function(self)
        T.setGrid(self, false)
        local parts = { HOMEMADE_INVERTER, T.POWER_INVERTER }
        for _ = 1, 4 do
            table.insert(parts, T.L16)
        end
        local bank = T.bank(self, "batteryBankMetal", parts)
        if not bank then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.batch(function()
            for _ = 1, HOMEMADE_PASSES do
                T.setCharge(self, bank, 1)
                T.bankPass(self, bank, 0, { hours = HOMEMADE_HOURS / HOMEMADE_PASSES, label = "after" })
            end
        end)
    end,
    validate = function(self)
        local after = self.reads.after
        local status = after.status
        if not expect(status.state == "on" and status.loadW > 0, string.format(
            "the bank isn't carrying a load to share (%s, %.1f W)", tostring(status.state), status.loadW)) then return end
        local homemade, found = Specs.inverters[HOMEMADE_INVERTER], Specs.inverters[T.POWER_INVERTER]
        local carried = homemade.watts + found.watts
        local drawn = homemade.watts / homemade.efficiency + found.watts / found.efficiency
        expectNear("W drawn for the shared load", status.drawW,
            status.loadW * drawn / carried + homemade.idle + found.idle, 0.01)
        local rate = Specs.partWear.perHour.inverter
        local foundLoss = math.floor(rate * HOMEMADE_HOURS)
        local homemadeLoss = math.floor(homemade.wear * rate * HOMEMADE_HOURS)
        expect(homemadeLoss > foundLoss, "the hours on wear the homemade inverter no more whole points than the found one")
        expectEqual("found inverter after " .. HOMEMADE_HOURS .. " hours on", T.stateCondition(after, T.POWER_INVERTER),
            100 - foundLoss)
        expectEqual("homemade inverter after " .. HOMEMADE_HOURS .. " hours on", T.stateCondition(after, HOMEMADE_INVERTER),
            instanceItem(HOMEMADE_INVERTER):getConditionMax() - homemadeLoss)
    end,
})

-- A crafted inverter comes out short of its cap at the recipe's Electricity level: the Makeshift
-- Inverter's 80 less 20.
local MAKESHIFT_RECIPE, MAKESHIFT = "RenewableEnergy_MakeMakeshiftInverter", "RenewableEnergy.MakeshiftInverter"
T.craftTest(T.craftName("bank", MAKESHIFT_RECIPE, "at_recipe_level"), {
    recipe = MAKESHIFT_RECIPE,
    from = Specs.charger,
    prefer = { Specs.charger },
    setup = function(self)
        T.setPerk(self, Perks.Electricity, getScriptManager():getCraftRecipe(MAKESHIFT_RECIPE):getRequiredSkill(0):getLevel())
    end,
    counts = { [MAKESHIFT] = 1 },
    after = function(self) T.readCarried(self, { MAKESHIFT }) end,
    validate = function(self)
        local inverter = T.carriedFirst(self, MAKESHIFT)
        if not expect(inverter ~= nil, "no makeshift inverter was made") then return end
        expectEqual("the condition of an inverter made at the recipe's Electricity level", inverter.condition, 60)
    end,
})

-- Each Electricity level past the recipe's makes up 5 of the shortfall, up to the cap.
test("renewable_energy_bank_crafted_inverter_condition_by_level", {
    run = function(self)
        self.twoPast, self.sevenPast = Wear.craftedInverterCondition(80, 5, 3), Wear.craftedInverterCondition(80, 10, 3)
    end,
    validate = function(self)
        expectEqual("an 80-cap inverter made two levels past the recipe's", self.twoPast, 70)
        expectEqual("an 80-cap inverter made seven levels past the recipe's", self.sevenPast, 80)
    end,
})
