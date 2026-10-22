-- How a bank runs a wind charger (the "wind" family of RenewableEnergy.Sources) on the authority:
-- its output in the wind and its blades breaking in a gale. The one writer of a charger's brake
-- and broken blades, on the object and on its bank's record alike.

if isClient() then return end

require "RenewableEnergy/Chance"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Wind"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"

RenewableEnergy = RenewableEnergy or {}
local Chance, Specs, Wind = RenewableEnergy.Chance, RenewableEnergy.Specs, RenewableEnergy.Wind
local PowerBank, Sources = RenewableEnergy.PowerBank, RenewableEnergy.Sources

local WindSource = {}
RenewableEnergy.WindSource = WindSource

-- A charger losing more than this share of its watts to shelter says so in the status.
local SHELTERED_LOSS = 0.3

local function setFlag(isoObject, key, on)
    isoObject:getModData()[key] = on or nil
    isoObject:transmitModData()
end

--- Sets the brake of the wind charger `isoObject`, and of `source`, its bank's record, if it feeds
--- one (else nil).
function WindSource.setBraked(isoObject, braked, source)
    setFlag(isoObject, Wind.BRAKED, braked)
    if source then
        source.braked = braked
    end
end

--- Marks the blades of the wind charger `isoObject` broken or whole, and of `source`, its bank's
--- record, if it feeds one (else nil).
function WindSource.setBroken(isoObject, broken, source)
    setFlag(isoObject, Wind.BROKEN, broken)
    if source then
        source.broken = broken
    end
end

--- The chance that a wind charger left running through `hours` of a wind of `kph` breaks its
--- blades, at its kind's chance (Specs.wind.turbines breakPerHour) scaled by the StormDamage
--- options: none while braked or broken already.
function WindSource.breakChance(source, kph, hours)
    local options = SandboxVars.RenewableEnergy
    local spec = Specs.wind.turbines[source.kind]
    if not options.StormDamage or hours <= 0 or source.braked or source.broken or not Wind.canBreak(spec, kph) then
        return 0
    end
    local perHour = spec.breakPerHour * options.StormDamageRate / 100
    return 1 - (1 - math.min(1, perHour)) ^ hours
end

-- No roll when the blades can't break, so a test's set rolls go only to chances that can come up.
local function breaks(source, kph, hours)
    local chance = WindSource.breakChance(source, kph, hours)
    return chance > 0 and Chance.hit(chance)
end

--- A newly connected wind charger's record: its brake and blades as the object has them, and its
--- shelter. A charger teaches its wiring the first time a player connects it; the world wires a
--- site's charger with no player (SolarSites), which leaves the lesson to the one who rewires it.
function WindSource.connect(player, source, isoObject)
    source.braked = Wind.isBraked(isoObject)
    source.broken = Wind.isBroken(isoObject)
    source.shelter = Wind.shelterAt(source.x, source.y, source.z)
    if player and not isoObject:getModData()[PowerBank.CONNECTED_ONCE] then
        setFlag(isoObject, PowerBank.CONNECTED_ONCE, true)
        addXp(player, Perks.Electricity, Specs.connectXp * Sources.slotsOf(source.kind))
    end
end

--- The charger's output over the pass, and why it makes nothing or little: braked, broken, calm,
--- furled or sheltered. Its brake is the object's while it is loaded (setBraked sets both); its
--- broken blades are the record's, which a gale may break while the object is unloaded, and go to
--- the object when it is loaded. Its shelter is counted again then, since trees, buildings and
--- walls around it change.
function WindSource.update(source, object, inSlot, hours, context)
    if object then
        source.braked = Wind.isBraked(object)
        source.shelter = Wind.shelterAt(source.x, source.y, source.z)
    end
    if breaks(source, context.windKph, hours) then
        source.broken = true
    end
    if object and Wind.isBroken(object) ~= (source.broken == true) then
        setFlag(object, Wind.BROKEN, source.broken)
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
    entry.shelterPct = round(100 * (source.shelter or 0))
end

return WindSource
