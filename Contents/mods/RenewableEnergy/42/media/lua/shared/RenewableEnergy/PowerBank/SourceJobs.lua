-- The hands-on jobs at a source a bank takes (RenewableEnergy.Sources): what each takes of the
-- character and what refuses it (cf_commonlib's Jobs). JobSites.source does them.

require "Util/BuildingHelper"
local RenewableEnergy = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local Wind = require "RenewableEnergy/Wind"
local Recipes = require "RenewableEnergy/Recipes"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Items = require "cf_commonlib/Items"
local Jobs = require "cf_commonlib/Jobs"
local Squares = require "cf_commonlib/Squares"

local SourceJobs = {}
RenewableEnergy.SourceJobs = SourceJobs

SourceJobs.CONNECT = "ConnectSource"
SourceJobs.DISCONNECT = "DisconnectSource"
SourceJobs.CLEAR_SNOW = "ClearSnow"
SourceJobs.SEAL_MODULE = "SealModule"
SourceJobs.BRAKE = "Brake"
SourceJobs.RELEASE_BRAKE = "ReleaseBrake"
SourceJobs.REPLACE_BLADES = "ReplaceBlades"

-- What clears snow off a panel without scratching it: a broom sweeps, a snow shovel pushes.
local SNOW_TOOLS = { ["Base.Broom"] = true, ["Base.Broom_Twig"] = true, ["Base.SnowShovel"] = true }

function SourceJobs.isSnowTool(item)
    return item ~= nil and SNOW_TOOLS[item:getFullType()] == true and Items.notBroken(item)
end

-- Whether `item` is blades of any wind charger's.
local function isBlades(item)
    local fullType = item:getFullType()
    for _, blades in pairs(Specs.wind.blades) do
        if blades.item == fullType then
            return true
        end
    end
    return false
end

local function connectMinutes(character)
    return SandboxVars.RenewableEnergy.ConnectPanelMin * PowerBank.skillFactor(character)
end

-- A wind charger's brake, a lever or pin at the foot of the mast, set to `braked`.
local function brakeJob(braked)
    return {
        braked = braked, minutes = 1,
        blocker = function(character, source)
            if not Wind.isCharger(source) then
                return "no wind charger"
            end
            return Wind.isBraked(source) == braked and "brake already so" or nil
        end,
    }
end

-- Every job, by name (Jobs.define), at the source's tile; `with` is the bank Connect Source wires
-- it to, the tool or blades a job works with, or the module slot Seal Cracked Module seals.
SourceJobs.JOBS = {
    -- A source feeds one bank, and connecting it again to the bank it feeds leaves it as it is,
    -- snow and all. The authority counts the bank's input slots afresh first
    -- (JobSites.source); a client has its summary's.
    [SourceJobs.CONNECT] = {
        minutes = function(source, bank, character) return connectMinutes(character) end,
        light = true, sound = "GeneratorConnect",
        blocker = function(character, source, bank)
            local summary = PowerBank.isBank(bank) and PowerBank.currentSummary(bank)
            if not summary then
                return "no bank"
            end
            return Sources.connectRefusal(source, Squares.positionOf(bank)) or Sources.bankRefusal(bank:isConnected())
                or Sources.slotRefusal(Sources.kindOf(source), summary.freeSlots)
        end,
    },
    [SourceJobs.DISCONNECT] = {
        minutes = function(source, bank, character) return connectMinutes(character) / 2 end,
        light = true,
        blocker = function(character, source) return not PowerBank.connectedBank(source) and "not connected" or nil end,
    },
    -- With the broom or snow shovel in hand.
    [SourceJobs.CLEAR_SNOW] = {
        minutes = 5, metabolics = Metabolics.LightWork, wield = true,
        begin = function(self)
            if self.with:getType() == "SnowShovel" then
                self:setActionAnim(BuildingHelper.getShovelAnim(self.with))
                self.sound = self.character:playSound("Shoveling")
            else
                self:setActionAnim("Rake")
            end
        end,
        blocker = function(character, source)
            if not Sources.sweepable(Sources.kindOf(source)) then
                return "holds no snow"
            end
            return not PowerBank.connectedBank(source) and "not connected" or nil
        end,
        with = SourceJobs.isSnowTool, withMissing = "Tooltip_RenewableEnergy_NeedSnowTool",
    },
    -- Seal Cracked Module's twin for a module on a placed panel, as long as the crafting window
    -- takes for it.
    [SourceJobs.SEAL_MODULE] = {
        units = function(source, slot, character) return Recipes.sealInPlaceUnits(character) end,
        light = true, sound = "GeneratorRepair",
        needs = Recipes.sealInPlaceNeeds,
        blocker = function(character, source, slot)
            return not Recipes.sealableModule(source, slot) and "Tooltip_RenewableEnergy_ModuleSealedFully" or nil
        end,
    },
    [SourceJobs.BRAKE] = brakeJob(true),
    [SourceJobs.RELEASE_BRAKE] = brakeJob(false),
    -- Lowering the head, unbolting the broken blades and bolting new ones on.
    [SourceJobs.REPLACE_BLADES] = {
        minutes = 20, light = true,
        blocker = function(character, source)
            return not (Wind.isCharger(source) and Wind.isBroken(source)) and "not broken" or nil
        end,
        with = isBlades, withMissing = "Tooltip_RenewableEnergy_NeedsFittingBlades",
        withRefusal = function(character, source, blades)
            return not Wind.bladesOfItem(Sources.kindOf(source), blades) and "Tooltip_RenewableEnergy_NeedsFittingBlades"
                or nil
        end,
    },
}

Jobs.define(SourceJobs, {
    subjectOf = function(source) return Sources.kindOf(source) and source end, missing = "no source",
})

--- Select currently eligible Connect jobs in discovery order. An already-refused action would
--- clear the whole queue, losing the sources that fit. Later jobs still recheck live slots.
--- Also returns the refusal when none fit, and the total nearby count for the menu's label.
function SourceJobs.connectBatch(character, bank)
    local sources = Sources.sourcesInReach(Squares.positionOf(bank))
    local count, ready, refusal = #sources, 0, "Tooltip_RenewableEnergy_NoSourcesInReach"
    for _, source in ipairs(sources) do
        local blocker = SourceJobs.refusalAt(character, SourceJobs.CONNECT, source, bank)
        if blocker then
            refusal = blocker
        else
            ready = ready + 1
            sources[ready] = source
        end
    end
    for i = count, ready + 1, -1 do sources[i] = nil end
    return sources, ready == 0 and refusal or nil, count
end

return SourceJobs
