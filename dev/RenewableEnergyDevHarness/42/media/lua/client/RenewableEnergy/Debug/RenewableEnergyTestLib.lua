require "PZHarness/TestLib"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/Gadgets/VehicleBattery"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/UI/StatusWindow"
require "RenewableEnergy/Debug/RenewableEnergyLoot"

-- Helpers for the RenewableEnergyTests*.lua files: the shared harness's test library
-- (PZHarness/TestLib.lua explains the runner and the rules every helper keeps), plus fixtures
-- that know this mod's objects.
--
-- Banks and panels live on the authority, so their fixtures are built through T.server by the
-- dev mod's server handlers (RenewableEnergyTestServer.lua) and removed there when the test ends.
-- A fixture is a handle: its square is picked at once, so later fixtures can be placed near it,
-- and `object` is filled in once this client has its copy of what the server built.
RenewableEnergyTest = setmetatable({}, { __index = PZHarness.Test })
local T = RenewableEnergyTest

local PowerBank, Sprites = RenewableEnergy.PowerBank, RenewableEnergy.Sprites
local Sources, Treadmill = RenewableEnergy.Sources, RenewableEnergy.Treadmill

-- The longest a fixture waits for the server's copies, in ticks. A multiplayer server sends them
-- a tick or more later in real time, so a high frame rate needs more ticks.
local COPY_FRAMES = 3000

-- The square a fixture handle, an object or a square stands on.
local function squareOf(near)
    if type(near) == "table" then
        return near.square
    end
    return near
end

--- The { x, y, z } of a handle (its x, y, z, else its square) or a square, the form the server
--- handlers take.
function T.at(handleOrSquare)
    if type(handleOrSquare) == "table" and handleOrSquare.x then
        return { x = handleOrSquare.x, y = handleOrSquare.y, z = handleOrSquare.z }
    end
    local square = squareOf(handleOrSquare)
    return { x = square:getX(), y = square:getY(), z = square:getZ() }
end

--- A free square as T.squares picks one by `opts`, whose `near` may also be a fixture handle; nil,
--- and missing `what`, without one.
function T.square(self, opts, what)
    opts = opts or {}
    local picked = {}
    for key, value in pairs(opts) do
        picked[key] = value
    end
    picked.near = squareOf(opts.near)
    return (T.need(self, T.squares(self, 1, picked), what) or {})[1]
end

--- Queues a wait until `condition()` holds on this client, then fails the test as missing `what`
--- if it still doesn't, so a copy that never came can't pass; the harness's T.waitUntil just ends.
function T.waitFor(self, condition, what, maxFrames)
    T.waitUntil(condition, maxFrames or COPY_FRAMES, what)
    T.step(function() T.need(self, condition(), what) end)
end

--- Queues setting the authority's Chance.roll until the test ends: `rolls` a number, every roll;
--- or a list, the next rolls in order, failing the call that draws one more. So a test checks
--- either side of a chance (Chance.hit) in one try each.
function T.forceRoll(self, rolls)
    T.server(self, "forceRoll", { rolls = rolls })
end

--- The first `fullType` this client's character carries, in any bag, or nil.
function T.carried(fullType)
    return T.player():getInventory():getFirstTypeRecurse(fullType)
end

--- Queues a wait until this client's character carries a `fullType`: what the server gives
--- reaches this client after its answer.
function T.waitForCarried(self, fullType, what)
    T.waitFor(self, function() return T.carried(fullType) ~= nil end, what)
end

--- Queues T.give, then an empty step: a T.server call with table args goes out ahead of T.give's
--- wait for this client's copies (sendAhead), so without the step a later call, or an action that
--- uses the items up, could run on the server before they arrive here.
function T.giveBeforeCalls(self, name, items)
    T.give(self, name, items)
    T.step(function() end)
end

-- Fixtures -------------------------------------------------------------------------------------

