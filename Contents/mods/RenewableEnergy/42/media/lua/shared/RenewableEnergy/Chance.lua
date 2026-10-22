-- The mod's yes-or-no chances. Every chance goes through Chance.hit, so a test can set the roll
-- and check either side of the chance instead of rolling it many times.

RenewableEnergy = RenewableEnergy or {}
local Chance = {}
RenewableEnergy.Chance = Chance

--- A roll, 0 up to but not including 1.
function Chance.roll()
    return ZombRandFloat(0, 1)
end

--- Whether a chance of `chance` (0 to 1) comes up: a roll below it.
function Chance.hit(chance)
    return Chance.roll() < chance
end
