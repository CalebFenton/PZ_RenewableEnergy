-- Development only, not published. States of the mod's things that both the tests and the promo
-- shots set, so that a new saved field is added in one place.

local Battery = require "RenewableEnergy/PowerBank/Battery"
local Digester = require "RenewableEnergy/Biogas/Digester"

local Fixtures = {}

--- Saved fields of a started, mature digester of tier `tier`, past its startup and settled down,
--- holding its tier's potential cap, with `fields`' fields over them.
function Fixtures.matureDigester(tier, fields)
    local state = { fed = true, started = true, gasHours = 1000, potential = Digester.TIERS[tier].potentialCap,
        temp = 30, acid = 0, sour = false, sludge = 0 }
    for key, value in pairs(fields or {}) do
        state[key] = value
    end
    return state
end

--- A working bank of tile `sprite` on `square` (BankSystem.place), its container holding `items`
--- (full types) put straight in, as world spawns stock a bank, each battery at `charge`. Authority
--- only.
function Fixtures.placeBank(square, sprite, items, charge)
    -- A server module, which loads after this file.
    local BankSystem = require "RenewableEnergy/PowerBank/BankSystem"
    return BankSystem.place(square, sprite, nil, function(container)
        for _, fullType in ipairs(items) do
            local item = container:AddItem(fullType)
            if item and Battery.isBattery(item) then
                Battery.setCharge(item, charge)
            end
        end
    end)
end

return Fixtures
