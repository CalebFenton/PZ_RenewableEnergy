require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/GasLine/GasKit"
local Squares = require "cf_commonlib/Squares"

-- Fixtures of the biogas, gas line and wood gas tests (RenewableEnergyTestsBiogas*.lua,
-- RenewableEnergyTestsGasLine*.lua, RenewableEnergyTestsWoodGas*.lua) and of the rural find tests'
-- digesters and gasifiers (RenewableEnergyTestsRuralFinds.lua), added to RenewableEnergyTest.
-- Digesters and gasifiers are records of the Global Object System on the authority; the server
-- handlers (RenewableEnergyTestServerBiogas.lua, ...Gas.lua) build, drive and read them by kind
-- and place. A record handle is { x, y, z, square, kind }, and `object` is this client's copy of
-- its tile once it has its summary. Reads land in self.reads[label].

local T = RenewableEnergyTest
local Digester, GasKit, GasifierJobs = RenewableEnergy.Digester, RenewableEnergy.GasKit, RenewableEnergy.GasifierJobs

-- What a record kind's tile and summary are on this client: the server helper's RECORD_KINDS, whose
-- owner and tile test are shared code. The helper loads after client Lua, so it is required here.
local function kindOf(handle)
    local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
    return Helpers.RECORD_KINDS[handle.kind]
end

--- The server handlers' args for the record `handle`, with `extra`'s fields added.
function T.recordArgs(handle, extra)
    local args = T.at(handle, extra)
    args.kind = handle.kind
    return args
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
    local handle = T.at(square, { square = square, kind = kind })
    T.server(self, "recordPlace", T.recordArgs(handle, { tile = tile }))
    local spec = kindOf(handle)
    local owner = spec.owner()
    T.waitFor(self, function()
        local object = Squares.findObjectOn(getSquare(handle.x, handle.y, handle.z), spec.isObject)
        handle.object = object and owner.summaryOf(object) and object or nil
        return handle.object ~= nil
    end, "this client's copy of the " .. kind)
    return handle
end

--- Queues building a record of `kind` from the build menu's entry of `entity` on a T.buildSite
--- (T.build with `prefer`), waiting for this client's copy of the tile `tile`. Its record lands in
--- self.reads.built, the build in self.build, what is left carried in self.counts.left;
--- T.expectBuilt checks them. Returns the handle, or nil.
function T.buildRecord(self, kind, entity, tile, prefer)
    local square = T.buildSite(self)
    if not square then return nil end
    local handle = T.at(square, { square = square, kind = kind })
    T.server(self, "recordTrack", T.recordArgs(handle))
    self.build = T.build(self, entity, square, prefer, function() return T.objectWithSprite(square, tile) ~= nil end,
        "this client's copy of the " .. tostring(tile) .. " " .. kind)
    if not self.build then return nil end
    T.batch(function()
        T.readRecord(self, handle, "built")
        T.count(self, "left", self.build.types)
    end)
    return handle
end

--- Expects T.buildRecord's build to have built its record on the tile `tile`, and taken what it
--- takes while keeping its tools (T.expectBuildUsed).
function T.expectBuilt(self, tile)
    local built = self.reads.built or {}
    T.expectBuildUsed(self.build, self.counts.left)
    T.expect(built.sprite == tile, "the built tile is " .. tostring(built.sprite) .. ", expected " .. tostring(tile))
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

--- The record's summary as this client has it, or nil.
function T.recordSummary(handle)
    return handle.object and kindOf(handle).owner().summaryOf(handle.object)
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

