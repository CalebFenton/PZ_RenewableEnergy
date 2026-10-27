-- Generators running on gas, on the authority: the Gas Conversion Kit's jobs and the pass that
-- feeds each kitted generator from its digester or gasifier.
--
-- A generator on gas runs on vanilla's own update (sound, zombies, fumes, wear, backfire); only its
-- fuel is managed here. Vanilla stops a generator whose fuel runs out, so while gas reaches it the
-- generator holds at least PHANTOM_FUEL and every pass puts back what was burned, billed to the gas.
-- Its real tank is kept apart (`tank`) and restored once gas stops, the kit comes off or the line is
-- cut. A kitted generator can't be picked up, so the phantom fuel never leaves with it.

if isClient() then return end

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Sprites = require "RenewableEnergy/Sprites"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local Payers = require "RenewableEnergy/PowerBank/Payers"
local Fumes = require "RenewableEnergy/Fumes"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Chance = require "cf_commonlib/Chance"
local Clock = require "cf_commonlib/Clock"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local Items = require "cf_commonlib/Items"
local Squares = require "cf_commonlib/Squares"
local Tiles = require "cf_commonlib/Tiles"

local GasLines = {}
RenewableEnergy.GasLines = GasLines

-- Cap on one pass (a save loaded after the clock jumped). Time a generator spent unloaded is billed
-- by vanilla to its fuel when it loads (IsoGenerator.update), and the next pass bills that to the gas.
local LONGEST_PASS = 24
local EPSILON = RenewableEnergy.EPSILON
-- Vanilla's wear chance for a generator whose item script it can't find (IsoGenerator.update).
local NO_SCRIPT_ONE_IN = 30
-- Global ModData older saves keep: kitted generators by "x,y,z", each { x, y, z, source }.
local LEGACY_LIST = "RenewableEnergyGasKits"

local function generatorAt(position)
    local square = getSquare(position.x, position.y, position.z)
    return square and Squares.findObjectOn(square, GeneratorReach.isVanillaGenerator)
end

-- The record of the source at `position` ({ x, y, z, kind }), loaded or not. A source has
-- canSupply(), supply(litres), capW(), wearFactor() and afterChange(), and a piped one
-- (GasKit.SOURCES) setPipe(side).
local function recordAt(position)
    return position and GasKit.SOURCES[position.kind].owner.recordAt(position.x, position.y, position.z)
end

local function isPiped(position)
    return position ~= nil and GasKit.SOURCES[position.kind].piped == true
end

local isKitOverlay = Sprites.matcher(Sprites.gasKit)
local isGeneratorPipeOverlay = Sprites.matcher(Sprites.gasifierPipeGen)

-- Takes the pipe off the piped source at `position`: its half of it.
local function unpipeSource(position)
    local record = isPiped(position) and recordAt(position)
    if record then
        record:setPipe(nil)
    end
end

-- Lays a pipe between `generator` and the piped source `source`, each half on its own tile.
local function pipe(generator, source)
    local gx, gy, x, y = generator:getX(), generator:getY(), source:getX(), source:getY()
    Tiles.showOverlay(generator, isGeneratorPipeOverlay,
        Sprites.gasifierPipeGenFor(Sprites.nameOf(generator), Gasifier.sideOf(gx, gy, x, y)))
    local record = Gasifier.recordOf(source)
    if record then
        record:setPipe(Gasifier.sideOf(x, y, gx, gy))
    end
end

-- Forgets what the line last measured and why it stopped, once nothing runs on its gas to say it of:
-- the line is cut, or the generator switched to petrol.
local function forgetGas(state)
    state.stalled = false
    state.outOfGas = false
    state.watts = nil
end

-- Cuts the line, a pipe at both ends, and forgets what it was waiting for. Returns what the line
-- took ({ item, count }), or nil.
local function cutLine(generator, state)
    if isPiped(state.source) then
        Tiles.showOverlay(generator, isGeneratorPipeOverlay, nil)
        unpipeSource(state.source)
    end
    local line = state.line
    state.source = nil
    state.line = nil
    forgetGas(state)
    return line
end

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

