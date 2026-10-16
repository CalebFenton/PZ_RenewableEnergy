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
--- path: "barrel.steel", "standard"), built as the build menu builds it on `opts.square`, else on
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
    T.waitForCopy(function()
        local object = T.recordObject(handle)
        handle.object = object and owner.summaryOf(object) and object or nil
        return handle.object ~= nil
    end, "this client's copy of the " .. kind)
    T.step(function() T.need(self, handle.object, "this client's copy of the " .. kind) end)
    return handle
end

--- Queues setting the record's saved fields `fields` as of now.
function T.setRecord(self, handle, fields)
    T.server(self, "recordSet", T.recordArgs(handle, { fields = fields }))
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

--- Queues a wait until this client's summary of the record satisfies `check(summary)`.
function T.waitForSummary(handle, check, what)
    T.waitForCopy(function()
        local summary = T.recordSummary(handle)
        return summary ~= nil and check(summary)
    end, what)
end

--- Queues the gas job `job` of `feature` ("digester", "gasifier", "heater", "kit") at the tile of
--- `handle`, as its menu queues it (RenewableEnergyGasAction). `item` and `other` (a handle, for
--- the far end of a gas line) may be functions, called when the job is queued, for what the queue
--- gives or builds first.
function T.gasJob(self, feature, handle, job, item, other)
    T.doJob(self, handle.square, function()
        if type(item) == "function" then
            item = item()
        end
        if type(other) == "function" then
            other = other()
        end
        return RenewableEnergyGasAction:new(T.player(), feature, job, handle.object, item, other and other.object)
    end)
end

-- Digesters ------------------------------------------------------------------------------------

--- Saved fields of a started, mature digester, past its startup and settled down, holding
--- `potential`.
function T.matureDigester(potential)
    return { fed = true, started = true, gasHours = 1000, potential = potential, temp = 30, acid = 0, sour = false, sludge = 0 }
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

--- Queues setting the generator's fuel and switching it (`fields`: { fuel, running }).
function T.setGenerator(self, generator, fields)
    local args = T.at(generator)
    args.fuel, args.running = fields.fuel, fields.running
    T.server(self, "generatorSet", args)
end

--- Queues the gas pass, as though `hours` had passed since the generator's last.
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
