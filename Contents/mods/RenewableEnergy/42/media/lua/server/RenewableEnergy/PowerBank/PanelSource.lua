-- How a bank runs a solar panel (the "panel" family of Sources) on the authority:
-- its modules' watts in the sun, snow lying on it, and storms cracking its modules (PanelStorms),
-- connected or loose. The one writer of a placed panel's module record (Panel.MODULES_KEY) and of
-- its crack and snow overlays.

if isClient() then return end

local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local StormNotice = require "RenewableEnergy/StormNotice"
local Sun = require "RenewableEnergy/Sun"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local PanelStorms = require "RenewableEnergy/PowerBank/PanelStorms"
local Items = require "cf_commonlib/Items"
local PlaceTracker = require "cf_commonlib/PlaceTracker"
local Tiles = require "cf_commonlib/Tiles"

local PanelSource = {}

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
        now = now + Panel.moduleWatts(module.type, module.condition)
        best = best + Panel.moduleWatts(module.type, Items.conditionMaxOf(module.type))
    end
    return now, best
end

--- Commits detached `modules` to a placed panel and its cracks, and adopts them in `source` when
--- connected. The object's copy stays independent of the bank's simulated module records.
function PanelSource.writeModules(isoObject, modules, source)
    isoObject:getModData()[Panel.MODULES_KEY] = Panel.copyModules(modules)
    if source then
        source.modules, source.modulesChanged = modules, nil
    end
    isoObject:transmitModData()
    PanelSource.showCracks(isoObject, modules)
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
    Tiles.showOverlays(isoObject, isCrackOrSnow, wanted)
end

--- Shows each of a placed panel's modules' cracked glass, light or heavy as
--- ModuleRepair.crackLookOf has it, and none over the others, keeping the snow it shows on
--- top, and sends the overlays to clients if they changed. Does nothing for an object that is no panel.
function PanelSource.showCracks(isoObject, modules)
    local kind, facing, material = Sources.kindOf(isoObject)
    if Sources.familyOf(kind) ~= "panel" then return end
    showCracksOf(isoObject, kind, facing, material, modules or Panel.modulesOf(isoObject, kind))
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
    Tiles.showOverlay(object, Sprites.isSnow, shown)
end

--- Someone swept the panel `source` (a bank's record), whose object is `object` when loaded.
function PanelSource.clearSnow(source, object)
    source.snow = 0
    if object then
        showSnow(object, source)
    end
end

--- Keeps a panel's module record and the bank's copy `source` the same: a crack while the
--- panel's square was unloaded goes to the object, otherwise the object (which unmounting and
--- repairs change) is the truth. Either way the tile shows the cracks the record now holds.
function PanelSource.reconcile(source, object)
    if source.modulesChanged then
        PanelSource.writeModules(object, source.modules, source)
        return
    end
    source.modules = Panel.modulesOf(object, source.kind)
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

--- A newly connected panel's record: its mount's facing and material, no snow, the modules it
--- holds, and the storms it weathered loose (PanelStorms.toRecord). Each module teaches a little
--- the first time it is ever connected, and the module record keeps that, through moves between
--- banks and with the module when it comes off its mount.
function PanelSource.connect(player, source, isoObject, facing, material)
    local modules = Panel.modulesOf(isoObject, source.kind)
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
    PanelStorms.toRecord(source, isoObject)
end

--- The panel left its bank: its object, if still there, weathers on loose from where the record
--- left off.
function PanelSource.disconnect(source, object)
    if object then
        PanelStorms.toObject(source, object)
    end
end

--- The panel's output over the pass, and why it is low. A storm cracking a module tells the
--- players in earshot (StormNotice).
function PanelSource.update(source, object, inSlot, hours, context)
    if PanelStorms.weatherRecord(source) then
        source.modulesChanged = true
        StormNotice.tell(StormNotice.CRACKED_MODULE, source.x, source.y, source.z)
    end
    if object then
        PanelSource.reconcile(source, object)
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

--- Brings the loose panel `isoObject` up to the world's storm hours (PanelStorms.weatherObject),
--- writing a crack to it. A connected panel weathers on its bank's record instead.
function PanelSource.weather(isoObject)
    if PowerBank.connectedBank(isoObject) then
        return
    end
    local kind, _, material = Sources.kindOf(isoObject)
    local source = { kind = kind, material = material, modules = Panel.modulesOf(isoObject, kind) }
    if PanelStorms.weatherObject(isoObject, source) then
        PanelSource.writeModules(isoObject, source.modules)
        StormNotice.tell(StormNotice.CRACKED_MODULE, isoObject:getX(), isoObject:getY(), isoObject:getZ())
    end
end

local function isPanel(isoObject)
    return Sources.familyOf(Sources.kindOf(isoObject)) == "panel"
end

local function panelSprites()
    local names = {}
    for kind in pairs(Specs.mounts) do
        for _, name in ipairs(Sprites.namesOf(kind)) do
            table.insert(names, name)
        end
    end
    return names
end

-- Every loaded panel, each weathered as its chunk loads or it is placed.
local panels = PlaceTracker.new({ sprites = panelSprites(), matches = isPanel, onFound = PanelSource.weather })

--- Weathers every loaded loose panel (PanelSource.weather).
function PanelSource.weatherLoaded()
    panels:each(PanelSource.weather)
end

-- EveryTenMinutes fires at most once a tick however much game time passed, so the storm clock
-- measures the time itself. Registered before any bank pass, so the passes of a tick read it.
Events.EveryTenMinutes.Add(function()
    if PanelStorms.advance() > 0 then
        PanelSource.weatherLoaded()
    end
end)

return PanelSource
