-- Who pays for an appliance that more than one running source reaches: the nearest one, alone.
-- Vanilla bills every generator for everything in its reach, so overlapping generators each burn
-- fuel for the same fridge, and banks, measuring their load the same way, would each drain for it.
--
-- A source is a running vanilla generator or a bank powering its squares. Nearest is by tiles,
-- each level counting as one; a tie goes to the lower position (PlaceTracker.key), so every
-- source agrees on the payer. A bank measures its own load against the sources running now
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

-- Generators found as their chunk loads, as a player starts one (below), and as a bank comes on
-- one in its reach. A generator dropped from the hands fires no event, so it is found once started.
local generators = PlaceTracker.new({ sprites = generatorSprites(), matches = GasKit.isGenerator })

--- Track `generator`, found running some other way.
function Payers.track(generator)
    generators:add(generator)
end

local function source(x, y, z, fields)
    fields.x, fields.y, fields.z, fields.key = x, y, z, PlaceTracker.key(x, y, z)
    return fields
end

--- The source a bank is.
function Payers.ofBank(bank)
    return source(bank.x, bank.y, bank.z, { bank = bank })
end

--- The source a generator is.
function Payers.ofGenerator(generator)
    return source(generator:getX(), generator:getY(), generator:getZ(), { generator = generator })
end

-- A bank runs while its generator does; unloaded, while it would.
local function bankRuns(bank)
    local isoObject = bank:getIsoObject()
    if isoObject then
        return isoObject:isActivated()
    end
    return bank:shouldPower()
end

--- The sources running now.
function Payers.running()
    local list = {}
    generators:each(function(generator)
        if generator:isActivated() then
            table.insert(list, Payers.ofGenerator(generator))
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

local function reaches(s, x, y, z)
    local radius, levels = SandboxVars.GeneratorTileRange, SandboxVars.GeneratorVerticalPowerRange
    local dx, dy = x - s.x, y - s.y
    return math.abs(z - s.z) <= levels and dx * dx + dy * dy <= radius * radius
end

--- `payer` and the sources in `sources` that reach any square it does: those it may share with.
function Payers.sharers(payer, sources)
    local radius, levels = SandboxVars.GeneratorTileRange, SandboxVars.GeneratorVerticalPowerRange
    local span = 2 * radius
    local list = { payer }
    for _, s in ipairs(sources) do
        local dx, dy = s.x - payer.x, s.y - payer.y
        if s.key ~= payer.key and math.abs(s.z - payer.z) <= 2 * levels and dx * dx + dy * dy <= span * span then
            table.insert(list, s)
        end
    end
    return list
end

--- The source among `sharers` that pays for an appliance at x, y, z: the nearest that reaches it.
function Payers.payerAt(sharers, x, y, z)
    local best, bestDistance
    for _, s in ipairs(sharers) do
        if reaches(s, x, y, z) then
            local dx, dy, dz = x - s.x, y - s.y, z - s.z
            local distance = dx * dx + dy * dy + dz * dz
            if not best or distance < bestDistance or (distance == bestDistance and s.key < best.key) then
                best, bestDistance = s, distance
            end
        end
    end
    return best
end

-- Watts of the loads of the banks `generator` carries as their backup.
local function backedW(g)
    local watts = 0
    local banks = PowerBank.serverSystem
    for i = 1, (banks and banks:getLuaObjectCount() or 0) do
        local bank = banks:getLuaObjectByIndex(i)
        local backup = bank.generator
        if backup and backup.running and backup.x == g.x and backup.y == g.y and backup.z == g.z and bank:shouldPower() then
            watts = watts + bank.loadW
        end
    end
    return watts
end

local function treadmillInReach(g)
    local found = false
    Treadmill.eachDrawing(function(tile)
        found = found or reaches(g, tile:getX(), tile:getY(), tile:getZ())
    end)
    return found
end

--- What the running `generator` delivers, its share of `sources` (default: those running now):
--- the Loads.scan load it pays for, plus `backedW`, the banks it carries.
function Payers.loadOf(generator, sources)
    local g = Payers.ofGenerator(generator)
    local load = RenewableEnergy.Loads.scan(generator:getSquare(), g, sources or Payers.running())
    load.backedW = backedW(g)
    return load
end

-- Generators billed their share, by key: { generator, expected (what getTotalPowerUsing reads),
-- othersFuel (vanilla's bill for what others pay), extraFuel (what vanilla doesn't bill) }.
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

local function bill(generator, sources, consumption)
    local g = Payers.ofGenerator(generator)
    local shared = #Payers.sharers(g, sources) > 1
    local backed = backedW(g)
    if not shared and backed == 0 and not treadmillInReach(g) then
        if billed[g.key] then unbill(g.key) end
        return
    end
    local load = RenewableEnergy.Loads.scan(generator:getSquare(), g, sources)
    local treadmillW = load.kinds.treadmill and load.kinds.treadmill.watts or 0
    local entry = billed[g.key] or { generator = generator }
    billed[g.key] = entry
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
    local sources = Payers.running()
    local running = {}
    for _, s in ipairs(sources) do
        if s.generator then
            running[s.key] = true
            bill(s.generator, sources, consumption)
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
        if not generator:getSquare() or generator:getObjectIndex() == -1 or not generator:isActivated() then
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
