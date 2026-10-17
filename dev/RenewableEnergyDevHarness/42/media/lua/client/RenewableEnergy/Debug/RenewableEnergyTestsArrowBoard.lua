require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Specs"
local Stage = require "RenewableEnergyDevStage"

-- Arrow board trailer tests. See RenewableEnergyTestLib.lua for how the runner works. The
-- trailer's panels, box, lid, lamps and frame live on the authority, so the tests set and read
-- them through the handlers in RenewableEnergyTestServerTrailer.lua, and check what players see on
-- this client's copy. What players do (opening the battery box, the mechanics window, the repairs,
-- washing, hitching and driving) goes through the vanilla actions and the mod's own.

local T = RenewableEnergyTest
local test, expect, expectNear, player = T.test, T.expect, T.expectNear, T.player

local MODULE, HOMEMADE = RenewableEnergy.Specs.factoryModule, "RenewableEnergy.HomemadeSolarModule"
local DEEP_CYCLE, L16 = "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery"

-- Fixtures ----------------------------------------------------------------------------------------

local function isOpenGround(x, y, z)
    local square = getSquare(x, y, z)
    return square ~= nil and square:isOutside() and square:isFree(false) and not square:HasTree()
        and square:getVehicleContainer() == nil
end

-- The square nearest the character with open ground three squares across, from `ahead` squares
-- north of it to `behind` squares south, clear of the character: room for vehicles facing north.
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

local LEFT, RIGHT = "RenewableEnergyPanelLeft", "RenewableEnergyPanelRight"
local PANELS = { LEFT, RIGHT }
-- How long the server is given to show a change a client asked for.
local SERVER_MS = 15000

-- The trailer's battery box lid and the box. ArrowBoard.lua is a server file, which loads after
-- this one, so the part ids are read when a test runs.
local function lidOf(vehicle)
    return vehicle:getPartById(RenewableEnergy.ArrowBoard.LID)
end

local function boxOf(vehicle)
    return vehicle:getPartById(RenewableEnergy.ArrowBoard.BATTERY_BOX)
end

-- Queues an arrow board on open ground near the character, spawned by the authority with `args`
-- (see RenewableEnergyTestLibWorld.lua) and facing `facing` (north unless given). Leaves its
-- T.placeVehicle handle in self.trailer and returns it, or nil without open ground.
local function spawnTrailer(self, args, facing)
    local square = T.need(self, openStrip(TRAILER_AHEAD, TRAILER_BEHIND), "open ground for the arrow board")
    self.trailer = square and T.placeVehicle(self, RenewableEnergy.ArrowBoard.SCRIPT, { square = square, args = args, facing = facing })
    return self.trailer
end

-- Queues what `fn` queues in one T.batch, from a step: by then the trailer is placed, so its calls
-- go out as plain tables, together.
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

-- Whether two states of the trailer have the same panels: modules, conditions and shown models.
local function samePanels(a, b)
    for _, id in ipairs(PANELS) do
        if panelCondition(a, id) ~= panelCondition(b, id) or panelShown(a, id) ~= panelShown(b, id) then
            return false
        end
    end
    return true
end

-- Queues a wait until this client's copy of the trailer, what players see, shows the panels of the
-- server's last state; a copy that never does fails the test.
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

-- Queues reading the conditions world spawns give modules (WorldSpawns.CRACKED and WEATHERED),
-- which only the authority loads, into self.server.worldSpawnStock.
local function readStockRanges(self)
    T.server(self, "worldSpawnStock", { names = {} })
end

-- Expects `state`'s panels stocked as a found trailer's, at the conditions of `ranges` (the
-- worldSpawnStock answer): the first module weathered, the second weathered or cracked. Returns
-- both conditions.
local function expectStockConditions(state, ranges, what)
    local left, right = panelCondition(state, LEFT), panelCondition(state, RIGHT)
    expect(left and T.inRange(left, ranges.weathered), what .. "'s left panel's module is at " .. tostring(left))
    expect(right and (T.inRange(right, ranges.weathered) or T.inRange(right, ranges.cracked)),
        what .. "'s right panel's module is at " .. tostring(right))
    return left, right
end

-- Queues the battery box's lid unpadlocked and down, as most trailers spawn with it padlocked,
-- and a wait until this client's copy shows it unlocked.
local function unlockBox(self, trailer)
    T.onVehicle(self, trailer, "setTrailer", { lidOpen = false, lidLocked = false })
    T.waitFor(self, function() return not lidOf(trailer.vehicle):getDoor():isLocked() end, "this client's copy of the unlocked lid")
end

-- The model a panel holding a module at `condition` (nil: none) shows.
local function modelFor(condition)
    return condition and (RenewableEnergy.ArrowBoard.isCracked(condition) and "Cracked" or "Whole") or ""
end

-- A spawned arrow board has a module on each panel, the first weathered and the second weathered
-- or cracked, each showing the model its condition calls for, to players too; its battery box
-- holds no modules, worn deep cycle batteries at a part charge, and at most one charge
-- controller; and the trailer turns up among junkyard and traffic jam vehicles.
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
        expect(T.inRange(batteries, stock.batteries), batteries .. " batteries in the battery box")
        expect(#boxItems(state, stock.battery) == batteries, "the battery box holds other batteries")
        T.expectFoundCharges(charges, "the battery box")
        local controllers = #boxItems(state, RenewableEnergy.Specs.controller)
        expect(controllers <= 1, "the battery box has " .. controllers .. " charge controllers")
    end,
})

-- A trailer spawned the plain way, as debug tools and the world's vehicle stories spawn vehicles,
-- which set every part's condition after its panels were stocked, keeps the stock conditions, and
-- each panel shows the model its condition calls for, to players too.
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

-- A trailer from a save made before its panels were parts loads with them empty, and they get
-- their modules on that first load, once: panels taken off later stay off.
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

-- Puts the character at the middle of one of the vehicle's areas, or `toSide` squares from there
-- towards the vehicle's side, facing the vehicle: teleportTo rounds down to the square's corner,
-- which can fall outside a narrow area. The area's middle is where vanilla's walk to the area
-- (ISPathFindAction:pathToVehicleArea) ends, and facing the vehicle is the turn an action's
-- waitToStart waits for, so an action queued from there neither walks nor turns, which would take
-- real time.
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

