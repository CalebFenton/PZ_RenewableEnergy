-- A bank's backup generator on the authority: the plugged-in generators beside a bank, the
-- failsafe relay that starts and stops one by the bank's charge, and the one the status shows.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/PlaceTracker"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Payers"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/GasLine/GasLines"
require "RenewableEnergy/PowerBank/Bank"

RenewableEnergy = RenewableEnergy or {}
local Specs, Sprites, PowerBank = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.PowerBank
local Payers, PlaceTracker, Bank = RenewableEnergy.Payers, RenewableEnergy.PlaceTracker, RenewableEnergy.Bank

-- At or below this condition a running generator may catch fire or explode at every hour it runs
-- (IsoGenerator.update), so a relay, which nobody stands by, never starts one that worn.
local FIRE_CONDITION = 20

local function isFailsafe(object)
    return Sprites.nameOf(object) == Sprites.failsafe
end

local function generatorPlace(found)
    return PlaceTracker.objectPlace(found.generator)
end

-- Every plugged-in generator within backup reach (Specs.backupReach) on the bank's floor, nearest
-- first (PlaceTracker.sortNearest): { generator, failsafe }, `failsafe` whether one stands on its
-- square.
local function generatorsInReach(bank)
    local found = {}
    RenewableEnergy.eachSquareAround(bank.x, bank.y, bank.z, Specs.backupReach, function(square)
        local generator = square:getGenerator()
        if RenewableEnergy.isGenerator(generator) and generator:isConnected() then
            Payers.track(generator)
            table.insert(found, { generator = generator, failsafe = RenewableEnergy.findObjectOn(square, isFailsafe) ~= nil })
        end
    end)
    PlaceTracker.sortNearest(found, bank.x, bank.y, bank.z, generatorPlace)
    return found
end

-- The bank a failsafe answers to: the nearest bank with its generator in backup reach, the lower
-- place on a tie (PlaceTracker.nearest). A relay is wired to one bank, so two banks beside it never
-- switch it against each other.
local function failsafeBank(generator)
    local gx, gy, gz = PlaceTracker.objectPlace(generator)
    local reach, banks = Specs.backupReach, {}
    PowerBank.eachBank(function(bank)
        if bank.z == gz and math.abs(bank.x - gx) <= reach and math.abs(bank.y - gy) <= reach then
            table.insert(banks, bank)
        end
    end)
    return PlaceTracker.nearest(banks, gx, gy, gz)
end

-- Start or stop a backup generator with a failsafe by the charge, as a generator auto-start relay
-- does. A generator stalled on gas starts again by itself once its load fits (GasLines), so the
-- relay leaves it be, and only calls that off when it would stop it.
local function runFailsafe(generator, wanted, charge)
    local startPercent, stopPercent = PowerBank.failsafeRange()
    local gas = RenewableEnergy.GasKit.stateOf(generator)
    -- The charge comes back from whole battery uses (DrainableComboItem.getCurrentUsesFloat), a
    -- hair off the percent it was set to, so it is compared to two places.
    local percent = round(charge * 100, 2)
    local wantsOff = not wanted or percent >= stopPercent
    if generator:isActivated() then
        if wantsOff then
            generator:setActivated(false)
        end
    elseif gas and gas.stalled then
        if wantsOff then
            RenewableEnergy.GasLines.cancelStall(generator)
        end
    elseif wanted and percent < startPercent and generator:getFuel() > 0
        and generator:getCondition() > FIRE_CONDITION then
        generator:setActivated(true)
    end
end

--- Run every failsafe that answers to the bank (failsafeBank), and record the backup generator the
--- status shows, which carries the load while it runs: one the bank runs, a running one first,
--- else one with a failsafe, else the nearest. The failsafe runs a generator only while the bank
--- could carry its load (Bank:canCarryLoad). While the bank is unloaded, the last known state holds.
function Bank:updateGenerator()
    if not self:getSquare() then return end
    local armed = self:canCarryLoad()
    local shown, shownRank
    for _, found in ipairs(generatorsInReach(self)) do
        local generator = found.generator
        local controls = found.failsafe and failsafeBank(generator) == self
        if controls then
            runFailsafe(generator, armed, self.charge)
        end
        local running = generator:isActivated()
        local rank = (controls and 4 or 0) + (controls and running and 2 or 0) + (found.failsafe and 1 or 0)
        -- Nearest first, so of two alike the nearer stays.
        if not shown or rank > shownRank then
            shown, shownRank = {
                x = generator:getX(), y = generator:getY(), z = generator:getZ(),
                running = running, failsafe = found.failsafe, controls = controls, armed = armed,
            }, rank
        end
    end
    self.generator = shown or false
end

function Bank:backupCarriesLoad()
    return self.generator and self.generator.running
end

return Bank
