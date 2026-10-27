-- A bank's backup generator on the authority: the plugged-in generators beside a bank, the
-- failsafe relay that starts and stops one by the bank's charge, and the one the status shows.

if isClient() then return end

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Places = require "RenewableEnergy/Places"
local Sprites = require "RenewableEnergy/Sprites"
local Fumes = require "RenewableEnergy/Fumes"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Payers = require "RenewableEnergy/PowerBank/Payers"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local GasLines = require "RenewableEnergy/GasLine/GasLines"
local Bank = require "RenewableEnergy/PowerBank/Bank"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local Squares = require "cf_commonlib/Squares"

-- A backup generator a failsafe can start is one plugged in within this many squares of its bank
-- on either axis, on the bank's floor.
local BACKUP_REACH = 3
-- At or below this condition a running generator may catch fire or explode at every hour it runs
-- (IsoGenerator.update), so a relay, which nobody stands by, never starts one that worn.
local FIRE_CONDITION = 20

local function isFailsafe(object)
    return Sprites.nameOf(object) == Sprites.failsafe
end

local function generatorPlace(found)
    return Places.objectPlace(found.generator)
end

-- Every plugged-in generator within BACKUP_REACH on the bank's floor, nearest
-- first (Places.sortNearest): { generator, failsafe }, `failsafe` whether one stands on its
-- square.
local function generatorsInReach(bank)
    local found = {}
    Squares.eachAround(bank.x, bank.y, bank.z, BACKUP_REACH, function(square)
        local generator = square:getGenerator()
        if GeneratorReach.isVanillaGenerator(generator) and generator:isConnected() then
            Payers.track(generator)
            table.insert(found, { generator = generator, failsafe = Squares.findObjectOn(square, isFailsafe) ~= nil })
        end
    end)
    Places.sortNearest(found, bank.x, bank.y, bank.z, generatorPlace)
    return found
end

-- The bank a failsafe answers to: the nearest bank with its generator in backup reach, the lower
-- place on a tie (Places.nearest). A relay is wired to one bank, so two banks beside it never
-- switch it against each other.
local function failsafeBank(generator)
    local gx, gy, gz = Places.objectPlace(generator)
    local reach, banks = BACKUP_REACH, {}
    PowerBank.each(function(bank)
        if bank.z == gz and math.abs(bank.x - gx) <= reach and math.abs(bank.y - gy) <= reach then
            table.insert(banks, bank)
        end
    end)
    return Places.nearest(banks, gx, gy, gz)
end

-- Start or stop a backup generator with a failsafe by the charge, as a generator auto-start relay
-- does. A generator stalled on gas starts again by itself once its load fits (GasLines), so the
-- relay leaves it be, and only calls that off when it would stop it.
local function runFailsafe(generator, wanted, charge)
    local startPercent, stopPercent = PowerBank.failsafeRange()
    local gas = GasKit.stateOf(generator)
    -- The charge comes back from whole battery uses (DrainableComboItem.getCurrentUsesFloat), a
    -- hair off the percent it was set to, so it is compared to two places.
    local percent = round(charge * 100, 2)
    local wantsOff = not wanted or percent >= stopPercent
    if generator:isActivated() then
        if wantsOff then
            Fumes.setRunning(generator, false)
        end
    elseif gas and gas.stalled then
        if wantsOff then
            GasLines.cancelStall(generator)
        end
    elseif wanted and percent < startPercent and generator:getFuel() > 0
        and generator:getCondition() > FIRE_CONDITION then
        Fumes.setRunning(generator, true)
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