-- Its battery box, unlocked, opens only with its lid open, from beside it, and takes a battery a
-- player puts in.
test("renewable_energy_world_arrow_board_battery_box_opens_with_lid", {
    instant = true,
    run = function(self)
        -- A spawned vehicle may lack parts, and the box opens freely without its lid.
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, p = self.trailer, player()
        unlockBox(self, trailer)
        T.give(self, "battery", { { type = DEEP_CYCLE } })
        T.step(function()
            -- A spawned trailer may come stocked, so count from what it already holds.
            self.before = #boxItems(trailer.state, DEEP_CYCLE)
            local vehicle = trailer.vehicle
            local lid, box = lidOf(vehicle), boxOf(vehicle)
            self.lid, self.box = lid, box
            if not (lid and lid:getDoor() and box and box:getItemContainer()) then return end
            standIn(vehicle, box:getArea())
            self.shutAccess = vehicle:canAccessContainer(box:getIndex(), p)
            -- What the trailer's menu does for Open Trunk.
            ISVehicleMenu.onOpenDoor(p, lid)
        end)
        T.waitFor(self, function() return self.lid and self.lid:getDoor() and self.lid:getDoor():isOpen() end,
            "this client's copy of the lid opened")
        T.step(function()
            if not (self.lid and self.box) then return end
            self.openAccess = trailer.vehicle:canAccessContainer(self.box:getIndex(), p)
            ISTimedActionQueue.add(ISInventoryTransferAction:new(p, self.items.battery[1], p:getInventory(),
                self.box:getItemContainer()))
        end)
        T.awaitVehicleState(self, trailer, function(state)
            return #boxItems(state, DEEP_CYCLE) > self.before
        end, SERVER_MS)
    end,
    validate = function(self)
        if not (expect(self.lid ~= nil and self.lid:getDoor() ~= nil, "the battery box has no lid")
                and expect(self.box ~= nil and self.box:getItemContainer() ~= nil, "the battery box holds nothing")) then
            return
        end
        expect(self.trailer.state.lid ~= nil and not self.trailer.state.lid.locked, "the battery box stayed locked")
        expect(not self.shutAccess, "the battery box opens with its lid shut")
        expect(self.trailer.state.lid.open, "opening the lid left it shut")
        expect(self.openAccess, "the battery box doesn't open beside it with its lid open")
        local after = #boxItems(self.trailer.state, DEEP_CYCLE)
        expect(after == self.before + 1, "the battery box holds " .. after .. " deep cycles after one was put in, " .. self.before .. " before")
    end,
})

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

-- Saves a full screenshot as test_lid_<name>.png in the cache's Screenshots, which every --test
-- run clears first. The game copies the frame last shown (Core.TakeFullScreenshot). The console
-- line gives dev/lid-shots.py where the trailer's centre and its box's area are on the screen, in
-- UI units, and the zoom and the screen's width in UI units, to crop by.
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

-- The battery box lid swings open on its hinge when a player opens it and stays open, and swings
-- shut when they close it; it swings the same way in this game when someone else opens and closes
-- it, which vanilla shows only to the player who did (ArrowBoard.lua's watchLids). Each
-- swing passes the poses between shut and open, and the batteries come out only while it is open.
-- A run that selects this test alone by its name, as dev/lid-shots.py's command does, also saves
-- what this game drew (test_lid_*.png: the lid held shut, then one held and one mid-swing per
-- swing) for dev/lid-shots.py to lay out; other runs skip the shots, which cost the waits for the
-- screen and the lighting.
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

-- Queues putting the battery box's padlock on and its lid down, with what the box holds, and a
-- wait until this client's copy shows the lid locked; leaves the lid and the box in self.
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

-- Queues the character taking the deep cycle in self.box into their inventory, and a wait until
-- the server's box is empty and this client holds the battery.
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

-- A padlocked battery box stays shut when a player opens it as they would an unlocked one: the
-- trailer's Open Trunk tries the lock first, and nobody has the key. The refused unlock empties
-- the action queue (ISBaseTimedAction.stop), so it comes last and the checks read the copy here.
test("renewable_energy_world_arrow_board_locked_box_stays_shut", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, p = self.trailer, player()
        padlockBox(self, trailer)
        T.step(function()
            self.canUnlock = trailer.vehicle:canUnlockDoor(self.lid, p)
            ISVehicleMenu.onOpenDoor(p, self.lid)
        end)
    end,
    validate = function(self)
        local door = self.lid:getDoor()
        expect(not self.canUnlock, "a character without a key can unlock the battery box")
        expect(door:isLocked() and not door:isOpen(), "opening the padlocked box left it "
            .. (door:isLocked() and "locked" or "unlocked") .. " and " .. (door:isOpen() and "open" or "shut"))
        expect(not self.trailer.vehicle:canAccessContainer(self.box:getIndex(), player()), "the padlocked box opens")
    end,
})

-- A padlocked battery box opens the way vanilla gets into a locked trunk without its key: the lid
-- comes off in the mechanics window with a wrench and vanilla's trunk lid skill, without its Basic
-- Mechanics recipe, and then a player takes the batteries out. Off, the lid shows no model. The
-- lid goes back on without the recipe too, unlocked and drawn shut, so the box shuts again. The
-- test reads canUninstallPart and canInstallPart itself, so in multiplayer the mechanics cheat can
-- shorten the actions, as with the panels.
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

-- The lid shows its padlock only while it is on, locked, and its lock isn't cut, on the server and
-- in this game, which follows the server's changes: unlocking, locking again, cutting the lock,
-- taking the lid off, and putting a lid on unlocked, which shows all its models
-- (VehiclePart.setInventoryItem) until the lid watcher hides the padlock.
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

-- Puts the character inside the box's area, most of the way to its side, facing the trailer: where
-- a player opens the box from, so that the trailer's menu offers the lid (BaseVehicle.getUseablePart
-- wants the character in the area and facing the box, which from the area's middle they can't).
local function standAtBox(vehicle)
    standIn(vehicle, boxOf(vehicle):getArea(), 0.7)
end

-- The slices of the trailer's radial menu, opened where the character stands. The menu goes away
-- again before it is drawn.
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

-- What the trailer's radial menu shows of Cut Padlock: "offered" when a slice cuts the padlock,
-- "unavailable" when a slice only says what cutting takes (it has no command), "none" without
-- either.
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

-- What the trailer's radial menu shows of the lamps' switch: "on" or "off" for a slice that turns
-- the arrow board on or off, "shut" for the one that says the switch is in the shut box and has
-- no command, "none" without any.
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

