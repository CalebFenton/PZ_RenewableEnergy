-- The banks as a client sees them: the server's status for each one, arriving through the
-- Global Object System (also in single player, where it loops back), and commands back.
--
-- Bank generators and containers come to a multiplayer client as plain copies, so this
-- side does on its copy what the server does on its own: keep the generator out of the
-- cell's update, which would run a gas generator's engine sound, and give the container
-- its filter, which is neither saved nor sent.

require "Map/CGlobalObjectSystem"
require "Map/CGlobalObject"
require "RenewableEnergy/PowerBank/PowerBank"

local PowerBank = RenewableEnergy.PowerBank

local ACCEPT_ITEM = "RenewableEnergy.PowerBank.acceptItem"

local ClientBank = CGlobalObject:derive("RenewableEnergy_ClientBank")

local BankSystem = CGlobalObjectSystem:derive("RenewableEnergy_ClientBankSystem")

function BankSystem:new()
    return CGlobalObjectSystem.new(self, PowerBank.SYSTEM_NAME)
end

function BankSystem:initSystem()
    PowerBank.clientSystem = self
end

function BankSystem:isValidIsoObject(isoObject)
    return PowerBank.isBank(isoObject)
end

function BankSystem:newLuaObject(globalObject)
    return ClientBank:new(self, globalObject)
end

local function adoptCopy(isoObject)
    if not PowerBank.isBank(isoObject) then return end
    isoObject:getCell():addToProcessIsoObjectRemove(isoObject)
    local container = isoObject:getContainer()
    if container and container:getAcceptItemFunction() == nil then
        container:setAcceptItemFunction(ACCEPT_ITEM)
    end
end

-- Only later updates come here: a new bank's first status is copied in by the engine
-- without a call (CGlobalObjectSystem.receiveNewLuaObjectAt).
function BankSystem:OnLuaObjectUpdated(bank)
    if isClient() then
        adoptCopy(bank:getIsoObject())
    end
end

-- The server sends no system commands, and vanilla's default raises an error for any command.
function BankSystem:OnServerCommand(command, args)
end

CGlobalObjectSystem.RegisterSystemClass(BankSystem)

--- Send command `name` to the server (single player too). See Commands.lua.
function PowerBank.command(player, name, args)
    if BankSystem.instance then
        BankSystem.instance:sendCommand(player, name, args)
    end
end

if isClient() then
    for _, name in ipairs(PowerBank.bankSprites()) do
        MapObjects.OnLoadWithSprite(name, adoptCopy, 6)
    end
end

-- A container opened in the loot window gets its filter before anything is dropped in it.
Events.OnRefreshInventoryWindowContainers.Add(function(page, state)
    if state ~= "buttonsAdded" then return end
    for _, button in ipairs(page.backpacks or {}) do
        local container = button.inventory
        local parent = container and container:getParent()
        if parent and PowerBank.isBank(parent) and container:getAcceptItemFunction() == nil then
            container:setAcceptItemFunction(ACCEPT_ITEM)
        end
    end
end)

return BankSystem
