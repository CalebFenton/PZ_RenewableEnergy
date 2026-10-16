-- How a bank runs a wired treadmill (the "treadmill" family of RenewableEnergy.Sources) on the
-- authority. A run banks its watt-hours when it ends (Commands.runTreadmill, credit), and the
-- passes after it pay them out at no more than a runner puts in. Bank.lua calls init and update
-- for each treadmill it holds; its status entry needs nothing of its own.

if isClient() then return end

require "RenewableEnergy/Specs"

RenewableEnergy = RenewableEnergy or {}
local Specs = RenewableEnergy.Specs

local TreadmillSource = {}
RenewableEnergy.TreadmillSource = TreadmillSource

-- Watt-hours left over below this are rounding, not a run.
local LEFT_WH = 0.001

function TreadmillSource.init(source, isoObject, facing)
    source.facing = facing
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