-- This client's copy of the bank on `square` once it holds `count` items and has a summary.
local function bankCopy(square, count)
    local bank = PowerBank.findOn(square)
    local container = bank and bank:getContainer()
    if container and container:getItems():size() >= count and PowerBank.summaryOf(bank) then
        return bank
    end
    return nil
end

--- Queues a working bank of Sprites field `kind` holding `items` (full types), filled straight
--- into its container as world spawns do, its batteries charged to `opts.charge`. It faces
--- `opts.facing` (S if nil) and stands on `opts.square`, else near `opts.near`, indoors unless
--- `opts.outdoors`. It comes connected, as a world bank does, unless `opts.connected == false`, as
--- a player's placed bank starts. Returns its handle { square, position, object }.
function T.bank(self, kind, items, opts)
    opts = opts or {}
    local square = opts.square or T.square(self, { indoors = not opts.outdoors, near = opts.near },
        "a free " .. (opts.outdoors and "outdoor" or "indoor") .. " square for a bank")
    if not square then
        return nil
    end
    local bank = { square = square, position = T.at(square) }
    local count = #(items or {})
    local connected = opts.connected ~= false
    local args = T.at(square)
    args.kind, args.facing, args.items, args.charge, args.connected = kind, opts.facing, items, opts.charge, connected
    T.server(self, "placeBank", args)
    T.waitFor(self, function()
        bank.object = bankCopy(square, count)
        return bank.object ~= nil and bank.object:isConnected() == connected
    end, "this client's copy of the bank, with its parts and summary")
    return bank
end

-- A source on the square, or a treadmill not yet wired to be one.
local function placedOn(square)
    return Sources.findOn(square) or Treadmill.findOn(square)
end

-- Whether this client has its copy of the panel and, if it was connected, sees the bank's summary
-- list it.
local function panelArrived(panel, bank)
    local here = panel.position
    return placedOn(panel.square) ~= nil
        and (not panel.connected or PowerBank.samePosition(PowerBank.bankOfSource(here.x, here.y, here.z), bank.position))
end

--- Queues a source tile of `sprite` (a panel mount, a wind charger, a treadmill) on
--- `opts.square`, else outdoors near `opts.near`, a mount holding `opts.modules` ({ { type,
--- condition } }) and placed as the moveables cursor places one. When `opts.connect`, the server's
--- character connects it to the bank handle `opts.near`; the handle gets `connected` and `reason`
--- (the refusal) from the server. A treadmill comes wired when `opts.wired`; a wind charger is its
--- build-menu entity when `opts.built`, and its blades come broken when `opts.broken`.
function T.panel(self, sprite, opts)
    opts = opts or {}
    local square = opts.square or T.square(self, { near = opts.near }, "a free outdoor square for a panel")
    if not square then
        return nil
    end
    local panel = { square = square, position = T.at(square) }
    local bank = opts.connect and opts.near
    local args = T.at(square)
    args.sprite, args.modules, args.bank, args.wired = sprite, opts.modules, bank and bank.position, opts.wired
    args.built, args.broken = opts.built, opts.broken
    T.server(self, "placePanel", args)
    T.step(function()
        panel.connected, panel.reason = self.server.placePanel.connected, self.server.placePanel.reason
    end)
    T.waitFor(self, function()
        panel.object = panelArrived(panel, bank) and placedOn(square) or nil
        return panel.object ~= nil
    end, "this client's copy of the panel")
    return panel
end

--- A panel's `modules` (T.panel's opts.modules): a factory module (RenewableEnergy.SolarModule)
--- at each condition given, in mount order.
function T.factoryModules(...)
    local modules = {}
    for i, condition in ipairs({ ... }) do
        modules[i] = { type = "RenewableEnergy.SolarModule", condition = condition }
    end
    return modules
end

--- Sets the character's skills to the levels `recipe` requires.
function T.setRecipeSkills(self, recipe)
    for i = 0, recipe:getRequiredSkillCount() - 1 do
        local skill = recipe:getRequiredSkill(i)
        T.setPerk(self, skill:getPerk(), skill:getLevel())
    end
