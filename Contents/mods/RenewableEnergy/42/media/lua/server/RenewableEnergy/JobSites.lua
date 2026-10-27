-- The authority's side of the hands-on jobs at banks, sources and treadmills (cf_commonlib's
-- Jobs.perform), once RenewableEnergyAction's complete() found the character at the job; the rules
-- are each feature's job module's. Other features serve theirs from their own files.
--
-- A bank runs in passes, each billing the hours since the last at the bank's state now. A job
-- that changes that state first brings the bank up to now, so the change counts from the moment
-- it was made rather than from the last pass.

if isClient() then return end

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local Wind = require "RenewableEnergy/Wind"
local Recipes = require "RenewableEnergy/Recipes"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local BankSystem = require "RenewableEnergy/PowerBank/BankSystem"
local PanelSource = require "RenewableEnergy/PowerBank/PanelSource"
local Payers = require "RenewableEnergy/PowerBank/Payers"
local WindSource = require "RenewableEnergy/PowerBank/WindSource"
local TreadmillSource = require "RenewableEnergy/PowerBank/TreadmillSource"
local Items = require "cf_commonlib/Items"
local Jobs = require "cf_commonlib/Jobs"
local Squares = require "cf_commonlib/Squares"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"

local JobSites = {}

-- The bank brought up to now; bank jobs defer its bill until tell, after their mutation too.
local function settledBank(isoObject, deferBilling)
    local bank = BankSystem.bankAt(Squares.positionOf(isoObject))
    if bank then
        BankSystem.updateBank(bank, nil, deferBilling)
    end
    return bank
end

-- The bank the placed source `object` feeds, or nil.
local function bankFedBy(object)
    return BankSystem.bankOfSourceAt(object:getX(), object:getY(), object:getZ())
end

-- The bank's record of the source `object`.
local function recordOf(bank, object)
    return bank:findSource(object:getX(), object:getY(), object:getZ())
end

-- The bank looks at itself again after its parts changed.
local function partsChanged(bank)
    bank:powerUp()
    bank:showBatteries()
end

-- What each bank job does to the bank's record `bank` (its tile `isoObject`) beyond taking its
-- materials and giving its XP, by its row of BankJobs.JOBS. Returns whether it was done.
local BANK = {
    [BankJobs.TURN_ON] = function(character, bank, row)
        bank.on = row.on
        bank:powerUp()
        return true
    end,
    -- setConnected syncs the generator to the clients.
    [BankJobs.CONNECT] = function(character, bank, row, isoObject)
        isoObject:setConnected(row.connected)
        bank.connected = row.connected
        bank:powerUp()
        return true
    end,
    -- The bank's container filter refuses every transfer, so the part is moved here, past it.
    [BankJobs.WIRE_IN] = function(character, bank, row, isoObject, item)
        Items.takeItem(character, item)
        Items.addItem(isoObject:getContainer(), item)
        RenewableEnergy.teachOnce(character, item, PowerBank.WIRED_ONCE_KEY, Perks.Electricity,
            PowerBank.wiringFor(item:getFullType()).xp)
        partsChanged(bank)
        return true
    end,
    -- The battery leaves with the bank's shared charge as it is now.
    [BankJobs.UNWIRE] = function(character, bank, row, isoObject, item)
        bank:writeBatteries(isoObject:getContainer(), false)
        Items.takeItem(character, item)
        Items.giveItems(character, item)
        Items.giveItems(character, PowerBank.WIRE, PowerBank.wiringFor(item:getFullType()).wire)
        partsChanged(bank)
        return true
    end,
    [BankJobs.REPAIR] = function(character, bank, row, isoObject, item)
        Wear.setCondition(item, item:getCondition() + Specs.partRepair.condition)
        sendItemStats(item)
        partsChanged(bank)
        return true
    end,
    [BankJobs.RENAME] = function(character, bank, row, isoObject, name)
        name = PowerBank.trimName(name)
        bank.name = name ~= "" and name or nil
        return true
    end,
}
BANK[BankJobs.TURN_OFF] = BANK[BankJobs.TURN_ON]
BANK[BankJobs.DISCONNECT] = BANK[BankJobs.CONNECT]

--- Bank jobs catch up at the old state, mutate, then settle once, even when the job was refused:
--- catch-up alone can change the live payer set. Activation never waits for the settlement.
JobSites.bank = {
    open = function(isoObject) return settledBank(isoObject, true) end,
    act = function(character, job, bank, row, isoObject, with)
        return bank ~= nil and BANK[job](character, bank, row, isoObject, with)
    end,
    tell = function(bank)
        if bank then
            Payers.billGenerators()
            bank:sendStatus()
        end
    end,
}

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
        local module, modules = Recipes.sealableModule(object, slot)
        Recipes.useInputs(Recipes.sealInPlaceInputs(character), character)
        Recipes.sealRecord(module)
        PanelSource.writeModules(object, modules, bank and recordOf(bank, object))
        Recipes.moduleRepairRecipe():addXP(character)
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
        local broke = Specs.wind.blades[Wind.bladesOfObject(object)]
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
--- its container, whatever filled it since the last pass. Each bank tells the clients after.
JobSites.source = {
    open = function(object, with)
        local place = {}
        if PowerBank.isBank(with) then
            local target = settledBank(with)
            place.target = target
            if target then
                target:recount()
            end
        end
        local bank = bankFedBy(object)
        place.bank = bank
        if not bank then
            return place
        end
        if bank ~= place.target then BankSystem.updateBank(bank) end
        local source = recordOf(bank, object)
        -- Catch-up can disconnect a source whose square no longer works.
        if not source then
            return place
        end
        if Sources.familyOf(source.kind) == "panel" then
            PanelSource.syncModules(source, object)
        elseif source.broken and not Wind.isBroken(object) then
            WindSource.setBroken(object, true, source)
        end
        return place
    end,
    act = function(character, job, place, row, object, with)
        if job == SourceJobs.CONNECT then with = place.target end
        return SOURCE[job](character, place.bank, row, object, with)
    end,
    tell = function(place)
        if place.bank then
            place.bank:sendStatus()
        end
        if place.target and place.target ~= place.bank then
            place.target:sendStatus()
        end
    end,
}

--- Connects a world source through the same preparation, mutation and publication as a source
--- job, without charging materials. The caller checked the placement and connection rules.
function JobSites.connectSource(character, object, isoObject)
    local site = JobSites.source
    local place = site.open(object, isoObject)
    site.act(character, SourceJobs.CONNECT, place, SourceJobs.JOBS[SourceJobs.CONNECT], object, isoObject)
    site.tell(place)
end

--- The authority's side of the jobs at a treadmill's tile.
JobSites.treadmill = Jobs.targetSite({
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

Action.serve({ bank = JobSites.bank, source = JobSites.source, treadmill = JobSites.treadmill })

return JobSites
