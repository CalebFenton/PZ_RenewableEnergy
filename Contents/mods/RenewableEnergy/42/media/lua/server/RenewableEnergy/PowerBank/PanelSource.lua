-- How a bank runs a solar panel (the "panel" family of RenewableEnergy.Sources) on the authority:
-- its modules' watts in the sun, snow lying on it, and storms cracking its modules. Bank.lua calls
-- init, update and status for each panel it holds.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"

RenewableEnergy = RenewableEnergy or {}
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local PowerBank, Sources = RenewableEnergy.PowerBank, RenewableEnergy.Sources

local PanelSource = {}
RenewableEnergy.PanelSource = PanelSource

-- Snow cover on a panel, as a share of the panel per hour: falling snow adds it, mild air and
-- sun melt it, and a rack sheds it in sun or mild air.
local SNOW_PER_HOUR = 0.5
local SNOW_MELT_PER_HOUR = 0.1
local SNOW_SUN_MELT_PER_HOUR = 0.05
local RACK_SHED_PER_HOUR = 0.5
local RACK_SHEDS_ABOVE_C = -2
-- Snow this deep shows on the panel's tile.
local SNOW_SHOWN = 0.5
-- A panel making less than this share of what it would in clear full sun names the biggest
-- reason in the status.
local LOW_SHARE = 0.7

local CONDITION_MAX = {}

-- A module type's ConditionMax, from its item script.
local function conditionMax(fullType)
    if not CONDITION_MAX[fullType] then
        local script = getScriptManager():FindItem(fullType)
        CONDITION_MAX[fullType] = script and script:getConditionMax() or 100
    end
    return CONDITION_MAX[fullType]
end

--- The watts a panel's modules are rated for as they are now, and at their best.
local function moduleWatts(source)
    local now, best = 0, 0
    for _, module in ipairs(source.modules) do
        now = now + PowerBank.moduleWatts(module.type, module.condition)
        best = best + PowerBank.moduleWatts(module.type, conditionMax(module.type))
    end
    return now, best
end

-- Cracks and snow draw over a panel's tile; snow lies on the glass, so it draws last.
local isCrackOrSnow = Sprites.matcher(Sprites.cracks, Sprites.snow)

--- Shows a cracked glass over each of a placed panel's modules below Specs.crackedBelow and over
--- none of the others, keeping the snow it shows on top, and sends the overlays to clients if
--- they changed. Authority only: a client's own overlays would be overwritten by the server's next
--- sprite update.
function PanelSource.showCracks(isoObject)
    local kind, facing, material = Sources.kindOf(isoObject)
    if Sources.familyOf(kind) ~= "panel" then return end
    local wanted = Sprites.crackOverlays(kind, facing, material, PowerBank.modulesOf(isoObject, kind))
    local attached = isoObject:getAttachedAnimSprite()
    for i = 0, (attached and attached:size() or 0) - 1 do
        local name = attached:get(i):getName()
        if Sprites.isSnow(name) then
            table.insert(wanted, name)
        end
    end
    RenewableEnergy.showOverlays(isoObject, isCrackOrSnow, wanted)
end

-- Snow cover after `hours` of the weather in `context`.
local function updateSnow(source, hours, context)
    if source.kind == "wall" then
        source.snow = 0
        return
    end
    local snow = source.snow or 0
    if context.weather.snowing then
        snow = snow + SNOW_PER_HOUR * context.precipitation * hours
    end
    if context.airC > 0 then
        snow = snow - SNOW_MELT_PER_HOUR * hours
    end
    local sun = context.irradiance(source.kind, source.facing) / Sun.FULL_SUN
    snow = snow - SNOW_SUN_MELT_PER_HOUR * sun * hours
    if source.kind == "rack" and (context.airC > RACK_SHEDS_ABOVE_C or sun > 0) then
        snow = snow - RACK_SHED_PER_HOUR * hours
    end
    source.snow = math.max(0, math.min(1, snow))
end

-- The snow overlay of the panel's tile; none for an upright wall panel.
local function snowOverlay(source)
    if source.kind == "flat" then
        return Sprites.snow.flat
    end
    local rack = source.kind == "rack" and Sprites.snow.rack[source.material]
    return rack and rack[source.facing]
end

local function showSnow(object, source)
    RenewableEnergy.showOverlay(object, Sprites.isSnow, source.snow >= SNOW_SHOWN and snowOverlay(source) or nil)
end

