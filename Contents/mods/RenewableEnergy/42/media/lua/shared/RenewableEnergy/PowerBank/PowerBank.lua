-- Battery banks as both sides see them: what an object is, what a bank holds and what it may
-- take, the sources connected to it, and the bank's summary and status as the server last
-- reported them. What each kind of source is lives in RenewableEnergy.Sources.
--
-- The server and client bank systems add their own functions to this table. Both register a Global
-- Object System under SYSTEM_NAME, which keeps each bank's state while its chunk is unloaded and
-- copies its small `summary` to every client; the whole `status` goes only to players watching it.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
local Materials = require "cf_commonlib/Materials"
local Squares = require "cf_commonlib/Squares"

RenewableEnergy = RenewableEnergy or {}
local PowerBank = {}
RenewableEnergy.PowerBank = PowerBank

local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites

PowerBank.SYSTEM_NAME = "renewable_energy_powerbank"
-- The sendServerCommand module and command that carry a bank's status to the players watching it.
PowerBank.COMMAND_MODULE, PowerBank.STATUS_COMMAND = "RenewableEnergyBankStatus", "status"
PowerBank.WIRE = "Base.ElectricWire"
PowerBank.SCRAP = "Base.ElectronicsScrap"
-- Item modData: the item was wired into a bank once, which taught its Electricity XP.
PowerBank.WIRED_ONCE_KEY = "RenewableEnergy_wiredOnce"
-- Item and placed-object modData: the modules a panel mount holds, { { type, condition, repaired,
-- mounted, connected }, ... }. repaired is the module item's repair count (its seals; nil is 0).
-- mounted and connected say the module already taught the XP of its first mounting and its first
-- connection to a bank, so moving modules around teaches nothing new.
PowerBank.MODULES_KEY = "RenewableEnergy_modules"
-- Solar module item modData: the same two flags, while the module is off its mount. A placed wind
-- charger keeps CONNECTED_ONCE too.
PowerBank.MOUNTED_ONCE_KEY = "RenewableEnergy_mountedOnce"
PowerBank.CONNECTED_ONCE_KEY = "RenewableEnergy_connectedOnce"

-- The longest name a bank takes.
PowerBank.NAME_LENGTH = 32

-- Placed bank sprite, in any facing or fixed (Sprites.fixedTiles), to its Specs.banks row and the
-- item it is.
local BANKS_BY_SPRITE = {}
for fullType, bank in pairs(Specs.banks) do
    for _, name in pairs(Sprites[bank.sprite]) do
        BANKS_BY_SPRITE[name] = { fullType = fullType, spec = bank }
    end
end
for fixed, twin in pairs(Sprites.fixedTiles) do
    BANKS_BY_SPRITE[fixed] = BANKS_BY_SPRITE[twin]
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
function PowerBank.findOn(square)
    return Squares.findObjectOn(square, PowerBank.isBank)
end

function PowerBank.copyModules(modules)
    local copy = {}
    for i, module in ipairs(modules) do
        copy[i] = { type = module.type, condition = module.condition, repaired = module.repaired, mounted = module.mounted,
            connected = module.connected }
    end
    return copy
end

--- The modules a panel holds, as a fresh list of module records: what the item or placed object
--- `holder` recorded under MODULES or, without a record (a mount spawned by debug), the `mount`
--- kind's full load of factory modules at full condition.
function PowerBank.modulesOf(holder, mount)
    local recorded = holder:getModData()[PowerBank.MODULES_KEY]
    local modules = type(recorded) == "table" and PowerBank.copyModules(recorded) or {}
    if #modules == 0 then
        for i = 1, Specs.mounts[mount].modules do
            modules[i] = { type = Specs.factoryModule, condition = 100 }
        end
    end
    return modules
end

