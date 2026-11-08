require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"
require "RenewableEnergy/Debug/RenewableEnergyTestLibGenerators"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sprites = require "RenewableEnergy/Sprites"

-- Banks in a room a player built (T.playerRoom): walled all round and roofed, it is indoors as a
-- map building's room is, though the authority of a multiplayer game knows it only as such a
-- region (IsoWorldRegion.isPlayerRoom) and keeps no building for it. And the fumes the game gives a
-- building for a bank running in it as it makes such rooms into buildings again (BankFumes.lua).

local T = RenewableEnergyTest
local test, expect, expectEqual = T.test, T.expect, T.expectEqual

local RACK = "RenewableEnergy.BatteryRackWood"

-- A room a player built takes a bank as a map building's room does: the cursor allows it, the
-- authority places it, and the bank counts as indoors. Knocking a wall down leaves it outdoors:
-- placing there is refused, and the bank's next pass finds it outdoors.
test("renewable_energy_bank_player_room_takes_a_bank", {
    instant = true,
    run = function(self)
        T.setGrid(self, false)
        local room = T.playerRoom(self)
        if not room then return end
        local square = room.inside[5]
        T.setPerk(self, Perks.Electricity, 10)
        T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
        T.step(function()
            self.allowed = PowerBank.canPlaceBank(square)
            self.cursorAllows = ISMoveableSpriteProps.new(Sprites.batteryRackWood.S):canPlaceMoveable(T.player(), square,
                instanceItem(RACK))
        end)
        T.placeAsPlayer(self, square, RACK, Sprites.batteryRackWood.S)
        local bank = T.where(square)
        bank.kind = "bank"
        T.waitFor(self, function() return PowerBank.findOn(square) ~= nil end, "this client's copy of the placed bank")
        T.readRecord(self, bank, "closed")
        T.openPlayerRoom(self, room)
        T.step(function() self.openAllowed, self.reason = PowerBank.canPlaceBank(square) end)
        T.bankPass(self, bank, 0, { label = "opened" })
    end,
    validate = function(self)
        local reads = self.reads
        expect(self.allowed, "a bank is refused in a room a player built")
        expect(self.cursorAllows, "the cursor refuses a battery rack in a room a player built")
        if not expect(reads.closed, "the placed bank's record") then return end
        expect(reads.closed.status.state ~= "outdoors", "the bank in the room a player built counts as outdoors")
        expect(not self.openAllowed, "a bank may stand in a player's room with a wall knocked down")
        expectEqual("the reason a bank is refused there", self.reason, "Tooltip_RenewableEnergy_BankIndoorsOnly")
        expectEqual("the state of the bank once the wall is down", reads.opened and reads.opened.status.state, "outdoors")
    end,
})

-- Queues a running bank on the first square inside `room`, the character standing on the last,
-- then a change to the map nearby that has the game make the rooms players built into buildings
-- again (WorldRegionToMetaGrid), which marks one toxic for every generator running in it. Waits
-- for this client's new building of the room; whether its air is toxic then lands in self.toxic,
-- and the authority's view of the room in self.reads.authority.
local function runBankThenRebuild(self, room)
    local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER }, { square = room.inside[1] })
    local elsewhere = bank and T.square(self, { near = room, minDistance = 6 }, "an outdoor square away from the room")
    if not elsewhere then return end
    local inside = room.inside[#room.inside]
    T.switchOn(self, bank)
    T.step(function() T.standOn(inside) end)
    T.waitFor(self, function()
        local building = inside:getBuilding()
        self.before = building and building:getID()
        return building ~= nil
    end, "this client's building of the room")
    T.floorAbove(self, elsewhere)
    T.waitFor(self, function()
        local building = inside:getBuilding()
        return building ~= nil and building:getID() ~= self.before
    end, "this client's building of the room made again")
    -- Long enough for a correction a few ticks late to land.
    T.waitUntil(function() return false end, 250)
    T.step(function() self.toxic = inside:getBuilding():isToxic() end)
    T.read(self, "roomRead", T.at(inside), "authority")
end

-- A bank burns nothing, so the room a player built that it stands in never fills with fumes, even
-- after the game makes that room into a building again with the bank running.
test("renewable_energy_bank_fumes_player_room_stays_clear", {
    run = function(self)
        T.setGrid(self, false)
        local room = T.playerRoom(self)
        if room then
            runBankThenRebuild(self, room)
        end
    end,
    validate = function(self)
        if not expect(self.toxic ~= nil, "a read of the room's air") then return end
        expect(not self.toxic, "the running bank filled the room a player built with fumes")
        local authority = self.reads.authority
        expect(authority and authority.inRoom, "the authority doesn't count the room a player built a room")
        expect(not (authority and authority.toxic), "the authority's building of the room is toxic")
    end,
})

-- A generator running beside the bank fills the room with fumes, and the bank's room being made
-- into a building again leaves it so.
test("renewable_energy_bank_fumes_player_room_generator_stays", {
    run = function(self)
        T.setGrid(self, false)
        local room = T.playerRoom(self)
        if not (room and T.generator(self, { square = room.inside[3], running = true })) then return end
        runBankThenRebuild(self, room)
    end,
    validate = function(self)
        if not expect(self.toxic ~= nil, "a read of the room's air") then return end
        expect(self.toxic, "the room a player built cleared with a generator running in it")
    end,
})

-- The game marks a map building toxic for a bank running in it too, as it makes a room a player
-- built in the same chunk into a building again. Marked where a player stands, it clears at once;
-- a sour digester in it fumes, which the bank's being there doesn't clear.
test("renewable_energy_bank_fumes_map_building_cleared_unless_a_source_fumes", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local digester = bank and T.placeRecord(self, "digester", "barrel.MetalDrum", { indoors = true, near = bank.square })
        local stand = digester and T.square(self, { indoors = true, near = bank.square }, "an indoor square to stand on")
        if not stand then return end
        local building = stand:getBuilding()
        if not T.need(self, bank.square:getBuilding() == building and digester.square:getBuilding() == building,
            "the bank, the digester and the character in one building") then return end
        T.switchOn(self, bank)
        T.step(function()
            T.standOn(stand)
            -- As WorldRegionToMetaGrid marks it.
            building:setToxic(true)
        end)
        T.waitUntil(function() return not building:isToxic() end, 2000)
        T.step(function() self.marked = building:isToxic() end)
        T.setRecord(self, digester, T.sourDigester("barrel"))
        T.waitFor(self, function() return building:isToxic() end, "this client's copy of the building fuming")
        -- Long enough for a multiplayer client's question to the server and its answer.
        T.waitUntil(function() return not building:isToxic() end, 1000)
        T.step(function() self.fuming = building:isToxic() end)
    end,
    validate = function(self)
        if not expect(self.marked ~= nil, "a read of the marked building") then return end
        expect(not self.marked, "the building the game marked toxic for the bank stayed toxic")
        expect(self.fuming, "the building cleared with a sour digester in it")
    end,
})
