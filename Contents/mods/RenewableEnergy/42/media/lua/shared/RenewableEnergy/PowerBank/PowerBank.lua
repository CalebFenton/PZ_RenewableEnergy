-- Battery banks as both sides see them: what an object is, what a bank holds and what it may
-- take, the sources connected to it, and the bank's summary and status as the server last
-- reported them. What each kind of source is lives in RenewableEnergy.Sources.
--
-- The server runs the banks (server/RenewableEnergy/PowerBank) and adds perform(), place() and
-- remove() to this table; the client adds watchStatus() and unwatchStatus() (client/
-- RenewableEnergy/PowerBank/ClientBankSystem.lua). Both register a Global Object System under
-- SYSTEM_NAME, which keeps each bank's state while its chunk is unloaded and copies its small
-- `summary` to every client. The whole `status` goes only to the players watching it.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"

RenewableEnergy = RenewableEnergy or {}
local PowerBank = {}
RenewableEnergy.PowerBank = PowerBank

local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites

PowerBank.SYSTEM_NAME = "renewable_energy_powerbank"
-- The sendServerCommand module that carries a bank's status to the players watching it.
PowerBank.STATUS_MODULE = "RenewableEnergyBankStatus"
PowerBank.WIRE = "Base.ElectricWire"
PowerBank.SCRAP = "Base.ElectronicsScrap"
-- Item modData: the item was wired into a bank once, which taught its Electricity XP.
PowerBank.WIRED_ONCE = "RenewableEnergy_wiredOnce"
-- Item and placed-object modData: the modules a panel mount holds, { { type, condition, mounted,
-- connected }, ... }. mounted and connected say the module already taught the XP of its first
-- mounting and its first connection to a bank, so moving modules around teaches nothing new.
PowerBank.MODULES = "RenewableEnergy_modules"
-- Solar module item modData: the same two flags, while the module is off its mount. A placed wind
-- charger keeps CONNECTED_ONCE too.
PowerBank.MOUNTED_ONCE = "RenewableEnergy_mountedOnce"
PowerBank.CONNECTED_ONCE = "RenewableEnergy_connectedOnce"

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

--- The bank a placed sprite is: { fullType, spec }, or nil.
function PowerBank.bankOfSprite(name)
    return name and BANKS_BY_SPRITE[name]
end

--- Whether an object is a working bank: a bank tile turned into the generator that powers
--- the squares around it.
function PowerBank.isBank(isoObject)
    return instanceof(isoObject, "IsoGenerator") and PowerBank.bankOfSprite(Sprites.nameOf(isoObject)) ~= nil
end

--- The working bank on a square, or nil.
function PowerBank.bankOn(square)
    return RenewableEnergy.findObjectOn(square, PowerBank.isBank)
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

--- The watts a module of `fullType` makes in full sun at `condition`, on a mount or a trailer
--- alike; 0 for a type that is no module.
function PowerBank.moduleWatts(fullType, condition)
    local spec = Specs.modules[fullType]
    return spec and spec.watts * condition / 100 or 0
end

--- Marks a solar module item with its record's flags, as it comes off a mount.
function PowerBank.markModule(item, module)
    local data = item:getModData()
    data[PowerBank.MOUNTED_ONCE] = module.mounted or nil
    data[PowerBank.CONNECTED_ONCE] = module.connected or nil
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

--- The bank container's filter (ItemContainer.isItemAllowed). Parts go in only by being wired
--- in, which moves them without asking the filter, so it refuses every transfer.
function PowerBank.acceptItem(container, item)
    return false
end

--- Gives a bank's container its filter, acceptItem by the dotted path the game resolves. The
--- filter is neither saved nor sent, so every side sets it on its own copy.
function PowerBank.adoptContainer(container)
    if container and container:getAcceptItemFunction() == nil then
        container:setAcceptItemFunction("RenewableEnergy.PowerBank.acceptItem")
    end
end

-- Adds a need to a list for RenewableEnergy.firstUnmet, unless nothing of it is needed.
local function addNeed(needs, need)
    if need.need > 0 then
        table.insert(needs, need)
    end
end

