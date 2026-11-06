-- A bank's backup generator on the authority: the plugged-in generators beside a bank, the
-- failsafe relay that starts and stops one by the bank's charge, and the one the status shows. A
-- generator beside the bank carries its load while it runs. A failsafe generator need only reach
-- the bank, as one its chargers fill from does: it fills the bank through them.

if isClient() then return end

local Places = require "RenewableEnergy/Places"
local Sprites = require "RenewableEnergy/Sprites"
local Fumes = require "RenewableEnergy/Fumes"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Payers = require "RenewableEnergy/PowerBank/Payers"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local GasLines = require "RenewableEnergy/GasLine/GasLines"
local Bank = require "RenewableEnergy/PowerBank/Bank"
local Failsafe = require "RenewableEnergy/PowerBank/Failsafe"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local Squares = require "cf_commonlib/Squares"
local Tiles = require "cf_commonlib/Tiles"

-- At or below this condition a running generator may catch fire or explode at every hour it runs
-- (IsoGenerator.update), so a relay, which nobody stands by, never starts one that worn.
local FIRE_CONDITION = 20

local function generatorPlace(found)
    return Places.objectPlace(found.generator)
end

local function hasFailsafe(generator)
    return Squares.findObjectOn(generator:getSquare(), Failsafe.isFailsafe) ~= nil
end

local function isPluggedIn(generator)
    return GeneratorReach.isVanillaGenerator(generator) and generator:isConnected()
end

-- Whether `generator`'s power reaches the bank's square, as a generator the chargers fill from must.
local function reachesBank(generator, bank)
    local gx, gy, gz = Places.objectPlace(generator)
    return GeneratorReach.covers(gx, gy, gz, bank.x, bank.y, bank.z)
end

-- A generator a failsafe goes under is tracked at once, so the failsafe can start it before it has
-- ever run (Payers tracks a generator found no other way once it starts).
Tiles.onLoad({ Sprites.failsafe }, function(failsafe)
    local generator = failsafe:getSquare():getGenerator()
    if GeneratorReach.isVanillaGenerator(generator) then
        Payers.track(generator)
    end
end, { matches = Failsafe.isFailsafe, added = true })

-- The generators a bank's status may show, nearest first (Places.sortNearest): every plugged-in
-- generator within PowerBank.BACKUP_REACH on the bank's floor, `beside` it, and every plugged-in
-- failsafe generator whose power reaches the bank. Each { generator, failsafe, beside }, `failsafe`
-- whether one stands on its square.
local function generatorsFor(bank)
    local found, beside = {}, {}
    Squares.eachAround(bank.x, bank.y, bank.z, PowerBank.BACKUP_REACH, function(square)
        local generator = square:getGenerator()
        if isPluggedIn(generator) then
            Payers.track(generator)
            beside[Squares.placeKey(Places.objectPlace(generator))] = true
            table.insert(found, { generator = generator, failsafe = hasFailsafe(generator), beside = true })
        end
    end)
    Payers.eachGenerator(function(generator)
        if not beside[Squares.placeKey(Places.objectPlace(generator))] and isPluggedIn(generator)
            and hasFailsafe(generator) and reachesBank(generator, bank) then
            table.insert(found, { generator = generator, failsafe = true, beside = false })
        end
    end)
    Places.sortNearest(found, bank.x, bank.y, bank.z, generatorPlace)
    return found
end

-- The bank a failsafe answers to: the nearest bank its generator's power reaches, the lower place
-- on a tie (Places.nearest). A relay is wired to one bank, so two banks it reaches never switch it
-- against each other.
local function failsafeBank(generator)
    local gx, gy, gz = Places.objectPlace(generator)
    local banks = {}
    PowerBank.each(function(bank)
        if reachesBank(generator, bank) then
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

--- Run every failsafe that answers to the bank (failsafeBank), and record the generator the status
--- shows: a running one beside the bank first, since it carries the load; then a running one; of
--- those alike, one whose failsafe answers to the bank, else one with a failsafe, else the nearest.
--- One not beside the bank is `distant`. The failsafe runs a generator only while the bank could
--- carry its load (Bank:canCarryLoad). While the bank is unloaded, the last known state holds.
function Bank:updateGenerator()
    if not self:getSquare() then return end
    local armed = self:canCarryLoad()
    local shown, shownRank
    for _, found in ipairs(generatorsFor(self)) do
        local generator = found.generator
        local controls = found.failsafe and failsafeBank(generator) == self
        if controls then
            runFailsafe(generator, armed, self.charge)
        end
        local running = generator:isActivated()
        local carries = running and found.beside
        local rank = (carries and 8 or 0) + (running and 4 or 0) + (controls and 2 or 0) + (found.failsafe and 1 or 0)
        -- Nearest first, so of two alike the nearer stays.
        if not shown or rank > shownRank then
            shown, shownRank = {
                x = generator:getX(), y = generator:getY(), z = generator:getZ(), running = running,
                distant = not found.beside, failsafe = found.failsafe, controls = controls, armed = armed,
            }, rank
        end
    end
    self.generator = shown or false
end

--- Whether a running generator beside the bank carries its load in the bank's place.
function Bank:backupCarriesLoad()
    return self.generator and self.generator.running and not self.generator.distant
end

return Bank
