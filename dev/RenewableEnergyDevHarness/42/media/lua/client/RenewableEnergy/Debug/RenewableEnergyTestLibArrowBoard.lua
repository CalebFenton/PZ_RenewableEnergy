require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Trailer"

-- Fixtures of the arrow board tests. The trailer's state lives on the authority, so they go
-- through RenewableEnergyTestServerTrailer.lua.

local T = RenewableEnergyTest
local player = T.player

-- A vehicle is a T.placeVehicle handle, spawned by the authority through the spawnVehicle setting,
-- stocked as the world spawns it when `args.stocked` and whole when `args.repair`.

--- Queues reading the server's state of the vehicle until `done(state)` holds, for what a
--- client's action changes there later; the answer goes in self.reads[label or "vehicleState"].
function T.awaitVehicleState(self, vehicle, done, label)
    label = label or "vehicleState"
    T.readUntil(self, "vehicleState", function() return T.at(vehicle, { id = vehicle.id }) end, label,
        function(reply) return done(reply.state) end)
    T.step(function() vehicle.state = self.reads[label].state end)
end

--- This side's state of its copy of the vehicle, as the server reads its own (Kinds.vehicleState).
function T.copyState(vehicle)
    return Kinds.vehicleState(vehicle.vehicle)
end

--- How this game draws the lid of its copy of the trailer (Kinds.lidPose).
function T.lidPose(vehicle)
    return Kinds.lidPose(vehicle.vehicle)
end

--- Queues a wait until this side's copy of the vehicle matches `matches(state)`; fails the test
--- as missing `what` if it never does.
function T.waitForVehicleCopy(self, vehicle, matches, what)
    T.waitFor(self, function() return vehicle.vehicle ~= nil and matches(T.copyState(vehicle)) end, what)
end

-- The squares an arrow board takes north and south of its centre.
local TRAILER_AHEAD, TRAILER_BEHIND = 3, 3

-- Ground a trailer can stand on: outdoors, with nothing on it that blocks, whatever else lies there.
local function isTrailerGround(x, y, z)
    local square = getSquare(x, y, z)
    return square ~= nil and square:isOutside() and square:isFree(false) and not square:HasTree()
        and square:getVehicleContainer() == nil
end

-- Whether open ground runs three squares across around `square`, TRAILER_AHEAD north to
-- TRAILER_BEHIND south.
local function stripOpen(square)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for sx = x - 1, x + 1 do
        for sy = y - TRAILER_AHEAD, y + TRAILER_BEHIND do
            if not isTrailerGround(sx, sy, z) then
                return false
            end
        end
    end
    return true
end

local LEFT, RIGHT = ArrowBoard.PANELS[1], ArrowBoard.PANELS[2]

-- Queues an arrow board on open ground near the character, spawned with `args` and facing `facing`
-- (default north). Leaves its T.placeVehicle handle in self.trailer and returns it.
function T.spawnTrailer(self, args, facing)
    -- Far enough that the strip never covers the character.
    local square = T.square(self, { accept = stripOpen, minDistance = math.max(TRAILER_AHEAD, TRAILER_BEHIND) + 1 },
        "open ground for the arrow board")
    self.trailer = square and T.placeVehicle(self, ArrowBoard.SCRIPT, { square = square, args = args, facing = facing })
    return self.trailer
end

-- Queues `fn`'s calls in one T.batch once the trailer is placed.
function T.batchOnTrailer(fn)
    T.step(function() T.batch(fn) end)
end

function T.panelCondition(state, partId)
    local panel = state and state.panels[partId]
    return panel and panel.installed and panel.condition or nil
end

function T.panelShown(state, partId)
    local panel = state and state.panels[partId]
    return panel and panel.shown or "?"
end

-- Whether two states show the same panels: modules, conditions and models.
local function samePanels(a, b)
    for _, id in ipairs(ArrowBoard.PANELS) do
        if T.panelCondition(a, id) ~= T.panelCondition(b, id) or T.panelShown(a, id) ~= T.panelShown(b, id) then
            return false
        end
    end
    return true
end

-- Queues a wait until this client's copy shows the panels of the server's last state.
function T.waitForPanelsCopy(self, trailer)
    T.waitForVehicleCopy(self, trailer, function(copy) return samePanels(copy, trailer.state) end,
        "this client's copy of the trailer's panels")
end

function T.boxItems(state, fullType)
    local items = {}
    for _, item in ipairs(state and state.box and state.box.items or {}) do
        if not fullType or item.type == fullType then
            table.insert(items, item)
        end
    end
    return items
end

-- setTrailer's `panels` with a factory module at `condition` on each panel.
function T.modulesOnBothPanels(condition)
    return { [LEFT] = { type = T.FACTORY_MODULE, condition = condition },
        [RIGHT] = { type = T.FACTORY_MODULE, condition = condition } }
end

-- Puts the character at the middle of the vehicle's `area` (or `toSide` squares toward its side),
-- facing it, where vanilla's walk to the area ends, so a queued action neither walks nor turns.
function T.standIn(vehicle, area, toSide)
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

return T
