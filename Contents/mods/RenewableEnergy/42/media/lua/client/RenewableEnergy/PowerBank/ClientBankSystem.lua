-- The banks as a client sees them: the server's summary of each one, arriving through the
-- Global Object System (also in single player, where it loops back), the whole status of the
-- banks this game's players watch, and commands back.
--
-- Bank generators and containers come to a multiplayer client as plain copies, so this
-- side does on its copy what the server does on its own: keep the generator out of the
-- cell's update, which would run a gas generator's engine sound, give the container its
-- filter, which is neither saved nor sent, and let go of the squares a running bank powered
-- when it is taken away.

require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/ClientObjects"

local PowerBank, ClientObjects = RenewableEnergy.PowerBank, RenewableEnergy.ClientObjects

local function adoptCopy(isoObject)
    isoObject:getCell():addToProcessIsoObjectRemove(isoObject)
    PowerBank.adoptContainer(isoObject:getContainer())
end

local BankSystem = ClientObjects.define({
    name = "Bank", sprites = PowerBank.bankSprites(), owner = PowerBank, isObject = PowerBank.isBank,
    adoptCopy = adoptCopy, adoptContainer = PowerBank.adoptContainer,
})

-- A bank the server places reaches a client in an ordered packet (AddItemToMapPacket) and its
-- state after it in syncs, which are reliable but unordered (PacketTypes.SyncIsoObject), so a
-- sync can arrive first and be dropped for naming an object the client doesn't have yet. Once this
-- client has the bank, it asks the server for its state again.
if isClient() then
    Events.OnObjectAdded.Add(function(isoObject)
        local player = getPlayer()
        if player and PowerBank.isBank(isoObject) then
            BankSystem.instance:sendCommand(player, "resync", { bank = PowerBank.positionOf(isoObject) })
        end
    end)
end

-- The banks this game's players watch, as "x,y,z" to { [player number] = true }. The server sends
-- a bank's status only to its watchers, so once nobody here watches it, this client's copy goes
-- rather than show stale when a window next opens.
local watching = {}

local function keyOf(position)
    return position.x .. "," .. position.y .. "," .. position.z
end

-- This client's copy of the bank at `position`.
local function copyAt(position)
    local globalObject = BankSystem.instance.system:getObjectAt(position.x, position.y, position.z)
    return globalObject and globalObject:getModData()
end

--- `player` watches the status of `bank` (single player too): the server sends it now, after a
--- fresh look at the bank, and after every change until unwatchStatus. The status window watches
--- while it is open. Jobs that change a bank go through RenewableEnergyAction instead; the server
--- takes no other command from a client but "resync".
function PowerBank.watchStatus(player, bank)
    local position = PowerBank.positionOf(bank)
    local key = keyOf(position)
    watching[key] = watching[key] or {}
    watching[key][player:getPlayerNum()] = true
    BankSystem.instance:sendCommand(player, "watch", { bank = position })
end

--- `player` stops watching the status of `bank`.
function PowerBank.unwatchStatus(player, bank)
    local position = PowerBank.positionOf(bank)
    local key = keyOf(position)
    BankSystem.instance:sendCommand(player, "unwatch", { bank = position })
    local players = watching[key]
    if players then
        players[player:getPlayerNum()] = nil
        for _ in pairs(players) do
            return
        end
    end
    watching[key] = nil
    local copy = copyAt(position)
    if copy then
        copy.status = nil
    end
end

-- A multiplayer server sends a bank's status to the players watching it. Single player has no such
-- message: there the status window reads the bank on the authority.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= PowerBank.STATUS_MODULE or command ~= "status" then return end
    local copy = watching[keyOf(args)] and copyAt(args)
    if copy then
        copy.status = args.status
    end
end)

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
    Events.OnObjectAboutToBeRemoved.Add(releasePower)
end

return BankSystem
