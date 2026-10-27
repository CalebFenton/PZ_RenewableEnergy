-- The hands-on jobs at a source a bank takes (Sources): what each takes of the
-- character and what refuses it (cf_commonlib's Jobs). SourceSite does them.

require "Util/BuildingHelper"
local Wind = require "RenewableEnergy/Wind"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Wiring = require "RenewableEnergy/PowerBank/Wiring"
local Items = require "cf_commonlib/Items"
local Jobs = require "cf_commonlib/Jobs"
local Squares = require "cf_commonlib/Squares"

local SourceJobs = {}

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
    for _, blades in pairs(Wind.SPEC.blades) do
        if blades.item == fullType then
            return true
        end
    end
    return false
end

--- The blades `character` would fit to the broken wind charger `source`: of its own material if
--- carried, else the first other blades its kind takes that are carried, or nil; second, the
--- names of all the blades its kind takes.
function SourceJobs.bladesFor(character, source)
    local own = Wind.bladesOfObject(source)
    local turbine = Wind.SPEC.turbines[Sources.kindOf(source)]
    local inventory = character:getInventory()
    local blades = own and inventory:getFirstTypeRecurse(Wind.SPEC.blades[own].item)
    local names = {}
    for _, material in ipairs(turbine and turbine.blades or {}) do
        local item = Wind.SPEC.blades[material].item
        blades = blades or inventory:getFirstTypeRecurse(item)
        table.insert(names, getItemNameFromFullType(item))
    end
    return blades, names
end

--- The module record in `slot` of the placed panel `panel` if a seal can help it, else nil;
--- second, the panel's whole list of module records it was read from.
function SourceJobs.sealableModule(panel, slot)
    local modules = Panel.placedModules(panel)
    local module = modules and type(slot) == "number" and modules[slot]
    if module and ModuleRepair.sealable(module.type, module.condition, module.repaired) then
        return module, modules
    end
    return nil
end

local function connectMinutes(character)
    return SandboxVars.RenewableEnergy.ConnectPanelMin * Wiring.skillFactor(character)
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
    -- (SourceSite.source); a client has its summary's.
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
    [SourceJobs.SEAL_MODULE] = ModuleRepair.sealRow(SourceJobs.sealableModule, "Tooltip_RenewableEnergy_ModuleSealedFully"),
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