-- With bolt cutters a player cuts the battery box's padlock where the trailer's menu offers it: the
-- lid comes unlocked with a broken lock, on the server and here, the box opens and gives up its
-- battery, and the lock never closes again, even for someone holding the trailer's key, which no
-- arrow board spawns with. Cut, the box offers no more cutting.
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

-- The trailer's menu offers Cut Padlock only at a padlock that holds, to a player carrying bolt
-- cutters; without them it shows the slice that only says what cutting takes, and on an unlocked
-- box or with the lid off it shows neither.
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
        T.onVehicle(self, trailer, "setTrailer", { lidLocked = false })
        T.waitFor(self, function() return not lidOf(trailer.vehicle):getDoor():isLocked() end,
            "this client's copy of the unlocked lid")
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

-- Its panels charge the batteries in its box, the emptiest first: all of a pass goes to the
-- emptier battery while it has room, and once batteries fill, the rest goes unstored.
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
            -- 1% of room in each: both fill, and the rest of the hour is lost.
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = DEEP_CYCLE, charge = 0.99 }, { type = L16, charge = 0.99 } } })
            T.onVehicle(self, trailer, "arrowBoardCharge", { hours = 1 })
            T.step(function() self.second = trailer.answer end)
        end)
    end,
    validate = function(self)
        local Specs = RenewableEnergy.Specs
        local deepWh, l16Wh = Specs.batteries[DEEP_CYCLE].wh, Specs.batteries[L16].wh
        -- What the panels made this hour; how a module's watts follow its condition is the next test's.
        local hourWh = self.first.watts * self.first.flatWh
        local room = 0.01 * (deepWh + l16Wh)
        if not expect(hourWh > room, "the sun at noon gives only " .. hourWh .. " Wh an hour, too little to fill both") then
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

-- The arrow board's lamps light only while its switch is on and its lamp board isn't wrecked:
-- switching off or wrecking the board darkens it, and welding the board back lights it again. The
-- photocell dims them after dark. How the battery's charge cuts them off and lights them again is
-- lamps_cut_off_and_come_back's.
test("renewable_energy_world_arrow_board_lamps_need_switch_charge_and_board", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, board = self.trailer, RenewableEnergy.ArrowBoard.BOARD
        self.stages = {}
        local function stage(name, args, night, want)
            T.onVehicle(self, trailer, "setTrailer", args)
            T.onVehicle(self, trailer, "arrowBoardLamps", { hours = 0, night = night })
            T.step(function() table.insert(self.stages, { name = name, want = want, lamps = trailer.answer.state.lamps }) end)
        end
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
        for _, stage in ipairs(self.stages) do
            expect(stage.lamps == stage.want, "the lamps " .. stage.name .. " are " .. tostring(stage.lamps or "dark")
                .. ", expected " .. tostring(stage.want or "dark"))
        end
    end,
})

-- Its panels only charge its batteries: switched on in the noon sun with no battery in its box,
-- only a charge controller, the clock's pass leaves it dark and stores nothing.
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

-- Lit, the lamps draw their flashing average from the box's battery for the time they run: by day
-- at full brightness, and less once the photocell dims them for the night.
test("renewable_energy_world_arrow_board_lamps_draw_less_at_night", {
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
            T.onVehicle(self, trailer, "setTrailer", { switchOn = true, box = { { type = DEEP_CYCLE, charge = 0.8 } } })
            -- A pass draws at the lamps' current state and only then sets it for `night`
            -- (ArrowBoard.runLamps), so a zero-hour pass sets the state the measured pass draws at.
            lamps(0, false)
            lamps(2, false, "day")
            lamps(0, true)
            lamps(2, true, "night")
        end)
    end,
    validate = function(self)
        local wh = RenewableEnergy.Specs.batteries[DEEP_CYCLE].wh
        local dayWh, nightWh = self.day.drawn, self.night.drawn
        expect(dayWh > 0, "two hours of lit lamps by day drew nothing")
        expect(nightWh > 0 and nightWh < dayWh / 2, string.format("the dimmed lamps draw %.2f Wh against %.2f by day", nightWh, dayWh))
        local battery = boxItems(self.night.state, DEEP_CYCLE)[1]
        -- What they drew came out of the battery. A battery's charge is kept in whole uses of its
        -- UseDelta, which each pass rounds to.
        expectNear("the battery's charge after both", battery and battery.charge or -1, 0.8 - (dayWh + nightWh) / wh, 3e-5)
    end,
})

