-- What players do to banks, run on the authority: from a timed action's complete(), or the refresh
-- of a bank whose status window a client opened (BankSystem:OnClientCommand). Every command
-- checks the world again, since a client's view can be stale or forged. Each returns whether it
-- did anything and, if not, why (a translation key where the player is told).
--
-- A bank runs in passes, each billing the hours since the last at the bank's state now. A command
-- that changes that state first brings the bank up to now (settle), so the change counts from the
-- moment it was made rather than from the last pass.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Wind"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/BankSystem"
require "RenewableEnergy/PowerBank/PanelSource"
require "RenewableEnergy/PowerBank/WindSource"
require "RenewableEnergy/PowerBank/TreadmillSource"

RenewableEnergy = RenewableEnergy or {}
local Specs, Wind, PowerBank, Wear = RenewableEnergy.Specs, RenewableEnergy.Wind, RenewableEnergy.PowerBank, RenewableEnergy.Wear
local Sources, Treadmill, BankSystem = RenewableEnergy.Sources, RenewableEnergy.Treadmill, RenewableEnergy.BankSystem
local PanelSource, WindSource = RenewableEnergy.PanelSource, RenewableEnergy.WindSource
local isPosition, bankAt = PowerBank.isPosition, BankSystem.bankAt

local Commands = {}
RenewableEnergy.Commands = Commands

-- Longest name a bank takes.
local NAME_LENGTH = 32

local function sourceAt(position)
    return isPosition(position) and Sources.on(getSquare(position.x, position.y, position.z)) or nil
end

local function bankOfSource(position)
    local found = isPosition(position) and PowerBank.bankOfSource(position.x, position.y, position.z)
    return found and bankAt(found) or nil
end

-- The bank `position` names a source of, and its record of that source; nil for a source that
-- feeds no bank.
local function recordOf(position)
    local bank = bankOfSource(position)
    return bank, bank and bank:findSource(position.x, position.y, position.z)
end

-- The bank's container, if its chunk is loaded.
local function containerOf(bank)
    local isoObject = bank:getIsoObject()
    return isoObject and isoObject:getContainer()
end

-- Brings `bank` (nil for none) up to now before a change to it.
local function settle(bank)
    if bank then
        BankSystem.updateBank(bank)
    end
end

-- The bank looks at itself again after its parts changed.
local function refreshBank(bank)
    bank:powerUp()
    bank:showBatteries()
    bank:sendStatus()
end

function Commands.setBankOn(player, args)
    local bank = bankAt(args.bank)
    if not bank then return false, "no bank" end
    local on = args.on == true
    local refusal = PowerBank.switchRefusal(bank:buildSummary(), on)
    if refusal then return false, refusal end
    settle(bank)
    bank.on = on
    bank:powerUp()
    bank:sendStatus()
    return true
end

function Commands.setBankConnected(player, args)
    local bank = bankAt(args.bank)
    local isoObject = bank and bank:getIsoObject()
    if not isoObject then return false, "no bank" end
    local connected = args.connected == true
    local refusal = PowerBank.connectRefusal(player, isoObject, bank, connected)
    if refusal then return false, refusal end
    settle(bank)
    -- setConnected syncs the generator to the clients.
    isoObject:setConnected(connected)
    bank.connected = connected
    bank:powerUp()
    bank:sendStatus()
    return true
end

function Commands.connectSource(player, args)
    local bank = bankAt(args.bank)
    local source = sourceAt(args.source)
    if not (bank and source) then return false, "no bank or source" end
    -- A source feeds one bank, and connecting it again to the bank it feeds leaves it as it is,
    -- snow and all.
    local refusal = Sources.connectRefusal(source, bank)
    if refusal then return false, refusal end
    -- The container is the truth about the controllers, whatever filled it since the last pass.
    bank:recount()
    refusal = Sources.slotRefusal(Sources.kindOf(source), bank:inputSlots() - bank:slotsUsed())
    if refusal then return false, refusal end
    local previous = bankOfSource(args.source)
    if previous then
        settle(previous)
        previous:removeSource(source:getX(), source:getY(), source:getZ())
        previous:sendStatus()
    end
    settle(bank)
    bank:addSource(source, player)
    bank:sendStatus()
    return true
