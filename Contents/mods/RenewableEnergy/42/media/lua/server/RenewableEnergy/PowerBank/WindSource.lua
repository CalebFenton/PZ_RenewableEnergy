-- How a bank runs a wind charger (the "wind" family of RenewableEnergy.Sources) on the authority:
-- its output in the wind and its blades breaking in a gale. Bank.lua calls init, update and status
-- for each wind charger it holds.

if isClient() then return end

require "RenewableEnergy/Specs"
require "RenewableEnergy/Wind"

RenewableEnergy = RenewableEnergy or {}
local Specs, Wind = RenewableEnergy.Specs, RenewableEnergy.Wind

local WindSource = {}
RenewableEnergy.WindSource = WindSource

-- A charger losing more than this share of its watts to shelter says so in the status.
local SHELTERED_LOSS = 0.3

--- Whether a wind charger left running through `hours` of a wind of `kph` breaks its blades, at
--- its kind's chance (Specs.wind.turbines breakPerHour) scaled by the StormDamage options.
local function breaks(source, kph, hours)
    local options = SandboxVars.RenewableEnergy
    local spec = Specs.wind.turbines[source.kind]
    if not options.StormDamage or hours <= 0 or source.braked or source.broken or not Wind.canBreak(spec, kph) then
        return false
    end
    local perHour = spec.breakPerHour * options.StormDamageRate / 100
    return ZombRandFloat(0, 1) < 1 - (1 - math.min(1, perHour)) ^ hours
end

--- A new wind charger's record: its brake and blades as the object has them, and its shelter.
function WindSource.init(source, isoObject)
    source.braked = Wind.isBraked(isoObject)
    source.broken = Wind.isBroken(isoObject)
    source.shelter = Wind.shelterAt(source.x, source.y, source.z)
end

--- The charger's output over the pass, and why it makes nothing or little: braked, broken, calm,
--- furled or sheltered. Its brake is the object's while it is loaded (the brake command sets
--- both); its broken blades are the record's, which a gale may break while the object is
--- unloaded, and go to the object when it is loaded. Its shelter is counted again then, since the
--- trees and buildings around it change.
function WindSource.update(source, object, inSlot, hours, context)
    if object then
        source.braked = Wind.isBraked(object)
        source.shelter = Wind.shelterAt(source.x, source.y, source.z)
    end
    if breaks(source, context.windKph, hours) then
        source.broken = true
    end
    if object and Wind.isBroken(object) ~= (source.broken == true) then
        Wind.setBroken(object, source.broken)
    end
    local spec = Specs.wind.turbines[source.kind]
    local watts = Wind.watts(spec, context.windKph, source.z, source.shelter or 0)
    source.watts = (inSlot and not source.braked and not source.broken) and watts or 0
    if not inSlot then
        source.reason = "noController"
    elseif source.braked then
        source.reason = "braked"
    elseif source.broken then
        source.reason = "broken"
    elseif context.windKph <= spec.cutInKph then
        source.reason = "calm"
    elseif Wind.furled(spec, context.windKph) then
        source.reason = "furled"
    elseif (source.shelter or 0) * Specs.wind.shelterLoss > SHELTERED_LOSS then
        source.reason = "sheltered"
    else
        source.reason = nil
    end
end

--- The charger's part of its status entry: its brake, blades and shelter.
function WindSource.status(entry, source)
    entry.braked, entry.broken = source.braked == true, source.broken == true
    entry.shelterPct = math.floor(100 * (source.shelter or 0) + 0.5)
end

return WindSource
