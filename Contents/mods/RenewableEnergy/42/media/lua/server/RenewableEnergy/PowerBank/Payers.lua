-- Who pays for an appliance that more than one running payer reaches: the nearest one, alone.
-- Vanilla bills every generator for everything in its reach, so overlapping generators each burn
-- fuel for the same fridge, and banks, measuring their load the same way, would each drain for it.
--
-- A payer is a running vanilla generator or a bank powering its squares. Nearest is by tiles,
-- each level counting as one; a tie goes to the lower position (PlaceTracker.key), so every
-- payer agrees on who pays. A bank measures its own load against the payers running now
-- (Loads.scan). A generator's bill is vanilla's totalPowerUsing, which the engine rebuilds
-- whenever anything in its reach switches (IsoGenerator.setSurroundingElectricity) and burns at
-- the hour (IsoGenerator.update); so its share is set after each rebuild, before the next hour.
-- A generator also pays for an unwired treadmill it powers, which vanilla doesn't know of, and
-- for the load of each bank it backs up (Bank.backupCarriesLoad).

if isClient() then return end

require "RenewableEnergy/Utilities"
require "TimedActions/ISActivateGenerator"
require "RenewableEnergy/PlaceTracker"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/GasLine/GasKit"

RenewableEnergy = RenewableEnergy or {}
local Payers = {}
RenewableEnergy.Payers = Payers

local PlaceTracker, PowerBank, Treadmill, GasKit = RenewableEnergy.PlaceTracker, RenewableEnergy.PowerBank,
    RenewableEnergy.Treadmill, RenewableEnergy.GasKit
local WATTS_PER_FUEL = RenewableEnergy.Specs.wattsPerFuel
local EPSILON = 1e-6

local function generatorSprites()
    local sprites = {}
    for name in pairs(RenewableEnergy.Sprites.gasKit.bySprite) do
        table.insert(sprites, name)
    end
    return sprites
end

-- Generators found as their chunk loads, as a player starts one (ISActivateGenerator.complete), and
-- as a bank comes on one in its reach. A generator dropped from the hands fires no event, so it is
-- found once started.
local generators = PlaceTracker.new({ sprites = generatorSprites(), matches = GasKit.isGenerator })

--- Track `generator`, found running some other way.
function Payers.track(generator)
    generators:add(generator)
end

local function newPayer(x, y, z, fields)
    fields.x, fields.y, fields.z, fields.key = x, y, z, PlaceTracker.key(x, y, z)
    return fields
end

--- The payer a bank is.
function Payers.ofBank(bank)
    return newPayer(bank.x, bank.y, bank.z, { bank = bank })
end

local function ofGenerator(generator)
    return newPayer(generator:getX(), generator:getY(), generator:getZ(), { generator = generator })
end

-- A bank runs while its generator does; unloaded, while it would.
local function bankRuns(bank)
    local isoObject = bank:getIsoObject()
    if isoObject then
        return isoObject:isActivated()
    end
    return bank:shouldPower()
end

--- The payers running now.
function Payers.running()
    local list = {}
    generators:each(function(generator)
        if generator:isActivated() then
            table.insert(list, ofGenerator(generator))
        end
    end)
    local banks = PowerBank.serverSystem
    for i = 1, (banks and banks:getLuaObjectCount() or 0) do
        local bank = banks:getLuaObjectByIndex(i)
        if bankRuns(bank) then
            table.insert(list, Payers.ofBank(bank))
        end
    end
    return list
end

local function reaches(payer, x, y, z)
    local radius, levels = SandboxVars.GeneratorTileRange, SandboxVars.GeneratorVerticalPowerRange
    local dx, dy = x - payer.x, y - payer.y
    return math.abs(z - payer.z) <= levels and dx * dx + dy * dy <= radius * radius
end

--- `payer` and the payers in `payers` that reach any square it does: those it may share with.
function Payers.sharers(payer, payers)
    local radius, levels = SandboxVars.GeneratorTileRange, SandboxVars.GeneratorVerticalPowerRange
    local span = 2 * radius
    local list = { payer }
    for _, other in ipairs(payers) do
        local dx, dy = other.x - payer.x, other.y - payer.y
        if other.key ~= payer.key and math.abs(other.z - payer.z) <= 2 * levels and dx * dx + dy * dy <= span * span then
            table.insert(list, other)
        end
    end
    return list
end

--- The payer among `sharers` that pays for an appliance at x, y, z: the nearest that reaches it.
function Payers.payerAt(sharers, x, y, z)
    local best, bestDistance
    for _, sharer in ipairs(sharers) do
        if reaches(sharer, x, y, z) then
            local dx, dy, dz = x - sharer.x, y - sharer.y, z - sharer.z
            local distance = dx * dx + dy * dy + dz * dz
            if not best or distance < bestDistance or (distance == bestDistance and sharer.key < best.key) then
                best, bestDistance = sharer, distance
            end
        end
    end
    return best
