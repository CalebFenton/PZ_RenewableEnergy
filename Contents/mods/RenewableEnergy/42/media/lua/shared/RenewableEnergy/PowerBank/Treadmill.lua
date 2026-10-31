-- Vanilla's treadmill (Sprites.treadmill), two tiles. Unwired, a run on it draws its motor's watts
-- like any appliance. Connected to a bank, which wires its motor to make power, a run on it banks
-- watt-hours instead.

local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Wiring = require "RenewableEnergy/PowerBank/Wiring"
local Jobs = require "cf_commonlib/Jobs"
local Squares = require "cf_commonlib/Squares"

local Treadmill = {}

-- Tile modData: the tile wired to feed a bank (one of the treadmill's two tiles). Connecting wires
-- it and disconnecting unwires it; a tile left wired without a bank (its bank gone, or out of
-- reach) connects again without wiring, or is unwired on its own.
Treadmill.WIRED_KEY = "RenewableEnergy_treadmillWired"
-- The item dismantling a treadmill gives.
Treadmill.MOTOR = "RenewableEnergy.TreadmillMotor"

-- Wiring cost (as Specs.wiring), the input slots it takes in a bank, watts a runner puts in (an
-- hour of running is roughly an hour of a fridge-freezer), run length, and an hour's cost and XP.
-- Unwired, a run draws drawFuel: vanilla bills nothing for a treadmill, so it is billed like the
-- other clothing appliances, at IsoGenerator.ClothingAppliancePowerConsumption, a static field Lua
-- can't read.
Treadmill.SPEC = {
    slots = 1,
    wiring = { seconds = 90, wire = 2, scrap = 1, tools = { Specs.SCREWDRIVER },
        skill = 2, xp = 10 },
    watts = 240, runMinutes = 30, drawFuel = 0.09,
    endurancePerHour = 0.6, thirstPerHour = 0.2,
    xpPerHour = { Fitness = 20, Sprinting = 15 },
}

-- The step in x and y to the square on each side, by compass letter: north is up the map, -y.
local FACING_STEPS = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }
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

Treadmill.CONNECT = "ConnectTreadmill"
Treadmill.UNWIRE = "UnwireTreadmill"

local WIRING = Treadmill.SPEC.wiring

-- Why the bank `bank` can't take the treadmill tile `tile` now, or nil: Connect Source's refusals
-- (PowerBank.sourceRefusal), for a tile that isn't a source until it is wired.
local function bankRefusal(tile, bank)
    return PowerBank.sourceRefusal(bank, Treadmill.SPEC.slots, function(bankPosition)
        return not PowerBank.inSourceReach(bankPosition, tile:getX(), tile:getY(), tile:getZ()) and "out of reach" or nil
    end)
end

-- The jobs at a treadmill's tile, by name (cf_commonlib's Jobs). Connect wires a loose treadmill's
-- motor to make power, as a part is wired in, and connects it to the bank `with`; a wired one
-- moves between banks by Connect Source like any source. Unwire takes it out of its bank and
-- unwires it, labelled Disconnect while it feeds one.
Treadmill.JOBS = {
    -- Either tile wired already refuses it, so a treadmill is wired once.
    [Treadmill.CONNECT] = {
        units = function(tile, bank, character) return Wiring.units(character, WIRING) end,
        light = true, sound = "GeneratorConnect", tooltip = "Tooltip_RenewableEnergy_ConnectTreadmill",
        blocker = function(character, tile, bank)
            return Treadmill.wiredHalf(tile) and "already wired" or bankRefusal(tile, bank)
        end,
        materials = Wiring.materials(WIRING),
    },
    -- As a part comes out of a bank: quicker than wiring, with the same tools, the wire given back.
    [Treadmill.UNWIRE] = {
        units = function(tile, with, character) return Wiring.units(character, WIRING, 0.5) end,
        light = true, sound = "GeneratorConnect", tooltip = "Tooltip_RenewableEnergy_UnwireTreadmill",
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