-- The controller cuts the lamps off once every battery is down to its cutoff, taking none below
-- it, and lights them only once a battery is back up at the reconnect level. Charges are kept in
-- whole uses of the battery's UseDelta, so the boundaries are one use either side: a use above the
-- cutoff keeps lit lamps lit but doesn't light cut-off ones, a use under the reconnect level
-- leaves them dark, the level itself lights them, a battery set to the cutoff cuts them off, and
-- the panels charging it past the reconnect level light them again.
test("renewable_energy_world_arrow_board_lamps_cut_off_and_come_back", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, spec = self.trailer, RenewableEnergy.Specs.arrowBoard
        local use = instanceItem(DEEP_CYCLE):getUseDelta()
        self.use, self.stages = use, {}
        -- Queues `args` set on the trailer, then a zero-hour pass of the lamps, expecting them `want`.
        local function stage(name, args, want)
            T.onVehicle(self, trailer, "setTrailer", args)
            T.onVehicle(self, trailer, "arrowBoardLamps", { hours = 0, night = false })
            T.step(function() table.insert(self.stages, { name = name, want = want, lamps = trailer.answer.state.lamps }) end)
        end
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
        for _, stage in ipairs(self.stages) do
            expect(stage.lamps == stage.want, "the lamps " .. stage.name .. " are " .. tostring(stage.lamps or "dark")
                .. ", expected " .. tostring(stage.want or "dark"))
        end
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

-- The trailer's menu at its battery box offers the arrow board's switch only while the box is open
-- or its lid off: at a shut box, padlocked or not, a slice says the switch is inside and does
-- nothing, and the authority refuses the switch too. Opened, the switch turns the lamps off and on
-- again through the switch action, on the server and in this game.
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

-- This game draws the lamps the server lights: while they are lit the board flashes, lit and dark
-- by turns, and once the server switches them off it stays dark for a whole flash period, in
-- which a flashing board is lit for part of the time (ArrowBoard.flashPhase).
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

-- Found trailers have their switch on by STOCK.switchedOnChance: over SWITCH_ROLLS rolls the share
-- lands within SWITCH_TOLERANCE of it, about ten standard deviations, so the test doesn't fail by
-- chance.
local SWITCH_ROLLS, SWITCH_TOLERANCE = 4000, 0.045
test("renewable_energy_world_arrow_board_found_switched_on_mostly", {
    run = function(self)
        if not spawnTrailer(self) then return end
        T.onVehicle(self, self.trailer, "arrowBoardSwitchRolls", { rolls = SWITCH_ROLLS })
    end,
    validate = function(self)
        local answer = self.trailer.answer
        local share, chance = answer.on / SWITCH_ROLLS, RenewableEnergy.ArrowBoard.STOCK.switchedOnChance
        expect(math.abs(share - chance) <= SWITCH_TOLERANCE, string.format("%.3f of found trailers are switched on, expected about %.2f",
            share, chance))
    end,
})

-- Taking a cracked panel off in the mechanics way gives the module at the panel's condition and
-- leaves no panel showing; putting another module on shows it, whole or cracked by its condition,
-- to players too: one below Specs.crackedBelow shows cracked, one at it whole. A multiplayer
-- server times both actions in real time, so there the mechanics cheat shortens them
-- (T.setMechanicsCheat).
test("renewable_energy_world_arrow_board_panels_come_off_and_go_on", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer, p = self.trailer, player()
        local crackedBelow = RenewableEnergy.Specs.crackedBelow
        self.offAt, self.onAt = crackedBelow - 1, crackedBelow
        T.setPerk(self, Perks.Mechanics, 2)
        T.setPerk(self, Perks.Electricity, 1)
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

-- The mechanics window's menu for `part`, built by its own doPartContextMenu on a window that has
-- just what that function reads.
local function mechanicsMenu(vehicle, part)
    local window = setmetatable({ chr = player(), playerNum = 0, vehicle = vehicle }, { __index = ISVehicleMechanics })
    window.getAbsoluteX = function() return 0 end
    window.getAbsoluteY = function() return 0 end
    window:doPartContextMenu(part, 0, 0)
    return window.context
end

-- A panel's skills are vanilla's recommendations, as for any part: short of one, the panel still
-- comes off and goes on, the mechanics window offers Uninstall, and only the odds fall, by
-- vanilla's 20 plus 15 for each missing level (VehicleUtils.calculateInstallationSuccess), which
-- its tooltip shows. With every skill met the job can't fail. One test per case, as T.setPerk
-- sets its level when called and holds it for the whole test: { name, mechanics, electricity, odds }.
local ONE_SHORT = 100 - (20 + 15)
local SKILL_CASES = {
    { "recommend_mechanics", 1, 1, ONE_SHORT },
    { "recommend_electrical", 2, 0, ONE_SHORT },
    { "skilled", 2, 1, 100 },
}

for _, case in ipairs(SKILL_CASES) do
    local mechanics, electricity, success = case[2], case[3], case[4]
    local skills = "Mechanics " .. mechanics .. ", Electrical " .. electricity
    test("renewable_energy_world_arrow_board_panels_" .. case[1], {
        instant = true,
        run = function(self)
            if not spawnTrailer(self) then return end
            local trailer, p = self.trailer, player()
            T.setPerk(self, Perks.Mechanics, mechanics)
            T.setPerk(self, Perks.Electricity, electricity)
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = 90 }, [RIGHT] = {} } })
            waitForPanelsCopy(self, trailer)
            T.give(self, "kit", { { type = "Base.Wrench", equip = "primary" }, { type = MODULE, condition = 90 } })
            T.step(function()
                local vehicle = trailer.vehicle
                local left, right = vehicle:getPartById(LEFT), vehicle:getPartById(RIGHT)
                self.canTakeOff = vehicle:canUninstallPart(p, left)
                self.canPutOn = vehicle:canInstallPart(p, right)
                self.takeOffOdds = VehicleUtils.calculateInstallationSuccess(left:getTable("uninstall").skills, p)
                self.putOnOdds = VehicleUtils.calculateInstallationSuccess(right:getTable("install").skills, p)
                local context = mechanicsMenu(vehicle, left)
                local uninstall = context and context:getOptionFromName(getText("IGUI_Uninstall"))
                self.uninstallOption = uninstall and (uninstall.notAvailable and "greyed out" or "offered") or "missing"
                local tooltip = uninstall and uninstall.toolTip and uninstall.toolTip.description or ""
                self.showsOdds = tooltip:find(getText("Tooltip_chanceSuccess") .. " " .. self.takeOffOdds .. "%", 1, true) ~= nil
                if context then
                    context:closeAll()
                end
            end)
        end,
        validate = function(self)
            expect(self.canTakeOff, "a panel can't come off at " .. skills)
            expect(self.canPutOn, "a panel can't go on at " .. skills)
            expect(self.uninstallOption == "offered", "the mechanics window's Uninstall at " .. skills .. " is " .. tostring(self.uninstallOption))
            expectNear("odds of taking a panel off at " .. skills, self.takeOffOdds, success, 0)
            expectNear("odds of putting a panel on at " .. skills, self.putOnOdds, success, 0)
            -- Vanilla shows the odds only when the job can fail.
            expect(self.showsOdds == (success < 100), "the Uninstall tooltip " .. (self.showsOdds and "shows" or "doesn't show")
                .. " vanilla's odds of success at " .. skills)
        end,
    })
end

-- The mechanics window offers to install an inventory item whose full type is in the part's item
-- types (ISVehicleMechanics, VehicleUtils.getItems), so each panel lists both modules as they are
-- named, without the mechanicType the game appends to a specific item; and repair() puts a module
-- back on an empty panel, where an appended name found no item.
test("renewable_energy_world_arrow_board_panels_take_real_modules", {
    run = function(self)
        if not spawnTrailer(self) then return end
        T.onVehicle(self, self.trailer, "arrowBoardRepairAll")
    end,
    validate = function(self)
        local answer = self.trailer.answer
        for _, id in ipairs(PANELS) do
            local listed, types = answer.types[id], {}
            for _, fullType in ipairs(listed) do
                types[fullType] = true
            end
            expect(types[MODULE] and types[HOMEMADE], id .. " takes " .. table.concat(listed, ", "))
        end
        local left = answer.state.panels[LEFT]
        expect(left.installed and (left.type == MODULE or left.type == HOMEMADE),
            "repair() put " .. tostring(left.type or "nothing") .. " on the empty panel")
    end,
})

