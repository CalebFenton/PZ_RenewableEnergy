require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local Battery = require "RenewableEnergy/PowerBank/Battery"

-- Fixtures of the world and loot tests. What they build and read lives on the authority, so they
-- go through the dev mod's server handlers (RenewableEnergyTestServer*.lua); the harness's
-- visits (T.startVisits) take the character to the far places they read.

local T = RenewableEnergyTest

--- Whether `value` lies in `range` ({ min, max }), both ends included, as the server's handlers
--- judge it (RenewableEnergyTestKinds).
T.inRange = Kinds.inRange

--- Expects every charge of `charges` to be one a found battery holds (Battery.FOUND_CHARGE).
function T.expectFoundCharges(charges, what)
    local range = Battery.FOUND_CHARGE
    for _, charge in ipairs(charges) do
        T.expect(T.inRange(charge, range), what .. " holds a battery at " .. charge .. ", expected " .. range.min .. " to "
            .. range.max)
    end
end

--- Expects a count range read from the authority to be one a player can meet: at least one, and
--- no more at its low end than at its high. The test checks spawns against it.
function T.expectSaneRange(range, what)
    T.expect(range.min >= 1 and range.min <= range.max, what .. " runs from " .. range.min .. " to " .. range.max)
end

return T
