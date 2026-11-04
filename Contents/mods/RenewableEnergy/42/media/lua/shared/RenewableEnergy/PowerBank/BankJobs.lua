-- The hands-on jobs at a battery bank: what each takes of the character and what refuses it
-- (cf_commonlib's Jobs). Parts enter and leave a bank only through Wire In and Unwire
-- (WiredPartsGuard).

local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Wiring = require "RenewableEnergy/PowerBank/Wiring"
local Jobs = require "cf_commonlib/Jobs"

local BankJobs = {}

BankJobs.TURN_ON = "TurnOn"
BankJobs.TURN_OFF = "TurnOff"
BankJobs.CONNECT = "ConnectBank"
BankJobs.DISCONNECT = "DisconnectBank"
BankJobs.WIRE_IN = "WireIn"
BankJobs.UNWIRE = "Unwire"
BankJobs.REPAIR = "RepairPart"
BankJobs.RENAME = "Rename"

-- The longest name a bank takes.
BankJobs.NAME_LENGTH = 32

-- What wiring the part `item` in or out takes, or nil for no part.
local function wiringOf(item)
    return instanceof(item, "InventoryItem") and Wiring.forPart(item:getFullType()) or nil
end

local function countParts(container, kind)
    local count = 0
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        if PowerBank.partKind(items:get(i):getFullType()) == kind then
            count = count + 1
        end
    end
    return count
end

--- How many more parts of `kind` (a PowerBank.PARTS key) the bank `bank` takes; 0 for no bank.
function BankJobs.freePartSlots(bank, kind)
    local tier = PowerBank.bankOfSprite(Sprites.nameOf(bank))
    local container = tier and bank:getContainer()
    if not container then
        return 0
    end
    return math.max(0, tier.spec[PowerBank.PARTS[kind].max] - countParts(container, kind))
end

--- Why the bank whose summary or status is `summary` can't be switched `on` (true) or off now, or
--- nil: "already on" or "already off", or, switching on, what keeps it from carrying a load that a
--- player can mend (PowerBank.blocker): no working inverter, or no battery capacity.
function BankJobs.switchRefusal(summary, on)
    if summary.on == on then
        return on and "already on" or "already off"
    elseif on then
        local _, refusal = PowerBank.blocker({ limitW = summary.limitW, capacityWh = summary.capacityWh, on = true })
        return refusal
    end
    return nil
end

--- Turn On or Turn Off for a bank in `summary`'s state: its label key, its job, and why it is
--- refused (nil when it isn't).
function BankJobs.switchOf(summary)
    local on = summary.on == true
    return on and "ContextMenu_Turn_Off" or "ContextMenu_Turn_On", on and BankJobs.TURN_OFF or BankJobs.TURN_ON,
        BankJobs.switchRefusal(summary, not on)
end

--- `name` without the spaces around it, as a bank keeps it.
function BankJobs.trimName(name)
    return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Why `name` can't name a bank, or nil: a name is one line of at most NAME_LENGTH characters once
--- trimmed, which the rename box holds it to.
function BankJobs.nameRefusal(name)
    if type(name) ~= "string" then
        return "no name"
    end
    name = BankJobs.trimName(name)
    if #name > BankJobs.NAME_LENGTH then
        return "name too long"
    elseif name:find("%c") then
        return "name not one line"
    end
    return nil
end

--- Why `character` can't connect (`connect` true) or disconnect the bank `bank`, whose
--- summary or status is `summary`, or nil. Vanilla's generator rules: connecting needs the generator
--- Electricity level or the "Generator" recipe (ISWorldObjectContextMenuLogic.doGeneratorMenu), and
--- only a switched-off one disconnects.
function BankJobs.connectRefusal(character, bank, summary, connect)
    if bank:isConnected() == connect then
        return connect and "already connected" or "already disconnected"
    elseif connect and character:getPerkLevel(Perks.Electricity) < 3 and not character:isRecipeActuallyKnown("Generator") then
        return "ContextMenu_GeneratorPlugTT"
    elseif not connect and summary.on then
        return "already on"
    end
    return nil
end

-- Whether `item` is in the bank's container, of a type `isKind(fullType)` accepts.
local function inBank(bank, item, isKind)
    local container = bank:getContainer()
    return instanceof(item, "InventoryItem") and container ~= nil and container:contains(item)
        and isKind(item:getFullType()) and true or false
end

--- Whether `item` is a bank part (PowerBank.PARTS), which Wire In takes.
function BankJobs.isPart(item)
    return PowerBank.partKind(item:getFullType()) ~= nil
end

-- The bank's switch set to `on`.
local function switchJob(on)
    return {
        on = on, minutes = 0.5, doneSound = "LightSwitch",
        blocker = function(character, bank) return BankJobs.switchRefusal(PowerBank.currentSummary(bank), on) end,
    }
end

-- Connect and Disconnect the bank to the house's wiring, as vanilla's ISPlugGenerator, which can't
-- tell the bank its state changed. Unlike vanilla's, it needs light: it is wiring at the house's
-- panel, as wiring a part in is.
local function plugJob(connected)
    return {
        connected = connected, units = 300, light = true, sound = "GeneratorConnect",
        blocker = function(character, bank)
            return BankJobs.connectRefusal(character, bank, PowerBank.currentSummary(bank), connected)
        end,
    }
end

-- Every job, by name (Jobs.define), at the bank's tile; `with` is the part a job wires or mends,
-- or Rename's new name.
BankJobs.JOBS = {
    [BankJobs.TURN_ON] = switchJob(true),
    [BankJobs.TURN_OFF] = switchJob(false),
    [BankJobs.CONNECT] = plugJob(true),
    [BankJobs.DISCONNECT] = plugJob(false),
    -- A carried part into the bank.
    [BankJobs.WIRE_IN] = {
        units = function(bank, item, character) return Wiring.units(character, wiringOf(item)) end,
        light = true, sound = "GeneratorConnect",
        with = BankJobs.isPart, withMissing = "Tooltip_RenewableEnergy_NotAPart",
        blocker = function(character, bank, item)
            local kind = instanceof(item, "InventoryItem") and PowerBank.partKind(item:getFullType())
            return kind and BankJobs.freePartSlots(bank, kind) == 0 and "Tooltip_RenewableEnergy_NoSlot" or nil
        end,
        materials = function(character, bank, item)
            local wiring = wiringOf(item)
            return wiring and Wiring.materials(wiring) or {}
        end,
    },
    -- A part out of the bank, given back with its wire; it takes the tools that wired it in, as
    -- vanilla takes a car part's install tools to uninstall it.
    [BankJobs.UNWIRE] = {
        units = function(bank, item, character) return Wiring.units(character, wiringOf(item), 0.5) end,
        light = true, inTarget = true, sound = "GeneratorConnect",
        blocker = function(character, bank, item)
            return not inBank(bank, item, PowerBank.partKind) and "Tooltip_RenewableEnergy_NotAPart" or nil
        end,
        materials = function(character, bank, item)
            local wiring = wiringOf(item)
            return wiring and wiring.tools or {}
        end,
    },
    -- An inverter or controller in the bank mended with Electronics Scrap, as long as vanilla's
    -- ISFixGenerator.
    [BankJobs.REPAIR] = {
        units = function(bank, item, character) return 150 - character:getPerkLevel(Perks.Electricity) * 3 end,
        light = true, inTarget = true, sound = "GeneratorRepair",
        blocker = function(character, bank, item)
            if not inBank(bank, item, PowerBank.isRepairable) then
                return "Tooltip_RenewableEnergy_NotRepairable"
            end
            return item:getCondition() >= item:getConditionMax() and "Tooltip_RenewableEnergy_NoRepairNeeded" or nil
        end,
        materials = { { perk = "Electricity", need = Specs.partRepair.skill }, { item = Wiring.SCRAP, need = 1 } },
        xp = { perk = "Electricity", amount = Specs.partRepair.xp },
    },
    -- An empty name gives the bank back its tier's.
    [BankJobs.RENAME] = {
        minutes = 0.5,
        withRefusal = function(character, bank, name) return BankJobs.nameRefusal(name) end,
    },
}

Jobs.define(BankJobs, {
    subjectOf = function(bank) return PowerBank.currentSummary(bank) and bank end, missing = "no bank",
})

--- All Batteries uses the same jobs as individual wiring. Select before totaling needs: best
--- condition first up to the free slots for Wire In, container order for Unwire. With no free
--- slots keep the candidates so the ordinary blocker explains why the batch is unavailable.
--- Returns the items and the batch's verdict (BankJobs.verdict's shape: the first blocker, the
--- combined needs, the first withRefusal), or nil when fewer than two batteries qualify.
function BankJobs.batteryBatch(character, job, bank, parts)
    local batteries = {}
    for _, item in ipairs(parts) do
        if PowerBank.partKind(item:getFullType()) == "battery" then
            table.insert(batteries, item)
        end
    end
    if job == BankJobs.WIRE_IN then
        table.sort(batteries, function(a, b)
            return a:getCondition() / a:getConditionMax() > b:getCondition() / b:getConditionMax()
        end)
        local free = BankJobs.freePartSlots(bank, "battery")
        while free > 0 and #batteries > free do
            table.remove(batteries)
        end
    end
    if #batteries < 2 then return nil end
    local batch, byKind = { needs = {} }, {}
    for _, item in ipairs(batteries) do
        local verdict = BankJobs.verdict(character, job, bank, item)
        batch.blocker = batch.blocker or verdict.blocker
        batch.withRefusal = batch.withRefusal or verdict.withRefusal
        for _, need in ipairs(verdict.needs or {}) do
            local kind = byKind[need.kind] or {}
            byKind[need.kind] = kind
            local key = need.perk or need.tool or need.item
            local previous = kind[key]
            if previous then
                -- Wiring's item needs are consumed; its tools and skills are reused.
                previous.need = need.kind == "item" and previous.need + need.need
                    or math.max(previous.need, need.need)
            else
                kind[key] = need
                table.insert(batch.needs, need)
            end
        end
    end
    return batteries, batch
end

return BankJobs