-- A crack, from a storm or a crash, takes as much from a panel's module as a storm takes from a
-- module on a mount, and shows it cracked, to players too; a storm cracks a trailer's panels as it
-- would flat panels.
test("renewable_energy_world_arrow_board_panels_crack", {
    sandbox = { StormDamage = true, StormDamageRate = 1000 },
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = 80 } } })
            T.onVehicle(self, trailer, "arrowBoardCrack", { part = LEFT })
        end)
        waitForPanelsCopy(self, trailer)
        T.step(function() self.crack = trailer.state end)
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { panels = modulesOnBothPanels(100) })
            -- This long a storm at the raised rate makes a crack all but certain.
            T.onVehicle(self, trailer, "arrowBoardStorm", { hours = 1000 })
        end)
        T.step(function()
            self.storm = trailer.answer
            T.setSandbox(self, "StormDamage", false)
        end)
        T.onVehicle(self, trailer, "arrowBoardStorm", { hours = 1000 })
        T.step(function() self.calm = trailer.answer end)
    end,
    validate = function(self)
        local crack = RenewableEnergy.Specs.storm.crack
        local left = panelCondition(self.crack, LEFT)
        expect(left == 80 - crack, "a crack left the panel at 80 at " .. tostring(left))
        expect(panelShown(self.crack, LEFT) == "Cracked", "the cracked panel at " .. tostring(left) .. " shows "
            .. panelShown(self.crack, LEFT))
        expect(self.storm.cracked == 2, "a long storm cracked " .. self.storm.cracked .. " panels, not both")
        local state = self.storm.state
        expect(panelCondition(state, LEFT) == 100 - crack and panelCondition(state, RIGHT) == 100 - crack,
            "the storm left the panels at " .. tostring(panelCondition(state, LEFT)) .. " and " .. tostring(panelCondition(state, RIGHT)))
        expect(self.calm.cracked == 0, "a storm cracked panels with storm damage off")
    end,
})

local TOWING_CAR = "Base.OffRoad"
-- How far ahead of the car, and behind the trailer, the strip they stand on runs, in squares:
-- the car is pushed a few squares north.
local STRIP_AHEAD, STRIP_BEHIND = 7, 9
-- Frames to wait for the pair to join the cell and come to rest, to settle on the hitch, and to
-- be pulled along. The physics runs in real time, so at an uncapped frame rate each takes many
-- frames.
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
-- wait until the hitch has pulled the trailer in and the pair has settled. Leaves in
-- self.hitchedAt a real time just after the hitch was made; a hitch that never forms fails the
-- test.
local function attachTrailer(self)
    local p, car, trailer = player(), self.car, self.trailer
    T.step(function()
        ISTimedActionQueue.add(ISAttachTrailerToVehicle:new(p, car.vehicle, trailer.vehicle, "trailer", "trailer"))
    end)
    -- The action hitches as it starts, so the hitch is older than its time since this. A test that
    -- tows runs instantly: at its real length the action would take two seconds, as long as the
    -- game spares a fresh hitch from snapping.
    T.step(function() self.hitchedAt = getTimestampMs() end)
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
-- stand beside the car's tow bar. Leaves self.car, self.trailer and self.hitchedAt.
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

-- A push each frame, small enough that a frame adds only a few km/h, and the speeds a crash's jolt
-- and a bump's stop pushing at. The game applies a push for the frame's length of physics time
-- (BaseVehicle.applyAccumulatedImpulsesFromHitObjectsToPhysics), so one push gives a different
-- speed at each frame rate; pushing up to a measured speed doesn't. Even at 60 frames a second
-- the crash's push takes well under the watcher's quarter second.
local PUSH, CRASH_KMH, BUMP_KMH = 1000, 35, 6

-- How long, in real milliseconds, a hitch holds whatever jolts it (Bullet.onVehicleConstraintImpulse),
-- and a push that snaps an older hitch in its first frames, well before the trailer has sped up by
-- a crash's worth.
local FRESH_HITCH_MS, SNAP_PUSH = 2000, 5000

-- How long a freshly spawned vehicle is given to fall onto its wheels before it counts as at rest
-- without having been seen moving: it reads as at rest before its physics exists
-- (BaseVehicle.isAtRest).
local SETTLE_MS = 1000

-- Queues a wait until the trailer stands alone at rest: once its physics has run and stopped, or
-- after SETTLE_MS.
local function waitForParked(self, trailer)
    local spawnedMs, moved
    T.step(function() spawnedMs = getTimestampMs() end)
    T.waitFor(self, function()
        local vehicle = trailer.vehicle
        moved = moved or vehicle:isPhysicsActive()
        return (moved or getTimestampMs() - spawnedMs > SETTLE_MS) and inCell(vehicle) and vehicle:isAtRest()
    end, "the trailer at rest on its own", VEHICLE_FRAMES)
end

