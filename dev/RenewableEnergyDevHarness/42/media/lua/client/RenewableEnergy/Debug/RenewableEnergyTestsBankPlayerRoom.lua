require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sprites = require "RenewableEnergy/Sprites"

-- Banks in a room a player built (T.playerRoom): walled all round and roofed, it is indoors as a
-- map building's room is, though the authority of a multiplayer game knows it only as such a
-- region (IsoWorldRegion.isPlayerRoom) and keeps no building for it.

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
