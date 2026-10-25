require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Debug/RenewableEnergyTestLibArrowBoard"

-- Arrow board trailer (World/ArrowBoard.lua, Vehicles.txt): stock and its rolls, panels, repair
-- and frame. Its battery box, power and crashes are in RenewableEnergyTestsArrowBoard*.lua.
-- Authority state goes through RenewableEnergyTestServerTrailer.lua; player actions go through
-- the vanilla and mod actions, checked on this client's copy.

local T = RenewableEnergyTest
local test, expect, expectNear, player = T.test, T.expect, T.expectNear, T.player
local spawnTrailer, batchOnTrailer, waitForPanelsCopy, standIn = T.spawnTrailer, T.batchOnTrailer, T.waitForPanelsCopy, T.standIn
local panelCondition, panelShown, boxItems, modulesOnBothPanels = T.panelCondition, T.panelShown, T.boxItems, T.modulesOnBothPanels
local LEFT, RIGHT = T.BOARD_PANELS[1], T.BOARD_PANELS[2]

local MODULE = RenewableEnergy.Specs.factoryModule

-- Queues reading WorldSpawns' module conditions (authority only) into self.server.worldSpawnStock.
local function readStockRanges(self)
    T.server(self, "worldSpawnStock", { names = {} })
end

-- Expects `state`'s panels at a found trailer's conditions (`ranges` from worldSpawnStock): the
-- first weathered, the second weathered or cracked. Returns both conditions.
local function expectStockConditions(state, ranges, what)
    local left, right = panelCondition(state, LEFT), panelCondition(state, RIGHT)
    expect(left and T.inRange(left, ranges.weathered), what .. "'s left panel's module is at " .. tostring(left))
    expect(right and (T.inRange(right, ranges.weathered) or T.inRange(right, ranges.cracked)),
        what .. "'s right panel's module is at " .. tostring(right))
    return left, right
end

-- The model a panel shows for each look of RenewableEnergy.crackLookOf.
local MODEL_OF_LOOK = { light = "LightCracked", heavy = "Cracked" }

-- The model a panel holding a module at `condition` (nil: none) shows.
local function modelFor(condition)
    if not condition then
        return ""
    end
    local look = RenewableEnergy.crackLookOf(MODULE, condition)
    return look and MODEL_OF_LOOK[look] or "Whole"
end