end

--- Queues a Base.Generator plugged in on `opts.square`, else near `opts.near` but at least
--- `opts.minDistance` away, with `opts.fuel` litres, running if `opts.running`, with a failsafe
--- beside it if `opts.failsafe`. When the test ends the server removes it and this client lets go
--- of its squares (RenewableEnergy.Debug.releaseGeneratorPower). Returns { x, y, z, square, object }.
function T.generator(self, opts)
    opts = opts or {}
    local square = opts.square
        or T.square(self, { near = opts.near, minDistance = opts.minDistance or 2 }, "a free square for a generator")
    if not square then
        return nil
    end
    local handle = T.at(square)
    handle.square = square
    local args = T.at(square)
    args.fuel, args.running, args.failsafe = opts.fuel, opts.running, opts.failsafe
    T.server(self, "placeGenerator", args)
    T.step(function()
        T.defer(self, function() RenewableEnergy.Debug.releaseGeneratorPower(handle.x, handle.y, handle.z) end)
    end)
    T.waitFor(self, function()
        handle.object = square:getGenerator()
        return handle.object ~= nil
    end, "this client's copy of the generator")
    return handle
end

--- Queues a job at `square`: the character goes next to it unless it already stands where the
--- last T.doJob put it, then `makeAction()`'s action is queued. Decided when the queue reaches it,
--- so a teleport between jobs counts.
function T.doJob(self, square, makeAction)
    T.step(function()
        local p = T.player()
        if self.jobSquare ~= square or self.jobStand ~= p:getCurrentSquare() then
            T.goNextTo(self, square)
            T.step(function() self.jobSquare, self.jobStand = square, T.player():getCurrentSquare() end)
        end
        T.step(function() ISTimedActionQueue.add(makeAction()) end)
    end)
end

--- Queues a lit flashlight in the character's secondary hand: light to work by indoors, where the
--- tests' daylight hour doesn't reach. A light in hand is never too dark (IsoPlayer.tooDarkToRead).
function T.holdLight(self)
    T.give(self, "light", { { type = "Base.Torch", equip = "secondary" } })
    T.step(function() self.items.light[1]:setActivated(true) end)
end

--- The submenu `option` opens in `context`, or nil.
function T.subMenu(context, option)
    return option and option.subOption and context:getSubMenu(option.subOption)
end

--- The submenu labelled `label` that vanilla's right-click menu (ISWorldObjectContextMenu.createMenu)
--- builds for `object`, and the context menu, to hide once read.
function T.worldSubmenu(object, label)
    local context = ISWorldObjectContextMenu.createMenu(0, { object }, 0, 0)
    if type(context) ~= "table" then
        return nil, nil
    end
    return T.subMenu(context, context:getOptionFromName(label)), context
end

--- The server handlers' name for a T.placeVehicle handle's vehicle. Call it once the server has
--- answered, as in a T.server args function.
function T.vehicleArgs(vehicle)
    return { id = vehicle.id, x = vehicle.x, y = vehicle.y, z = vehicle.z }
end

--- The battery in this client's copy of the vehicle of a T.placeVehicle handle, or nil.
function T.vehicleBattery(vehicle)
    local part = RenewableEnergy.VehicleBattery.partOf(vehicle.vehicle)
    return part and part:getInventoryItem()
end

--- The shared T.placeVehicle, then, on the server, the battery replaced by a new `opts.battery`
--- and charged to `opts.charge`, and a wait until this client's copy has that battery.
function T.placeVehicle(self, script, opts)
    opts = opts or {}
    local vehicle = PZHarness.Test.placeVehicle(self, script,
        { square = opts.square, near = opts.near, facing = opts.facing, args = opts.args })
    if opts.battery or opts.charge then
        T.server(self, "vehicleBattery", function()
            return { vehicle = T.vehicleArgs(vehicle), type = opts.battery, uses = opts.charge }
        end)
        T.waitFor(self, function()
            local item = T.vehicleBattery(vehicle)
            return item ~= nil and (not opts.battery or item:getFullType() == opts.battery)
                and (not opts.charge or math.abs(item:getCurrentUsesFloat() - opts.charge) < 0.001)
        end, "this client's copy of the vehicle's new battery")
    end
    return vehicle
