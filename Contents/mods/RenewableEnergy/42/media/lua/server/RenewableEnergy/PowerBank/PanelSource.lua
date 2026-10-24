-- How a bank runs a solar panel (the "panel" family of RenewableEnergy.Sources) on the authority:
-- its modules' watts in the sun, snow lying on it, and storms cracking its modules. The one
-- writer of a placed panel's module record (PowerBank.MODULES) and of its crack and snow overlays.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Chance"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/StormNotice"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"

RenewableEnergy = RenewableEnergy or {}
local Chance, Specs, Sprites, Sun = RenewableEnergy.Chance, RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local StormNotice = RenewableEnergy.StormNotice
local PowerBank, Sources = RenewableEnergy.PowerBank, RenewableEnergy.Sources

local PanelSource = {}
RenewableEnergy.PanelSource = PanelSource

-- Snow cover on a panel, as a share of the panel per hour: falling snow adds it, mild air and
-- sun melt it, and a mount that sheds snow (Specs.mounts shedsSnow) sheds it in sun or mild air.
local SNOW_PER_HOUR = 0.5
local SNOW_MELT_PER_HOUR = 0.1
local SNOW_SUN_MELT_PER_HOUR = 0.05
local SHED_PER_HOUR = 0.5
local SHEDS_ABOVE_C = -2
-- Snow this deep shows on the panel's tile.
local SNOW_SHOWN = 0.5
-- A panel making less than this share of what it would in clear full sun names the biggest
-- reason in the status.
local LOW_SHARE = 0.7

-- The watts a panel's modules are rated for as they are now, and at their best.
local function ratedWatts(source)
    local now, best = 0, 0
    for _, module in ipairs(source.modules) do
        now = now + PowerBank.moduleWatts(module.type, module.condition)
        best = best + PowerBank.moduleWatts(module.type, RenewableEnergy.conditionMaxOf(module.type))
    end
    return now, best
end

--- Records `modules` on a placed panel and sends the record to clients.
function PanelSource.writeModules(isoObject, modules)
    isoObject:getModData()[PowerBank.MODULES] = PowerBank.copyModules(modules)
    isoObject:transmitModData()
end

-- Cracks and snow draw over a panel's tile; snow lies on the glass, so it draws last.
local isCrackOrSnow = Sprites.matcher(Sprites.cracks, Sprites.snow)

-- Shows the cracks of `modules` on the panel `isoObject` of kind, facing and material, keeping the
-- snow it shows on top.
local function showCracksOf(isoObject, kind, facing, material, modules)
    local wanted = Sprites.crackOverlays(kind, facing, material, modules)
    local attached = isoObject:getAttachedAnimSprite()
    for i = 0, (attached and attached:size() or 0) - 1 do
        local name = attached:get(i):getName()
        if Sprites.isSnow(name) then
            table.insert(wanted, name)
        end
    end
    RenewableEnergy.showOverlays(isoObject, isCrackOrSnow, wanted)
end

--- Shows each of a placed panel's modules' cracked glass, light or heavy as
--- RenewableEnergy.crackLookOf has it, and none over the others, keeping the snow it shows on
--- top, and sends the overlays to clients if they changed. Does nothing for an object that is no panel.
function PanelSource.showCracks(isoObject)
    local kind, facing, material = Sources.kindOf(isoObject)
    if Sources.familyOf(kind) ~= "panel" then return end
    showCracksOf(isoObject, kind, facing, material, PowerBank.modulesOf(isoObject, kind))
end

-- Snow cover after `hours` of the weather in `context`.
local function updateSnow(source, hours, context)
    local mount = Specs.mounts[source.kind]
    if not mount.holdsSnow then
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
    if mount.shedsSnow and (context.airC > SHEDS_ABOVE_C or sun > 0) then
        snow = snow - SHED_PER_HOUR * hours
    end
    source.snow = math.max(0, math.min(1, snow))
end

local function showSnow(object, source)
    local shown = source.snow >= SNOW_SHOWN and Sprites.snowOverlay(source.kind, source.facing, source.material) or nil
    RenewableEnergy.showOverlay(object, Sprites.isSnow, shown)
