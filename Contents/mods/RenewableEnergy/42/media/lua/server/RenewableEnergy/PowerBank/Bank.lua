-- One battery bank on the authority (single player or the server): its batteries, inverters,
-- chargers, controllers and sources, and the energy that moves between them each pass. Its backup
-- generator is Backup.lua's, and what it tells the clients BankStatus.lua's; both add to this class.
--
-- The table is the bank's global object (SGlobalObject), so every field in SAVED_FIELDS is saved
-- with the world and kept while the chunk is unloaded. While loaded, the container is the truth
-- about the parts and each battery's charge is the truth about the charge; while unloaded, the
-- snapshot in `batteries` and `charge` carries on, and it and the wear taken meanwhile are
-- written back into the parts when the chunk loads.

if isClient() then return end

require "Map/SGlobalObject"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/PlaceTracker"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/PanelSource"
require "RenewableEnergy/PowerBank/WindSource"
require "RenewableEnergy/PowerBank/TreadmillSource"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Payers"
require "RenewableEnergy/GasLine/GasLines"
require "RenewableEnergy/Fumes"
require "RenewableEnergy/PowerBank/Loads"
local Tiles = require "cf_commonlib/Tiles"

RenewableEnergy = RenewableEnergy or {}
local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites
local Battery, Wear, PowerBank, Sources = RenewableEnergy.Battery, RenewableEnergy.Wear, RenewableEnergy.PowerBank,
    RenewableEnergy.Sources
local Payers, PlaceTracker, Loads = RenewableEnergy.Payers, RenewableEnergy.PlaceTracker, RenewableEnergy.Loads

local Bank = SGlobalObject:derive("RenewableEnergy_Bank")
RenewableEnergy.Bank = Bank

-- The fields the Global Object System saves with the world; a field renamed here is lost from
-- existing saves.
Bank.SAVED_FIELDS = {
    "bankType", "name", "on", "overloaded", "indoors", "gridPowered", "charge", "nominalWh", "batteries",
    "inverters", "chargers", "controllers", "sources", "loadW", "loadByKind", "chargeSource", "chargeWantW",
    "generator", "lastHour", "day", "cycleHigh", "cycleDepth", "pendingDepths", "pendingPartWear",
    "solarWhToday", "loadWhToday", "empty", "windWhToday", "runWhToday", "backupWhToday", "connected",
}

-- How the bank runs each family of source (RenewableEnergy.Sources): connect(player, source,
-- isoObject, facing, material), if any, fills a newly connected source's record and teaches
-- `player` what connecting it first teaches; update(source, object, inSlot, hours, context) sets
-- its watts and reason for a pass; and status(entry, source), if any, adds to its status entry.
Bank.FAMILY = {
    panel = RenewableEnergy.PanelSource,
    wind = RenewableEnergy.WindSource,
    treadmill = RenewableEnergy.TreadmillSource,
}
-- Each family's watts now in the status, and its watt-hours today, saved; solarWhToday keeps its
-- older name because saves hold it.
Bank.TOTALS = {
    panel = { now = "solarW", today = "solarWhToday" },
    wind = { now = "windW", today = "windWhToday" },
    treadmill = { now = "runW", today = "runWhToday" },
}
local FAMILY, TOTALS = Bank.FAMILY, Bank.TOTALS

local function resetToday(bank)
    for _, total in pairs(TOTALS) do
        bank[total.today] = 0
    end
    bank.loadWhToday = 0
    bank.backupWhToday = 0
end

function Bank:initNew()
    self.on = false
    self.overloaded = false
    self.indoors = true
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
    self.chargeSource = false
    self.generator = false
    self.cycleHigh = 0
    self.cycleDepth = 0
    self.pendingDepths = {}
    self.pendingPartWear = { hours = 0, overloads = 0 }
    resetToday(self)
    self.empty = false
    self.lastHour = getGameTime():getWorldAgeHours()
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
    self.indoors = PowerBank.canPlaceBank(isoObject:getSquare())
    -- The truth is the generator's own connected flag; the record keeps it for while it's unloaded.
    self.connected = isoObject:isConnected()
    self:recount()
    self:switchGenerator()
    self:sendStatus()
end

--- Look at the container again, whatever filled or emptied it: the parts it holds, whether the
--- bank runs, the batteries on its tile and the status the clients see.
function Bank:refresh()
    self:recount()
    self:switchGenerator()
    self:showBatteries()
    self:sendStatus()
end

function Bank:spec()
    return Specs.banks[self.bankType]
end

--- The bank's container, or nil while its chunk is unloaded.
function Bank:container()
    local isoObject = self:getIsoObject()
    return isoObject and isoObject:getContainer()
end