end

-- Banks ----------------------------------------------------------------------------------------

-- Queues the server handler `name` on `bank` and leaves the bank's state in bank.state.
local function onBank(self, bank, name, args)
    args.bank = bank.position
    T.server(self, name, args)
    T.step(function() bank.state = self.server[name] end)
end

--- Queues reading the server's record of `bank` into bank.state.
function T.bankState(self, bank)
    T.server(self, "bankState", bank.position)
    T.step(function() bank.state = self.server.bankState end)
end

--- Queues the bank system's own pass of `bank` over the last `opts.hours` (1 if nil) on the
--- server, with the sky the test sets: `light` W/m² on every mount, snow falling if
--- `opts.snowing`, else clear, at `opts.airC` °C (mild if nil), `opts.stormHours` of storm and a
--- wind of `opts.windKph`. Runs a bank whose chunk is unloaded too.
function T.bankPass(self, bank, light, opts)
    opts = opts or {}
    T.server(self, "bankPass", { bank = bank.position, light = light, hours = opts.hours, stormHours = opts.stormHours,
        windKph = opts.windKph, snowing = opts.snowing, airC = opts.airC })
    T.step(function() bank.state = self.server.bankPass end)
end

--- Queues a snowfall on `bank`'s panels on the server: its pass over the last `hours` (1 if nil)
--- of a frosty night with snow falling, which settles on every mount that holds snow.
function T.snowfall(self, bank, hours)
    T.bankPass(self, bank, 0, { hours = hours or 1, snowing = true, airC = -10 })
end

--- The watts appliances of the kinds `names` draw together, at vanilla's figures
--- (RenewableEnergy.Loot.applianceWatts).
function T.applianceWatts(names)
    local watts = 0
    for _, name in ipairs(names) do
        watts = watts + RenewableEnergy.Loot.applianceWatts(name)
    end
    return watts
end

--- Queues replacing the measured load of `bank` with appliances of the kinds `names`, and letting
--- the bank cut or restore its power and send its status. For the window tests, which are about
--- how a load of given kinds shows; a pass measures the real load again.
function T.applyLoad(self, bank, names)
    local appliances = {}
    for i, name in ipairs(names) do
        appliances[i] = { name = name, watts = T.applianceWatts({ name }) }
    end
    onBank(self, bank, "applyLoad", { appliances = appliances })
end

--- Queues charging every battery in `bank` to `charge` on the server, as the batteries carry their
--- charge, and the bank reading them again.
function T.setCharge(self, bank, charge)
    onBank(self, bank, "setCharge", { charge = charge })
end

--- Queues setting the condition of the first `fullType` in `bank` on the server, and its repair
--- count if `repaired`, and letting the bank read its parts again if `recount`.
function T.setPartCondition(self, bank, fullType, condition, recount, repaired)
    onBank(self, bank, "setPartCondition", { type = fullType, condition = condition, recount = recount, repaired = repaired })
end

--- The condition a new `fullType` battery keeps after one day's discharge `depth` deep at a
--- Battery Wear of 100: Battery.cycleWear's fraction of its ConditionMax, in whole points.
function T.conditionAfterDischarge(fullType, depth)
    local battery = instanceItem(fullType)
    local max = battery:getConditionMax()
    return max - math.floor(RenewableEnergy.Battery.cycleWear(battery, depth) * max)
end

--- The summary of `bank` (a handle) as this client last received it, or nil.
function T.clientSummary(bank)
    return bank.object and PowerBank.summaryOf(bank.object)
end

