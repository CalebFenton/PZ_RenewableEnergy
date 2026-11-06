require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Debug/RenewableEnergyTestLibArrowBoard"
require "RenewableEnergy/Debug/RenewableEnergyTestLibCraft"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Items = require "cf_commonlib/Items"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Power"
local Specs = require "RenewableEnergy/Specs"
local VehicleJobs = require "RenewableEnergy/Gadgets/VehicleJobs"
local VehicleMenu = require "RenewableEnergy/UI/VehicleMenu"

-- Arrow board trailer (ArrowBoard/Trailer.lua, Vehicles.txt): stock and its rolls, panels, repair
-- and frame. Its battery box, power and crashes are in RenewableEnergyTestsArrowBoard*.lua.
-- Authority state goes through RenewableEnergyTestServerTrailer.lua; player actions go through
-- the vanilla and mod actions, checked on this client's copy.

local T = RenewableEnergyTest
local test, expect, expectEqual, expectNear, player = T.test, T.expect, T.expectEqual, T.expectNear, T.player
local spawnTrailer, batchOnTrailer, waitForPanelsCopy, standIn = T.spawnTrailer, T.batchOnTrailer, T.waitForPanelsCopy, T.standIn
local panelCondition, panelShown, boxItems, modulesOnBothPanels = T.panelCondition, T.panelShown, T.boxItems, T.modulesOnBothPanels
local LEFT, RIGHT = ArrowBoard.PANELS[1], ArrowBoard.PANELS[2]
local FRAME_FRONT, FRAME_BACK = ArrowBoard.FRAME[1].id, ArrowBoard.FRAME[2].id

local function frameCondition(state, partId)
    local part = state and state.frame[partId]
    return part and part.installed and part.condition or nil
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
        -- The spawn sets every part's condition after stocking and the next tick puts the stock
        -- ones back (Trailer.lua's keepStockConditions); read only once the authority has run it.
        T.awaitServerFrame(self)
        T.onVehicle(self, self.trailer, "vehicleState")
        T.read(self, "worldSpawnStock", { names = {} }, "ranges")
        waitForPanelsCopy(self, self.trailer)
    end,
    validate = function(self)
        local stock = ArrowBoard.STOCK
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
        local controllers = #boxItems(state, Specs.controller)
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
        T.readUntil(self, "arrowBoardStock", function() return T.at(trailer, { id = trailer.id }) end, "stock", function(reply)
            return panelCondition(reply.state, LEFT) == reply.stock[LEFT] and panelCondition(reply.state, RIGHT) == reply.stock[RIGHT]
        end)
        T.step(function() trailer.state = self.reads.stock.state end)
        waitForPanelsCopy(self, trailer)
    end,
    validate = function(self)
        local stock, state = self.reads.stock.stock, self.trailer.state
        for _, id in ipairs(ArrowBoard.PANELS) do
            local condition = panelCondition(state, id)
            expect(stock[id] ~= nil, id .. " was stocked with no module")
            expectEqual(id .. "'s condition", condition, stock[id])
            expectEqual("the model " .. id .. " at " .. tostring(condition) .. " shows", panelShown(state, id), modelFor(condition))
        end
    end,
})

-- A trailer saved before its panels were parts gets them on its first load, modules at found
-- conditions, and the script's colour over the random one it spawned with. Panels
-- taken off later stay off through the next load.
test("renewable_energy_world_arrow_board_old_trailer_gets_its_new_parts_once", {
    sandbox = { LRMSolarPanels = 1 },
    run = function(self)
        if not spawnTrailer(self) then return end
        T.onVehicle(self, self.trailer, "arrowBoardOldPanels", nil, "panels")
        T.onVehicle(self, self.trailer, "arrowBoardOldFrame", { hsv = { 0.3, 0.9, 0.8 } }, "frame")
        T.read(self, "worldSpawnStock", { names = {} }, "ranges")
        waitForPanelsCopy(self, self.trailer)
    end,
    validate = function(self)
        local first, second = self.reads.panels.first, self.reads.panels.second
        expectStockConditions(first, self.reads.ranges, "the old trailer")
        expect(panelCondition(second, LEFT) == nil and panelCondition(second, RIGHT) == nil,
            "panels taken off came back on the next load")
        expect(panelShown(second, LEFT) == "" and panelShown(second, RIGHT) == "",
            "empty panels show " .. panelShown(second, LEFT) .. " and " .. panelShown(second, RIGHT))
        local frame = self.reads.frame
        expect(frame.state.colorSat == frame.forcedSat and frame.state.colorVal == frame.forcedVal,
            string.format("the old trailer kept its colour, saturation %.2f and value %.2f", frame.state.colorSat, frame.state.colorVal))
    end,
})

