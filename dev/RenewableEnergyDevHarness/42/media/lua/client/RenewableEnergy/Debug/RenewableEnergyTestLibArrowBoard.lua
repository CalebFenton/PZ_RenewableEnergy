require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Specs"

-- Fixtures of the arrow board tests (RenewableEnergyTestsArrowBoard*.lua), added to
-- RenewableEnergyTest. The trailer's state lives on the authority, so they go through the dev
-- mod's server handlers (RenewableEnergyTestServerTrailer.lua). Those load after client Lua, even
-- on a multiplayer client, so the trailer readers are required when a test runs.

local T = RenewableEnergyTest
local player = T.player

local MODULE = RenewableEnergy.Specs.factoryModule

local function trailer()
    return require "RenewableEnergy/Debug/RenewableEnergyTestServerTrailer"
end

-- Vehicles ----------------------------------------------------------------------------------------
-- A vehicle is a T.placeVehicle handle, spawned by the authority through Trailer.spawnVehicle,
-- stocked as the world spawns it when `args.stocked` and whole when `args.repair`.

--- Queues reading the server's state of the vehicle into vehicle.state.
function T.vehicleState(self, vehicle)
    T.onVehicle(self, vehicle, "arrowBoardState")
end

--- Queues reading the server's state of the vehicle until `done(state)` holds, for what a
--- client's action changes there later.
function T.awaitVehicleState(self, vehicle, done)
    T.serverUntil(self, "arrowBoardState", function() return T.vehicleArgs(vehicle) end,
        function(reply) return done(reply.state) end)
    T.step(function() vehicle.state = self.server.arrowBoardState.state end)
end

--- This side's state of its copy of the vehicle, as Trailer.vehicleState reads it.
function T.copyState(vehicle)
    return trailer().vehicleState(vehicle.vehicle)
end

--- How this game draws the lid of its copy of the trailer, as Trailer.lidPose reads it.
function T.lidPose(vehicle)
    return trailer().lidPose(vehicle.vehicle)
end

--- Queues a wait until this side's copy of the vehicle matches `matches(state)`; fails the test
--- as missing `what` if it never does.
function T.waitForVehicleCopy(self, vehicle, matches, what)
    T.waitFor(self, function() return vehicle.vehicle ~= nil and matches(T.copyState(vehicle)) end, what)
end

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

-- ArrowBoard.PANELS's ids, copied for the reason T.lidOf gives.
T.BOARD_PANELS = { "RenewableEnergyPanelLeft", "RenewableEnergyPanelRight" }
local LEFT, RIGHT = T.BOARD_PANELS[1], T.BOARD_PANELS[2]

-- ArrowBoard.lua is a server file, loaded after this one, so part ids are read at run time.
function T.lidOf(vehicle)
    return vehicle:getPartById(RenewableEnergy.ArrowBoard.LID)
end

function T.boxOf(vehicle)
    return vehicle:getPartById(RenewableEnergy.ArrowBoard.BATTERY_BOX)
end

-- Queues an arrow board on open ground near the character, spawned with `args` and facing `facing`
-- (default north). Leaves its T.placeVehicle handle in self.trailer and returns it.
function T.spawnTrailer(self, args, facing)
    local square = T.need(self, openStrip(TRAILER_AHEAD, TRAILER_BEHIND), "open ground for the arrow board")
    self.trailer = square and T.placeVehicle(self, RenewableEnergy.ArrowBoard.SCRIPT, { square = square, args = args, facing = facing })
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
    for _, id in ipairs(T.BOARD_PANELS) do
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
    return { [LEFT] = { type = MODULE, condition = condition }, [RIGHT] = { type = MODULE, condition = condition } }
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