--- The whole status of `bank` as this client last received it, or nil. It comes only while this
--- client watches the bank (T.watch, or an open status window).
function T.clientStatus(bank)
    return bank.object and PowerBank.statusOf(bank.object)
end

--- Queues watching `bank`'s status as the status window does, until the test ends, and a wait
--- until this client has it.
function T.watch(self, bank)
    T.step(function()
        local p = T.player()
        PowerBank.watchStatus(p, bank.object)
        T.defer(self, function() PowerBank.unwatchStatus(p, bank.object) end)
    end)
    T.waitFor(self, function() return T.clientStatus(bank) ~= nil end, "this client's copy of the bank's status")
end

--- The server's entry for the first `fullType` in a bank state's items, or nil.
function T.stateItem(state, fullType)
    for _, item in ipairs(state and state.items or {}) do
        if item.type == fullType then
            return item
        end
    end
end

-- The first entry of a bank state's status sources that `matches`, or nil.
local function stateSource(state, matches)
    for _, source in ipairs(state and state.status and state.status.sources or {}) do
        if matches(source) then
            return source
        end
    end
    return nil
end

--- The status entry of the source at `position` in a bank state, or nil.
function T.stateSource(state, position)
    return stateSource(state, function(source) return PowerBank.samePosition(source, position) end)
end

--- The status entry of the first source of `kind` in a bank state, or nil.
function T.stateSourceOfKind(state, kind)
    return stateSource(state, function(source) return source.kind == kind end)
end

--- The first `fullType` in this client's copy of `bank` (a handle), or nil.
function T.copyItem(bank, fullType)
    return bank.object:getContainer():getFirstType(fullType)
end

--- The charge of the first `fullType` in this client's copy of `bank`, or -1.
function T.copyUses(bank, fullType)
    local item = T.copyItem(bank, fullType)
    return item and item:getCurrentUsesFloat() or -1
end

--- Queues the bank system's command `command` on the authority as the server's character, the way
--- a timed action's complete() runs it: the server takes no such command from a client. With
--- `item` ({ type, inBank }), the server fills in args.itemId itself, so the call needs no earlier
--- answer and can go out in a T.batch. Its answer lands in self.server.perform.
function T.perform(self, command, args, item)
    T.server(self, "perform", { command = command, args = args, item = item })
end

--- Queues T.perform and leaves its answer in self[key].
function T.performInto(self, key, command, args, item)
    T.perform(self, command, args, item)
    T.step(function() self[key] = self.server.perform end)
end

--- Checks that the panel fixture `panel` connected, saying why not.
function T.expectConnected(panel)
    return T.expect(panel.connected, "connecting the panel failed (" .. tostring(panel.reason) .. ")")
end

--- Queues switching `bank` on with the bank system's command, and a wait until this client's
--- summary says it is on, whatever the bank then does.
function T.switchOn(self, bank)
    T.perform(self, "setBankOn", { bank = bank.position, on = true })
    T.waitFor(self, function()
        local summary = T.clientSummary(bank)
        return summary ~= nil and summary.on == true
    end, "this client's copy of the bank's summary, switched on")
end

--- The overlays `object` shows, as sprite names joined by commas in drawing order, the form a
--- bank state's `overlays` takes. The helper loads after client Lua, so it is required here.
function T.overlays(object)
    local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
    return table.concat(Helpers.overlaysOf(object), ",")
end

--- Chooses a context menu option the way a click does.
function T.choose(option)
    option.onSelect(option.target, option.param1, option.param2, option.param3, option.param4)
end

-- Menus and the status window -----------------------------------------------------------------

function T.newContext()
    return ISContextMenu.get(0, 0, 0)
end

function T.optionNamed(menu, name)
    return menu and menu.getOptionFromName and menu:getOptionFromName(name)
end

function T.tooltipOf(option)
    return option and option.toolTip and option.toolTip.description
end

--- What a context menu option (nil when not offered) shows: { shown, greyed, reason }.
function T.optionState(option)
    if not option then
        return { shown = false, greyed = false }
    end
    return { shown = true, greyed = option.notAvailable == true, reason = T.tooltipOf(option) }
