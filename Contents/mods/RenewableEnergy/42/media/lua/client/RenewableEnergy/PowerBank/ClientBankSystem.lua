-- The banks as a client sees them: the server's status for each one, arriving through the
-- Global Object System (also in single player, where it loops back), and commands back.
--
-- Bank generators and containers come to a multiplayer client as plain copies, so this
-- side does on its copy what the server does on its own: keep the generator out of the
-- cell's update, which would run a gas generator's engine sound, give the container its
-- filter, which is neither saved nor sent, and let go of the squares a running bank powered
-- when it is taken away.

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

-- Squares a generator powers are listed in the chunks around it (IsoChunk.addGeneratorPos), 8
-- squares a side.
local CHUNK_SQUARES = 8

-- A server sends an object's removal before it removes its own copy (GameServer.RemoveItemFromMap),
-- so the bank system there switches a running bank off only after this client has lost its copy,
-- and the switch-off, which names the bank by its place on the square, finds nothing here. The
-- copy of a running bank leaving this client's square lets go of the squares it powers itself,
-- as a generator switching off does (IsoGenerator.setSurroundingElectricity); otherwise they stay
-- powered here until their chunks reload.
local function releasePower(isoObject)
    if not (PowerBank.isBank(isoObject) and isoObject:isActivated()) then return end
    local x, y, z = isoObject:getX(), isoObject:getY(), isoObject:getZ()
    local radius = SandboxVars.GeneratorTileRange
    local cell = getCell()
    for wx = math.floor((x - radius) / CHUNK_SQUARES), math.floor((x + radius) / CHUNK_SQUARES) do
        for wy = math.floor((y - radius) / CHUNK_SQUARES), math.floor((y + radius) / CHUNK_SQUARES) do
            local chunk = cell:getChunk(wx, wy)
            if chunk then
                chunk:removeGeneratorPos(x, y, z)
            end
        end
    end
end

if isClient() then
    for _, name in ipairs(PowerBank.bankSprites()) do
        MapObjects.OnLoadWithSprite(name, adoptCopy, 6)
    end
    Events.OnObjectAboutToBeRemoved.Add(releasePower)
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
