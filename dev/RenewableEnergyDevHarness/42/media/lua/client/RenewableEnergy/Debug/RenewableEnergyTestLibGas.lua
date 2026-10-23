require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/GasLine/GasKit"

-- Fixtures of the biogas, gas line and wood gas tests (RenewableEnergyTestsBiogas.lua,
-- RenewableEnergyTestsGasLine.lua, RenewableEnergyTestsWoodGas.lua), added to RenewableEnergyTest.
-- Digesters and gasifiers are records of the Global Object System on the authority; the server
-- handlers (RenewableEnergyTestServerBiogas.lua, ...Gas.lua) build, drive and read them by kind
-- and place. A record handle is { x, y, z, square, kind }, and `object` is this client's copy of
-- its tile once it has its summary. Reads land in self.reads[label].

local T = RenewableEnergyTest
local Digester, GasKit = RenewableEnergy.Digester, RenewableEnergy.GasKit

-- What a record kind's tile and summary are on this client: the server helper's RECORD_KINDS, whose
-- owner and tile test are shared code. The helper loads after client Lua, so it is required here.
local function kindOf(handle)
    local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
    return Helpers.RECORD_KINDS[handle.kind]
end

--- The server handlers' args for the record `handle`, with `extra`'s fields added.
function T.recordArgs(handle, extra)
    local args = T.at(handle)
    args.kind = handle.kind
    for key, value in pairs(extra or {}) do
        args[key] = value
    end
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
    local handle = T.at(square)
    handle.square, handle.kind = square, kind
    T.server(self, "recordPlace", T.recordArgs(handle, { tile = tile }))
    local spec = kindOf(handle)
    local owner = spec.owner()
    T.waitFor(self, function()
        local object = RenewableEnergy.findObjectOn(getSquare(handle.x, handle.y, handle.z), spec.isObject)
        handle.object = object and owner.summaryOf(object) and object or nil
        return handle.object ~= nil
    end, "this client's copy of the " .. kind)
    return handle
end

