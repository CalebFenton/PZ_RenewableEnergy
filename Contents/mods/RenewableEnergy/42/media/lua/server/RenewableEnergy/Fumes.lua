-- The air of buildings the mod's objects fill with fumes (a sour or leaking digester, a lit
-- gasifier), on the authority, and the switch of a battery bank's generator, which must not.
--
-- Toxicity belongs to the whole building and isn't saved. The rule: a building is toxic while a
-- generator runs in it (the engine's) or one of the mod's sources fumes in it (this file's). The
-- engine writes it on its own: a generator sets it as it starts and clears it as it stops, out of
-- fuel too (IsoGenerator.setActivated, update), and a game working out the rooms players built
-- again makes their buildings anew with clear air (WorldRegionToMetaGrid). So each source says at
-- each pass whether it fumes, and every tick each fuming source's building is made toxic again if
-- something cleared it. A source is kept by its square: a room a player built is a new building
-- each time the game makes it, and only in single player, never on a dedicated server, which keeps
-- no building for it.

if isClient() then return end

local Payers = require "RenewableEnergy/PowerBank/Payers"

local Fumes = {}

-- Source key -> { x, y, z, building }: the square it fumes from and the building it fumed in then,
-- kept so a source can stop without its tile, which is gone when its record is removed after its
-- chunk loads.
local fuming = {}

--- The building whose air an object on `square` fumes, or nil outdoors: vanilla's own test for a
--- generator's fumes (IsoGenerator.setActivated), so a square open to the sky in a building isn't.
function Fumes.buildingOf(square)
    return not square:isOutside() and square:getBuilding() or nil
end

-- The building `source` fumes in now: its square's, else, while that is unloaded or no longer in
-- one, the one it fumed in.
local function buildingNow(source)
    local square = getSquare(source.x, source.y, source.z)
    return square and Fumes.buildingOf(square) or source.building
end

--- Whether one of the mod's sources fumes in `building` now.
function Fumes.sourceIn(building)
    local id = building:getID()
    for _, source in pairs(fuming) do
        if buildingNow(source):getID() == id then
            return true
        end
    end
    return false
end

-- Whether a generator runs inside `building`, which keeps it toxic itself.
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

--- Says whether the source `key` on `square` fumes now. A source that stops needs no square; one
--- outdoors, or whose building isn't loaded, fumes nothing.
function Fumes.set(key, square, isFuming)
    local was = fuming[key]
    local building = isFuming and square and Fumes.buildingOf(square)
    if building then
        fuming[key] = { x = square:getX(), y = square:getY(), z = square:getZ(), building = building }
        if not building:isToxic() then
            building:setToxic(true)
        end
    elseif was then
        fuming[key] = nil
        local wasIn = buildingNow(was)
        if not Fumes.sourceIn(wasIn) and not generatorRunsIn(wasIn) then
            wasIn:setToxic(false)
        end
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

-- A generator stopping, or the building being made anew, clears what a source still fumes.
Events.OnTick.Add(function()
    for _, source in pairs(fuming) do
        local building = buildingNow(source)
        if not building:isToxic() then
            building:setToxic(true)
        end
    end
end)

return Fumes
