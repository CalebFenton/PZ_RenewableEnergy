require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Debug/RenewableEnergyTestLibArrowBoard"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Items = require "cf_commonlib/Items"

-- Arrow board trailer (ArrowBoard/Trailer.lua, Vehicles.txt): stock and its rolls, panels, repair
-- and frame. Its battery box, power and crashes are in RenewableEnergyTestsArrowBoard*.lua.
-- Authority state goes through RenewableEnergyTestServerTrailer.lua; player actions go through
-- the vanilla and mod actions, checked on this client's copy.

local T = RenewableEnergyTest
local test, expect, expectEqual, expectNear, player = T.test, T.expect, T.expectEqual, T.expectNear, T.player
local spawnTrailer, batchOnTrailer, waitForPanelsCopy, standIn = T.spawnTrailer, T.batchOnTrailer, T.waitForPanelsCopy, T.standIn
local panelCondition, panelShown, boxItems, modulesOnBothPanels = T.panelCondition, T.panelShown, T.boxItems, T.modulesOnBothPanels
local LEFT, RIGHT = T.BOARD_PANELS[1], T.BOARD_PANELS[2]

-- Expects `state`'s panels at a found trailer's conditions (`ranges` from worldSpawnStock): the
-- first weathered, the second weathered or cracked. Returns both conditions.
local function expectStockConditions(state, ranges, what)
    local left, right = panelCondition(state, LEFT), panelCondition(state, RIGHT)
    expect(left and T.inRange(left, ranges.weathered), what .. "'s left panel's module is at " .. tostring(left))
    expect(right and (T.inRange(right, ranges.weathered) or T.inRange(right, ranges.cracked)),
        what .. "'s right panel's module is at " .. tostring(right))
    return left, right
end

-- The model a panel shows for each look of ModuleRepair.crackLookOf.
local MODEL_OF_LOOK = { light = "LightCracked", heavy = "Cracked" }

-- The model a panel holding a module at `condition` (nil: none) shows.
local function modelFor(condition)
    if not condition then
        return ""
    end
    local look = ModuleRepair.crackLookOf(T.FACTORY_MODULE, condition)
    return look and MODEL_OF_LOOK[look] or "Whole"
end

