-- What players do to banks, run on the authority: from a timed action's complete(), or the refresh
-- of a bank whose status window a client opened (BankSystem:OnClientCommand). Every command
-- checks the world again, since a client's view can be stale or forged. Each returns whether it
-- did anything and, if not, why (a translation key where the player is told).

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
require "RenewableEnergy/PowerBank/TreadmillSource"

RenewableEnergy = RenewableEnergy or {}
local Specs, Wind, PowerBank, Wear = RenewableEnergy.Specs, RenewableEnergy.Wind, RenewableEnergy.PowerBank, RenewableEnergy.Wear
local Sources, Treadmill = RenewableEnergy.Sources, RenewableEnergy.Treadmill
local isPosition, bankAt = PowerBank.isPosition, RenewableEnergy.BankSystem.bankAt

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

-- The bank's container, if its chunk is loaded.
local function containerOf(bank)
    local isoObject = bank:getIsoObject()
    return isoObject and isoObject:getContainer()
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
    bank.on = args.on == true
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
    local kind = Sources.kindOf(source)
    if bank:slotsUsed() + Sources.slotsOf(kind) > bank:inputSlots() then
        return false, "Tooltip_RenewableEnergy_NoInputSlot"
    end
    local x, y, z = source:getX(), source:getY(), source:getZ()
    local previous = bankOfSource(args.source)
    if previous then
        previous:removeSource(x, y, z)
        previous:sendStatus()
    end
    local family = Sources.familyOf(kind)
    if family == "wind" then
        -- A wind charger teaches its wiring the first time it is ever connected.
        if not source:getModData()[PowerBank.CONNECTED_ONCE] then
            source:getModData()[PowerBank.CONNECTED_ONCE] = true
            source:transmitModData()
            addXp(player, Perks.Electricity, Specs.connectXp * Sources.slotsOf(kind))
        end
    elseif family == "panel" then
        -- Each module teaches a little the first time it is ever connected, and the record keeps
        -- that, through moves between banks and with the module when it comes off its mount.
        local modules = PowerBank.modulesOf(source, kind)
        local learned = 0
        for _, module in ipairs(modules) do
            if not module.connected then
                module.connected = true
                learned = learned + 1
            end
        end
        if learned > 0 then
            PowerBank.writeModules(source, modules)
            addXp(player, Perks.Electricity, Specs.connectXp * learned)
        end
    end
    bank:addSource(source)
    bank:sendStatus()
    return true
end

function Commands.disconnectSource(player, args)
    local bank = bankOfSource(args.source)
    if not (bank and bank:removeSource(args.source.x, args.source.y, args.source.z)) then
        return false, "not connected"
    end
    bank:sendStatus()
    return true
end

function Commands.clearSnow(player, args)
    local bank = bankOfSource(args.source)
    local source = bank and bank:findSource(args.source.x, args.source.y, args.source.z)
    if not source then return false, "not connected" end
    RenewableEnergy.PanelSource.clearSnow(source, sourceAt(args.source))
    bank:sendStatus()
    return true
end

-- Brakes a wind charger, or lets it go, and the record of the bank it feeds with it.
function Commands.setBrake(player, args)
    local object = sourceAt(args.source)
    if not (object and Sources.familyOf(Sources.kindOf(object)) == "wind") then return false, "no wind charger" end
    Wind.setBraked(object, args.braked == true)
    local bank = bankOfSource(args.source)
    local source = bank and bank:findSource(args.source.x, args.source.y, args.source.z)
    if source then
        source.braked = args.braked == true
        bank:sendStatus()
    end
    return true
end

--- Puts the blades `itemId` from the player's inventory on the wind charger at `args.source`,
--- whose blades a storm broke. Its bank's record, if it feeds one, mends with the object.
function Commands.replaceBlades(player, args)
    local object = sourceAt(args.source)
    if not (object and Sources.familyOf(Sources.kindOf(object)) == "wind") then return false, "no wind charger" end
    local bank = bankOfSource(args.source)
    local source = bank and bank:findSource(args.source.x, args.source.y, args.source.z)
    -- A gale may have broken the record since the last pass brought it to the object.
    if source and source.broken and not Wind.isBroken(object) then
        Wind.setBroken(object, true)
    end
    local item = type(args.itemId) == "number" and player:getInventory():getItemWithIDRecursiv(args.itemId) or nil
    local refusal = Wind.bladesRefusal(object, item)
    if refusal then return false, refusal end
    RenewableEnergy.takeItem(player, item)
    Wind.setBroken(object, false)
    if source then
        source.broken = false
        bank:sendStatus()
    end
    return true
end

--- Wires the treadmill tile at `args.source` to feed a bank, from the player's wire and scrap.
function Commands.wireTreadmill(player, args)
    local object = isPosition(args.source) and Treadmill.on(getSquare(args.source.x, args.source.y, args.source.z))
    if not (player and object) then return false, "no treadmill" end
    local refusal = Treadmill.wiringRefusal(player, object)
    if refusal then return false, refusal end
    local wiring = Specs.treadmill.wiring
    RenewableEnergy.takeItems(player, PowerBank.WIRE, wiring.wire)
    RenewableEnergy.takeItems(player, PowerBank.SCRAP, wiring.scrap)
    object:getModData()[Treadmill.WIRED] = true
    object:transmitModData()
    addXp(player, Perks.Electricity, wiring.xp)
    return true
end

--- Banks `args.hours` of running on the wired treadmill at `args.source` with the bank it feeds,
--- for its next passes. Runs from the treadmill action's own clock on the authority.
function Commands.runTreadmill(player, args)
    local bank = bankOfSource(args.source)
    local source = bank and bank:findSource(args.source.x, args.source.y, args.source.z)
    if not (source and Sources.familyOf(source.kind) == "treadmill" and sourceAt(args.source)) then
        return false, "not connected"
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
    local wiring = item and PowerBank.wiringFor(item:getFullType())
    if not wiring then return false, "Tooltip_RenewableEnergy_NotAPart" end
    if player:tooDarkToRead() then return false, "Tooltip_RenewableEnergy_TooDark" end
    -- The battery leaves with the bank's shared charge.
    bank:writeBatteries(container, false)
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    RenewableEnergy.giveItems(player, item)
    RenewableEnergy.giveItems(player, PowerBank.WIRE, wiring.wire)
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
