require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/GasLine/GasKit"

-- Fixtures of the biogas and gas tests (RenewableEnergyTestsBiogas.lua, RenewableEnergyTestsGas.lua),
-- added to RenewableEnergyTest. Digesters and gasifiers are records of the Global Object System on
-- the authority; the server handlers (RenewableEnergyTestServerBiogas.lua, ...Gas.lua) build, drive
-- and read them by kind and place. A record handle is { x, y, z, square, kind }, and `object` is
-- this client's copy of its tile once it has its summary. Reads land in self.reads[label].

local T = RenewableEnergyTest
local Digester = RenewableEnergy.Digester

-- What each record kind's tile and summary are on this client.
local KINDS = {
    digester = { owner = RenewableEnergy.Digester, isObject = RenewableEnergy.Digester.isDigester },
    gasifier = { owner = RenewableEnergy.Gasifier, isObject = RenewableEnergy.Gasifier.isGasifier },
}

--- The server handlers' args for the record `handle`, with `extra`'s fields added.
function T.recordArgs(handle, extra)
    local args = T.at(handle)
    args.kind = handle.kind
    for key, value in pairs(extra or {}) do
        args[key] = value
    end
    return args
end

--- This client's copy of the record `handle`'s tile, or nil.
function T.recordObject(handle)
    return RenewableEnergy.findObjectOn(getSquare(handle.x, handle.y, handle.z), KINDS[handle.kind].isObject)
end

--- Queues a record of `kind` ("digester", "gasifier") on the Sprites[kind] tile `tile` (a dotted
--- path: "barrel.MetalDrum", "standard"), built as the build menu builds it on `opts.square`, else on
--- a free square (outdoors unless `opts.indoors`) near `opts.near`, at least `opts.minDistance`
--- away. Returns its handle, or nil when there is no square.
function T.placeRecord(self, kind, tile, opts)
    opts = opts or {}
    local square = opts.square or T.square(self, { indoors = opts.indoors, near = opts.near, minDistance = opts.minDistance },
        "a free square for a " .. kind)
    if not square then return nil end
    local handle = T.at(square)
    handle.square, handle.kind = square, kind
    T.server(self, "recordPlace", T.recordArgs(handle, { tile = tile }))
    local owner = KINDS[kind].owner
    T.waitFor(self, function()
        local object = T.recordObject(handle)
        handle.object = object and owner.summaryOf(object) and object or nil
        return handle.object ~= nil
    end, "this client's copy of the " .. kind)
    return handle
end

--- Queues setting the record's saved fields `fields` as of now, and those of `ago` ({ [field] =
--- hours }) to the world hour that many hours before the server runs it.
function T.setRecord(self, handle, fields, ago)
    T.server(self, "recordSet", T.recordArgs(handle, { fields = fields, ago = ago }))
end

--- Queues putting `items` in the record's containers as a player's transfer does: { hopper = { {
--- type, count, rotten } }, filter = ... }.
function T.fillRecord(self, handle, items)
    T.server(self, "recordFill", T.recordArgs(handle, { items = items }))
end

--- Queues the record's own pass, as though `hours` had passed since its last; its state lands in
--- self.reads[label] if given.
function T.ageRecord(self, handle, hours, label)
    T.read(self, "recordAge", T.recordArgs(handle, { hours = hours }), label)
end

--- Queues a read of the record's state (the server's Helpers.recordState) into self.reads[label].
function T.readRecord(self, handle, label)
    T.read(self, "recordRead", T.recordArgs(handle), label)
end

--- Queues taking the record's tile away the way the game does (a sledgehammer, a pickup).
function T.removeRecord(self, handle)
    T.server(self, "recordRemove", T.recordArgs(handle))
end

--- Queues the server handler `name` with `args` and puts its answer in self.reads[label], if given.
function T.read(self, name, args, label)
    T.server(self, name, args)
    if label then
        T.step(function()
            self.reads = self.reads or {}
            self.reads[label] = self.server[name]
        end)
    end
end

--- The record's summary as this client has it, or nil.
function T.recordSummary(handle)
    return handle.object and KINDS[handle.kind].owner.summaryOf(handle.object)
end

--- Queues a wait until this client's summary of the record satisfies `check(summary)`; missing
--- `what` if it never does.
function T.waitForSummary(self, handle, check, what)
    T.waitFor(self, function()
        local summary = T.recordSummary(handle)
        return summary ~= nil and check(summary)
    end, what)
end