-- A found arrow board: a module on each panel at found conditions, each showing its model, to
-- players too; a box of stock batteries in the stock count, no modules, at most one controller.
test("renewable_energy_world_arrow_board_spawns_stocked", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        if not spawnTrailer(self, { stocked = true }) then return end
        T.onVehicle(self, self.trailer, "vehicleState")
        T.read(self, "worldSpawnStock", { names = {} }, "ranges")
        waitForPanelsCopy(self, self.trailer)
    end,
    validate = function(self)
        local stock = RenewableEnergy.ArrowBoard.STOCK
        local state = self.trailer.state
        local left, right = expectStockConditions(state, self.reads.ranges, "the found trailer")
        for id, condition in pairs({ [LEFT] = left, [RIGHT] = right }) do
            expectEqual("the model " .. id .. " at " .. tostring(condition) .. " shows", panelShown(state, id), modelFor(condition))
        end
        if not expect(state.box ~= nil, "the arrow board has no battery box") then
            return
        end
        expectEqual("modules in the battery box", #boxItems(state, T.FACTORY_MODULE), 0)
        local wear = self.reads.ranges.batteryWear[stock.batteryWear]
        local worn = { min = wear.mean - wear.halfWidth, max = math.min(100, wear.mean + wear.halfWidth) }
        local batteries, charges = 0, {}
        for _, item in ipairs(boxItems(state)) do
            if item.charge then
                batteries = batteries + 1
                table.insert(charges, item.charge)
                expect(T.inRange(item.condition, worn), "a battery in the box is at " .. item.condition .. "%")
            end
        end
        expect(batteries >= stock.batteries.min and batteries <= stock.batteries.max,
            string.format("%d batteries in the battery box, expected %d to %d", batteries, stock.batteries.min, stock.batteries.max))
        expectEqual("stock batteries in the battery box", #boxItems(state, stock.battery), batteries)
        T.expectFoundCharges(charges, "the battery box")
        local controllers = #boxItems(state, RenewableEnergy.Specs.controller)
        expect(controllers <= 1, "the battery box has " .. controllers .. " charge controllers")
    end,
})

-- A plain spawn (debug tools, vehicle stories) sets every part's condition after stocking; the
-- panels keep their stock conditions and models, to players too.
test("renewable_energy_world_arrow_board_plain_spawn_keeps_stock", {
    sandbox = { LRMSolarPanels = 1 },
    run = function(self)
        if not spawnTrailer(self, { recordStock = true }) then return end
        local trailer = self.trailer
        T.readUntil(self, "arrowBoardStock", function() return T.vehicleArgs(trailer) end, "stock", function(reply)
            return panelCondition(reply.state, LEFT) == reply.stock[LEFT] and panelCondition(reply.state, RIGHT) == reply.stock[RIGHT]
        end)
        T.step(function() trailer.state = self.reads.stock.state end)
        waitForPanelsCopy(self, trailer)
    end,
    validate = function(self)
        local stock, state = self.reads.stock.stock, self.trailer.state
        for _, id in ipairs(T.BOARD_PANELS) do
            local condition = panelCondition(state, id)
            expect(stock[id] ~= nil, id .. " was stocked with no module")
            expectEqual(id .. "'s condition", condition, stock[id])
            expectEqual("the model " .. id .. " at " .. tostring(condition) .. " shows", panelShown(state, id), modelFor(condition))
        end
    end,
})

-- A trailer saved before panels were parts gets its modules on first load only: panels taken
-- off later stay off.
test("renewable_energy_world_arrow_board_old_trailer_gets_panels_once", {
    sandbox = { LRMSolarPanels = 1 },
    run = function(self)
        if not spawnTrailer(self) then return end
        T.onVehicle(self, self.trailer, "arrowBoardOldPanels", nil, "old")
        T.step(function() self.trailer.state = self.reads.old.second end)
        T.read(self, "worldSpawnStock", { names = {} }, "ranges")
        waitForPanelsCopy(self, self.trailer)
    end,
    validate = function(self)
        local first, second = self.reads.old.first, self.reads.old.second
        expectStockConditions(first, self.reads.ranges, "the old trailer")
        expect(panelCondition(second, LEFT) == nil and panelCondition(second, RIGHT) == nil,
            "panels taken off came back on the next load")
        expect(panelShown(second, LEFT) == "" and panelShown(second, RIGHT) == "",
            "empty panels show " .. panelShown(second, LEFT) .. " and " .. panelShown(second, RIGHT))
    end,
})

-- A found trailer's switch is on for a roll under STOCK.switchedOnChance and off for one at it;
-- a trailer with its switch set keeps it, whatever the roll.
test("renewable_energy_world_arrow_board_found_switch_follows_its_chance", {
    run = function(self)
        if not spawnTrailer(self) then return end
        T.onVehicle(self, self.trailer, "arrowBoardSwitchRolls", { trials = { { roll = "under" }, { roll = "at" },
            { was = false, roll = 0 } } }, "rolls")
    end,
    validate = function(self)
        local on = self.reads.rolls.on
        expect(on[1] == true, "a roll just under the switch's chance left a found trailer off")
        expect(on[2] == false, "a roll at the switch's chance switched a found trailer on")
        expect(on[3] == false, "stocking switched on a trailer already switched off")
    end,
})

-- Queues setting the character's skills to those the trailer's `partId` lists for `job`
-- ("install"/"uninstall").
local function setPartSkills(self, trailer, partId, job)
    T.step(function()
        for name, level in trailer.vehicle:getPartById(partId):getTable(job).skills:gmatch("(%w+):(%d+)") do
            T.setPerk(self, Perks.FromString(name), tonumber(level))
        end
    end)
end

-- With the mechanics window's way, a cracked panel comes off as its module at the panel's
-- condition, leaving nothing shown; a module put on shows whole or cracked by its condition
-- (Specs.crackLooks), to players too.
test("renewable_energy_world_arrow_board_panels_come_off_and_go_on", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer, p = self.trailer, player()
        local looks = RenewableEnergy.Specs.crackLooks
        self.offAt, self.onAt = T.conditionAt(T.FACTORY_MODULE, looks.heavyBelow) - 1, T.conditionAt(T.FACTORY_MODULE, looks.lightBelow)
        setPartSkills(self, trailer, LEFT, "uninstall")
        if isClient() then
            T.setMechanicsCheat(self, true)
        end
        T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = T.FACTORY_MODULE, condition = self.offAt } } },
            "cracked")
        waitForPanelsCopy(self, trailer)
        T.give(self, "wrench", { { type = "Base.Wrench", equip = "primary" } })
        T.step(function()
            ISTimedActionQueue.add(ISUninstallVehiclePart:new(p, trailer.vehicle:getPartById(LEFT), 200))
        end)
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) == nil end, "emptied")
        waitForPanelsCopy(self, trailer)
        T.waitForCarried(self, T.FACTORY_MODULE, "this client's copy of the module taken off")
        T.step(function() self.removed = T.carried(T.FACTORY_MODULE):getCondition() end)
        T.give(self, "module", { { type = T.FACTORY_MODULE, condition = self.onAt } })
        T.step(function()
            ISTimedActionQueue.add(ISInstallVehiclePart:new(p, trailer.vehicle:getPartById(LEFT), self.items.module[1], 200))
            T.shortenQueuedInstalls()
        end)
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= nil end)
        waitForPanelsCopy(self, trailer)
    end,
    validate = function(self)
        local state, cracked, emptied = self.trailer.state, self.reads.cracked.state, self.reads.emptied.state
        expectEqual("the model a panel at " .. self.offAt .. " shows", panelShown(cracked, LEFT), "Cracked")
        expectEqual("the condition of the module taken off", self.removed, self.offAt)
        expectEqual("the server's emptied panel's condition", panelCondition(emptied, LEFT), nil)
        expectEqual("the model the server's emptied panel shows", panelShown(emptied, LEFT), "")
        expectEqual("the condition the module went on at", panelCondition(state, LEFT), self.onAt)
        expectEqual("the model a panel at " .. self.onAt .. " shows", panelShown(state, LEFT), "Whole")
    end,
})