-- The game cracks the panels of a trailer jolted as hard as a crash, and leaves them be after a
-- bump: the side that runs the trailer's physics watches its velocity, which is the client of the
-- player driving the car that tows it, and asks the server to crack them (in single player it
-- cracks them itself, parked trailers too). The jolt is a push on the trailer: `how` "towed" while
-- it is hitched to the character's car, soon enough after hitching that the hitch holds; "snap"
-- late enough that the jolt snaps the hitch, which the watcher then follows for a moment longer;
-- "parked" while it stands alone at rest, as a car running into it jolts it. `cracks` says
-- whether the jolt cracks the panels, by Specs.storm.crack each.
local function crashTest(name, targetKmh, cracks, how)
    local before = 90
    local towed, snap = how ~= "parked", how == "snap"
    test(name, {
        instant = true,
        spOnly = not towed and "a multiplayer client runs no physics for a trailer it doesn't tow, so it watches no parked one" or nil,
        run = function(self)
            local setup = { box = {}, panels = modulesOnBothPanels(before) }
            if towed then
                towingPair(self, { drive = true, trailer = setup })
            elseif spawnTrailer(self, { repair = true }) then
                T.onVehicle(self, self.trailer, "setTrailer", setup)
                waitForParked(self, self.trailer)
            end
            if not self.trailer then return end
            local trailer = self.trailer
            if snap then
                T.waitUntil(function() return getTimestampMs() - self.hitchedAt > FRESH_HITCH_MS end, VEHICLE_FRAMES)
            end
            self.peak = 0
            -- Until the car has stopped, so that the next test doesn't begin with the character at
            -- the wheel of a moving car, and the trailer too while hitched or parked, so that a
            -- crack a bump caused would show; a trailer the jolt set loose coasts on for a while. A
            -- pair rolling at a crash's speed takes longer to stop than one settling on its hitch.
            T.waitUntil(function()
                local vehicle = trailer.vehicle
                local speed = math.abs(vehicle:getCurrentSpeedKmHour())
                if not self.pushed then
                    if speed >= targetKmh then
                        self.pushed = true
                    else
                        vehicle:applyImpulseGeneric(vehicle:getX(), vehicle:getY(), vehicle:getZ(), 0, -1, 0, snap and SNAP_PUSH or PUSH)
                    end
                end
                self.peak = math.max(self.peak, speed)
                if towed and not self.snapSpeed and vehicle:getVehicleTowedBy() == nil then
                    self.snapSpeed = speed
                    self.hitchAgeMs = getTimestampMs() - self.hitchedAt
                end
                return self.pushed and (not towed or self.car.vehicle:isAtRest()) and (self.snapSpeed ~= nil or vehicle:isAtRest())
            end, 2 * VEHICLE_FRAMES)
            T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= before end,
                cracks and SERVER_MS or 0)
        end,
        validate = function(self)
            local state = self.trailer.state
            local expected = cracks and before - RenewableEnergy.Specs.storm.crack or before
            if not expect(self.pushed, string.format("the push never got the trailer to %d km/h, only %.1f", targetKmh, self.peak)) then
                return
            end
            if snap then
                expect(self.snapSpeed ~= nil, string.format("the jolt to %.1f km/h left the trailer hitched", self.peak))
            elseif towed then
                expect(self.snapSpeed == nil, string.format("the jolt snapped a hitch over %s ms old at %s km/h",
                    tostring(self.hitchAgeMs), tostring(self.snapSpeed)))
            end
            expect(panelCondition(state, LEFT) == expected and panelCondition(state, RIGHT) == expected,
                string.format("a jolt to %.1f km/h%s left the panels at %s and %s", self.peak,
                    self.snapSpeed and string.format(", snapping the hitch at %.1f,", self.snapSpeed) or "",
                    tostring(panelCondition(state, LEFT)), tostring(panelCondition(state, RIGHT))))
        end,
    })
end
crashTest("renewable_energy_world_arrow_board_crash_cracks_panels", CRASH_KMH, true, "towed")
crashTest("renewable_energy_world_arrow_board_bump_leaves_panels", BUMP_KMH, false, "towed")
crashTest("renewable_energy_world_arrow_board_crash_snapping_the_hitch_cracks_panels", CRASH_KMH, true, "snap")
crashTest("renewable_energy_world_arrow_board_crash_cracks_parked_panels", CRASH_KMH, true, "parked")
crashTest("renewable_energy_world_arrow_board_bump_leaves_parked_panels", BUMP_KMH, false, "parked")

-- The server takes a crash only from the player driving the car that tows the trailer: anyone
-- else's crash command, here the character's while standing beside the hitched pair, cracks
-- nothing.
test("renewable_energy_world_arrow_board_crash_command_needs_the_driver", {
    mpOnly = "single player cracks the panels where it watches the trailer; only a multiplayer client sends the crash command",
    instant = true,
    run = function(self)
        towingPair(self, { trailer = { panels = { [LEFT] = { type = MODULE, condition = 90 } } } })
        if not self.trailer then return end
        T.step(function()
            sendClientCommand(player(), "RenewableEnergyArrowBoard", "crashed", { vehicle = self.trailer.id, car = self.car.id })
        end)
        -- The command and a state request go out in order, so the state is read after the
        -- command was handled.
        T.vehicleState(self, self.trailer)
    end,
    validate = function(self)
        local left = panelCondition(self.trailer.state, LEFT)
        expect(left == 90, "a crash command from a player not driving left the panel at " .. tostring(left))
    end,
})

-- What Repair Cracked Module adds to a module's condition, and the most it brings it to.
local REPAIR_STEP, REPAIR_CAP = RenewableEnergy.Recipes.MODULE_REPAIR, RenewableEnergy.Recipes.MODULE_REPAIR_CAP[MODULE]

-- Queues a Repair Cracked Panel on the trailer's left panel, as the trailer's menu queues it.
local function repairPanel(trailer)
    T.step(function()
        ISTimedActionQueue.add(RenewableEnergyAction:new(player(), RenewableEnergyAction.REPAIR_PANEL, nil, nil, trailer.vehicle,
            nil, nil, LEFT))
    end)
end

