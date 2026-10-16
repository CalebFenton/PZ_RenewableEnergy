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
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/PowerBank/Loads"

RenewableEnergy = RenewableEnergy or {}
local GasLines = {}
RenewableEnergy.GasLines = GasLines

local GasKit, Digester, Gasifier, Sprites = RenewableEnergy.GasKit, RenewableEnergy.Digester, RenewableEnergy.Gasifier, RenewableEnergy.Sprites

-- Global ModData: the kitted generators by "x,y,z", so the pass finds them.
GasLines.MOD_DATA = "RenewableEnergyGasKits"
-- A pass longer than this (a save loaded after the clock jumped) counts as this long.
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

-- The record of the line's source, loaded or not: a digester or a gasifier. A source has
-- canSupply(), supply(watts, hours), capW(), wearFactor() and afterChange().
local function sourceOf(state)
    local position = state.source
    if not position then return nil end
    local system = position.kind == "gasifier" and Gasifier.serverSystem or Digester.serverSystem
    return system and system:getLuaObjectAt(position.x, position.y, position.z) or nil
end

local function sync(generator)
    if isServer() then
        generator:transmitModData()
    end
end

local function isKitOverlay(name)
    return name == Sprites.gasKit
end

local GENERATOR_PIPES = {}
for _, name in pairs(Sprites.gasifierPipeGen) do
    GENERATOR_PIPES[name] = true
end

local function isGeneratorPipe(name)
    return GENERATOR_PIPES[name] == true
end

-- The kit's valve on the generator's tile.
local function showKit(generator, fitted)
    RenewableEnergy.showOverlay(generator, isKitOverlay, fitted and Sprites.gasKit or nil)
end

-- A gasifier's pipe: the generator's half toward the gasifier's side, and the gasifier's half
-- toward the generator's; nil sides take them off.
local function showPipe(generator, gasifierSide, gasifier)
    RenewableEnergy.showOverlay(generator, isGeneratorPipe, gasifierSide and Sprites.gasifierPipeGen[gasifierSide] or nil)
    local record = gasifier and Gasifier.recordOf(gasifier)
    if record then
        record.pipe = gasifierSide and Gasifier.sideOf(gasifier:getX(), gasifier:getY(), generator:getX(), generator:getY()) or nil
        record:afterChange()
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
    local source = state.mode ~= "petrol" and sourceOf(state)
    if state.source and not source and state.mode ~= "petrol" then
        -- The source went: the line goes with it.
        if state.source.kind == "gasifier" then
            showPipe(generator, nil, nil)
        end
        state.source = nil
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

--- Runs every kitted generator whose chunk is loaded. One that is gone from its loaded square, or
--- lost its kit, leaves the list; an unloaded one waits, and vanilla bills the time away to its
--- fuel when it loads again (IsoGenerator.update), which PHANTOM_FUEL covers.
function GasLines.updateAll()
    local now = getGameTime():getWorldAgeHours()
    local gone = {}
    for key, position in pairs(registry()) do
        local loaded = getSquare(position.x, position.y, position.z) ~= nil
        local generator = loaded and generatorAt(position)
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
        registry()[key] = nil
    end
end

Events.EveryTenMinutes.Add(GasLines.updateAll)

-- Jobs ------------------------------------------------------------------------------------------

local function takeItems(character, fullType, count)
    local items = character:getInventory():getSomeTypeRecurse(fullType, count)
    for i = 0, items:size() - 1 do
        RenewableEnergy.takeItem(character, items:get(i))
    end
end

local function giveItems(character, fullType, count)
    local inventory = character:getInventory()
    for _ = 1, count do
        local item = inventory:AddItem(fullType)
        if item then
            sendAddItemToContainer(inventory, item)
        end
    end
end

-- Cuts the line: the hoses or the pipe come back, and the generator holds only its tank.
local function disconnect(character, generator, state)
    if state.hoses and state.hoses > 0 then
        giveItems(character, GasKit.HOSE, state.hoses)
    end
    if state.source and state.source.kind == "gasifier" then
        giveItems(character, GasKit.PIPE, 1)
        showPipe(generator, nil, GasKit.sourceAt(state.source))
    end
    state.source, state.hoses = nil, nil
    settleFuel(generator, state, false)
    if generator:isActivated() and state.mode ~= "petrol" then
        generator:setActivated(false)
    end
end

--- Does `job` at `generator` for `character`, on the authority, once its timed action finished
--- and its needs were checked. `source` is the digester or gasifier at the far end of Connect Gas
--- Line. Returns whether it was done.
function GasLines.perform(character, job, generator, source)
    if GasKit.refusal(character, job, generator, source) then
        return false
    end
    local modData = generator:getModData()
    local state = GasKit.stateOf(generator)
    if job == GasKit.INSTALL then
        takeItems(character, GasKit.ITEM, 1)
        modData[GasKit.MOD_DATA] = { kit = true, mode = "gas", tank = generator:getFuel(), onGas = false,
            lastHour = getGameTime():getWorldAgeHours() }
        registry()[keyOf(generator)] = { x = generator:getX(), y = generator:getY(), z = generator:getZ() }
        showKit(generator, true)
        addXp(character, Perks.Mechanics, 15)
    elseif job == GasKit.REMOVE then
        disconnect(character, generator, state)
        modData[GasKit.MOD_DATA] = nil
        registry()[keyOf(generator)] = nil
        showKit(generator, false)
        giveItems(character, GasKit.ITEM, 1)
    elseif job == GasKit.CONNECT then
        local kind = GasKit.sourceKind(source)
        state.source = { x = source:getX(), y = source:getY(), z = source:getZ(), kind = kind }
        if kind == "gasifier" then
            takeItems(character, GasKit.PIPE, 1)
            showPipe(generator, Gasifier.sideOf(generator:getX(), generator:getY(), source:getX(), source:getY()), source)
        else
            local hoses = GasKit.hosesFor(generator, source)
            takeItems(character, GasKit.HOSE, hoses)
            state.hoses = hoses
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