end

function Commands.disconnectSource(player, args)
    local bank = bankOfSource(args.source)
    if not bank then return false, "not connected" end
    settle(bank)
    bank:removeSource(args.source.x, args.source.y, args.source.z)
    bank:sendStatus()
    return true
end

function Commands.clearSnow(player, args)
    local bank, source = recordOf(args.source)
    if not source then return false, "not connected" end
    settle(bank)
    PanelSource.clearSnow(source, sourceAt(args.source))
    bank:sendStatus()
    return true
end

-- Brakes a wind charger, or lets it go, and the record of the bank it feeds with it.
function Commands.setBrake(player, args)
    local object = sourceAt(args.source)
    if not (object and Wind.isCharger(object)) then return false, "no wind charger" end
    local bank, source = recordOf(args.source)
    settle(bank)
    WindSource.setBraked(object, args.braked == true, source)
    if bank then
        bank:sendStatus()
    end
    return true
end

--- Puts the blades `itemId` from the player's inventory on the wind charger at `args.source`,
--- whose blades a storm broke. Its bank's record, if it feeds one, mends with the object.
function Commands.replaceBlades(player, args)
    local object = sourceAt(args.source)
    if not (object and Wind.isCharger(object)) then return false, "no wind charger" end
    local bank, source = recordOf(args.source)
    settle(bank)
    -- A gale may have broken the record since the last pass brought it to the object.
    if source and source.broken and not Wind.isBroken(object) then
        WindSource.setBroken(object, true, source)
    end
    local item = type(args.itemId) == "number" and player:getInventory():getItemWithIDRecursiv(args.itemId) or nil
    local refusal = Wind.bladesRefusal(object, item)
    if refusal then return false, refusal end
    RenewableEnergy.takeItem(player, item)
    WindSource.setBroken(object, false, source)
    if bank then
        bank:sendStatus()
    end
    return true
end

-- The treadmill tile at `position`, or nil.
local function treadmillAt(position)
    return isPosition(position) and Treadmill.on(getSquare(position.x, position.y, position.z)) or nil
end

--- Wires the treadmill tile at `args.source` to feed a bank, from the player's wire and scrap.
function Commands.wireTreadmill(player, args)
    local object = treadmillAt(args.source)
    if not (player and object) then return false, "no treadmill" end
    local refusal = Treadmill.wiringRefusal(player, object)
    if refusal then return false, refusal end
    local wiring = Specs.treadmill.wiring
    RenewableEnergy.takeItems(player, PowerBank.WIRE, wiring.wire)
    RenewableEnergy.takeItems(player, PowerBank.SCRAP, wiring.scrap)
    if RenewableEnergy.TreadmillSource.wire(object) then
        addXp(player, Perks.Electricity, wiring.xp)
    end
    return true
end

--- Unwires the wired treadmill tile at `args.source`: it stops feeding its bank, and the player
--- gets its wire back.
function Commands.unwireTreadmill(player, args)
    local object = treadmillAt(args.source)
    if not (player and object and Treadmill.isWired(object)) then return false, "not wired" end
    local bank = bankOfSource(args.source)
    if bank then
        -- What its runs banked up to now counts.
        settle(bank)
        bank:removeSource(args.source.x, args.source.y, args.source.z)
        bank:sendStatus()
    end
    RenewableEnergy.TreadmillSource.unwire(object, player)
    return true
end

