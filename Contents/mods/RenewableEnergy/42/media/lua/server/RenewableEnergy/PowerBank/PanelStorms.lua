-- Storms cracking panels' modules, on the authority: the one storm clock, and the rule each crack
-- follows. A placed panel stands in the weather whether or not it is connected, so disconnecting one
-- before a storm doesn't spare it.
--
-- The world keeps a running total of storm hours, and each panel the total it has weathered: a
-- connected panel on its bank's record of it (`weathered`), which every bank pass brings up to
-- the total (PanelSource.update), loaded or not; a loose panel on its object, brought up to it as
-- its chunk loads and every pass while loaded (PanelSource). Connecting and disconnecting hand
-- the mark between the two, so no storm counts twice or is skipped. A panel seen for the first
-- time starts at the total: it was just placed, or is from a save before this.

if isClient() then return end

local StormChance = require "RenewableEnergy/StormChance"
local Specs = require "RenewableEnergy/Specs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Chance = require "cf_commonlib/Chance"
local Clock = require "cf_commonlib/Clock"

local PanelStorms = {}

-- World ModData: `hours`, the storm hours since the world began; `lastHour`, the world age at the
-- last pass.
local MOD_DATA = "RenewableEnergy_storms"
-- Panel modData: the world's storm hours the panel has weathered.
local WEATHERED_KEY = "RenewableEnergy_stormHours"

local function store()
    return ModData.getOrCreate(MOD_DATA)
end

local function total()
    return store().hours or 0
end

--- The hours of a stretch of `hours`, ending now, in which a thunderstorm can crack modules: all
--- of them while one blows hard enough, else none.
function PanelStorms.stormHours(hours)
    local climate = getClimateManager()
    local storming = climate:getIsThunderStorming() and climate:getWindspeedKph() >= Specs.storm.panelKph
    return storming and hours or 0
end

--- Adds `stormHours` to the world's storm hours.
function PanelStorms.add(stormHours)
    if stormHours > 0 then
        local storms = store()
        storms.hours = (storms.hours or 0) + stormHours
    end
end

--- Brings the world's storm hours up to now. Returns the storm hours it added.
function PanelStorms.advance()
    local stormHours = PanelStorms.stormHours(Clock.hoursSince(store(), PowerBank.LONGEST_PASS))
    PanelStorms.add(stormHours)
    return stormHours
end

-- A mount's stormShare (Specs.storm), times its material's.
local function stormShare(mount, material)
    local materialSpec = material and Specs.materials[material]
    return Specs.mounts[mount].stormShare * (materialSpec and materialSpec.stormShare or 1)
end

--- The chance that `stormHours` of thunderstorm crack a module of `source` (anything with a mount
--- kind and material), at the StormDamage options.
function PanelStorms.stormChance(source, stormHours)
    return StormChance.stormDamage(Specs.storm.panelPerHour * stormShare(source.kind, source.material), stormHours)
end

--- A thunderstorm may crack one of a panel's modules (`source`, anything with a mount kind,
--- material and module records). Returns whether it did.
function PanelStorms.stormCrack(source, stormHours)
    local chance = PanelStorms.stormChance(source, stormHours)
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

-- The storm hours since `weathered` (nil: none, the first look), and the world's total.
local function since(weathered)
    local now = total()
    return weathered and now - weathered or 0, now
end

--- Brings a bank's record of a connected panel up to the world's storm hours: those since it last
--- weathered may crack one of its modules. Returns whether one cracked.
function PanelStorms.weatherRecord(source)
    local hours
    hours, source.weathered = since(source.weathered)
    return hours > 0 and PanelStorms.stormCrack(source, hours)
end

--- Brings the loose panel `isoObject` up to the world's storm hours: those since it last weathered
--- may crack one of `source`'s modules (its kind, material and the modules it holds) if it stands
--- outdoors. Returns whether one cracked; the caller writes them to the panel.
function PanelStorms.weatherObject(isoObject, source)
    local data = isoObject:getModData()
    local hours
    hours, data[WEATHERED_KEY] = since(data[WEATHERED_KEY])
    return hours > 0 and isoObject:getSquare():isOutside() and PanelStorms.stormCrack(source, hours)
end

--- A panel connecting: its bank's record `source` weathers on from where the object left off.
function PanelStorms.toRecord(source, isoObject)
    source.weathered = isoObject:getModData()[WEATHERED_KEY] or total()
end

--- A panel disconnecting: its object weathers on from where the bank's record `source` left off.
function PanelStorms.toObject(source, isoObject)
    isoObject:getModData()[WEATHERED_KEY] = source.weathered or total()
end

return PanelStorms
