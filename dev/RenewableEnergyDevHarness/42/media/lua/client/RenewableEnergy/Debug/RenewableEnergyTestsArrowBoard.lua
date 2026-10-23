require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Specs"
local Stage = require "RenewableEnergyDevStage"

-- Arrow board trailer (World/ArrowBoard.lua, ArrowBoardPower.lua, ArrowBoardCrashes.lua,
-- UI/BatteryBoxLid.lua, Vehicles.txt): stock, battery box and lid, panels, lamps, crashes, frame,
-- towing. Authority state goes through RenewableEnergyTestServerTrailer.lua; player actions go
-- through the vanilla and mod actions, checked on this client's copy.

local T = RenewableEnergyTest
local test, expect, expectNear, player = T.test, T.expect, T.expectNear, T.player

local MODULE, HOMEMADE = RenewableEnergy.Specs.factoryModule, "RenewableEnergy.HomemadeSolarModule"
local DEEP_CYCLE, L16 = "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery"
local CAR_BATTERY = RenewableEnergy.VehicleBattery.CAR_BATTERY

-- Fixtures ----------------------------------------------------------------------------------------

local function isOpenGround(x, y, z)
    local square = getSquare(x, y, z)
    return square ~= nil and square:isOutside() and square:isFree(false) and not square:HasTree()
        and square:getVehicleContainer() == nil
end

-- The nearest square with open ground three squares across, `ahead` north to `behind` south,
-- clear of the character.
local function openStrip(ahead, behind)
    local here = player():getSquare()
    local hx, hy, z = here:getX(), here:getY(), here:getZ()
    for radius = 1, 25 do
        for x, y in PZHarness.Fixtures.ring(hx, hy, radius) do
            local dx, dy = x - hx, y - hy
            local coversCharacter = math.abs(dx) <= 1 and -dy >= -ahead and -dy <= behind
            if not coversCharacter then
                local open = true
                for sx = x - 1, x + 1 do
                    for sy = y - ahead, y + behind do
                        open = open and isOpenGround(sx, sy, z)
                    end
                end
                if open then
                    return getSquare(x, y, z)
                end
            end
        end
    end
    return nil
end

-- The squares an arrow board takes north and south of its centre.
local TRAILER_AHEAD, TRAILER_BEHIND = 3, 3

-- ArrowBoard.PANELS's ids, copied for the reason lidOf gives.
local LEFT, RIGHT = "RenewableEnergyPanelLeft", "RenewableEnergyPanelRight"
local PANELS = { LEFT, RIGHT }
-- How long the server is given to show a change a client asked for.
local SERVER_MS = 15000

-- ArrowBoard.lua is a server file, loaded after this one, so part ids are read at run time.
local function lidOf(vehicle)
    return vehicle:getPartById(RenewableEnergy.ArrowBoard.LID)
end

local function boxOf(vehicle)
    return vehicle:getPartById(RenewableEnergy.ArrowBoard.BATTERY_BOX)
end

-- Queues an arrow board on open ground near the character, spawned with `args` and facing `facing`
-- (default north). Leaves its T.placeVehicle handle in self.trailer and returns it.
local function spawnTrailer(self, args, facing)
    local square = T.need(self, openStrip(TRAILER_AHEAD, TRAILER_BEHIND), "open ground for the arrow board")
    self.trailer = square and T.placeVehicle(self, RenewableEnergy.ArrowBoard.SCRIPT, { square = square, args = args, facing = facing })
    return self.trailer
end

-- Queues `fn`'s calls in one T.batch once the trailer is placed.
local function batchOnTrailer(fn)
    T.step(function() T.batch(fn) end)
end

local function panelCondition(state, partId)
    local panel = state and state.panels[partId]
    return panel and panel.installed and panel.condition or nil
end

local function panelShown(state, partId)
    local panel = state and state.panels[partId]
    return panel and panel.shown or "?"
end

-- Whether two states show the same panels: modules, conditions and models.
local function samePanels(a, b)
    for _, id in ipairs(PANELS) do
        if panelCondition(a, id) ~= panelCondition(b, id) or panelShown(a, id) ~= panelShown(b, id) then
            return false
        end
    end
    return true
end

-- Queues a wait until this client's copy shows the panels of the server's last state.
local function waitForPanelsCopy(self, trailer)
    T.waitForVehicleCopy(self, trailer, function(copy) return samePanels(copy, trailer.state) end,
        "this client's copy of the trailer's panels")
end

local function boxItems(state, fullType)
    local items = {}
    for _, item in ipairs(state and state.box and state.box.items or {}) do
        if not fullType or item.type == fullType then
            table.insert(items, item)
        end
    end
    return items
end

-- setTrailer's `panels` with a factory module at `condition` on each panel.
local function modulesOnBothPanels(condition)
    return { [LEFT] = { type = MODULE, condition = condition }, [RIGHT] = { type = MODULE, condition = condition } }
end

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

-- Queues the box's lid unpadlocked and down, and a wait until this client's copy shows it.
local function unlockBox(self, trailer)
    T.onVehicle(self, trailer, "setTrailer", { lidOpen = false, lidLocked = false })
    T.waitFor(self, function() return not lidOf(trailer.vehicle):getDoor():isLocked() end, "this client's copy of the unlocked lid")
end

-- The model a panel holding a module at `condition` (nil: none) shows.
local function modelFor(condition)
    return condition and (RenewableEnergy.ArrowBoard.isCracked(condition) and "Cracked" or "Whole") or ""
end

