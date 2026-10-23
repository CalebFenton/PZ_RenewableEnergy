-- The mod's chances and random picks. Every one draws on Chance.roll, so a test can set the roll
-- and check either side of a chance instead of rolling it many times.

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

--- A number from `min` up to but not including `max`, any as likely.
function Chance.within(min, max)
    return min + (max - min) * Chance.roll()
end

--- A whole number from `min` to `max`, both included, each as likely.
function Chance.between(min, max)
    return min + math.floor(Chance.roll() * (max - min + 1))
end

--- One of the entries of the non-empty `list`, each as likely.
function Chance.pick(list)
    return list[Chance.between(1, #list)]
end

--- The chance that something with a chance of `perHour` in each hour happens in `hours`.
function Chance.overHours(perHour, hours)
    return 1 - (1 - math.min(1, perHour)) ^ hours
end

--- The chance that storm damage with a chance of `perHour` at the default rate happens in `hours`,
--- at the StormDamage options: none while they turn it off.
function Chance.stormDamage(perHour, hours)
    local options = SandboxVars.RenewableEnergy
    if not options.StormDamage or hours <= 0 then
        return 0
    end
    return Chance.overHours(perHour * options.StormDamageRate / 100, hours)
end
