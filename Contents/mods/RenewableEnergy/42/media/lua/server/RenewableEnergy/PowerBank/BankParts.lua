-- The parts a bank holds: reading its container into the snapshot, writing the charge back into
-- its batteries, what its working inverters, chargers and controllers add up to, and their wear.
-- Adds to Bank.lua's class.

if isClient() then return end

local Specs = require "RenewableEnergy/Specs"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Bank = require "RenewableEnergy/PowerBank/Bank"

local function partEntry(item)
    return { type = item:getFullType(), condition = item:getCondition() }
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
            if Battery.changedVisibly(Battery.getCharge(item), self.charge) then
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

--- The sum of Specs.inverters[type][field] over the bank's working inverters.
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

--- The watts the inverters take from the batteries to carry the load and run themselves. Working
--- inverters share the load in proportion to what each carries, and each wastes its own share of
--- its part.
function Bank:inverterDrawW()
    local carried, drawn = 0, 0
    for _, inverter in ipairs(self.inverters) do
        if working(inverter) then
            local spec = Specs.inverters[inverter.type]
            carried = carried + spec.watts
            drawn = drawn + spec.watts / spec.efficiency
        end
    end
    local loadDrawW = carried > 0 and self.loadW * drawn / carried or 0
    return loadDrawW + sumInverters(self, "idle")
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

return Bank
