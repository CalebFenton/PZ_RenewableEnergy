require "RenewableEnergy/Debug/RenewableEnergyTestLibArrowBoard"
local Harness = require "PZHarness/Stage"

-- The arrow board's battery box (World/ArrowBoard.lua, UI/BatteryBoxLid.lua, Vehicles.txt): its
-- lid, padlock, loot window and lamp switch.
-- Authority state goes through RenewableEnergyTestServerTrailer.lua; player actions go through
-- the vanilla and mod actions, checked on this client's copy.

local T = RenewableEnergyTest
local test, expect, player = T.test, T.expect, T.player
local lidOf, boxOf, spawnTrailer, boxItems, standIn = T.lidOf, T.boxOf, T.spawnTrailer, T.boxItems, T.standIn

local DEEP_CYCLE = "RenewableEnergy.DeepCycleBattery"

-- Queues the box's lid unpadlocked and down, and a wait until this client's copy shows it.
local function unlockBox(self, trailer)
    T.onVehicle(self, trailer, "setTrailer", { lidOpen = false, lidLocked = false })
    T.waitFor(self, function() return not lidOf(trailer.vehicle):getDoor():isLocked() end, "this client's copy of the unlocked lid")
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
            T.waitFor(self, Harness.lightingSettled(p), "the lighting around the character")
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
    T.awaitVehicleState(self, trailer, function(state) return #boxItems(state) == 0 end)
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
        T.awaitVehicleState(self, trailer, function(state) return state.lid and not state.lid.installed end)
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
        T.awaitVehicleState(self, trailer, function(state) return state.lid and state.lid.installed end)
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
            T.awaitVehicleState(self, trailer, function(state) return state.lid and state.lid.shown == want end)
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
        T.awaitVehicleState(self, trailer, function(state) return state.lid and state.lid.lockBroken end)
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
            T.awaitVehicleState(self, trailer, function(state) return state.switchOn == on end)
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
