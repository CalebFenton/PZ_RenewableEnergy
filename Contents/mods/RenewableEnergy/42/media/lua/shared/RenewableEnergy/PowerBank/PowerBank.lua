-- Battery banks and the panels connected to them, as both sides see them: what an object is,
-- what a bank holds and what it may take, and the bank's status as the server last reported it.
--
-- The server runs the banks (server/RenewableEnergy/PowerBank) and adds perform() and
-- place() to this table; the client adds command() (client/RenewableEnergy/PowerBank/
-- ClientBankSystem.lua). Both register a Global Object System under SYSTEM_NAME, which keeps
-- each bank's state while its chunk is unloaded and copies the `status` field to every client.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"

RenewableEnergy = RenewableEnergy or {}
local PowerBank = {}
RenewableEnergy.PowerBank = PowerBank

local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites

PowerBank.SYSTEM_NAME = "renewable_energy_powerbank"
PowerBank.WIRE = "Base.ElectricWire"
PowerBank.SCRAP = "Base.ElectronicsScrap"
-- Item modData: the item was wired into a bank once, which taught its Electricity XP.
PowerBank.WIRED_ONCE = "RenewableEnergy_wiredOnce"
-- Item and placed-object modData: the modules a panel mount holds, { { type, condition, mounted,
-- connected }, ... }. mounted and connected say the module already taught the XP of its first
-- mounting and its first connection to a bank, so moving modules around teaches nothing new.
PowerBank.MODULES = "RenewableEnergy_modules"
-- Solar module item modData: the same two flags, while the module is off its mount.
PowerBank.MOUNTED_ONCE = "RenewableEnergy_mountedOnce"
PowerBank.CONNECTED_ONCE = "RenewableEnergy_connectedOnce"

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

--- The working bank on a square, or nil.
function PowerBank.bankOn(square)
    return RenewableEnergy.findObjectOn(square, PowerBank.isBank)
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

local function isSource(object)
    return PowerBank.sourceKind(object) ~= nil
end

--- The placed panel on a square, or nil.
function PowerBank.sourceOn(square)
    return RenewableEnergy.findObjectOn(square, isSource)
end

local function copyModule(module)
    return { type = module.type, condition = module.condition, mounted = module.mounted, connected = module.connected }
end

--- The modules a panel holds, as a fresh list of module records: what the item or placed object
--- `holder` recorded under MODULES or, without a record (a mount spawned by debug), the `mount`
--- kind's full load of factory modules at full condition.
function PowerBank.modulesOf(holder, mount)
    local modules = {}
    local recorded = holder:getModData()[PowerBank.MODULES]
    if type(recorded) == "table" then
        for _, module in ipairs(recorded) do
            table.insert(modules, copyModule(module))
        end
    end
    if #modules == 0 then
        for i = 1, Specs.mounts[mount].modules do
            modules[i] = { type = Specs.factoryModule, condition = 100 }
        end
    end
    return modules
end

--- Records `modules` on a placed panel and sends the record to clients.
function PowerBank.writeModules(isoObject, modules)
    local record = {}
    for i, module in ipairs(modules) do
        record[i] = copyModule(module)
    end
    isoObject:getModData()[PowerBank.MODULES] = record
    isoObject:transmitModData()
end

--- The module record of a solar module item.
function PowerBank.moduleRecord(item)
    local data = item:getModData()
    return { type = item:getFullType(), condition = item:getCondition(),
        mounted = data[PowerBank.MOUNTED_ONCE] == true, connected = data[PowerBank.CONNECTED_ONCE] == true }
end

--- Marks a solar module item with its record's flags, as it comes off a mount.
function PowerBank.markModule(item, module)
    local data = item:getModData()
    data[PowerBank.MOUNTED_ONCE] = module.mounted or nil
    data[PowerBank.CONNECTED_ONCE] = module.connected or nil
end

--- Shows a cracked glass over each of a placed panel's modules below Specs.crackedBelow and over
--- none of the others, then sends the overlays to clients if they changed. Authority only: a
--- client's own overlays would be overwritten by the server's next sprite update.
function PowerBank.showCracks(isoObject)
    local kind, facing, material = PowerBank.sourceKind(isoObject)
    if not kind then return end
    local list = Sprites.crackOverlays(kind, facing, material, PowerBank.modulesOf(isoObject, kind))
    local wanted = {}
    for _, name in ipairs(list) do
        wanted[name] = true
    end
    local shown, changed = {}, false
    local attached = isoObject:getAttachedAnimSprite()
    for i = (attached and attached:size() or 0) - 1, 0, -1 do
        local name = attached:get(i):getName()
        if Sprites.isCrack(name) then
            if wanted[name] and not shown[name] then
                shown[name] = true
            else
                isoObject:RemoveAttachedAnim(i)
                changed = true
            end
        end
    end
    local added = false
    for _, name in ipairs(list) do
        if not shown[name] then
            isoObject:addAttachedAnimSpriteByName(name)
            added = true
        end
    end
    if added then
        -- Snow lies on the glass, so it goes back on top of the cracks just added.
        local snow = {}
        attached = isoObject:getAttachedAnimSprite()
        for i = attached:size() - 1, 0, -1 do
            local name = attached:get(i):getName()
            if Sprites.isSnow(name) then
                table.insert(snow, 1, name)
                isoObject:RemoveAttachedAnim(i)
            end
        end
        for _, name in ipairs(snow) do
            isoObject:addAttachedAnimSpriteByName(name)
        end
    end
    if changed or added then
        isoObject:transmitUpdatedSpriteToClients()
    end
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
local function maxParts(bankSpec, kind)
    return bankSpec[MAX_FIELDS[kind]]
end

--- How many parts of `kind` a bank container holds.
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

--- What wiring `fullType` into a bank takes (Specs.wiring), with the Electricity level and XP
--- filled in, or nil if it is no part.
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
        wiring.xp = Specs.inverters[fullType].wireXp
    end
    return wiring
end

local function notBroken(item)
    return not item:isBroken()
end

--- Whether the character carries a working tool with ItemTag field `tag`.
local function hasTool(character, tag)
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
    if countParts(container, kind) >= maxParts(bank.spec, kind) then
        return "Tooltip_RenewableEnergy_NoSlot"
    elseif character:tooDarkToRead() then
        return "Tooltip_RenewableEnergy_TooDark"
    elseif character:getPerkLevel(Perks.Electricity) < wiring.skill then
        return "Tooltip_RenewableEnergy_NeedSkill"
    elseif not hasTool(character, wiring.tool) then
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

--- The status of the bank `isoObject`, or nil.
function PowerBank.statusOf(isoObject)
    return PowerBank.getStatus(isoObject:getX(), isoObject:getY(), isoObject:getZ())
end

--- An object's square as { x, y, z }, the form commands and statuses name places in.
function PowerBank.positionOf(isoObject)
    return { x = isoObject:getX(), y = isoObject:getY(), z = isoObject:getZ() }
end

--- Whether two { x, y, z } places are the same square; false if either is nil.
function PowerBank.samePosition(a, b)
    return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.z == b.z
end

--- Whether a panel at x, y, z is within Specs.sourceReach of `bank`, anything with x, y and z.
function PowerBank.isInReach(bank, x, y, z)
    local reach = Specs.sourceReach
    return IsoUtils.DistanceToSquared(x, y, bank.x, bank.y) <= reach.tiles * reach.tiles
        and math.abs(z - bank.z) <= reach.levels
end

--- Banks a panel on this square may be connected to.
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

--- The bank the panel on this square is connected to, as { x, y, z }, or nil.
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
