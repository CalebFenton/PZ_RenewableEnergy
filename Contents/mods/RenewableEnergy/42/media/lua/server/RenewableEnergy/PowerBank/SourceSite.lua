-- The authority's side of the hands-on jobs at a source a bank takes and at a treadmill's tile
-- (cf_commonlib's Jobs.perform), once RenewableEnergyAction's complete() found the character at
-- the job; the rules are SourceJobs' and Treadmill's.
--
-- A bank runs in passes, each billing the hours since the last at the bank's state now. A job
-- that changes what feeds a bank first brings each bank it touches up to now, so the change counts
-- from the moment it was made rather than from the last pass.

if isClient() then return end

local Wind = require "RenewableEnergy/Wind"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local Bank = require "RenewableEnergy/PowerBank/Bank"
local BankSystem = require "RenewableEnergy/PowerBank/BankSystem"
local PanelSource = require "RenewableEnergy/PowerBank/PanelSource"
local WindSource = require "RenewableEnergy/PowerBank/WindSource"
local TreadmillSource = require "RenewableEnergy/PowerBank/TreadmillSource"
local Items = require "cf_commonlib/Items"
local Jobs = require "cf_commonlib/Jobs"
local Squares = require "cf_commonlib/Squares"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"

local SourceSite = {}

-- The bank the placed source `object` feeds, or nil.
local function bankFedBy(object)
    return BankSystem.bankOfSourceAt(object:getX(), object:getY(), object:getZ())
end

-- The bank's record of the source `object`.
local function recordOf(bank, object)
    return bank:findSource(object:getX(), object:getY(), object:getZ())
end

-- What each source job does to the source `object` and the record `bank` keeps of it, if it feeds
-- one, beyond taking its materials, by its row of SourceJobs.JOBS. Returns whether it was done.
local SOURCE = {
    [SourceJobs.CONNECT] = function(character, bank, row, object, target)
        if bank then
            bank:removeSource(object:getX(), object:getY(), object:getZ())
        end
        target:addSource(object, character)
        return true
    end,
    [SourceJobs.DISCONNECT] = function(character, bank, row, object)
        bank:removeSource(object:getX(), object:getY(), object:getZ())
        return true
    end,
    [SourceJobs.CLEAR_SNOW] = function(character, bank, row, object)
        PanelSource.clearSnow(recordOf(bank, object), object)
        return true
    end,
    -- As Seal Cracked Module seals one in hand; the bank's record takes the sealed modules at once.
    [SourceJobs.SEAL_MODULE] = function(character, bank, row, object, slot)
        local module, modules = SourceJobs.sealableModule(object, slot)
        module.condition, module.repaired = ModuleRepair.sealed(module.type, module.condition, module.repaired)
        PanelSource.writeModules(object, modules, bank and recordOf(bank, object))
        return true
    end,
    [SourceJobs.BRAKE] = function(character, bank, row, object)
        WindSource.setBraked(object, row.braked, bank and recordOf(bank, object))
        return true
    end,
    -- The character gets what is left of the broken blades. Blades of another material its kind
    -- takes make it a charger of those (WindSource.fitBlades).
    [SourceJobs.REPLACE_BLADES] = function(character, bank, row, object, item)
        local source = bank and recordOf(bank, object)
        local broke = Wind.SPEC.blades[Wind.bladesOfObject(object)]
        Items.takeItem(character, item)
        WindSource.fitBlades(object, Wind.bladesOfItem(Sources.kindOf(object), item), source)
        WindSource.setBroken(object, false, source)
        Items.giveItems(character, broke.broken)
        return true
    end,
}
SOURCE[SourceJobs.RELEASE_BRAKE] = SOURCE[SourceJobs.BRAKE]

--- The authority's side of the jobs at a source: the bank it feeds, if any, is brought up to now,
--- and the source with it from the bank's record of it, which a storm may have cracked or broken
--- while its square was unloaded; Connect Source's bank too, its controllers counted afresh from
--- its container, whatever filled it since the last pass. Each bank settles and tells the clients
--- after, done or not.
SourceSite.source = {
    open = function(object, with)
        local place = {}
        if PowerBank.isBank(with) then
            local target = BankSystem.bankAt(Squares.positionOf(with))
            place.target = target
            if target then
                target:catchUp()
                target:recount()
            end
        end
        local bank = bankFedBy(object)
        place.bank = bank
        if not bank then
            return place
        end
        if bank ~= place.target then bank:catchUp() end
        local source = recordOf(bank, object)
        -- Catch-up can disconnect a source whose square no longer works.
        if source then
            Bank.reconcileSource(source, object)
        end
        return place
    end,
    act = function(character, job, place, row, object, with)
        if job == SourceJobs.CONNECT then with = place.target end
        return SOURCE[job](character, place.bank, row, object, with)
    end,
    tell = function(place)
        if place.bank then
            place.bank:afterChange()
        end
        if place.target and place.target ~= place.bank then
            place.target:afterChange()
        end
    end,
}

--- Connects a world source through the same preparation, mutation and publication as a source
--- job, without charging materials. The caller checked the placement and connection rules.
function SourceSite.connectSource(character, object, isoObject)
    local site = SourceSite.source
    local place = site.open(object, isoObject)
    site.act(character, SourceJobs.CONNECT, place, SourceJobs.JOBS[SourceJobs.CONNECT], object, isoObject)
    site.tell(place)
end

--- The authority's side of the jobs at a treadmill's tile.
SourceSite.treadmill = Jobs.targetSite({
    [Treadmill.WIRE] = function(character, row, tile)
        TreadmillSource.wire(tile, character)
        return true
    end,
    -- What its runs banked up to now counts.
    [Treadmill.UNWIRE] = function(character, row, tile)
        local bank = bankFedBy(tile)
        if bank then
            BankSystem.dropSource(bank, tile:getX(), tile:getY(), tile:getZ())
        end
        TreadmillSource.unwire(tile, character)
        return true
    end,
})

Action.serve({ source = SourceSite.source, treadmill = SourceSite.treadmill })

return SourceSite
