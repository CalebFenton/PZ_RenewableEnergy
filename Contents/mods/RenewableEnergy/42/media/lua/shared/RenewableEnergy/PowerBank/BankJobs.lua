-- The hands-on jobs at a battery bank: what each takes of the character and what refuses it
-- (cf_commonlib's Jobs). RenewableEnergy.JobSites.bank does them. Parts enter and leave a bank
-- only through Wire In and Unwire (see RenewableEnergy/PowerBank/WiredPartsGuard.lua).

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Jobs = require "cf_commonlib/Jobs"

local BankJobs = {}
RenewableEnergy.BankJobs = BankJobs

BankJobs.TURN_ON = "TurnOn"
BankJobs.TURN_OFF = "TurnOff"
BankJobs.CONNECT = "ConnectBank"
BankJobs.DISCONNECT = "DisconnectBank"
BankJobs.WIRE_IN = "WireIn"
BankJobs.UNWIRE = "Unwire"
BankJobs.REPAIR = "RepairPart"
BankJobs.RENAME = "Rename"

-- What wiring the part `item` in or out takes, or nil for no part.
local function wiringOf(item)
    return instanceof(item, "InventoryItem") and PowerBank.wiringFor(item:getFullType()) or nil
end

-- Whether `item` is in the bank's container, of a type `isKind(fullType)` accepts.
local function inBank(bank, item, isKind)
    local container = bank:getContainer()
    return instanceof(item, "InventoryItem") and container ~= nil and container:contains(item)
        and isKind(item:getFullType()) and true or false
end

local function isPart(item)
    return PowerBank.partKind(item:getFullType()) ~= nil
end

-- The bank's switch set to `on`.
local function switchJob(on)
    return {
        on = on, minutes = 0.5, doneSound = "LightSwitch",
        blocker = function(character, bank) return PowerBank.switchRefusal(PowerBank.currentSummary(bank), on) end,
    }
end

-- Connect and Disconnect the bank to the house's wiring, as vanilla's ISPlugGenerator, which can't
-- tell the bank its state changed. Unlike vanilla's, it needs light: it is wiring at the house's
-- panel, as wiring a part in is.
local function plugJob(connected)
    return {
        connected = connected, units = 300, light = true, sound = "GeneratorConnect",
        blocker = function(character, bank)
            return PowerBank.connectRefusal(character, bank, PowerBank.currentSummary(bank), connected)
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
        units = function(bank, item, character) return PowerBank.wiringUnits(character, wiringOf(item)) end,
        light = true, sound = "GeneratorConnect",
        blocker = function(character, bank, item)
            if not Jobs.carries(character, item, isPart) then
                return "Tooltip_RenewableEnergy_NotAPart"
            end
            return PowerBank.freePartSlots(bank, PowerBank.partKind(item:getFullType())) == 0
                and "Tooltip_RenewableEnergy_NoSlot" or nil
        end,
        materials = function(character, bank, item)
            local wiring = wiringOf(item)
            return wiring and PowerBank.wiringMaterials(wiring) or {}
        end,
    },
    -- A part out of the bank, given back with its wire; it takes the tools that wired it in, as
    -- vanilla takes a car part's install tools to uninstall it.
    [BankJobs.UNWIRE] = {
        units = function(bank, item, character) return PowerBank.wiringUnits(character, wiringOf(item), 0.5) end,
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
        materials = { { perk = "Electricity", need = Specs.partRepair.skill }, { item = PowerBank.SCRAP, need = 1 } },
        xp = { perk = "Electricity", amount = Specs.partRepair.xp },
    },
    -- An empty name gives the bank back its tier's.
    [BankJobs.RENAME] = {
        minutes = 0.5,
        withRefusal = function(character, bank, name) return PowerBank.nameRefusal(name) end,
    },
}

Jobs.define(BankJobs, {
    subjectOf = function(bank) return PowerBank.currentSummary(bank) and bank end, missing = "no bank",
})

--- All Batteries uses the same jobs as individual wiring. Select before totaling needs: best
--- condition first up to the free slots for Wire In, container order for Unwire. With no free
--- slots keep the candidates so the ordinary blocker explains why the batch is unavailable.
--- Returns items, combined needs and blocker, or nil when fewer than two batteries qualify.
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
        local free = PowerBank.freePartSlots(bank, "battery")
        while free > 0 and #batteries > free do
            table.remove(batteries)
        end
    end
    if #batteries < 2 then return nil end
    local needs, byKind, blocker = {}, {}, nil
    for _, item in ipairs(batteries) do
        blocker = blocker or BankJobs.blocker(character, job, bank, item)
        for _, need in ipairs(BankJobs.needs(character, job, bank, item)) do
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
                table.insert(needs, need)
            end
        end
    end
    return batteries, needs, blocker
end

return BankJobs