-- A found arrow board: a module on each panel at found conditions, each showing its model, to
-- players too; a box of stock batteries in the stock count, no modules, at most one controller;
-- and it spawns in junkyards and traffic jams.
test("renewable_energy_world_arrow_board_spawns_stocked", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        if not spawnTrailer(self, { stocked = true }) then return end
        T.vehicleState(self, self.trailer)
        readStockRanges(self)
        waitForPanelsCopy(self, self.trailer)
    end,
    validate = function(self)
        local ArrowBoard = RenewableEnergy.ArrowBoard
        local stock = ArrowBoard.STOCK
        for _, zone in ipairs({ "junkyard", "trafficjamn", "trafficjams" }) do
            expect(VehicleZoneDistribution[zone].vehicles[ArrowBoard.SCRIPT] ~= nil, "no arrow boards in " .. zone)
        end
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
        for _, id in ipairs(PANELS) do
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

-- Puts the character at the middle of the vehicle's `area` (or `toSide` squares toward its side),
-- facing it, where vanilla's walk to the area ends, so a queued action neither walks nor turns.
local function standIn(vehicle, area, toSide)
    local spot = vehicle:getAreaCenter(area)
    local x, y = spot:getX(), spot:getY()
    if toSide then
        local origin = vehicle:getWorldPos(0, 0, 0, Vector3f.new())
        local side = vehicle:getWorldPos(1, 0, 0, Vector3f.new())
        x, y = x + (side:x() - origin:x()) * toSide, y + (side:y() - origin:y()) * toSide
    end
    local p = player()
    p:teleportTo(x, y, vehicle:getZ())
    p:setX(x)
    p:setY(y)
    p:setTargetAndCurrentDirection(vehicle:getX() - x, vehicle:getY() - y)
end

-- Whether this game draws the trailer's lid held still, open or shut, as T.lidPose reads it.
local function lidHeld(pose, open)
    return pose ~= nil and pose.clip ~= nil and not pose.playing and pose.open == (open and 1 or 0)
end

local function describeLid(pose)
    if not pose then
        return "no lid model"
    end
    return string.format("clip %s, %s, %s open", tostring(pose.clip), pose.playing and "swinging" or "still", tostring(pose.open))
end

-- Saves test_lid_<name>.png (Core.TakeFullScreenshot) and prints where the trailer and its box
-- are on screen, with the zoom and screen width, for dev/lid-shots.py to crop by.
local function lidShot(name, vehicle)
    local file = "test_lid_" .. name .. ".png"
    getCore():TakeFullScreenshot(file)
    local x, y, z = vehicle:getX(), vehicle:getY(), vehicle:getZ()
    local box = vehicle:getAreaCenter(boxOf(vehicle):getArea())
    print(string.format("RELidShot %s %.1f %.1f %.1f %.1f %.3f %d", file, isoToScreenX(0, x, y, z), isoToScreenY(0, x, y, z),
        isoToScreenX(0, box:getX(), box:getY(), z), isoToScreenY(0, box:getX(), box:getY(), z),
        getCore():getZoom(0), getCore():getScreenWidth()))
end

local LID_SWINGS = "renewable_energy_world_arrow_board_lid_swings"

-- The lid swings open and stays open, and swings shut, both when this player moves it and when
-- someone else does (vanilla animates only the mover's game; ArrowBoard.lua's watchLids); the
-- box opens only while the lid is open. Run alone by name (dev/lid-shots.py), it also saves
-- screenshots of each pose.
test(LID_SWINGS, {
    instant = true,
    run = function(self)
        local shooting = PZHarness.run.selection == LID_SWINGS
        -- Facing south, its box is on the side the camera sees.
        if not spawnTrailer(self, { repair = true }, "S") then return end
        local trailer, p = self.trailer, player()
        T.onVehicle(self, trailer, "setTrailer", { lidOpen = false, lidLocked = false })
        T.waitFor(self, function()
            local door = lidOf(trailer.vehicle):getDoor()
            return not door:isLocked() and not door:isOpen() and lidHeld(T.lidPose(trailer), false)
        end, "this client's copy of the lid unlocked and held shut")
        T.step(function() self.shut = T.lidPose(trailer) end)
        -- Queues a shot of the held pose from beside the box: the box's area lies over the box, so
        -- the character steps south-west of it, level with it on the screen, hiding neither the
        -- box nor the trailer, and the pose gets a few frames to reach the screen.
        local function shotFromAside(label)
            if not shooting then return end
            T.step(function()
                local spot = trailer.vehicle:getAreaCenter(boxOf(trailer.vehicle):getArea())
                p:teleportTo(spot:getX() - 2, spot:getY() + 2, trailer.vehicle:getZ())
            end)
            -- The squares around the new spot stay dark until the lighting has seen them.
            T.waitFor(self, Stage.lightingSettled(p), "the lighting around the character")
            T.wait(3)
            T.step(function() lidShot(label, trailer.vehicle) end)
        end
        shotFromAside("0_shut")
        self.swings = {}
        -- Queues `act` from the box's area and a wait until the lid stands held `open`, noting what
        -- it passed on the way and whether the box then opens from there, with shots numbered
        -- `shot`: the first pose between, and the held pose.
        local function swing(name, open, shot, act)
            local seen = { name = name, open = open }
            table.insert(self.swings, seen)
            local label = shot .. "_" .. (name:gsub(" ", "_"))
            T.step(function()
                standIn(trailer.vehicle, boxOf(trailer.vehicle):getArea())
                act()
            end)
            T.waitFor(self, function()
                seen.pose = T.lidPose(trailer)
                if seen.pose and seen.pose.playing and seen.pose.open and seen.pose.open > 0.1 and seen.pose.open < 0.9 then
                    if shooting and not seen.between then
                        lidShot(label .. "_swinging", trailer.vehicle)
                    end
                    seen.between = true
                end
                return lidOf(trailer.vehicle):getDoor():isOpen() == open and lidHeld(seen.pose, open)
            end, "the lid held " .. (open and "open" or "shut") .. " after " .. name)
            T.step(function()
                local vehicle = trailer.vehicle
                seen.access = vehicle:canAccessContainer(boxOf(vehicle):getIndex(), p)
            end)
            shotFromAside(label)
        end
        -- What the trailer's menu does for Open Trunk and Close Trunk.
        swing("opening it", true, 1, function() ISVehicleMenu.onOpenDoor(p, lidOf(trailer.vehicle)) end)
        swing("closing it", false, 2, function() ISVehicleMenu.onCloseDoor(p, lidOf(trailer.vehicle)) end)
        swing("someone else opening it", true, 3, function() T.onVehicle(self, trailer, "setTrailer", { lidOpen = true }) end)
        swing("someone else closing it", false, 4, function() T.onVehicle(self, trailer, "setTrailer", { lidOpen = false }) end)
    end,
    validate = function(self)
        expect(self.shut.clip == "Lid_closing", "the lid plays " .. tostring(self.shut.clip))
        for _, seen in ipairs(self.swings) do
            expect(seen.between, seen.name .. " never swung the lid between shut and open")
            expect(seen.access == seen.open, seen.name .. " left the batteries " .. (seen.access and "reachable" or "out of reach")
                .. " with the lid " .. (seen.open and "open" or "shut"))
        end
    end,
})

-- Queues the lid padlocked and down, the box holding `box`, and a wait for this client's copy;
-- leaves the lid and the box in self.
local function padlockBox(self, trailer, box)
    T.onVehicle(self, trailer, "setTrailer", { lidOpen = false, lidLocked = true, box = box })
    T.waitFor(self, function()
        local lid = lidOf(trailer.vehicle)
        return lid and lid:getDoor() and lid:getDoor():isLocked() and not lid:getDoor():isOpen()
    end, "this client's copy of the padlocked lid")
    T.step(function()
        self.lid, self.box = lidOf(trailer.vehicle), boxOf(trailer.vehicle)
        standIn(trailer.vehicle, self.box:getArea())
    end)
end

-- Queues taking the deep cycle in self.box, and a wait until the server's box is empty and this
-- client holds it.
local function takeBattery(self, trailer)
    local p = player()
    T.step(function()
        local battery = self.box:getItemContainer():getFirstType(DEEP_CYCLE)
        if battery then
            ISTimedActionQueue.add(ISInventoryTransferAction:new(p, battery, self.box:getItemContainer(), p:getInventory()))
        end
    end)
    T.awaitVehicleState(self, trailer, function(state) return #boxItems(state) == 0 end, SERVER_MS)
    T.waitForCarried(self, DEEP_CYCLE, "this client's copy of the battery taken")
end

local function expectBatteryTaken(self)
    expect(#boxItems(self.trailer.state) == 0, #boxItems(self.trailer.state) .. " items left in the server's box")
end

-- A padlocked box opens the way vanilla gets into a locked trunk: the lid comes off in the
-- mechanics window, without its Basic Mechanics recipe, showing no model, and the batteries come
-- out; it goes back on without the recipe too, unlocked and shut.
test("renewable_energy_world_arrow_board_locked_box_opens_with_the_lid_off", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, p = self.trailer, player()
        T.setPerk(self, Perks.Mechanics, 3)
        if isClient() then
            T.setMechanicsCheat(self, true)
        end
        T.give(self, "wrench", { { type = "Base.Wrench" } })
        padlockBox(self, trailer, { { type = DEEP_CYCLE, charge = 0.5 } })
        T.waitFor(self, function() return self.box:getItemContainer():getItems():size() == 1 end,
            "this client's copy of the battery in the box")
        T.step(function()
            local vehicle = trailer.vehicle
            self.knewRecipe = p:isRecipeActuallyKnown("Basic Mechanics")
            self.lockedAccess = vehicle:canAccessContainer(self.box:getIndex(), p)
            self.canTakeOff = vehicle:canUninstallPart(p, self.lid)
            self.lidType = self.lid:getInventoryItem():getFullType()
            -- What the mechanics window does for Uninstall.
            ISVehiclePartMenu.onUninstallPart(p, self.lid)
        end)
        T.awaitVehicleState(self, trailer, function(state) return state.lid and not state.lid.installed end, SERVER_MS)
        T.waitFor(self, function() return self.lid:getInventoryItem() == nil and T.copyState(trailer).lid.shown == "" end,
            "this client's copy of the lid taken off, showing no model")
        T.step(function()
            self.lidOff = trailer.state
            self.lidOffPose = T.lidPose(trailer)
            self.openAccess = trailer.vehicle:canAccessContainer(self.box:getIndex(), p)
        end)
        takeBattery(self, trailer)
        T.step(function()
            self.canPutBack = trailer.vehicle:canInstallPart(p, self.lid)
            local lid = p:getInventory():getFirstTypeRecurse(self.lidType)
            if lid then
                ISVehiclePartMenu.onInstallPart(p, self.lid, lid)
                T.shortenQueuedInstalls()
            end
        end)
        T.awaitVehicleState(self, trailer, function(state) return state.lid and state.lid.installed end, SERVER_MS)
        T.waitFor(self, function() return self.lid:getInventoryItem() ~= nil and lidHeld(T.lidPose(trailer), false) end,
            "this client's copy of the lid put back, held shut")
        T.step(function()
            local door = self.lid:getDoor()
            self.lidBack = { locked = door:isLocked(), open = door:isOpen(), shown = T.copyState(trailer).lid.shown }
        end)
    end,
    validate = function(self)
        expect(not self.knewRecipe, "the character knows Basic Mechanics, so the lid coming off proves nothing")
        expect(not self.lockedAccess, "the padlocked box opens with its lid on")
        expect(self.canTakeOff, "the mechanics window won't take the padlocked lid off")
        expect(not self.lidOff.lid.installed, "the lid is still on the server's trailer")
        expect(self.openAccess, "the box doesn't open with its lid off")
        expect(self.lidOffPose == nil, "the lid taken off is still drawn, " .. describeLid(self.lidOffPose))
        expectBatteryTaken(self)
        expect(self.canPutBack, "the mechanics window won't put the lid back on")
        local back = self.lidBack
        expect(not back.locked and not back.open, "the lid put back is " .. (back.locked and "locked" or "unlocked")
            .. " and " .. (back.open and "open" or "shut") .. ", expected unlocked and shut")
        expect(back.shown == "Default", "the lid put back shows '" .. tostring(back.shown) .. "', expected Default")
    end,
})

-- The lid shows its padlock only while on, locked and uncut, on the server and in this game,
-- through unlocking, relocking, cutting, removal and refitting (which shows every model until the
-- lid watcher hides the padlock).
test("renewable_energy_world_arrow_board_padlock_shows_while_locked", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        self.seen = {}
        local function stage(name, args, want)
            local seen = { name = name, want = want }
            table.insert(self.seen, seen)
            T.onVehicle(self, trailer, "setTrailer", args)
            T.awaitVehicleState(self, trailer, function(state) return state.lid and state.lid.shown == want end, SERVER_MS)
            T.waitForVehicleCopy(self, trailer, function(copy) return copy.lid and copy.lid.shown == want end,
                "this client's copy of the lid " .. name .. " showing '" .. want .. "'")
            T.step(function() seen.server = trailer.state.lid and trailer.state.lid.shown end)
        end
        stage("locked", { lidOpen = false, lidLocked = true, lidLockBroken = false }, "Default,Padlock")
        stage("unlocked", { lidLocked = false }, "Default")
        stage("locked again", { lidLocked = true }, "Default,Padlock")
        stage("with its lock cut", { lidLockBroken = true }, "Default")
        stage("taken off", { lidInstalled = false, lidLocked = false, lidLockBroken = false }, "")
        stage("put back unlocked", { lidInstalled = true }, "Default")
    end,
    validate = function(self)
        for _, seen in ipairs(self.seen) do
            expect(seen.server == seen.want, "the lid " .. seen.name .. " shows '" .. tostring(seen.server)
                .. "' on the server, expected '" .. seen.want .. "'")
        end
    end,
})

-- Puts the character in the box's area near its side, facing the trailer, where the menu offers
-- the lid (BaseVehicle.getUseablePart can't from the area's middle).
local function standAtBox(vehicle)
    standIn(vehicle, boxOf(vehicle):getArea(), 0.7)
end

-- The slices of the trailer's radial menu where the character stands; undisplayed before drawing.
local function radialSlices()
    local p = player()
    local menu = getPlayerRadialMenu(p:getPlayerNum())
    ISVehicleMenu.showRadialMenuOutside(p)
    local slices = {}
    for _, slice in ipairs(menu.slices) do
        table.insert(slices, slice)
    end
    menu:undisplay()
    return slices
end

-- Cut Padlock in the radial menu: "offered" (cuts), "unavailable" (no command, says what it
-- takes) or "none".
local function cutPadlockSlice()
    local needs = getText("IGUI_RenewableEnergy_CutPadlockNeeds",
        getScriptManager():FindItem(RenewableEnergy.BatteryBoxLid.CUTTERS):getDisplayName())
    local shown = "none"
    for _, slice in ipairs(radialSlices()) do
        if slice.command[1] == RenewableEnergy.BatteryBoxLid.cutPadlock then
            shown = "offered"
        elseif slice.command[1] == nil and slice.text == needs then
            shown = "unavailable"
        end
    end
    return shown
end

-- The switch in the radial menu: "on"/"off" for the slice that turns it so, "shut" for the
-- commandless slice at a shut box, or "none".
local function switchSlice()
    local shown = "none"
    for _, slice in ipairs(radialSlices()) do
        if slice.command[1] == RenewableEnergy.BatteryBoxLid.flipSwitch then
            shown = slice.command[4] and "on" or "off"
        elseif slice.command[1] == nil and slice.text == getText("IGUI_RenewableEnergy_LampsSwitchShut") then
            shown = "shut"
        end
    end
    return shown
end

-- Bolt cutters cut the padlock from the menu: the lid unlocks with a broken lock, on the server
-- and here, the battery comes out, the cut lock never relocks even with the trailer's key, the
-- menu stops offering the cut, and the cutters survive.
test("renewable_energy_world_arrow_board_cut_padlock_opens_the_box", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, p = self.trailer, player()
        padlockBox(self, trailer, { { type = DEEP_CYCLE, charge = 0.5 } })
        T.waitFor(self, function() return self.box:getItemContainer():getItems():size() == 1 end,
            "this client's copy of the battery in the box")
        T.give(self, "cutters", { { type = RenewableEnergy.BatteryBoxLid.CUTTERS } })
        T.server(self, "arrowBoardKey", function() return T.vehicleArgs(trailer) end)
        T.step(function()
            local vehicle = trailer.vehicle
            standAtBox(vehicle)
            self.offered = cutPadlockSlice() == "offered"
            self.keyUnlocks = vehicle:canUnlockDoor(self.lid, p)
            local cutters = RenewableEnergy.BatteryBoxLid.padlockCutters(p, self.lid)
            if cutters then
                -- What the menu's Cut Padlock does, from where its walk would end.
                standIn(vehicle, self.box:getArea())
                RenewableEnergy.BatteryBoxLid.cutPadlock(p, self.lid, cutters)
            end
        end)
        T.awaitVehicleState(self, trailer, function(state) return state.lid and state.lid.lockBroken end, SERVER_MS)
        T.waitFor(self, function() return self.lid:getDoor():isLockBroken() and not self.lid:getDoor():isLocked() end,
            "this client's copy of the lid unlocked with a broken lock")
        T.step(function()
            local vehicle = trailer.vehicle
            self.cutServer = trailer.state.lid
            self.keyRelocks = vehicle:canLockDoor(self.lid, p)
            standAtBox(vehicle)
            self.cutSlice = cutPadlockSlice()
            ISVehicleMenu.onOpenDoor(p, self.lid)
        end)
        T.waitFor(self, function() return self.lid:getDoor():isOpen() end, "this client's copy of the cut lid opened")
        T.step(function()
            self.openAccess = trailer.vehicle:canAccessContainer(self.box:getIndex(), p)
        end)
        takeBattery(self, trailer)
    end,
    validate = function(self)
        expect(self.offered, "the menu at the padlocked box doesn't offer Cut Padlock to a player with bolt cutters")
        expect(self.keyUnlocks, "the trailer's key doesn't open its padlock, so it can't show the cut lock refusing it")
        local server = self.cutServer
        expect(server and not server.locked and server.lockBroken, "the server's lid is "
            .. tostring(server and server.locked and "locked" or "unlocked") .. " with its lock "
            .. tostring(server and server.lockBroken and "broken" or "whole") .. " after the cut")
        expect(not self.keyRelocks, "the cut padlock locks again with the trailer's key")
        expect(self.cutSlice == "none", "the menu shows Cut Padlock on a cut lock (" .. tostring(self.cutSlice) .. ")")
        expect(self.openAccess, "the box doesn't open once its padlock is cut")
        expectBatteryTaken(self)
        expect(player():getInventory():getFirstTypeRecurse(RenewableEnergy.BatteryBoxLid.CUTTERS) ~= nil,
            "cutting used up the bolt cutters")
    end,
})