-- Repair Cracked Panel takes Repair Cracked Module's inputs, keeping the screwdriver, needs its
-- Electricity level and gives its XP, and mends the panel's module from `from` by that recipe's
-- step, no higher than its repair cap. A module that isn't cracked (Specs.crackedBelow) can't be
-- repaired on the panel.
local function repairTest(name, from)
    test(name, {
        instant = true,
        run = function(self)
            if not spawnTrailer(self) then return end
            local trailer, p = self.trailer, player()
            T.setPerk(self, Perks.Electricity, 3)
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = RenewableEnergy.Specs.crackedBelow } } })
            waitForPanelsCopy(self, trailer)
            T.step(function() self.wholeRepairable = RenewableEnergy.ArrowBoard.repairablePanel(trailer.vehicle, LEFT) ~= nil end)
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = from } } })
            waitForPanelsCopy(self, trailer)
            T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.GlassPanel" }, { type = "Base.Epoxy" },
                { type = "Base.ElectricWire" } })
            -- The XP the authority's character has before and after; a client's copy can still be
            -- getting XP the test before gave.
            T.server(self, "electricityAward", { xp = 0 })
            T.step(function()
                self.epoxyUses = self.items.inputs[3]:getCurrentUses()
                self.xp = self.server.electricityAward.xp
            end)
            repairPanel(trailer)
            T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= from end, SERVER_MS)
            T.count(self, "left", { "Base.Screwdriver", "Base.GlassPanel", "Base.ElectricWire", "Base.Epoxy" })
            T.server(self, "electricityAward", { xp = 0 })
            T.step(function() self.gainedXp = self.server.electricityAward.xp - self.xp end)
            -- What the game gives this character for the recipe's xpAward, through the call
            -- CraftRecipe.addXP makes.
            T.server(self, "electricityAward", { xp = RenewableEnergy.Recipes.moduleRepairRecipe():getXPAward(0):getAmount() })
            waitForPanelsCopy(self, trailer)
        end,
        validate = function(self)
            local left = self.counts.left
            local condition, to = panelCondition(self.trailer.state, LEFT), math.min(REPAIR_CAP, from + REPAIR_STEP)
            expect(not self.wholeRepairable, "a panel at " .. RenewableEnergy.Specs.crackedBelow .. ", not cracked, can be repaired")
            expect(condition == to, "the repair took the panel from " .. from .. " to " .. tostring(condition) .. ", expected " .. to)
            expect(left["Base.Screwdriver"] == 1, "the repair used up the screwdriver")
            expect(left["Base.GlassPanel"] == 0, "the repair left the glass pane")
            expect(left["Base.ElectricWire"] == 0, "the repair left the wire")
            local epoxy = player():getInventory():getFirstTypeRecurse("Base.Epoxy")
            local epoxyLeft = epoxy and epoxy:getCurrentUses() or 0
            expect(epoxyLeft == self.epoxyUses - 1, "the epoxy went from " .. self.epoxyUses .. " uses to " .. epoxyLeft)
            expect(self.gainedXp > 0, "the repair gave no Electricity XP")
            expectNear("Electricity XP from the repair", self.gainedXp, self.server.electricityAward.gained, 0.01)
        end,
    })
end
-- One short of reaching the cap, and the least cracked module there is, which the cap stops.
repairTest("renewable_energy_world_arrow_board_repair_mends_a_cracked_panel", REPAIR_CAP - REPAIR_STEP - 1)
repairTest("renewable_energy_world_arrow_board_repair_stops_at_its_cap", RenewableEnergy.Specs.crackedBelow - 1)

-- What the trailer's menu shows of Repair Cracked Panel: "offered", "greyed out" with its
-- tooltip, or "missing".
local function repairPanelOption(vehicle)
    local context = ISContextMenu.get(0, 0, 0)
    RenewableEnergy.Menu.addPanelRepairOptions(0, context, vehicle)
    local option = context.options[1]
    local shown = { state = option and (option.notAvailable and "greyed out" or "offered") or "missing",
        tooltip = option and option.toolTip and option.toolTip.description or "" }
    context:closeAll()
    return shown
end

-- The menu offers Repair Cracked Panel to a character with everything it needs, and greys it out
-- in the dark, saying why, as the action's light rule refuses it (RenewableEnergyAction.needsLight).
test("renewable_energy_world_arrow_board_repair_needs_light", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        T.setPerk(self, Perks.Electricity, 3)
        T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = 35 } } })
        waitForPanelsCopy(self, trailer)
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.GlassPanel" }, { type = "Base.Epoxy" },
            { type = "Base.ElectricWire" } })
        T.step(function() self.lit = repairPanelOption(trailer.vehicle) end)
        -- T.makeDark sets the clock when called, so it waits its turn in a step.
        T.step(function() T.makeDark(self) end)
        T.step(function() self.dark = repairPanelOption(trailer.vehicle) end)
    end,
    validate = function(self)
        expect(self.lit.state == "offered", "in daylight with every input the repair is " .. self.lit.state)
        expect(self.dark.state == "greyed out", "in the dark the repair is " .. self.dark.state)
        expect(self.dark.tooltip:find(getText("Tooltip_RenewableEnergy_TooDark"), 1, true) ~= nil,
            "in the dark the repair's tooltip says '" .. self.dark.tooltip .. "'")
    end,
})

-- Part-used glue adds up, as in vanilla crafting: two tubes with one use left each pay the glue
-- the repair takes, and both are used up.
test("renewable_energy_world_arrow_board_repair_adds_up_part_used_glue", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        T.setPerk(self, Perks.Electricity, 3)
        T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = 35 } } })
        waitForPanelsCopy(self, trailer)
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.GlassPanel" }, { type = "Base.ElectricWire" },
            { type = "Base.Glue" }, { type = "Base.Glue" } })
        T.step(function()
            for i = 4, 5 do
                local glue = self.items.inputs[i]
                T.changeItem(self, glue, { uses = 1 / glue:getMaxUses() })
            end
        end)
        repairPanel(trailer)
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= 35 end, SERVER_MS)
        T.count(self, "left", { "Base.Glue" })
    end,
    validate = function(self)
        expect(panelCondition(self.trailer.state, LEFT) == math.min(REPAIR_CAP, 35 + REPAIR_STEP),
            "two part-used tubes of glue didn't pay for the repair")
        local glue = self.counts.left["Base.Glue"]
        expect(glue == 0, glue .. " tubes of glue left, expected both used up")
    end,
})

-- The car is pushed whenever it rolls slower than this, in squares a second, until the trailer
-- has followed it TOW_SQUARES. Pushed every frame, it would speed off the open strip, and a crash
-- snaps a hitch older than FRESH_HITCH_MS (Bullet.onVehicleConstraintImpulse).
local PUSH_SPEED = 5
local TOW_SQUARES = 2
-- A car with nobody at the wheel holds its brakes, so each push has to beat them.
local PUSH_IMPULSE = 6000

local function distanceFrom(start, x, y)
    return math.sqrt((x - start.x) ^ 2 + (y - start.y) ^ 2)
end