--- Banks `args.hours` of running on the wired treadmill at `args.source` with the bank it feeds,
--- for its next passes. Runs from the treadmill action's own clock on the authority.
function Commands.runTreadmill(player, args)
    local object = sourceAt(args.source)
    local _, source = recordOf(args.source)
    if not (object and source and Treadmill.isWiredTile(object)) then
        return false, "Tooltip_RenewableEnergy_TreadmillNotConnected"
    end
    local hours = math.max(0, math.min(tonumber(args.hours) or 0, Specs.treadmill.runMinutes / 60))
    RenewableEnergy.TreadmillSource.credit(source, Specs.treadmill.watts * hours)
    return true
end

--- Wire the part `itemId` from the player's inventory into the bank. The bank's container
--- filter refuses every transfer, so the part is moved here, past it.
function Commands.wireIn(player, args)
    local bank = bankAt(args.bank)
    local container = bank and containerOf(bank)
    if not (player and container and type(args.itemId) == "number") then return false, "no bank" end
    local item = player:getInventory():getItemWithIDRecursiv(args.itemId)
    local refusal = PowerBank.wiringRefusal(player, bank:getIsoObject(), item)
    if refusal then return false, refusal end
    settle(bank)
    local wiring = PowerBank.wiringFor(item:getFullType())
    RenewableEnergy.takeItems(player, PowerBank.WIRE, wiring.wire)
    RenewableEnergy.takeItems(player, PowerBank.SCRAP, wiring.scrap)
    RenewableEnergy.takeItem(player, item)
    container:AddItem(item)
    sendAddItemToContainer(container, item)
    local data = item:getModData()
    if not data[PowerBank.WIRED_ONCE] then
        data[PowerBank.WIRED_ONCE] = true
        addXp(player, Perks.Electricity, wiring.xp)
    end
    refreshBank(bank)
    return true
end

--- Unwire the part `itemId` from the bank: the player gets it back with its wire.
function Commands.unwire(player, args)
    local bank = bankAt(args.bank)
    local container = bank and containerOf(bank)
    if not (player and container and type(args.itemId) == "number") then return false, "no bank" end
    local item = container:getItemWithID(args.itemId)
    local refusal = PowerBank.unwireBlocker(bank:getIsoObject(), item)
    if refusal then return false, refusal end
    -- The battery leaves with the bank's shared charge as it is now.
    settle(bank)
    bank:writeBatteries(container, false)
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    RenewableEnergy.giveItems(player, item)
    RenewableEnergy.giveItems(player, PowerBank.WIRE, PowerBank.wiringFor(item:getFullType()).wire)
    refreshBank(bank)
    return true
end

--- Repair the inverter or controller `itemId` in the bank with one Electronics Scrap.
function Commands.repairPart(player, args)
    local bank = bankAt(args.bank)
    local container = bank and containerOf(bank)
    if not (player and container and type(args.itemId) == "number") then return false, "no bank" end
    local item = container:getItemWithID(args.itemId)
    local refusal = PowerBank.repairRefusal(player, item)
    if refusal then return false, refusal end
    settle(bank)
    RenewableEnergy.takeItems(player, PowerBank.SCRAP, 1)
    Wear.setCondition(item, item:getCondition() + Specs.partRepair.condition)
    sendItemStats(item)
    addXp(player, Perks.Electricity, Specs.partRepair.xp)
    refreshBank(bank)
    return true
end

--- Name the bank; an empty name gives it back its tier's name.
function Commands.rename(player, args)
    local bank = bankAt(args.bank)
    if not (bank and type(args.name) == "string") then return false, "no bank" end
    local name = args.name:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, NAME_LENGTH)
    bank.name = name ~= "" and name or nil
    bank:sendStatus()
    return true
end

function Commands.refresh(player, args)
    local bank = bankAt(args.bank)
    if not bank then return false, "no bank" end
    bank:refresh()
    return true
end

--- Run command `name` now. Returns whether it did anything, and why not.
function PowerBank.perform(player, name, args)
    local command = Commands[name]
    if not (command and type(args) == "table") then
        return false, "unknown command"
    end
    return command(player, args)
end

return Commands
