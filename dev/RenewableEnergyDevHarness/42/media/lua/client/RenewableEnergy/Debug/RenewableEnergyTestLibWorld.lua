require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Fixtures of the world, arrow board and loot tests. What they build and read lives on the
-- authority, so they go through the dev mod's server handlers (RenewableEnergyTestServer*.lua).
-- Those load after client Lua, even on a multiplayer client, so the trailer readers are required
-- when a test runs.

local T = RenewableEnergyTest

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

--- Queues reading the server's state of the vehicle until `done(state)` holds or `ms` real
--- milliseconds pass, for what a client's action changes there later.
function T.awaitVehicleState(self, vehicle, done, ms)
    T.serverUntil(self, "arrowBoardState", function() return T.vehicleArgs(vehicle) end,
        function(reply) return done(reply.state) end, ms)
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

-- Spawns ----------------------------------------------------------------------------------------

--- Whether `value` lies in `range` ({ min, max }), both ends included.
function T.inRange(value, range)
    return value >= range.min and value <= range.max
end

--- Expects every charge of `charges` to be one a found battery holds (Specs.foundCharge).
function T.expectFoundCharges(charges, what)
    local range = RenewableEnergy.Specs.foundCharge
    for _, charge in ipairs(charges) do
        T.expect(T.inRange(charge, range), what .. " holds a battery at " .. charge .. ", expected " .. range.min .. " to "
            .. range.max)
    end
end

return T
