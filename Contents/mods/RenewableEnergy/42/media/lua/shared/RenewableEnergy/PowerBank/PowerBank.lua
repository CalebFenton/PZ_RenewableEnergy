-- Battery banks and the panels wired to them, as both sides see them: what an object is,
-- what a bank holds and what it may take, and the bank's status as the server last reported it.
--
-- The server runs the banks (server/RenewableEnergy/PowerBank) and adds perform() and
-- place() to this table; the client adds command() and addStatusListener()
-- (client/RenewableEnergy/PowerBank). Both register a Global Object System under
-- SYSTEM_NAME, which keeps each bank's state while its chunk is unloaded and copies the
-- `status` field to every client.

require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"

local PowerBank = {}
RenewableEnergy.PowerBank = PowerBank

local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites

PowerBank.SYSTEM_NAME = "renewable_energy_powerbank"
PowerBank.WIRE = "Base.ElectricWire"
PowerBank.SCRAP = "Base.ElectronicsScrap"
-- Item modData: the item was wired into a bank once, which taught its Electricity XP.
PowerBank.WIRED_ONCE = "RenewableEnergy_wiredOnce"
-- Item and placed-object modData: the modules a panel mount holds, { { type, condition }, ... }.
PowerBank.MODULES = "RenewableEnergy_modules"

local SOURCE_KINDS = { flat = true, wall = true, rack = true }

-- Placed bank sprite to its Specs.banks row, and to the item it is.
local BANKS_BY_SPRITE = {}
for fullType, bank in pairs(Specs.banks) do
    BANKS_BY_SPRITE[Sprites[bank.sprite]] = { fullType = fullType, spec = bank }
end

--- Every placed bank tile's sprite name.
function PowerBank.bankSprites()
    local names = {}
    for name in pairs(BANKS_BY_SPRITE) do
        table.insert(names, name)
    end
    return names
end

local function spriteName(isoObject)
    if not instanceof(isoObject, "IsoObject") then
        return nil
    end
    local sprite = isoObject:getSprite()
    return sprite and sprite:getName()
end

--- The bank a placed sprite is: { fullType, spec }, or nil.
function PowerBank.bankOfSprite(name)
    return name and BANKS_BY_SPRITE[name]
end

--- Whether an object is a working bank: a bank tile turned into the generator that powers
--- the squares around it.
function PowerBank.isBank(isoObject)
    return instanceof(isoObject, "IsoGenerator") and PowerBank.bankOfSprite(spriteName(isoObject)) ~= nil
end

--- The mount of a placed panel, "flat", "wall" or "rack", the way it faces and what it is made
--- of; nil for anything else.
function PowerBank.sourceKind(isoObject)
    local kind, facing, material = Sprites.kindOf(spriteName(isoObject))
    if SOURCE_KINDS[kind] then
        return kind, facing, material
    end
    return nil
end

--- How likely a storm is to crack a module of a mount, relative to Specs.storm.chancePerHour.
function PowerBank.stormFactor(kind, material)
    local materialSpec = material and Specs.materials[material]
    return Specs.mounts[kind].stormFactor * (materialSpec and materialSpec.stormFactor or 1)
end

--- Where a bank may stand: inside a building, out of the weather. Returns true, or false and
--- the translation key of the reason.
function PowerBank.canPlaceBank(square)
    if square and square:getRoom() ~= nil and not square:isOutside() then
        return true
    end
    return false, "Tooltip_RenewableEnergy_BankIndoorsOnly"
end

-- Parts --------------------------------------------------------------------------------------

--- What kind of bank part an item type is: "battery", "inverter", "charger", "controller", or
--- nil.
function PowerBank.partKind(fullType)
    if Specs.batteries[fullType] then
        return "battery"
    elseif Specs.inverters[fullType] then
        return "inverter"
    elseif fullType == Specs.charger then
        return "charger"
    elseif fullType == Specs.controller then
        return "controller"
    end
    return nil
end

local MAX_FIELDS = { battery = "maxBatteries", inverter = "maxInverters", charger = "maxChargers", controller = "maxControllers" }

--- How many parts of `kind` a bank of Specs.banks row `bankSpec` takes.
function PowerBank.maxParts(bankSpec, kind)
    return bankSpec[MAX_FIELDS[kind]]
end

--- How many parts of `kind` a bank container holds.
function PowerBank.countParts(container, kind)
    local count = 0
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        if PowerBank.partKind(items:get(i):getFullType()) == kind then
            count = count + 1
        end
    end
    return count
end

--- What wiring `fullType` into a bank takes (Specs.wiring), with the Electricity level filled
--- in, or nil if it is no part.
function PowerBank.wiringFor(fullType)
    local kind = PowerBank.partKind(fullType)
    if not kind then
        return nil
    end
    local wiring = {}
    for key, value in pairs(Specs.wiring[kind]) do
        wiring[key] = value
    end
    if kind == "inverter" then
        wiring.skill = Specs.inverters[fullType].wireSkill
    end
    return wiring
