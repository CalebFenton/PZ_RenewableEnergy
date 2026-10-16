-- One digester on the authority (single player or the server): what it holds, how warm it is, the
-- gas it makes and stores, its sludge and souring, and the stink and fumes that come of them.
--
-- The table is the digester's global object (SGlobalObject), so every field in SAVED_FIELDS is
-- saved with the world and the digester keeps working while its chunk is unloaded. While loaded
-- its hopper is the truth about the feed; while unloaded it eats from a snapshot of the hopper
-- (`hopper`), and what it ate (`eaten`) leaves the hopper when the chunk loads again.

if isClient() then return end

require "Map/SGlobalObject"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/Stink"

RenewableEnergy = RenewableEnergy or {}
local Digester, Stink = RenewableEnergy.Digester, RenewableEnergy.Stink

local DigesterObject = SGlobalObject:derive("RenewableEnergy_Digester")
RenewableEnergy.DigesterObject = DigesterObject

-- The fields the Global Object System saves with the world; a field renamed here is lost from
-- existing saves.
DigesterObject.SAVED_FIELDS = {
    "tier", "material", "holder", "holderCondition", "potential", "gas", "temp", "fed", "startupHours",
    "seedHours", "started", "gasHours", "sludge", "acid", "sour", "leakHours", "indoors", "inRoom",
    "meterHours", "madePerDay", "hopper", "eaten", "lastHour",
}

-- Digestion rate k (share of the undigested potential a day) by temperature, between which it runs
-- in straight lines: nothing below 10 °C, the mesophilic best at 35 to 40, falling off above.
local K_BY_TEMP = { { 10, 0 }, { 15, 0.01 }, { 25, 1 / 30 }, { 35, 1 / 15 }, { 40, 1 / 15 }, { 50, 0 } }
-- Sour slows digestion to this share; sludge past SLUDGE_SLOW halves it.
local SOUR_K = 0.15
local SLUDGE_SLOW, SLUDGE_K = 80, 0.5
-- Startup counts only hours this warm, and manure's head start covers at most this share of it.
local STARTUP_MIN_TEMP = 10
local SEED_SHARE = 0.7
-- The souring buffer: acid decays by this share a day, and a digester sours above its limit
-- (ACID_LIMIT per unit of potentialCap) and recovers below half of it. Alkali banked beyond the
-- limit below zero is lost.
local ACID_DECAY_PER_DAY = 0.1
local ACID_LIMIT = 0.8
-- Sludge, in percent, that each m³ of potential fed adds, for a digester holding 1 m³; bigger ones
-- fill slower in proportion, so each tier needs emptying about weekly when fed to its cap.
local SLUDGE_PER_POTENTIAL = 35
-- A holder that vents indoors leaks for this many hours.
local LEAK_HOURS = 2
-- Air below this outdoors is held in by the dome's earth (ground temperature).
local GROUND_TEMP = 12
-- What a room does to the outdoor temperature while its chunk is unloaded, as
-- ClimateManager.getAirTemperatureForSquare does for a ground floor room at an average daylight.
local ROOM_PULL_COLD, ROOM_PULL_HOT = 0.5, 0.425
-- The made-per-day figure follows the last few hours.
local RATE_HOURS = 6
-- A pass longer than this (a save loaded after the clock jumped) counts as this long.
local LONGEST_PASS = 24 * 7

function DigesterObject:new(luaSystem, globalObject)
    return SGlobalObject.new(self, luaSystem, globalObject)
end

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
    self.lastHour = getGameTime():getWorldAgeHours()
end

--- An object the system has not seen: a digester just built.
function DigesterObject:stateFromIsoObject(isoObject)
    self:initNew()
    local tile = Digester.tileOf(isoObject)
    self.tier, self.material = tile.tier, tile.material
    self.holder = Digester.HOLDER_OF_TIER[self.tier] or "bags"
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
    self.indoors = square:getBuilding() ~= nil and not square:isOutside()
    self.inRoom = square:isInARoom()
    Digester.adoptContainer(isoObject:getContainer())
    self:snapshotHopper(isoObject:getContainer())
    self:showHolder()
    self:sendSummary()
end

function DigesterObject:tierSpec()
    return Digester.TIERS[self.tier]
end

function DigesterObject:key()
    return "digester:" .. self.x .. "," .. self.y .. "," .. self.z
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
    return ACID_LIMIT * self:tierSpec().potentialCap
end

-- Feed ----------------------------------------------------------------------------------------

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
            feed.neutraliser = Digester.isNeutraliser(item)
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
            feed.neutraliser = Digester.isNeutraliser(item)
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
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
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
                container:Remove(item)
                sendRemoveItemFromContainer(container, item)
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

-- Temperature ----------------------------------------------------------------------------------

