-- What a bank on the authority tells the clients: the summary every client keeps, the whole status
-- for the players watching it, and who watches.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/Bank"

RenewableEnergy = RenewableEnergy or {}
local PowerBank, Sources, Bank = RenewableEnergy.PowerBank, RenewableEnergy.Sources, RenewableEnergy.Bank

--- What the bank is doing, for the status window.
function Bank:state()
    if not self.indoors then return "outdoors" end
    if self:limitW() <= 0 then return "noInverter" end
    if self.nominalWh <= 0 then return "noBatteries" end
    if self.connected == false then return "disconnected" end
    if not self.on then return "off" end
    if self.gridPowered then return "grid" end
    if self.overloaded then return "overloaded" end
    if self.empty then return "empty" end
    return "on"
end

local function partStatus(parts, extra)
    local list = {}
    for _, part in ipairs(parts) do
        local entry = { id = part.id, type = part.type, condition = part.condition, working = Bank.isWorking(part) }
        if extra then
            extra(entry, part)
        end
        table.insert(list, entry)
    end
    return list
end

function Bank:sourceStatus()
    local sources = {}
    for _, source in ipairs(self.sources) do
        local entry = {
            x = source.x, y = source.y, z = source.z, kind = source.kind, watts = source.watts or 0,
            reason = source.reason,
        }
        local status = Bank.FAMILY[Sources.familyOf(source.kind)].status
        if status then
            status(entry, source)
        end
        table.insert(sources, entry)
    end
    return sources
end

-- Net watts into the batteries, and the hours until they are full (charging) or empty
-- (draining); hours is nil when nothing changes.
local function chargingStatus(netW, stored, capacity)
    local hours
    if netW > 0 and capacity > stored then
        hours = (capacity - stored) / netW
    elseif netW < 0 and stored > 0 then
        hours = stored / -netW
    end
    return { watts = netW, hours = hours }
end

function Bank:buildStatus()
    local now = self.now or {}
    local capacity = self.nominalWh
    local stored = self.charge * capacity
    local inW = now.chargerW or 0
    for _, total in pairs(Bank.TOTALS) do
        inW = inW + (now[total.now] or 0)
    end
    local drawW = now.drawW or 0
    local batteries = partStatus(self.batteries, function(entry, part)
        entry.nominalWh, entry.charge, entry.repaired = part.nominalWh, self.charge, part.repaired
    end)
    -- The window names what the chargers charge from, not where the generator stands.
    local chargeSource = self.chargeSource == "grid" and "grid" or (self.chargeSource and "generator") or nil
    local chargers = partStatus(self.chargers, function(entry)
        entry.charging = entry.working and (now.chargerW or 0) > 0 and chargeSource or nil
    end)
    local isoObject = self:getIsoObject()
    local status = {
        kind = self:spec().sprite,
        bankType = self.bankType,
        name = self.name,
        on = self.on,
        state = self:state(),
        powered = isoObject ~= nil and isoObject:isActivated() or (isoObject == nil and self:shouldPower()),
        hour = getGameTime():getWorldAgeHours(),
        sunElevation = now.elevation or 0,
        irradiance = now.irradiance or 0,
        windKph = now.windKph or 0,
        chargerW = now.chargerW or 0, chargerMaxW = self:chargerMaxW(), chargeSource = chargeSource, inW = inW,
        gridPowered = self.gridPowered,
        loadWhToday = self.loadWhToday, backupWhToday = self.backupWhToday or 0,
        loadW = self.loadW, drawW = drawW, limitW = self:limitW(), overloaded = self.overloaded,
        loadByKind = self.loadByKind,
        storedWh = stored, capacityWh = capacity, charge = self.charge,
        charging = chargingStatus(inW - drawW, stored, capacity),
        cycleDepth = self.cycleDepth,
        inputSlots = { used = self:slotsUsed(), total = self:inputSlots() },
        inverters = partStatus(self.inverters),
        controllers = partStatus(self.controllers),
        chargers = chargers,
        batteries = batteries,
        sources = self:sourceStatus(),
        generator = self.generator and {
            x = self.generator.x, y = self.generator.y, z = self.generator.z, running = self.generator.running,
            failsafe = self.generator.failsafe, controls = self.generator.controls, armed = self.generator.armed,
        } or nil,
    }
    for _, total in pairs(Bank.TOTALS) do
        status[total.now] = now[total.now] or 0
        status[total.today] = self[total.today] or 0
    end
    return status