-- What a trailer that comes back with its chunk shows: the lid padlocked, the switch on and the
-- lamps lit by day.
local function backAsSaved(state)
    return state.lamps == "day" and state.switchOn and state.lid ~= nil and state.lid.shown == "Default,Padlock"
end

-- A trailer comes back with its chunk as it was saved: its panel's module at its condition, not
-- cracked by the crash watcher reading its physics starting up (Crashes.lua), and the model it
-- shows, which the game doesn't save (Trailer.lua shows it again in the part's init); a panel taken off
-- stays off rather than being stocked again; the padlock shows on the locked lid; the switch stays
-- on, the lamps lit, and this game flashes them again. In multiplayer the server keeps the chunk,
-- so only this client's copy goes and comes back, sent again by the server.
test("renewable_energy_world_arrow_board_comes_back_from_a_chunk_reload", {
    timeoutSeconds = T.CHUNK_RELOAD_SECONDS,
    sandbox = { LRMSolarPanels = 1 },
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        self.cracked = T.conditionAt(T.FACTORY_MODULE, Specs.crackLooks.heavyBelow) - 1
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", {
                panels = { [LEFT] = { type = T.FACTORY_MODULE, condition = self.cracked }, [RIGHT] = {} },
                lidOpen = false, lidLocked = true, lidLockBroken = false, switchOn = true,
                box = { { type = T.DEEP_CYCLE, charge = 0.8 } },
            })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "runLamps", with = { 0, false } })
            T.onVehicle(self, trailer, "arrowBoardBeforeReload", {})
        end)
        T.waitForVehicleCopy(self, trailer, backAsSaved, "this client's copy of the trailer lit and padlocked")
        waitForPanelsCopy(self, trailer)
        -- The trip watches chunks load from when it is queued, so it is queued only once the
        -- server has said where the trailer stands.
        T.step(function()
            T.reloadChunk(self, T.at(trailer))
            T.readUntil(self, "arrowBoardAfterReload", function() return T.at(trailer, { id = trailer.id }) end, "after",
                function(reply) return reply.id ~= nil end)
            T.step(function()
                trailer.id, trailer.vehicle, trailer.state = self.reads.after.id, nil, self.reads.after.state
            end)
            T.waitFor(self, function()
                local copy = PZHarness.Fixtures.vehicleById(trailer.id, trailer)
                trailer.vehicle = copy and not copy:isRemovedFromWorld() and copy or nil
                return trailer.vehicle ~= nil
            end, "this client's copy of the trailer back with its chunk")
            T.waitForVehicleCopy(self, trailer, backAsSaved, "this client's copy of the trailer back lit and padlocked")
            waitForPanelsCopy(self, trailer)
            T.step(function() self.copy = T.copyState(trailer) end)
            local seen = {}
            T.waitFor(self, function()
                seen[trailer.vehicle:getWindowLightsOn()] = true
                return seen[true] and seen[false]
            end, "the board back with its chunk flashing lit and dark", 2 * 60000 / ArrowBoard.SPEC.flashesPerMinute)
        end)
    end,
    validate = function(self)
        local after = self.reads.after
        expect(isClient() or after.fresh, "the authority's trailer never went away with its chunk")
        for side, state in pairs({ ["the server's"] = after.state, ["this client's"] = self.copy }) do
            expectEqual(side .. " left panel's condition back from the save", panelCondition(state, LEFT), self.cracked)
            expectEqual("the model " .. side .. " left panel shows back from the save", panelShown(state, LEFT), "Cracked")
            expectEqual(side .. " emptied right panel's condition back from the save", panelCondition(state, RIGHT), nil)
            expectEqual("the model " .. side .. " emptied right panel shows back from the save", panelShown(state, RIGHT), "")
            expectEqual("the models " .. side .. " padlocked lid shows back from the save", state.lid and state.lid.shown,
                "Default,Padlock")
            expectEqual(side .. " lamps back from the save", state.lamps, "day")
        end
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
        local looks = Specs.crackLooks
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

