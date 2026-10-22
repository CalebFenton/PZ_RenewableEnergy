if isClient() then return end

-- Generators running on gas, on the authority: the Gas Conversion Kit's jobs and the pass that
-- feeds each kitted generator from its digester or gasifier.
--
-- A generator on gas runs on vanilla's own update (sound, zombies, fumes, wear, backfire); only its
-- fuel is managed here. Vanilla stops a generator whose fuel runs out, so while gas reaches it the
-- generator holds at least PHANTOM_FUEL and every pass puts back what was burned, billed to the gas.
-- Its real tank is kept apart (`tank`) and restored once gas stops, the kit comes off or the line is
-- cut. A kitted generator can't be picked up, so the phantom fuel never leaves with it.

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

-- Global ModData: kitted generators by "x,y,z", each { x, y, z, source }; the source is kept so a
-- gasifier's pipe can come off after the generator is gone.
GasLines.MOD_DATA = "RenewableEnergyGasKits"
-- Cap on one pass (a save loaded after the clock jumped). Time a generator spent unloaded is billed
-- by vanilla to its fuel when it loads (IsoGenerator.update), and the next pass bills that to the gas.
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
-- canSupply(), supply(litres), capW(), wearFactor() and afterChange(), and a piped one
-- (GasKit.SOURCES) setPipe(side).
local function sourceOf(position)
    return position and GasKit.SOURCES[position.kind].owner.recordAt(position.x, position.y, position.z)
end

local function isPiped(position)
    return position ~= nil and GasKit.SOURCES[position.kind].piped == true
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

-- Takes the pipe off the piped source at `position`: its half of it.
local function unpipeSource(position)
    local record = isPiped(position) and sourceOf(position)
    if record then
        record:setPipe(nil)
    end
end

-- Lays a pipe between `generator` and the piped source `source`, each half on its own tile.
local function pipe(generator, source)
    local gx, gy, x, y = generator:getX(), generator:getY(), source:getX(), source:getY()
    RenewableEnergy.showOverlay(generator, isGeneratorPipe,
        Sprites.gasifierPipeGenFor(Sprites.nameOf(generator), Gasifier.sideOf(gx, gy, x, y)))
    local record = Gasifier.recordOf(source)
    if record then
        record:setPipe(Gasifier.sideOf(x, y, gx, gy))
    end
end

-- Cuts the line, a pipe at both ends, and forgets what it was waiting for. Returns what the line
-- took ({ item, count }), or nil.
local function cutLine(generator, state)
    if isPiped(state.source) then
        RenewableEnergy.showOverlay(generator, isGeneratorPipe, nil)
        unpipeSource(state.source)
    end
    local line = state.line
    setSource(generator, state, nil)
    state.line = nil
    state.stalled = false
    state.outOfGas = false
    return line
end

--- The watts `generator` delivers: its share of what it powers (Payers.loadOf), and the chargers
--- of the battery banks that charge from it.
function GasLines.loadOf(generator)
    local load = RenewableEnergy.Payers.loadOf(generator)
    local watts = load.watts + load.backedW
    local key = RenewableEnergy.PlaceTracker.key(generator:getX(), generator:getY(), generator:getZ())
    local banks = RenewableEnergy.PowerBank.serverSystem
    for i = 1, (banks and banks:getLuaObjectCount() or 0) do
        local bank = banks:getLuaObjectByIndex(i)
        if bank.chargeSource == "generator" and bank.chargingFrom == key then
            watts = watts + bank:chargerW()
        end
    end
    return watts
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

-- Litres the generator lost since the last pass on gas, to vanilla's burn and any bank charging from
-- it. Read off the fuel itself, before settleFuel puts it back, so the gas pays exactly what was taken.
local function burnedSince(generator, state)
    return state.onGas and math.max(0, (state.set or 0) - generator:getFuel()) or 0
end

--- Runs one kitted generator for `hours`: its source pays for the fuel it burned on gas, it stalls
--- over what the source carries until the load fits again, stops when the gas runs out. A line
--- whose source is gone is lost with it, on petrol too: nothing comes back from it.
function GasLines.run(generator, state, hours)
    local source = sourceOf(state.source)
    if state.source and not source then
        cutLine(generator, state)
    end
    if state.mode == "petrol" then
        source = nil
    end
    local hasGas = source and source:canSupply()
    local litres = burnedSince(generator, state)
    if hasGas and litres > 0 then
        hasGas = source:supply(litres)
        source:afterChange()
    end
    if source and state.onGas and not hasGas and generator:isActivated() then
        generator:setActivated(false)
        state.outOfGas = true
    end
    if generator:isActivated() and state.onGas then
        local watts = GasLines.loadOf(generator)
        state.watts = watts
        if watts > (source and source:capW() or GasKit.CAP_W) then
            generator:setActivated(false)
            state.stalled = true
        elseif source then
            wear(generator, state, source:wearFactor(), hours)
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