-- A crack, from a storm or a crash, takes as much from a panel's module as a storm takes from a
-- module on a mount, and shows it cracked, to players too: a new module's first crack light, one
-- that takes a module under half its max heavy; a storm cracks a trailer's panels as it would
-- flat panels.
test("renewable_energy_world_arrow_board_panels_crack", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        local Specs = RenewableEnergy.Specs
        self.whole = Items.conditionMaxOf(T.FACTORY_MODULE)
        -- Half a crack above the heavy look, so a crack takes it below.
        self.light = T.conditionAt(T.FACTORY_MODULE, Specs.crackLooks.heavyBelow) + math.floor(Specs.storm.crack / 2)
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = T.FACTORY_MODULE, condition = self.whole },
                [RIGHT] = { type = T.FACTORY_MODULE, condition = self.light } } })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "crackPanel", part = LEFT })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "crackPanel", part = RIGHT }, "crack")
        end)
        waitForPanelsCopy(self, trailer)
        -- The lowest rolls for each panel: a storm cracks both, rolling for each crack and for the
        -- module it cracks.
        T.forceRoll(self, { 0, 0, 0, 0 })
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { panels = modulesOnBothPanels(100) })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "stormCrack", with = { 1 } }, "storm")
        end)
        T.step(function() T.setSandbox(self, "StormDamage", false) end)
        T.onVehicle(self, trailer, "arrowBoardRun", { call = "stormCrack", with = { 1 } }, "calm")
    end,
    validate = function(self)
        local crack, cracked = RenewableEnergy.Specs.storm.crack, self.reads.crack.state
        local left, right = panelCondition(cracked, LEFT), panelCondition(cracked, RIGHT)
        expectEqual("the condition a crack left the panel at " .. self.whole .. " at", left, self.whole - crack)
        expectEqual("the model the new panel cracked to " .. tostring(left) .. " shows", panelShown(cracked, LEFT), "LightCracked")
        expectEqual("the condition a crack left the panel at " .. self.light .. " at", right, self.light - crack)
        expectEqual("the model the panel cracked to " .. tostring(right) .. " shows", panelShown(cracked, RIGHT), "Cracked")
        expectEqual("panels a storm on the lowest rolls cracked", self.reads.storm.result, 2)
        local state = self.reads.storm.state
        expectEqual("the storm's left panel's condition", panelCondition(state, LEFT), 100 - crack)
        expectEqual("the storm's right panel's condition", panelCondition(state, RIGHT), 100 - crack)
        expectEqual("panels a storm cracked with storm damage off", self.reads.calm.result, 0)
    end,
})

