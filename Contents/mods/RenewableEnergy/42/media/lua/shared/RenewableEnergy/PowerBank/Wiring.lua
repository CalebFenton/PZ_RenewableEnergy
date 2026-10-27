local Utilities = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Clock = require "cf_commonlib/Clock"
local Items = require "cf_commonlib/Items"

local Wiring = {}

Wiring.WIRE = "Base.ElectricWire"
Wiring.SCRAP = "Base.ElectronicsScrap"
-- Item modData: the part was wired into a bank once, which taught its Electricity XP.
Wiring.PART_ONCE_KEY = "RenewableEnergy_wiredOnce"

--- What wiring the part type `fullType` into a bank takes: its kind's Specs.wiring, with what its
--- own type's row says over it (an inverter's skill and xp), or nil if it is no part.
function Wiring.forPart(fullType)
    local kind = PowerBank.partKind(fullType)
    if not kind then
        return nil
    end
    local wiring = {}
    for key, value in pairs(Specs.wiring[kind]) do
        wiring[key] = value
    end
    for key, value in pairs(PowerBank.PARTS[kind].types[fullType].wiring or {}) do
        wiring[key] = value
    end
    return wiring
end

--- What a wiring job of `wiring` takes, as a materials list (cf_commonlib's Materials): its
--- Electricity level, tools, wire and scrap, leaving out what it takes none of.
function Wiring.materials(wiring)
    local list = {}
    if wiring.skill > 0 then
        table.insert(list, { perk = "Electricity", need = wiring.skill })
    end
    for _, tool in ipairs(wiring.tools) do
        table.insert(list, tool)
    end
    if wiring.wire > 0 then
        table.insert(list, { item = Wiring.WIRE, need = wiring.wire })
    end
    if wiring.scrap > 0 then
        table.insert(list, { item = Wiring.SCRAP, need = wiring.scrap })
    end
    return list
end

-- The share of its full time a wiring job takes at an Electricity level, falling in a straight
-- line with skill.
local function factorAt(level)
    return 1 - 0.095 * (level - 3)
end

--- The share of its full time a wiring job takes `character`, by their Electricity.
function Wiring.skillFactor(character)
    return factorAt(character:getPerkLevel(Perks.Electricity))
end

--- Action units a wiring job of `wiring` takes `character`: its seconds at Electricity 0, less
--- with skill, times `share`. A part that is gone takes no time, and its job is refused.
function Wiring.units(character, wiring, share)
    if not wiring then
        return 1
    end
    local seconds = wiring.seconds * Wiring.skillFactor(character) / factorAt(0) * (share or 1)
    return seconds * Clock.unitsPerSecond()
end

--- Teaches `character` (if any) the XP of `wiring` the first time `holder` (the part, or the
--- treadmill tile) is ever wired, marked under its modData `key`. Authority only; the caller
--- sends a placed object's modData on.
function Wiring.teach(character, holder, key, wiring)
    return Utilities.teachOnce(character, holder, key, Perks.Electricity, wiring.xp)
end

--- Gives back the wire of `wiring` on unwiring: to a character, or, with none (the thing picked
--- up or destroyed), onto a square. The electronics scrap stays spent. Authority only.
function Wiring.refund(to, wiring)
    if instanceof(to, "IsoGridSquare") then
        for _ = 1, wiring.wire do
            Items.dropOn(to, Wiring.WIRE)
        end
        return
    end
    Items.giveItems(to, Wiring.WIRE, wiring.wire)
end

return Wiring