-- Runs `generator` for the time since it last ran, at most LONGEST_PASS.
local function catchUp(generator, state)
    local now = getGameTime():getWorldAgeHours()
    local hours = math.min(LONGEST_PASS, now - (state.lastHour or now))
    state.lastHour = now
    GasLines.run(generator, state, hours)
end

--- Runs every kitted generator whose chunk is loaded. One gone from its loaded square or without
--- its kit leaves the list, and a gasifier's pipe to it comes off; an unloaded one waits.
function GasLines.updateAll()
    local gone = {}
    for key, entry in pairs(registry()) do
        local loaded = getSquare(entry.x, entry.y, entry.z) ~= nil
        local generator = loaded and generatorAt(entry)
        local state = generator and GasKit.stateOf(generator)
        if loaded and not state then
            table.insert(gone, key)
        elseif state then
            catchUp(generator, state)
            sync(generator)
        end
    end
    for _, key in ipairs(gone) do
        unpipeSource(registry()[key].source)
        registry()[key] = nil
    end
end

Events.EveryTenMinutes.Add(GasLines.updateAll)

--- A failsafe relay calls off a stalled line's restart: clears `stalled` and sends the state.
--- Nothing for a generator without a kit or not stalled.
function GasLines.cancelStall(generator)
    local state = GasKit.stateOf(generator)
    if state and state.stalled then
        state.stalled = false
        sync(generator)
    end
end

-- Cuts the line, which gives back what it took, and the generator holds only its tank.
local function disconnect(character, generator, state)
    local line = cutLine(generator, state)
    if line then
        RenewableEnergy.giveItems(character, line.item, line.count)
    end
    settleFuel(generator, state, false)
    if generator:isActivated() and state.mode ~= "petrol" then
        generator:setActivated(false)
    end
end

-- What each job does at `generator` (its kit state `state`, nil before Install) beyond taking its
-- materials, by its row of GasKit.JOBS; `source` is Connect's.
local DO = {
    [GasKit.INSTALL] = function(character, generator)
        generator:getModData()[GasKit.MOD_DATA] = { kit = true, mode = "gas", tank = generator:getFuel(), onGas = false,
            lastHour = getGameTime():getWorldAgeHours() }
        registry()[keyOf(generator)] = { x = generator:getX(), y = generator:getY(), z = generator:getZ() }
        RenewableEnergy.showOverlay(generator, isKitOverlay, Sprites.gasKitFor(Sprites.nameOf(generator)))
    end,
    [GasKit.REMOVE] = function(character, generator, state)
        disconnect(character, generator, state)
        generator:getModData()[GasKit.MOD_DATA] = nil
        registry()[keyOf(generator)] = nil
        RenewableEnergy.showOverlay(generator, isKitOverlay, nil)
        RenewableEnergy.giveItems(character, GasKit.ITEM)
    end,
    [GasKit.CONNECT] = function(character, generator, state, source)
        local kind = GasKit.sourceKind(source)
        local spec = GasKit.SOURCES[kind]
        local line = spec.line(generator, source)
        setSource(generator, state, { x = source:getX(), y = source:getY(), z = source:getZ(), kind = kind })
        state.line = { item = line.item, count = line.need }
        if spec.piped then
            pipe(generator, source)
        end
        GasLines.run(generator, state, 0)
    end,
    [GasKit.DISCONNECT] = disconnect,
    [GasKit.TO_GAS] = function(character, generator, state, source, row)
        state.mode = row.mode
        GasLines.run(generator, state, 0)
    end,
    [GasKit.TO_PETROL] = function(character, generator, state, source, row)
        state.mode = row.mode
        state.stalled = false
        settleFuel(generator, state, false)
    end,
}

--- Does `job` at `generator` for `character` once its timed action finished: catches the line up
--- first so earlier time bills at the old state, rechecks the job, does it, sends the state.
--- `source` is the far end of Connect Gas Line. Returns whether it was done.
function GasLines.perform(character, job, generator, source)
    local state = GasKit.stateOf(generator)
    if state then
        catchUp(generator, state)
    end
    local done = not GasKit.refusal(character, job, generator, source)
    if done then
        local row = GasKit.JOBS[job]
        Materials.consume(character, GasKit.materials(job, generator, source))
        DO[job](character, generator, state, source, row)
        if row.xp then
            addXp(character, Perks[row.xp.perk], row.xp.amount)
        end
    end
    if done or state then
        sync(generator)
    end
    return done
end

--- Fits the kit to `generator` and runs its line to `source`, as Install Kit and Connect Gas Line
--- do, for a generator the world places rather than a player (SolarSites): nobody pays for them.
function GasLines.fit(generator, source)
    DO[GasKit.INSTALL](nil, generator)
    DO[GasKit.CONNECT](nil, generator, GasKit.stateOf(generator), source)
    sync(generator)
end

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
