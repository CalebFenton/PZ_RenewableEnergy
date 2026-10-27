-- Buildings the mod's objects fill with fumes (a sour digester, a lit gasifier), on the authority,
-- and the one place generators are switched, since switching one writes its building's toxicity.
--
-- Toxicity belongs to the whole building and isn't saved. Vanilla writes it too: a generator sets
-- it as it starts indoors and clears it as it stops (IsoGenerator.setActivated), and while it runs
-- sets it again each hour (IsoGenerator.update). So each source says every pass whether it fumes,
-- the building is toxic while any does, and it is cleared only when the last one stops with no
-- generator running inside.

if isClient() then return end

require "TimedActions/ISActivateGenerator"
local Payers = require "RenewableEnergy/PowerBank/Payers"
local GeneratorReach = require "cf_commonlib/GeneratorReach"

local Fumes = {}

-- Source key -> the building it fumes in now. Kept so a source can stop without its tile, which
-- is gone when its record is removed after its chunk loads.
local fuming = {}

--- The building whose air an object on `square` fumes, or nil outdoors: vanilla's own test for a
--- generator's fumes (IsoGenerator.setActivated), so a square open to the sky in a building isn't.
function Fumes.buildingOf(square)
    return not square:isOutside() and square:getBuilding() or nil
end

local function stillFumed(building)
    local id = building:getID()
    for _, other in pairs(fuming) do
        if other:getID() == id then
            return true
        end
    end
    return false
end

-- Whether a generator runs inside `building`, which vanilla keeps toxic itself.
local function generatorRunsIn(building)
    local id = building:getID()
    for _, payer in ipairs(Payers.running()) do
        local square = payer.generator and payer.generator:getSquare()
        local inside = square and Fumes.buildingOf(square)
        if inside and inside:getID() == id then
            return true
        end
    end
    return false
end

--- Says whether the source `key` fumes now, in `building`. A source that stops needs no building;
--- one outdoors, or whose building isn't loaded, doesn't start.
function Fumes.set(key, building, isFuming)
    local was = fuming[key]
    if isFuming and building then
        fuming[key] = building
        if not building:isToxic() then
            building:setToxic(true)
        end
    elseif not isFuming and was then
        fuming[key] = nil
        if not stillFumed(was) and not generatorRunsIn(was) then
            was:setToxic(false)
        end
    end
end

--- Makes `building` toxic again if a source still fumes in it, after vanilla cleared it as a
--- generator there stopped. Nothing for nil, outdoors.
function Fumes.restore(building)
    if building and not building:isToxic() and stillFumed(building) then
        building:setToxic(true)
    end
end

--- Starts or stops the vanilla generator `generator`, as vanilla does, putting back the fumes of
--- the mod's sources in its building that a stop clears. Billing is the caller's.
function Fumes.setRunning(generator, on)
    if generator:isActivated() == on then return end
    generator:setActivated(on)
    if not on then
        Fumes.restore(Fumes.buildingOf(generator:getSquare()))
    end
end

--- Starts or stops a battery bank's generator. A bank has no exhaust, so its building keeps the
--- toxicity it had, which vanilla's switch would set or clear.
function Fumes.setBankRunning(generator, on)
    if generator:isActivated() == on then return end
    local building = Fumes.buildingOf(generator:getSquare())
    local wasToxic = building and building:isToxic()
    generator:setActivated(on)
    if building and building:isToxic() ~= wasToxic then
        building:setToxic(wasToxic)
    end
end

-- A player starting or stopping a generator: vanilla switches it (ISActivateGenerator.complete),
-- so the fumes it cleared go back here, and who pays nearby changes at once.
local vanillaComplete = ISActivateGenerator.complete
function ISActivateGenerator:complete()
    local result = vanillaComplete(self)
    local generator = self.generator
    if GeneratorReach.isVanillaGenerator(generator) then
        if not generator:isActivated() then
            Fumes.restore(Fumes.buildingOf(generator:getSquare()))
        end
        Payers.track(generator)
        Payers.billGenerators()
    end
    return result
end

return Fumes
