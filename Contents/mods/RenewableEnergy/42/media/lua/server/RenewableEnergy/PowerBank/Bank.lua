-- One battery bank on the authority (single player or the server): its batteries, inverters,
-- chargers, controllers and sources, and the energy that moves between them each pass. Its parts
-- are BankParts.lua's, its backup generator Backup.lua's, and what it tells the clients
-- BankStatus.lua's; each adds to this class.
--
-- The table is the bank's global object, a cf_commonlib ObjectSystem.Object record, so every field
-- in SAVED_FIELDS is saved with the world and kept while the chunk is unloaded. While loaded, the
-- container is the truth about the parts and each battery's charge is the truth about the charge;
-- while unloaded, the snapshot in `batteries` and `charge` carries on, and it and the wear taken
-- meanwhile are written back into the parts when the chunk loads.
--
-- A pass (catchUp, advance) switches the bank's generator at once, so the banks after it see who
-- runs, but bills nothing and tells nobody: whoever ran the pass settles it once (afterChange), a
-- job, a player's look at the bank or the system's pass over every bank.

if isClient() then return end

local Places = require "RenewableEnergy/Places"
local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local PanelSource = require "RenewableEnergy/PowerBank/PanelSource"
local WindSource = require "RenewableEnergy/PowerBank/WindSource"
local TreadmillSource = require "RenewableEnergy/PowerBank/TreadmillSource"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Payers = require "RenewableEnergy/PowerBank/Payers"
local Loads = require "RenewableEnergy/PowerBank/Loads"
local GpbBuildings = require "RenewableEnergy/PowerBank/GpbBuildings"
local Fumes = require "RenewableEnergy/Fumes"
local Clock = require "cf_commonlib/Clock"
local LibObjectSystem = require "cf_commonlib/ObjectSystem"
local Squares = require "cf_commonlib/Squares"
local Telemetry = require "cf_commonlib/Telemetry"
local Tiles = require "cf_commonlib/Tiles"

-- One line per bank pass: what came in and went out, and how long the pass took.
local passLog = Telemetry.channel("RenewableEnergy.bankPass")

local Bank = LibObjectSystem.Object:derive("RenewableEnergy_Bank")

-- The fields the Global Object System saves with the world, besides lastHour (cf_commonlib's
-- ObjectSystem); a field renamed here is lost from existing saves.
Bank.SAVED_FIELDS = {
    "bankType", "name", "on", "overloaded", "indoors", "gridPowered", "charge", "nominalWh", "batteries",
    "inverters", "chargers", "controllers", "sources", "loadW", "loadByKind", "loadElsewhere",
    "chargeSource", "chargeWantW", "generator", "day", "cycleHigh", "cycleDepth", "pendingDepths", "pendingPartWear",
    "solarWhToday", "loadWhToday", "empty", "windWhToday", "runWhToday", "backupWhToday", "connected",
    -- A building powered through Generator Powered Buildings (GpbBuildings): the litres it took
    -- since the last pass, and its watts.
    "gpbLitres", "gpbW",
    -- The last pass's sun and watts, for a status built before the next pass.
    "now",
}

-- How the bank runs each family of source (Sources.FAMILIES): connect(player, source, isoObject,
-- facing, material), if any, fills a newly connected source's record and teaches `player` what
-- connecting it first teaches; disconnect(source, object), if any, hands what the record kept back
-- to its object (nil when gone); reconcile(source, object), if any, brings the record and its
-- loaded object back into step; update(source, object, inSlot, hours, context) sets its watts and
-- reason for a pass, reconciling first; and status(entry, source), if any, adds to its status entry.
Bank.FAMILY = {
    panel = PanelSource,
    wind = WindSource,
    treadmill = TreadmillSource,
}
local FAMILY = Bank.FAMILY

local function familyOf(source)
    return FAMILY[Sources.familyOf(source.kind)]
end

local function resetToday(bank)
    for _, family in ipairs(Sources.FAMILIES) do
        bank[family.today] = 0
    end
    bank.loadWhToday = 0
    bank.backupWhToday = 0
end

