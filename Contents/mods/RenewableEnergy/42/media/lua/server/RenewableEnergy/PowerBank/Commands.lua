-- What players do to banks, run on the authority: from a timed action's complete(), or from
-- a client's PowerBank.command. Every command checks the world again, since a client's view
-- can be stale or forged.

if isClient() then return end

require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/BankSystem"

local PowerBank = RenewableEnergy.PowerBank

local Commands = {}

local function bankAt(position)
    local system = PowerBank.serverSystem
    if not (system and type(position) == "table" and position.x and position.y and position.z) then
        return nil
    end
    return system:getLuaObjectAt(position.x, position.y, position.z)
end

local function sourceAt(position)
    local square = type(position) == "table" and position.x and getSquare(position.x, position.y, position.z)
    local objects = square and square:getObjects()
    for i = 0, (objects and objects:size() or 0) - 1 do
        local object = objects:get(i)
        if PowerBank.sourceKind(object) then
            return object
        end
    end
    return nil
end

local function bankOfSource(position)
    local found = PowerBank.bankOfSource(position.x, position.y, position.z)
    return found and bankAt(found)
end

function Commands.setBankOn(player, args)
    local bank = bankAt(args.bank)
    if not bank then return false, "no bank" end
    bank.on = args.on == true
    bank:powerUp()
    bank:sendStatus()
    return true
end

function Commands.resetInverter(player, args)
    local bank = bankAt(args.bank)
    if not bank then return false, "no bank" end
    bank:powerUp()
    bank:sendStatus()
    return true
end

function Commands.connectSource(player, args)
    local bank = bankAt(args.bank)
    local source = sourceAt(args.source)
    if not (bank and source) then return false, "no bank or panel" end
    local x, y, z = source:getX(), source:getY(), source:getZ()
    if not (source:getSquare():isOutside() and PowerBank.isInReach(bank, x, y, z)) then
        return false, "out of reach"
    end
    -- A panel feeds one bank.
    local previous = bankOfSource(args.source)
    if previous then
        previous:removeSource(x, y, z)
        previous:sendStatus()
    end
    bank:addSource(source)
    bank:sendStatus()
    return true
end

function Commands.disconnectSource(player, args)
    local bank = type(args.source) == "table" and bankOfSource(args.source)
    if not (bank and bank:removeSource(args.source.x, args.source.y, args.source.z)) then
        return false, "not connected"
    end
    bank:sendStatus()
    return true
end

function Commands.clearSnow(player, args)
    local bank = type(args.source) == "table" and bankOfSource(args.source)
    local source = bank and bank:findSource(args.source.x, args.source.y, args.source.z)
    if not source then return false, "not connected" end
    bank:clearSnow(source, sourceAt(args.source))
    bank:sendStatus()
    return true
end

function Commands.connectVehicle(player, args)
    local bank = bankAt(args.bank)
    if not bank then return false, "no bank" end
    local id = args.vehicle
    if type(id) ~= "number" then return false, "no vehicle" end
    -- getVehicleById knows vehicles only on a server (BaseVehicle.createPhysics).
    local vehicle = getVehicleById(id) or bank:findVehicle(function(candidate) return candidate:getId() == id end)
    if not vehicle then return false, "no vehicle" end
    if bank.vehicle then return false, "already connected" end
    if not PowerBank.vehicleInReach(bank:position(), vehicle) then return false, "out of reach" end
    local wire = PowerBank.findVehicleWire(player)
    if not wire then return false, "no wire" end
    for i = 0, wire:size() - 1 do
        local item = wire:get(i)
        local container = item:getContainer()
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    end
    local script = vehicle:getScript()
    bank.vehicle = {
        sqlId = vehicle:getSqlId(), id = vehicle:getId(),
        name = script:getCarModelName() or script:getName(),
    }
    bank:sendStatus()
    return true
end

function Commands.disconnectVehicle(player, args)
    local bank = bankAt(args.bank)
    if not (bank and bank.vehicle) then return false, "not connected" end
    if player then
        for _ = 1, PowerBank.VEHICLE_WIRE_COUNT do
            Actions.addOrDropItem(player, instanceItem(PowerBank.VEHICLE_WIRE))
        end
        bank.vehicle = false
    else
        bank:dropVehicleWire()
    end
    bank:sendStatus()
    return true
end

function Commands.refresh(player, args)
    local bank = bankAt(args.bank)
    if not bank then return false, "no bank" end
    bank:recount()
    bank:switchGenerator()
    bank:showBatteries()
    bank:sendStatus()
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