local function partEntry(item)
    return { id = item:getID(), type = item:getFullType(), condition = item:getCondition() }
end

--- Read what the container holds into the bank's snapshot. Does nothing without one: a
--- bank whose container hasn't arrived isn't a bank holding nothing.
function Bank:recount()
    local container = self:container()
    if not container then return end
    local parts = {}
    for kind in pairs(PowerBank.PARTS) do
        parts[kind] = {}
    end
    local items = container:getItems()
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        local kind = PowerBank.partKind(item:getFullType())
        if kind then
            local entry = partEntry(item)
            if Battery.isBattery(item) then
                entry.nominalWh = Battery.nominalWh(item)
                -- The status window's repair hint depends on the repair limit.
                entry.repaired = item:getHaveBeenRepaired()
            end
            table.insert(parts[kind], entry)
        end
    end
    for kind, part in pairs(PowerBank.PARTS) do
        self[part.field] = parts[kind]
    end
    self.charge, self.nominalWh = Battery.containerCharge(container)
end

--- Put the bank's charge into every battery it holds: the batteries are wired in parallel,
--- so they share one state of charge. With `applyPending`, the battery wear the bank took while
--- unloaded lands too.
function Bank:writeBatteries(container, applyPending)
    local charged = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if Battery.isBattery(item) and item:getCondition() > 0 then
            -- Clients hear of the charge only once it changes at two decimals.
            if VehicleUtils.compareFloats(Battery.getCharge(item), self.charge, 2) then
                table.insert(charged, item)
            end
            Battery.setCharge(item, self.charge)
        end
    end
    -- After the charge, so that the batteries the wear sends carry it.
    local sent = {}
    if applyPending then
        for _, depth in ipairs(self.pendingDepths) do
            for item in pairs(Battery.wearAll(container, depth)) do
                sent[item] = true
            end
        end
        self.pendingDepths = {}
    end
    for _, item in ipairs(charged) do
        if not sent[item] then
            sendItemStats(item)
        end
    end
end

--- Whether a part in the bank's snapshot works; a broken one counts for nothing.
function Bank.isWorking(part)
    return part.condition > 0
end
local working = Bank.isWorking

-- The sum of Specs.inverters[type][field] over the bank's working inverters.
local function sumInverters(bank, field)
    local total = 0
    for _, inverter in ipairs(bank.inverters) do
        if working(inverter) then
            total = total + Specs.inverters[inverter.type][field]
        end
    end
    return total
end

--- The watts the bank's working inverters carry together.
function Bank:limitW()
    return sumInverters(self, "watts")
end

--- The watts the bank's working chargers, and the chargers built into its inverters, put in
--- while grid or generator power reaches it.
function Bank:chargerMaxW()
    local watts = sumInverters(self, "chargerWatts")
    for _, charger in ipairs(self.chargers) do
        if working(charger) then
            watts = watts + Specs.chargerWatts
        end
    end
    return watts
end

--- How many input slots the bank has: a few on their own, and more for each working controller.
function Bank:inputSlots()
    local slots = Specs.freeSlots
    for _, controller in ipairs(self.controllers) do
        if working(controller) then
            slots = slots + Specs.slotsPerController
        end
    end
    return slots
end

--- The input slots its sources take.
function Bank:slotsUsed()
    local used = 0
    for _, source in ipairs(self.sources) do
        used = used + Sources.slotsOf(source.kind)
    end
    return used
end

-- Inverters and controllers wear while they work, and an overload strains the inverters
-- (Specs.partWear); a homemade inverter by its own `wear` share.
function Bank:wearParts(container, hours, overloads)
    local wear = Specs.partWear
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fullType = item:getFullType()
        local kind = PowerBank.partKind(fullType)
        local inverter = Specs.inverters[fullType]
        local scale = inverter and inverter.wear or 1
        local points = kind and scale * ((wear.perHour[kind] or 0) * hours + (wear.perOverload[kind] or 0) * overloads) or 0
        if Wear.take(item, points) then
            sendItemStats(item)
        end
    end
end

-- Wear now if the parts are at hand, else when the chunk next loads.
function Bank:addPartWear(container, hours, overloads)
    if container then
        self:wearParts(container, hours, overloads)
    else
        self.pendingPartWear.hours = self.pendingPartWear.hours + hours
        self.pendingPartWear.overloads = self.pendingPartWear.overloads + overloads
    end
end

function Bank:applyPendingPartWear(container)
    local pending = self.pendingPartWear
    self:wearParts(container, pending.hours, pending.overloads)
    self.pendingPartWear = { hours = 0, overloads = 0 }
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
    local connect = FAMILY[Sources.familyOf(kind)].connect
    if connect then
        connect(player, source, isoObject, facing, material)
    end
    table.insert(self.sources, source)
end