-- Cut Padlock is offered only at a holding padlock to a player with cutters; without them a
-- slice says what it takes; unlocked or lidless boxes show neither.
test("renewable_energy_world_arrow_board_cut_padlock_needs_cutters_and_a_padlock", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        self.seen = {}
        local function look(name, want)
            T.step(function()
                standAtBox(trailer.vehicle)
                table.insert(self.seen, { name = name, want = want, shown = cutPadlockSlice() })
            end)
        end
        padlockBox(self, trailer)
        look("at a padlocked box without bolt cutters", "unavailable")
        T.give(self, "cutters", { { type = RenewableEnergy.BatteryBoxLid.CUTTERS } })
        look("at a padlocked box with bolt cutters", "offered")
        unlockBox(self, trailer)
        look("at an unlocked box", "none")
        T.onVehicle(self, trailer, "setTrailer", { lidInstalled = false, lidLocked = true })
        T.waitFor(self, function()
            local lid = lidOf(trailer.vehicle)
            return lid:getInventoryItem() == nil and lid:getDoor():isLocked()
        end, "this client's copy of the locked box without its lid")
        look("at a locked box without its lid", "none")
    end,
    validate = function(self)
        for _, seen in ipairs(self.seen) do
            expect(seen.shown == seen.want, "the menu " .. seen.name .. " shows Cut Padlock " .. seen.shown
                .. " rather than " .. seen.want)
        end
    end,
})

