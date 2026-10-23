-- One digester on the authority: what it holds, how warm it is, the gas it makes and stores, its
-- sludge and souring, and the stink and fumes that come of them.
--
-- It keeps working while its chunk is unloaded. While loaded its hopper is the truth about the feed;
-- while unloaded it eats from a snapshot (`hopper`), and what it ate (`eaten`) leaves the hopper when
-- the chunk loads again. Likewise `heaterLit` carries the heater's lit tile through unloaded passes.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/ObjectSystem"
require "RenewableEnergy/Fumes"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/Stink"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/GasLine/GasKit"

RenewableEnergy = RenewableEnergy or {}
local Digester, Stink, Sprites = RenewableEnergy.Digester, RenewableEnergy.Stink, RenewableEnergy.Sprites
local GasHeater, GasKit, Fumes = RenewableEnergy.GasHeater, RenewableEnergy.GasKit, RenewableEnergy.Fumes

local DigesterObject = RenewableEnergy.ObjectSystem.Object:derive("RenewableEnergy_Digester")
RenewableEnergy.DigesterObject = DigesterObject

-- The fields the Global Object System saves with the world; a field renamed here is lost from
-- existing saves.
DigesterObject.SAVED_FIELDS = {
    "tier", "holder", "holderCondition", "potential", "gas", "temp", "fed", "startupHours",
    "seedHours", "started", "gasHours", "sludge", "acid", "sour", "leakHours", "indoors", "inRoom",
    "meterHours", "madePerDay", "hopper", "eaten", "lastHour", "scrubber", "scrubCO2", "scrubWool",
    "heaterLit",
}

-- Sour slows digestion to this share.
local SOUR_K = 0.15
-- Acid decays by this share a day. Alkali banked beyond the souring limit (Digester.ACID_LIMIT)
-- below zero is lost.
local ACID_DECAY_PER_DAY = 0.1
-- Sludge, in percent, that each m³ of potential fed adds, for a digester holding 1 m³; bigger ones
-- fill slower in proportion, so each tier needs emptying about weekly when fed to its cap.
local SLUDGE_PER_POTENTIAL = 35
-- Air below this outdoors is held in by the dome's earth (ground temperature).
local GROUND_TEMP = 12
-- What a room does to the outdoor temperature while its chunk is unloaded, as
-- ClimateManager.getAirTemperatureForSquare does for a ground floor room at an average daylight:
-- pulls it toward ROOM_TEMP.
local ROOM_TEMP = 22
local ROOM_PULL_COLD, ROOM_PULL_HOT = 0.5, 0.425
-- The made-per-day figure follows the last few hours.
local RATE_HOURS = 6

function DigesterObject:initNew()
    self.holderCondition = 100
    self.potential = 0
    self.gas = 0
    self.fed = false
    self.startupHours = 0
    self.seedHours = 0
    self.started = false
    self.gasHours = 0
    self.sludge = 0
    self.acid = 0
    self.sour = false
    self.leakHours = 0
    self.meterHours = 0
    self.madePerDay = 0
    self.hopper = {}
    self.eaten = {}
    self.scrubber = false
    self.scrubCO2 = 0
    self.scrubWool = 0
    self.heaterLit = false
    self.lastHour = getGameTime():getWorldAgeHours()
end

--- An object the system has not seen: a digester just built.
function DigesterObject:stateFromIsoObject(isoObject)
    self:initNew()
    self.tier = Digester.tierOf(isoObject)
    self.holder = self:tierSpec().holder
    self.temp = getClimateManager():getAirTemperatureForSquare(isoObject:getSquare())
    self:loaded(isoObject)
end

--- The digester's chunk loaded: what it ate meanwhile leaves the hopper.
function DigesterObject:stateToIsoObject(isoObject)
    local container = isoObject:getContainer()
    if container then
        self:takeEaten(container)
    end
    self:loaded(isoObject)
end

function DigesterObject:loaded(isoObject)
    local square = isoObject:getSquare()
    self.indoors = Fumes.buildingOf(square) ~= nil
    self.inRoom = square:isInARoom()
    Digester.adoptContainer(isoObject:getContainer())
    self:snapshotHopper(isoObject:getContainer())
    self:show()
    self:sendSummary()