function Bank:initNew()
    self.on = false
    self.overloaded = false
    -- Until its tile says otherwise (lookIndoors).
    self.indoors = false
    self.gridPowered = false
    self.connected = false
    self.charge = 0
    self.nominalWh = 0
    self.batteries = {}
    self.inverters = {}
    self.chargers = {}
    self.controllers = {}
    self.sources = {}
    self.loadW = 0
    self.loadByKind = {}
    self.loadElsewhere = false
    self.chargeSource = false
    self.generator = false
    self.cycleHigh = 0
    self.cycleDepth = 0
    self.pendingDepths = {}
    self.pendingPartWear = { hours = 0, overloads = 0 }
    resetToday(self)
    self.empty = false
end

--- An object the bank system has not seen: a bank just placed, or one from a save whose
--- global objects were lost.
function Bank:stateFromIsoObject(isoObject)
    self:initNew()
    self.bankType = PowerBank.bankOfSprite(Sprites.nameOf(isoObject)).fullType
    self:loaded(isoObject)
end

--- The bank's chunk loaded: hand the charge and wear it kept while unloaded back to its parts.
function Bank:stateToIsoObject(isoObject)
    local container = isoObject:getContainer()
    if container then
        self:writeBatteries(container, true)
        self:applyPendingPartWear(container)
    end
    self:loaded(isoObject)
end

function Bank:loaded(isoObject)
    -- IsoGenerator.update would burn fuel, wear the condition and run an engine sound.
    isoObject:getCell():addToProcessIsoObjectRemove(isoObject)
    self:lookIndoors()
    -- The truth is the generator's own connected flag; the record keeps it for while it's unloaded.
    self.connected = isoObject:isConnected()
    GpbBuildings.topUp(self, isoObject, false)
    self:refresh()
end

--- Looks again whether the bank stands indoors: a wall knocked down or the roof taken off a room
--- a player built changes it. Keeps what it knew while the game can't tell yet, as early in a
--- loading game (PowerBank.indoorsAt), or while the tile is unloaded.
function Bank:lookIndoors()
    local square = self:getSquare()
    local indoors = square and PowerBank.indoorsAt(square)
    if indoors ~= nil then
        self.indoors = indoors
    end
end

--- Look at the container again, whatever filled or emptied it: the parts it holds, whether the
--- bank runs, the batteries on its tile and the status the clients see.
function Bank:refresh()
    self:recount()
    self:switchGenerator()
    self:afterChange()
end

function Bank:spec()
    return Specs.banks[self.bankType]
end

--- The bank's container, or nil while its chunk is unloaded.
function Bank:container()
    local isoObject = self:getIsoObject()
    return isoObject and isoObject:getContainer()
end

function Bank:findSource(x, y, z)
    for i, source in ipairs(self.sources) do
        if source.x == x and source.y == y and source.z == z then
            return source, i
        end
    end
    return nil
end

--- Connects the source `isoObject`, which `player` wired to the bank.
function Bank:addSource(isoObject, player)
    local kind, facing, material = Sources.kindOf(isoObject)
    local source = { x = isoObject:getX(), y = isoObject:getY(), z = isoObject:getZ(), kind = kind, watts = 0 }
    local connect = familyOf(source).connect
    if connect then
        connect(player, source, isoObject, facing, material)
    end
    table.insert(self.sources, source)
end

--- Brings the bank's record of a source and its loaded object `object` back into step, as a pass
--- does, for a job that works on the source between passes.
function Bank.reconcileSource(source, object)
    local reconcile = familyOf(source).reconcile
    if reconcile then
        reconcile(source, object)
    end
end

-- Takes the source at `index`, whose object (if still there) is `object`, off the bank. What it
-- still owed the bank, a treadmill run not yet paid out (TreadmillSource.credit), goes into the
-- batteries now, up to full, so taking a source away forfeits nothing it made.
local function dropSource(bank, index, object)
    local source = table.remove(bank.sources, index)
    local disconnect = familyOf(source).disconnect
    if disconnect then
        disconnect(source, object)
    end
    local wh = source.pendingWh
    if wh and bank.nominalWh > 0 then
        bank.charge = math.min(1, bank.charge + wh / bank.nominalWh)
        local today = Sources.FAMILY[Sources.familyOf(source.kind)].today
        bank[today] = (bank[today] or 0) + wh
        -- Into the batteries too: the next pass's recount rereads the charge from them.
        local container = bank:container()
        if container then
            bank:writeBatteries(container, false)
        end
    end
end

function Bank:removeSource(x, y, z)
    local _, index = self:findSource(x, y, z)
    if index then
        dropSource(self, index, Sources.findOn(getSquare(x, y, z)))
    end
end