end

local function notBroken(item)
    return not item:isBroken()
end

--- Whether the character carries a working tool with ItemTag field `tag`.
function PowerBank.hasTool(character, tag)
    return character:getInventory():containsTagEvalRecurse(ItemTag[tag], notBroken)
end

--- The bank container's filter (ItemContainer.isItemAllowed). Parts go in only by being wired
--- in, which moves them without asking the filter, so it refuses every transfer.
function PowerBank.acceptItem(container, item)
    return false
end

--- Why `character` can't wire `item` into the bank `bankObject` now, as a translation key, or
--- nil if they can.
function PowerBank.wiringRefusal(character, bankObject, item)
    local bank = PowerBank.bankOfSprite(spriteName(bankObject))
    local container = bank and bankObject:getContainer()
    local wiring = instanceof(item, "InventoryItem") and PowerBank.wiringFor(item:getFullType())
    if not (container and wiring) then
        return "Tooltip_RenewableEnergy_NotAPart"
    end
    local kind = PowerBank.partKind(item:getFullType())
    if PowerBank.countParts(container, kind) >= PowerBank.maxParts(bank.spec, kind) then
        return "Tooltip_RenewableEnergy_NoSlot"
    elseif character:tooDarkToRead() then
        return "Tooltip_RenewableEnergy_TooDark"
    elseif character:getPerkLevel(Perks.Electricity) < wiring.skill then
        return "Tooltip_RenewableEnergy_NeedSkill"
    elseif not PowerBank.hasTool(character, wiring.tool) then
        return "Tooltip_RenewableEnergy_NeedTool"
    end
    local inventory = character:getInventory()
    if inventory:getCountTypeRecurse(PowerBank.WIRE) < wiring.wire then
        return "Tooltip_RenewableEnergy_NeedWire"
    elseif inventory:getCountTypeRecurse(PowerBank.SCRAP) < wiring.scrap then
        return "Tooltip_RenewableEnergy_NeedScrap"
    end
    return nil
end

--- Why `character` can't repair the inverter or controller `item` with Electronics Scrap now,
--- as a translation key, or nil if they can.
function PowerBank.repairRefusal(character, item)
    local kind = instanceof(item, "InventoryItem") and PowerBank.partKind(item:getFullType())
    if kind ~= "inverter" and kind ~= "controller" then
        return "Tooltip_RenewableEnergy_NotRepairable"
    elseif item:getCondition() >= item:getConditionMax() then
        return "Tooltip_RenewableEnergy_NoRepairNeeded"
    elseif character:tooDarkToRead() then
        return "Tooltip_RenewableEnergy_TooDark"
    elseif character:getPerkLevel(Perks.Electricity) < Specs.partRepair.skill then
        return "Tooltip_RenewableEnergy_NeedSkill"
    elseif character:getInventory():getCountTypeRecurse(PowerBank.SCRAP) < 1 then
        return "Tooltip_RenewableEnergy_NeedScrap"
    end
    return nil
end

-- Banks as either side knows them ---------------------------------------------------------

-- The Global Object System of this side: the server's in single player, where both exist
-- and the server's is the live one.
local function system()
    return PowerBank.serverSystem or PowerBank.clientSystem
end

local function eachBank(fn)
    local sys = system()
    if not sys then return end
    local objects = sys.system
    for i = 0, objects:getObjectCount() - 1 do
        local luaObject = objects:getObjectByIndex(i):getModData()
        if fn(luaObject) then return end
    end
end

local function bankAt(x, y, z)
    local sys = system()
    local globalObject = sys and sys.system:getObjectAt(x, y, z)
    return globalObject and globalObject:getModData()
end

--- The bank's status (see Bank:buildStatus), or nil.
function PowerBank.getStatus(x, y, z)
    local bank = bankAt(x, y, z)
    return bank and bank.status
end

function PowerBank.isInReach(bank, x, y, z)
    local reach = Specs.sourceReach
    return IsoUtils.DistanceToSquared(x, y, bank.x, bank.y) <= reach.tiles * reach.tiles
        and math.abs(z - bank.z) <= reach.levels
end

--- Banks a panel on this square may be wired to.
function PowerBank.banksInReach(x, y, z)
    local found = {}
    local square = getSquare(x, y, z)
    if not (square and square:isOutside()) then
        return found
    end
    eachBank(function(bank)
        if PowerBank.isInReach(bank, x, y, z) then
            table.insert(found, { x = bank.x, y = bank.y, z = bank.z })
        end
    end)
    return found
end

--- The bank the panel on this square is wired to, or nil.
function PowerBank.bankOfSource(x, y, z)
    local found
    eachBank(function(bank)
        for _, source in ipairs(bank.status and bank.status.sources or {}) do
            if source.x == x and source.y == y and source.z == z then
                found = { x = bank.x, y = bank.y, z = bank.z }
                return true
            end
        end
    end)
    return found
end

return PowerBank
