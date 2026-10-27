-- How a bank runs a wired treadmill (the "treadmill" family of RenewableEnergy.Sources) on the
-- authority, and the one writer of a treadmill tile's wiring. A run banks its watt-hours when it
-- ends (credit, through BankSystem.creditTreadmill), and the passes after it pay them out at no
-- more than a runner puts in; what is left when the treadmill leaves its bank goes in at once. Its
-- record and status entry need nothing of their own, so it has no connect or status.

if isClient() then return end

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local Wiring = require "RenewableEnergy/PowerBank/Wiring"

local SPEC = Treadmill.SPEC

local TreadmillSource = {}
RenewableEnergy.TreadmillSource = TreadmillSource

-- Watt-hours left over below this are rounding, not a run.
local LEFT_WH = 0.001
-- Tile modData: the tile was wired once, which taught its Electricity XP, so wiring it again after
-- unwiring teaches nothing, as a bank's part teaches only its first wiring (Wiring.PART_ONCE_KEY).
local WIRED_ONCE_KEY = "RenewableEnergy_treadmillWiredOnce"

--- Wires the treadmill tile `object` to feed a bank, teaching `player` (if any) the wiring the
--- first time the tile is ever wired.
function TreadmillSource.wire(object, player)
    object:getModData()[Treadmill.WIRED_KEY] = true
    Wiring.teach(player, object, WIRED_ONCE_KEY, SPEC.wiring)
    object:transmitModData()
end

--- Unwires the treadmill tile `object`. Its wire comes back, as a bank's part gives back its wire:
--- into `player`'s hands, or, with no player (the tile picked up or destroyed), onto its square.
--- The electronics scrap stays spent. The caller takes the tile out of its bank first.
function TreadmillSource.unwire(object, player)
    object:getModData()[Treadmill.WIRED_KEY] = nil
    object:transmitModData()
    Wiring.refund(player or object:getSquare(), SPEC.wiring)
end

--- Banks `hours` of a run, at most one run's, in the bank's record `source` of the treadmill, for
--- the passes to come.
function TreadmillSource.credit(source, hours)
    source.pendingWh = (source.pendingWh or 0) + SPEC.watts * math.max(0, math.min(hours, SPEC.runMinutes / 60))
end

--- The treadmill's output over the pass: what runs banked, at no more than Treadmill.SPEC.watts,
--- the rest carried to the next pass, so a finished run reads as a runner's watts for as long as
--- it lasted rather than all at once. Runs past the bank's input slots are lost.
function TreadmillSource.update(source, object, inSlot, hours)
    local wh = source.pendingWh or 0
    local watts = inSlot and math.min(wh / hours, SPEC.watts) or 0
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