-- Takes the source at `index` off the bank. What it still owed the bank, a treadmill run not yet
-- paid out (TreadmillSource.credit), goes into the batteries now, up to full, so taking a source
-- away forfeits nothing it made.
local function dropSource(bank, index)
    local source = table.remove(bank.sources, index)
    local wh = source.pendingWh
    if wh and bank.nominalWh > 0 then
        bank.charge = math.min(1, bank.charge + wh / bank.nominalWh)
        local today = TOTALS[Sources.familyOf(source.kind)].today
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
        dropSource(self, index)
        return true
    end
    return false
end

--- Every source's output over the pass, as watts by family (TOTALS). A source whose square is
--- loaded is checked for still being there, where its kind works and in reach; one that is gone
--- is dropped. Each source takes its slots if they fit in what the sources before it in the
--- list left free; one that doesn't fit stays wired and makes nothing.
function Bank:updateSources(hours, context)
    local watts, slots, used = {}, self:inputSlots(), 0
    for family in pairs(TOTALS) do
        watts[family] = 0
    end
    -- A dropped source gives its place in the list, and so its slots, to the next one.
    local i = 1
    while i <= #self.sources do
        local source = self.sources[i]
        local square = getSquare(source.x, source.y, source.z)
        local object = Sources.findOn(square)
        if square and not (object and Sources.squareOk(square, source.kind)
            and PowerBank.isInReach(self, source.x, source.y, source.z)) then
            dropSource(self, i)
        else
            local size = Sources.slotsOf(source.kind)
            local inSlot = used + size <= slots
            if inSlot then
                used = used + size
            end
            local family = Sources.familyOf(source.kind)
            FAMILY[family].update(source, object, inSlot, hours, context)
            watts[family] = watts[family] + source.watts
            i = i + 1
        end
    end
    return watts
end

--- Whether the bank can carry its load: connected, switched on, indoors, with a working inverter
--- and batteries that can hold a charge, and off the grid. `connected` is nil on banks saved before
--- it was recorded, and those were all connected.
function Bank:canCarryLoad()
    return self.connected ~= false and self.on and self.indoors and self:limitW() > 0 and self.nominalWh > 0
        and not self.gridPowered
end

--- Measure what the bank pays for, and whether the grid powers its square. The load counts what is
--- switched on in its reach even while the grid powers it, so a bank unloaded when the grid goes
--- carries what was on. Unloaded, the last measurement stands until the grid shuts down. A bank
--- that is off with no charger skips the scan. Returns the running generators that reach the bank.
function Bank:measure()
    local square = self:getSquare()
    if not square then
        self.gridPowered = self.gridPowered and getSandboxOptions():doesPowerGridExist()
        return {}
    end
    self.gridPowered = square:hasGridPower()
    local load = (self.on or self:chargerMaxW() > 0) and Loads.scan(square, Payers.ofBank(self), Payers.running(), true)
        or Loads.new()
    self.loadW = load.watts
    self.loadByKind = Loads.byKind(load)
    return load.generators
end

local function hasFuel(generator)
    return generator:getFuel() > 0
end

-- The nearest of `generators` with fuel to `bank` (PlaceTracker.nearest).
local function fueled(bank, generators)
    return PlaceTracker.nearest(generators, bank.x, bank.y, bank.z, PlaceTracker.objectPlace, hasFuel)
end

-- The place key of `generator`, as chargeSource names a charging generator.
local function keyOf(generator)
    return PlaceTracker.key(PlaceTracker.objectPlace(generator))
end

--- What the chargers charge from, saved as `chargeSource`: "grid", the place key (keyOf) of the
--- nearest fueled running generator whose reach covers the bank, or false. Saves as `chargeWantW`
--- their watts, capped so they fill no more than `roomWh` over `hours`: a gas line splits its
--- cap by these wants (GasLines.chargerLimitW), so it must outlive the pass. Returns the watts put
--- in: the want, capped by the gas line. A generator bills them with what it powers
--- (Payers.billGenerators), so its fuel pays for them at its hour, and its window shows them.
--- Unloaded, only the grid carries on, until it shuts down.
function Bank:chargeFrom(generators, hours, roomWh)
    local generator
    local wasSource, wasWantW = self.chargeSource, self.chargeWantW
    if self:getSquare() then
        generator = not self.gridPowered and fueled(self, generators)
        self.chargeSource = (self.gridPowered and "grid") or (generator and keyOf(generator)) or false
    elseif not (self.chargeSource == "grid" and self.gridPowered) then
        self.chargeSource = false
    end
    local charging = self.chargeSource and roomWh > 0
    self.chargeWantW = charging and math.min(self:chargerMaxW(), roomWh / hours) or 0
    if self.chargeSource ~= wasSource or math.abs(self.chargeWantW - (wasWantW or 0)) > 0.01 then
        Payers.billGenerators()
    end
    if not charging then
        return 0
    end
    local watts = self.chargeWantW
    if generator then
        watts = math.min(watts, RenewableEnergy.GasLines.chargerLimitW(generator, self) or watts)
    end
    return watts
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