-- The build menu entry of `entity` (a game entity script's full name), or nil.
local function buildEntry(entity)
    local script = getScriptManager():getGameEntityScript(entity)
    local spriteConfig = script and script:getComponentScriptFor(ComponentType.SpriteConfig)
    if not spriteConfig then
        return nil
    end
    local infos = SpriteConfigManager.GetObjectInfoList()
    for i = 0, infos:size() - 1 do
        if infos:get(i):getScript() == spriteConfig then
            return infos:get(i)
        end
    end
    return nil
end

--- Queues building a record of `kind` from the build menu's entry of `entity` on a bare outdoor
--- square, through the build menu's own path (ISBuildIsoEntity, ISBuildAction): the character gets
--- the recipe's skill levels and exactly its inputs (T.recipeInputs with `prefer`), and the build
--- waits for this client's copy of the tile `tile`. Its record lands in self.reads.built, what is
--- left carried in self.counts.left; T.expectBuilt checks them. Returns the handle, or nil.
function T.buildRecord(self, kind, entity, tile, prefer)
    -- Bare: grass and the like block placing anything built (BlocksPlacement), as for vanilla's.
    local square = T.square(self, { bare = true }, "a bare outdoor square for a " .. kind)
    if not square then return nil end
    local info = T.need(self, buildEntry(entity), "the build menu entry of " .. entity)
    local recipe = info and info:getRecipe() and info:getRecipe():getCraftRecipe()
    if not T.need(self, recipe, "the build recipe of " .. entity) then return nil end
    local handle = T.at(square)
    handle.square, handle.kind = square, kind
    for i = 0, recipe:getRequiredSkillCount() - 1 do
        local skill = recipe:getRequiredSkill(i)
        T.setPerk(self, skill:getPerk(), skill:getLevel())
    end
    local inputs, unmatched = T.recipeInputs(recipe, prefer)
    if not T.need(self, #unmatched == 0, "an item for " .. table.concat(unmatched, "; ")) then return nil end
    -- What a build should leave carried: its kept tools, and none of the items it takes whole.
    -- A drainable it takes uses of stays part-used, so isn't counted.
    self.expected, self.types = {}, {}
    for i, entry in ipairs(inputs) do
        local input = recipe:getInputs():get(i - 1)
        if input:isKeep() then
            self.expected[entry.type] = entry.count
        elseif input:isItemCount() or not getScriptManager():FindItem(entry.type):isItemType(ItemType.DRAINABLE) then
            self.expected[entry.type] = 0
        end
        table.insert(self.types, entry.type)
    end
    T.give(self, "materials", inputs)
    T.server(self, "recordTrack", T.recordArgs(handle))
    T.step(function()
        local player = T.player()
        T.standNextTo(square)
        local build = ISBuildIsoEntity:new(player, info, 1, ISInventoryPaneContextMenu.getContainers(player))
        -- What the build panel does before the cursor can build (ISBuildPanel): the player
        -- number the drag sets (IsoCell.setDrag), and the recipe's inputs picked from what is carried.
        build.player = player:getPlayerNum()
        build.buildPanelLogic:refresh()
        build.buildPanelLogic:autoPopulateInputs()
        self.canBuild = build.buildPanelLogic:canPerformCurrentRecipe()
        self.validSquare = build:isValid(square)
        build:tryBuild(handle.x, handle.y, handle.z)
    end)
    T.waitFor(self, function() return T.objectWithSprite(square, tile) ~= nil end,
        "this client's copy of the " .. tostring(tile) .. " " .. kind)
    T.batch(function()
        T.readRecord(self, handle, "built")
        T.count(self, "left", self.types)
    end)
    return handle
end

--- Expects T.buildRecord's build to have been possible, built its record on the tile `tile`, and
--- taken what it takes while keeping its tools.
function T.expectBuilt(self, tile)
    local built = self.reads.built or {}
    T.expect(self.canBuild and self.validSquare, "the build menu can't build it from its materials on a bare square")
    T.expect(built.sprite == tile, "the built tile is " .. tostring(built.sprite) .. ", expected " .. tostring(tile))
    for fullType, count in pairs(self.expected or {}) do
        local left = self.counts.left and self.counts.left[fullType] or 0
        T.expect(left == count, "building left " .. left .. " " .. fullType .. ", not " .. count)
    end
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

--- The same, soured: acid well past its limit, so the passes that run meanwhile keep it sour.
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
--- running, fuel, condition, its bill, its kit's state, whether the gas pass lists it, its
--- overlays, its building's toxicity, the world hour.
function T.readGenerator(self, generator, label)
    T.read(self, "generatorRead", T.at(generator), label)
end

--- Queues pouring `fields.pour` litres into the generator, switching it (`fields.running`) and,
--- with `fields.rebuild`, having vanilla rebuild the bills of the generators reaching it. A rebuild
--- happens in the generators' next update, which a multiplayer server runs on its own clock, so the
--- wait is for a later server frame rather than a count of this client's ticks; the shares Payers
--- sets after a rebuild stand by then too.
function T.setGenerator(self, generator, fields)
    local args = T.at(generator)
    args.pour, args.running, args.rebuild = fields.pour, fields.running, fields.rebuild
    T.server(self, "generatorSet", args)
    if fields.rebuild then
        T.serverUntil(self, "worldFrame", {}, function(now) return now.frame > self.server.generatorSet.frame end)
    end
end

--- Queues taking `litres` from the generator's fuel, as vanilla's hourly bill and a bank charging
--- from it take it, but at once and with no pass running; the next gas pass or job bills them to a
--- line on gas.
function T.burnFuel(self, generator, litres)
    local args = T.at(generator)
    args.litres = litres
    T.server(self, "generatorBurn", args)
end

--- Queues the gas pass, as though `hours` had passed since the generator's last.
function T.gasPass(self, generator, hours)
    local args = T.at(generator)
    args.hours = hours
    T.server(self, "gasPass", args)
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
    T.giveMaterials(self, "kit", GasKit.materials(GasKit.INSTALL))
    T.kitJob(self, generator, GasKit.INSTALL)
end

--- Queues fitting the kit and connecting the line to the record `source`, with what each takes
--- given first; self.line is what the line took.
function T.fitAndConnect(self, generator, source)
    T.fitKit(self, generator)
    T.step(function()
        self.line = GasKit.materials(GasKit.CONNECT, generator.object, source.object)
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