-- Opening the lid shows the battery box in the loot window as opening a trunk shows the trunk:
-- in single player only, since vanilla picks the container in complete(), which a multiplayer
-- client never runs (ISOpenVehicleDoor.selectContainerInLootWindow).
test("renewable_energy_world_arrow_board_box_shows_in_the_loot_window", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, p = self.trailer, player()
        unlockBox(self, trailer)
        T.step(function()
            self.lid, self.box = lidOf(trailer.vehicle), boxOf(trailer.vehicle)
            standAtBox(trailer.vehicle)
            getPlayerLoot(p:getPlayerNum()).forceSelectedContainer = nil
            ISVehicleMenu.onOpenDoor(p, self.lid)
        end)
        T.waitFor(self, function()
            if not self.lid:getDoor():isOpen() then
                return false
            end
            self.selected = getPlayerLoot(p:getPlayerNum()).forceSelectedContainer
            return true
        end, "this client's copy of the lid opened")
    end,
    validate = function(self)
        local picked = self.selected ~= nil and self.selected == self.box:getItemContainer()
        expect(picked == not isClient(), "opening the lid " .. (picked and "picked" or "didn't pick") .. " the battery box in the loot window"
            .. (isClient() and ", which vanilla never does for a trunk on a multiplayer client" or ""))
    end,
})

-- The panels charge the emptiest battery first, all of it while it has room; once all are full
-- the rest goes unstored.
test("renewable_energy_world_arrow_board_panels_charge_the_emptiest_battery", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", {
                panels = modulesOnBothPanels(100),
                box = { { type = DEEP_CYCLE, charge = 0.6 }, { type = L16, charge = 0.2 } },
            })
            T.onVehicle(self, trailer, "arrowBoardCharge", { hours = 1 })
            T.step(function() self.first = trailer.answer end)
            -- Little room in each: both fill, and the rest of the hour is lost.
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = DEEP_CYCLE, charge = 0.99 }, { type = L16, charge = 0.99 } } })
            T.onVehicle(self, trailer, "arrowBoardCharge", { hours = 1 })
            T.step(function() self.second = trailer.answer end)
        end)
    end,
    validate = function(self)
        local Specs = RenewableEnergy.Specs
        local deepWh, l16Wh = Specs.batteries[DEEP_CYCLE].wh, Specs.batteries[L16].wh
        -- How watts follow condition is charge_scales_with_panel_condition's.
        local hourWh = self.first.watts * self.first.flatWh
        local room = 0.01 * (deepWh + l16Wh)
        if not expect(hourWh > room, "the sun at noon gives only " .. hourWh .. " Wh an hour, too little to fill both") then
            return
        end
        if not expect(hourWh <= (1 - 0.2) * l16Wh, "an hour's " .. hourWh .. " Wh overfills the empty L-16") then
            return
        end
        local deepCycle, l16 = boxItems(self.first.state)[1], boxItems(self.first.state)[2]
        expectNear("watt-hours stored in an hour", self.first.stored, hourWh, 0.001)
        expectNear("the emptier L-16's charge", l16.charge, 0.2 + hourWh / l16Wh, 0.0001)
        expectNear("the fuller deep cycle's charge", deepCycle.charge, 0.6, 0.0001)
        expectNear("watt-hours stored with little room", self.second.stored, room, 0.01)
        local full = boxItems(self.second.state)
        expect(full[1].charge == 1 and full[2].charge == 1, "the batteries aren't full: " .. full[1].charge .. ", " .. full[2].charge)
    end,
})

-- Each installed panel makes power by its condition, a half-cracked one half what a whole one
-- does and a homemade one some, and with no panels the trailer stores nothing. The trailer reads
-- a module's watts with the mounts' own PowerBank.moduleWatts, so the checks compare the passes
-- with each other rather than with that function.
test("renewable_energy_world_arrow_board_charge_scales_with_panel_condition", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        self.passes = {}
        local function pass(panels, box)
            T.onVehicle(self, trailer, "setTrailer", { panels = panels, box = box })
            T.onVehicle(self, trailer, "arrowBoardCharge", { hours = 1 })
            T.step(function() table.insert(self.passes, trailer.answer) end)
        end
        batchOnTrailer(function()
            pass({ [LEFT] = { type = MODULE, condition = 100 }, [RIGHT] = { type = MODULE, condition = 50 } },
                { { type = L16, charge = 0 } })
            pass({ [RIGHT] = {} })
            pass({ [LEFT] = { type = HOMEMADE, condition = 60 } })
            pass({ [LEFT] = {} })
        end)
    end,
    validate = function(self)
        local p = self.passes
        local flatWh = p[1].flatWh
        if not expect(flatWh > 0, "no sun at noon") then return end
        local whole = p[2].watts
        if not expect(whole > 0, "a whole panel made nothing at noon") then return end
        expectNear("watts of a half-cracked panel over a whole one", (p[1].watts - whole) / whole, 0.5, 0.001)
        expectNear("watt-hours they store in an hour", p[1].stored, p[1].watts * flatWh, 0.001)
        expect(p[3].watts > 0 and p[3].watts < whole, "a homemade module at 60 makes " .. p[3].watts
            .. " W, expected some and less than a whole factory module's " .. whole)
        expectNear("watts with no panels", p[4].watts, 0)
        expectNear("watt-hours stored with no panels", p[4].stored, 0)
    end,
})

-- Lamps -----------------------------------------------------------------------------------------

-- Queues `args` set on the trailer and a zero-hour pass of its lamps, the photocell seeing dark
-- if `night`, noting in self.stages whether the lamps then show `want` ("day", "night", or nil for
-- dark).
local function lampStage(self, trailer, name, args, night, want)
    T.onVehicle(self, trailer, "setTrailer", args)
    T.onVehicle(self, trailer, "arrowBoardLamps", { hours = 0, night = night })
    T.step(function() table.insert(self.stages, { name = name, want = want, lamps = trailer.answer.state.lamps }) end)
end

local function expectLampStages(stages)
    for _, stage in ipairs(stages) do
        expect(stage.lamps == stage.want, "the lamps " .. stage.name .. " are " .. tostring(stage.lamps or "dark")
            .. ", expected " .. tostring(stage.want or "dark"))
    end
end

-- The lamps light only while switched on with the lamp board intact: switching off or wrecking
-- the board darkens them, welding it relights them, and after dark the photocell sets night.
test("renewable_energy_world_arrow_board_lamps_follow_switch_board_and_photocell", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, board = self.trailer, RenewableEnergy.ArrowBoard.BOARD
        self.stages = {}
        local function stage(name, args, night, want) lampStage(self, trailer, name, args, night, want) end
        batchOnTrailer(function()
            stage("switched on with a charged battery", { switchOn = true, box = { { type = DEEP_CYCLE, charge = 0.6 } } },
                false, "day")
            stage("after dark", {}, true, "night")
            stage("switched off", { switchOn = false }, false, nil)
            stage("on with its lamp board wrecked", { switchOn = true, frame = { [board] = 0 } }, false, nil)
            stage("on with its lamp board welded", { frame = { [board] = 100 } }, false, "day")
        end)
    end,
    validate = function(self)
        expectLampStages(self.stages)
    end,
})