-- A found arrow board: a module on each panel at found conditions, each showing its model, to
-- players too; a box of stock batteries in the stock count, no modules, at most one controller.
test("renewable_energy_world_arrow_board_spawns_stocked", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        if not spawnTrailer(self, { stocked = true }) then return end
        T.vehicleState(self, self.trailer)
        readStockRanges(self)
        waitForPanelsCopy(self, self.trailer)
    end,
    validate = function(self)
        local stock = RenewableEnergy.ArrowBoard.STOCK
        local state = self.trailer.state
        local left, right = expectStockConditions(state, self.server.worldSpawnStock, "the found trailer")
        for id, condition in pairs({ [LEFT] = left, [RIGHT] = right }) do
            expect(panelShown(state, id) == modelFor(condition), id .. " at " .. tostring(condition) .. " shows "
                .. panelShown(state, id))
        end
        if not expect(state.box ~= nil, "the arrow board has no battery box") then
            return
        end
        expect(#boxItems(state, MODULE) == 0, #boxItems(state, MODULE) .. " modules in the battery box")
        local batteries, charges = 0, {}
        for _, item in ipairs(boxItems(state)) do
            if item.charge then
                batteries = batteries + 1
                table.insert(charges, item.charge)
                expect(T.inRange(item.condition, stock.batteryCondition), "a battery in the box is at " .. item.condition .. "%")
            end
        end
        expect(batteries >= stock.batteries.min and batteries <= stock.batteries.max,
            string.format("%d batteries in the battery box, expected %d to %d", batteries, stock.batteries.min, stock.batteries.max))
        expect(#boxItems(state, stock.battery) == batteries, "the battery box holds other batteries")
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
        T.serverUntil(self, "arrowBoardStock", function() return T.vehicleArgs(trailer) end, function(reply)
            return panelCondition(reply.state, LEFT) == reply.stock[LEFT] and panelCondition(reply.state, RIGHT) == reply.stock[RIGHT]
        end)
        T.step(function()
            trailer.answer = self.server.arrowBoardStock
            trailer.state = trailer.answer.state
        end)
        waitForPanelsCopy(self, trailer)
    end,
    validate = function(self)
        local stock, state = self.trailer.answer.stock, self.trailer.state
        for _, id in ipairs(T.BOARD_PANELS) do
            local condition = panelCondition(state, id)
            expect(stock[id] ~= nil and condition == stock[id],
                id .. " was stocked at " .. tostring(stock[id]) .. " and is at " .. tostring(condition))
            expect(panelShown(state, id) == modelFor(condition), id .. " at " .. tostring(condition) .. " shows '"
                .. panelShown(state, id) .. "'")
        end
    end,
})

-- A trailer saved before panels were parts gets its modules on first load only: panels taken
-- off later stay off.
test("renewable_energy_world_arrow_board_old_trailer_gets_panels_once", {
    sandbox = { LRMSolarPanels = 1 },
    run = function(self)
        if not spawnTrailer(self) then return end
        T.onVehicle(self, self.trailer, "arrowBoardOldPanels")
        T.step(function() self.trailer.state = self.trailer.answer.second end)
        readStockRanges(self)
        waitForPanelsCopy(self, self.trailer)
    end,
    validate = function(self)
        local first, second = self.trailer.answer.first, self.trailer.answer.second
        expectStockConditions(first, self.server.worldSpawnStock, "the old trailer")
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
            { was = false, roll = 0 } } })
    end,
    validate = function(self)
        local on = self.trailer.answer.on
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
        self.offAt, self.onAt = T.conditionAt(MODULE, looks.heavyBelow) - 1, T.conditionAt(MODULE, looks.lightBelow)
        setPartSkills(self, trailer, LEFT, "uninstall")
        if isClient() then
            T.setMechanicsCheat(self, true)
        end
        T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = self.offAt } } })
        waitForPanelsCopy(self, trailer)
        T.give(self, "wrench", { { type = "Base.Wrench", equip = "primary" } })
        T.step(function()
            self.cracked = trailer.state
            ISTimedActionQueue.add(ISUninstallVehiclePart:new(p, trailer.vehicle:getPartById(LEFT), 200))
        end)
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) == nil end)
        waitForPanelsCopy(self, trailer)
        T.waitForCarried(self, MODULE, "this client's copy of the module taken off")
        T.step(function()
            self.emptied = trailer.state
            self.removed = T.carried(MODULE):getCondition()
        end)
        T.give(self, "module", { { type = MODULE, condition = self.onAt } })
        T.step(function()
            ISTimedActionQueue.add(ISInstallVehiclePart:new(p, trailer.vehicle:getPartById(LEFT), self.items.module[1], 200))
            T.shortenQueuedInstalls()
        end)
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= nil end)
        waitForPanelsCopy(self, trailer)
    end,
    validate = function(self)
        local state = self.trailer.state
        expect(panelShown(self.cracked, LEFT) == "Cracked", "a panel at " .. self.offAt .. " shows " .. panelShown(self.cracked, LEFT))
        expect(self.removed == self.offAt, "the panel at " .. self.offAt .. " came off as " .. self.removed .. "%")
        expect(panelCondition(self.emptied, LEFT) == nil and panelShown(self.emptied, LEFT) == "",
            "after taking it off the server's panel is at " .. tostring(panelCondition(self.emptied, LEFT)) .. " showing '"
            .. panelShown(self.emptied, LEFT) .. "'")
        expect(panelCondition(state, LEFT) == self.onAt, "the module went on at " .. tostring(panelCondition(state, LEFT)))
        expect(panelShown(state, LEFT) == "Whole", "a panel at " .. self.onAt .. " shows " .. panelShown(state, LEFT))
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
        self.whole = RenewableEnergy.conditionMaxOf(MODULE)
        -- Half a crack above the heavy look, so a crack takes it below.
        self.light = T.conditionAt(MODULE, Specs.crackLooks.heavyBelow) + math.floor(Specs.storm.crack / 2)
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = self.whole },
                [RIGHT] = { type = MODULE, condition = self.light } } })
            T.onVehicle(self, trailer, "arrowBoardCrack", { part = LEFT })
            T.onVehicle(self, trailer, "arrowBoardCrack", { part = RIGHT })
        end)
        waitForPanelsCopy(self, trailer)
        T.step(function() self.crack = trailer.state end)
        -- The lowest rolls for each panel: a storm cracks both, rolling for each crack and for the
        -- module it cracks.
        T.forceRoll(self, { 0, 0, 0, 0 })
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { panels = modulesOnBothPanels(100) })
            T.onVehicle(self, trailer, "arrowBoardStorm", { hours = 1 })
        end)
        T.step(function()
            self.storm = trailer.answer
            T.setSandbox(self, "StormDamage", false)
        end)
        T.onVehicle(self, trailer, "arrowBoardStorm", { hours = 1 })
        T.step(function() self.calm = trailer.answer end)
    end,
    validate = function(self)
        local crack = RenewableEnergy.Specs.storm.crack
        local left, right = panelCondition(self.crack, LEFT), panelCondition(self.crack, RIGHT)
        expect(left == self.whole - crack, "a crack left the panel at " .. self.whole .. " at " .. tostring(left))
        expect(panelShown(self.crack, LEFT) == "LightCracked", "the new panel cracked to " .. tostring(left) .. " shows "
            .. panelShown(self.crack, LEFT))
        expect(right == self.light - crack, "a crack left the panel at " .. self.light .. " at " .. tostring(right))
        expect(panelShown(self.crack, RIGHT) == "Cracked", "the panel cracked to " .. tostring(right) .. " shows "
            .. panelShown(self.crack, RIGHT))
        expect(self.storm.cracked == 2, "a storm on the lowest rolls cracked " .. self.storm.cracked .. " panels, not both")
        local state = self.storm.state
        expect(panelCondition(state, LEFT) == 100 - crack and panelCondition(state, RIGHT) == 100 - crack,
            "the storm left the panels at " .. tostring(panelCondition(state, LEFT)) .. " and " .. tostring(panelCondition(state, RIGHT)))
        expect(self.calm.cracked == 0, "a storm cracked panels with storm damage off")
    end,
})

