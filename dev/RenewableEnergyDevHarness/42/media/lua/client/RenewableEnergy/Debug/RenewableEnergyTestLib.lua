require "PZHarness/TestLib"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/Gadgets/VehicleBattery"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/UI/StatusWindow"

-- Helpers for the RenewableEnergyTests*.lua files: the shared harness's test library
-- (dev/harness/mod/42/media/lua/client/PZHarness/TestLib.lua explains the runner and the rules
-- every helper keeps), plus the fixtures that know this mod's objects, which push their undos the
-- same way. RenewableEnergyTestSettings.lua gives the library this mod's settings.
--
-- Banks and panels live on the authority, so their fixtures are built by the dev mod's server
-- handlers (server/RenewableEnergy/Debug/RenewableEnergyTestServer.lua) through T.server, in this
-- game in single player and on the server in multiplayer, and removed there when the test ends.
-- A fixture is a handle: the square is picked at once, so later fixtures can be placed near it,
-- and `object` is filled in on the queue once this client has its copy of what the server built.
-- The bank helpers read and drive the server's record of a bank, leaving its state (see stateOf
-- in the server file) in the handle's `state`.
RenewableEnergyTest = setmetatable({}, { __index = PZHarness.Test })
local T = RenewableEnergyTest

local PowerBank, Sprites = RenewableEnergy.PowerBank, RenewableEnergy.Sprites
local Sources, Treadmill = RenewableEnergy.Sources, RenewableEnergy.Treadmill

-- The longest a fixture waits for the server's object, and the bank's status, to reach this
-- client, in ticks. Single player has them at once; a multiplayer server sends them a tick or more
-- after it built them, in real time, so at a high frame rate this takes more ticks.
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

