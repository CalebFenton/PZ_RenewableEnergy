-- The hands-on jobs at a gasifier: what each takes of the character and what refuses it. The menu
-- shows the same needs the authority checks (RenewableEnergy.firstUnmet). Loading wood and changing
-- the filter's packing are the loot window's.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/WoodGas/Gasifier"

RenewableEnergy = RenewableEnergy or {}
local GasifierJobs = {}
RenewableEnergy.GasifierJobs = GasifierJobs

local Gasifier = RenewableEnergy.Gasifier

GasifierJobs.LIGHT = "LightGasifier"
GasifierJobs.PUT_OUT = "PutOutGasifier"
GasifierJobs.CLEAN_ASH = "CleanOutAsh"

-- In-game minutes each job takes; a cold start with the bellows takes COLD_LIGHT_MINUTES.
GasifierJobs.MINUTES = {
    [GasifierJobs.LIGHT] = 2,
    [GasifierJobs.PUT_OUT] = 1,
    [GasifierJobs.CLEAN_ASH] = 10,
}
GasifierJobs.COLD_LIGHT_MINUTES = 10

local function notBroken(item)
    return not item:isBroken()
end

local function hasTag(character, tag)
    return character:getInventory():containsTagEvalRecurse(tag, notBroken) and 1 or 0
end

local function bellowsCount(character)
    local inventory = character:getInventory()
    for _, fullType in ipairs(Gasifier.BELLOWS) do
        if inventory:containsTypeRecurse(fullType) then
            return 1
        end
    end
    return 0
end

--- What `job` takes of `character` (RenewableEnergy.firstUnmet, RenewableEnergy.Needs), at a
--- gasifier whose summary is `summary`: a cold one also takes bellows to light.
function GasifierJobs.needs(character, job, summary)
    local needs = {}
    if job == GasifierJobs.LIGHT then
        table.insert(needs, { kind = "tool", item = "Base.Matches", have = hasTag(character, ItemTag.START_FIRE), need = 1 })
        if summary and summary.cold then
            table.insert(needs, { kind = "tool", item = Gasifier.BELLOWS[1], have = bellowsCount(character), need = 1 })
        end
    elseif job == GasifierJobs.CLEAN_ASH then
        table.insert(needs, { kind = "tool", item = "Base.Shovel", have = hasTag(character, ItemTag.TAKE_DIRT), need = 1 })
    end
    return needs
end

--- In-game minutes `job` takes at a gasifier whose summary is `summary`.
function GasifierJobs.minutesFor(job, summary)
    if job == GasifierJobs.LIGHT and summary and summary.cold then
        return GasifierJobs.COLD_LIGHT_MINUTES
    end
    return GasifierJobs.MINUTES[job]
end

--- The state of the gasifier that refuses `job`, as a translation key, or nil.
function GasifierJobs.blocker(job, summary)
    if job == GasifierJobs.LIGHT then
        if summary.lit then
            return "Tooltip_RenewableEnergy_GasifierLit"
        end
        return summary.hopperKg <= 0 and "Tooltip_RenewableEnergy_NoWood" or nil
    elseif job == GasifierJobs.PUT_OUT then
        return not summary.lit and "Tooltip_RenewableEnergy_GasifierOut" or nil
    elseif job == GasifierJobs.CLEAN_ASH then
        return summary.ash < Gasifier.ASH_PER_ITEM and "Tooltip_RenewableEnergy_LittleAsh" or nil
    end
    return nil
end

--- What refuses `character` doing `job` at the gasifier whose summary is `summary`: a blocker
--- key, "short" when they lack a need, or nil.
function GasifierJobs.refusal(character, job, summary)
    if not summary or not GasifierJobs.MINUTES[job] then
        return "Tooltip_RenewableEnergy_NoGasifier"
    end
    return GasifierJobs.blocker(job, summary)
        or (RenewableEnergy.firstUnmet(GasifierJobs.needs(character, job, summary)) and "short")
        or nil
end

return GasifierJobs
