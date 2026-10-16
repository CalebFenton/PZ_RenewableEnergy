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
Sources.FAMILIES = { panel = { outdoors = true }, wind = { outdoors = true }, treadmill = { outdoors = false } }

local NO_BLADES = {}

-- Kind -> { family, spec, blades }, blades the set of blade items that mend a broken wind charger.
local KINDS = {}
for kind, spec in pairs(Specs.mounts) do
    KINDS[kind] = { family = "panel", spec = spec }
end
for kind, spec in pairs(Specs.wind.turbines) do
    local blades = {}
    for _, fullType in ipairs(spec.blades or {}) do
        blades[fullType] = true
    end
    KINDS[kind] = { family = "wind", spec = spec, blades = blades }
end
KINDS.treadmill = { family = "treadmill", spec = Specs.treadmill }

--- "panel", "wind" or "treadmill" for a source kind; nil for anything else.
function Sources.familyOf(kind)
    local entry = kind and KINDS[kind]
    return entry and entry.family
end

--- The input slots a source of `kind` takes in a bank.
function Sources.slotsOf(kind)
    return KINDS[kind].spec.slots
end

--- Whether a source of `kind` must stand outdoors.
function Sources.needsOutdoors(kind)
    return Sources.FAMILIES[KINDS[kind].family].outdoors
end

--- The blade items that make a wind charger of `kind` whole again, as a set of full types; empty
--- for a kind that never breaks. Shared: don't change it.
function Sources.bladesFor(kind)
    local entry = kind and KINDS[kind]
    return entry and entry.blades or NO_BLADES
end

--- The kind of a placed source (Sprites.kindOf), the way it faces and what it is made of; nil for
--- anything else, a treadmill's tile included until it is wired to feed a bank.
function Sources.kindOf(isoObject)
    local kind, facing, material = Sprites.kindOf(Sprites.nameOf(isoObject))
    if not KINDS[kind] or (kind == "treadmill" and not Treadmill.isWired(isoObject)) then
        return nil
    end
    return kind, facing, material
end

local function isSource(isoObject)
    return Sources.kindOf(isoObject) ~= nil
end

--- The source on a square, or nil.
function Sources.on(square)
    return RenewableEnergy.findObjectOn(square, isSource)
end

--- Whether a source of `kind` may feed a bank from `square`: outdoors, unless its family works
--- indoors.
function Sources.squareOk(square, kind)
    return square ~= nil and (square:isOutside() or not Sources.needsOutdoors(kind))
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

--- Why the source `isoObject` can't be connected to the bank at `bank` ({ x, y, z }) now, or nil:
--- "out of reach" (or a square it can't work from), or "already connected" to that bank. Whether
--- the bank has the input slots is the authority's to say (Commands.connectSource).
function Sources.connectRefusal(isoObject, bank)
    local kind = Sources.kindOf(isoObject)
    if not (kind and Sources.squareOk(isoObject:getSquare(), kind)
        and PowerBank.isInReach(bank, isoObject:getX(), isoObject:getY(), isoObject:getZ())) then
        return "out of reach"
    elseif PowerBank.samePosition(PowerBank.connectedBank(isoObject), bank) then
        return "already connected"
    end
    return nil
end

return Sources
