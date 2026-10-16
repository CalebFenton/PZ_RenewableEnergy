-- Buildings the mod's objects fill with fumes (a sour digester, a lit gasifier), on the authority.
--
-- Toxicity belongs to the whole building, isn't saved, and any vanilla generator there sets it
-- again within the hour while it runs. So each source says every pass whether it fumes, the
-- building is toxic while any does, and it is cleared only when the last one stops.

if isClient() then return end

RenewableEnergy = RenewableEnergy or {}
local Fumes = {}
RenewableEnergy.Fumes = Fumes

-- Building ID -> { count, [source key] = true } of the sources fuming there now.
local fuming = {}

--- Says whether the source `key` in `building` (or nil, outdoors) fumes now.
function Fumes.set(key, building, isFuming)
    if not building then return end
    local id = building:getID()
    local sources = fuming[id]
    if isFuming then
        if not sources then
            sources = { count = 0 }
            fuming[id] = sources
        end
        if not sources[key] then
            sources[key] = true
            sources.count = sources.count + 1
        end
        if not building:isToxic() then
            building:setToxic(true)
        end
    elseif sources and sources[key] then
        sources[key] = nil
        sources.count = sources.count - 1
        if sources.count == 0 then
            fuming[id] = nil
            building:setToxic(false)
        end
    end
end

return Fumes
