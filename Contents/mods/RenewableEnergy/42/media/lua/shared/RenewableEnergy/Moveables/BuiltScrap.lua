-- What dismantling a digester, gasifier or wind charger gives back: what its build recipe used up,
-- each piece on a roll whose odds rise with the recipe's first skill, as vanilla means a built
-- object to give back what it was built of (ISMoveableSpriteProps.scrapObjectInternal's build
-- materials, which this build of the game then passes over for the tile's Material). The parts that
-- make a wind charger go always come back, broken blades broken; so do a digester's fittings, its
-- scrubber's materials on the same rolls as the rest.

local Sprites = require "RenewableEnergy/Sprites"
local Wind = require "RenewableEnergy/Wind"
local Digester = require "RenewableEnergy/Biogas/Digester"
local DigesterJobs = require "RenewableEnergy/Biogas/DigesterJobs"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local CarAlternator = require "RenewableEnergy/Gadgets/CarAlternator"
local Chance = require "cf_commonlib/Chance"

local BuiltScrap = {}

-- Each piece's odds: BASE at the skill's level 0, PER_LEVEL more a level.
BuiltScrap.BASE, BuiltScrap.PER_LEVEL = 0.7, 0.02

-- The build entity of each kind of tile (Sprites.kindOf), by tier where the kind has tiers. A
-- bladed wind charger has one recipe, built on its wooden-blade tile, whatever blades it took.
local ENTITIES = {
    digester = {
        barrel = "Base.RenewableEnergy_BarrelDigester",
        insulated = "Base.RenewableEnergy_InsulatedDigester",
        dome = "Base.RenewableEnergy_BrickDome",
    },
    gasifier = {
        primitive = "Base.RenewableEnergy_PrimitiveGasifier",
        standard = "Base.RenewableEnergy_Gasifier",
        advanced = "Base.RenewableEnergy_AdvancedGasifier",
    },
    scoop = "Base.RenewableEnergy_ScoopRotor",
    timberScoop = "Base.RenewableEnergy_TimberScoopRotor",
    propeller = "Base.RenewableEnergy_PropellerWood",
    carAlternator = "Base.RenewableEnergy_CarAlternatorWood",
    timberPropeller = "Base.RenewableEnergy_TimberPropellerWood",
    timberCarAlternator = "Base.RenewableEnergy_TimberCarAlternatorWood",
    alternator = "Base.RenewableEnergy_TurbineWood",
}

-- What a build uses up for good: glued and taped joins, the straw that rots in the walls, garbage
-- bags. An input that can be any of these gives nothing back.
local SPENT = {
    ["Base.Glue"] = true, ["Base.DuctTape"] = true, ["Base.HayTuft"] = true, ["Base.Straw2"] = true,
    ["Base.Garbagebag"] = true,
}

-- What makes a wind charger go, which comes off whole rather than as scrap.
local ALWAYS = { [Treadmill.MOTOR] = true, [CarAlternator.ITEM] = true, ["RenewableEnergy.HomemadeAlternator"] = true }
for _, blades in pairs(Wind.SPEC.blades) do
    ALWAYS[blades.item] = true
end

-- The kind of item an input taking several gives back: the object's own where it says which (the
-- barrel a barrel digester was built from, a wind charger's blades), a plain bucket for a bucket,
-- else the first the recipe lists.
local PREFERRED = { ["Base.Bucket"] = true }

--- The odds of each piece coming back to a character at `level` of the recipe's skill.
function BuiltScrap.odds(level)
    return math.min(1, BuiltScrap.BASE + BuiltScrap.PER_LEVEL * level)
end

--- The build recipe of the entity `entity`, or nil.
local function recipeOf(entity)
    local script = getScriptManager():getGameEntityScript(entity)
    local component = script and script:getComponentScriptFor(ComponentType.CraftRecipe)
    return component and component:getCraftRecipe()
end

--- What dismantling `isoObject` gives back, read before the dismantling takes it and its record
--- away: { recipe, prefer, swap, digester }, or nil for anything not built in place.
function BuiltScrap.planOf(isoObject)
    local kind, tier, variant = Sprites.kindOfObject(isoObject)
    local entity = ENTITIES[kind]
    if type(entity) == "table" then
        entity = entity[tier]
    end
    local recipe = entity and recipeOf(entity)
    if not recipe then
        return nil
    end
    local plan = { recipe = recipe, prefer = {}, swap = {} }
    if kind == "digester" then
        if tier == "barrel" then
            plan.prefer["Base." .. variant] = true
        end
        local record = Digester.recordOf(isoObject)
        if record then
            plan.digester = {
                holder = record.holder, holderCondition = record.holderCondition, scrubber = record.scrubber == true,
                scrubSponge = record.scrubSponge, compressor = record.compressor == true,
            }
        end
    end
    local blades = Wind.SPEC.turbines[kind] and Wind.bladesOfObject(isoObject)
    if blades then
        local spec = Wind.SPEC.blades[blades]
        plan.prefer[spec.item] = true
        if Wind.isBroken(isoObject) then
            plan.swap[spec.item] = spec.broken
        end
    end
    return plan
end

-- The item an input gives back for `plan`, by PREFERRED's rule; nil when any it takes is spent.
local function returnedType(input, plan)
    local possible, first, preferred = input:getPossibleInputItems(), nil, nil
    for i = 0, possible:size() - 1 do
        local fullType = possible:get(i):getFullName()
        if SPENT[fullType] then
            return nil
        end
        first = first or fullType
        if not preferred and (plan.prefer[fullType] or PREFERRED[fullType]) then
            preferred = fullType
        end
    end
    return preferred or first
end

-- Adds `count` of `fullType` to `types`, each always if it is a part, else on a roll at `odds`.
local function addPieces(types, fullType, count, odds, swap)
    for _ = 1, count do
        if ALWAYS[fullType] or Chance.hit(odds) then
            table.insert(types, swap[fullType] or fullType)
        end
    end
end

--- What dismantling the object of `plan` (BuiltScrap.planOf) gives `character`: the full types
--- of the pieces, and the fittings that come back as they were, items with their condition.
function BuiltScrap.itemsOf(plan, character)
    local recipe, level = plan.recipe, 0
    if recipe:getRequiredSkillCount() > 0 then
        level = character:getPerkLevel(recipe:getRequiredSkill(0):getPerk())
    end
    local odds, types, items = BuiltScrap.odds(level), {}, {}
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if input:getResourceType() == ResourceType.Item and not input:isKeep() and not input:isTool()
            and input:isRecordInput() then
            local fullType = returnedType(input, plan)
            if fullType then
                addPieces(types, fullType, math.max(input:getIntAmount(fullType), input:getIntAmount()), odds, plan.swap)
            end
        end
    end
    local digester = plan.digester
    if digester then
        if digester.scrubber then
            for _, material in ipairs(DigesterJobs.JOBS[DigesterJobs.FIT_SCRUBBER].materials) do
                if material.item and not material.perk and not material.uses then
                    addPieces(types, material.item, material.need or 1, odds, plan.swap)
                end
            end
        end
        local fittings = {
            Digester.holderItem(digester.holder, digester.holderCondition or 0),
            Digester.spentSponge(digester.scrubSponge),
            digester.compressor and instanceItem(Digester.COMPRESSOR) or nil,
        }
        for slot = 1, 3 do
            if fittings[slot] then
                table.insert(items, fittings[slot])
            end
        end
    end
    return types, items
end

return BuiltScrap
