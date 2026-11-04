-- The authority's half of the treadmill tests: runs completed or started as the server's
-- character, the way the server finishes or starts a client's action.

require "PZHarness/ServerHandlers"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local Squares = require "cf_commonlib/Squares"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"

local handler, need = PZHarness.serverHandler, PZHarness.need

-- Completes the treadmill action `run` as the server finishes a client's action (complete()), or,
-- given `progress`, stops it that far through as the server stops a client's (serverStop(), which
-- reads the share run off its NetTimedAction). Answers whether a whole run settled, and the
-- character's Fitness XP, endurance and thirst before and after.
local function completeRun(player, run, progress)
    local stats, xp = player:getStats(), player:getXp()
    local reply = { xpBefore = xp:getXP(Perks.Fitness), enduranceBefore = stats:get(CharacterStat.ENDURANCE),
        thirstBefore = stats:get(CharacterStat.THIRST) }
    if progress then
        run.netAction = { getProgress = function() return progress end }
        run:serverStop()
    else
        reply.done = run:complete() == true
    end
    reply.xpAfter, reply.enduranceAfter = xp:getXP(Perks.Fitness), stats:get(CharacterStat.ENDURANCE)
    reply.thirstAfter = stats:get(CharacterStat.THIRST)
    return reply
end

-- A whole Run on Treadmill on the wired treadmill tile at `args` as the server's character
-- (completeRun).
handler("completeTreadmillRun", function(player, args)
    local tile = Kinds.find({ kind = "wiredTreadmill", x = args.x, y = args.y, z = args.z })
    return completeRun(player, RenewableEnergyTreadmillAction:new(player, tile))
end)

-- The runs startTreadmillRun started and completeStartedTreadmillRun has yet to finish, by the
-- treadmill tile's position.
local treadmillRuns = {}

-- Starts a Run on Treadmill on the treadmill tile at `args` as the server's character, the way the
-- multiplayer server starts a client's action (serverStart), and leaves it running until
-- completeStartedTreadmillRun or the end of the test.
handler("startTreadmillRun", function(player, args, defer)
    local tile = Kinds.find({ kind = "treadmill", x = args.x, y = args.y, z = args.z })
    local run = RenewableEnergyTreadmillAction:new(player, tile)
    run:serverStart()
    local key = Squares.placeKey(args.x, args.y, args.z)
    treadmillRuns[key] = run
    defer(function()
        if treadmillRuns[key] == run then
            treadmillRuns[key] = nil
            Treadmill.stopDrawing(tile, run)
        end
    end)
    return {}
end)

-- Finishes the run startTreadmillRun started on the tile at `args`, or stops it `args.progress`
-- through (completeRun).
handler("completeStartedTreadmillRun", function(player, args)
    local key = Squares.placeKey(args.x, args.y, args.z)
    local run = need(treadmillRuns[key], "a run startTreadmillRun started on the server")
    treadmillRuns[key] = nil
    return completeRun(player, run, args.progress)
end)