-- A crack, from a crash or a storm, takes as much from a panel's module as a storm takes from a
-- module on a mount, and shows it cracked, to players too: a new module's first crack light, one
-- that takes a module under half its max heavy. A crash cracks every panel at once, down to no
-- glass at all and no further; a storm cracks a trailer's panels as it would flat panels.
test("renewable_energy_world_arrow_board_panels_crack", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        self.whole = Items.conditionMaxOf(T.FACTORY_MODULE)
        -- Half a crack above the heavy look, so a crack takes it below.
        self.light = T.conditionAt(T.FACTORY_MODULE, Specs.crackLooks.heavyBelow) + math.floor(Specs.storm.crack / 2)
        -- Less glass than a crack takes.
        self.thin = Specs.storm.crack - 1
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = T.FACTORY_MODULE, condition = self.whole },
                [RIGHT] = { type = T.FACTORY_MODULE, condition = self.light } } })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "crashCrack" }, "crack")
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = T.FACTORY_MODULE, condition = self.thin },
                [RIGHT] = { type = T.FACTORY_MODULE, condition = 0 } } })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "crashCrack" }, "thin")
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
        local crack, cracked = Specs.storm.crack, self.reads.crack.state
        local left, right = panelCondition(cracked, LEFT), panelCondition(cracked, RIGHT)
        expectEqual("the condition a crash left the panel at " .. self.whole .. " at", left, self.whole - crack)
        expectEqual("the model the new panel cracked to " .. tostring(left) .. " shows", panelShown(cracked, LEFT), "LightCracked")
        expectEqual("the condition a crash left the panel at " .. self.light .. " at", right, self.light - crack)
        expectEqual("the model the panel cracked to " .. tostring(right) .. " shows", panelShown(cracked, RIGHT), "Cracked")
        local thin = self.reads.thin.state
        expectEqual("the condition a crash left the panel at " .. self.thin .. " at", panelCondition(thin, LEFT), 0)
        expectEqual("the condition a crash left the panel with no glass at", panelCondition(thin, RIGHT), 0)
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
        ISTimedActionQueue.add(RenewableEnergyAction:new(player(), "vehicle", VehicleJobs.SEAL_PANEL,
            trailer.vehicle, LEFT))
    end)
end

-- The uses of epoxy the craft recipe `name` takes.
local function epoxyUses(name)
    local inputs = getScriptManager():getCraftRecipe(name):getInputs()
    local epoxy = getScriptManager():FindItem("Base.Epoxy")
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if input:containsItem(epoxy) then
            return math.ceil(input:getIntAmount() * input:getRelativeScale("Base.Epoxy"))
        end
    end
    return 0
end

-- The perks the craft recipe `name` awards XP in, by id.
local function recipeXpPerks(name)
    local recipe, perks = getScriptManager():getCraftRecipe(name), {}
    for i = 0, recipe:getXPAwardCount() - 1 do
        table.insert(perks, recipe:getXPAward(i):getPerk():getId())
    end
    return perks
end

-- Queues reading the authority's XP in the perks of the craft recipe `name` into
-- self.reads[label].
local function readRecipeXp(self, name, label)
    T.readCharacter(self, label, { perks = recipeXpPerks(name) })
end

-- Queues, after the job's "after" read, what CraftRecipe.addXP gives this character for each of the
-- recipe `name`'s xpAward lines, into self.reads["award" .. perk].
local function readRecipeAwards(self, name)
    local recipe = getScriptManager():getCraftRecipe(name)
    for i = 0, recipe:getXPAwardCount() - 1 do
        local award = recipe:getXPAward(i)
        T.xpAward(self, award:getPerk():getId(), award:getAmount(), "award" .. award:getPerk():getId())
    end
end

-- Expects the job `what` to have given the XP of each of the recipe `name`'s xpAward lines.
local function expectRecipeXp(self, name, what)
    for _, perk in ipairs(recipeXpPerks(name)) do
        local gained = self.reads.after.xp[perk] - self.reads.before.xp[perk]
        expect(gained > 0, what .. " gave no " .. perk .. " XP")
        expectNear(perk .. " XP from " .. what, gained, self.reads["award" .. perk].gained, 0.01)
    end
end

