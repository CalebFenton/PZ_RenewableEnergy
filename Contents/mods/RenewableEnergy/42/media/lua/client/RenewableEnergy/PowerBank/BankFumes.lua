-- A bank is a generator to the game, so the game's fumes for a generator running in a building
-- reach a bank's building too. Of the three places the game writes a building's toxicity, the
-- authority keeps two off banks: their switch (Fumes.setBankRunning) and the hourly update they are
-- kept out of (Bank:loaded). The third is here. A client or single player, after any wall, floor or
-- stairs change nearby and as a loading game reads its regions in, makes the rooms players built
-- into buildings anew and marks toxic each building with an activated generator on a roofed square
-- of its rooms in the chunks it touched (WorldRegionToMetaGrid.updateSquares): a bank's room a
-- player built, or a map building sharing a chunk with one. A dedicated server never does. No Lua
-- event follows, but it runs after the characters' update and before OnTick (IsoWorld.updateWorld),
-- so each tick every bank loaded here whose building has turned toxic is looked at, in that tick.
--
-- The building is put back to the rule Fumes keeps: toxic while another generator runs on a roofed
-- square of it or, in single player, one of the mod's sources fumes there. A multiplayer client's
-- toxicity hurts nobody, since the server deals the damage, but it shows the noxious smell moodle.
-- The server keeps no building for a room a player built, so none of the mod's sources fumes in
-- one there; a map building's air is the server's, which the client asks for.

local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local ClientBankSystem = require "RenewableEnergy/PowerBank/ClientBankSystem"
local PlaceTracker = require "cf_commonlib/PlaceTracker"
local Squares = require "cf_commonlib/Squares"

-- Place key of a bank -> the ID of its toxic building, already looked at.
local lookedAt = {}

local banks = PlaceTracker.new({
    sprites = PowerBank.feature.sprites,
    matches = PowerBank.isBank,
    onLost = function(x, y, z)
        lookedAt[Squares.placeKey(x, y, z)] = nil
    end,
})

local function isGenerator(object)
    return instanceof(object, "IsoGenerator")
end

-- Whether a generator besides the banks runs on a roofed square of `building`, as the game counts
-- one for its fumes.
local function otherGeneratorRuns(building)
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
                    if generator and not PowerBank.isBank(generator) and generator:isActivated()
                        and not square:isOutside() then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Puts the toxic `building` that `bank` stands in back to the rule.
local function settle(building, bank)
    if otherGeneratorRuns(building) then
        return
    end
    if not isClient() then
        -- Single player: the authority's Fumes, a server file, loads after this one.
        local Fumes = require "RenewableEnergy/Fumes"
        building:setToxic(Fumes.sourceIn(building))
    elseif building:getDef():isUserDefined() then
        building:setToxic(false)
    else
        local player = getPlayer()
        if player then
            ClientBankSystem.instance:sendCommand(player, PowerBank.AIR_COMMAND, { bank = Squares.positionOf(bank) })
        end
    end
end

Events.OnTick.Add(function()
    local settled = {}
    banks:each(function(bank)
        local key = Squares.placeKey(bank:getX(), bank:getY(), bank:getZ())
        local square = bank:getSquare()
        local building = not square:isOutside() and square:getBuilding()
        if building and building:isToxic() then
            local id = building:getID()
            if lookedAt[key] ~= id then
                lookedAt[key] = id
                if not settled[id] then
                    settled[id] = true
                    settle(building, bank)
                end
            end
        else
            lookedAt[key] = nil
        end
    end)
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
