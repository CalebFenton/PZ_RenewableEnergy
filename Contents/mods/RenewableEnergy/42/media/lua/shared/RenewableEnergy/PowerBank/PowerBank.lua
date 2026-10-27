-- Battery banks as both sides see them: what an object is, what parts a bank takes, whether it can
-- carry a load, the sources connected to it, and the bank's summary and status as the server last
-- reported them. What each kind of source is lives in Sources; the jobs at a bank
-- in BankJobs.
--
-- Both sides register a Global Object System under SYSTEM_NAME, which keeps each bank's state
-- while its chunk is unloaded and copies its small `summary` to every client; the whole `status`
-- goes only to players watching it.

local Utilities = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local GlobalObjects = require "cf_commonlib/GlobalObjects"
local Squares = require "cf_commonlib/Squares"

local PowerBank = {}
-- A bank's containers name acceptItem by Lua path.
RenewableEnergy = RenewableEnergy or {}
RenewableEnergy.PowerBank = PowerBank

PowerBank.SYSTEM_NAME = "renewable_energy_powerbank"
-- The sendServerCommand module and command that carry a bank's status to the players watching it.
PowerBank.COMMAND_MODULE, PowerBank.STATUS_COMMAND = "RenewableEnergyBankStatus", "status"

-- Placed bank sprite, in any facing or fixed (Sprites.fixedTiles), to its Specs.banks row and the
-- item it is.
local BANKS_BY_SPRITE = {}
for fullType, bank in pairs(Specs.banks) do
    for _, name in pairs(Sprites[bank.sprite]) do
        BANKS_BY_SPRITE[name] = { fullType = fullType, spec = bank }
    end
end
for fixed, twin in pairs(Sprites.fixedTiles) do
    BANKS_BY_SPRITE[fixed] = BANKS_BY_SPRITE[twin]
end

--- Every placed bank tile's sprite name.
function PowerBank.bankSprites()
    local names = {}
    for name in pairs(BANKS_BY_SPRITE) do
        table.insert(names, name)
    end
    return names
end

--- The bank a placed sprite is: { fullType, spec }, or nil.
function PowerBank.bankOfSprite(name)
    return name and BANKS_BY_SPRITE[name]
end

--- Whether an object is a working bank: a bank tile turned into the generator that powers
--- the squares around it.
function PowerBank.isBank(isoObject)
    return instanceof(isoObject, "IsoGenerator") and PowerBank.bankOfSprite(Sprites.nameOf(isoObject)) ~= nil
end

-- A bank is a generator to the game, but none of vanilla's.
GeneratorReach.excludeGenerators(PowerBank.isBank)

--- The working bank on a square, or nil.
function PowerBank.findOn(square)
    return Squares.findObjectOn(square, PowerBank.isBank)
end

--- Where a bank may stand: inside a building, out of the weather. Returns true, or false and
--- the translation key of the reason.
function PowerBank.canPlaceBank(square)
    if square and square:getRoom() ~= nil and not square:isOutside() then
        return true
    end
    return false, "Tooltip_RenewableEnergy_BankIndoorsOnly"
end

--- Every kind of bank part: its item types (each type's Specs row), the bank record field that
--- lists the bank's parts of the kind (Bank.SAVED_FIELDS), the Specs.banks field that caps how
--- many a bank takes, and whether Electronics Scrap repairs it.
PowerBank.PARTS = {
    battery = { types = Specs.batteries, field = "batteries", max = "maxBatteries" },
    inverter = { types = Specs.inverters, field = "inverters", max = "maxInverters", repairable = true },
    charger = { types = { [Specs.charger] = {} }, field = "chargers", max = "maxChargers" },
    controller = { types = { [Specs.controller] = {} }, field = "controllers", max = "maxControllers", repairable = true },
}

-- Item type to its PARTS kind.
local PART_KINDS = {}
for kind, part in pairs(PowerBank.PARTS) do
    for fullType in pairs(part.types) do
        PART_KINDS[fullType] = kind
    end
end

--- What kind of bank part an item type is (a PowerBank.PARTS key), or nil.
function PowerBank.partKind(fullType)
    return fullType and PART_KINDS[fullType]
end

--- Whether an item type is a bank part that Electronics Scrap repairs.
function PowerBank.isRepairable(fullType)
    local kind = PowerBank.partKind(fullType)
    return kind ~= nil and PowerBank.PARTS[kind].repairable == true
end

--- The bank container's filter (ItemContainer.isItemAllowed). Parts go in only by being wired
--- in, which moves them without asking the filter, so it refuses every transfer.
function PowerBank.acceptItem(container, item)
    return false
end

--- The failsafe's thresholds, in percent of a bank's charge: below `start` it starts its generator,
--- at `stop` it stops it (the FailsafeStartCharge and FailsafeStopCharge options).
function PowerBank.failsafeRange()
    local options = SandboxVars.RenewableEnergy
    return options.FailsafeStartCharge, options.FailsafeStopCharge
end

-- What keeps a bank from carrying its load, in the order the status window names it: each a
-- Bank:state key, the test that fails it, and the translation key a job switching it on says.
local READINESS = {
    { state = "outdoors", fails = function(s) return s.indoors == false end },
    { state = "noInverter", fails = function(s) return (s.limitW or 0) <= 0 end,
        refusal = "Tooltip_RenewableEnergy_NoInverter" },
    { state = "noBatteries", fails = function(s) return (s.capacityWh or 0) <= 0 end,
        refusal = "Tooltip_RenewableEnergy_NoBatteries" },
    { state = "disconnected", fails = function(s) return s.connected == false end },
    { state = "off", fails = function(s) return not s.on end },
    { state = "grid", fails = function(s) return s.grid == true end },
}

--- What first keeps a bank in `snapshot` from carrying its load ({ indoors, limitW, capacityWh,
--- connected, on, grid }; an indoors or connected the caller doesn't know is nil, which passes):
--- the Bank:state key and, where a job is told it, its translation key; nil when it can.
function PowerBank.blocker(snapshot)
    for _, rule in ipairs(READINESS) do
        if rule.fails(snapshot) then
            return rule.state, rule.refusal
        end
    end
    return nil
end

--- The whole status of the bank `isoObject` (see Bank:buildStatus), or nil. It reaches only the
--- players watching it, and the authority keeps it only while someone does.
function PowerBank.statusOf(isoObject)
    local bank = PowerBank.objectAt(isoObject:getX(), isoObject:getY(), isoObject:getZ())
    return bank and bank.status
end

--- The bank the source on this square is connected to, as { x, y, z }, or nil. The authority
--- reads the bank's own list of sources; a client has only the summary the server last sent.
function PowerBank.bankOfSource(x, y, z)
    local found
    local authority = PowerBank.serverSystem ~= nil
    PowerBank.each(function(bank)
        local sources = authority and bank.sources or (bank.summary and bank.summary.sources)
        for _, source in ipairs(sources or {}) do
            if source.x == x and source.y == y and source.z == z then
                found = { x = bank.x, y = bank.y, z = bank.z }
                return true
            end
        end
    end)
    return found
end

--- The bank the placed source `isoObject` is connected to, as { x, y, z }, or nil.
function PowerBank.connectedBank(isoObject)
    return PowerBank.bankOfSource(isoObject:getX(), isoObject:getY(), isoObject:getZ())
end

GlobalObjects.declare(PowerBank, {
    prefix = Utilities.CLASS_PREFIX, name = "Bank", isObject = PowerBank.isBank,
    sprites = PowerBank.bankSprites(), accept = "RenewableEnergy.PowerBank.acceptItem",
})

return PowerBank
