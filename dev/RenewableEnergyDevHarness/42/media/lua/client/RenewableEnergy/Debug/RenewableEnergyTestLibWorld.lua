require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local Battery = require "RenewableEnergy/PowerBank/Battery"

-- Fixtures of the world and loot tests.

local T = RenewableEnergyTest

T.inRange = Kinds.inRange

--- Expects every charge of `charges` to be one a found battery holds (Battery.FOUND_CHARGE).
function T.expectFoundCharges(charges, what)
    local range = Battery.FOUND_CHARGE
    for _, charge in ipairs(charges) do
        T.expect(T.inRange(charge, range), what .. " holds a battery at " .. charge .. ", expected " .. range.min .. " to "
            .. range.max)
    end
end

return T
