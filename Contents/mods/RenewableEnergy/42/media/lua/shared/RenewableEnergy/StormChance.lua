-- The chances of storm damage, at the save's Storm Damage options. They are odds rather than draws:
-- the draws that test them are cf_commonlib's Chance, whose roll a test can set.

local Specs = require "RenewableEnergy/Specs"
local Chance = require "cf_commonlib/Chance"

local StormChance = {}

--- The chance that storm damage with a chance of `perHour` at the default rate happens in `hours`,
--- at the StormDamage options: none while they turn it off.
function StormChance.stormDamage(perHour, hours)
    local options = SandboxVars.RenewableEnergy
    if not options.StormDamage or hours <= 0 then
        return 0
    end
    return Chance.overHours(perHour * options.StormDamageRate / 100, hours)
end

-- The hourly chance that the game's strongest wind breaks the weakest blades (Specs.storm).
local WORST_PER_HOUR = 1 - (1 - Specs.storm.worstChance) ^ (1 / Specs.storm.worstHours)

--- How hard a wind of `kph` blows on blades it starts to break above `fromKph`, as a share of the
--- hourly chance at the game's strongest wind: none up to `fromKph`, then the square of the way
--- from there to Specs.storm.fullKph, and all of it from there on.
function StormChance.stormStrength(fromKph, kph)
    if kph <= fromKph then
        return 0
    end
    return math.min(1, (kph - fromKph) / (Specs.storm.fullKph - fromKph)) ^ 2
end

--- The hourly chance, at the default Storm Damage Rate and the game's strongest wind, that blades
--- with `share` of the weakest blades' chance break (Specs.storm).
function StormChance.stormPerHour(share)
    return WORST_PER_HOUR * share
end

return StormChance