end

--- Stands the character next to `square` so vanilla's walkAdj has nowhere to go, then makes that
--- walk, as the menu does before an action: a multiplayer server refuses a job from afar.
function T.walkTo(self, square, what)
    T.standNextTo(square)
    return T.need(self, luautils.walkAdj(T.player(), square, true), "a walk to " .. what)
end

--- Opens the status window on self.bank, closed when the test ends, and waits until it has drawn
--- the bank's status. The character stands next to the bank first, where the menu's Status walks
--- them, as the window closes once they are out of reach.
function T.openWindow(self)
    T.standNextTo(self.bank.square)
    local window = RenewableEnergy.StatusWindow:openOn(0, self.bank.object)
    self.window = window
    T.defer(self, function() window:close() end)
    T.waitFor(self, function() return (window.renderedFrames or 0) > 0 end, "the status window drawing the bank's status")
end

-- Crafting -------------------------------------------------------------------------------------

--- The test name for `recipe` in `system`'s tests: "solar", "RenewableEnergy_TakeApartSolarCellCharger",
--- "returns_x" -> "renewable_energy_solar_craft_take_apart_solar_cell_charger_returns_x".
function T.craftName(system, recipe, behavior)
    return "renewable_energy_" .. system .. "_craft_" .. T.snake((recipe:gsub("^RenewableEnergy_", "")))
        .. (behavior and "_" .. behavior or "")
end

