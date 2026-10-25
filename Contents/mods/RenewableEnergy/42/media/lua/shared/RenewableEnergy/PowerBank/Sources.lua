-- Every kind of source a bank takes, by its Sprites.kindOf kind: its family, which decides how a
-- bank runs it (server/RenewableEnergy/PowerBank/<Family>Source.lua), and its row of Specs. A new
-- kind needs only its Specs row and its sprites.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Treadmill"

RenewableEnergy = RenewableEnergy or {}
local Sources = {}
RenewableEnergy.Sources = Sources

local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites
local PowerBank, Treadmill = RenewableEnergy.PowerBank, RenewableEnergy.Treadmill

-- Whether a source of each family must stand outdoors: a treadmill works under a roof.
local OUTDOORS = { panel = true, wind = true, treadmill = false }

-- Kind -> { family, spec, isPlaced }: isPlaced(isoObject), if any, whether a tile of the kind is
-- a source yet.
local KINDS = {}
for kind, spec in pairs(Specs.mounts) do
    KINDS[kind] = { family = "panel", spec = spec }
end
for kind, spec in pairs(Specs.wind.turbines) do
    KINDS[kind] = { family = "wind", spec = spec }
end
-- A treadmill's tile is a source once it is wired to feed a bank.
KINDS.treadmill = { family = "treadmill", spec = Specs.treadmill, isPlaced = Treadmill.isWired }

--- "panel", "wind" or "treadmill" for a source kind; nil for anything else.
function Sources.familyOf(kind)
    local entry = kind and KINDS[kind]
    return entry and entry.family
end

--- The input slots a source of `kind` takes in a bank.
function Sources.slotsOf(kind)
    return KINDS[kind].spec.slots
end

--- Why a source of `kind` can't go on a bank with `freeSlots` input slots free, or nil. The
--- authority counts them from the bank's container; a client has its summary's freeSlots.
function Sources.slotRefusal(kind, freeSlots)
    if Sources.slotsOf(kind) > freeSlots then
        return "Tooltip_RenewableEnergy_NoInputSlot"
    end
    return nil
end

--- Why no source may be connected to a bank whose connected flag is `connected` (the bank's own
--- Connect Bank, as a generator's), or nil. A client passes its copy of the generator's flag,
--- which IsoGenerator.setConnected syncs; the authority its record's, nil on banks saved before
--- it was kept, all of them connected. Sources already on a bank stay when it is disconnected.
function Sources.bankRefusal(connected)
    if connected == false then
        return "Tooltip_RenewableEnergy_BankNotConnected"
    end
    return nil
end

--- Whether snow lies on a source of `kind` until someone sweeps it off (Specs.mounts holdsSnow
--- without shedsSnow).
function Sources.sweepable(kind)
    local entry = kind and KINDS[kind]
    return entry ~= nil and entry.spec.holdsSnow == true and not entry.spec.shedsSnow
end

--- The kind of a placed source (Sprites.kindOf), the way it faces and what it is made of; nil for
--- anything else, a treadmill's tile included until it is wired to feed a bank.
function Sources.kindOf(isoObject)
    local kind, facing, material = Sprites.kindOfObject(isoObject)
    local entry = kind and KINDS[kind]
    if not entry or (entry.isPlaced and not entry.isPlaced(isoObject)) then
        return nil
    end
    return kind, facing, material
end

local function isSource(isoObject)
    return Sources.kindOf(isoObject) ~= nil
end

--- The source on a square, or nil.
function Sources.findOn(square)
    return RenewableEnergy.findObjectOn(square, isSource)
end

--- Whether a source of `kind` may feed a bank from `square`: outdoors, unless its family works
--- indoors.
function Sources.squareOk(square, kind)
    return square ~= nil and (square:isOutside() or not OUTDOORS[KINDS[kind].family])
end

--- The banks, as { x, y, z }, a source of `kind` at x, y, z may be connected to.
function Sources.banksInReach(x, y, z, kind)
    local found = {}
    if not Sources.squareOk(getSquare(x, y, z), kind) then
        return found
    end
    PowerBank.eachBank(function(bank)
        if PowerBank.isInReach(bank, x, y, z) then
            table.insert(found, { x = bank.x, y = bank.y, z = bank.z })
        end
    end)
    return found
end

--- Why the source `isoObject` can't be connected to the bank at `bankPosition` ({ x, y, z }) now,
--- or nil: "out of reach" (or a square it can't work from), or "already connected" to that bank.
--- Whether the bank has the input slots is the authority's to say (BankJobs.connectSource).
function Sources.connectRefusal(isoObject, bankPosition)
    local kind = Sources.kindOf(isoObject)
    if not (kind and Sources.squareOk(isoObject:getSquare(), kind)
        and PowerBank.isInReach(bankPosition, isoObject:getX(), isoObject:getY(), isoObject:getZ())) then
        return "out of reach"
    elseif PowerBank.samePosition(PowerBank.connectedBank(isoObject), bankPosition) then
        return "already connected"
    end
    return nil
end

--- The loaded sources the bank at `bankPosition` ({ x, y, z }) could take now
--- (Sources.connectRefusal), those connected to another bank included.
function Sources.sourcesInReach(bankPosition)
    local reach = Specs.sourceReach
    local found = {}
    for z = bankPosition.z - reach.levels, bankPosition.z + reach.levels do
        RenewableEnergy.eachSquareAround(bankPosition.x, bankPosition.y, z, reach.tiles, function(square)
            local source = Sources.findOn(square)
            if source and not Sources.connectRefusal(source, bankPosition) then
                table.insert(found, source)
            end
        end)
    end
    return found
end

return Sources