--- Every source's output over the pass, as watts by family name. A source whose square is
--- loaded is checked for still being there, where its kind works and in reach; one that is gone
--- is dropped. Each source takes its slots if they fit in what the sources before it in the
--- list left free; one that doesn't fit stays wired and makes nothing.
function Bank:updateSources(hours, context)
    local watts, slots, used = {}, self:inputSlots(), 0
    for _, family in ipairs(Sources.FAMILIES) do
        watts[family.name] = 0
    end
    -- A dropped source gives its place in the list, and so its slots, to the next one.
    local i = 1
    while i <= #self.sources do
        local source = self.sources[i]
        local square = getSquare(source.x, source.y, source.z)
        local object = Sources.findOn(square)
        if square and not (object and Sources.squareOk(square, source.kind)
            and PowerBank.inSourceReach(self, source.x, source.y, source.z)) then
            dropSource(self, i, object)
        else
            local size = Sources.slotsOf(source.kind)
            local inSlot = used + size <= slots
            if inSlot then
                used = used + size
            end
            familyOf(source).update(source, object, inSlot, hours, context)
            local family = Sources.familyOf(source.kind)
            watts[family] = watts[family] + source.watts
            i = i + 1
        end
    end
    return watts
end

-- What the bank's state is, as PowerBank.blocker reads it.
local function snapshot(bank)
    return { indoors = bank.indoors == true, limitW = bank:limitW(), capacityWh = bank.nominalWh,
        connected = bank.connected, on = bank.on, grid = bank.gridPowered }
end

--- Whether the bank can carry its load: connected, switched on, indoors, with a working inverter
--- and batteries that can hold a charge, and off the grid (PowerBank.blocker). `connected` is nil
--- on banks saved before it was recorded, and those were all connected.
function Bank:canCarryLoad()
    return PowerBank.blocker(snapshot(self)) == nil
end

--- What the bank is doing, for the status window.
function Bank:state()
    return PowerBank.blocker(snapshot(self)) or (self.overloaded and "overloaded") or (self.empty and "empty") or "on"
end

--- Measure what the bank pays for, and whether the grid powers its square. The load counts what is
--- switched on in its reach even while the grid powers it, so a bank unloaded when the grid goes
--- carries what was on, and the building it powers through Generator Powered Buildings at the last
--- pass's watts (GpbBuildings.takeWatts). Unloaded, the last measurement stands, but for that
--- building, until the grid shuts down. A bank that is off with no charger skips the scan. Returns
--- the running generators that reach the bank.
function Bank:measure()
    local square = self:getSquare()
    if not square then
        self.gridPowered = self.gridPowered and getSandboxOptions():doesPowerGridExist()
        -- That mod bills the building for the time away when the chunk loads.
        if (self.gpbW or 0) > 0 then
            self.loadW = self.loadW - self.gpbW
            for i, entry in ipairs(self.loadByKind) do
                if entry.kind == "building" then
                    table.remove(self.loadByKind, i)
                    break
                end
            end
            self.gpbW = 0
        end
        return {}
    end
    self.gridPowered = Squares.hasGridPower(square)
    local load = (self.on or self:chargerMaxW() > 0) and Payers.scan(Payers.ofBank(self), Payers.running(), true)
        or Loads.new()
    if (self.gpbW or 0) > 0 then
        Loads.add(load, "building", self.gpbW)
    end
    self.loadW = load.watts
    self.loadByKind = Loads.byKind(load)
    self.loadElsewhere = Loads.elsewhere(load) or false
    return load.generators
end

local function hasFuel(generator)
    return generator:getFuel() > 0
end

-- The nearest of `generators` with fuel to `bank` (Places.nearest).
local function fueled(bank, generators)
    return Places.nearest(generators, bank.x, bank.y, bank.z, Places.objectPlace, hasFuel)
end

-- The place key of `generator`, as chargeSource names a charging generator.
local function keyOf(generator)
    return Squares.placeKey(Places.objectPlace(generator))
end

