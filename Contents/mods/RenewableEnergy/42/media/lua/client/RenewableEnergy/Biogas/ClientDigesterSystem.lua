-- The digesters as a client sees them: the server's summary of each one, arriving through the
-- Global Object System (also in single player, where it loops back), and the hopper's filter on
-- this client's copy of the container, which is neither saved nor sent.

require "Map/CGlobalObjectSystem"
require "Map/CGlobalObject"
require "RenewableEnergy/Biogas/Digester"

local Digester = RenewableEnergy.Digester

-- MapObjects keeps one function per sprite and priority.
local LOAD_PRIORITY = 6

local ClientDigester = CGlobalObject:derive("RenewableEnergy_ClientDigester")

local DigesterSystem = CGlobalObjectSystem:derive("RenewableEnergy_ClientDigesterSystem")

function DigesterSystem:new()
    return CGlobalObjectSystem.new(self, Digester.SYSTEM_NAME)
end

function DigesterSystem:initSystem()
    Digester.clientSystem = self
end

function DigesterSystem:isValidIsoObject(isoObject)
    return Digester.isDigester(isoObject)
end

function DigesterSystem:newLuaObject(globalObject)
    return ClientDigester:new(self, globalObject)
end

-- The server sends no system commands, and vanilla's default raises an error for any command.
function DigesterSystem:OnServerCommand(command, args)
end

CGlobalObjectSystem.RegisterSystemClass(DigesterSystem)

local function adoptCopy(isoObject)
    if Digester.isDigester(isoObject) then
        Digester.adoptContainer(isoObject:getContainer())
    end
end

if isClient() then
    for _, name in ipairs(Digester.sprites()) do
        MapObjects.OnLoadWithSprite(name, adoptCopy, LOAD_PRIORITY)
    end
end

-- A hopper opened in the loot window gets its filter before anything is dropped in it.
Events.OnRefreshInventoryWindowContainers.Add(function(page, state)
    if state ~= "buttonsAdded" then return end
    for _, button in ipairs(page.backpacks or {}) do
        local container = button.inventory
        local parent = container and container:getParent()
        if parent and Digester.isDigester(parent) then
            Digester.adoptContainer(container)
        end
    end
end)

return DigesterSystem
