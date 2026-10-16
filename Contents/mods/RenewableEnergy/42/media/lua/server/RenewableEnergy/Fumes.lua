-- Buildings the mod's objects fill with fumes (a sour digester, a lit gasifier), on the authority.
--
-- Toxicity belongs to the whole building, isn't saved, and any vanilla generator there sets it
-- again within the hour while it runs. So each source says every pass whether it fumes, the
-- building is toxic while any does, and it is cleared only when the last one stops.

if isClient() then return end

RenewableEnergy = RenewableEnergy or {}
local Fumes = {}
RenewableEnergy.Fumes = Fumes

-- Source key -> the building it fumes in now. Kept so a source can stop without its tile, which
-- is gone when its record is removed after its chunk loads.
local fuming = {}

local function stillFumed(building)
    local id = building:getID()
    for _, other in pairs(fuming) do
        if other:getID() == id then
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
        if not stillFumed(was) then
            was:setToxic(false)
        end
    end
end

return Fumes