local function kAt(temp)
    if temp <= K_BY_TEMP[1][1] or temp >= K_BY_TEMP[#K_BY_TEMP][1] then
        return 0
    end
    for i = 2, #K_BY_TEMP do
        local hi = K_BY_TEMP[i]
        if temp <= hi[1] then
            local lo = K_BY_TEMP[i - 1]
            return lo[2] + (hi[2] - lo[2]) * (temp - lo[1]) / (hi[1] - lo[1])
        end
    end
    return 0
end
DigesterObject.kAt = kAt

-- The air the digester sits in: its square's while loaded (rooms and heat sources included), else
-- the outdoor air, pulled toward a room's as the game pulls it.
function DigesterObject:airTemp(square)
    local climate = getClimateManager()
    if square then
        return climate:getAirTemperatureForSquare(square)
    end
    local temp = climate:getTemperature()
    if self.inRoom then
        if temp <= 22 then
            temp = temp + (22 - temp) * ROOM_PULL_COLD
        else
            temp = temp - (temp - 22) * ROOM_PULL_HOT
        end
    end
    return temp
end

-- The temperature the digester heads for, and whether it burns gas to get there.
function DigesterObject:targetTemp(air)
    local spec = self:tierSpec()
    if not spec.warmTo then
        return air, false
    end
    local target = math.max(air, GROUND_TEMP)
    if self.started and self.gas > 0 and target < spec.warmTo then
        return spec.warmTo, true
    end
    return target, false
end

-- The pass ------------------------------------------------------------------------------------

function DigesterObject:startupNeeded()
    return getSandboxOptions():getCompostHours()
end

function DigesterObject:startupProgress()
    local needed = self:startupNeeded()
    local seeded = math.min(self.seedHours, needed * SEED_SHARE)
    return math.min(1, (self.startupHours + seeded) / needed)
end

-- Runs `hours` (at most one) of digestion at the air temperature `air`.
function DigesterObject:step(hours, air)
    local spec = self:tierSpec()
    local target, heating = self:targetTemp(air)
    self.temp = self.temp + (target - self.temp) * (1 - math.exp(-hours / (spec.days * 24)))

    local made = 0
    if not self.started then
        if self.fed and self.temp >= STARTUP_MIN_TEMP then
            self.startupHours = self.startupHours + hours
        end
        self.started = self:startupProgress() >= 1
    else
        self.gasHours = self.gasHours + hours
        local k = kAt(self.temp) * (self.sour and SOUR_K or 1) * (self.sludge > SLUDGE_SLOW and SLUDGE_K or 1)
        local digested = self.potential * (1 - math.exp(-k * hours / 24))
        self.potential = self.potential - digested
        made = digested * SandboxVars.RenewableEnergy.BiogasMultiplier
        if heating then
            made = made * (1 - spec.heatShare)
        end
    end
    self.gas = self.gas + made
    self.madePerDay = self.madePerDay + (made * 24 / hours - self.madePerDay) * (1 - math.exp(-hours / RATE_HOURS))

    self.acid = self.acid * math.exp(-ACID_DECAY_PER_DAY * hours / 24)
    local limit = self:acidLimit()
    if self.acid > limit then
        self.sour = true
    elseif self.acid < limit / 2 then
        self.sour = false
    end

    local holder = Digester.HOLDERS[self.holder]
    if holder.wearPerDay and self.holderCondition > 0 then
        self.holderCondition = math.max(0, self.holderCondition - holder.wearPerDay * hours / 24)
    end
    self.leakHours = math.max(0, self.leakHours - hours)
    local capacity = self:capacity()
    if self.gas > capacity then
        self.gas = capacity
        if self.indoors then
            self.leakHours = LEAK_HOURS
        end
    end
end

--- Brings the digester up to now.
function DigesterObject:update()
    local now = getGameTime():getWorldAgeHours()
    local hours = math.min(LONGEST_PASS, now - (self.lastHour or now))
    self.lastHour = now
    if hours <= 0 then
        return
    end
    local isoObject = self:getIsoObject()
    local container = isoObject and isoObject:getContainer()
    local square = isoObject and isoObject:getSquare()
    local air = self:airTemp(square)
    while hours > 0 do
        local step = math.min(1, hours)
        self:meter(step, container)
        self:step(step, air)
        hours = hours - step
    end
    if container then
        self:snapshotHopper(container)
    end
    self:afterChange()
end

--- Shows and tells what changed, after a pass or a job.
function DigesterObject:afterChange()
    self:smell()
    self:fumes()
    self:showHolder()
    self:sendSummary()
end

-- Stink and fumes -----------------------------------------------------------------------------

-- Startup stinks most at its middle, the first week or so at the default compost time; a working
-- digester settles down over its first two weeks of gas.
local STARTUP_STINK, STARTUP_PEAK = 1.0, 0.5
local YOUNG_STINK, MATURE_STINK, MATURE_HOURS = 0.8, 0.4, 14 * 24
local SLUDGE_STINK, SOUR_STINK = 0.8, 1.5
-- A part-filled digester stinks less than a full one.
local EMPTY_SHARE = 0.5
-- Smell levels in the game's corpse count at the default corpse option: nothing for five or
-- fewer, the first level from 6, the second from 15, the third at 25 (BodyDamage and MoodleStat).
local FIRST, SECOND, THIRD = 6, 15, 25

--- The stink score: under 0.2 none, then up to 1 the first smell level, up to 2 the second, and
--- the third beyond.
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

--- The corpses the stink score smells like.
function DigesterObject.corpsesFor(score)
    if score < 0.2 then
        return 0
    elseif score < 1 then
        return FIRST + math.floor((score - 0.2) / 0.8 * (SECOND - FIRST))
    elseif score < 2 then
        return SECOND + math.floor((score - 1) * (THIRD - SECOND))
    end
    return THIRD
end

function DigesterObject:smell()
    Stink.set(self:key(), self.x, self.y, self.z, DigesterObject.corpsesFor(self:stinkScore()))
end

--- Whether the digester fills its building with fumes: badly sour or leaking, indoors. The dome
--- is sealed and buried.
function DigesterObject:fuming()
    return self.indoors and self.tier ~= "dome" and (self.sour or self.leakHours > 0)
end

-- Toxicity belongs to the whole building, isn't saved, and any vanilla generator there sets it
-- again within the hour while it runs, so this sets it while fuming and clears what it set.
function DigesterObject:fumes()
    local isoObject = self:getIsoObject()
    local building = isoObject and isoObject:getSquare():getBuilding()
    if not building then
        return
    end
    local fuming = self:fuming()
    if fuming then
        if not building:isToxic() then
            building:setToxic(true)
        end
        self.madeToxic = true
    elseif self.madeToxic then
        self.madeToxic = nil
        if not self.luaSystem:buildingNeedsFumes(building, self) then
            building:setToxic(false)
        end
    end
end

-- Holder -------------------------------------------------------------------------------------

function DigesterObject:showHolder()
    local isoObject = self:getIsoObject()
    if not isoObject then return end
    local capacity = Digester.HOLDERS[self.holder].capacity
    local wanted = Digester.holderOverlay(self.holder, self.gas / capacity, self:isTorn())
    local attached = isoObject:getAttachedAnimSprite()
    local count = attached and attached:size() or 0
    local shown
    for i = 0, count - 1 do
        local name = attached:get(i):getName()
        if Digester.isHolderOverlay(name) then
            shown = name
        end
    end
    if shown == wanted then return end
    for i = count - 1, 0, -1 do
        if Digester.isHolderOverlay(attached:get(i):getName()) then
            isoObject:RemoveAttachedAnim(i)
        end
    end
    if wanted then
        isoObject:addAttachedAnimSpriteByName(wanted)
    end
    isoObject:transmitUpdatedSpriteToClients()
end

-- Gas ------------------------------------------------------------------------------------------

--- Takes up to `m3` of gas out of the holder. Returns what it took.
function DigesterObject:takeGas(m3)
    local taken = math.min(m3, self.gas)
    self.gas = self.gas - taken
    return taken
end

-- Summary --------------------------------------------------------------------------------------

local function round(value, places)
    local scale = 10 ^ places
    return math.floor(value * scale + 0.5) / scale
end

--- What every client keeps of the digester: what its menu checks and its status window shows,
--- rounded so a pass that changes little sends nothing.
function DigesterObject:buildSummary()
    local spec = self:tierSpec()
    return {
        tier = self.tier, material = self.material, holder = self.holder,
        holderCondition = math.floor(self.holderCondition + 0.5), torn = self:isTorn(),
        gas = round(self.gas, 2), capacity = self:capacity(),
        temp = round(self.temp, 0),
        fed = self.fed, started = self.started, startup = round(self:startupProgress(), 2),
        sludge = math.floor(self.sludge), sour = self.sour, leaking = self.leakHours > 0,
        fill = round(math.min(1, self.potential / spec.potentialCap), 2),
        madePerDay = round(self.madePerDay, 2),
        hopper = #self.hopper,
        stink = round(self:stinkScore(), 1),
    }
end

local function same(a, b)
    for key, value in pairs(a) do
        if b[key] ~= value then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

function DigesterObject:sendSummary()
    local summary = self:buildSummary()
    if not (self.summary and same(summary, self.summary)) then
        self.summary = summary
        self:updateOnClient()
    end
end

return DigesterObject
