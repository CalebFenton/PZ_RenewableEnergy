-- How a bank runs a wired treadmill (the "treadmill" family of RenewableEnergy.Sources) on the
-- authority, and the one writer of a treadmill tile's wiring. A run banks its watt-hours when it
-- ends (credit), and the passes after it pay them out at no more than a runner puts in; what is
-- left when the treadmill leaves its bank goes in at once. Its record and status entry need
-- nothing of their own, so it has no connect or status.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Treadmill"

RenewableEnergy = RenewableEnergy or {}
local Specs, PowerBank, Treadmill = RenewableEnergy.Specs, RenewableEnergy.PowerBank, RenewableEnergy.Treadmill

local TreadmillSource = {}
RenewableEnergy.TreadmillSource = TreadmillSource

-- Watt-hours left over below this are rounding, not a run.
local LEFT_WH = 0.001
-- Tile modData: the tile was wired once, which taught its Electricity XP, so wiring it again after
-- unwiring teaches nothing, as a bank's part teaches only its first wiring (PowerBank.WIRED_ONCE).
local WIRED_ONCE = "RenewableEnergy_treadmillWiredOnce"

--- Wires the treadmill tile `object` to feed a bank. Returns whether this is the first time the
--- tile was ever wired.
function TreadmillSource.wire(object)
    local data = object:getModData()
    local first = not data[WIRED_ONCE]
    data[Treadmill.WIRED] = true
    data[WIRED_ONCE] = true
    object:transmitModData()
    return first
end

--- Unwires the treadmill tile `object`. Its wire comes back, as a bank's part gives back its wire:
--- into `player`'s hands, or, with no player (the tile picked up or destroyed), onto its square.
--- The electronics scrap stays spent. The caller takes the tile out of its bank first.
function TreadmillSource.unwire(object, player)
    object:getModData()[Treadmill.WIRED] = nil
    object:transmitModData()
    local wire = Specs.treadmill.wiring.wire
    if player then
        RenewableEnergy.giveItems(player, PowerBank.WIRE, wire)
        return
    end
    local square = object:getSquare()
    for _ = 1, wire do
        square:AddWorldInventoryItem(PowerBank.WIRE, ZombRandFloat(0.1, 0.9), ZombRandFloat(0.1, 0.9), 0)
    end
end

--- Banks a run's `wh` with the treadmill `source` (its bank's record) for the passes to come.
function TreadmillSource.credit(source, wh)
    source.pendingWh = (source.pendingWh or 0) + wh
end

--- The treadmill's output over the pass: what runs banked, at no more than Specs.treadmill.watts,
--- the rest carried to the next pass, so a finished run reads as a runner's watts for as long as
--- it lasted rather than all at once. Runs past the bank's input slots are lost.
function TreadmillSource.update(source, object, inSlot, hours)
    if hours <= 0 then
        source.watts = 0
        return
    end
    local wh = source.pendingWh or 0
    local watts = inSlot and math.min(wh / hours, Specs.treadmill.watts) or 0
    local left = inSlot and wh - watts * hours or 0
    source.pendingWh = left > LEFT_WH and left or nil
    source.watts = watts
    if not inSlot then
        source.reason = "noController"
    elseif wh <= 0 then
        source.reason = "idle"
    else
        source.reason = nil
    end
end

return TreadmillSource