--- What a wiring job of `wiring` (as Specs.wiring's) takes of `character`
--- (RenewableEnergy.firstUnmet): the Electricity level, the tool, Electric Wire and Electronics
--- Scrap.
function PowerBank.jobNeeds(character, wiring)
    local inventory = character:getInventory()
    local needs = {}
    addNeed(needs, { kind = "skill", perk = Perks.Electricity, have = character:getPerkLevel(Perks.Electricity), need = wiring.skill })
    addNeed(needs, { kind = "tool", tool = wiring.tool,
        have = RenewableEnergy.hasWorkingTool(character, ItemTag[wiring.tool]) and 1 or 0, need = 1 })
    addNeed(needs, { kind = "wire", item = PowerBank.WIRE, have = inventory:getCountTypeRecurse(PowerBank.WIRE), need = wiring.wire })
    addNeed(needs, { kind = "scrap", item = PowerBank.SCRAP, have = inventory:getCountTypeRecurse(PowerBank.SCRAP), need = wiring.scrap })
    return needs
end

--- What wiring a part of type `fullType` into a bank takes of `character`
--- (RenewableEnergy.firstUnmet): the Electricity level, the tool, Electric Wire and Electronics
--- Scrap.
function PowerBank.wiringNeeds(character, fullType)
    return PowerBank.jobNeeds(character, PowerBank.wiringFor(fullType))
end

--- What keeps `character` from wiring `item` into the bank `bankObject` now whatever they
--- carry, as a translation key, or nil.
function PowerBank.wiringBlocker(character, bankObject, item)
    local bank = PowerBank.bankOfSprite(Sprites.nameOf(bankObject))
    local container = bank and bankObject:getContainer()
    local kind = instanceof(item, "InventoryItem") and PowerBank.partKind(item:getFullType())
    if not (container and kind) then
        return "Tooltip_RenewableEnergy_NotAPart"
    elseif countParts(container, kind) >= maxParts(bank.spec, kind) then
        return "Tooltip_RenewableEnergy_NoSlot"
    elseif character:tooDarkToRead() then
        return "Tooltip_RenewableEnergy_TooDark"
    end
    return nil
end

--- Why `character` can't wire `item` into the bank `bankObject` now, or nil if they can: what
--- wiringBlocker says, else the kind of the first of wiringNeeds they are short of.
function PowerBank.wiringRefusal(character, bankObject, item)
    local blocker = PowerBank.wiringBlocker(character, bankObject, item)
    if blocker then
        return blocker
    end
    local short = RenewableEnergy.firstUnmet(PowerBank.wiringNeeds(character, item:getFullType()))
    return short and short.kind
end

--- What repairing an inverter or controller takes of `character` (RenewableEnergy.firstUnmet):
--- the Electricity level and one Electronics Scrap.
function PowerBank.repairNeeds(character)
    local needs = {}
    addNeed(needs, { kind = "skill", perk = Perks.Electricity, have = character:getPerkLevel(Perks.Electricity), need = Specs.partRepair.skill })
    addNeed(needs, { kind = "scrap", item = PowerBank.SCRAP, have = character:getInventory():getCountTypeRecurse(PowerBank.SCRAP), need = 1 })
    return needs
end

--- What keeps `character` from repairing `item` with Electronics Scrap now whatever they carry,
--- as a translation key, or nil.
function PowerBank.repairBlocker(character, item)
    local kind = instanceof(item, "InventoryItem") and PowerBank.partKind(item:getFullType())
    if kind ~= "inverter" and kind ~= "controller" then
        return "Tooltip_RenewableEnergy_NotRepairable"
    elseif item:getCondition() >= item:getConditionMax() then
        return "Tooltip_RenewableEnergy_NoRepairNeeded"
    elseif character:tooDarkToRead() then
        return "Tooltip_RenewableEnergy_TooDark"
    end
    return nil
end

--- Why `character` can't repair the inverter or controller `item` now, or nil if they can: what
--- repairBlocker says, else the kind of the first of repairNeeds they are short of.
function PowerBank.repairRefusal(character, item)
    local blocker = PowerBank.repairBlocker(character, item)
    if blocker then
        return blocker
    end
    local short = RenewableEnergy.firstUnmet(PowerBank.repairNeeds(character))
    return short and short.kind
end

-- Banks as either side knows them ---------------------------------------------------------

-- The Global Object System of this side: the server's in single player, where both exist
-- and the server's is the live one.
local function system()
    return PowerBank.serverSystem or PowerBank.clientSystem
end

--- Calls `fn(bank)` for each bank record this side has, until it returns true.
function PowerBank.eachBank(fn)
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

--- What every client knows of the bank at x, y, z (see Bank:buildSummary), or nil.
function PowerBank.getSummary(x, y, z)
    local bank = bankAt(x, y, z)
    return bank and bank.summary
end

--- The summary of the bank `isoObject`, or nil.
function PowerBank.summaryOf(isoObject)
    return PowerBank.getSummary(isoObject:getX(), isoObject:getY(), isoObject:getZ())
end

--- The whole status of the bank `isoObject` (see Bank:buildStatus), or nil. It reaches only the
--- players watching it, and the authority keeps it only while someone does.
function PowerBank.statusOf(isoObject)
    local bank = bankAt(isoObject:getX(), isoObject:getY(), isoObject:getZ())
    return bank and bank.status
end

--- An object's square as { x, y, z }, the form commands and statuses name places in.
function PowerBank.positionOf(isoObject)
    return { x = isoObject:getX(), y = isoObject:getY(), z = isoObject:getZ() }
end

--- Whether two { x, y, z } places are the same square; false if either is nil.
function PowerBank.samePosition(a, b)
    return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.z == b.z
end

--- Whether `position` is a { x, y, z } place, as a command argument from a client must be.
function PowerBank.isPosition(position)
    return type(position) == "table" and type(position.x) == "number" and type(position.y) == "number"
        and type(position.z) == "number"
end

--- Whether a source at x, y, z is within Specs.sourceReach of `bank`, anything with x, y and z.
function PowerBank.isInReach(bank, x, y, z)
    local reach = Specs.sourceReach
    return IsoUtils.DistanceToSquared(x, y, bank.x, bank.y) <= reach.tiles * reach.tiles
        and math.abs(z - bank.z) <= reach.levels
end

--- The bank the source on this square is connected to, as { x, y, z }, or nil. The authority
--- reads the bank's own list of sources; a client has only the summary the server last sent.
function PowerBank.bankOfSource(x, y, z)
    local found
    local authority = PowerBank.serverSystem ~= nil
    PowerBank.eachBank(function(bank)
        local sources = authority and bank.sources or (bank.summary and bank.summary.sources)
        for _, source in ipairs(sources or {}) do
            if source.x == x and source.y == y and source.z == z then
                found = { x = bank.x, y = bank.y, z = bank.z }
                return true
            end
        end
    end)
    return found
end

--- The bank the placed source `isoObject` is connected to, as { x, y, z }, or nil.
function PowerBank.connectedBank(isoObject)
    return PowerBank.bankOfSource(isoObject:getX(), isoObject:getY(), isoObject:getZ())
end

return PowerBank