-- The full type a material (cf_commonlib's Materials) names, if it is an item.
local function materialItem(material)
    return not material.perk and not material.water and material.item or nil
end

--- Queues giving the character what the materials list `list` (cf_commonlib's Materials) asks
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
--- holding its tier's potential cap, with `fields`' fields over them.
function T.matureDigester(tier, fields)
    local state = { fed = true, started = true, gasHours = 1000, potential = Digester.TIERS[tier].potentialCap, temp = 30,
        acid = 0, sour = false, sludge = 0 }
    for key, value in pairs(fields or {}) do
        state[key] = value
    end
    return state
end

--- The same, soured: acid well past its limit, so the passes that run meanwhile keep it sour.
function T.sourDigester(tier, fields)
    local state = T.matureDigester(tier)
    state.sour, state.acid = true, 2 * Digester.ACID_LIMIT * state.potential
    for key, value in pairs(fields or {}) do
        state[key] = value
    end
    return state
end

--- Queues running the digester for `hours` at the air temperature `air` (°C), without moving the
--- clock, through its own pass (DigesterObject:run).
function T.runDigester(self, handle, hours, air)
    T.server(self, "digesterRun", T.recordArgs(handle, { hours = hours, air = air }))
end

--- Queues a wait until this client's summary of the record shows `gas` m³, to the hundredth the
--- summary rounds it to.
function T.waitForGas(self, handle, gas)
    T.waitForSummary(self, handle, function(summary) return math.abs(summary.gas - gas) < 0.005 end,
        "this client's summary of the gas")
end

--- A digester holding `gas` and making none, placed as T.placeRecord's `opts` say: not started, so
--- it neither digests nor, a dome, burns any to keep warm, and only a line takes its gas.
function T.digesterWithGas(self, tile, gas, opts)
    local digester = T.placeRecord(self, "digester", tile, opts)
    if not digester then return nil end
    T.setRecord(self, digester, { gas = gas })
    return digester
end

--- A generator holding `fuel` litres beside a T.digesterWithGas, kitted and on a line to it: the
--- generator's handle and the digester's, or nil.
function T.generatorOnDigester(self, tile, gas, fuel)
    local digester = T.digesterWithGas(self, tile, gas)
    local generator = digester and T.generator(self, { near = digester.square, fuel = fuel })
    if not generator then return nil end
    T.fitAndConnect(self, generator, digester)
    return generator, digester
end

-- Gasifiers ------------------------------------------------------------------------------------

--- Queues an empty-tanked generator, or one with `fuel` litres, and a gasifier of `tier` beside it.
--- Returns the generator and the gasifier's handle, or nil.
function T.gasifierBeside(self, tier, fuel)
    local generator = T.generator(self, { fuel = fuel or 0 })
    if not generator then return nil end
    local square = T.need(self, T.squareBeside(generator.square), "a free square beside the generator")
    local gasifier = square and T.placeRecord(self, "gasifier", tier, { square = square })
    return gasifier and generator, gasifier
end

--- Queues lighting the gasifier once this client sees wood in it, with what that takes then given
--- first.
function T.lightGasifier(self, gasifier)
    T.waitForSummary(self, gasifier, function(summary) return summary.hopperKg > 0 end, "this client's summary of the gasifier's wood")
    T.step(function()
        T.giveMaterials(self, "light", GasifierJobs.materials(T.player(), GasifierJobs.LIGHT, T.recordSummary(gasifier)))
    end)
    T.gasJob(self, "gasifier", gasifier, GasifierJobs.LIGHT)
end

--- Queues the gasifier burning `kg` of its wood at once.
function T.burnGasifier(self, gasifier, kg)
    T.server(self, "gasifierBurn", T.recordArgs(gasifier, { kg = kg }))
end

-- Generators -----------------------------------------------------------------------------------

--- Queues a load the line feeding the running `generator` can't carry, a gas pass, and a read of
--- the generator, stalled, into self.reads[label].
function T.stallLine(self, generator, label)
    -- Any load the line can't carry stalls it; how much isn't what this is about.
    T.gasLoad(self, GasKit.CAP_W + 1)
    T.gasPass(self, generator, 0.1)
    T.readGenerator(self, generator, label)
end

--- Queues taking `litres` from the generator's fuel, as vanilla's hourly bill and a bank charging
--- from it take it, but at once and with no pass running; the next gas pass or job bills them to a
--- line on gas.
function T.burnFuel(self, generator, litres)
    T.server(self, "generatorBurn", T.at(generator, { litres = litres }))
end

--- Queues the gas pass, as though `hours` had passed since the generator's last.
function T.gasPass(self, generator, hours)
    T.server(self, "gasPass", T.at(generator, { hours = hours }))
end

--- Queues a gas pass, then reads of the generator and of the record `source` feeding it into
--- self.reads[label] and self.reads[label .. "Source"].
function T.readBill(self, generator, source, label)
    T.batch(function()
        T.gasPass(self, generator, 0)
        T.readGenerator(self, generator, label)
        T.readRecord(self, source, label .. "Source")
    end)
end

--- Queues moving the clock on `hours`, so vanilla bills a running generator for each whole hour
--- that passes (IsoGenerator.update).
function T.jumpClock(self, hours)
    T.step(function() T.setTime(self, getGameTime():getTimeOfDay() + hours) end)
end

-- How long vanilla may take to bill a generator after the clock moved, in ms: it bills in the
-- generator's next update.
local BILL_MS = 5000

--- Queues a wait until vanilla has billed the generator since the read `label` (T.readBill): its
--- fuel fell, or a gas pass since saw it fall.
function T.waitForBill(self, generator, label)
    T.serverUntil(self, "generatorRead", T.at(generator), function(read)
        local before = self.reads[label]
        local billed, was = read.state and read.state.billedHour, before.state and before.state.billedHour
        return read.fuel < before.fuel - 0.0001 or (billed ~= nil and was ~= nil and billed > was)
    end, BILL_MS)
end

--- The litres vanilla bills the generator between the reads `before` and `after` (T.readBill),
--- had it the fuel: its bill an hour (`bill`, the GeneratorFuelConsumption option applied) for
--- each whole world hour between them (IsoGenerator.update). Also returns those hours.
function T.vanillaBill(self, before, after)
    local hours = math.floor(self.reads[after].hours) - math.floor(self.reads[before].hours)
    return hours * self.reads[before].bill, hours
end

--- Queues every kitted generator delivering `watts`, whatever it powers, until the test ends.
function T.gasLoad(self, watts)
    T.server(self, "gasLoad", { watts = watts })
end

-- What this client's copy of a generator's kit state shows once each job is done.
local KIT_DONE = {
    [GasKit.INSTALL] = function(state) return state ~= nil end,
    [GasKit.REMOVE] = function(state) return state == nil end,
    [GasKit.CONNECT] = function(state) return state ~= nil and state.source ~= nil end,
    [GasKit.DISCONNECT] = function(state) return state ~= nil and state.source == nil end,
    [GasKit.TO_PETROL] = function(state) return state ~= nil and state.mode == "petrol" end,
    [GasKit.TO_GAS] = function(state) return state ~= nil and state.mode == "gas" end,
}

--- Queues the kit job `job` at `generator` (to the record `source` for Connect Gas Line), then a
--- wait until this client's copy shows it done, since the next job's action checks that copy.
function T.kitJob(self, generator, job, source)
    T.gasJob(self, "kit", generator, job, source)
    T.waitFor(self, function() return KIT_DONE[job](GasKit.stateOf(generator.object)) end,
        "this client's copy of the generator after " .. job)
end

--- Queues fitting the kit to `generator`, with what that takes given first.
function T.fitKit(self, generator)
    T.giveMaterials(self, "kit", GasKit.materials(T.player(), GasKit.INSTALL))
    T.kitJob(self, generator, GasKit.INSTALL)
end

--- Queues fitting the kit and connecting the line to the record `source`, with what each takes
--- given first; self.line is what the line took.
function T.fitAndConnect(self, generator, source)
    T.fitKit(self, generator)
    T.step(function()
        self.line = GasKit.materials(T.player(), GasKit.CONNECT, generator.object, source.object)
        T.giveMaterials(self, "line", self.line)
    end)
    T.kitJob(self, generator, GasKit.CONNECT, source)
end

local SIDES = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
local CORNERS = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }

--- A free outdoor square beside `square`, or on one of its corners if `corner`, or nil.
function T.squareBeside(square, corner)
    for _, offset in ipairs(corner and CORNERS or SIDES) do
        local found = getSquare(square:getX() + offset[1], square:getY() + offset[2], square:getZ())
        if RenewableEnergy.Debug.isFreeSquare(found, false) then
            return found
        end
    end
    return nil
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

--- Whether a generator read (T.readGenerator) shows it stopped by its gas line: off, with its
--- kit's state saying stalled.
function T.isStalled(read)
    return not read.running and read.state ~= nil and read.state.stalled == true
end

return T
