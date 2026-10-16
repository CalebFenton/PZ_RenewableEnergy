-- The gasifiers as a client sees them: the server's summary of each one, arriving through the
-- Global Object System (also in single player, where it loops back), and the hopper's and filter's
-- AcceptItemFunctions on this client's copies of the containers, which are neither saved nor sent.

require "Map/CGlobalObjectSystem"
require "Map/CGlobalObject"
require "RenewableEnergy/WoodGas/Gasifier"

local Gasifier = RenewableEnergy.Gasifier

-- MapObjects keeps one function per sprite and priority.
local LOAD_PRIORITY = 6

local ClientGasifier = CGlobalObject:derive("RenewableEnergy_ClientGasifier")

local GasifierSystem = CGlobalObjectSystem:derive("RenewableEnergy_ClientGasifierSystem")

function GasifierSystem:new()
    return CGlobalObjectSystem.new(self, Gasifier.SYSTEM_NAME)
end

function GasifierSystem:initSystem()
    Gasifier.clientSystem = self
end

function GasifierSystem:isValidIsoObject(isoObject)
    return Gasifier.isGasifier(isoObject)
end

function GasifierSystem:newLuaObject(globalObject)
    return ClientGasifier:new(self, globalObject)
end

-- The server sends no system commands, and vanilla's default raises an error for any command.
function GasifierSystem:OnServerCommand(command, args)
end

CGlobalObjectSystem.RegisterSystemClass(GasifierSystem)

local function adoptCopy(isoObject)
    if Gasifier.isGasifier(isoObject) then
        Gasifier.adoptContainers(isoObject)
    end
end

if isClient() then
    for _, name in ipairs(Gasifier.sprites()) do
        MapObjects.OnLoadWithSprite(name, adoptCopy, LOAD_PRIORITY)
    end
end

-- A hopper or filter opened in the loot window gets its AcceptItemFunction before anything is
-- dropped in it.
Events.OnRefreshInventoryWindowContainers.Add(function(page, state)
    if state ~= "buttonsAdded" then return end
    for _, button in ipairs(page.backpacks or {}) do
        local container = button.inventory
        local parent = container and container:getParent()
        if parent and Gasifier.isGasifier(parent) then
            Gasifier.adoptContainer(container)
        end
    end
end)

return GasifierSystem
