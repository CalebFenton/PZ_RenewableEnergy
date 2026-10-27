-- A solar panel's modules as records, the same on a mount item, a placed mount and a module item
-- off its mount: what each is, its condition and seals, and the XP it already taught.

local Specs = require "RenewableEnergy/Specs"
local Sources = require "RenewableEnergy/PowerBank/Sources"

local Panel = {}

-- Item and placed-object modData: the modules a panel mount holds, { { type, condition, repaired,
-- mounted, connected }, ... }. repaired is the module item's repair count (its seals; nil is 0).
-- mounted and connected say the module already taught the XP of its first mounting and its first
-- connection to a bank, so moving modules around teaches nothing new.
Panel.MODULES_KEY = "RenewableEnergy_modules"
-- Solar module item modData: the same two flags, while the module is off its mount. A placed wind
-- charger keeps CONNECTED_ONCE too.
Panel.MOUNTED_ONCE_KEY = "RenewableEnergy_mountedOnce"
Panel.CONNECTED_ONCE_KEY = "RenewableEnergy_connectedOnce"

function Panel.copyModules(modules)
    local copy = {}
    for i, module in ipairs(modules) do
        copy[i] = { type = module.type, condition = module.condition, repaired = module.repaired, mounted = module.mounted,
            connected = module.connected }
    end
    return copy
end

--- The modules a panel holds, as a fresh list of module records: what the item or placed object
--- `holder` recorded under MODULES_KEY or, without a record (a mount spawned by debug), the `mount`
--- kind's full load of factory modules at full condition.
function Panel.modulesOf(holder, mount)
    local recorded = holder:getModData()[Panel.MODULES_KEY]
    local modules = type(recorded) == "table" and Panel.copyModules(recorded) or {}
    if #modules == 0 then
        for i = 1, Specs.mounts[mount].modules do
            modules[i] = { type = Specs.factoryModule, condition = 100 }
        end
    end
    return modules
end

--- The placed panel's module records (Panel.modulesOf), or nil for an object that is no panel.
function Panel.placedModules(panel)
    local kind = Sources.kindOf(panel)
    return Sources.familyOf(kind) == "panel" and Panel.modulesOf(panel, kind) or nil
end

--- The module record of a solar module item: its seals (vanilla's repair count) go with it.
function Panel.moduleRecord(item)
    local data = item:getModData()
    return { type = item:getFullType(), condition = item:getCondition(), repaired = item:getHaveBeenRepaired(),
        mounted = data[Panel.MOUNTED_ONCE_KEY] == true, connected = data[Panel.CONNECTED_ONCE_KEY] == true }
end

--- The watts a module of `fullType` makes in full sun at `condition`, on a mount or a trailer
--- alike; 0 for a type that is no module.
function Panel.moduleWatts(fullType, condition)
    local spec = Specs.modules[fullType]
    return spec and spec.watts * condition / 100 or 0
end

--- Marks a solar module item with its record's seals and flags, as it comes off a mount.
function Panel.markModule(item, module)
    item:setHaveBeenRepaired(module.repaired or 0)
    local data = item:getModData()
    data[Panel.MOUNTED_ONCE_KEY] = module.mounted or nil
    data[Panel.CONNECTED_ONCE_KEY] = module.connected or nil
end

return Panel