-- What the trailer's menu shows of Seal Cracked Panel for its left panel (T.optionState): the
-- trailer may hold a cracked right panel too.
local function sealPanelOption(vehicle)
    local context = T.newContext()
    VehicleMenu.addSealPanelOptions(0, context, vehicle)
    local shown = T.optionState(T.findIn(context.options, "param4", LEFT))
    context:closeAll()
    return shown
end

-- A module sealed before, low enough for one more seal, which would take a module never sealed
-- further: only a seal that reads the module's own seal count stops where it should.
local SEALED_BEFORE, SEAL_FROM = 2, 50

-- Seal Cracked Panel seals the panel's module as Seal Cracked Module seals one in hand
-- (ModuleRepair.sealed, whose steps and caps the module repair tests check), counting the seal,
-- and takes that recipe's inputs (keeping the screwdriver), skill and XP. The sealed panel still
-- shows cracked, and keeps its option, greyed out saying to reglaze it, since a seal can't bring
-- it further.
test("renewable_energy_world_arrow_board_seal_mends_a_cracked_panel", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        self.epoxyNeeded = epoxyUses(ModuleRepair.SEAL_RECIPE)
        T.setRecipeSkills(self, getScriptManager():getCraftRecipe(ModuleRepair.SEAL_RECIPE))
        T.onVehicle(self, trailer, "setTrailer",
            { panels = { [LEFT] = { type = T.FACTORY_MODULE, condition = SEAL_FROM, repaired = SEALED_BEFORE } } })
        waitForPanelsCopy(self, trailer)
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" } })
        -- Read the authority's XP: a client's copy may still be getting the last test's.
        readRecipeXp(self, ModuleRepair.SEAL_RECIPE, "before")
        T.step(function() self.epoxyUses = self.items.inputs[2]:getCurrentUses() end)
        sealPanel(trailer)
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= SEAL_FROM end)
        T.count(self, "left", { "Base.Screwdriver", "Base.Epoxy" })
        readRecipeXp(self, ModuleRepair.SEAL_RECIPE, "after")
        readRecipeAwards(self, ModuleRepair.SEAL_RECIPE)
        waitForPanelsCopy(self, trailer)
        T.step(function() self.after = sealPanelOption(trailer.vehicle) end)
    end,
    validate = function(self)
        local expected, seals = ModuleRepair.sealed(T.FACTORY_MODULE, SEAL_FROM, SEALED_BEFORE)
        if not expect(expected ~= ModuleRepair.sealed(T.FACTORY_MODULE, SEAL_FROM, 0),
            "a module never sealed seals to the same condition, so the seal count can't show") then
            return
        end
        local state = self.trailer.state
        local condition = panelCondition(state, LEFT)
        expectEqual("the condition the seal took the panel at " .. SEAL_FROM .. " to", condition, expected)
        expectEqual("the model the sealed panel at " .. tostring(condition) .. " shows", panelShown(state, LEFT), modelFor(condition))
        expectEqual("the sealed panel's seal count", state.panels[LEFT].repaired, seals)
        expect(self.after.shown and self.after.greyed and self.after.reason == getText("Tooltip_RenewableEnergy_PanelSealedFully"),
            "the sealed panel at " .. tostring(condition) .. ", sealed as far as it goes, shows Seal Cracked Panel "
            .. (self.after.shown and (self.after.greyed and "greyed out" or "offered") or "not at all")
            .. " (" .. tostring(self.after.reason) .. ")")
        expect(self.counts.left["Base.Screwdriver"] == 1, "the seal used up the screwdriver")
        local epoxy = T.carried("Base.Epoxy")
        expectEqual("epoxy uses left of " .. self.epoxyUses .. " (the seal takes " .. self.epoxyNeeded .. ")",
            epoxy and epoxy:getCurrentUses() or 0, self.epoxyUses - self.epoxyNeeded)
        expectRecipeXp(self, ModuleRepair.SEAL_RECIPE, "the seal")
    end,
})

-- The trailer menu `context`'s Reglaze Panel option for its left panel, or nil: the right panel
-- may be damaged too.
local function reglazeLeftOption(context)
    for _, option in ipairs(context.options) do
        if option.param2 == VehicleJobs.REGLAZE_PANEL and option.param4 == LEFT then
            return option
        end
    end
    return nil
end

