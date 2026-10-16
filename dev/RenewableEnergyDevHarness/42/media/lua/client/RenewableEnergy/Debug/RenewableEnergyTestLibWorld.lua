require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Fixtures of the world, trailer, tile and loot tests, added to RenewableEnergyTest. What they build
-- and read lives on the authority, so they go through the dev mod's server handlers in
-- server/RenewableEnergy/Debug/RenewableEnergyTestServer*.lua, which single player runs in this
-- game. Those files load after client Lua, on a multiplayer client as well, so the trailer
-- readers are required when a test runs.

local T = RenewableEnergyTest

local function trailer()
    return require "RenewableEnergy/Debug/RenewableEnergyTestServerTrailer"
end

--- Expects a server check's answer ({ failures = { message, ... } }) to have found nothing wrong.
function T.expectNoFailures(answer)
    for _, failure in ipairs(answer and answer.failures or { "the check never answered" }) do
        T.expect(false, failure)
    end
end

--- Registers a test that runs the server check `name` with `args`, under the sandbox options
--- `sandbox` if given, and expects it to find nothing wrong.
function T.serverCheck(testName, name, args, sandbox)
    T.test(testName, {
        sandbox = sandbox,
        run = function(self) T.server(self, name, args) end,
        validate = function(self) T.expectNoFailures(self.server[name]) end,
    })
end

-- Vehicles ----------------------------------------------------------------------------------------
-- A vehicle is a T.placeVehicle handle, spawned by the authority, which the trailer server file's
-- Trailer.spawnVehicle (the `spawnVehicle` setting) spawns as the world does when `args.stocked`,
-- and whole when `args.repair`. The handlers find it by T.vehicleArgs (RenewableEnergyTestLib.lua).

--- Queues the server handler `name` on the vehicle with `args` (a table, or a function returning
--- one when the call goes out) and leaves its answer in vehicle.answer and, if it holds one, the
--- server's state of the vehicle (see Trailer.vehicleState in RenewableEnergyTestServerTrailer.lua)
--- in vehicle.state.
function T.onVehicle(self, vehicle, name, args)
    local function allArgs()
        local all = T.vehicleArgs(vehicle)
        for key, value in pairs(type(args) == "function" and args() or args or {}) do
            all[key] = value
        end
        return all
    end
    -- Queued once the vehicle is placed, the call can go out ahead of its turn (T.server, T.batch).
    T.server(self, name, (vehicle.id and type(args) ~= "function") and allArgs() or allArgs)
    T.step(function()
        vehicle.answer = self.server[name]
        vehicle.state = vehicle.answer.state or vehicle.state
    end)
end

--- Queues reading the server's state of the vehicle into vehicle.state.
function T.vehicleState(self, vehicle)
    T.onVehicle(self, vehicle, "vehicleState")
end

--- Queues reading the server's state of the vehicle again and again until `done(state)` holds or
--- `ms` real milliseconds pass, for what a client's action or command changes there later; leaves
--- the last state read in vehicle.state.
function T.awaitVehicleState(self, vehicle, done, ms)
    T.serverUntil(self, "vehicleState", function() return T.vehicleArgs(vehicle) end,
        function(reply) return done(reply.state) end, ms)
    T.step(function() vehicle.state = self.server.vehicleState.state end)
end

--- This side's state of its copy of the vehicle, as Trailer.vehicleState reads it.
function T.copyState(vehicle)
    return trailer().vehicleState(vehicle.vehicle)
end

--- How this game draws the lid of its copy of the trailer, as Trailer.lidPose reads it.
function T.lidPose(vehicle)
    return trailer().lidPose(vehicle.vehicle)
end

--- Queues a wait, as long as a fixture's, until this side's copy of the vehicle matches
--- `matches(state)`, its state as T.copyState reads it; fails the test as missing `what` if it
--- never does.
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
