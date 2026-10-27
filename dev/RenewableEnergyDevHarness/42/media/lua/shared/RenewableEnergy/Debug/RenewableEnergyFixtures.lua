-- Development only, not published. States of the mod's things that both the tests and the promo
-- shots set, so that a new saved field is added in one place.

require "RenewableEnergy/Biogas/Digester"

local Fixtures = {}

--- Saved fields of a started, mature digester of tier `tier`, past its startup and settled down,
--- holding its tier's potential cap, with `fields`' fields over them.
function Fixtures.matureDigester(tier, fields)
    local state = { fed = true, started = true, gasHours = 1000, potential = RenewableEnergy.Digester.TIERS[tier].potentialCap,
        temp = 30, acid = 0, sour = false, sludge = 0 }
    for key, value in pairs(fields or {}) do
        state[key] = value
    end
    return state
end

return Fixtures