end

--- What every client keeps of the bank wherever it stands: what the menus of the bank and its
--- sources show and check. The Global Object System sends it to every client each time it
--- changes, so it holds nothing that moves with every pass.
function Bank:buildSummary()
    local sources = {}
    for _, source in ipairs(self.sources) do
        table.insert(sources, { x = source.x, y = source.y, z = source.z, snowy = (source.snow or 0) > 0 or nil })
    end
    return { bankType = self.bankType, name = self.name, on = self.on, limitW = self:limitW(), capacityWh = self.nominalWh,
        freeSlots = self:inputSlots() - self:slotsUsed(), sources = sources }
end

-- A client loads at most this many squares each way around its player (the widest chunk grid a
-- server lets a client connect with, GameServer.receivePlayerConnect), so a bank farther away
-- can't be in its view.
local VIEW_REACH = 80

--- Whether the bank can be in `player`'s view: they are alive, still connected, and near enough
--- for their client to have the bank loaded.
function Bank:inViewOf(player)
    if player:isDead() then
        return false
    end
    -- The server forgets a player who leaves, and one who comes back is a new object.
    if isServer() and getPlayerByOnlineID(player:getOnlineID()) ~= player then
        return false
    end
    return math.abs(player:getX() - self.x) <= VIEW_REACH and math.abs(player:getY() - self.y) <= VIEW_REACH
end

-- The players watching the bank's status, once those who can no longer see the bank are dropped:
-- the server hears of no disconnect, and a client that died or walked away never closes its window.
local function watchersOf(bank)
    local players, gone = {}, {}
    for player in pairs(bank.watchers or {}) do
        table.insert(bank:inViewOf(player) and players or gone, player)
    end
    for _, player in ipairs(gone) do
        bank.watchers[player] = nil
    end
    return players
end

local function sendTo(bank, player)
    sendServerCommand(player, PowerBank.COMMAND_MODULE, PowerBank.STATUS_COMMAND, { x = bank.x, y = bank.y, z = bank.z, status = bank.status })
end

--- Tell the clients what changed: every client the summary, when it changed, and the players
--- watching the bank its whole status. Single player has no network to send on; its status
--- window reads the status the bank keeps while someone watches.
function Bank:sendStatus()
    local summary = self:buildSummary()
    if not RenewableEnergy.sameValue(summary, self.summary) then
        self.summary = summary
        self:updateOnClient()
    end
    local players = watchersOf(self)
    self.status = #players > 0 and self:buildStatus() or nil
    for _, player in ipairs(players) do
        sendTo(self, player)
    end
end

--- `player` opened the bank's status window, and gets the status after every change until they
--- close it. Returns whether they weren't watching already.
function Bank:watch(player)
    self.watchers = self.watchers or {}
    local new = not self.watchers[player]
    self.watchers[player] = true
    return new
end

--- Send the status as the other watchers last had it to `player` alone.
function Bank:sendStatusTo(player)
    self.status = self.status or self:buildStatus()
    sendTo(self, player)
end

--- `player` closed the bank's status window. With nobody watching, the bank keeps no status.
function Bank:unwatch(player)
    local watchers = self.watchers
    if not watchers then return end
    watchers[player] = nil
    for _ in pairs(watchers) do
        return
    end
    self.watchers = nil
    self.status = nil
end

return Bank