-- It spawns, a vanilla car hitches it with the game's own action, and when the car is pushed north
-- the trailer follows, still on the hitch, on the server too.
test("renewable_energy_world_arrow_board_towed_by_car", {
    instant = true,
    run = function(self)
        towingPair(self)
        if not self.trailer then return end
        local car, trailer = self.car, self.trailer
        local function towed()
            return distanceFrom(self.start, trailer.vehicle:getX(), trailer.vehicle:getY())
        end
        T.step(function()
            self.start = { x = trailer.vehicle:getX(), y = trailer.vehicle:getY() }
        end)
        T.waitUntil(function()
            if towed() >= TOW_SQUARES then
                return true
            end
            local vehicle = car.vehicle
            if vehicle:getSpeed2D() < PUSH_SPEED then
                vehicle:applyImpulseGeneric(vehicle:getX(), vehicle:getY(), vehicle:getZ(), 0, -1, 0, PUSH_IMPULSE)
            end
            return false
        end, VEHICLE_FRAMES)
        T.step(function()
            self.moved = towed()
            self.gap = hitchGap(car.vehicle, trailer.vehicle)
            self.towedBy = trailer.vehicle:getVehicleTowedBy() == car.vehicle
        end)
        T.awaitVehicleState(self, trailer, function(state)
            return distanceFrom(self.start, state.x, state.y) >= TOW_SQUARES
        end, SERVER_MS)
    end,
    validate = function(self)
        expect(self.towedBy, "the trailer is not hitched to the car")
        expect(self.moved >= TOW_SQUARES, string.format("the trailer moved %.2f squares behind the pushed car", self.moved))
        expect(self.gap < ON_HITCH, string.format("the trailer's coupler is %.2f squares off the car's hitch", self.gap))
        local state = self.trailer.state
        expect(state.towedBy == self.car.id, "the server's trailer is towed by " .. tostring(state.towedBy) .. ", not the car")
        local moved = distanceFrom(self.start, state.x, state.y)
        expect(moved >= TOW_SQUARES, string.format("the server's trailer moved %.2f squares", moved))
    end,
})

-- Unhitched and left on its own, it comes to rest on its wheels and coupler, as vanilla's Trailer
-- does (up vector dot 0.989, about 8.5 degrees nose down). Without its physics shapes it rests on
-- the chassis box's front edge at 0.897.
test("renewable_energy_world_arrow_board_stands_alone", {
    spOnly = "a dedicated server runs no vehicle physics and a client only those it drives, tows or bumps, so nothing settles a trailer left alone",
    run = function(self)
        if not spawnTrailer(self) then return end
        waitForParked(self, self.trailer)
    end,
    validate = function(self)
        local up = self.trailer.vehicle:getUpVectorDot()
        expect(up > 0.98, string.format("it came to rest tipped over (up vector dot %.3f)", up))
    end,
})

local FRAME_FRONT, FRAME_BACK = "EngineDoor", "TruckBed"

local function frameCondition(state, partId)
    local part = state and state.frame[partId]
    return part and part.installed and part.condition or nil
end

-- The game's own crash damage, which a car's crash passes on to the trailer it tows
-- (BaseVehicle.crash), dents the front of the frame in a front crash and the back in a rear one;
-- the mechanics window lists neither part.
test("renewable_energy_world_arrow_board_frame_dents_in_crashes", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "vehicleCrash", { amount = 40, front = true })
            T.step(function() self.front = trailer.state end)
            T.onVehicle(self, trailer, "vehicleCrash", { amount = 40, front = false })
        end)
    end,
    validate = function(self)
        for _, id in ipairs({ FRAME_FRONT, FRAME_BACK }) do
            local part = self.front.frame[id]
            expect(part ~= nil and part.category == "nodisplay", id .. " shows in the mechanics window")
        end
        local front, back = frameCondition(self.front, FRAME_FRONT), frameCondition(self.front, FRAME_BACK)
        expect(front and front < 100, "a front crash left the front of the frame at " .. tostring(front))
        expect(back == 100, "a front crash took the back of the frame to " .. tostring(back))
        back = frameCondition(self.trailer.state, FRAME_BACK)
        expect(back and back < 100, "a rear crash left the back of the frame at " .. tostring(back))
    end,
})

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

-- Vanilla's wash action offers each side of the trailer and washes its blood off from the side's
-- area: Front by the coupler, Rear behind the deck, Left and Right beside it.
local WASH_AREAS = { { side = "Front", area = "Engine" }, { side = "Rear", area = "TruckBed" },
    { side = "Left", area = "SeatLeft" }, { side = "Right", area = "SeatRight" } }
local WASH_BLOOD = 0.2

test("renewable_energy_world_arrow_board_washes", {
    instant = true,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer, p = self.trailer, player()
        T.give(self, "bucket", { { type = "Base.Bucket" } })
        self.offered, self.left = {}, {}
        -- Each side's wash is queued once the one before has finished, behind it.
        local function washSide(i)
            local wash = WASH_AREAS[i]
            local blood = {}
            for _, other in ipairs(WASH_AREAS) do
                blood[other.side] = other == wash and WASH_BLOOD or 0
            end
            T.onVehicle(self, trailer, "setTrailer", { blood = blood })
            T.server(self, "refillFluid", function() return { id = self.items.bucket[1]:getID(), fluid = "Water", liters = 10 } end)
            T.waitFor(self, function() return trailer.vehicle:getBloodIntensity(wash.side) > 0 end,
                "this client's copy of the blood on " .. wash.side)
            T.step(function()
                local vehicle = trailer.vehicle
                local area = ISWashVehicle.hasBlood(vehicle) and ISWashVehicle.chooseArea(p, vehicle)
                self.offered[wash.side] = area and area.id .. " at " .. area.area or "nothing"
                standIn(vehicle, wash.area)
                ISTimedActionQueue.add(ISWashVehicle:new(p, vehicle, wash.side, wash.area))
            end)
            T.awaitVehicleState(self, trailer, function(state) return state.blood[wash.side] <= 0 end, SERVER_MS)
            T.step(function()
                self.left[wash.side] = trailer.state.blood[wash.side]
                if WASH_AREAS[i + 1] then
                    washSide(i + 1)
                end
            end)
        end
        washSide(1)
    end,
    validate = function(self)
        for _, wash in ipairs(WASH_AREAS) do
            local expected = wash.side .. " at " .. wash.area
            expect(self.offered[wash.side] == expected, "blood on " .. wash.side .. " offered " .. tostring(self.offered[wash.side]))
            expect(self.left[wash.side] == 0, "washing " .. wash.side .. " left " .. tostring(self.left[wash.side]))
        end
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
        -- The frame's options, and under each the first fix: one sheet metal.
        local function frameOptions()
            local context = ISContextMenu.get(0, 0, 0)
            RenewableEnergy.Menu.addFrameRepairOptions(0, context, trailer.vehicle)
            local found = {}
            for _, option in ipairs(context.options) do
                local submenu = option.subOption and context:getSubMenu(option.subOption)
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
        expect(left == 1, "welding left " .. left .. " of 3 sheet metal")
        expect(self.afterRepair == 0, "a whole frame offers " .. tostring(self.afterRepair) .. " repairs")
    end,
})
