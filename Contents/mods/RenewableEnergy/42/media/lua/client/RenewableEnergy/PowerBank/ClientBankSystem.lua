-- The banks as a client sees them: each one's summary through the Global Object System (looped
-- back in single player), the full status of banks this game's players watch, and commands back.
--
-- A multiplayer client gets plain copies of bank generators and containers, so it does on its copy
-- what the server does: keep the generator out of the cell's update (else a gas generator's engine
-- sound runs), give the container its unsaved, unsent filter, and release the squares a running
-- bank powered when it is removed.

require "RenewableEnergy/Sprites"
require "RenewableEnergy/PlaceTracker"
require "RenewableEnergy/PowerBank/PowerBank"
local ClientObjects = require "cf_commonlib/ClientObjects"
local GeneratorReach = require "cf_commonlib/GeneratorReach"

local PowerBank, PlaceTracker = RenewableEnergy.PowerBank, RenewableEnergy.PlaceTracker
local Sprites = RenewableEnergy.Sprites

local function adoptCopy(isoObject)
    isoObject:getCell():addToProcessIsoObjectRemove(isoObject)
    PowerBank.adoptContainer(isoObject:getContainer())
end

local BankSystem = ClientObjects.define({
    prefix = "RenewableEnergy_", name = "Bank", owner = PowerBank, isObject = PowerBank.isBank,
    sprites = PowerBank.bankSprites(), loadPriority = Sprites.LOAD_PRIORITY,
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

-- The banks this game's players watch, by place (PlaceTracker.key), to { [player number] = true }.
-- The server sends a bank's status only to its watchers, so once nobody here watches it, this
-- client's copy goes rather than show stale when a window next opens.
local watching = {}

local function keyOf(position)
    return PlaceTracker.key(position.x, position.y, position.z)
end

-- This client's copy of the bank at `position`.
local function copyAt(position)
    local globalObject = BankSystem.instance.system:getObjectAt(position.x, position.y, position.z)
    return globalObject and globalObject:getModData()
end

--- `player` watches the status of `bank` (single player too): the server sends it now, after a
--- fresh look at the bank, and after every change until unwatchStatus. The status window watches
--- while it is open. Jobs that change a bank go through RenewableEnergyAction instead; besides
--- watching, the server takes no command from a client but "resync".
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
    if module ~= PowerBank.COMMAND_MODULE or command ~= PowerBank.STATUS_COMMAND then return end
    local copy = watching[keyOf(args)] and copyAt(args)
    if copy then
        copy.status = args.status
    end
end)

-- A running generator's position is listed in every chunk its reach touches
-- (IsoGenerator.setSurroundingElectricity, IsoChunk.addGeneratorPos).
local CHUNK_SQUARES = getChunkSizeInSquares()

--- Lets this client's chunks go of the squares a generator at x, y, z powered, as the generator
--- switching off does (IsoGenerator.setSurroundingElectricity); otherwise they stay powered here
--- until their chunks reload.
function PowerBank.releaseGeneratorPower(x, y, z)
    local radius = GeneratorReach.range()
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

-- A server sends an object's removal before it removes its own copy (GameServer.RemoveItemFromMap),
-- so the bank system there switches a running bank off only after this client has lost its copy,
-- and the switch-off, which names the bank by its place on the square, finds nothing here. So the
-- copy of a running bank leaving this client's square lets go of the squares it powers itself.
local function releasePower(isoObject)
    if PowerBank.isBank(isoObject) and isoObject:isActivated() then
        PowerBank.releaseGeneratorPower(isoObject:getX(), isoObject:getY(), isoObject:getZ())
    end
end

if isClient() then
    Events.OnObjectAboutToBeRemoved.Add(releasePower)
end

return BankSystem