-- Switched on in the noon sun with only a controller in the box, the pass stores nothing and the
-- lamps stay dark.
test("renewable_energy_world_arrow_board_lamps_stay_dark_without_batteries", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", {
                switchOn = true, box = { { type = RenewableEnergy.Specs.controller } }, panels = modulesOnBothPanels(100),
            })
            T.onVehicle(self, trailer, "arrowBoardUpdate", { hours = 1 })
        end)
    end,
    validate = function(self)
        local answer = self.trailer.answer
        expect(answer.state.switchOn, "the switch isn't on")
        expect(answer.state.lamps == nil, "the lamps are " .. tostring(answer.state.lamps) .. " with no battery in the box")
        expectNear("watt-hours stored with no battery", answer.stored, 0)
    end,
})

-- Lit, by day or night, the lamps drain a car battery at vanilla's engine-off lightbar rate:
-- Vehicles.Update.Lightbar's drain a minute, applied twice by VehicleUtils.chargeBattery.
local LIGHTBAR_SHARE_PER_HOUR = 2 * 0.000025 * 60
test("renewable_energy_world_arrow_board_lamps_drain_a_lightbars_share", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        local function lamps(hours, night, key)
            T.onVehicle(self, trailer, "arrowBoardLamps", { hours = hours, night = night })
            if key then
                T.step(function() self[key] = trailer.answer end)
            end
        end
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { switchOn = true, box = { { type = CAR_BATTERY, charge = 0.8 } } })
            -- A pass draws at the lamps' current state and only then sets it for `night`
            -- (ArrowBoard.runLamps), so a zero-hour pass sets the state the measured pass draws at.
            lamps(0, false)
            lamps(2, false, "day")
            lamps(0, true)
            lamps(2, true, "night")
        end)
    end,
    validate = function(self)
        -- A battery's charge is kept in whole uses of its UseDelta, which each pass rounds to.
        local function charge(answer)
            local battery = boxItems(answer.state, CAR_BATTERY)[1]
            return battery and battery.charge or -1
        end
        local share = 2 * LIGHTBAR_SHARE_PER_HOUR
        expectNear("the car battery's charge after two hours lit by day", charge(self.day), 0.8 - share, 2e-5)
        expectNear("the car battery's charge after two more hours lit at night", charge(self.night), 0.8 - 2 * share, 3e-5)
    end,
})

-- The controller cuts the lamps off once every battery is down to its cutoff, drawing none below
-- it, and relights them only at the reconnect level. Charges are whole uses, so each boundary is
-- probed one use either side; the panels charging back past reconnect relight them.
test("renewable_energy_world_arrow_board_lamps_cut_off_and_come_back", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, spec = self.trailer, RenewableEnergy.Specs.arrowBoard
        local use = instanceItem(DEEP_CYCLE):getUseDelta()
        self.use, self.stages = use, {}
        local function stage(name, args, want) lampStage(self, trailer, name, args, false, want) end
        local function battery(charge)
            return { { type = DEEP_CYCLE, charge = charge } }
        end
        batchOnTrailer(function()
            stage("lit, a use above the cutoff", { switchOn = true, panels = { [LEFT] = {}, [RIGHT] = {} },
                box = battery(spec.cutoff + use) }, "day")
            T.onVehicle(self, trailer, "arrowBoardLamps", { hours = 2, night = false })
            T.step(function() self.cut = trailer.answer end)
            stage("cut off, a use above the cutoff", { box = battery(spec.cutoff + use) }, nil)
            stage("cut off, a use under the reconnect level", { box = battery(spec.reconnect - use) }, nil)
            stage("cut off, at the reconnect level", { box = battery(spec.reconnect) }, "day")
            stage("lit, set to the cutoff", { box = battery(spec.cutoff) }, nil)
            -- A few hours of noon sun on two whole panels put it back over the reconnect level.
            T.onVehicle(self, trailer, "setTrailer", { panels = modulesOnBothPanels(100), box = battery(spec.reconnect - use) })
            T.onVehicle(self, trailer, "arrowBoardUpdate", { hours = 3 })
            T.step(function() self.charged = trailer.answer end)
        end)
    end,
    validate = function(self)
        local spec, wh = RenewableEnergy.Specs.arrowBoard, RenewableEnergy.Specs.batteries[DEEP_CYCLE].wh
        expectLampStages(self.stages)
        -- A battery's charge is read back as a 32-bit float.
        expectNear("watt-hours drawn down to the cutoff", self.cut.drawn, self.use * wh, 1e-3)
        local battery = boxItems(self.cut.state, DEEP_CYCLE)[1]
        expectNear("the battery's charge once cut off", battery.charge, spec.cutoff, 1e-6)
        expect(self.cut.state.lamps == nil, "the lamps are " .. tostring(self.cut.state.lamps) .. " drawn down to the cutoff")
        local charged = boxItems(self.charged.state, DEEP_CYCLE)[1]
        if not expect(charged.charge >= spec.reconnect, "the panels left the battery at " .. charged.charge
            .. ", too little sun to show the lamps coming back") then
            return
        end
        expect(self.charged.state.lamps == "day", "the lamps are " .. tostring(self.charged.state.lamps)
            .. " with the battery charged back to " .. charged.charge)
    end,
})

-- The switch is offered only with the box open or its lid off; at a shut box a commandless slice
-- says it's inside and the authority refuses it. Flipped, the lamps follow on server and client.
test("renewable_energy_world_arrow_board_switch_works_only_in_the_open_box", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, p = self.trailer, player()
        self.seen, self.refused = {}, {}
        local function look(name, want)
            T.step(function()
                standAtBox(trailer.vehicle)
                table.insert(self.seen, { name = name, want = want, shown = switchSlice() })
            end)
        end
        local function refused(name)
            T.onVehicle(self, trailer, "arrowBoardCanSwitch", { on = false })
            T.step(function() table.insert(self.refused, { name = name, can = trailer.answer.can }) end)
        end
        local function flip(on)
            T.step(function()
                -- From where the switch's walk would end.
                standIn(trailer.vehicle, boxOf(trailer.vehicle):getArea())
                RenewableEnergy.BatteryBoxLid.flipSwitch(p, trailer.vehicle, on)
            end)
            T.awaitVehicleState(self, trailer, function(state) return state.switchOn == on end, SERVER_MS)
            T.waitForVehicleCopy(self, trailer, function(copy) return copy.switchOn == on end,
                "this client's copy of the switch " .. (on and "on" or "off"))
            T.step(function()
                self[on and "onAgain" or "off"] = { server = trailer.state, copy = T.copyState(trailer) }
            end)
        end
        T.onVehicle(self, trailer, "setTrailer", {
            lidOpen = false, lidLocked = true, lidLockBroken = false, switchOn = true,
            box = { { type = DEEP_CYCLE, charge = 0.8 } },
        })
        T.waitForVehicleCopy(self, trailer, function(copy) return copy.switchOn and copy.lid and copy.lid.locked end,
            "this client's copy of the switched-on trailer with its lid padlocked")
        look("at a padlocked box", "shut")
        refused("padlocked")
        T.onVehicle(self, trailer, "setTrailer", { lidLocked = false })
        T.waitForVehicleCopy(self, trailer, function(copy) return copy.lid and not copy.lid.locked end,
            "this client's copy of the unlocked lid")
        look("at a shut box", "shut")
        refused("shut")
        T.onVehicle(self, trailer, "setTrailer", { lidOpen = true })
        T.waitForVehicleCopy(self, trailer, function(copy) return copy.lid and copy.lid.open end,
            "this client's copy of the open lid")
        look("at the open box, switched on", "off")
        flip(false)
        look("at the open box, switched off", "on")
        flip(true)
        T.onVehicle(self, trailer, "setTrailer", { lidInstalled = false })
        T.waitForVehicleCopy(self, trailer, function(copy) return copy.lid and not copy.lid.installed end,
            "this client's copy of the trailer without its lid")
        look("at the box without its lid", "off")
    end,
    validate = function(self)
        for _, seen in ipairs(self.seen) do
            expect(seen.shown == seen.want, "the menu " .. seen.name .. " shows the switch " .. seen.shown .. " rather than " .. seen.want)
        end
        for _, refused in ipairs(self.refused) do
            expect(refused.can == false, "the server lets the switch be flipped through the " .. refused.name .. " lid")
        end
        local off, on = self.off, self.onAgain
        expect(off.server.lamps == nil and off.copy.lamps == nil, "switched off, the lamps are "
            .. tostring(off.server.lamps) .. " on the server and " .. tostring(off.copy.lamps) .. " here")
        expect(on.server.lamps ~= nil and on.copy.lamps == on.server.lamps, "switched on again, the lamps are "
            .. tostring(on.server.lamps) .. " on the server and " .. tostring(on.copy.lamps) .. " here")
    end,
})