--- Run the bank's generator, which is what powers the squares, while the bank should.
function Bank:switchGenerator()
    local generator = self:getIsoObject()
    if not generator then return end
    local run = self:shouldPower()
    if generator:isActivated() ~= run then
        -- setActivated sets the building toxic as a fuel generator's exhaust would
        -- (IsoGenerator.setActivated); a bank has no exhaust, so the building keeps its state.
        local building = RenewableEnergy.Fumes.buildingOf(generator:getSquare())
        local wasToxic = building and building:isToxic()
        generator:setActivated(run)
        if building and building:isToxic() ~= wasToxic then
            building:setToxic(wasToxic)
        end
        -- The generators sharing its reach pay for more or less now.
        Payers.billGenerators()
    elseif run then
        -- Chunks that loaded in reach since the last pass get their power here, which
        -- IsoGenerator.update does for generators it still processes.
        generator:setSurroundingElectricity()
    end
end

--- The player's switch, or parts wired in or out: look at the load again now.
function Bank:powerUp()
    self.empty = false
    self:recount()
    self:measure()
    self:checkOverload()
    self:switchGenerator()
end

-- Follows the day's discharge cycle (Battery.trackCycle). A new day wears the batteries by the
-- depth of yesterday's deepest discharge: now, or while the bank is unloaded, when it next loads.
function Bank:trackCycle(container)
    local day, finished = Battery.today()
    self.cycleHigh, self.cycleDepth, finished = Battery.trackCycle(self.day, self.cycleHigh, self.cycleDepth,
        self.charge, day)
    if finished then
        if container then
            Battery.wearAll(container, finished)
        elseif finished > 0 then
            table.insert(self.pendingDepths, finished)
        end
        resetToday(self)
    end
    self.day = day
end

-- The watts the inverters take from the batteries to carry the load and run themselves. Working
-- inverters share the load in proportion to what each carries, and each wastes its own share of
-- its part.
local function inverterDrawW(bank)
    local carried, drawn = 0, 0
    for _, inverter in ipairs(bank.inverters) do
        if working(inverter) then
            local spec = Specs.inverters[inverter.type]
            carried = carried + spec.watts
            drawn = drawn + spec.watts / spec.efficiency
        end
    end
    local loadDrawW = carried > 0 and bank.loadW * drawn / carried or 0
    return loadDrawW + sumInverters(bank, "idle")
end

--- The watts the batteries give the inverters now.
function Bank:drawW()
    if not self:shouldPower() or self:backupCarriesLoad() then
        return 0
    end
    return inverterDrawW(self)
end

--- One pass: `hours` of sun, load and charging up to now.
---@param context table see BankSystem.passContext
function Bank:update(hours, context)
    local container = self:container()
    self:recount()

    local watts = self:updateSources(hours, context)
    local sourcesW = 0
    for _, w in pairs(watts) do
        sourcesW = sourcesW + w
    end
    self:updateGenerator()
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
    local stored = math.max(0, math.min(capacity, availableWh - drawW * hours))
    self.charge = capacity > 0 and stored / capacity or 0
    -- The share of the pass the batteries carried the load: all of it, or until they ran out.
    local carried = drawW > 0 and math.min(1, availableWh / (drawW * hours)) or 0
    -- An empty bank's inverters cut out, and come back once a pass of load is stored, so
    -- a bank that barely charges doesn't stop and start every pass.
    if drawW > 0 and stored <= 0 then
        self.empty = true
    elseif self.empty and stored > 0 and stored >= inverterDrawW(self) * hours then
        self.empty = false
    end
    local powering = self:shouldPower()
    if powering then
        self:addPartWear(container, hours, 0)
    end

    for family, total in pairs(TOTALS) do
        self[total.today] = (self[total.today] or 0) + watts[family] * hours
    end
    self.loadWhToday = self.loadWhToday + self.loadW * hours * carried
    self.backupWhToday = (self.backupWhToday or 0) + backupW * hours
    self:trackCycle(container)
    if container then
        self:writeBatteries(container, false)
        self:recount()
    end
    self:switchGenerator()
    self:showBatteries()

    self.now = { chargerW = chargerW, drawW = drawW, irradiance = context.irradiance("flat"), elevation = context.elevation,
        windKph = context.windKph }
    for family, total in pairs(TOTALS) do
        self.now[total.now] = watts[family]
    end
    self:sendStatus()
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