-- Queues a Seal Cracked Panel on the trailer's left panel, as the trailer's menu queues it.
local function sealPanel(trailer)
    T.step(function()
        ISTimedActionQueue.add(RenewableEnergyAction:new(player(), RenewableEnergyAction.SEAL_PANEL, nil, nil, trailer.vehicle,
            nil, nil, LEFT))
    end)
end

-- Sets the character's skills to Seal Cracked Module's required levels.
local function setSealSkills(self)
    T.setRecipeSkills(self, RenewableEnergy.Recipes.moduleRepairRecipe())
end

-- The uses of epoxy Seal Cracked Module takes.
local function sealEpoxyUses()
    local inputs = RenewableEnergy.Recipes.moduleRepairRecipe():getInputs()
    local epoxy = getScriptManager():FindItem("Base.Epoxy")
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if input:containsItem(epoxy) then
            return math.ceil(input:getIntAmount() * input:getRelativeScale("Base.Epoxy"))
        end
    end
    return 0
end

-- Seal Cracked Panel takes Seal Cracked Module's inputs (keeping the screwdriver), skill and XP,
-- and seals the module, sealed `repaired` times before, from `from(cap)` by Recipes.MODULE_REPAIR
-- up to its cap, still cracked, counting the seal; an uncracked module can't be sealed.
local function repairTest(name, repaired, fromBelowCap)
    test(name, {
        instant = true,
        run = function(self)
            if not spawnTrailer(self) then return end
            local trailer = self.trailer
            self.from = fromBelowCap(T.sealCap(MODULE, repaired))
            self.to = math.min(T.sealCap(MODULE, repaired), self.from + RenewableEnergy.Recipes.MODULE_REPAIR)
            self.epoxyNeeded = sealEpoxyUses()
            setSealSkills(self)
            self.wholeAt = T.conditionAt(MODULE, RenewableEnergy.Specs.crackLooks.lightBelow)
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = self.wholeAt } } })
            waitForPanelsCopy(self, trailer)
            T.step(function() self.wholeRepairable = RenewableEnergy.ArrowBoard.sealablePanel(trailer.vehicle, LEFT) ~= nil end)
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = self.from, repaired = repaired } } })
            waitForPanelsCopy(self, trailer)
            T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" } })
            -- Read the authority's XP: a client's copy may still be getting the last test's.
            T.server(self, "perkXp", { perk = "Electricity" })
            T.step(function()
                self.epoxyUses = self.items.inputs[2]:getCurrentUses()
                self.xp = self.server.perkXp.value
            end)
            sealPanel(trailer)
            T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= self.from end)
            T.count(self, "left", { "Base.Screwdriver", "Base.Epoxy" })
            T.server(self, "perkXp", { perk = "Electricity" })
            T.step(function() self.gainedXp = self.server.perkXp.value - self.xp end)
            -- What CraftRecipe.addXP gives this character for the recipe's xpAward.
            T.server(self, "electricityAward", { xp = RenewableEnergy.Recipes.moduleRepairRecipe():getXPAward(0):getAmount() })
            waitForPanelsCopy(self, trailer)
        end,
        validate = function(self)
            local left, from, to = self.counts.left, self.from, self.to
            local condition = panelCondition(self.trailer.state, LEFT)
            expect(not self.wholeRepairable, "a panel at " .. self.wholeAt .. ", not cracked, can be sealed")
            expect(condition == to, "the seal took the panel from " .. from .. " to " .. tostring(condition) .. ", expected " .. to)
            expect(panelShown(self.trailer.state, LEFT) ~= "Whole", "the sealed panel at " .. tostring(condition) .. " shows whole")
            local sealed = self.trailer.state.panels[LEFT].repaired
            expect(sealed == repaired + 1, "the sealed panel reads repaired " .. tostring(sealed) .. "x, expected " .. repaired + 1)
            expect(left["Base.Screwdriver"] == 1, "the seal used up the screwdriver")
            local epoxy = player():getInventory():getFirstTypeRecurse("Base.Epoxy")
            local epoxyLeft = epoxy and epoxy:getCurrentUses() or 0
            expect(epoxyLeft == self.epoxyUses - self.epoxyNeeded, "the epoxy went from " .. self.epoxyUses .. " uses to " .. epoxyLeft
                .. ", the seal takes " .. self.epoxyNeeded)
            expect(self.gainedXp > 0, "the repair gave no Electricity XP")
            expectNear("Electricity XP from the repair", self.gainedXp, self.server.electricityAward.gained, 0.01)
        end,
    })
