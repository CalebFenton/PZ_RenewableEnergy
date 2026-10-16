-- Vanilla's treadmill (Sprites.treadmill) as a source for a bank: two tiles, one of which a player
-- wires to feed a bank (Wire to a Bank), after which a run on it (RenewableEnergyTreadmillAction)
-- banks watt-hours. Unwiring it, picking it up or destroying it gives back the wire
-- (TreadmillSource.unwire). Dismantled, a treadmill gives its motor (Moveables.lua).

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"

RenewableEnergy = RenewableEnergy or {}
local Treadmill = {}
RenewableEnergy.Treadmill = Treadmill

local Specs, Sprites, PowerBank = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.PowerBank

-- Tile modData: the tile wired to feed a bank (one of the treadmill's two tiles).
Treadmill.WIRED = "RenewableEnergy_treadmillWired"
-- The item dismantling a treadmill gives: the wind charger's generator.
Treadmill.MOTOR = "RenewableEnergy.TreadmillMotor"

-- A step in each facing, in squares.
local FACING_STEPS = { N = { 0, -1 }, S = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } }
-- Steps back from each end of the treadmill (Sprites.treadmill) to its rear end.
local STEPS_TO_REAR = { rear = 0, console = 1 }

--- Whether a sprite is one of a treadmill's tiles (Sprites.treadmill).
Treadmill.isSprite = Sprites.matcher(Sprites.treadmill)

--- Whether `isoObject` is a treadmill's tile, wired or not.
function Treadmill.isTreadmill(isoObject)
    return Treadmill.isSprite(Sprites.nameOf(isoObject))
end

--- Whether the treadmill tile `tile` is the one wired to feed a bank.
function Treadmill.isWired(tile)
    return tile:getModData()[Treadmill.WIRED] == true
end

--- Whether `isoObject` is a treadmill's tile wired to feed a bank.
function Treadmill.isWiredTile(isoObject)
    return Treadmill.isTreadmill(isoObject) and Treadmill.isWired(isoObject)
end

--- A treadmill's tile on `square`, wired or not, or nil.
function Treadmill.on(square)
    return RenewableEnergy.findObjectOn(square, Treadmill.isTreadmill)
end

--- Where the treadmill of `tile` has its rear end, which the runner stands on, and its console
--- end, as { x, y } each, and the step from rear to console, the way the runner faces
--- (Sprites.treadmill).
function Treadmill.ends(tile)
    local _, facing, part = Sprites.kindOf(Sprites.nameOf(tile))
    local step = FACING_STEPS[facing]
    local square = tile:getSquare()
    local back = STEPS_TO_REAR[part]
    local x, y = square:getX() - step[1] * back, square:getY() - step[2] * back
    return { x = x, y = y }, { x = x + step[1], y = y + step[2] }, step
end

--- The wired tile of the treadmill `tile` is part of: `tile` itself, or its other half; nil when
--- neither is wired. A treadmill beside it is not its other half unless both tiles put the
--- treadmill's ends in the same places.
function Treadmill.wiredHalf(tile)
    if Treadmill.isWired(tile) then
        return tile
    end
    local rear, console = Treadmill.ends(tile)
    local square = tile:getSquare()
    local other = (square:getX() == rear.x and square:getY() == rear.y) and console or rear
    local found = Treadmill.on(getSquare(other.x, other.y, square:getZ()))
    if not (found and Treadmill.isWired(found)) then
        return nil
    end
    local foundRear, foundConsole = Treadmill.ends(found)
    if PowerBank.samePosition(foundRear, rear) and PowerBank.samePosition(foundConsole, console) then
        return found
    end
    return nil
end

--- What wiring a treadmill to feed a bank takes of `character` (RenewableEnergy.firstUnmet), as
--- PowerBank.wiringNeeds does for a part.
function Treadmill.needs(character)
    return PowerBank.jobNeeds(character, Specs.treadmill.wiring)
end

--- Why `character` can't wire the treadmill of `tile` now, or nil if they can: "already wired"
--- when either of its tiles is, else the kind of the first of Treadmill.needs they are short of.
--- The action, the menu and the authority's command all ask it, so a treadmill is wired once.
function Treadmill.wiringRefusal(character, tile)
    if Treadmill.wiredHalf(tile) then
        return "already wired"
    end
    local short = RenewableEnergy.firstUnmet(Treadmill.needs(character))
    return short and short.kind
end

--- Why a run on the wired treadmill tile `tile` would bank nothing, or nil: it feeds no bank, as
--- this side last heard (PowerBank.connectedBank).
function Treadmill.runRefusal(tile)
    if not PowerBank.connectedBank(tile) then
        return "Tooltip_RenewableEnergy_TreadmillNotConnected"
    end
    return nil
end

return Treadmill
