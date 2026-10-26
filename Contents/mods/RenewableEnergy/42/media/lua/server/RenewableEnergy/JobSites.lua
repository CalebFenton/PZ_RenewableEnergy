-- The authority's side of the hands-on jobs at banks, sources, treadmills, garden lights and
-- vehicles (cf_commonlib's Jobs.perform), once RenewableEnergyAction's complete() found the
-- character at the job; the rules are each feature's job module's. Gas features keep theirs on
-- their systems.
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
local WindSource = require "RenewableEnergy/PowerBank/WindSource"
local TreadmillSource = require "RenewableEnergy/PowerBank/TreadmillSource"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local VehicleJobs = require "RenewableEnergy/Gadgets/VehicleJobs"
local ArrowBoard = require "RenewableEnergy/World/ArrowBoard"
local CarAlternator = require "RenewableEnergy/Gadgets/CarAlternator"
local SolarMaintainer = require "RenewableEnergy/Gadgets/SolarMaintainer"
local Items = require "cf_commonlib/Items"
local Jobs = require "cf_commonlib/Jobs"

local JobSites = {}
RenewableEnergy.JobSites = JobSites

-- The record of the bank `isoObject`, brought up to now; nil for none.
local function settledBank(isoObject)
    local bank = BankSystem.bankAt(PowerBank.positionOf(isoObject))
    if bank then
        BankSystem.updateBank(bank)
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

--- The authority's side of the jobs at a bank: they work on its record, brought up to now, which
--- tells the clients after, done or not.
JobSites.bank = {
    open = settledBank,
    act = function(character, job, bank, row, isoObject, with)
        return bank ~= nil and BANK[job](character, bank, row, isoObject, with)
    end,
    tell = function(bank)
        if bank then
            bank:sendStatus()
        end
    end,
}

--- Connects the source `object` to the bank `isoObject`, off the bank it fed before if any, with
--- `character` (nil for the world) as its wiring's owner. Authority only; the caller checked the
--- job (SourceJobs).
function JobSites.connectSource(character, object, isoObject)
    local previous = bankFedBy(object)
    if previous then
        BankSystem.dropSource(previous, object:getX(), object:getY(), object:getZ())
    end
    local bank = settledBank(isoObject)
    bank:addSource(object, character)
    bank:sendStatus()
end

-- What each source job does to the source `object` and the record `bank` keeps of it, if it feeds
-- one, beyond taking its materials, by its row of SourceJobs.JOBS. Returns whether it was done.
local SOURCE = {
    [SourceJobs.CONNECT] = function(character, bank, row, object, isoObject)
        JobSites.connectSource(character, object, isoObject)
        return true
    end,
    [SourceJobs.DISCONNECT] = function(character, bank, row, object)
        BankSystem.dropSource(bank, object:getX(), object:getY(), object:getZ())
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
        PanelSource.writeModules(object, modules)
        PanelSource.showCracks(object)
        Recipes.moduleRepairRecipe():addXP(character)
        local source = bank and recordOf(bank, object)
        if source then
            source.modules = PowerBank.copyModules(modules)
        end
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
        if PowerBank.isBank(with) then
            local target = settledBank(with)
            if target then
                target:recount()
            end
        end
        local bank = bankFedBy(object)
        if not bank then
            return nil
        end
        BankSystem.updateBank(bank)
        local source = recordOf(bank, object)
        if Sources.familyOf(source.kind) == "panel" then
            PanelSource.syncModules(source, object)
        elseif source.broken and not Wind.isBroken(object) then
            WindSource.setBroken(object, true, source)
        end
        return bank
    end,
    act = function(character, job, bank, row, object, with)
        return SOURCE[job](character, bank, row, object, with)
    end,
    tell = function(bank)
        if bank then
            bank:sendStatus()
        end
    end,
}

--- The authority's side of the jobs at a treadmill's tile.
JobSites.treadmill = Jobs.targetSite({
    [Treadmill.WIRE] = function(character, place, row, tile)
        TreadmillSource.wire(tile, character)
        return true
    end,
    -- What its runs banked up to now counts.
    [Treadmill.UNWIRE] = function(character, place, row, tile)
        local bank = bankFedBy(tile)
        if bank then
            BankSystem.dropSource(bank, tile:getX(), tile:getY(), tile:getZ())
        end
        TreadmillSource.unwire(tile, character)
        return true
    end,
})

--- The authority's side of the jobs at a garden light.
JobSites.light = Jobs.targetSite({
    [SolarGardenLight.REMOVE_BULB] = function(character, place, row, light)
        return SolarGardenLight.removeBulb(character, light)
    end,
    [SolarGardenLight.ADD_BULB] = function(character, place, row, light, bulb)
        return SolarGardenLight.addBulb(character, light, bulb)
    end,
})

-- What each vehicle job does, by its row of VehicleJobs.JOBS. Returns whether it was done.
local VEHICLE = {
    [VehicleJobs.ATTACH_MAINTAINER] = function(character, place, row, vehicle, item)
        return SolarMaintainer.attach(character, vehicle, item)
    end,
    [VehicleJobs.DETACH_MAINTAINER] = function(character, place, row, vehicle)
        return SolarMaintainer.detach(character, vehicle)
    end,
    [VehicleJobs.TAKE_OUT_ALTERNATOR] = function(character, place, row, vehicle)
        return CarAlternator.takeOut(character, vehicle)
    end,
    [VehicleJobs.PUT_BACK_ALTERNATOR] = function(character, place, row, vehicle, item)
        return CarAlternator.putBack(character, vehicle, item)
    end,
    [VehicleJobs.BOARD_ON] = function(character, place, row, vehicle)
        return ArrowBoard.setSwitch(vehicle, row.on)
    end,
    -- The lid unlocked, its lock broken. The cutters wear as vanilla's cutting recipes wear them
    -- (MayDegradeLight in CutUpTire, CraftRecipeData.processKeepInputItem), and a pair that breaks
    -- leaves the hands as a broken weapon does (ISDestroyStuffAction).
    [VehicleJobs.CUT_PADLOCK] = function(character, place, row, vehicle, cutters)
        if not ArrowBoard.cutPadlock(vehicle) then
            return false
        end
        if cutters:damageCheck(0, 3) then
            ItemUtils.checkWeapon(character)
        end
        return true
    end,
    [VehicleJobs.SEAL_PANEL] = function(character, place, row, vehicle, partId)
        return ArrowBoard.sealPanel(character, vehicle, partId)
    end,
}
VEHICLE[VehicleJobs.BOARD_OFF] = VEHICLE[VehicleJobs.BOARD_ON]

--- The authority's side of the jobs at a vehicle.
JobSites.vehicle = Jobs.targetSite(VEHICLE)

return JobSites
