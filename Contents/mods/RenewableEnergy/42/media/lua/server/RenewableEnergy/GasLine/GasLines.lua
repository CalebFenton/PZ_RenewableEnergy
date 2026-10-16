if isClient() then return end

-- Generators running on gas, on the authority: the Gas Conversion Kit's jobs and the pass that
-- feeds each kitted generator from its source, a digester or a gasifier.
--
-- A generator on gas runs on vanilla's own update, which makes its sound, draws zombies, fills a
-- building with fumes, wears it and backfires as on petrol; only its fuel is managed here. Vanilla
-- stops a generator whose fuel runs out, so while gas reaches it the generator holds at least
-- PHANTOM_FUEL, and every pass puts back what vanilla burned (and what a bank charging from it
-- took): the gas paid for it. Its real tank is kept apart (`tank`) and is all it holds again once
-- gas stops, the kit comes off or the line is cut. A kitted generator can't be picked up, so the
-- fuel that isn't there never leaves with it.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Materials"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/PowerBank/Loads"

RenewableEnergy = RenewableEnergy or {}
local GasLines = {}
RenewableEnergy.GasLines = GasLines

local GasKit, Gasifier, Sprites, Materials = RenewableEnergy.GasKit, RenewableEnergy.Gasifier, RenewableEnergy.Sprites, RenewableEnergy.Materials