-- Queues a Seal Cracked Panel on the trailer's left panel, as the trailer's menu queues it.
local function sealPanel(trailer)
    T.step(function()
        ISTimedActionQueue.add(RenewableEnergyAction:new(player(), "vehicle", RenewableEnergy.VehicleJobs.SEAL_PANEL,
            trailer.vehicle, LEFT))
    end)
end

-- Sets the character's skills to Seal Cracked Module's required levels.
local function setSealSkills(self)
    T.setRecipeSkills(self, ModuleRepair.sealRecipe())
end

-- The uses of epoxy Seal Cracked Module takes.
local function sealEpoxyUses()
    local inputs = ModuleRepair.sealRecipe():getInputs()
    local epoxy = getScriptManager():FindItem("Base.Epoxy")
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if input:containsItem(epoxy) then
            return math.ceil(input:getIntAmount() * input:getRelativeScale("Base.Epoxy"))
        end
    end
    return 0
end

-- What the trailer's menu shows of Seal Cracked Panel for its left panel (T.optionState): the
-- trailer may hold a cracked right panel too.
local function sealPanelOption(vehicle)
    local context = T.newContext()
    RenewableEnergy.VehicleMenu.addSealPanelOptions(0, context, vehicle)
    local shown = T.optionState(T.findIn(context.options, "param4", LEFT))
    context:closeAll()
    return shown
end

