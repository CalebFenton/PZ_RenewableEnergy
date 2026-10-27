require "RenewableEnergy/Debug/RenewableEnergyTestLibGenerators"
local Debug = require "RenewableEnergy/Debug/RenewableEnergyDebug"
local Fixtures = require "RenewableEnergy/Debug/RenewableEnergyFixtures"
local Digester = require "RenewableEnergy/Biogas/Digester"
local GasifierJobs = require "RenewableEnergy/WoodGas/GasifierJobs"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local Sprites = require "RenewableEnergy/Sprites"

-- Fixtures of the biogas, gas line and wood gas tests (RenewableEnergyTestsBiogas*.lua,
-- RenewableEnergyTestsGasLine*.lua, RenewableEnergyTestsWoodGas*.lua) and of the rural find tests'
-- digesters and gasifiers (RenewableEnergyTestsRuralFinds.lua), added to RenewableEnergyTest.
-- Digesters and gasifiers are records of the Global Object System on the authority, which the
-- harness's record kit places, sets, fills, ages and reads (kinds "digester" and "gasifier",
-- RenewableEnergyTestKinds); the server handlers (RenewableEnergyTestServerBiogas.lua, ...Gas.lua)
-- run what is the mod's own. Reads land in self.reads[label].

local T = RenewableEnergyTest

--- Queues building a record of `kind` from the build menu's entry of `entity` on a T.buildSite
--- (T.build with `prefer`, which takes away what it leaves when the test ends), waiting for this
--- client's copy of the tile `tile`. Its record lands in self.reads.built. Returns the handle, or
--- nil.
function T.buildRecord(self, kind, entity, tile, prefer)
    local square = T.buildSite(self)
    if not square then return nil end
    local handle = T.where(square)
    handle.kind = kind
    if not T.build(self, entity, square, prefer, function() return T.objectWithSprite(square, tile) ~= nil end,
        "this client's copy of the " .. tostring(tile) .. " " .. kind) then
        return nil
    end
    T.readRecord(self, handle, "built")
    return handle
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

--- Saved fields of a mature digester of tier `tier` (Fixtures.matureDigester), soured: acid well
--- past its limit, so the passes that run meanwhile keep it sour.
function T.sourDigester(tier, fields)
    local state = Fixtures.matureDigester(tier)
    state.sour, state.acid = true, 2 * Digester.ACID_LIMIT * state.potential
    for key, value in pairs(fields or {}) do
        state[key] = value
    end
    return state
end

--- Queues running the digester for `hours` at the air temperature `air` (°C), without moving the
--- clock, through its own pass (DigesterObject:run).
function T.runDigester(self, handle, hours, air)
    T.server(self, "runDigester", T.at(handle, { hours = hours, air = air }))
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

--- The kilograms of wood a gasifier of `tier`'s hopper holds: its tile's ContainerCapacity.
function T.hopperHolds(tier)
    return tonumber(getSprite(Sprites.gasifier[tier]):getProperties():get("ContainerCapacity"))
end

--- Queues lighting the gasifier once this client sees wood in it, with what that takes then given
--- first.
function T.lightGasifier(self, gasifier)
    T.waitForSummary(self, gasifier, function(summary) return summary.hopperKg > 0 end, "this client's summary of the gasifier's wood")
    T.step(function()
        T.giveMaterials(self, "light", GasifierJobs.materials(T.player(), GasifierJobs.LIGHT, T.recordSummary(gasifier)))
    end)
    T.actionJob(self, "gasifier", gasifier, GasifierJobs.LIGHT)
end

--- Queues the gasifier burning `kg` of its wood at once.
function T.burnGasifier(self, gasifier, kg)
    T.server(self, "burnGasifier", T.at(gasifier, { kg = kg }))
end

-- Gas lines -------------------------------------------------------------------------------------

--- Queues a load the line feeding the running `generator` can't carry, a gas pass, and a read of
--- the generator, stalled, into self.reads[label].
function T.stallLine(self, generator, label)
    -- Any load the line can't carry stalls it; how much isn't what this is about.
    T.gasLoad(self, GasKit.CAP_W + 1)
    T.gasPass(self, generator, 0.1)
    T.readGenerator(self, generator, label)
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
    T.actionJob(self, "kit", generator, job, source)
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
        if Debug.isFreeSquare(found, false) then
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