end

-- Its stink goes, and the heater it fed goes out; a tile picked up or destroyed is still on its
-- square here (OnObjectAboutToBeRemoved).
function DigesterObject:aboutToRemoveFromSystem()
    Stink.clear(self:key())
    local isoObject = self:getIsoObject()
    local heater = isoObject and GasHeater.litHeaterFor(isoObject)
    if heater then
        DigesterObject.showHeaterLit(heater, false)
    end
    RenewableEnergy.ObjectSystem.Object.aboutToRemoveFromSystem(self)
end

--- The gas the holder stores, nothing once torn.
function DigesterObject:capacity()
    if self:isTorn() then
        return 0
    end
    return Digester.HOLDERS[self.holder].capacity
end

function DigesterObject:isTorn()
    return Digester.HOLDERS[self.holder].wearPerDay ~= nil and self.holderCondition <= 0
end

function DigesterObject:acidLimit()
    return Digester.ACID_LIMIT * self:tierSpec().potentialCap
end

-- The hopper's feed as plain values the digester can eat from while its chunk is unloaded, in the
-- order it eats them.
function DigesterObject:snapshotHopper(container)
    local hopper = {}
    local items = container and container:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        local item = items:get(i)
        local feed = Digester.feedOf(item)
        if feed then
            feed.id = item:getID()
            feed.uses = not feed.whole and item:getCurrentUses() or nil
            table.insert(hopper, feed)
        end
    end
    self.hopper = hopper
end

-- The next feed to eat: an alkali first while there is acid to take, else the first feed while
-- there is room. Returns its index in `entries`, or nil.
function DigesterObject:pickFeed(entries)
    local wantsAlkali = self.acid > 0
    local room = self.potential < self:tierSpec().potentialCap
    for i, entry in ipairs(entries) do
        if entry.neutraliser then
            if wantsAlkali then
                return i
            end
        elseif room then
            return i
        end
    end
    return nil
end

function DigesterObject:eat(feed)
    self.potential = self.potential + feed.potential
    self.acid = math.max(-self:acidLimit(), self.acid + feed.acid)
    if feed.potential > 0 then
        self.fed = true
        self.sludge = math.min(100, self.sludge + feed.potential * SLUDGE_PER_POTENTIAL / self:tierSpec().potentialCap)
    end
    if not self.started and feed.seedHours then
        self.seedHours = self.seedHours + feed.seedHours
    end
end

-- Takes one feed out of the loaded hopper. Returns whether there was one to take.
function DigesterObject:feedFromContainer(container)
    local items, entries = {}, {}
    local list = container:getItems()
    for i = 0, list:size() - 1 do
        local item = list:get(i)
        local feed = Digester.feedOf(item)
        if feed then
            table.insert(items, item)
            table.insert(entries, feed)
        end
    end
    local index = self:pickFeed(entries)
    if not index then
        return false
    end
    local item, feed = items[index], entries[index]
    if feed.whole or item:getCurrentUses() <= 1 then
        RenewableEnergy.removeItem(item)
    else
        item:setCurrentUses(item:getCurrentUses() - 1)
        sendItemStats(item)
    end
    self:eat(feed)
    return true
end

-- The same from the snapshot, while the chunk is unloaded; what it eats is taken from the hopper
-- when the chunk loads.
function DigesterObject:feedFromSnapshot()
    local index = self:pickFeed(self.hopper)
    if not index then
        return false
    end
    local entry = self.hopper[index]
    self:eat(entry)
    if entry.uses and entry.uses > 1 then
        entry.uses = entry.uses - 1
        self.eaten[tostring(entry.id)] = (self.eaten[tostring(entry.id)] or 0) + 1
    else
        table.remove(self.hopper, index)
        self.eaten[tostring(entry.id)] = "all"
    end
    return true
end

function DigesterObject:takeEaten(container)
    for id, eaten in pairs(self.eaten) do
        local item = container:getItemWithID(tonumber(id))
        if item then
            local left = eaten ~= "all" and item:getCurrentUses() - eaten or 0
            if left > 0 then
                item:setCurrentUses(left)
                sendItemStats(item)
            else
                RenewableEnergy.removeItem(item)
            end
        end
    end
    self.eaten = {}