--- What the chargers charge from, saved as `chargeSource`: "grid", the place key (keyOf) of the
--- nearest fueled running generator whose reach covers the bank, or false. Saves as `chargeWantW`
--- their watts, capped so they fill no more than `roomWh` over `hours`: a gas line splits its
--- cap by these wants (Payers.chargerLimitW), so it must outlive the pass. Returns the watts put
--- in: the want, capped by the gas line. A generator bills them with what it powers
--- (Payers.billGenerators), so its fuel pays for them at its hour, and its window shows them.
--- Unloaded, only the grid carries on, until it shuts down.
function Bank:chargeFrom(generators, hours, roomWh)
    local generator
    if self:getSquare() then
        generator = not self.gridPowered and fueled(self, generators)
        self.chargeSource = (self.gridPowered and "grid") or (generator and keyOf(generator)) or false
    elseif not (self.chargeSource == "grid" and self.gridPowered) then
        self.chargeSource = false
    end
    local charging = self.chargeSource and roomWh > 0
    self.chargeWantW = charging and math.min(self:chargerMaxW(), roomWh / hours) or 0
    if not charging then
        return 0
    end
    return (generator and Payers.chargerLimitW(generator, self)) or self.chargeWantW
end

--- Whether the bank's chargers charge from `generator`. An older save's "generator" names none;
--- the bank's next pass names it.
function Bank:chargesFrom(generator)
    return self.chargeSource == keyOf(generator)
end

--- Whether the bank would carry its load now: it can, and no backup generator does it instead.
function Bank:carriesLoad()
    return self:canCarryLoad() and not self:backupCarriesLoad()
end

--- Cut the power while the load is beyond the inverters, and bring it back once it fits.
--- Returns whether an overload began.
function Bank:checkOverload()
    local wasOverloaded = self.overloaded
    if not self:carriesLoad() then
        self.overloaded = false
    else
        self.overloaded = self.loadW > self:limitW()
    end
    return self.overloaded and not wasOverloaded
end

--- Whether the bank should power its squares now.
function Bank:shouldPower()
    return self:canCarryLoad() and not self.overloaded and not self.empty
end

--- Run the bank's generator while the bank should; return whether activation changed. The caller
--- settles the bill (afterChange).
function Bank:switchGenerator()
    local generator = self:getIsoObject()
    if not generator then return false end
    local run = self:shouldPower()
    if generator:isActivated() ~= run then
        Fumes.setBankRunning(generator, run)
        return true
    elseif run then
        -- Chunks that loaded in reach since the last pass get their power here, which
        -- IsoGenerator.update does for generators it still processes.
        generator:setSurroundingElectricity()
    end
    return false
end

--- Reconcile a bank job's switch or parts mutation; the job site settles it (afterChange).
function Bank:powerUp()
    self.empty = false
    self:recount()
    -- The pass's room-limited demand stands, clamped to the hardware still present: a job may have
    -- taken chargers out, and integrating the pass's hours again here would count them twice.
    self.chargeWantW = self.nominalWh > 0 and math.min(self.chargeWantW or 0, self:chargerMaxW()) or 0
    self:measure()
    self:checkOverload()
    self:switchGenerator()
end

-- Follows the day's discharge cycle (Battery.trackCycle), the charge at midnight `midnight` closing
-- the day a pass crossed. A new day wears the batteries by the depth of yesterday's deepest
-- discharge: now, or while the bank is unloaded, when it next loads. Returns whether the day turned,
-- which starts the day's watt-hour totals again.
function Bank:trackCycle(container, midnight)
    local day = Battery.today()
    local finished
    self.cycleHigh, self.cycleDepth, finished = Battery.trackCycle(self.day, self.cycleHigh, self.cycleDepth,
        self.charge, day, midnight)
    if finished then
        if container then
            Battery.wearAll(container, finished)
        elseif finished > 0 then
            table.insert(self.pendingDepths, finished)
        end
        resetToday(self)
    end
    self.day = day
    return finished ~= nil
end

--- The watts the batteries give the inverters now.
function Bank:drawW()
    if not self:shouldPower() or self:backupCarriesLoad() then
        return 0
    end
    return self:inverterDrawW()
end