end

-- Watts of the loads of the banks the generator `payer` carries as their backup.
local function backedW(payer)
    local watts = 0
    local banks = PowerBank.serverSystem
    for i = 1, (banks and banks:getLuaObjectCount() or 0) do
        local bank = banks:getLuaObjectByIndex(i)
        local backup = bank.generator
        if backup and backup.running and PowerBank.samePosition(backup, payer) and bank:shouldPower() then
            watts = watts + bank.loadW
        end
    end
    return watts
end

local function treadmillInReach(payer)
    local found = false
    Treadmill.eachDrawing(function(tile)
        found = found or reaches(payer, tile:getX(), tile:getY(), tile:getZ())
    end)
    return found
end

--- What the running `generator` delivers, its share of `payers` (default: those running now):
--- the Loads.scan load it pays for, plus `backedW`, the banks it carries.
function Payers.loadOf(generator, payers)
    local payer = ofGenerator(generator)
    local load = RenewableEnergy.Loads.scan(generator:getSquare(), payer, payers or Payers.running())
    load.backedW = backedW(payer)
    return load
end

-- Generators billed their share, by key: { generator, baseFuel (getBasePowerConsumption as fuel),
-- expected (what getTotalPowerUsing reads), othersFuel (vanilla's bill for what others pay),
-- extraFuel (what vanilla doesn't bill) }.
local billed = {}

local function setBill(entry, fuel)
    local generator = entry.generator
    generator:setTotalPowerUsing(math.max(entry.baseFuel, fuel))
    entry.expected = generator:getTotalPowerUsing()
end

local function unbill(key)
    local entry = billed[key]
    billed[key] = nil
    local generator = entry.generator
    if generator:getSquare() and generator:isActivated() then
        generator:setSurroundingElectricity()
    end
end

local function bill(generator, payers, consumption)
    local payer = ofGenerator(generator)
    local shared = #Payers.sharers(payer, payers) > 1
    local backed = backedW(payer)
    if not shared and backed == 0 and not treadmillInReach(payer) then
        if billed[payer.key] then unbill(payer.key) end
        return
    end
    local load = RenewableEnergy.Loads.scan(generator:getSquare(), payer, payers)
    local treadmillW = load.kinds.treadmill and load.kinds.treadmill.watts or 0
    local entry = billed[payer.key] or {}
    billed[payer.key] = entry
    -- A chunk reload puts a new generator object at the same key.
    entry.generator = generator
    entry.baseFuel = generator:getBasePowerConsumption() / consumption
    entry.othersFuel = load.othersFuel
    entry.extraFuel = (treadmillW + backed) / WATTS_PER_FUEL
    setBill(entry, entry.baseFuel + (load.watts + backed) / WATTS_PER_FUEL)
end

--- Bill every running generator its share. Each one's rebuilds until the next call keep it
--- (keepShares).
function Payers.billGenerators()
    local consumption = SandboxVars.GeneratorFuelConsumption
    if consumption <= 0 then return end
    local payers = Payers.running()
    local running = {}
    for _, payer in ipairs(payers) do
        if payer.generator then
            running[payer.key] = true
            bill(payer.generator, payers, consumption)
        end
    end
    for key in pairs(billed) do
        if not running[key] then unbill(key) end
    end
end

-- After vanilla rebuilds a billed generator's bill, take off what others pay and add what it
-- doesn't know of, as of the last billing. A stopped or unloaded generator drops out.
local function keepShares()
    local consumption = SandboxVars.GeneratorFuelConsumption
    if consumption <= 0 then return end
    for key, entry in pairs(billed) do
        local generator = entry.generator
        if not generator:getSquare() or not RenewableEnergy.onSquare(generator) or not generator:isActivated() then
            billed[key] = nil
        else
            local now = generator:getTotalPowerUsing()
            if math.abs(now - entry.expected) > EPSILON then
                setBill(entry, now / consumption - entry.othersFuel + entry.extraFuel)
            end
        end
    end
end

-- A player starting or stopping a generator changes who pays nearby at once.
local vanillaComplete = ISActivateGenerator.complete
function ISActivateGenerator:complete()
    local result = vanillaComplete(self)
    if GasKit.isGenerator(self.generator) then
        Payers.track(self.generator)
        Payers.billGenerators()
    end
    return result
end

Events.OnTick.Add(keepShares)
Events.EveryTenMinutes.Add(Payers.billGenerators)

return Payers