end

-- One feed an hour goes in, from the hopper while loaded or from its snapshot while not.
function DigesterObject:meter(hours, container)
    self.meterHours = self.meterHours + hours
    while self.meterHours >= 1 do
        self.meterHours = self.meterHours - 1
        if container then
            self:feedFromContainer(container)
        else
            self:feedFromSnapshot()
        end
    end
end

local function kAt(temp)
    local points = Digester.K_BY_TEMP
    if temp <= points[1][1] or temp >= points[#points][1] then
        return 0
    end
    for i = 2, #points do
        local hi = points[i]
        if temp <= hi[1] then
            local lo = points[i - 1]
            return lo[2] + (hi[2] - lo[2]) * (temp - lo[1]) / (hi[1] - lo[1])
        end
    end
    return 0
end

-- The air the digester sits in: its square's while loaded (rooms and heat sources included), else
-- the outdoor air, pulled toward a room's as the game pulls it.
function DigesterObject:airTemp(square)
    local climate = getClimateManager()
    if square then
        return climate:getAirTemperatureForSquare(square)
    end
    local temp = climate:getTemperature()
    if self.inRoom then
        if temp <= ROOM_TEMP then
            temp = temp + (ROOM_TEMP - temp) * ROOM_PULL_COLD
        else
            temp = temp - (temp - ROOM_TEMP) * ROOM_PULL_HOT
        end
    end
    return temp
end

-- The temperature the digester heads for, and whether it burns gas to get there: a lit heater, or
-- the dome's own burner, which a lit heater stands in for.
function DigesterObject:targetTemp(air)
    local spec = self:tierSpec()
    local target, burning = air, false
    if spec.warmTo then
        target = math.max(air, GROUND_TEMP)
        if self.started and self.gas > 0 and target < spec.warmTo then
            target, burning = spec.warmTo, true
        end
    end
    if self.heaterLit then
        target, burning = math.max(target, GasHeater.TEMP), true
    end
    return target, burning
end

function DigesterObject:startupNeeded()
    return getSandboxOptions():getCompostHours()
end

function DigesterObject:startupProgress()
    local needed = self:startupNeeded()
    local seeded = math.min(self.seedHours, needed * Digester.SEED_SHARE)
    return math.min(1, (self.startupHours + seeded) / needed)
end

-- Runs `hours` (at most one) of digestion at the air temperature `air`.
function DigesterObject:step(hours, air)
    local spec = self:tierSpec()
    local target, heating = self:targetTemp(air)
    self.temp = self.temp + (target - self.temp) * (1 - math.exp(-hours / (spec.days * 24)))

    local made = 0
    if not self.started then
        if self.fed and self.temp >= Digester.STARTUP_MIN_TEMP then
            self.startupHours = self.startupHours + hours
        end
        self.started = self:startupProgress() >= 1
    else
        self.gasHours = self.gasHours + hours
        local k = kAt(self.temp) * (self.sour and SOUR_K or 1)
            * (self.sludge > Digester.SLUDGE_SLOW and Digester.SLUDGE_K or 1)
        local digested = self.potential * (1 - math.exp(-k * hours / 24))
        self.potential = self.potential - digested
        made = digested * SandboxVars.RenewableEnergy.BiogasMultiplier
    end
    self.gas = self.gas + made
    self.madePerDay = self.madePerDay + (made * 24 / hours - self.madePerDay) * (1 - math.exp(-hours / RATE_HOURS))

    self.acid = self.acid * math.exp(-ACID_DECAY_PER_DAY * hours / 24)
    local limit = self:acidLimit()
    if self.acid > limit then
        self.sour = true
    elseif self.acid < limit * Digester.ACID_RECOVER then
        self.sour = false
    end

    local holder = Digester.HOLDERS[self.holder]
    if holder.wearPerDay and self.holderCondition > 0 then
        self.holderCondition = math.max(0, self.holderCondition - holder.wearPerDay * hours / 24)
    end
    self.leakHours = math.max(0, self.leakHours - hours)
    if heating then
        -- Short of the pass's burning, a heater goes out and the dome burns what is left.
        local burn = GasHeater.m3PerHour() * hours
        if self.gas >= burn then
            self.gas = self.gas - burn
        elseif self.heaterLit then
            self.heaterLit = false
        else
            self.gas = 0
        end
    end
    local capacity = self:capacity()
    if self.gas > capacity then
        self.gas = capacity
        if self.indoors then
            self.leakHours = Digester.LEAK_HOURS
        end
    end
end

--- Runs `hours` of the digester, an hour at a time, at the air temperature `air`: feeding from
--- `container` (its loaded hopper, or nil for the snapshot) and digesting, then snapshots the
--- hopper.
function DigesterObject:run(hours, container, air)
    while hours > 0 do
        local step = math.min(1, hours)
        self:meter(step, container)
        self:step(step, air)
        hours = hours - step
    end
    if container then
        self:snapshotHopper(container)
    end
end

--- Runs the `hours` since it last caught up, in its square's air while loaded. A loaded digester's
--- heater counts as its tile shows.
function DigesterObject:advance(hours)
    if hours <= 0 then
        return
    end
    local isoObject = self:getIsoObject()
    if isoObject then
        self.heaterLit = GasHeater.litHeaterFor(isoObject) ~= nil
    end
    self:run(hours, isoObject and isoObject:getContainer(), self:airTemp(isoObject and isoObject:getSquare()))
end

--- Shows and tells what changed, after a pass or a job.
function DigesterObject:afterChange()
    Stink.set(self:key(), self.x, self.y, self.z, DigesterObject.corpsesFor(self:stinkScore()))
    self:setFuming(self:fuming())
    self:show()
    self:sendSummary()
end

-- Startup stinks most at its middle; a working digester settles down over its first weeks of gas.
local STARTUP_STINK, STARTUP_PEAK = 1.0, 0.5
local YOUNG_STINK, MATURE_STINK, MATURE_HOURS = 0.8, 0.4, 14 * 24
local SLUDGE_STINK, SOUR_STINK = 0.8, 1.5
-- A part-filled digester stinks less than a full one.
local EMPTY_SHARE = 0.5

--- The stink score: below the first of Digester.SMELL_SCORES none, then each score starts the
--- next smell level.
function DigesterObject:stinkScore()
    if not self.fed then
        return 0
    end
    local score
    if not self.started then
        score = STARTUP_STINK + STARTUP_PEAK * math.sin(math.pi * self:startupProgress())
    else
        local mature = math.min(1, self.gasHours / MATURE_HOURS)
        score = YOUNG_STINK + (MATURE_STINK - YOUNG_STINK) * mature
    end
    score = score + SLUDGE_STINK * self.sludge / 100 + (self.sour and SOUR_STINK or 0)
    local spec = self:tierSpec()
    local fill = math.min(1, self.potential / spec.potentialCap)
    score = score * spec.stink * (EMPTY_SHARE + (1 - EMPTY_SHARE) * fill) * (self.indoors and 2 or 1)
    return spec.stinkCap and math.min(score, spec.stinkCap) or score
end

--- The corpses the stink score smells like: none below the first smell level's score
--- (Digester.SMELL_SCORES), then rising through each level's corpses (Stink.LEVEL_CORPSES).
function DigesterObject.corpsesFor(score)
    local scores, corpses = Digester.SMELL_SCORES, Stink.LEVEL_CORPSES
    if score < scores[1] then
        return 0
    end
    for level = 1, #scores - 1 do
        if score < scores[level + 1] then
            local share = (score - scores[level]) / (scores[level + 1] - scores[level])
            return corpses[level] + math.floor(share * (corpses[level + 1] - corpses[level]))
        end
    end
    return corpses[#corpses]
end

--- Whether the digester fills its building with fumes: badly sour or leaking, indoors, unless it
--- is sealed.
function DigesterObject:fuming()
    return self.indoors and not self:tierSpec().sealed and (self.sour or self.leakHours > 0)
end

local showOverlay = RenewableEnergy.showOverlay

--- Lights or puts out `heater`, by its tile.
function DigesterObject.showHeaterLit(heater, lit)
    if GasHeater.isLit(heater) == lit then return end
    RenewableEnergy.showTile(heater, lit and Sprites.gasHeater.lit or Sprites.gasHeater.off)
end

--- Lights or puts out `heater`, the one that warms this digester (GasHeater.digesterNear).
function DigesterObject:setHeaterLit(heater, lit)
    self.heaterLit = lit
    DigesterObject.showHeaterLit(heater, lit)
end

-- The holder's fill, the scrubber, and a heater put out once the digester stops feeding it: out
-- of gas, here or while its chunk was unloaded.
function DigesterObject:show()
    local isoObject = self:getIsoObject()
    if not isoObject then return end
    local capacity = Digester.HOLDERS[self.holder].capacity
    showOverlay(isoObject, Digester.isHolderOverlay, Digester.holderOverlay(self.holder, self.gas / capacity, self:isTorn()))
    showOverlay(isoObject, Digester.isScrubberOverlay, self.scrubber and Sprites.digesterScrubber[self.tier] or nil)
    if not self.heaterLit then
        local heater = GasHeater.litHeaterFor(isoObject)
        if heater then
            DigesterObject.showHeaterLit(heater, false)
        end
    end
end

--- Makes it the tier its Upgrade makes of it (Digester.TIERS), with that tier's new holder: its
--- tile and entity, and the bigger hopper of the tile's ContainerCapacity, which a multiplayer
--- client gets only with the containers.
function DigesterObject:upgrade(isoObject)
    self.tier = self:tierSpec().upgrade
    self.holder = self:tierSpec().holder
    self.holderCondition = 100
    self.gas = math.min(self.gas, self:capacity())
    RenewableEnergy.setEntityTile(isoObject, Sprites.digester[self.tier])
    local container = isoObject:getContainer()
    if container then
        container:setCapacity(tonumber(isoObject:getProperties():get("ContainerCapacity")) or container:getCapacity())
    end
    isoObject:transmitUpdatedSpriteToClients()
    -- After the tile: a client's SpriteConfig checks its new script against the tile it shows.
    -- Single player has no other copy, and there sendObjectChange loops back to this one
    -- (SinglePlayerServer).
    if isServer() then
        isoObject:sendSyncEntity(nil)
        isoObject:sendObjectChange(IsoObjectChange.CONTAINERS)
    end
end

--- Takes up to `m3` of gas out of the holder. Returns what it took.
function DigesterObject:takeGas(m3)
    local taken = math.min(m3, self.gas)
    self.gas = self.gas - taken
    return taken
end

-- Below this the holder is too little to run a generator on.
local MIN_GAS = 0.01

function DigesterObject:canSupply()
    return self.gas >= MIN_GAS
end

function DigesterObject:capW()
    return GasKit.CAP_W
end

function DigesterObject:wearFactor()
    return 1
end

--- Gives the gas for `litres` of petrol the generator was billed. Returns whether there was enough.
function DigesterObject:supply(litres)
    local need = GasKit.M3_PER_LITRE * litres
    return self:takeGas(need) + 1e-4 >= need
end

--- What every client keeps of the digester: what its menu checks and its status window shows,
--- rounded so a pass that changes little sends nothing. Digester's accessors add what its hopper
--- holds.
function DigesterObject:buildSummary()
    local spec = self:tierSpec()
    return {
        tier = self.tier, holder = self.holder,
        holderCondition = round(self.holderCondition), torn = self:isTorn(),
        gas = round(self.gas, 2), capacity = self:capacity(),
        temp = round(self.temp),
        fed = self.fed, started = self.started, startup = round(self:startupProgress(), 2),
        sludge = math.floor(self.sludge), sour = self.sour, leaking = self.leakHours > 0,
        fill = round(math.min(1, self.potential / spec.potentialCap), 2),
        madePerDay = round(self.madePerDay, 2),
        stink = round(self:stinkScore(), 1),
        scrubber = self.scrubber == true,
        scrubCO2 = round(self.scrubCO2 or 0, 1),
        scrubWool = round(self.scrubWool or 0, 1),
        heaterLit = self.heaterLit == true,
    }
end

return DigesterObject
