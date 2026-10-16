-- The client's side of the features the authority keeps in a Global Object System: the system that
-- receives each object's summary (also in single player, where it loops back), and this client's
-- own copies of their tiles, which need what the server's copies have but neither save nor send,
-- such as a container's AcceptItemFunction.

require "Map/CGlobalObjectSystem"
require "Map/CGlobalObject"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"

RenewableEnergy = RenewableEnergy or {}
local ClientObjects = {}
RenewableEnergy.ClientObjects = ClientObjects

local Sprites = RenewableEnergy.Sprites

--- Has this client set up its copies of the tiles of `sprites` (names) that `isObject` tells:
--- `adoptCopy(isoObject)` on a multiplayer client's copy that arrives with its chunk or that the
--- server just placed (single player sets up the authority's own), and
--- `adoptContainer(container)` on each of their containers opened in the loot window, before
--- anything is dropped in it, on every side.
function ClientObjects.adopt(sprites, isObject, adoptCopy, adoptContainer)
    if isClient() then
        local function adopt(isoObject)
            if isObject(isoObject) then
                adoptCopy(isoObject)
            end
        end
        for _, name in ipairs(sprites) do
            MapObjects.OnLoadWithSprite(name, adopt, Sprites.LOAD_PRIORITY)
        end
        Events.OnObjectAdded.Add(adopt)
    end
    Events.OnRefreshInventoryWindowContainers.Add(function(page, state)
        if state ~= "buttonsAdded" then return end
        for _, button in ipairs(page.backpacks or {}) do
            local container = button.inventory
            local parent = container and container:getParent()
            if parent and isObject(parent) then
                adoptContainer(container)
            end
        end
    end)
end

--- Defines and registers the client system of a feature the authority keeps in a Global Object
--- System of the same `spec.name`: `owner` (its shared module, with SYSTEM_NAME; it gets
--- clientSystem, for GlobalObjects' accessors) and `isObject`, and adopts the copies of its tiles,
--- whose sprite names are `spec.sprites` (ClientObjects.adopt), with `spec.adoptCopy` and
--- `spec.adoptContainer`. Returns the system class.
function ClientObjects.define(spec)
    local ClientObject = CGlobalObject:derive("RenewableEnergy_Client" .. spec.name)
    local System = CGlobalObjectSystem:derive("RenewableEnergy_Client" .. spec.name .. "System")

    function System:new()
        return CGlobalObjectSystem.new(self, spec.owner.SYSTEM_NAME)
    end

    function System:initSystem()
        spec.owner.clientSystem = self
    end

    function System:isValidIsoObject(isoObject)
        return spec.isObject(isoObject)
    end

    function System:newLuaObject(globalObject)
        return ClientObject:new(self, globalObject)
    end

    -- The server sends no system commands, and vanilla's default raises an error for any command.
    function System:OnServerCommand(command, args)
    end

    CGlobalObjectSystem.RegisterSystemClass(System)
    ClientObjects.adopt(spec.sprites, spec.isObject, spec.adoptCopy, spec.adoptContainer)
    return System
end

return ClientObjects