--- Brings the bank up to now: the hours since its last pass, at most PowerBank.LONGEST_PASS, in
--- the pass context `contextFor(hours)` gives (default: its system's passContext). Settles nothing.
function Bank:catchUp(contextFor)
    local hours = Clock.hoursSince(self, PowerBank.LONGEST_PASS)
    if hours > 0 then
        self:advance(hours, (contextFor or self.luaSystem.passContext)(hours))
    end
end

--- Bills the generators whose payers the bank's changes moved, shows its batteries and tells the
--- clients.
function Bank:afterChange()
    Payers.billGenerators()
    self:showBatteries()
    self:sendStatus()
end

--- One pass: `hours` of sun, load and charging up to now.
---@param context table see BankSystem.passContext
function Bank:advance(hours, context)
    local started = passLog.on and Telemetry.now()
    local container = self:container()
    self:lookIndoors()
    self:recount()

    local watts = self:updateSources(hours, context)
    local sourcesW = 0
    for _, w in pairs(watts) do
        sourcesW = sourcesW + w
    end
    self:updateGenerator()
    if self:getSquare() then
        self.gpbW = GpbBuildings.takeWatts(self, self:getIsoObject(), hours)
    end
    local generators = self:measure()
    if self:checkOverload() then
        self:addPartWear(container, 0, 1)
    end

    local drawW = self:drawW()
    -- While the bank is on, a running backup generator carries the load in its place.
    local backupW = (self:shouldPower() and self:backupCarriesLoad()) and self.loadW or 0
    local capacity = self.nominalWh
    local before = self.charge * capacity
    -- The chargers fill what the sources and the load leave; with no batteries there is nothing to fill.
    local roomWh = capacity > 0 and capacity - before - (sourcesW - drawW) * hours or 0
    local chargerW = self:chargeFrom(generators, hours, roomWh)
    local inW = sourcesW + chargerW
    local availableWh = before + inW * hours
    -- The pass's flows are steady, so the stored watt-hours run straight until the batteries fill or
    -- run out.
    local function storedAfter(passHours)
        return math.max(0, math.min(capacity, before + (inW - drawW) * passHours))
    end
    local stored = storedAfter(hours)
    self.charge = capacity > 0 and stored / capacity or 0
    local midnight = capacity > 0 and storedAfter(hours - Battery.hoursToday(hours)) / capacity or 0
    -- The share of the pass the batteries carried the load: all of it, or until they ran out.
    local carried = drawW > 0 and math.min(1, availableWh / (drawW * hours)) or 0
    -- An empty bank's inverters cut out, and come back once a pass of load is stored, so
    -- a bank that barely charges doesn't stop and start every pass.
    if drawW > 0 and stored <= 0 then
        self.empty = true
    elseif self.empty and stored > 0 and stored >= self:inverterDrawW() * hours then
        self.empty = false
    end
    local powering = self:shouldPower()
    if powering then
        self:addPartWear(container, hours, 0)
    end

    -- The day's totals take the pass's hours on the day it ends: after midnight, for a pass that
    -- crossed it. The batteries carried the load from the pass's start.
    local todayHours = self:trackCycle(container, midnight) and Battery.hoursToday(hours) or hours
    for _, family in ipairs(Sources.FAMILIES) do
        self[family.today] = (self[family.today] or 0) + watts[family.name] * todayHours
    end
    self.loadWhToday = self.loadWhToday + self.loadW * math.max(0, carried * hours - (hours - todayHours))
    self.backupWhToday = (self.backupWhToday or 0) + backupW * todayHours
    if container then
        self:writeBatteries(container, false)
        self:recount()
    end
    self:switchGenerator()

    self.now = { chargerW = chargerW, drawW = drawW, irradiance = context.irradiance("flat"), elevation = context.elevation,
        windKph = context.windKph }
    for _, family in ipairs(Sources.FAMILIES) do
        self.now[family.now] = watts[family.name]
    end
    if started then
        passLog:log("bank", self.x .. "," .. self.y .. "," .. self.z, "hour", Clock.now(), "hours", hours,
            "chargeBefore", capacity > 0 and before / capacity or 0, "chargeAfter", self.charge, "sourcesW", sourcesW,
            "chargerW", chargerW, "chargeSource", self.chargeSource, "loadW", self.loadW, "limitW", self:limitW(),
            "drawW", drawW, "backupW", backupW, "on", self.on, "overloaded", self.overloaded, "empty", self.empty,
            "powering", powering, "ms", Telemetry.now() - started)
    end
end

-- The bank's tile shows its batteries, each as its type, and its charge.
function Bank:showBatteries()
    local isoObject = self:getIsoObject()
    if not isoObject then return end
    -- recount reads the container from its last item, so this is the order they went in.
    local types = {}
    for i = #self.batteries, 1, -1 do
        table.insert(types, self.batteries[i].type)
    end
    Tiles.showOverlays(isoObject, Sprites.isOverlay, Sprites.bankOverlays(Sprites.nameOf(isoObject), types, self.charge))
end

return Bank