-- Global ModData: the kitted generators by "x,y,z", so the pass finds them, each { x, y, z,
-- source }, its line's source kept too so a gasifier's pipe can come off after the generator is
-- gone.
GasLines.MOD_DATA = "RenewableEnergyGasKits"
-- A pass longer than this (a save loaded after the clock jumped) counts as this long. A generator
-- runs here only while loaded; vanilla bills the time it was away to its fuel when it loads
-- (IsoGenerator.update), which PHANTOM_FUEL covers, so the gas pays for a day of it at most.
local LONGEST_PASS = 24
local EPSILON = 1e-4
-- Vanilla's generator wear: each hour running, one chance in this many of losing 1 or 2 condition
-- (IsoGenerator.update, the item's ConditionLowerChanceOneIn). Dirty gas adds chances on top.
local WEAR_ONE_IN = 30

local function keyOf(object)
    return object:getX() .. "," .. object:getY() .. "," .. object:getZ()
end

local function registry()
    return ModData.getOrCreate(GasLines.MOD_DATA)
end

local function generatorAt(position)
    local square = getSquare(position.x, position.y, position.z)
    return square and RenewableEnergy.findObjectOn(square, GasKit.isGenerator)
end

-- The record of the source at `position` ({ x, y, z, kind }), loaded or not. A source has
-- canSupply(), supply(watts, hours), capW(), wearFactor() and afterChange().
local function sourceOf(position)
    return position and GasKit.SOURCES[position.kind].recordAt(position.x, position.y, position.z)
end

local function sync(generator)
    if isServer() then
        generator:transmitModData()
    end
end

local isKitOverlay = Sprites.matcher(Sprites.gasKit)
local isGeneratorPipe = Sprites.matcher(Sprites.gasifierPipeGen)

-- Sets the line's source, in the generator's state and its registry entry.
local function setSource(generator, state, source)
    state.source = source
    registry()[keyOf(generator)].source = source
end

-- Takes a gasifier's pipe off its side: the gasifier's half of it, on the gasifier at `position`.
local function unpipeGasifier(position)
    local record = position and position.kind == "gasifier" and sourceOf(position)
    if record then
        record:setPipe(nil)
    end
end

-- Lays a gasifier's pipe between `generator` and `gasifier`, each half on its own tile.
local function pipe(generator, gasifier)
    local gx, gy, x, y = generator:getX(), generator:getY(), gasifier:getX(), gasifier:getY()
    RenewableEnergy.showOverlay(generator, isGeneratorPipe, Sprites.gasifierPipeGen[Gasifier.sideOf(gx, gy, x, y)])
    local record = Gasifier.recordOf(gasifier)
    if record then
        record:setPipe(Gasifier.sideOf(x, y, gx, gy))
    end
end

-- Cuts the line where it ends at its source, if a gasifier's pipe, and at the generator.
local function unpipe(generator, state)
    if state.source and state.source.kind == "gasifier" then
        RenewableEnergy.showOverlay(generator, isGeneratorPipe, nil)
        unpipeGasifier(state.source)
    end
end

-- Load ------------------------------------------------------------------------------------------

local function reachOf(generator, x, y, z)
    local radius = SandboxVars.GeneratorTileRange
    local levels = SandboxVars.GeneratorVerticalPowerRange
    return math.abs(z - generator:getZ()) <= levels
        and IsoUtils.DistanceToSquared(generator:getX() + 0.5, generator:getY() + 0.5, x + 0.5, y + 0.5) <= radius * radius
end

--- The watts `generator` delivers: what it powers, and the chargers of the battery banks that
--- charge from a generator within its reach.
function GasLines.loadOf(generator)
    local watts = RenewableEnergy.Loads.scan(generator:getSquare()).watts
    local banks = RenewableEnergy.PowerBank.serverSystem
    for i = 1, (banks and banks:getLuaObjectCount() or 0) do
        local bank = banks:getLuaObjectByIndex(i)
        if bank.chargeSource == "generator" and reachOf(generator, bank.x, bank.y, bank.z) then
            watts = watts + bank:chargerW()
        end
    end
    return watts
end

-- The pass -----------------------------------------------------------------------------------------

-- Fuel the generator holds now: on gas, its tank or PHANTOM_FUEL, whichever is more; else its
-- tank. A rise since the last pass on gas is petrol someone poured in, which goes into the tank.
local function settleFuel(generator, state, onGas)
    if state.onGas then
        local fuel = generator:getFuel()
        if fuel > (state.set or 0) + EPSILON then
            state.tank = math.min(generator:getMaxFuel(), state.tank + fuel - state.set)
        end
    else
        state.tank = generator:getFuel()
    end
    if onGas then
        local want = math.max(state.tank, GasKit.PHANTOM_FUEL)
        if math.abs(generator:getFuel() - want) > EPSILON then
            generator:setFuel(want)
        end
        state.set = want
    elseif state.onGas then
        generator:setFuel(state.tank)
        state.set = nil
    end
    state.onGas = onGas
end

-- Dirty gas (`factor` times vanilla's wear) wears a running generator more over `hours`, rolled
-- as vanilla rolls its own, once an hour.
local function wear(generator, state, factor, hours)
    if factor <= 1 then
        state.wearHours = nil
        return
    end
    state.wearHours = (state.wearHours or 0) + hours
    while state.wearHours >= 1 do
        state.wearHours = state.wearHours - 1
        if ZombRandFloat(0, 1) < (factor - 1) / WEAR_ONE_IN then
            generator:setCondition(generator:getCondition() - ZombRand(1, 3))
        end
    end
end

--- Runs one kitted generator for `hours`: it burns its source's gas while it runs, stalls over
--- what the source carries until the load fits again, stops when the gas runs out.
function GasLines.run(generator, state, hours)
    local source = state.mode ~= "petrol" and sourceOf(state.source)
    if state.source and not source and state.mode ~= "petrol" then
        -- The source went, and the line with it: nothing comes back from it.
        unpipe(generator, state)
        setSource(generator, state, nil)
        state.hoses = nil
    end
    local hasGas = source and source:canSupply()
    if generator:isActivated() and state.onGas then
        local watts = GasLines.loadOf(generator)
        state.watts = watts
        if watts > (source and source:capW() or GasKit.CAP_W) then
            generator:setActivated(false)
            state.stalled = true
        elseif source then
            if not source:supply(watts, hours) then
                generator:setActivated(false)
                state.outOfGas = true
                hasGas = false
            else
                wear(generator, state, source:wearFactor(), hours)
            end
            source:afterChange()
        end
    elseif state.stalled and hasGas and not generator:isActivated() then
        local watts = GasLines.loadOf(generator)
        state.watts = watts
        if watts <= source:capW() then
            generator:setActivated(true)
            state.stalled = false
        end
    end
    if hasGas then
        state.outOfGas = false
    end
    if not generator:isActivated() and not state.stalled then
        state.watts = nil
    end
    settleFuel(generator, state, hasGas or false)
end

--- Runs every kitted generator whose chunk is loaded. One that is gone from its loaded square
--- (destroyed; it can't be picked up), or lost its kit, leaves the list, and a gasifier's pipe to
--- it comes off; an unloaded one waits, and vanilla bills the time away to its fuel when it loads
--- again (IsoGenerator.update), which PHANTOM_FUEL covers.
function GasLines.updateAll()
    local now = getGameTime():getWorldAgeHours()
    local gone = {}
    for key, entry in pairs(registry()) do
        local loaded = getSquare(entry.x, entry.y, entry.z) ~= nil
        local generator = loaded and generatorAt(entry)
        local state = generator and GasKit.stateOf(generator)
        if loaded and not state then
            table.insert(gone, key)
        elseif state then
            local hours = math.min(LONGEST_PASS, now - (state.lastHour or now))
            state.lastHour = now
            GasLines.run(generator, state, hours)
            sync(generator)
        end
    end
    for _, key in ipairs(gone) do
        unpipeGasifier(registry()[key].source)
        registry()[key] = nil
    end
end

Events.EveryTenMinutes.Add(GasLines.updateAll)

-- Jobs ------------------------------------------------------------------------------------------

-- Cuts the line: the hoses or the pipe come back, and the generator holds only its tank.
local function disconnect(character, generator, state)
    if state.hoses then
        RenewableEnergy.giveItems(character, GasKit.HOSE, state.hoses)
    end
    if state.source and state.source.kind == "gasifier" then
        RenewableEnergy.giveItems(character, GasKit.PIPE)
    end
    unpipe(generator, state)
    setSource(generator, state, nil)
    state.hoses = nil
    settleFuel(generator, state, false)
    if generator:isActivated() and state.mode ~= "petrol" then
        generator:setActivated(false)
    end
end

--- Does `job` at `generator` for `character`, on the authority, once its timed action finished.
--- `source` is the digester or gasifier at the far end of Connect Gas Line (the action's `other`;
--- no kit job takes an `item`). Returns whether it was done.
function GasLines.perform(character, job, generator, item, source)
    if GasKit.refusal(character, job, generator, item, source) then
        return false
    end
    Materials.consume(character, GasKit.materials(job, generator, source))
    local modData = generator:getModData()
    local state = GasKit.stateOf(generator)
    if job == GasKit.INSTALL then
        modData[GasKit.MOD_DATA] = { kit = true, mode = "gas", tank = generator:getFuel(), onGas = false,
            lastHour = getGameTime():getWorldAgeHours() }
        registry()[keyOf(generator)] = { x = generator:getX(), y = generator:getY(), z = generator:getZ() }
        RenewableEnergy.showOverlay(generator, isKitOverlay, Sprites.gasKit)
        addXp(character, Perks.Mechanics, 15)
    elseif job == GasKit.REMOVE then
        disconnect(character, generator, state)
        modData[GasKit.MOD_DATA] = nil
        registry()[keyOf(generator)] = nil
        RenewableEnergy.showOverlay(generator, isKitOverlay, nil)
        RenewableEnergy.giveItems(character, GasKit.ITEM)
    elseif job == GasKit.CONNECT then
        local kind = GasKit.sourceKind(source)
        setSource(generator, state, { x = source:getX(), y = source:getY(), z = source:getZ(), kind = kind })
        if kind == "gasifier" then
            pipe(generator, source)
        else
            state.hoses = GasKit.hosesFor(generator, source)
        end
        state.lastHour = getGameTime():getWorldAgeHours()
        GasLines.run(generator, state, 0)
        addXp(character, Perks.Mechanics, 5)
    elseif job == GasKit.DISCONNECT then
        disconnect(character, generator, state)
    elseif job == GasKit.TO_PETROL then
        state.mode = "petrol"
        state.stalled = false
        settleFuel(generator, state, false)
    elseif job == GasKit.TO_GAS then
        state.mode = "gas"
        GasLines.run(generator, state, 0)
    end
    sync(generator)
    return true
end

-- Picking up --------------------------------------------------------------------------------------

-- Taking up a kitted generator is refused: the kit would fall off (ISTakeGenerator copies only
-- fuel and condition to the item) and with it what the tank really holds.
require "TimedActions/ISTakeGenerator"
local complete = ISTakeGenerator.complete
function ISTakeGenerator:complete()
    if GasKit.hasKit(self.generator) then
        return false
    end
    return complete(self)
end

return GasLines