-- Vanilla's generator wear: each hour running, one chance in this many of losing 1 or 2 condition
-- (IsoGenerator.update, the generator item's ConditionLowerChanceOneIn).
local function wearOneIn(generator)
    local item = getScriptManager():getItem(generator:getGeneratorItemType())
    return item and item:getConditionLowerChance() or NO_SCRIPT_ONE_IN
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
        if Chance.hit((factor - 1) / wearOneIn(generator)) then
            generator:setCondition(generator:getCondition() - Chance.between(1, 2))
        end
    end
end

-- Litres the generator lost since the last pass on gas, to vanilla's burn, which bills the banks
-- charging from it too (Payers). Read off the fuel itself, before settleFuel puts it back, so the
-- gas pays exactly what was taken.
local function burnedSince(generator, state)
    return state.onGas and math.max(0, (state.set or 0) - generator:getFuel()) or 0
end

-- Whether vanilla stopped the generator for fuel: its hourly bill took all it showed. Every pass on
-- gas leaves at least PHANTOM_FUEL, and neither a stall nor a player switching it off empties it,
-- so on gas only that bill does, an hour's, or every hour of a long absence at once when its chunk
-- loads (IsoGenerator.update). One worn out by the same bill stays stopped.
local function stoppedForFuel(generator, state)
    return state.onGas and not state.stalled and not generator:isActivated() and generator:getFuel() <= EPSILON
        and generator:getCondition() > 0
end

-- Litres the generator would have burned through the bill that stopped it: an hour's bill for each
-- whole hour since its last, as vanilla bills them, at its bill when a pass last saw it run. Before
-- any pass saw it run, the pass's `hours` at its bill now.
local function dryBill(generator, state, hours)
    if not state.billedHour then
        return hours * generator:getTotalPowerUsing()
    end
    return (math.floor(getGameTime():getWorldAgeHours()) - state.billedHour) * state.billLitres
end

-- Keeps track of vanilla's last bill of the generator running on gas, which Lua can't read: fuel
-- taken since the last pass means this hour's came, and a pass that comes between a new hour and
-- vanilla's bill of it keeps the last.
-- getTotalPowerUsing already includes GeneratorFuelConsumption (IsoGenerator).
local function trackBill(generator, state, litres)
    if generator:isActivated() and state.onGas then
        if not state.billedHour or litres > 0 then
            state.billedHour = math.floor(getGameTime():getWorldAgeHours())
        end
        state.billLitres = generator:getTotalPowerUsing()
    else
        state.billedHour, state.billLitres = nil, nil
    end
end

--- Runs one kitted generator for `hours`: its source pays for the fuel it burned on gas, it stalls
--- over what the source carries until the load fits again, stops when the gas runs out. Stopped by
--- vanilla for fuel while on gas, it ran those hours on gas: the source pays for them and it starts
--- again. A line whose source is gone is lost with it, on petrol too: nothing comes back from it.
function GasLines.run(generator, state, hours)
    local record = recordAt(state.source)
    if state.source and not record then
        cutLine(generator, state)
    end
    if state.mode == "petrol" then
        record = nil
    end
    local hasGas = record and record:canSupply()
    local litres = burnedSince(generator, state)
    local ranDry = stoppedForFuel(generator, state)
    if ranDry then
        litres = math.max(litres, dryBill(generator, state, hours))
    end
    if hasGas and litres > 0 then
        hasGas = record:supply(litres)
        record:afterChange()
    end
    if ranDry and hasGas then
        Fumes.setRunning(generator, true)
    end
    if record and state.onGas and not hasGas and (ranDry or generator:isActivated()) then
        Fumes.setRunning(generator, false)
        state.outOfGas = true
    end
    if generator:isActivated() and state.onGas then
        local watts = Payers.deliveredW(generator)
        state.watts = watts
        if watts > GasKit.capW(generator) then
            Fumes.setRunning(generator, false)
            state.stalled = true
        elseif record then
            wear(generator, state, record:wearFactor(), hours)
        end
    elseif state.stalled and hasGas and not generator:isActivated() then
        local watts = Payers.deliveredW(generator)
        state.watts = watts
        if watts <= record:capW() then
            Fumes.setRunning(generator, true)
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
    trackBill(generator, state, litres)
end

-- Runs `generator` for the time since it last ran, at most LONGEST_PASS.
local function catchUp(generator, state)
    GasLines.run(generator, state, Clock.hoursSince(state, LONGEST_PASS))
end

-- A gasifier piped to a generator that the list of an older save still held after the generator
-- was gone keeps its half of the pipe; the first pass that finds that square loaded takes it off,
-- and the list goes once every entry is settled.
local function settleLegacyList()
    if not ModData.exists(LEGACY_LIST) then return end
    local list = ModData.get(LEGACY_LIST)
    local settled, waiting = {}, false
    for key, entry in pairs(list) do
        if not isPiped(entry.source) then
            table.insert(settled, key)
        elseif getSquare(entry.x, entry.y, entry.z) then
            if not GasKit.hasKit(generatorAt(entry)) then
                unpipeSource(entry.source)
            end
            table.insert(settled, key)
        else
            waiting = true
        end
    end
    if not waiting then
        ModData.remove(LEGACY_LIST)
        return
    end
    for _, key in ipairs(settled) do
        list[key] = nil
    end
end

--- Runs every kitted generator whose chunk is loaded (Payers.eachGenerator); an unloaded one waits.
function GasLines.updateAll()
    settleLegacyList()
    Payers.eachGenerator(function(generator)
        local state = GasKit.stateOf(generator)
        if state then
            catchUp(generator, state)
            generator:transmitModData()
        end
    end)
end

Events.EveryTenMinutes.Add(GasLines.updateAll)

-- A kitted generator leaving the map, burnt or taken away, takes its half of a gasifier's pipe
-- with it, so the gasifier's half comes off too.
Events.OnObjectAboutToBeRemoved.Add(function(isoObject)
    local state = GasKit.stateOf(isoObject)
    if state then
        unpipeSource(state.source)
    end
end)

--- A failsafe relay calls off a stalled line's restart: clears `stalled` and sends the state.
--- Nothing for a generator without a kit or not stalled.
function GasLines.cancelStall(generator)
    local state = GasKit.stateOf(generator)
    if state and state.stalled then
        state.stalled = false
        generator:transmitModData()
    end
end

-- Cuts the line, which gives back what it took, and the generator holds only its tank.
local function disconnect(character, generator, state)
    local line = cutLine(generator, state)
    if line then
        Items.giveItems(character, line.item, line.count)
    end
    settleFuel(generator, state, false)
    if state.mode ~= "petrol" then
        Fumes.setRunning(generator, false)
    end
end

-- What each job does at `generator` (its kit state `state`, nil before Install) beyond taking its
-- materials, by its row of GasKit.JOBS; `source` is Connect's. Returns whether it was done.
local DO = {
    [GasKit.INSTALL] = function(character, state, row, generator)
        generator:getModData()[GasKit.STATE_KEY] = { kit = true, mode = "gas", tank = generator:getFuel(), onGas = false,
            lastHour = getGameTime():getWorldAgeHours() }
        Payers.track(generator)
        Tiles.showOverlay(generator, isKitOverlay, Sprites.gasKitFor(Sprites.nameOf(generator)))
        return true
    end,
    [GasKit.REMOVE] = function(character, state, row, generator)
        disconnect(character, generator, state)
        generator:getModData()[GasKit.STATE_KEY] = nil
        Tiles.showOverlay(generator, isKitOverlay, nil)
        Items.giveItems(character, GasKit.ITEM)
        return true
    end,
    [GasKit.CONNECT] = function(character, state, row, generator, source)
        local kind = GasKit.sourceKind(source)
        local spec = GasKit.SOURCES[kind]
        local line = spec.line(generator, source)
        state.source = { x = source:getX(), y = source:getY(), z = source:getZ(), kind = kind }
        state.line = { item = line.item, count = line.need }
        if spec.piped then
            pipe(generator, source)
        end
        GasLines.run(generator, state, 0)
        return true
    end,
    [GasKit.DISCONNECT] = function(character, state, row, generator)
        disconnect(character, generator, state)
        return true
    end,
    [GasKit.TO_GAS] = function(character, state, row, generator)
        state.mode = row.mode
        GasLines.run(generator, state, 0)
        return true
    end,
    [GasKit.TO_PETROL] = function(character, state, row, generator)
        state.mode = row.mode
        forgetGas(state)
        settleFuel(generator, state, false)
        return true
    end,
}

--- The authority's side of the jobs at a generator (Jobs.perform), whose `with` is the far end
--- of Connect Gas Line. They work on its kit state, the line caught up first so the time before
--- bills at the old state. Settle once after catch-up and mutation, including a refused job whose
--- catch-up started or stopped a generator; the periodic gas pass has its own following settlement.
GasLines.jobSite = {
    open = function(generator)
        local state = GasKit.stateOf(generator)
        if state then
            catchUp(generator, state)
        end
        return state
    end,
    act = function(character, job, state, row, generator, source)
        return DO[job](character, state, row, generator, source)
    end,
    tell = function(state, generator, done)
        if done or state then
            Payers.billGenerators()
            generator:transmitModData()
        end
    end,
}
Action.serve({ kit = GasLines.jobSite })

--- Fits the kit to `generator` and runs its line to `source`, as Install Kit and Connect Gas Line
--- do, for a generator the world places rather than a player (SolarSites): nobody pays for them.
function GasLines.fit(generator, source)
    DO[GasKit.INSTALL](nil, nil, GasKit.JOBS[GasKit.INSTALL], generator)
    DO[GasKit.CONNECT](nil, GasKit.stateOf(generator), GasKit.JOBS[GasKit.CONNECT], generator, source)
    generator:transmitModData()
end

return GasLines
