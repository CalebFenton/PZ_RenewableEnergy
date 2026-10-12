require "Tests/TimedActionsTests"
require "Moveables/ISMoveableSpriteProps"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Debug/RenewableEnergyDebug"

-- Helpers for the RenewableEnergyTests*.lua files, which register tests with the vanilla timed
-- action test runner: Debug menu > Dev > Unit Tests > Timed Actions, in debug mode. The runner
-- calls run(), waits until the character's action queue is empty, then calls validate(). Before
-- each test it empties the inventory and the hands, clears worn items and teleports the character
-- back; perks, known recipes, modData, world objects, sandbox options and the clock carry over.
-- Each result goes to console.txt as "RETest PASS <name>" or "RETest FAIL <name>: <reasons>".
--
-- Rules of the API, so that no test depends on what an earlier one left:
-- - T.test gives every run a fresh `self`, sets the clock to `spec.hour` (DEFAULT_HOUR unless
--   given), runs timed actions instantly when `spec.instant` (otherwise at their real duration),
--   and applies `spec.sandbox`.
-- - Each T.set* call, T.defer, T.onTick and every fixture (T.bank, T.panel, T.tile, T.bench,
--   T.placeMoveable, T.vehicle, T.track) pushes its undo onto the test's restore stack. After
--   validate and `spec.cleanup`, the wrapper unwinds it newest first: it removes what the test
--   placed (banks through PowerBank.remove, running generators switched off first, vehicles
--   permanently) and restores the clock, perks, grid, sandbox options, game speed and the instant
--   cheat. The perks the mod's actions and recipes read are restored even when a test sets them
--   another way.
-- - A fixture that can't be built records what is missing (T.need); the wrapper then fails the
--   test with it and skips spec.validate, so validate never indexes a missing fixture.
-- - A Lua error stops the game in the debug-mode error handler, pcall or not, and the runner never
--   finishes, so tests never throw.
RenewableEnergyTest = {}
local T = RenewableEnergyTest

local PowerBank, Battery, Sprites = RenewableEnergy.PowerBank, RenewableEnergy.Battery, RenewableEnergy.Sprites

-- Daylight, so crafting and wiring can see and panels have sun.
local DEFAULT_HOUR = 10
-- The longest a test waits for the light to follow the clock or the grid. The lighting catches up
-- at its own pace in real time, so at a high frame rate it takes more ticks.
local LIGHT_FRAMES = 600
-- Squares searched around a fixture's centre, in tiles.
local SEARCH_RADIUS = 30
-- Squares a vehicle is tried on before a test gives up on it.
local VEHICLE_TRIES = 8
local RESTORED_PERKS = { Perks.Electricity, Perks.MetalWelding, Perks.Woodwork }

function T.player()
    return getSpecificPlayer(0)
end

-- Expectations ---------------------------------------------------------------------------------

-- Unmet expectations of the test being validated.
local failures = {}

function T.expect(condition, message)
    if not condition then
        table.insert(failures, message)
    end
    return condition
end

function T.expectNear(label, actual, expected, tolerance)
    return T.expect(type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 0.0001),
        label .. " is " .. tostring(actual) .. ", expected " .. expected)
end