end
-- One seal short of the cap, one under it, and one under a twice-sealed module's lower cap.
repairTest("renewable_energy_world_arrow_board_repair_mends_a_cracked_panel", 0,
    function(cap) return cap - RenewableEnergy.Recipes.MODULE_REPAIR - 1 end)
repairTest("renewable_energy_world_arrow_board_repair_stops_at_its_cap", 0, function(cap) return cap - 1 end)
repairTest("renewable_energy_world_arrow_board_repair_after_two_seals_stops_lower", 2, function(cap) return cap - 1 end)

-- What the trailer's menu shows of Seal Cracked Panel (T.optionState).
local function sealPanelOption(vehicle)
    local context = T.newContext()
    RenewableEnergy.VehicleMenu.addSealPanelOptions(0, context, vehicle)
    local shown = T.optionState(context.options[1])
    context:closeAll()
    return shown
end

-- The menu offers Seal Cracked Panel to a character with everything it needs, and greys it out
-- in the dark, saying why, as the action's light rule refuses it
-- (RenewableEnergyAction.needsLight).
test("renewable_energy_world_arrow_board_repair_needs_light", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        setSealSkills(self)
        T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = T.sealCap(MODULE, 0) - 1 } } })
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
        T.onVehicle(self, self.trailer, "arrowBoardOldFrame", { hsv = { 0.3, 0.9, 0.8 } })
    end,
    validate = function(self)
        local answer = self.trailer.answer
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
        local front = getText("ContextMenu_RenewableEnergy_RepairFrame", getText("IGUI_RenewableEnergy_FrameFront"), 20)
        local back = getText("ContextMenu_RenewableEnergy_RepairFrame", getText("IGUI_RenewableEnergy_FrameBack"), 45)
        expect(self.labels[1] == front and self.labels[2] == back, "the menu offered " .. table.concat(self.labels, ", "))
        local state = self.trailer.state
        expect(frameCondition(state, FRAME_FRONT) == 100 and frameCondition(state, FRAME_BACK) == 100,
            "welding left the frame at " .. tostring(frameCondition(state, FRAME_FRONT)) .. " and "
            .. tostring(frameCondition(state, FRAME_BACK)))
        local left = self.counts.left["Base.SheetMetal"]
        expect(left < 3, "welding took none of the 3 sheet metal")
        expect(self.afterRepair == 0, "a whole frame offers " .. tostring(self.afterRepair) .. " repairs")
    end,
})

-- A new trailer's lid is padlocked on a roll just under STOCK.lockedChance and not on one at it,
-- whatever it was before; with the game's Easy Use option it is left unlocked even on the lowest roll.
test("renewable_energy_world_arrow_board_lid_lock_roll", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        T.onVehicle(self, self.trailer, "arrowBoardLidRolls", { trials = {
            { was = false, roll = "under" }, { was = true, roll = "at" }, { was = true, roll = 0, easyUse = true },
        } })
    end,
    validate = function(self)
        local locked = self.trailer.answer.locked
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
        T.onVehicle(self, self.trailer, "arrowBoardPanelStockRolls", { rolls = { "under", "at" } })
    end,
    validate = function(self)
        local answer = self.trailer.answer
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
        T.server(self, "arrowBoardControllerRolls", { trials = {
            { misc = 1, roll = "under" }, { misc = 1, roll = "at" }, { misc = 0.5, roll = "under" }, { misc = 0.5, roll = "at" },
        } })
    end,
    validate = function(self)
        local controllers = self.server.arrowBoardControllerRolls.controllers
        for i, misc in ipairs({ 1, 1, 0.5, 0.5 }) do
            local wanted = i % 2 == 1 and 1 or 0
            expect(controllers[i] == wanted, string.format("at Misc %s a roll %s the chance gave %d controllers, expected %d",
                misc, wanted == 1 and "just under" or "at", controllers[i], wanted))
        end
    end,
})
