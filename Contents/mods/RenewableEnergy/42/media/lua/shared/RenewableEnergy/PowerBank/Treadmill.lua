-- Vanilla's treadmill (Sprites.treadmill), two tiles. Unwired, a run on it draws its motor's watts
-- like any appliance. Wired to feed a bank, a run on it banks watt-hours instead.

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Jobs = require "cf_commonlib/Jobs"
local Squares = require "cf_commonlib/Squares"

local Treadmill = {}
RenewableEnergy.Treadmill = Treadmill

-- Tile modData: the tile wired to feed a bank (one of the treadmill's two tiles).
Treadmill.WIRED_KEY = "RenewableEnergy_treadmillWired"
-- The item dismantling a treadmill gives.
Treadmill.MOTOR = "RenewableEnergy.TreadmillMotor"

local FACING_STEPS = RenewableEnergy.SIDE_STEPS
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
    return tile:getModData()[Treadmill.WIRED_KEY] == true
end

--- Whether `isoObject` is a treadmill's tile wired to feed a bank.
function Treadmill.isWiredTile(isoObject)
    return Treadmill.isTreadmill(isoObject) and Treadmill.isWired(isoObject)
end

--- A treadmill's tile on `square`, wired or not, or nil.
function Treadmill.findOn(square)
    return Squares.findObjectOn(square, Treadmill.isTreadmill)
end

--- Where the treadmill of `tile` has its rear end, which the runner stands on, and its console
--- end, as { x, y } each, and the step from rear to console, the way the runner faces
--- (Sprites.treadmill).
function Treadmill.ends(tile)
    local _, facing, part = Sprites.kindOfObject(tile)
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
    local found = Treadmill.findOn(getSquare(other.x, other.y, square:getZ()))
    if not (found and Treadmill.isWired(found)) then
        return nil
    end
    local foundRear, foundConsole = Treadmill.ends(found)
    if Squares.samePosition(foundRear, rear) and Squares.samePosition(foundConsole, console) then
        return found
    end
    return nil
end

Treadmill.WIRE = "WireTreadmill"
Treadmill.UNWIRE = "UnwireTreadmill"

local WIRING = Specs.treadmill.wiring

-- The jobs at a treadmill's tile, by name (cf_commonlib's Jobs): wiring it to feed a bank, as a
-- part is wired in, and unwiring it. JobSites.treadmill does them.
Treadmill.JOBS = {
    -- Either tile wired already refuses it, so a treadmill is wired once.
    [Treadmill.WIRE] = {
        units = function(tile, with, character) return PowerBank.wiringUnits(character, WIRING) end,
        light = true, sound = "GeneratorConnect",
        blocker = function(character, tile) return Treadmill.wiredHalf(tile) and "already wired" or nil end,
        materials = PowerBank.wiringMaterials(WIRING),
    },
    -- As a part comes out of a bank: quicker than wiring, with the same tools, the wire given back.
    [Treadmill.UNWIRE] = {
        units = function(tile, with, character) return PowerBank.wiringUnits(character, WIRING, 0.5) end,
        light = true, sound = "GeneratorConnect",
        blocker = function(character, tile) return not Treadmill.isWired(tile) and "not wired" or nil end,
        materials = WIRING.tools,
    },
}

Jobs.define(Treadmill, {
    subjectOf = function(tile) return Treadmill.isTreadmill(tile) and tile or nil end, missing = "no treadmill",
})

--- Whether the treadmill of `tile` has power, from the grid or a generator, a bank included, as
--- vanilla decides an appliance has (ItemContainer.isObjectPowered).
function Treadmill.isPowered(tile)
    return ItemContainer.isObjectPowered(tile, true)
end

--- Why a run on the treadmill tile `tile` can't go now, or nil: a wired tile that feeds no bank, as
--- this side last heard (PowerBank.connectedBank), would bank nothing; an unwired one needs power
--- for its motor.
function Treadmill.runRefusal(tile)
    if Treadmill.isWired(tile) then
        return not PowerBank.connectedBank(tile) and "Tooltip_RenewableEnergy_TreadmillNotConnected" or nil
    end
    if not Treadmill.isPowered(tile) then
        return "Tooltip_RenewableEnergy_TreadmillNoPower"
    end
    return nil
end

-- The unwired treadmill tiles a run draws power through now, each to its run: on the authority,
-- and in memory rather than modData, so none outlives its run in a save or travels with a
-- treadmill picked up.
local drawing = {}

--- Marks the unwired treadmill tile `tile` as drawing power for `run` until Treadmill.stopDrawing.
function Treadmill.startDrawing(tile, run)
    drawing[tile] = run
end

--- Ends `run`'s draw through `tile`; another run's draw through it stays.
function Treadmill.stopDrawing(tile, run)
    if drawing[tile] == run then
        drawing[tile] = nil
    end
end

--- Whether a run draws power through `object` now (Treadmill.startDrawing). Authority only.
function Treadmill.isDrawing(object)
    return drawing[object] ~= nil
end

--- Calls `fn(tile)` for each tile a run draws power through now. Authority only.
function Treadmill.eachDrawing(fn)
    for tile in pairs(drawing) do
        fn(tile)
    end
end

return Treadmill
