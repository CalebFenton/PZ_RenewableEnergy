-- Storms on the panels no bank runs. A placed panel stands in the weather whether or not it is
-- connected, so disconnecting one before a storm doesn't spare it: a bank's pass cracks its own
-- panels (PanelSource.update), and this cracks every other outdoor panel the same way.
--
-- The world keeps a running total of storm hours, and each panel the total it has weathered, so a
-- panel whose chunk was unloaded through a storm takes it when its chunk next loads. A panel seen
-- for the first time starts at the total: it was just placed, or is from a save before this.

if isClient() then return end

require "RenewableEnergy/PlaceTracker"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/PanelSource"

RenewableEnergy = RenewableEnergy or {}
local PowerBank, Sources, PanelSource = RenewableEnergy.PowerBank, RenewableEnergy.Sources, RenewableEnergy.PanelSource

local PanelStorms = {}
RenewableEnergy.PanelStorms = PanelStorms

-- World ModData: `hours`, the storm hours since the world began; `lastHour`, the world age at the
-- last pass.
local MOD_DATA = "RenewableEnergy_storms"
-- Panel modData: the world's storm hours the panel has weathered.
local WEATHERED = "RenewableEnergy_stormHours"
-- As a bank's pass: a save loaded after the clock jumped never counts days of storm at once.
local LONGEST_PASS = 24

local function ledger()
    return ModData.getOrCreate(MOD_DATA)
end

local function isPanel(isoObject)
    return Sources.familyOf(Sources.kindOf(isoObject)) == "panel"
end

--- Brings the placed panel `isoObject` up to the world's storm hours: if it stands outdoors and
--- feeds no bank, the storm hours since it last weathered may crack a module, as a bank's pass
--- would (PanelSource.stormCrack). Returns whether one cracked.
function PanelStorms.weather(isoObject)
    local total = ledger().hours or 0
    local data = isoObject:getModData()
    local weathered = data[WEATHERED]
    if weathered == total then
        return false
    end
    -- A connected panel keeps up too, so the storms its bank cracked it for don't count again
    -- once it is disconnected.
    data[WEATHERED] = total
    if not weathered or PowerBank.connectedBank(isoObject) or not isoObject:getSquare():isOutside() then
        return false
    end
    local kind, _, material = Sources.kindOf(isoObject)
    local source = { kind = kind, material = material, modules = PowerBank.modulesOf(isoObject, kind) }
    if not PanelSource.stormCrack(source, total - weathered) then
        return false
    end
    PanelSource.writeModules(isoObject, source.modules)
    PanelSource.showCracks(isoObject)
    return true
end

local function panelSprites()
    local names = {}
    for kind in pairs(RenewableEnergy.Specs.mounts) do
        for _, name in ipairs(RenewableEnergy.Sprites.namesOf(kind)) do
            table.insert(names, name)
        end
    end
    return names
end

-- Every loaded panel, each weathered as its chunk loads or it is placed.
local panels = RenewableEnergy.PlaceTracker.new({ sprites = panelSprites(), matches = isPanel, onFound = PanelStorms.weather })

--- Adds `stormHours` to the world's storm hours and weathers every loaded panel. Returns how many
--- cracked.
function PanelStorms.pass(stormHours)
    if stormHours <= 0 then
        return 0
    end
    local store = ledger()
    store.hours = (store.hours or 0) + stormHours
    local cracked = 0
    panels:each(function(isoObject)
        if PanelStorms.weather(isoObject) then
            cracked = cracked + 1
        end
    end)
    return cracked
end

-- EveryTenMinutes fires at most once a tick however much game time passed, so the pass measures
-- the time itself.
local function update()
    local store = ledger()
    local now = getGameTime():getWorldAgeHours()
    local hours = math.min(LONGEST_PASS, now - (store.lastHour or now))
    store.lastHour = now
    PanelStorms.pass(PanelSource.stormHours(hours))
end

Events.EveryTenMinutes.Add(update)

return PanelStorms