-- Seal Cracked Panel takes Seal Cracked Module's inputs (keeping the screwdriver), skill and XP,
-- and seals the module, sealed `repaired` times before, from `from(cap)` by ModuleRepair.SEAL_ADDS
-- up to its cap, still cracked, counting the seal; an uncracked module can't be sealed. The sealed
-- panel keeps its option, greyed out saying to reglaze it once a seal can't bring it further.
local function repairTest(name, repaired, fromBelowCap)
    test(name, {
        instant = true,
        run = function(self)
            if not spawnTrailer(self) then return end
            local trailer = self.trailer
            self.from = fromBelowCap(T.sealCap(T.FACTORY_MODULE, repaired))
            self.to = math.min(T.sealCap(T.FACTORY_MODULE, repaired), self.from + ModuleRepair.SEAL_ADDS)
            self.epoxyNeeded = sealEpoxyUses()
            setSealSkills(self)
            self.wholeAt = T.conditionAt(T.FACTORY_MODULE, RenewableEnergy.Specs.crackLooks.lightBelow)
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = T.FACTORY_MODULE, condition = self.wholeAt } } })
            waitForPanelsCopy(self, trailer)
            T.step(function() self.wholeRepairable = RenewableEnergy.ArrowBoard.sealablePanel(trailer.vehicle, LEFT) ~= nil end)
            T.onVehicle(self, trailer, "setTrailer",
                { panels = { [LEFT] = { type = T.FACTORY_MODULE, condition = self.from, repaired = repaired } } })
            waitForPanelsCopy(self, trailer)
            T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" } })
            -- Read the authority's XP: a client's copy may still be getting the last test's.
            T.read(self, "character", { perks = { "Electricity" } }, "before")
            T.step(function() self.epoxyUses = self.items.inputs[2]:getCurrentUses() end)
            sealPanel(trailer)
            T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= self.from end)
            T.count(self, "left", { "Base.Screwdriver", "Base.Epoxy" })
            T.read(self, "character", { perks = { "Electricity" } }, "after")
            -- What CraftRecipe.addXP gives this character for the recipe's xpAward.
            T.read(self, "electricityAward", { xp = ModuleRepair.sealRecipe():getXPAward(0):getAmount() }, "award")
            waitForPanelsCopy(self, trailer)
            T.step(function() self.after = sealPanelOption(trailer.vehicle) end)
        end,
        validate = function(self)
            local left, from, to = self.counts.left, self.from, self.to
            local condition = panelCondition(self.trailer.state, LEFT)
            expect(not self.wholeRepairable, "a panel at " .. self.wholeAt .. ", not cracked, can be sealed")
            expectEqual("the condition the seal took the panel at " .. from .. " to", condition, to)
            expect(panelShown(self.trailer.state, LEFT) ~= "Whole", "the sealed panel at " .. tostring(condition) .. " shows whole")
            expectEqual("the sealed panel's seal count", self.trailer.state.panels[LEFT].repaired, repaired + 1)
            local fully = to >= T.sealCap(T.FACTORY_MODULE, repaired + 1)
            expect(self.after.shown and self.after.greyed == fully
                and (not fully or self.after.reason == getText("Tooltip_RenewableEnergy_PanelSealedFully")),
                "the sealed panel at " .. tostring(condition) .. (fully and ", sealed as far as it goes," or "")
                .. " shows Seal Cracked Panel " .. (self.after.shown and (self.after.greyed and "greyed out" or "offered") or "not at all")
                .. " (" .. tostring(self.after.reason) .. ")")
            expect(left["Base.Screwdriver"] == 1, "the seal used up the screwdriver")
            local epoxy = T.carried("Base.Epoxy")
            expectEqual("epoxy uses left of " .. self.epoxyUses .. " (the seal takes " .. self.epoxyNeeded .. ")",
                epoxy and epoxy:getCurrentUses() or 0, self.epoxyUses - self.epoxyNeeded)
            local gainedXp = self.reads.after.xp.Electricity - self.reads.before.xp.Electricity
            expect(gainedXp > 0, "the repair gave no Electricity XP")
            expectNear("Electricity XP from the repair", gainedXp, self.reads.award.gained, 0.01)
        end,
    })
end
-- One seal short of the cap, one under it, and one under a twice-sealed module's lower cap.
repairTest("renewable_energy_world_arrow_board_repair_mends_a_cracked_panel", 0,
    function(cap) return cap - ModuleRepair.SEAL_ADDS - 1 end)
repairTest("renewable_energy_world_arrow_board_repair_stops_at_its_cap", 0, function(cap) return cap - 1 end)
repairTest("renewable_energy_world_arrow_board_repair_after_two_seals_stops_lower", 2, function(cap) return cap - 1 end)

-- The menu offers Seal Cracked Panel to a character with everything it needs, and greys it out
-- in the dark, saying why, as the action's light rule refuses it
-- (RenewableEnergyAction.needsLight).
test("renewable_energy_world_arrow_board_repair_needs_light", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        setSealSkills(self)
        T.onVehicle(self, trailer, "setTrailer",
            { panels = { [LEFT] = { type = T.FACTORY_MODULE, condition = T.sealCap(T.FACTORY_MODULE, 0) - 1 } } })
        waitForPanelsCopy(self, trailer)
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" } })
        T.step(function() self.lit = sealPanelOption(trailer.vehicle) end)
        -- T.makeDark sets the clock when called, so it runs in a step.
        T.step(function() T.makeDark(self) end)
        T.step(function() self.dark = sealPanelOption(trailer.vehicle) end)
    end,
    validate = function(self)
        expect(self.lit.shown and not self.lit.greyed, "in daylight with every input the repair isn't offered")
        expect(self.dark.greyed, "in the dark the repair isn't greyed out")
        expect(tostring(self.dark.reason):find(getText("Tooltip_RenewableEnergy_TooDark"), 1, true) ~= nil,
            "in the dark the repair's tooltip says '" .. tostring(self.dark.reason) .. "'")
    end,
})