-- The frames a watch of the lamps may take at most: far more than its real time needs at any
-- frame rate.
local FLASH_WATCH_FRAMES = 100000

-- While the server has the lamps lit, this game flashes them lit and dark (ArrowBoard.flashPhase);
-- switched off, they stay dark for a whole flash period.
test("renewable_energy_world_arrow_board_lamps_flash_for_players", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        local period = 60000 / RenewableEnergy.Specs.arrowBoard.flashesPerMinute
        -- Queues counting the frames the board shows lit and dark into self[key], until `enough`
        -- of them are seen or `ms` pass.
        local function watch(key, ms, enough)
            T.step(function()
                local seen = { lit = 0, dark = 0, start = getTimestampMs() }
                self[key] = seen
                T.waitUntil(function()
                    local lit = trailer.vehicle:getWindowLightsOn()
                    seen.lit, seen.dark = seen.lit + (lit and 1 or 0), seen.dark + (lit and 0 or 1)
                    return enough(seen) or getTimestampMs() - seen.start >= ms
                end, FLASH_WATCH_FRAMES, "the lamps' flashes")
            end)
        end
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { switchOn = true, box = { { type = DEEP_CYCLE, charge = 0.8 } } })
            T.onVehicle(self, trailer, "arrowBoardLamps", { hours = 0, night = false })
        end)
        T.waitForVehicleCopy(self, trailer, function(copy) return copy.lamps == "day" end, "this client's copy of the lit lamps")
        watch("lit", 2 * period, function(seen) return seen.lit > 0 and seen.dark > 0 end)
        T.onVehicle(self, trailer, "setTrailer", { switchOn = false })
        T.waitForVehicleCopy(self, trailer, function(copy) return copy.lamps == nil end, "this client's copy of the dark lamps")
        watch("dark", period, function(seen) return seen.lit > 0 end)
    end,
    validate = function(self)
        local lit, dark = self.lit, self.dark
        expect(lit.lit > 0 and lit.dark > 0, string.format("lit, the board showed lit %d and dark %d frames", lit.lit, lit.dark))
        expect(dark.lit == 0, string.format("switched off, the board showed lit %d of %d frames", dark.lit, dark.lit + dark.dark))
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
-- (Specs.crackedBelow), to players too.
test("renewable_energy_world_arrow_board_panels_come_off_and_go_on", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer, p = self.trailer, player()
        local crackedBelow = RenewableEnergy.Specs.crackedBelow
        self.offAt, self.onAt = crackedBelow - 1, crackedBelow
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
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) == nil end, SERVER_MS)
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
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= nil end, SERVER_MS)
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

-- Each panel's install and uninstall skills name skills the game knows: it weighs the job's odds
-- by them (VehicleUtils.calculateInstallationSuccess) and reads an unknown name as Perks.MAX.
test("renewable_energy_world_arrow_board_panels_name_real_skills", {
    run = function(self) spawnTrailer(self) end,
    validate = function(self)
        local vehicle = self.trailer.vehicle
        for _, id in ipairs(PANELS) do
            for _, job in ipairs({ "install", "uninstall" }) do
                local skills, what = vehicle:getPartById(id):getTable(job).skills or "", id .. " " .. job
                expect(skills:find("%w+:%d") ~= nil, what .. " lists no skills")
                for name in skills:gmatch("(%w+):%d+") do
                    expect(Perks.FromString(name) ~= Perks.MAX, what .. " names the unknown skill " .. name)
                end
            end
        end
    end,
})

-- A crack, from a storm or a crash, takes as much from a panel's module as a storm takes from a
-- module on a mount, and shows it cracked, to players too; a storm cracks a trailer's panels as it
-- would flat panels.
test("renewable_energy_world_arrow_board_panels_crack", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = 80 } } })
            T.onVehicle(self, trailer, "arrowBoardCrack", { part = LEFT })
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
        local left = panelCondition(self.crack, LEFT)
        expect(left == 80 - crack, "a crack left the panel at 80 at " .. tostring(left))
        expect(panelShown(self.crack, LEFT) == "Cracked", "the cracked panel at " .. tostring(left) .. " shows "
            .. panelShown(self.crack, LEFT))
        expect(self.storm.cracked == 2, "a storm on the lowest rolls cracked " .. self.storm.cracked .. " panels, not both")
        local state = self.storm.state
        expect(panelCondition(state, LEFT) == 100 - crack and panelCondition(state, RIGHT) == 100 - crack,
            "the storm left the panels at " .. tostring(panelCondition(state, LEFT)) .. " and " .. tostring(panelCondition(state, RIGHT)))
        expect(self.calm.cracked == 0, "a storm cracked panels with storm damage off")
    end,
})

local TOWING_CAR = "Base.OffRoad"
-- How far ahead of the car, and behind the trailer, the strip they stand on runs, in squares.
local STRIP_AHEAD, STRIP_BEHIND = 7, 9
-- Frames to wait for the pair to join the cell and come to rest, and to settle on the hitch. The
-- physics runs in real time, so at an uncapped frame rate each takes many frames.
local VEHICLE_FRAMES = 3000
-- How close, in squares, the coupler sits on the hitch once the hitch has pulled the trailer in,
-- and how slow, in squares a second, the pair then rolls once it has settled.
local ON_HITCH, SETTLED_SPEED = 0.1, 0.2

local function hitchGap(car, trailer)
    local hitch = car:getTowingWorldPos("trailer", Vector3f.new())
    local coupler = trailer:getTowedByWorldPos("trailer", Vector3f.new())
    if not (hitch and coupler) then
        return math.huge
    end
    return math.sqrt((hitch:x() - coupler:x()) ^ 2 + (hitch:y() - coupler:y()) ^ 2)
end

local function inCell(vehicle)
    return getCell():getVehicles():contains(vehicle)
end

-- Queues a car and an arrow board on a strip of open ground, the trailer behind the car, both
-- whole, the trailer set up with `trailerArgs` if given (see the setTrailer handler), and a wait
-- until the game moves them. Leaves the handles in self.car and self.trailer and returns the strip
-- the car stands on, or nil without one.
local function createTowingPair(self, trailerArgs)
    local strip = T.need(self, openStrip(STRIP_AHEAD, STRIP_BEHIND), "open ground for a car and the arrow board")
    if not strip then return nil end
    local x, y, z = strip:getX(), strip:getY(), strip:getZ()
    local car = T.placeVehicle(self, TOWING_CAR, { square = strip, args = { repair = true } })
    local trailer = T.placeVehicle(self, RenewableEnergy.ArrowBoard.SCRIPT,
        { square = getSquare(x, y + 5, z), args = { repair = true } })
    self.car, self.trailer = car, trailer
    if trailerArgs then
        T.onVehicle(self, trailer, "setTrailer", trailerArgs)
    end
    -- The game moves, and checks the hitch of, only vehicles that have joined the cell. Single
    -- player then lets them settle where they dropped, which the tests can do without: a pair
    -- still rocking only takes longer to line up. A multiplayer client runs no physics for
    -- vehicles no player here drives or tows, so they never come to rest there.
    T.waitFor(self, function() return inCell(car.vehicle) and inCell(trailer.vehicle) end, "the car and the trailer in the cell",
        VEHICLE_FRAMES)
    T.waitUntil(function() return isClient() or car.vehicle:isAtRest() and trailer.vehicle:isAtRest() end, VEHICLE_FRAMES)
    return strip
