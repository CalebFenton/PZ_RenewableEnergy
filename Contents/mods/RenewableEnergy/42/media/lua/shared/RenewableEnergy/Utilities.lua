-- Helpers that several of the mod's modules share.
--
-- RenewableEnergy is the mod's one global table. The only other globals are the timed action
-- class RenewableEnergyAction, which the game looks up by name, and the debug test runner's
-- RenewableEnergyTest. Every file that adds to the table creates it first if no file has yet, so
-- files may load in any order.

RenewableEnergy = RenewableEnergy or {}

--- The first object on `square` for which `matches(object)` is true, or nil. Takes a nil square.
function RenewableEnergy.findObjectOn(square, matches)
    local objects = square and square:getObjects()
    for i = 0, (objects and objects:size() or 0) - 1 do
        local object = objects:get(i)
        if matches(object) then
            return object
        end
    end
    return nil
end

return RenewableEnergy
