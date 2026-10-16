-- What players do to banks, run on the authority: from a timed action's complete(), or the refresh
-- of a bank whose status window a client opened (BankSystem:OnClientCommand). Every command
-- checks the world again, since a client's view can be stale or forged. Each returns whether it
-- did anything and, if not, why (a translation key where the player is told).

if isClient() then return end

require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/BankSystem"

RenewableEnergy = RenewableEnergy or {}
local Specs, PowerBank, Wear = RenewableEnergy.Specs, RenewableEnergy.PowerBank, RenewableEnergy.Wear
local isPosition, bankAt = PowerBank.isPosition, RenewableEnergy.BankSystem.bankAt

local Commands = {}
RenewableEnergy.Commands = Commands

-- Longest name a bank takes.
local NAME_LENGTH = 32

local function sourceAt(position)
    return isPosition(position) and PowerBank.sourceOn(getSquare(position.x, position.y, position.z)) or nil
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

-- Take `count` items of `fullType` from the character's inventory, bags included.
local function consume(character, fullType, count)
    if count <= 0 then return end
    local items = character:getInventory():getSomeTypeRecurse(fullType, count)
    for i = 0, items:size() - 1 do
        RenewableEnergy.takeItem(character, items:get(i))
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
    bank.on = args.on == true
    bank:powerUp()
    bank:sendStatus()
    return true
end

function Commands.connectSource(player, args)
    local bank = bankAt(args.bank)
    local source = sourceAt(args.source)
    if not (bank and source) then return false, "no bank or source" end
    local x, y, z = source:getX(), source:getY(), source:getZ()
    if not (PowerBank.sourceSquareOk(source:getSquare(), PowerBank.sourceKind(source)) and PowerBank.isInReach(bank, x, y, z)) then
        return false, "out of reach"
    end
    -- A source feeds one bank, and connecting it again to the bank it feeds leaves it as it is,
    -- snow and all.
    local previous = bankOfSource(args.source)
    if previous == bank then
        return false, "already connected"
    end
    -- The container is the truth about the controllers, whatever filled it since the last pass.
    bank:recount()
    local kind = PowerBank.sourceKind(source)
    if bank:slotsUsed() + PowerBank.slotsOf(kind) > bank:inputSlots() then
        return false, "Tooltip_RenewableEnergy_NoInputSlot"
    end
    if previous then
        previous:removeSource(x, y, z)
        previous:sendStatus()
    end
    if PowerBank.isWind(kind) then
        -- A wind charger teaches its wiring the first time it is ever connected.
        if not source:getModData()[PowerBank.CONNECTED_ONCE] then
            source:getModData()[PowerBank.CONNECTED_ONCE] = true
            source:transmitModData()
            addXp(player, Perks.Electricity, Specs.connectXp * PowerBank.slotsOf(kind))
        end
    elseif PowerBank.isPanel(kind) then
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
    bank:clearSnow(source, sourceAt(args.source))
    bank:sendStatus()
    return true
end

-- Brakes a wind charger, or lets it go. One on no bank keeps the brake on its object.
function Commands.setBrake(player, args)
    local object = sourceAt(args.source)
    if not (object and PowerBank.isWind(PowerBank.sourceKind(object))) then return false, "no wind charger" end
    local bank = bankOfSource(args.source)
    local source = bank and bank:findSource(args.source.x, args.source.y, args.source.z)
    if source then
        bank:setBrake(source, args.braked == true, object)
        bank:sendStatus()
    else
        PowerBank.setBraked(object, args.braked == true)
    end
    return true
end

--- Puts the blades `itemId` from the player's inventory on the wind charger at `args.source`,
--- whose blades a storm broke. Its bank's record, if it feeds one, mends with the object.
function Commands.replaceBlades(player, args)
    local object = sourceAt(args.source)
    local kind = object and PowerBank.sourceKind(object)
    if not PowerBank.isWind(kind) then return false, "no wind charger" end
    local bank = bankOfSource(args.source)
    local source = bank and bank:findSource(args.source.x, args.source.y, args.source.z)
    if not (PowerBank.isBroken(object) or (source and source.broken)) then return false, "not broken" end
    local item = type(args.itemId) == "number" and player:getInventory():getItemWithIDRecursiv(args.itemId)
    if not (item and PowerBank.bladesFor(kind)[item:getFullType()]) then return false, "no blades" end
    RenewableEnergy.takeItem(player, item)
    PowerBank.setBroken(object, false)
    if source then
        source.broken = false
        bank:sendStatus()
    end
    return true
end

--- Wires the treadmill tile at `args.source` to feed a bank, from the player's wire and scrap.
function Commands.wireTreadmill(player, args)
    local object = isPosition(args.source) and PowerBank.treadmillOn(getSquare(args.source.x, args.source.y, args.source.z))
    if not (player and object) then return false, "no treadmill" end
    if PowerBank.isWiredTreadmill(object) then return false, "already wired" end
    local short = RenewableEnergy.firstUnmet(PowerBank.treadmillNeeds(player))
    if short then return false, short.kind end
    local wiring = Specs.treadmill.wiring
    consume(player, PowerBank.WIRE, wiring.wire)
    consume(player, PowerBank.SCRAP, wiring.scrap)
    object:getModData()[PowerBank.TREADMILL_WIRED] = true
    object:transmitModData()
    addXp(player, Perks.Electricity, wiring.xp)
    return true
end

--- Banks `args.hours` of running on the wired treadmill at `args.source` with the bank it feeds,
--- for that bank's next pass. Runs from the treadmill action's own clock on the authority.
function Commands.runTreadmill(player, args)
    local object = sourceAt(args.source)
    if not (object and PowerBank.sourceKind(object) == "treadmill") then return false, "no treadmill" end
    local bank = bankOfSource(args.source)
    if not bank then return false, "not connected" end
    local hours = math.max(0, math.min(tonumber(args.hours) or 0, Specs.treadmill.runMinutes / 60))
    bank:creditRun(args.source.x, args.source.y, args.source.z, Specs.treadmill.watts * hours)
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
    consume(player, PowerBank.WIRE, wiring.wire)
    consume(player, PowerBank.SCRAP, wiring.scrap)
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
    Actions.addOrDropItem(player, item)
    for _ = 1, wiring.wire do
        Actions.addOrDropItem(player, instanceItem(PowerBank.WIRE))
    end
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
    consume(player, PowerBank.SCRAP, 1)
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