end

-- Queues the character getting in at the wheel of self.car through the driver's door, and a wait
-- until they sit there. The character takes the seat as the action starts (vehicle:enter), and
-- the action then only plays the enter animation, in real time, until the animation sets
-- EnterAnimationFinished (ISEnterVehicle.update); the crash tests start from a seated driver, so
-- the action is told the animation finished at once.
local function enterDriver(self)
    local p, car = player(), self.car
    T.step(function()
        local outside = car.vehicle:getPassengerPosition(0, "outside")
        local door = car.vehicle:getWorldPos(outside:getOffset(), Vector3f.new())
        p:teleportTo(door:x(), door:y(), p:getZ())
        local enter = ISEnterVehicle:new(p, car.vehicle, 0)
        function enter:update()
            if self.started then
                self.character:SetVariable("EnterAnimationFinished", "true")
            end
            ISEnterVehicle.update(self)
        end
        ISTimedActionQueue.add(enter)
    end)
    T.waitFor(self, function() return car.vehicle:isDriver(p) end, "the character at the wheel of the car", VEHICLE_FRAMES)
end

-- Queues lining up self.car and self.trailer as a player does: tow points within a square and the
-- pair parallel, facing north. Do it after a driver gets in, since from then on the driver's client
-- moves the car and the server's place for it no longer counts.
local function alignTowPoints(self)
    local car, trailer = self.car, self.trailer
    T.server(self, "lineUpTrailer", function()
        return { car = T.vehicleArgs(car), trailer = T.vehicleArgs(trailer), facing = "N" }
    end)
    -- And this client's copies, which take the server's places only when it next sends them.
    T.step(function() T.lineUpTrailer(car.vehicle, trailer.vehicle, "N") end)
    T.waitFor(self, function() return hitchGap(car.vehicle, trailer.vehicle) < 1 end, "the tow points lined up", VEHICLE_FRAMES)
end

-- Queues hitching self.trailer to self.car the way a player does, with vanilla's action, and a
-- wait until the hitch has pulled the trailer in and the pair has settled; a hitch that never
-- forms fails the test. A test that tows runs instantly: the action hitches as it starts, and at
-- its real length it would take as long as the game spares a fresh hitch from snapping.
local function attachTrailer(self)
    local p, car, trailer = player(), self.car, self.trailer
    T.step(function()
        ISTimedActionQueue.add(ISAttachTrailerToVehicle:new(p, car.vehicle, trailer.vehicle, "trailer", "trailer"))
    end)
    -- The hitch pulls the trailer in over the next physics steps.
    T.waitUntil(function()
        return trailer.vehicle:getVehicleTowedBy() == car.vehicle and hitchGap(car.vehicle, trailer.vehicle) < ON_HITCH
            and car.vehicle:getSpeed2D() < SETTLED_SPEED and trailer.vehicle:getSpeed2D() < SETTLED_SPEED
    end, VEHICLE_FRAMES)
    T.step(function()
        local hitched = trailer.vehicle:getVehicleTowedBy() == car.vehicle
        T.need(self, hitched, string.format("the trailer hitched to the car (driving %s, tow points %.2f apart)",
            tostring(car.vehicle:isDriver(p)), hitchGap(car.vehicle, trailer.vehicle)))
    end)
end

-- Queues a hitched car and arrow board (createTowingPair, with `opts.trailer`). With `opts.drive`
-- the character gets in at the wheel first, so the hitch is fresh when the test goes on; else they
-- stand beside the car's tow bar. Leaves self.car and self.trailer.
local function towingPair(self, opts)
    opts = opts or {}
    local strip = createTowingPair(self, opts.trailer)
    if not strip then return end
    if opts.drive then
        enterDriver(self)
    end
    alignTowPoints(self)
    if not opts.drive then
        -- Beside the car's tow bar, out of the trailer's way; the runner puts the character back.
        T.step(function() player():teleportTo(strip:getX() + 2.5, strip:getY() + 3.5, strip:getZ()) end)
    end
    attachTrailer(self)
end