--- The module record of a solar module item: its seals (vanilla's repair count) go with it.
function PowerBank.moduleRecord(item)
    local data = item:getModData()
    return { type = item:getFullType(), condition = item:getCondition(), repaired = item:getHaveBeenRepaired(),
        mounted = data[PowerBank.MOUNTED_ONCE_KEY] == true, connected = data[PowerBank.CONNECTED_ONCE_KEY] == true }
end

--- The watts a module of `fullType` makes in full sun at `condition`, on a mount or a trailer
--- alike; 0 for a type that is no module.
function PowerBank.moduleWatts(fullType, condition)
    local spec = Specs.modules[fullType]
    return spec and spec.watts * condition / 100 or 0
end

--- Marks a solar module item with its record's seals and flags, as it comes off a mount.
function PowerBank.markModule(item, module)
    item:setHaveBeenRepaired(module.repaired or 0)
    local data = item:getModData()
    data[PowerBank.MOUNTED_ONCE_KEY] = module.mounted or nil
    data[PowerBank.CONNECTED_ONCE_KEY] = module.connected or nil
end

--- Where a bank may stand: inside a building, out of the weather. Returns true, or false and
--- the translation key of the reason.
function PowerBank.canPlaceBank(square)
    if square and square:getRoom() ~= nil and not square:isOutside() then
        return true
    end
    return false, "Tooltip_RenewableEnergy_BankIndoorsOnly"
end

--- Every kind of bank part: its item types (each type's Specs row), the bank record field that
--- lists the bank's parts of the kind (Bank.SAVED_FIELDS), the Specs.banks field that caps how
--- many a bank takes, and whether Electronics Scrap repairs it.
PowerBank.PARTS = {
    battery = { types = Specs.batteries, field = "batteries", max = "maxBatteries" },
    inverter = { types = Specs.inverters, field = "inverters", max = "maxInverters", repairable = true },
    charger = { types = { [Specs.charger] = {} }, field = "chargers", max = "maxChargers" },
    controller = { types = { [Specs.controller] = {} }, field = "controllers", max = "maxControllers", repairable = true },
}

-- Item type to { kind, spec }: its PARTS kind and its row of the kind's types.
local PART_TYPES = {}
for kind, part in pairs(PowerBank.PARTS) do
    for fullType, spec in pairs(part.types) do
        PART_TYPES[fullType] = { kind = kind, spec = spec }
    end
end

--- What kind of bank part an item type is (a PowerBank.PARTS key), or nil.
function PowerBank.partKind(fullType)
    local part = fullType and PART_TYPES[fullType]
    return part and part.kind
end

--- Whether an item type is a bank part that Electronics Scrap repairs.
function PowerBank.isRepairable(fullType)
    local kind = PowerBank.partKind(fullType)
    return kind ~= nil and PowerBank.PARTS[kind].repairable == true
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

--- What wiring `fullType` into a bank takes: its kind's Specs.wiring, with what its own type's row
--- says over it (an inverter's skill and xp), or nil if it is no part.
function PowerBank.wiringFor(fullType)
    local part = fullType and PART_TYPES[fullType]
    if not part then
        return nil
    end
    local wiring = {}
    for key, value in pairs(Specs.wiring[part.kind]) do
        wiring[key] = value
    end
    for key, value in pairs(part.spec.wiring or {}) do
        wiring[key] = value
    end
    return wiring
end

--- The bank container's filter (ItemContainer.isItemAllowed). Parts go in only by being wired
--- in, which moves them without asking the filter, so it refuses every transfer.
function PowerBank.acceptItem(container, item)
    return false
end

--- Gives a bank's container its filter (RenewableEnergy.adoptContainer).
function PowerBank.adoptContainer(container)
    RenewableEnergy.adoptContainer(container, "RenewableEnergy.PowerBank.acceptItem")
end

--- What a wiring job of `wiring` (as Specs.wiring's) takes, as a materials list
--- (cf_commonlib's Materials): its Electricity level, tools, wire and scrap, leaving out what it
--- takes none of.
function PowerBank.wiringMaterials(wiring)
    local list = {}
    if wiring.skill > 0 then
        table.insert(list, { perk = "Electricity", need = wiring.skill })
    end
    for _, tool in ipairs(wiring.tools) do
        table.insert(list, tool)
    end
    if wiring.wire > 0 then
        table.insert(list, { item = PowerBank.WIRE, need = wiring.wire })
    end
    if wiring.scrap > 0 then
        table.insert(list, { item = PowerBank.SCRAP, need = wiring.scrap })
    end
    return list
end

--- What a wiring job of `wiring` (as Specs.wiring's) takes of `character`, for
--- Materials.firstUnmet.
function PowerBank.wiringNeeds(character, wiring)
    return Materials.needs(character, PowerBank.wiringMaterials(wiring))
end

--- What undoing a wiring job of `wiring` takes of `character`: its tools, as vanilla takes a car
--- part's install tools to uninstall it. For Materials.firstUnmet.
function PowerBank.unwiringNeeds(character, wiring)
    return Materials.needs(character, wiring.tools)
end

--- How many more parts of `kind` (a PARTS key) the bank `bank` takes; 0 for no bank.
function PowerBank.freePartSlots(bank, kind)
    local tier = PowerBank.bankOfSprite(Sprites.nameOf(bank))
    local container = tier and bank:getContainer()
    if not container then
        return 0
    end
    return math.max(0, tier.spec[PowerBank.PARTS[kind].max] - countParts(container, kind))
end

--- What keeps anyone from wiring `item` into the bank `bank` now whatever they carry, as a
--- translation key, or nil. The light is the action's to check (RenewableEnergyAction.needsLight):
--- only the player's own side can see it (IsoPlayer.tooDarkToRead is false for a remote player).
function PowerBank.wiringBlocker(bank, item)
    local kind = instanceof(item, "InventoryItem") and PowerBank.partKind(item:getFullType())
    if not (kind and PowerBank.bankOfSprite(Sprites.nameOf(bank)) and bank:getContainer()) then
        return "Tooltip_RenewableEnergy_NotAPart"
    elseif PowerBank.freePartSlots(bank, kind) == 0 then
        return "Tooltip_RenewableEnergy_NoSlot"
    end
    return nil
end

--- Why `character` can't wire `item` into the bank `bank` now, or nil if they can: what
--- wiringBlocker says, else the kind of the first of the part's wiringNeeds they are short of.
function PowerBank.wiringRefusal(character, bank, item)
    return PowerBank.wiringBlocker(bank, item)
        or Materials.unmetKind(PowerBank.wiringNeeds(character, PowerBank.wiringFor(item:getFullType())))
end

-- What repairing an inverter or controller takes, as a materials list (cf_commonlib's Materials).
local REPAIR = { { perk = "Electricity", need = Specs.partRepair.skill }, { item = PowerBank.SCRAP, need = 1 } }

--- What repairing an inverter or controller uses up of `character`. Authority only.
function PowerBank.consumeRepair(character)
    Materials.consume(character, REPAIR)
end

--- What repairing an inverter or controller takes of `character`, for Materials.firstUnmet.
function PowerBank.repairNeeds(character)
    return Materials.needs(character, REPAIR)
end

--- What keeps anyone from repairing `item` with Electronics Scrap now whatever they carry, as a
--- translation key, or nil. The light is the action's to check, as for wiringBlocker.
function PowerBank.repairBlocker(item)
    if not (instanceof(item, "InventoryItem") and PowerBank.isRepairable(item:getFullType())) then
        return "Tooltip_RenewableEnergy_NotRepairable"
    elseif item:getCondition() >= item:getConditionMax() then
        return "Tooltip_RenewableEnergy_NoRepairNeeded"
    end
    return nil
end

--- Why `character` can't repair the inverter or controller `item` now, or nil if they can: what
--- repairBlocker says, else the kind of the first of repairNeeds they are short of.
function PowerBank.repairRefusal(character, item)
    return PowerBank.repairBlocker(item) or Materials.unmetKind(PowerBank.repairNeeds(character))
end

--- What keeps anyone from unwiring `item` from the bank `bank` now whatever they carry, as a
--- translation key, or nil: it must be a part in the bank's container. The light is the action's
--- to check, as for wiringBlocker.
function PowerBank.unwiringBlocker(bank, item)
    local container = PowerBank.isBank(bank) and bank:getContainer()
    if not (container and instanceof(item, "InventoryItem") and container:contains(item)
        and PowerBank.partKind(item:getFullType())) then
        return "Tooltip_RenewableEnergy_NotAPart"
    end
    return nil
end

--- Why `character` can't unwire `item` from the bank `bank` now, or nil if they can: what
--- unwiringBlocker says, else the kind of the first of the part's unwiringNeeds they are short of.
function PowerBank.unwiringRefusal(character, bank, item)
    return PowerBank.unwiringBlocker(bank, item)
        or Materials.unmetKind(PowerBank.unwiringNeeds(character, PowerBank.wiringFor(item:getFullType())))
end

--- The failsafe's thresholds, in percent of a bank's charge: below `start` it starts its generator,
--- at `stop` it stops it (the FailsafeStartCharge and FailsafeStopCharge options).
function PowerBank.failsafeRange()
    local options = SandboxVars.RenewableEnergy
    return options.FailsafeStartCharge, options.FailsafeStopCharge
end

--- Why the bank whose summary or status is `summary` can't be switched `on` (true) or off now, or
--- nil: "already on" or "already off", or, switching on, no working inverter to carry a load or
--- no battery capacity to carry it from.
function PowerBank.switchRefusal(summary, on)
    if summary.on == on then
        return on and "already on" or "already off"
    elseif on and (summary.limitW or 0) <= 0 then
        return "Tooltip_RenewableEnergy_NoInverter"
    elseif on and (summary.capacityWh or 0) <= 0 then
        return "Tooltip_RenewableEnergy_NoBatteries"
    end
    return nil
end

--- Why `name` can't name a bank, or nil: a name is one line of at most NAME_LENGTH characters,
--- which the rename box holds it to.
function PowerBank.nameRefusal(name)
    if #name > PowerBank.NAME_LENGTH then
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
function PowerBank.connectRefusal(character, bank, summary, connect)
    if bank:isConnected() == connect then
        return connect and "already connected" or "already disconnected"
    elseif connect and character:getPerkLevel(Perks.Electricity) < 3 and not character:isRecipeActuallyKnown("Generator") then
        return "ContextMenu_GeneratorPlugTT"
    elseif not connect and summary.on then
        return "already on"
    end
    return nil
end

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

local function recordAt(x, y, z)
    local sys = system()
    local globalObject = sys and sys.system:getObjectAt(x, y, z)
    return globalObject and globalObject:getModData()
end

--- What every client knows of the bank at x, y, z (see Bank:buildSummary), or nil.
function PowerBank.summaryAt(x, y, z)
    local bank = recordAt(x, y, z)
    return bank and bank.summary
end

--- The summary of the bank `isoObject`, or nil.
function PowerBank.summaryOf(isoObject)
    return PowerBank.summaryAt(isoObject:getX(), isoObject:getY(), isoObject:getZ())
end

--- The whole status of the bank `isoObject` (see Bank:buildStatus), or nil. It reaches only the
--- players watching it, and the authority keeps it only while someone does.
function PowerBank.statusOf(isoObject)
    local bank = recordAt(isoObject:getX(), isoObject:getY(), isoObject:getZ())
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