--- The given inputs (T.craftTest's self.items.inputs) of `fullType`.
function T.inputsOf(self, fullType)
    local found = {}
    for _, item in ipairs(self.items.inputs or {}) do
        if item:getFullType() == fullType then
            table.insert(found, item)
        end
    end
    return found
end

--- Queues reading the authority's copies of `types` and its litres of `fluids` into
--- self.server.carried (see the carried handler), whose `total` counts its main inventory.
function T.readCarried(self, types, fluids)
    T.server(self, "carried", { types = types, fluids = fluids })
end

--- The authority's items of `fullType` from the last T.readCarried, in a list, empty if none.
function T.carriedItems(self, fullType)
    return self.server.carried and self.server.carried.items[fullType] or {}
end

--- The authority's first item of `fullType` from the last T.readCarried, or nil.
function T.carriedFirst(self, fullType)
    return T.carriedItems(self, fullType)[1]
end

--- The authority's litres of `fluid` from the last T.readCarried, or nil.
function T.carriedLitres(self, fluid)
    return self.server.carried and self.server.carried.fluids[fluid]
end

--- Queues setting the repair count of the carried `fullType` items on the authority, and a wait
--- until this client's copy has it: the craft reads this client's copy.
function T.setRepaired(self, fullType, repaired)
    T.server(self, "setRepaired", { type = fullType, repaired = repaired })
    T.waitFor(self, function()
        local item = T.carried(fullType)
        return item ~= nil and item:getHaveBeenRepaired() == repaired
    end, "this client's " .. fullType .. " repaired " .. repaired .. "x")
end

-- Data -----------------------------------------------------------------------------------------

--- `name` in snake case, for test names: "HomesteadPowerMag1" -> "homestead_power_mag1".
function T.snake(name)
    return string.lower((name:gsub("(%l)(%u)", "%1_%2"):gsub("(%d)(%u)", "%1_%2")))
end

-- Every placed tile: the item picking it up gives, what Sprites.kindOf reports, and whether it
-- holds items.
T.PLACED_TILES = {
    { sprite = Sprites.flat, item = "RenewableEnergy.SolarFlat", kind = "flat" },
    { sprite = Sprites.failsafe, item = "RenewableEnergy.SolarFailsafe", kind = "failsafe" },
    { sprite = Sprites.cellCharger, item = RenewableEnergy.SolarCellCharger.ITEM, kind = "cellCharger", container = true },
    { sprite = Sprites.gardenLight.off, item = RenewableEnergy.SolarGardenLight.ITEM, kind = "gardenLight" },
    { sprite = Sprites.gardenLight.lit, item = RenewableEnergy.SolarGardenLight.ITEM, kind = "gardenLight" },
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
        for facing, sprite in pairs(Sprites[field]) do
            table.insert(T.PLACED_TILES, { sprite = sprite, item = "RenewableEnergy.Battery" .. tier .. suffix,
                kind = field, facing = facing, material = material, container = true })
        end
    end
end
-- The fixed tiles a save's banks may stand on (Sprites.fixedTiles), each as its turnable twin.
for fixed, twin in pairs(Sprites.fixedTiles) do
    for _, placed in ipairs(T.PLACED_TILES) do
        if placed.sprite == twin then
            table.insert(T.PLACED_TILES, { sprite = fixed, item = placed.item, kind = placed.kind, facing = placed.facing,
                material = placed.material, container = placed.container })
            break
        end
    end
end

-- How far the character goes for a chunk to unload, and the longest that and its loading again
-- may take, in ticks.
local AWAY = 600
local CHUNK_FRAMES = 6000
-- How long the character stays away once the chunk has unloaded, in real milliseconds. Back at
-- once, a chunk has been seen to load with a vehicle a test had removed before the trip, as an
-- earlier save of it held it; the game hot-saves loaded chunks every second
-- (IsoChunkMap.hotSaveFrequency).
local AWAY_MS = 2000

--- Lets `self` move the character until the test ends: returns teleport(x, y, z), which asks for
--- the move, made on the next tick, as a teleport from inside a timed action doesn't stick.
function T.teleporter(self)
    local p, target = T.player(), nil
    T.onTick(self, function()
        if target then
            p:teleportTo(target[1], target[2], target[3])
            target = nil
        end
    end)
    return function(x, y, z) target = { x, y, z } end
end

--- Queues a trip that unloads the chunk of the square at x, y, z and loads it again: the
--- character goes AWAY squares east of `home` ({ x, y, z }) and back. `whileAway()`, if given, is
--- queued while the chunk is unloaded. A trip that doesn't unload the chunk, or brings it back
--- without LoadChunk (from a cache, with its state), misses its fixture.
function T.awayAndBack(self, home, x, y, z, whileAway)
    local p = T.player()
    local teleport = T.teleporter(self)
    -- `home` may be filled in by a queued step that a failed test never reached.
    T.defer(self, function()
        if home.x then
            p:teleportTo(home.x + 0.5, home.y + 0.5, home.z)
        end
    end)
    local loads = 0
    local function onLoadChunk(chunk)
        local origin = chunk:getGridSquare(0, 0, 0)
        local dx, dy = origin and x - origin:getX(), origin and y - origin:getY()
        if origin and dx >= 0 and dx < 8 and dy >= 0 and dy < 8 then
            loads = loads + 1
        end
    end
    Events.LoadChunk.Add(onLoadChunk)
    T.defer(self, function() Events.LoadChunk.Remove(onLoadChunk) end)
    T.step(function() teleport(home.x + AWAY + 0.5, home.y + 0.5, 0) end)
    T.waitFor(self, function() return getSquare(x, y, z) == nil end, "the fixture's chunk unloaded", CHUNK_FRAMES)
    local awaySince
    T.waitFor(self, function()
        awaySince = awaySince or getTimestampMs()
        return getTimestampMs() - awaySince >= AWAY_MS
    end, "a stay away from the fixture's chunk", CHUNK_FRAMES)
    if whileAway then
        whileAway()
    end
    T.step(function() teleport(home.x + 0.5, home.y + 0.5, home.z) end)
    T.waitFor(self, function() return getSquare(x, y, z) ~= nil end, "the fixture's chunk loaded again", CHUNK_FRAMES)
    T.step(function() T.need(self, loads > 0, "the fixture's chunk loaded again through LoadChunk") end)
end

return T