--- Queues the gas job `job` of `feature` ("digester", "gasifier", "heater", "kit") at the tile of
--- `handle`, as its menu queues it (RenewableEnergyGasAction). `with` is what the job works with:
--- the bag, tank or container it fills, or a record handle at the far end of a gas line; or a
--- function, called when the job is queued, returning one, for what the queue gives first.
function T.gasJob(self, feature, handle, job, with)
    T.doJob(self, handle.square, function()
        local what = type(with) == "function" and with() or with
        if type(what) == "table" then
            what = what.object
        end
        return RenewableEnergyGasAction:new(T.player(), feature, job, handle.object, what)
    end)
end

-- Materials -------------------------------------------------------------------------------------

-- The full type a material (RenewableEnergy.Materials) names, if it is an item.
local function materialItem(material)
    return not material.perk and not material.water and material.item or nil
end

--- Queues giving the character what the materials list `list` (RenewableEnergy.Materials) asks
--- for, into self.items[name]: its skill levels, and each item, tool or tagged item at its count.
--- An item counted in uses comes as one whole item, which holds more uses than any job takes.
--- Water is the test's own to pour.
function T.giveMaterials(self, name, list)
    local items = {}
    for _, material in ipairs(list) do
        if material.perk then
            T.setPerk(self, Perks[material.perk], material.need)
        elseif materialItem(material) then
            table.insert(items, { type = material.item, count = not material.uses and material.need or 1 })
        end
    end
    T.give(self, name, items)
end

--- Queues a count, into self.counts[label], of the items the materials list `list` names.
function T.countMaterials(self, label, list)
    local types = {}
    for _, material in ipairs(list) do
        if materialItem(material) then
            table.insert(types, material.item)
        end
    end
    T.count(self, label, types)
end

--- Expects the count `label` (T.countMaterials) to show what `list` uses up gone, and the tools
--- and kept items it only needs still carried. Items counted in uses aren't checked.
function T.expectMaterialsUsed(self, label, list, job)
    local counts = self.counts[label] or {}
    for _, material in ipairs(list) do
        local fullType = materialItem(material)
        if fullType and not material.uses then
            local left = counts[fullType] or 0
            if material.tool or material.keep then
                T.expect(left >= 1, job .. " used up its " .. fullType)
            else
                T.expect(left == 0, job .. " left " .. left .. " " .. fullType .. " it takes")
            end
        end
    end
end

-- Digesters ------------------------------------------------------------------------------------

--- Saved fields of a started, mature digester of tier `tier`, past its startup and settled down,
--- holding its tier's potential cap.
function T.matureDigester(tier)
    return { fed = true, started = true, gasHours = 1000, potential = Digester.TIERS[tier].potentialCap, temp = 30,
        acid = 0, sour = false, sludge = 0 }
end

--- The same, soured: acid at twice its limit, so the passes that run meanwhile keep it sour.
function T.sourDigester(tier)
    local state = T.matureDigester(tier)
    state.sour, state.acid = true, 2 * Digester.ACID_LIMIT * state.potential
    return state
end

--- Queues running the digester for `hours` at the air temperature `air` (°C), without moving the
--- clock, through its own pass (DigesterObject:run).
function T.runDigester(self, handle, hours, air)
    T.server(self, "digesterRun", T.recordArgs(handle, { hours = hours, air = air }))
end

-- Generators -----------------------------------------------------------------------------------

--- Queues a read of the generator `generator` (a T.generator handle) into self.reads[label]:
--- running, fuel, its kit's state, whether the gas pass lists it, its overlays.
function T.readGenerator(self, generator, label)
    T.read(self, "generatorRead", T.at(generator), label)
end

--- Queues pouring `fields.pour` litres into the generator and switching it (`fields.running`).
function T.setGenerator(self, generator, fields)
    local args = T.at(generator)
    args.pour, args.running = fields.pour, fields.running
    T.server(self, "generatorSet", args)
end

--- Queues setting the generator's last gas pass `hours` ago without running one, so the next
--- pass or job bills them.
function T.gasAge(self, generator, hours)
    local args = T.at(generator)
    args.hours = hours
    T.server(self, "gasAge", args)
end

--- Queues the gas pass, as though `hours` had passed since the generator's last, or, with `hours`
--- nil, from its last pass as it stands.
function T.gasPass(self, generator, hours)
    local args = T.at(generator)
    args.hours = hours
    T.server(self, "gasPass", args)
end

--- Queues every kitted generator delivering `watts`, whatever it powers, until the test ends.
function T.gasLoad(self, watts)
    T.server(self, "gasLoad", { watts = watts })
end

-- Reads ------------------------------------------------------------------------------------------

--- Whether a read's `overlays` list `name`.
function T.hasOverlay(read, name)
    for _, overlay in ipairs(read and read.overlays or {}) do
        if overlay == name then
            return true
        end
    end
    return false
end

return T