-- ArrowBoard.FRAME's front and back ids, copied for the reason T.lidOf gives.
local FRAME_FRONT, FRAME_BACK = "EngineDoor", "TruckBed"

local function frameCondition(state, partId)
    local part = state and state.frame[partId]
    return part and part.installed and part.condition or nil
end

-- A trailer from a save made before its frame was parts loads with them empty and the random
-- colour it spawned with, and gets a frame and the script's colour on that load.
test("renewable_energy_world_arrow_board_old_trailer_gets_frame", {
    run = function(self)
        if not spawnTrailer(self) then return end
        T.onVehicle(self, self.trailer, "arrowBoardOldFrame", { hsv = { 0.3, 0.9, 0.8 } }, "old")
    end,
    validate = function(self)
        local answer = self.reads.old
        for _, frame in ipairs(RenewableEnergy.ArrowBoard.FRAME) do
            expect(frameCondition(answer.state, frame.id) ~= nil, "the old trailer's " .. frame.id .. " loaded empty")
        end
        expect(answer.state.colorSat == answer.forcedSat and answer.state.colorVal == answer.forcedVal,
            string.format("the old trailer kept its colour, saturation %.2f and value %.2f", answer.state.colorSat, answer.state.colorVal))
    end,
})

-- Repair Frame offers each dented end of the frame, and the sheet metal fix it offers, vanilla's
-- welding, walks there and welds it whole at high skill; a whole frame offers nothing.
test("renewable_energy_world_arrow_board_frame_welds", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        T.setPerk(self, Perks.MetalWelding, 10)
        T.setPerk(self, Perks.Mechanics, 10)
        T.onVehicle(self, trailer, "setTrailer", { frame = { [FRAME_FRONT] = 20, [FRAME_BACK] = 45 } })
        T.waitForVehicleCopy(self, trailer, function(copy)
            return frameCondition(copy, FRAME_FRONT) == 20 and frameCondition(copy, FRAME_BACK) == 45
        end, "this client's copy of the dented frame")
        -- A spare sheet metal: on a multiplayer client vanilla's fix action checks for the sheet
        -- metal (ISFixVehiclePartAction.isValid) after the server's weld has taken the last one,
        -- and stops, which empties the queue and drops the test's later steps. The weld itself
        -- has happened on the server.
        T.give(self, "tools", { { type = "Base.BlowTorch" }, { type = "Base.SheetMetal", count = 3 } })
        self.labels = {}
        -- The frame's options, and the first fix under each.
        local function frameOptions()
            local context = T.newContext()
            RenewableEnergy.VehicleMenu.addFrameRepairOptions(0, context, trailer.vehicle)
            local found = {}
            for _, option in ipairs(context.options) do
                local submenu = T.subMenu(context, option)
                table.insert(found, { name = option.name, fix = submenu and submenu.options[1] })
            end
            return found
        end
        local function weld(option, area)
            standIn(trailer.vehicle, area)
            T.choose(option.fix)
        end
        T.step(function()
            local offered = frameOptions()
            for _, option in ipairs(offered) do
                table.insert(self.labels, option.name)
            end
            if not T.need(self, #offered == 2 and offered[1].fix and offered[2].fix or nil, "a fix under each frame option") then
                return
            end
            weld(offered[1], "Engine")
            T.awaitVehicleState(self, trailer, function(state) return frameCondition(state, FRAME_FRONT) == 100 end)
            T.waitForVehicleCopy(self, trailer, function(copy) return frameCondition(copy, FRAME_FRONT) == 100 end,
                "this client's copy of the welded front")
            T.step(function()
                weld(frameOptions()[1], "TruckBed")
                T.awaitVehicleState(self, trailer, function(state) return frameCondition(state, FRAME_BACK) == 100 end)
                T.waitForVehicleCopy(self, trailer, function(copy) return frameCondition(copy, FRAME_BACK) == 100 end,
                    "this client's copy of the welded back")
                T.count(self, "left", { "Base.SheetMetal" })
                T.step(function()
                    self.afterRepair = #frameOptions()
                end)
            end)
        end)
    end,
    validate = function(self)
        local front = getText("ContextMenu_RenewableEnergy_RepairFrame", getText("IGUI_RenewableEnergy_FrameFront"), "20%")
        local back = getText("ContextMenu_RenewableEnergy_RepairFrame", getText("IGUI_RenewableEnergy_FrameBack"), "45%")
        expect(self.labels[1] == front and self.labels[2] == back, "the menu offered " .. table.concat(self.labels, ", "))
        local state = self.trailer.state
        expectEqual("the welded front's condition", frameCondition(state, FRAME_FRONT), 100)
        expectEqual("the welded back's condition", frameCondition(state, FRAME_BACK), 100)
        local left = self.counts.left["Base.SheetMetal"]
        expect(left < 3, "welding took none of the 3 sheet metal")
        expectEqual("repairs a whole frame offers", self.afterRepair, 0)
    end,
})

