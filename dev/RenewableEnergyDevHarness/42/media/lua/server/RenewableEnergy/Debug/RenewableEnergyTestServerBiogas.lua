-- The authority's half of the biogas tests: the stink's ghosts are counted where the authority
-- updates the characters. Only registers handlers, so a --stay rerun loads it again
-- (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"

local handler = PZHarness.serverHandler

-- Makes the source `args.key` at x, y, z smell like `args.count` corpses (RenewableEnergy.Stink),
-- until the test ends. Answers how many its chunk counts now.
handler("stinkSet", function(player, args, defer)
    local Stink = RenewableEnergy.Stink
    Stink.set(args.key, args.x, args.y, args.z, args.count)
    defer(function() Stink.set(args.key, args.x, args.y, args.z, 0) end)
    return { counted = Stink.counted(args.key) }
end)

-- What the authority's copy of the character smells: its corpse sickness rate, its noxious smell
-- moodle level and food sickness; the corpses on the square at x, y, z, which ghosts never join;
-- and what is left of the filter of a worn gas mask, if any.
handler("stinkRead", function(player, args)
    local square = getSquare(args.x, args.y, args.z)
    local mask
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(i)
        if item and item:hasTag(ItemTag.GAS_MASK) then
            mask = item:getUsedDelta()
        end
    end
    return {
        rate = player:getCorpseSicknessRate(),
        level = player:getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL),
        sickness = player:getStats():get(CharacterStat.FOOD_SICKNESS),
        bodies = square and square:getDeadBodys():size() or -1,
        objects = square and square:getMovingObjects():size() or -1,
        mask = mask,
    }
end)