-- Reglaze Panel, chosen from the trailer's menu, brings a heavily cracked, sealed panel back to new
-- and whole, clearing its seals, and takes Reglaze Module's inputs (keeping the screwdriver) and
-- gives its XP in each of its skills. The new panel is offered no more reglazing.
test("renewable_energy_world_arrow_board_reglaze_panel_in_place", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        T.setRecipeSkills(self, getScriptManager():getCraftRecipe(ModuleRepair.REGLAZE_RECIPE))
        T.knowRecipes(self, { ModuleRepair.REGLAZE_RECIPE })
        T.onVehicle(self, trailer, "setTrailer",
            { panels = { [LEFT] = { type = T.FACTORY_MODULE, condition = 30, repaired = 2 } } })
        waitForPanelsCopy(self, trailer)
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.GlassPanel" }, { type = "Base.Epoxy" },
            { type = "Base.ElectricWire" } })
        readRecipeXp(self, ModuleRepair.REGLAZE_RECIPE, "before")
        T.step(function() self.epoxyUses = self.items.inputs[3]:getCurrentUses() end)
        T.step(function()
            local context = T.newContext()
            VehicleMenu.addSealPanelOptions(0, context, trailer.vehicle)
            self.offered = T.optionState(reglazeLeftOption(context))
            context:closeAll()
            ISTimedActionQueue.add(RenewableEnergyAction:new(player(), "vehicle", VehicleJobs.REGLAZE_PANEL,
                trailer.vehicle, LEFT))
        end)
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= 30 end)
        T.count(self, "left", { "Base.Screwdriver", "Base.GlassPanel", "Base.ElectricWire", "Base.Epoxy" })
        readRecipeXp(self, ModuleRepair.REGLAZE_RECIPE, "after")
        readRecipeAwards(self, ModuleRepair.REGLAZE_RECIPE)
        waitForPanelsCopy(self, trailer)
        T.step(function()
            local context = T.newContext()
            VehicleMenu.addSealPanelOptions(0, context, trailer.vehicle)
            self.offeredAfter = reglazeLeftOption(context) ~= nil
            context:closeAll()
        end)
    end,
    validate = function(self)
        expect(self.offered.shown and not self.offered.greyed, "Reglaze Panel isn't offered for a cracked panel ("
            .. tostring(self.offered.reason) .. ")")
        local state = self.trailer.state
        expectEqual("the reglazed panel's condition", panelCondition(state, LEFT), 100)
        expectEqual("the model the reglazed panel shows", panelShown(state, LEFT), "Whole")
        expectEqual("the reglazed panel's seal count", state.panels[LEFT].repaired or 0, 0)
        expect(not self.offeredAfter, "the new panel is still offered Reglaze Panel")
        local left = self.counts.left
        expectEqual("screwdrivers left", left["Base.Screwdriver"], 1)
        expectEqual("glass panes left", left["Base.GlassPanel"], 0)
        expectEqual("electric wire left", left["Base.ElectricWire"], 0)
        local epoxy, needed = T.carried("Base.Epoxy"), epoxyUses(ModuleRepair.REGLAZE_RECIPE)
        expectEqual("epoxy uses left of " .. self.epoxyUses .. " (reglazing takes " .. needed .. ")",
            epoxy and epoxy:getCurrentUses() or 0, self.epoxyUses - needed)
        expectRecipeXp(self, ModuleRepair.REGLAZE_RECIPE, "reglazing")
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
        -- The first fix under each of the frame's options.
        local function frameFixes()
            local context = T.newContext()
            VehicleMenu.addFrameRepairOptions(0, context, trailer.vehicle)
            local fixes = {}
            for _, option in ipairs(context.options) do
                local submenu = T.subMenu(context, option)
                table.insert(fixes, submenu and submenu.options[1] or false)
            end
            return fixes
        end
        local function weld(fix, area)
            standIn(trailer.vehicle, area)
            T.choose(fix)
        end
        T.step(function()
            local fixes = frameFixes()
            if not T.need(self, #fixes == 2 and fixes[1] and fixes[2] or nil, "a fix under an option for each dented end") then
                return
            end
            weld(fixes[1], "Engine")
            T.awaitVehicleState(self, trailer, function(state) return frameCondition(state, FRAME_FRONT) == 100 end)
            T.waitForVehicleCopy(self, trailer, function(copy) return frameCondition(copy, FRAME_FRONT) == 100 end,
                "this client's copy of the welded front")
            T.step(function()
                weld(frameFixes()[1], "TruckBed")
                T.awaitVehicleState(self, trailer, function(state) return frameCondition(state, FRAME_BACK) == 100 end)
                T.waitForVehicleCopy(self, trailer, function(copy) return frameCondition(copy, FRAME_BACK) == 100 end,
                    "this client's copy of the welded back")
                T.count(self, "left", { "Base.SheetMetal" })
                T.step(function()
                    self.afterRepair = #frameFixes()
                end)
            end)
        end)
    end,
    validate = function(self)
        local state = self.trailer.state
        expectEqual("the welded front's condition", frameCondition(state, FRAME_FRONT), 100)
        expectEqual("the welded back's condition", frameCondition(state, FRAME_BACK), 100)
        -- Each weld takes the one sheet its fix names (Fix Trailer Frame Welding): 3 - 2 × 1.
        expectEqual("sheet metal left of 3 after welding both ends", self.counts.left["Base.SheetMetal"], 1)
        expectEqual("repairs a whole frame offers", self.afterRepair, 0)
    end,
})