-- The crash watcher (ArrowBoard.sampleCrash), fed a frame at a time the velocities a trailer would
-- show, tells a crash from what isn't one: a speed change of a crash's worth within the window is
-- one, into a parked trailer, at speed, sideways too; a bump, or braking spread past the window,
-- isn't; a jolt soon after one, as the hitch brings a trailer up short, is the same crash, and
-- one after the quiet time a new one.
test("renewable_energy_world_arrow_board_crash_watch_tells_crashes", {
    instant = true,
    validate = function()
        local ArrowBoard = RenewableEnergy.ArrowBoard
        local crash = ArrowBoard.CRASH
        local crashMs, frame = crash.kmh / 3.6, 16
        local cruise, stopped = { 0, -30 / 3.6 }, { 0, 0 }
        -- Feeds `ground` velocities in m/s ({ x, y }, or "rest") one frame apart into a new watch;
        -- answers the frames that began a new crash, joined with commas.
        local function crashes(ground)
            local watch, found = ArrowBoard.newCrashWatch(), {}
            for i, v in ipairs(ground) do
                local atRest = v == "rest"
                if ArrowBoard.sampleCrash(watch, i * frame, atRest and 0 or v[1], atRest and 0 or v[2], atRest) then
                    table.insert(found, i)
                end
            end
            return table.concat(found, ",")
        end
        -- `list` with `frames` more frames at velocity `v`.
        local function hold(list, v, frames)
            for _ = 1, frames do
                table.insert(list, v)
            end
            return list
        end
        local function cruising(after)
            local list = hold({}, cruise, 5)
            table.insert(list, after)
            return list
        end

        expect(crashes({ "rest", { 0, -1.01 * crashMs } }) == "2", "a crash's jolt into a parked trailer went unseen")
        expect(crashes({ "rest", { 0, -0.99 * crashMs } }) == "", "a jolt just short of a crash's into a parked trailer cracked it")
        expect(crashes(cruising(stopped)) == "6", "stopping dead from 30 km/h went unseen")
        expect(crashes(cruising({ 1.01 * crashMs, cruise[2] })) == "6", "a crash's jolt sideways went unseen")
        expect(crashes(cruising({ 0, cruise[2] + 6 / 3.6 })) == "", "a bump of 6 km/h cracked the panels")
        -- Off 30 km/h over twice the window, the window sees half the speed shed.
        local braking, frames = {}, math.ceil(2 * crash.ms / frame)
        for i = 0, frames do
            table.insert(braking, { 0, cruise[2] * (1 - i / frames) })
        end
        expect(crashes(braking) == "", "braking to a stop over " .. frames * frame .. " ms cracked the panels")

        -- Stopped dead, thrown forward on the hitch 600 ms later, then stopped dead again once
        -- the throw has been out of the window for the quiet time.
        local hits = hold(cruising(stopped), stopped, math.floor(600 / frame))
        table.insert(hits, { 0, -1.01 * crashMs })
        local rebound = #hits
        hold(hits, { 0, -1.01 * crashMs }, math.ceil((crash.ms + crash.quietMs) / frame))
        table.insert(hits, stopped)
        local seen = crashes(hits)
        expect(seen == "6," .. #hits, string.format("a crash, its rebound at frame %d and a crash at frame %d began crashes at frames %s",
            rebound, #hits, seen))
    end,
})

-- Queues the crash command a driver's client sends for self.trailer behind self.car, then a read
-- of the trailer's state, which goes out after the command and so reads what it did.
local function reportCrash(self)
    T.step(function()
        sendClientCommand(player(), "RenewableEnergyArrowBoard", "crashed", { vehicle = self.trailer.id, car = self.car.id })
    end)
    T.vehicleState(self, self.trailer)
end

-- A multiplayer client asks the server to crack the panels of the trailer behind the car its
-- player drives; the authority's handler takes the command in single player too. From the driver,
-- a crash cracks them by Specs.storm.crack, the same crash reported again within the quiet time
-- cracks nothing more, and a crash that snapped the hitch counts while the trailer is close behind.
test("renewable_energy_world_arrow_board_crash_command_from_the_driver", {
    instant = true,
    run = function(self)
        towingPair(self, { drive = true, trailer = { box = {}, panels = modulesOnBothPanels(90) } })
        if not self.trailer then return end
        local trailer = self.trailer
        local function crashed(key)
            reportCrash(self)
            T.step(function() self[key] = trailer.state end)
        end
        crashed("once")
        -- The authority took the first crash before its state came back.
        T.step(function() self.firstMs = getTimestampMs() end)
        crashed("again")
        T.step(function() sendClientCommand(player(), "vehicle", "detachTrailer", { vehicle = self.car.id }) end)
        T.waitFor(self, function() return trailer.vehicle:getVehicleTowedBy() == nil end, "the trailer unhitched", VEHICLE_FRAMES)
        T.waitFor(self, function() return getTimestampMs() - self.firstMs > RenewableEnergy.ArrowBoard.CRASH.quietMs end,
            "the quiet time after the first crash", VEHICLE_FRAMES)
        crashed("snapped")
    end,
    validate = function(self)
        local crack = RenewableEnergy.Specs.storm.crack
        for _, case in ipairs({ { "once", 90 - crack, "a crash from the driver" }, { "again", 90 - crack, "the crash reported twice" },
            { "snapped", 90 - 2 * crack, "a later crash that snapped the hitch" } }) do
            local state = self[case[1]]
            expect(panelCondition(state, LEFT) == case[2] and panelCondition(state, RIGHT) == case[2], string.format(
                "%s left the panels at %s and %s, expected %d", case[3], tostring(panelCondition(state, LEFT)),
                tostring(panelCondition(state, RIGHT)), case[2]))
        end
    end,
})

-- The server takes a crash only from the player driving the car that tows the trailer: anyone
-- else's crash command, here the character's while standing beside the hitched pair, cracks
-- nothing.
test("renewable_energy_world_arrow_board_crash_command_needs_the_driver", {
    instant = true,
    run = function(self)
        towingPair(self, { trailer = { panels = { [LEFT] = { type = MODULE, condition = 90 } } } })
        if not self.trailer then return end
        reportCrash(self)
    end,
    validate = function(self)
        local left = panelCondition(self.trailer.state, LEFT)
        expect(left == 90, "a crash command from a player not driving left the panel at " .. tostring(left))
    end,
})

-- Queues a Seal Cracked Panel on the trailer's left panel, as the trailer's menu queues it.
local function repairPanel(trailer)
    T.step(function()
        ISTimedActionQueue.add(RenewableEnergyAction:new(player(), RenewableEnergyAction.REPAIR_PANEL, nil, nil, trailer.vehicle,
            nil, nil, LEFT))
    end)
end

-- The most a seal brings a factory module sealed `repaired` times before to (Recipes.sealLimit).
local function sealCap(repaired)
    local Recipes = RenewableEnergy.Recipes
    return Recipes.MODULE_REPAIR_CAP[MODULE] - Recipes.REPAIR_LIMIT_STEP * repaired
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
            self.from = fromBelowCap(sealCap(repaired))
            self.to = math.min(sealCap(repaired), self.from + RenewableEnergy.Recipes.MODULE_REPAIR)
            self.epoxyNeeded = sealEpoxyUses()
            setSealSkills(self)
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = RenewableEnergy.Specs.crackedBelow } } })
            waitForPanelsCopy(self, trailer)
            T.step(function() self.wholeRepairable = RenewableEnergy.ArrowBoard.repairablePanel(trailer.vehicle, LEFT) ~= nil end)
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = self.from, repaired = repaired } } })
            waitForPanelsCopy(self, trailer)
            T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" } })
            -- Read the authority's XP: a client's copy may still be getting the last test's.
            T.server(self, "perkXp", { perk = "Electricity" })
            T.step(function()
                self.epoxyUses = self.items.inputs[2]:getCurrentUses()
                self.xp = self.server.perkXp.value
            end)
            repairPanel(trailer)
            T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= self.from end, SERVER_MS)
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
            expect(not self.wholeRepairable, "a panel at " .. RenewableEnergy.Specs.crackedBelow .. ", not cracked, can be sealed")
            expect(condition == to, "the seal took the panel from " .. from .. " to " .. tostring(condition) .. ", expected " .. to)
            expect(condition < RenewableEnergy.Specs.crackedBelow, "the sealed panel at " .. tostring(condition) .. " shows whole")
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
local function repairPanelOption(vehicle)
    local context = T.newContext()
    RenewableEnergy.Menu.addPanelRepairOptions(0, context, vehicle)
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
        T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = sealCap(0) - 1 } } })
        waitForPanelsCopy(self, trailer)
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" } })
        T.step(function() self.lit = repairPanelOption(trailer.vehicle) end)
        -- T.makeDark sets the clock when called, so it runs in a step.
        T.step(function() T.makeDark(self) end)
        T.step(function() self.dark = repairPanelOption(trailer.vehicle) end)
    end,
    validate = function(self)
        expect(self.lit.shown and not self.lit.greyed, "in daylight with every input the repair isn't offered")
        expect(self.dark.greyed, "in the dark the repair isn't greyed out")
        expect(tostring(self.dark.reason):find(getText("Tooltip_RenewableEnergy_TooDark"), 1, true) ~= nil,
            "in the dark the repair's tooltip says '" .. tostring(self.dark.reason) .. "'")
    end,
})

-- ArrowBoard.FRAME's front and back ids, copied for the reason lidOf gives.
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
            RenewableEnergy.Menu.addFrameRepairOptions(0, context, trailer.vehicle)
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
            T.awaitVehicleState(self, trailer, function(state) return frameCondition(state, FRAME_FRONT) == 100 end, SERVER_MS)
            T.waitForVehicleCopy(self, trailer, function(copy) return frameCondition(copy, FRAME_FRONT) == 100 end,
                "this client's copy of the welded front")
            T.step(function()
                weld(frameOptions()[1], "TruckBed")
                T.awaitVehicleState(self, trailer, function(state) return frameCondition(state, FRAME_BACK) == 100 end, SERVER_MS)
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
-- Misc loot option and none at it: 0.75 at an option of 1, 0.375 at 0.5.
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

-- The box's discharge cycle is the calendar day's: a pass just after midnight, half an hour after
-- the evening's, finishes the day and wears its battery by the day's depth, run flat from full;
-- the evening's passes wear nothing.
test("renewable_energy_world_arrow_board_cycle_ends_at_midnight", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        local trailer = spawnTrailer(self, { repair = true })
        if not trailer then return end
        local function lampsArgs()
            local args = T.vehicleArgs(trailer)
            args.hours, args.night = 0, true
            return args
        end
        T.step(function() T.setTime(self, 23.5) end)
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = CAR_BATTERY, charge = 1 } } })
            T.onVehicle(self, trailer, "arrowBoardLamps", lampsArgs)
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = CAR_BATTERY, charge = 0 } } })
            T.onVehicle(self, trailer, "arrowBoardLamps", lampsArgs)
            T.step(function() self.evening = trailer.state end)
        end)
        T.step(function()
            self.full = instanceItem(CAR_BATTERY):getConditionMax()
            T.setTime(self, 24.01)
        end)
        T.serverUntil(self, "arrowBoardLamps", lampsArgs, function(reply)
            local battery = boxItems(reply.state, CAR_BATTERY)[1]
            return battery ~= nil and battery.condition < self.full
        end, SERVER_MS)
        T.step(function() trailer.state = self.server.arrowBoardLamps.state end)
    end,
    validate = function(self)
        local new = instanceItem(CAR_BATTERY)
        local full = new:getConditionMax()
        local expected = full - math.floor(RenewableEnergy.Battery.cycleWear(new, 1) * full)
        if not expect(expected < full, "a flat day wears a car battery less than a point, so its wear can't show") then return end
        local evening = boxItems(self.evening, CAR_BATTERY)[1]
        expect(evening ~= nil and evening.condition == full, "the evening's passes left the battery at "
            .. tostring(evening and evening.condition))
        local morning = boxItems(self.trailer.state, CAR_BATTERY)[1]
        expect(morning ~= nil and morning.condition == expected, "after midnight the battery is at "
            .. tostring(morning and morning.condition) .. ", expected " .. expected)
    end,
})