--- Returns `value`; when it is nil or false, records `what` (a noun phrase: "a free indoor square
--- for a bank") as missing, which fails the test without running spec.validate.
function T.need(self, value, what)
    if not value then
        table.insert(self.missing, what)
    end
    return value
end

-- Restore stack --------------------------------------------------------------------------------

--- Runs `undo` when the test ends, before the undos pushed earlier.
function T.defer(self, undo)
    table.insert(self.undo, undo)
end

--- Calls `fn` every tick until the test ends.
function T.onTick(self, fn)
    Events.OnTick.Add(fn)
    T.defer(self, function() Events.OnTick.Remove(fn) end)
end

function T.setTime(self, hour)
    local time = getGameTime()
    local saved = time:getTimeOfDay()
    T.defer(self, function() time:setTimeOfDay(saved) end)
    time:setTimeOfDay(hour)
end

function T.setPerk(self, perk, level)
    local p = T.player()
    local saved = p:getPerkLevel(perk)
    T.defer(self, function() p:setPerkLevelDebug(perk, saved) end)
    p:setPerkLevelDebug(perk, level)
end

--- Sets a sandbox option of this mod (SandboxVars.RenewableEnergy) or, failing that, of the game.
--- An option in neither is recorded as missing rather than created.
function T.setSandbox(self, key, value)
    local options = SandboxVars.RenewableEnergy[key] ~= nil and SandboxVars.RenewableEnergy
        or SandboxVars[key] ~= nil and SandboxVars
    if not T.need(self, options, "the sandbox option " .. key) then return end
    local saved = options[key]
    T.defer(self, function() options[key] = saved end)
    options[key] = value
end

--- The game runs `multiplier` times as fast: the clock and every timed action alike. The game drops
--- back to 1 when the character moves without a path or a zombie comes close.
function T.setMultiplier(self, multiplier)
    local time = getGameTime()
    local saved = time:getTrueMultiplier()
    T.defer(self, function() time:setMultiplier(saved) end)
    time:setMultiplier(multiplier)
end

--- The power grid on or off. The scenario starts with it on, which powers squares without a
--- generator.
function T.setGrid(self, on)
    local option = getSandboxOptions():getOptionByName("ElecShutModifier")
    local hydro, shut = getWorld():isHydroPowerOn(), option and option:getValue()
    T.defer(self, function()
        if option then option:setValue(shut) end
        getWorld():setHydroPowerOn(hydro)
    end)
    if option then option:setValue(on and 100000 or -1) end
    getWorld():setHydroPowerOn(on)
end

-- Queue ----------------------------------------------------------------------------------------

-- Holds the action queue, so the runner validates only once the world has caught up: until
-- `done()` holds or `total` ticks pass, calling `onTick(n)` every tick.
local Wait = ISBaseTimedAction:derive("RenewableEnergyTestWait")

function Wait:isValid()
    return true
end

function Wait:update()
    self.ticks = self.ticks + 1
    if self.onTick then
        self.onTick(self.ticks)
    end
    if self.ticks >= self.total or (self.done and self.done()) then
        self:forceComplete()
    end
end

function Wait:new(character, total, onTick, done)
    local o = ISBaseTimedAction.new(self, character)
    o.total, o.onTick, o.done, o.ticks = total, onTick, done, 0
    o.stopOnWalk, o.stopOnRun, o.stopOnAim = false, false, false
    o.maxTime = -1
    return o
end

--- Queues `ticks` ticks of waiting, calling `onTick(n)` every tick.
function T.wait(ticks, onTick)
    ISTimedActionQueue.add(Wait:new(T.player(), ticks, onTick))
end

--- Queues a wait that ends as soon as `condition()` holds, or after `maxFrames` ticks; the
--- following validate checks what it waited for.
function T.waitUntil(condition, maxFrames)
    ISTimedActionQueue.add(Wait:new(T.player(), maxFrames, nil, condition))
end

--- Runs `fn` once the actions queued before it are done.
function T.step(fn)
    ISTimedActionQueue.add(Wait:new(T.player(), 1, function() fn() end))
end

local function lit()
    return not T.player():tooDarkToRead()
end

--- Midnight with the grid off, dark where the character stands; queues a wait for the light to
--- follow the clock.
function T.makeDark(self)
    T.setGrid(self, false)
    T.setTime(self, 0)
    T.waitUntil(function() return not lit() end, LIGHT_FRAMES)
end

-- Registering tests ----------------------------------------------------------------------------

--- Registers test `name`. `spec`: run(self), validate(self), cleanup(self), all optional; `hour`;
--- `instant`; `sandbox` (option = value, see T.setSandbox).
function T.test(name, spec)
    local function start(self)
        local p = T.player()
        local cheat = p:isTimedActionInstantCheat()
        T.defer(self, function() p:setTimedActionInstantCheat(cheat) end)
        p:setTimedActionInstantCheat(spec.instant == true)
        T.setTime(self, spec.hour or DEFAULT_HOUR)
        for key, value in pairs(spec.sandbox or {}) do
            T.setSandbox(self, key, value)
        end
        if spec.run and #self.missing == 0 then
            spec.run(self)
        end
    end
    TimedActionTests.getTests()[name] = {
        run = function(entry)
            local self = { undo = {}, missing = {}, used = {} }
            entry.state = self
            local p = T.player()
            for _, perk in pairs(RESTORED_PERKS) do
                local level = p:getPerkLevel(perk)
                T.defer(self, function() p:setPerkLevelDebug(perk, level) end)
            end
            -- The light lags a clock or grid change by some frames, and the previous test may
            -- have ended in the dark.
            if lit() then
                start(self)
            else
                T.waitUntil(lit, LIGHT_FRAMES)
                T.step(function() start(self) end)
            end
        end,
        validate = function(entry)
            local self = entry.state or { undo = {}, missing = { "a run before validate" } }
            entry.state = nil
            failures = {}
            if #self.missing > 0 then
                table.insert(failures, "missing " .. table.concat(self.missing, "; "))
            elseif spec.validate then
                spec.validate(self)
            end
            if spec.cleanup then
                spec.cleanup(self)
            end
            for i = #self.undo, 1, -1 do
                self.undo[i]()
            end
            if #failures > 0 then
                print("RETest FAIL " .. name .. ": " .. table.concat(failures, "; "))
                return false
            end
            print("RETest PASS " .. name)
            return true
        end,
    }
end

-- Squares --------------------------------------------------------------------------------------

local function squareOf(near)
    if not near then
        return T.player():getCurrentSquare()
    end
    return instanceof(near, "IsoGridSquare") and near or near:getSquare()
end

-- Up to `count` free squares; see T.squares.
local function freeSquares(self, count, opts)
    local center = squareOf(opts.near)
    local found = {}
    if not center then return found end
    for radius = opts.minDistance or 1, SEARCH_RADIUS do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local square = math.max(math.abs(dx), math.abs(dy)) == radius
                    and getSquare(center:getX() + dx, center:getY() + dy, center:getZ())
                if #found < count and square and not self.used[square]
                    and RenewableEnergy.Debug.isFreeSquare(square, opts.indoors == true)
                    and (not opts.bare or square:getObjects():size() == 1) then
                    self.used[square] = true
                    table.insert(found, square)
                end
            end
        end
    end
    return found
end

--- `count` free squares (RenewableEnergy.Debug.isFreeSquare) around `opts.near` (a square or
--- object; the character's square by default), nearest first and at least `opts.minDistance`
--- tiles away: indoors where a bank may stand when `opts.indoors`, else outdoors; holding only
--- their floor when `opts.bare`. Each square goes to one fixture per test. Nil unless all are
--- found.
function T.squares(self, count, opts)
    local found = freeSquares(self, count, opts or {})
    return #found == count and found or nil
end

local function placeWord(opts)
    return opts.indoors and "indoor" or "outdoor"
end

-- Fixtures -------------------------------------------------------------------------------------

--- Removes `thing` (an IsoObject or a vehicle) when the test ends, the way the game does, so the
--- mod's removal handlers run. Returns `thing`.
function T.track(self, thing)
    T.defer(self, function()
        if instanceof(thing, "BaseVehicle") then
            thing:permanentlyRemove()
        elseif thing:getObjectIndex() ~= -1 then
            if PowerBank.isBank(thing) then
                PowerBank.remove(thing)
                return
            end
            -- Squares stay powered by a running generator that leaves them.
            if instanceof(thing, "IsoGenerator") and thing:isActivated() then
                thing:setActivated(false)
            end
            thing:getSquare():transmitRemoveItemFromSquare(thing)
        end
    end)
    return thing
end

--- A tile object of `sprite` on `square`, with `modData`.
function T.tile(self, square, sprite, modData)
    local object = IsoObject.new(square, sprite, "RenewableEnergyTest")
    for key, value in pairs(modData or {}) do
        object:getModData()[key] = value
    end
    square:AddTileObject(object)
    return T.track(self, object)
end

--- A working bank of Sprites field `kind` holding `items` (full types), filled straight into its
--- container as world spawns do, its batteries charged to `opts.charge` (full by default). It
--- stands on `opts.square`, else on a free square near `opts.near`: indoors unless
--- `opts.outdoors`. Returns the bank (its IsoGenerator) and the server's record of it.
function T.bank(self, kind, items, opts)
    opts = opts or {}
    local square = opts.square or (T.squares(self, 1, { indoors = not opts.outdoors, near = opts.near }) or {})[1]
    if not T.need(self, square, "a free " .. placeWord({ indoors = not opts.outdoors }) .. " square for a bank") then
        return nil
    end
    local bank = T.track(self, PowerBank.place(square, Sprites[kind], -1))
    local container = bank:getContainer()
    for _, fullType in ipairs(items or {}) do
        local item = container:AddItem(fullType)
        if item and Battery.isBattery(item) then
            Battery.setCharge(item, opts.charge or 1)
        end
    end
    PowerBank.perform(nil, "refresh", { bank = PowerBank.positionOf(bank) })
    local record = PowerBank.serverSystem:getLuaObjectOnSquare(square)
    return T.need(self, record and bank, "a bank the bank system registered"), record
end

--- Connects `panel` to `bank` through the authority. Returns whether it did, and the refusal.
function T.connect(bank, panel)
    return PowerBank.perform(T.player(), "connectSource",
        { bank = PowerBank.positionOf(bank), source = PowerBank.positionOf(panel) })
end

--- A panel tile of `sprite` on a free outdoor square near `opts.near` (a bank, object or
--- square), holding `opts.modules` ({ { type, condition } }) if given, and connected to
--- `opts.near` when `opts.connect`. Returns the panel and, when connecting, T.connect's results.
function T.panel(self, sprite, opts)
    opts = opts or {}
    local square = (T.squares(self, 1, { near = opts.near }) or {})[1]
    if not T.need(self, square, "a free outdoor square for a panel") then
        return nil
    end
    local panel = T.tile(self, square, sprite, opts.modules and { [PowerBank.MODULES] = opts.modules })
    if opts.connect then
        return panel, T.connect(opts.near, panel)
    end
    return panel
end

--- Places a new `itemType` on `square` the way the moveables cursor does, with `modData` on the
--- item first. Returns the placed object.
function T.placeMoveable(self, square, itemType, sprite, modData)
    local item = instanceItem(itemType)
    for key, value in pairs(modData or {}) do
        item:getModData()[key] = value
    end
    T.player():getInventory():AddItem(item)
    ISMoveableSpriteProps.new(sprite):placeMoveable(T.player(), square, item:getWorldSprite(), true)
    local object = T.objectWithSprite(square, sprite)
    return T.need(self, object and T.track(self, object), "a placed " .. itemType)
end

--- A workstation of the entity script `entity` (such as "Base.Kiln_Small"), drawn as `sprite`,
--- on a free square next to the character, who is using it as its crafting window makes them.
--- Returns the object.
function T.bench(self, entity, sprite)
    local script = T.need(self, getScriptManager():getGameEntityScript(entity), "the entity script " .. entity)
    local here = T.player():getSquare()
    local square
    for _, direction in ipairs({ IsoDirections.S, IsoDirections.E, IsoDirections.N, IsoDirections.W }) do
        local next = here:getAdjacentSquare(direction)
        if not square and next and not self.used[next] and next:isFree(false) and not here:isBlockedTo(next) then
            square = next
        end
    end
    if not (script and T.need(self, square, "a free square next to the character for a " .. entity)) then
        return nil
    end
    self.used[square] = true
    local bench = IsoObject.new(square, sprite, entity)
    GameEntityFactory.CreateIsoObjectEntity(bench, script, true)
    square:AddTileObject(bench)
    T.track(self, bench)
    bench:setUsingPlayer(T.player())
    return T.need(self, bench:getComponent(ComponentType.CraftBench) and bench, "a craft bench in " .. entity)
end

--- A vehicle of `script` facing north on `opts.square`, else on open ground near `opts.near`
--- (the character by default), its battery replaced by a new `opts.battery` (a full type) if
--- given and charged to `opts.charge` if given. Returns the vehicle and its battery.
function T.vehicle(self, script, opts)
    opts = opts or {}
    -- Far enough that the vehicle doesn't land on the character.
    local squares = opts.square and { opts.square }
        or freeSquares(self, VEHICLE_TRIES, { near = opts.near, minDistance = 4, bare = true })
    for _, square in ipairs(squares) do
        -- addVehicleDebug returns a vehicle even where it leaves it out of the world, as it does
        -- where it would hit another vehicle; only a vehicle in the world gets an id
        -- (BaseVehicle.createPhysics).
        local vehicle = addVehicleDebug(script, IsoDirections.N, nil, square)
        if vehicle and vehicle:getId() ~= -1 then
            T.track(self, vehicle)
            local part = vehicle:getPartById("Battery")
            if part and opts.battery then
                part:setInventoryItem(instanceItem(opts.battery))
            end
            local battery = part and part:getInventoryItem()
            if battery and opts.charge then
                battery:setCurrentUsesFloat(opts.charge)
            end
            return vehicle, battery
        end
    end
    T.need(self, nil, "open ground for a " .. script)
    return nil
end

-- Banks ----------------------------------------------------------------------------------------

--- A bank pass's context with the weather fixed: `light` W/m² on every mount, clear, 25 °C, no
--- snow, and `stormHours` of storm.
function T.passContext(light, stormHours)
    local function irradiance() return light end
    return {
        weather = RenewableEnergy.Sun.CLEAR_WEATHER, precipitation = 0, airC = 25, elevation = light > 0 and 45 or -10,
        stormHours = stormHours or 0, irradiance = irradiance, clearIrradiance = irradiance,
    }
end

--- Replaces the bank's measured load with appliances of the Specs.loads kinds `names`, as if the
--- scan had found them switched on, and lets the bank react: cut or restore its power and send
--- its status. The next pass measures the real load again.
function T.applyLoad(record, names)
    local Loads = RenewableEnergy.Loads
    local load = Loads.new()
    for _, name in ipairs(names) do
        Loads.add(load, name)
    end
    record.loadW, record.averageLoadW, record.loadByKind = load.watts, load.averageWatts, Loads.byKind(load)
    record:checkOverload()
    record:switchGenerator()
    record:sendStatus()
end

-- Lookups and data -----------------------------------------------------------------------------

function T.objectWithSprite(square, sprite)
    return RenewableEnergy.findObjectOn(square, function(object)
        return object:getTextureName() == sprite
    end)
end

--- How often `fullType` appears in a flat { item, weight, ... } loot list, and its last weight.
function T.countPairs(items, fullType)
    local count, weight = 0, nil
    for i = 1, #items - 1, 2 do
        if items[i] == fullType then
            count = count + 1
            weight = items[i + 1]
        end
    end
    return count, weight
end

-- Every placed tile: the item picking it up gives, what Sprites.kindOf reports (kind, facing,
-- material), and whether it holds items.
T.PLACED_TILES = {
    { sprite = Sprites.flat, item = "RenewableEnergy.SolarFlat", kind = "flat" },
    { sprite = Sprites.failsafe, item = "RenewableEnergy.SolarFailsafe", kind = "failsafe" },
    { sprite = Sprites.cellCharger, item = "RenewableEnergy.SolarCellCharger", kind = "cellCharger", container = true },
    { sprite = Sprites.gardenLight.off, item = "RenewableEnergy.SolarGardenLight", kind = "gardenLight" },
    { sprite = Sprites.gardenLight.lit, item = "RenewableEnergy.SolarGardenLight", kind = "gardenLight" },
}
for material, suffix in pairs({ wood = "Wood", metal = "Metal" }) do
    for _, mount in ipairs({ "wall", "rack" }) do
        local item = "RenewableEnergy.Solar" .. (mount == "wall" and "Wall" or "Rack") .. suffix
        for facing, sprite in pairs(Sprites[mount][material]) do
            table.insert(T.PLACED_TILES, { sprite = sprite, item = item, kind = mount, facing = facing, material = material })
        end
    end
    for _, tier in ipairs({ "Box", "Rack", "Bank" }) do
        local field = "battery" .. tier .. suffix
        table.insert(T.PLACED_TILES, { sprite = Sprites[field], item = "RenewableEnergy.Battery" .. tier .. suffix,
            kind = field, material = material, container = true })
    end
end

-- Crafting -------------------------------------------------------------------------------------

-- The crafting logic the game starts `recipe` from the item `from` with: the right-click menu's,
-- with a table in reach as the surface, or with `bench` (from T.bench) the bench window's.
local function craftLogic(recipe, from, bench)
    local p = T.player()
    local logic
    if bench then
        logic = HandcraftLogic.new(p, bench:getComponent(ComponentType.CraftBench), bench)
    else
        logic = HandcraftLogic.new(p, nil, nil)
        logic:setIsoObject(logic:findCraftSurface(p, 2))
    end
    logic:setContainers(ISInventoryPaneContextMenu.getContainers(p))
    logic:setRecipeFromContextClick(recipe, from)
    return logic
end

-- Why the game would refuse to start this craft, or nil if it would start it. The menu and the
-- crafting windows refuse without saying why.
function T.craftRefusal(recipe, from, bench)
    local p = T.player()
    local logic = craftLogic(recipe, from, bench)
    if logic:canPerformCurrentRecipe() then
        return nil
    elseif not p:isRecipeActuallyKnown(recipe) then
        return "recipe not known"
    elseif not recipe:characterHasRequiredSkills(p) then
        return "skills too low"
    elseif recipe:isAnySurfaceCraft() and not logic:isCharacterInRangeOfWorkbench() then
        return "no table in reach"
    elseif p:tooDarkToRead() then
        return "too dark"
    end
    local missing = {}
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local data = logic:getRecipeData():getDataForInputScript(inputs:get(i))
        if data and not data:isInputItemsSatisfied() then
            table.insert(missing, inputs:get(i):getOriginalLine())
        end
    end
    return "missing " .. table.concat(missing, "; ")
end

--- Starts crafting `recipe` from the item `from` the way the right-click menu does or, with
--- `bench` (from T.bench), the way the bench's crafting window does. Adds why the game refused
--- to `self.refusal`.
function T.startCraft(self, recipe, from, bench)
    local refusal = T.craftRefusal(recipe, from, bench)
    if refusal then
        self.refusal = (self.refusal and self.refusal .. "; " or "") .. recipe:getName() .. ": " .. refusal
    end
    if bench then
        ISEntityUI.HandcraftStart(T.player(), craftLogic(recipe, from, bench), false, true)
    else
        ISInventoryPaneContextMenu.OnNewCraft(from, recipe, T.player():getPlayerNum(), false)
    end
end

-- How many `fullType` lie on the floor around the character, removing them. A craft whose output
-- doesn't fit drops it at the character's feet (Actions.addOrDropItem).
local function takeDropped(fullType)
    local here, count = T.player():getCurrentSquare(), 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = here and getSquare(here:getX() + dx, here:getY() + dy, here:getZ())
            local objects = square and square:getWorldObjects()
            for i = (objects and objects:size() or 0) - 1, 0, -1 do
                if objects:get(i):getItem():getFullType() == fullType then
                    count = count + 1
                    square:removeWorldObject(objects:get(i))
                end
            end
        end
    end
    return count
end

--- Registers a test that crafts `spec.recipe` from the first `spec.from` item the way the
--- right-click menu does or, with `spec.bench` ({ entity script, sprite }, see T.bench), at that
--- workstation the way its crafting window does; instantly unless `spec.instant` is false. The
--- character knows every recipe, has at least the levels the recipe requires, stands by a table,
--- and carries exactly the inputs of one craft (RenewableEnergy.Debug.addRecipeInputs with
--- `spec.prefer`) and whatever `spec.setup(self)` adds. validate() expects the counts in
--- `spec.counts`, in the inventory or dropped at the character's feet, then runs
--- `spec.validate(self)`. A failing test also reports why the game refused the craft.
function T.craftTest(name, spec)
    T.test(name, {
        sandbox = spec.sandbox,
        hour = spec.hour,
        instant = spec.instant ~= false,
        run = function(self)
            local p = T.player()
            local recipe = T.need(self, getScriptManager():getCraftRecipe(spec.recipe), "the recipe " .. spec.recipe)
            if not recipe then return end
            RenewableEnergy.Debug.learnRecipes(p)
            RenewableEnergy.Debug.placeWorkTable(p)
            local bench = spec.bench and T.bench(self, spec.bench[1], spec.bench[2])
            if spec.bench and not bench then return end
            for i = 0, recipe:getRequiredSkillCount() - 1 do
                local skill = recipe:getRequiredSkill(i)
                if p:getPerkLevel(skill:getPerk()) < skill:getLevel() then
                    T.setPerk(self, skill:getPerk(), skill:getLevel())
                end
            end
            local unmatched = RenewableEnergy.Debug.addRecipeInputs(p, recipe, spec.prefer)
            if not T.need(self, #unmatched == 0, "an item for " .. table.concat(unmatched, "; ")) then return end
            if spec.setup then
                spec.setup(self)
            end
            local from = T.need(self, p:getInventory():getFirstTypeRecurse(spec.from), "a " .. spec.from .. " to craft from")
            if not from then return end
            T.startCraft(self, recipe, from, bench)
        end,
        validate = function(self)
            local before = #failures
            for fullType, count in pairs(spec.counts or {}) do
                local actual = T.player():getInventory():getCountTypeRecurse(fullType) + takeDropped(fullType)
                T.expect(actual == count, actual .. " " .. fullType .. ", expected " .. count)
            end
            if spec.validate then
                spec.validate(self)
            end
            if #failures > before and self.refusal then
                table.insert(failures, "the game refused the craft: " .. self.refusal)
            end
        end,
    })
end