-- A new trailer's lid is padlocked on a roll just under STOCK.lockedChance and not on one at it,
-- whatever it was before; with the game's Easy Use option it is left unlocked even on the lowest roll.
test("renewable_energy_world_arrow_board_lid_lock_roll", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        T.onVehicle(self, self.trailer, "arrowBoardLidRolls", { trials = {
            { was = false, roll = "under" }, { was = true, roll = "at" }, { was = true, roll = 0, easyUse = true },
        } }, "rolls")
    end,
    validate = function(self)
        local locked = self.reads.rolls.locked
        expect(locked[1] == true, "a roll just under the locked chance left the lid unlocked")
        expect(locked[2] == false, "a roll at the locked chance left the lid locked")
        expect(locked[3] == false, "with Easy Use the lowest roll left the lid locked")
    end,
})

-- A new trailer's second panel gets a cracked module on a roll just under STOCK.secondCrackedChance
-- and a weathered one at it; the first panel's is weathered either way.
test("renewable_energy_world_arrow_board_second_panel_cracked_roll", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        T.onVehicle(self, self.trailer, "arrowBoardPanelStockRolls", { rolls = { "under", "at" } }, "rolls")
    end,
    validate = function(self)
        local answer = self.reads.rolls
        local under, at = answer.stocked[1], answer.stocked[2]
        for label, stocked in pairs({ ["just under the chance"] = under, ["at the chance"] = at }) do
            expect(T.inRange(stocked[LEFT], answer.weathered), "on a roll " .. label .. " the left module is at " .. tostring(stocked[LEFT]))
        end
        expect(T.inRange(under[RIGHT], answer.cracked), "on a roll just under the chance the right module is at " .. tostring(under[RIGHT]))
        expect(T.inRange(at[RIGHT], answer.weathered), "on a roll at the chance the right module is at " .. tostring(at[RIGHT]))
    end,
})

-- A found battery box holds a charge controller on a roll just under STOCK.controllerChance × the
-- Misc loot option and none at it.
test("renewable_energy_world_arrow_board_box_controller_roll", {
    run = function(self)
        T.read(self, "arrowBoardControllerRolls", { trials = {
            { misc = 1, roll = "under" }, { misc = 1, roll = "at" }, { misc = 0.5, roll = "under" }, { misc = 0.5, roll = "at" },
        } }, "rolls")
    end,
    validate = function(self)
        local controllers = self.reads.rolls.controllers
        for i, misc in ipairs({ 1, 1, 0.5, 0.5 }) do
            local wanted = i % 2 == 1 and 1 or 0
            expectEqual(string.format("controllers at Misc %s from a roll %s the chance", misc, wanted == 1 and "just under" or "at"),
                controllers[i], wanted)
        end
    end,
})