-- A found battery box holds a charge controller on a roll just under STOCK.controllerChance × the
-- Misc loot option and none at it: each trial's Misc option and roll.
local CONTROLLER_TRIALS = {
    { misc = 1, roll = "under" }, { misc = 1, roll = "at" }, { misc = 0.5, roll = "under" }, { misc = 0.5, roll = "at" },
}

-- A new trailer's switch is on for a roll under STOCK.switchedOnChance and off for one at it; a
-- trailer with its switch set keeps it, whatever the roll. Its lid is padlocked on a roll just under
-- STOCK.lockedChance and not on one at it, whatever it was before; with the game's Easy Use option
-- it is left unlocked even on the lowest roll. Its second panel gets a cracked module on a roll just
-- under STOCK.secondCrackedChance and a weathered one at it; the first panel's is weathered either
-- way. Its battery box gets a controller by CONTROLLER_TRIALS.
test("renewable_energy_world_arrow_board_stock_rolls", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "arrowBoardSwitchRolls", { trials = { { roll = "under" }, { roll = "at" },
                { was = false, roll = 0 } } }, "switch")
            T.onVehicle(self, trailer, "arrowBoardLidRolls", { trials = {
                { was = false, roll = "under" }, { was = true, roll = "at" }, { was = true, roll = 0, easyUse = true },
            } }, "lid")
            T.onVehicle(self, trailer, "arrowBoardPanelStockRolls", { rolls = { "under", "at" } }, "panels")
            T.read(self, "arrowBoardControllerRolls", { trials = CONTROLLER_TRIALS }, "controllers")
        end)
    end,
    validate = function(self)
        local on = self.reads.switch.on
        expect(on[1] == true, "a roll just under the switch's chance left a found trailer off")
        expect(on[2] == false, "a roll at the switch's chance switched a found trailer on")
        expect(on[3] == false, "stocking switched on a trailer already switched off")
        local locked = self.reads.lid.locked
        expect(locked[1] == true, "a roll just under the locked chance left the lid unlocked")
        expect(locked[2] == false, "a roll at the locked chance left the lid locked")
        expect(locked[3] == false, "with Easy Use the lowest roll left the lid locked")
        local panels = self.reads.panels
        local under, at = panels.stocked[1], panels.stocked[2]
        for label, stocked in pairs({ ["just under the chance"] = under, ["at the chance"] = at }) do
            expect(T.inRange(stocked[LEFT], panels.weathered), "on a roll " .. label .. " the left module is at " .. tostring(stocked[LEFT]))
        end
        expect(T.inRange(under[RIGHT], panels.cracked), "on a roll just under the chance the right module is at " .. tostring(under[RIGHT]))
        expect(T.inRange(at[RIGHT], panels.weathered), "on a roll at the chance the right module is at " .. tostring(at[RIGHT]))
        local controllers = self.reads.controllers.controllers
        for i, trial in ipairs(CONTROLLER_TRIALS) do
            local wanted = trial.roll == "under" and 1 or 0
            expectEqual(string.format("controllers at Misc %s from a roll %s the chance", trial.misc,
                trial.roll == "under" and "just under" or "at"), controllers[i], wanted)
        end
    end,
})