--- Someone swept the panel `source` (a bank's record), whose object is `object` when loaded.
function PanelSource.clearSnow(source, object)
    source.snow = 0
    if object then
        showSnow(object, source)
    end
end

--- How likely a storm is to crack a module of a mount, relative to Specs.storm.chancePerHour.
local function stormFactor(mount, material)
    local materialSpec = material and Specs.materials[material]
    return Specs.mounts[mount].stormFactor * (materialSpec and materialSpec.stormFactor or 1)
end

--- The hours of a pass of `hours`, ending now, in which a thunderstorm can crack modules: all
--- of them while one blows hard enough, else none.
function PanelSource.stormHours(hours)
    local climate = getClimateManager()
    local storming = climate:getIsThunderStorming() and climate:getWindspeedKph() >= Specs.storm.windMin
    return storming and hours or 0
end

--- A thunderstorm may crack one of a panel's modules (`source`, anything with a mount kind,
--- material and module records). Returns whether it did.
function PanelSource.stormCrack(source, stormHours)
    local options = SandboxVars.RenewableEnergy
    if not options.StormDamage or stormHours <= 0 then
        return false
    end
    local perHour = Specs.storm.chancePerHour * stormFactor(source.kind, source.material) * options.StormDamageRate / 100
    local chance = 1 - (1 - math.min(1, perHour)) ^ stormHours
    local whole = {}
    for _, module in ipairs(source.modules) do
        if module.condition > 0 then
            table.insert(whole, module)
        end
    end
    if #whole == 0 or ZombRandFloat(0, 1) >= chance then
        return false
    end
    local module = whole[ZombRand(#whole) + 1]
    module.condition = math.max(0, module.condition - Specs.storm.crack)
    return true
end

-- Keep a panel's module record and the bank's copy the same: a crack while the panel's square
-- was unloaded goes to the object, otherwise the object (which unmounting and repairs change)
-- is the truth. Either way the tile shows the cracks the record now holds.
local function syncModules(source, object)
    if source.modulesChanged then
        PowerBank.writeModules(object, source.modules)
        source.modulesChanged = nil
    else
        source.modules = PowerBank.modulesOf(object, source.kind)
    end
    PanelSource.showCracks(object)
end

-- Why a panel makes less than it would at its best in clear full sun: the biggest loss, if it
-- is big enough to matter. On a tie the first reason checked wins.
local function lowReason(source, inSlot, light, clearLight, condition, context)
    if not inSlot then
        return "noController"
    elseif context.elevation <= 0 or clearLight <= 0 then
        return "night"
    end
    local reason, lowest = nil, LOW_SHARE
    local share = 1 - source.snow
    if share < lowest then reason, lowest = "snow", share end
    share = light / clearLight
    if share < lowest then reason, lowest = "cloud", share end
    share = clearLight / Sun.FULL_SUN
    if share < lowest then reason, lowest = "angle", share end
    if condition < lowest then reason = "cracked" end
    return reason
end

--- A new panel's record: its mount's facing and material, no snow, and the modules it holds.
function PanelSource.init(source, isoObject, facing, material)
    source.facing, source.material, source.snow = facing, material, 0
    source.modules = PowerBank.modulesOf(isoObject, source.kind)
end

--- The panel's output over the pass, and why it is low.
function PanelSource.update(source, object, inSlot, hours, context)
    if PanelSource.stormCrack(source, context.stormHours) then
        source.modulesChanged = true
    end
    if object then
        syncModules(source, object)
    end
    updateSnow(source, hours, context)
    if object then
        showSnow(object, source)
    end
    local light = context.irradiance(source.kind, source.facing)
    local clearLight = context.clearIrradiance(source.kind, source.facing)
    local now, best = moduleWatts(source)
    source.watts = inSlot and Sun.wattsFrom(now, light, source.snow) or 0
    source.fullSunPct = math.floor(100 * light * (1 - source.snow) / Sun.FULL_SUN + 0.5)
    source.reason = lowReason(source, inSlot, light, clearLight, best > 0 and now / best or 0, context)
end

--- The panel's part of its status entry: its mount, light, snow and modules.
function PanelSource.status(entry, source)
    local modules = {}
    for _, module in ipairs(source.modules) do
        table.insert(modules, { type = module.type, condition = module.condition })
    end
    entry.material, entry.facing, entry.fullSunPct = source.material, source.facing, source.fullSunPct or 0
    entry.snow, entry.modules = source.snow or 0, modules
end

return PanelSource