--- Queues a wait until `condition()` holds on this client, at most `maxFrames` ticks (by default as
--- long as a fixture waits for the server's copy), then fails the test as missing `what` if it
--- still doesn't, so a copy that never came can't pass as one that did; the harness's T.waitUntil
--- just ends.
function T.waitFor(self, condition, what, maxFrames)
    T.waitUntil(condition, maxFrames or COPY_FRAMES, what)
    T.step(function() T.need(self, condition(), what) end)
end

--- The first `fullType` this client's character carries, in any bag, or nil.
function T.carried(fullType)
    return T.player():getInventory():getFirstTypeRecurse(fullType)
end

--- Queues a wait until this client's character carries a `fullType` (T.waitFor): what the server
--- gives or moves reaches this client after its answer, and what comes next reads this client's
--- copy.
function T.waitForCarried(self, fullType, what)
    T.waitFor(self, function() return T.carried(fullType) ~= nil end, what)
end

-- Fixtures -------------------------------------------------------------------------------------

-- This client's copy of the bank on `square` once it holds `count` items and has a summary.
local function bankCopy(square, count)
    local bank = PowerBank.bankOn(square)
    local container = bank and bank:getContainer()
    if container and container:getItems():size() >= count and PowerBank.summaryOf(bank) then
        return bank
    end
    return nil
end

--- Queues a working bank of Sprites field `kind` holding `items` (full types), filled straight
--- into its container as world spawns do, its batteries charged to `opts.charge` (full by default).
--- It stands on `opts.square`, else on a free square near `opts.near` (a handle, object or square):
--- indoors unless `opts.outdoors`. It comes connected, as a world bank does, unless
--- `opts.connected == false`, as a player's placed bank starts. Returns its handle { square, position };
--- `object` is this client's copy of the bank (its IsoGenerator) once it has arrived with its parts and summary.
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
    T.server(self, "placeBank", { x = square:getX(), y = square:getY(), z = square:getZ(), kind = kind, items = items,
        charge = opts.charge, connected = connected })
    T.waitFor(self, function()
        bank.object = bankCopy(square, count)
        return bank.object ~= nil and bank.object:isConnected() == connected
    end, "this client's copy of the bank, with its parts and summary")
    return bank
end

-- A source on the square, or a treadmill not yet wired to be one.
local function placedOn(square)
    return Sources.on(square) or Treadmill.on(square)
end

-- Whether this client has its copy of the panel and, if it was connected, sees the bank's summary
-- list it.
local function panelArrived(panel, bank)
    local here = panel.position
    return placedOn(panel.square) ~= nil
        and (not panel.connected or PowerBank.samePosition(PowerBank.bankOfSource(here.x, here.y, here.z), bank.position))
end

--- Queues a panel tile of `sprite` on `opts.square`, else on a free outdoor square near
--- `opts.near` (a handle, object or square), holding `opts.modules` ({ { type, condition } }) if
--- given, placed as the moveables cursor places one and, when `opts.connect`, connected by the
--- server's character to the bank handle `opts.near`. Returns its handle { square, position };
--- the server's answer fills in `connected` and `reason` (the refusal), and `object` is this
--- client's copy once it has arrived, connection included. Any source tile goes; a treadmill's
--- comes wired when `opts.wired`.
function T.panel(self, sprite, opts)
    opts = opts or {}
    local square = opts.square or T.square(self, { near = opts.near }, "a free outdoor square for a panel")
    if not square then
        return nil
    end
    local panel = { square = square, position = T.at(square) }
    local bank = opts.connect and opts.near
    T.server(self, "placePanel", { x = square:getX(), y = square:getY(), z = square:getZ(), sprite = sprite,
        modules = opts.modules, bank = bank and bank.position, wired = opts.wired })
    T.step(function()
        panel.connected, panel.reason = self.server.placePanel.connected, self.server.placePanel.reason
    end)
    T.waitFor(self, function()
        panel.object = panelArrived(panel, bank) and placedOn(square) or nil
        return panel.object ~= nil
    end, "this client's copy of the panel")
    return panel
end

--- Queues a Base.Generator plugged in on `opts.square`, else on a free outdoor square near
--- `opts.near` (a handle, object or square) at least `opts.minDistance` (2) away, with
--- `opts.fuel` litres (the placeGenerator handler's default if nil), running if `opts.running`,
--- with a failsafe beside it if `opts.failsafe`. The server switches it off and removes it when
--- the test ends, and this client lets go of its squares (RenewableEnergy.Debug.
--- releaseGeneratorPower). Returns its handle { x, y, z, square }; `object` is this client's copy.
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

--- Queues a job at `square`: the character goes next to it (T.goNextTo), unless the last T.doJob
--- went to the same square and the character hasn't moved since, then `makeAction()`'s action is
--- queued. Decided when the queue reaches it, so a teleport between jobs counts.
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

--- The submenu labelled `label` that a right-click on `object` builds through vanilla's menu
--- builder (ISWorldObjectContextMenu.createMenu), and the context menu, to hide once read; both
--- nil when no menu was built.
function T.worldSubmenu(object, label)
    local context = ISWorldObjectContextMenu.createMenu(0, { object }, 0, 0)
    if type(context) ~= "table" then
        return nil, nil
    end
    local option = context:getOptionFromName(label)
    return option and option.subOption and context:getSubMenu(option.subOption), context
end

--- The server handlers' name for the vehicle of a T.placeVehicle handle: its id and the square
--- it went on. Call it once the server has answered, as in a T.server args function.
function T.vehicleArgs(vehicle)
    return { id = vehicle.id, x = vehicle.x, y = vehicle.y, z = vehicle.z }
end

--- The battery in this client's copy of the vehicle of a T.placeVehicle handle, or nil.
function T.vehicleBattery(vehicle)
    local part = vehicle.vehicle and vehicle.vehicle:getPartById(RenewableEnergy.VehicleBattery.PART)
    return part and part:getInventoryItem()
end

--- The shared T.placeVehicle, then the vehicle's battery replaced by a new `opts.battery` (a full
--- type) if given and charged to `opts.charge` if given, on the server, and a wait until this
--- client's copy has that battery. Returns the shared handle.
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

-- Queues the server handler `name` on `bank` with `args` and leaves its answer, the bank's state,
-- in bank.state.
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

--- Queues a pass of `opts.hours` (1 by default) of `bank` on the server, with the weather fixed
--- clear: `light` W/m² on every mount, no snow, `opts.stormHours` of storm and a wind of
--- `opts.windKph` (calm by default).
function T.bankPass(self, bank, light, opts)
    opts = opts or {}
    onBank(self, bank, "bankPass", { light = light, hours = opts.hours, stormHours = opts.stormHours, windKph = opts.windKph })
end

-- What vanilla bills a generator for an appliance of each kind the status lists, in fuel an hour
-- (IsoGenerator's *PowerConsumption constants), for loads the tests make up.
local APPLIANCE_FUEL = {
    fridgeFreezer = 0.13, fridge = 0.08, light = 0.002, television = 0.03, radio = 0.01,
    microwave = 0.09, range = 0.09, washer = 0.09, dryer = 0.09, batteryCharger = 0.05,
}

--- The watts appliances of the kinds `names` draw together, at vanilla's figures.
function T.applianceWatts(names)
    local watts = 0
    for _, name in ipairs(names) do
        watts = watts + APPLIANCE_FUEL[name] * RenewableEnergy.Specs.wattsPerFuel
    end
    return watts
end

--- Queues replacing the measured load of `bank` with appliances of the kinds `names`
--- (T.applianceWatts), as if the scan had found them switched on, and letting the bank react: cut
--- or restore its power and send its status. The next pass measures the real load again.
function T.applyLoad(self, bank, names)
    local appliances = {}
    for i, name in ipairs(names) do
        appliances[i] = { name = name, watts = T.applianceWatts({ name }) }
    end
    onBank(self, bank, "applyLoad", { appliances = appliances })
end

--- Queues setting fields of the server's record of `bank` (`charge`, `on`), and writing its
--- charge into its batteries if `writeBatteries`.
function T.bankSet(self, bank, fields, writeBatteries)
    onBank(self, bank, "bankSet", { fields = fields, writeBatteries = writeBatteries })
end

--- Queues setting the condition of the first `fullType` in `bank` on the server, and its repair
--- count if `repaired`, and letting the bank read its parts again if `recount`.
function T.setPartCondition(self, bank, fullType, condition, recount, repaired)
    onBank(self, bank, "setPartCondition", { type = fullType, condition = condition, recount = recount, repaired = repaired })
end

--- The summary of `bank` (a handle) as this client last received it, or nil.
function T.clientSummary(bank)
    return bank.object and PowerBank.summaryOf(bank.object)
end

--- The whole status of `bank` (a handle) as this client last received it, or nil. It comes only
--- while this client watches the bank (T.watch, or an open status window).
function T.clientStatus(bank)
    return bank.object and PowerBank.statusOf(bank.object)
end

--- Queues watching the status of `bank` (a handle) as the status window does, until the test
--- ends, and a wait until this client has it.
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

--- The first `fullType` in this client's copy of `bank` (a handle), or nil.
function T.copyItem(bank, fullType)
    return bank.object:getContainer():getFirstType(fullType)
end

--- Queues the bank system's command `command` with `args` on the authority as the server's
--- character, the way a timed action's complete() runs it: the server takes no such command from a
--- client. With `item` ({ type = full type, inBank = true for the first in the bank `args.bank`,
--- else the first the character carries }), the server puts that item's id in args.itemId when the
--- call runs, so the call needs no earlier answer and can go out in a T.batch. Its answer, { ok,
--- reason, xpBefore, xpAfter }, lands in self.server.perform.
function T.perform(self, command, args, item)
    T.server(self, "perform", { command = command, args = args, item = item })
end

--- Queues T.perform and leaves its answer in self[key].
function T.performInto(self, key, command, args, item)
    T.perform(self, command, args, item)
    T.step(function() self[key] = self.server.perform end)
end

--- The charge of the first `fullType` in this client's copy of `bank`, or -1.
function T.copyUses(bank, fullType)
    local item = T.copyItem(bank, fullType)
    return item and item:getCurrentUsesFloat() or -1
end

--- Checks that the panel fixture `panel` connected, saying why not.
function T.expectConnected(panel)
    return T.expect(panel.connected, "connecting the panel failed (" .. tostring(panel.reason) .. ")")
end

--- Queues switching `bank` on with the bank system's command, and a wait until this client's copy
--- of its summary says it is on, whatever the bank then does.
function T.switchOn(self, bank)
    T.perform(self, "setBankOn", { bank = bank.position, on = true })
    T.waitFor(self, function()
        local summary = T.clientSummary(bank)
        return summary ~= nil and summary.on == true
    end, "this client's copy of the bank's summary, switched on")
end

--- The overlays `object` shows, as their sprite names joined by commas, in order; a server's
--- answer lists them the same way (`overlays` in a bank state), joined with table.concat. Both
--- read them with the server handlers' helper, which loads after client Lua, so it is required
--- when a test runs.
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

--- Stands the character next to `square` so the walk vanilla's walkAdj queues first has no way to
--- go (T.standNextTo), then makes that walk, as the menu does before an action: a multiplayer
--- server refuses a job from afar. False, with the walk missing from the test, when it fails.
function T.walkTo(self, square, what)
    T.standNextTo(square)
    return T.need(self, luautils.walkAdj(T.player(), square, true), "a walk to " .. what)
end

--- Opens the window of this client's copy of self.bank, closed again when the test ends, and
--- queues a wait until the bank's status has come and the window has drawn it.
function T.openWindow(self)
    local window = RenewableEnergy.StatusWindow.open(0, self.bank.object)
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

--- The given inputs (this client's copies, T.craftTest's self.items.inputs) of `fullType`.
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
--- self.server.carried (see the carried handler).
function T.readCarried(self, types, fluids)
    T.server(self, "carried", { types = types, fluids = fluids })
end

--- The authority's first item of `fullType` from the last T.readCarried, or nil.
function T.carriedFirst(self, fullType)
    local items = self.server.carried and self.server.carried.items[fullType]
    return items and items[1]
end

--- Queues setting the repair count of the carried `fullType` items on the authority, and a wait
--- until this client's copy has it: the craft tests its own copy.
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

-- Every placed tile: the item picking it up gives, what Sprites.kindOf reports (kind, facing,
-- material), and whether it holds items.
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
        table.insert(T.PLACED_TILES, { sprite = Sprites[field], item = "RenewableEnergy.Battery" .. tier .. suffix,
            kind = field, material = material, container = true })
    end
end

return T