end

--- Someone swept the panel `source` (a bank's record), whose object is `object` when loaded.
function PanelSource.clearSnow(source, object)
    source.snow = 0
    if object then
        showSnow(object, source)
    end
end

-- A mount's stormShare (Specs.storm), times its material's.
local function stormShare(mount, material)
    local materialSpec = material and Specs.materials[material]
    return Specs.mounts[mount].stormShare * (materialSpec and materialSpec.stormShare or 1)
end

--- The hours of a pass of `hours`, ending now, in which a thunderstorm can crack modules: all
--- of them while one blows hard enough, else none.
function PanelSource.stormHours(hours)
    local climate = getClimateManager()
    local storming = climate:getIsThunderStorming() and climate:getWindspeedKph() >= Specs.storm.panelKph
    return storming and hours or 0
end

--- The chance that `stormHours` of thunderstorm crack a module of `source` (anything with a mount
--- kind and material), at the StormDamage options.
function PanelSource.stormChance(source, stormHours)
    return Chance.stormDamage(Specs.storm.panelPerHour * stormShare(source.kind, source.material), stormHours)
end

--- A thunderstorm may crack one of a panel's modules (`source`, anything with a mount kind,
--- material and module records). Returns whether it did.
function PanelSource.stormCrack(source, stormHours)
    local chance = PanelSource.stormChance(source, stormHours)
    if chance <= 0 then
        return false
    end
    local whole = {}
    for _, module in ipairs(source.modules) do
        if module.condition > 0 then
            table.insert(whole, module)
        end
    end
    if #whole == 0 or not Chance.hit(chance) then
        return false
    end
    local module = Chance.pick(whole)
    module.condition = math.max(0, module.condition - Specs.storm.crack)
    return true
end

--- Keeps a panel's module record and the bank's copy `source` the same: a crack while the
--- panel's square was unloaded goes to the object, otherwise the object (which unmounting and
--- repairs change) is the truth. Either way the tile shows the cracks the record now holds.
function PanelSource.syncModules(source, object)
    if source.modulesChanged then
        PanelSource.writeModules(object, source.modules)
        source.modulesChanged = nil
    else
        source.modules = PowerBank.modulesOf(object, source.kind)
    end
    showCracksOf(object, source.kind, source.facing, source.material, source.modules)
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

--- A newly connected panel's record: its mount's facing and material, no snow, and the modules
--- it holds. Each module teaches a little the first time it is ever connected, and the module
--- record keeps that, through moves between banks and with the module when it comes off its mount.
function PanelSource.connect(player, source, isoObject, facing, material)
    local modules = PowerBank.modulesOf(isoObject, source.kind)
    local learned = 0
    for _, module in ipairs(modules) do
        if not module.connected then
            module.connected = true
            learned = learned + 1
        end
    end
    if learned > 0 then
        PanelSource.writeModules(isoObject, modules)
        addXp(player, Perks.Electricity, Specs.connectXp * learned)
    end
    source.facing, source.material, source.snow, source.modules = facing, material, 0, modules
end

--- The panel's output over the pass, and why it is low. A storm cracking a module tells the
--- players in earshot (StormNotice).
function PanelSource.update(source, object, inSlot, hours, context)
    if PanelSource.stormCrack(source, context.stormHours) then
        source.modulesChanged = true
        StormNotice.tell(StormNotice.MODULE, source.x, source.y, source.z)
    end
    if object then
        PanelSource.syncModules(source, object)
    end
    updateSnow(source, hours, context)
    if object then
        showSnow(object, source)
    end
    local light = context.irradiance(source.kind, source.facing)
    local clearLight = context.clearIrradiance(source.kind, source.facing)
    local now, best = ratedWatts(source)
    source.watts = inSlot and Sun.wattsFrom(now, light, source.snow) or 0
    source.fullSunPct = round(100 * light * (1 - source.snow) / Sun.FULL_SUN)
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
