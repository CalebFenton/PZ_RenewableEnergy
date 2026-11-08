-- The fumes the game gives a building for a bank running in it, cleared where this game's players
-- would breathe them. A bank is a generator to the game, and as a client or single player works
-- out the regions again after any wall, floor or stairs change nearby, it makes the rooms players
-- built into buildings anew and marks toxic each building with a generator running in its rooms
-- (WorldRegionToMetaGrid.updateSquares): a bank's room a player built, and a map building sharing
-- a chunk with such a room. No Lua event follows, and toxic air hurts every tick
-- (IsoGameCharacter.update). The game does this after the characters' update and before OnTick,
-- so a building a local player stands in that turned toxic is looked at in that same tick.
--
-- A building is cleared only with a bank in it and nothing else to fume: no other generator running
-- on a roofed square of it, as the game counts one, and in single player none of the mod's sources
-- (Fumes). A multiplayer client knows the mod's sources only through the server's toxicity of a
-- map building, so it asks the server for that; the server keeps no building for a room a player
-- built, so none of the mod's sources fumes in one there.

local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local ClientBankSystem = require "RenewableEnergy/PowerBank/ClientBankSystem"
local Squares = require "cf_commonlib/Squares"

local function isGenerator(object)
    return instanceof(object, "IsoGenerator")
end

-- A bank standing in `building`, or nil; and nil too once a generator besides the banks is found
-- running on a roofed square of it, which fumes.
local function bankAlone(building)
    local bank
    local rooms = building:getDef():getRooms()
    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        local z, rects = room:getZ(), room:getRects()
        for j = 0, rects:size() - 1 do
            local rect = rects:get(j)
            for x = rect:getX(), rect:getX() + rect:getW() - 1 do
                for y = rect:getY(), rect:getY() + rect:getH() - 1 do
                    local square = getSquare(x, y, z)
                    local generator = Squares.findObjectOn(square, isGenerator)
                    if generator and PowerBank.isBank(generator) then
                        bank = bank or generator
                    elseif generator and generator:isActivated() and not square:isOutside() then
                        return nil
                    end
                end
            end
        end
    end
    return bank
end

-- Clears the toxic `building` that `player` stands in if only its banks make it so.
local function settle(building, player)
    local bank = bankAlone(building)
    if not bank then
        return
    end
    if not isClient() then
        -- Single player: the authority's Fumes, a server file, loads after this one.
        local Fumes = require "RenewableEnergy/Fumes"
        building:setToxic(Fumes.sourceIn(building))
    elseif building:getDef():isUserDefined() then
        building:setToxic(false)
    else
        ClientBankSystem.instance:sendCommand(player, PowerBank.AIR_COMMAND, { bank = Squares.positionOf(bank) })
    end
end

-- Player number -> the ID of the toxic building they last stood in, already looked at.
local lookedAt = {}

Events.OnTick.Add(function()
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        local building = player and player:getCurrentBuilding()
        if building and building:isToxic() then
            local id = building:getID()
            if lookedAt[playerNum] ~= id then
                lookedAt[playerNum] = id
                settle(building, player)
            end
        else
            lookedAt[playerNum] = nil
        end
    end
end)

-- The server's toxicity of the map building a bank stands in, which this client asked for.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= PowerBank.COMMAND_MODULE or command ~= PowerBank.AIR_COMMAND then return end
    local square = getSquare(args.x, args.y, args.z)
    local building = square and square:getBuilding()
    if building then
        building:setToxic(args.toxic == true)
    end
end)
