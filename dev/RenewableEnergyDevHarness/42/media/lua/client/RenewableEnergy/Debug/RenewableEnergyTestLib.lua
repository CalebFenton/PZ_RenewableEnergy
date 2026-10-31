require "PZHarness/TestCraft"
require "PZHarness/TestMenus"
require "PZHarness/TestChunks"
require "PZHarness/TestBuild"
require "PZHarness/TestLearning"
require "PZHarness/TestReads"
require "PZHarness/TestRecords"
require "PZHarness/TestJobs"
local Capture = require "PZHarness/Capture"
local Squares = require "cf_commonlib/Squares"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local BankMenu = require "RenewableEnergy/UI/BankMenu"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local ClientBankSystem = require "RenewableEnergy/PowerBank/ClientBankSystem"
local Format = require "RenewableEnergy/UI/Format"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local SourceMenu = require "RenewableEnergy/UI/SourceMenu"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Specs = require "RenewableEnergy/Specs"
local StatusWindow = require "RenewableEnergy/UI/StatusWindow"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"
local Yardsticks = require "RenewableEnergy/Debug/RenewableEnergyYardsticks"

-- Helpers for the RenewableEnergyTests*.lua files: the shared harness's test library
-- (PZHarness/TestLib.lua explains the runner and the rules every helper keeps), plus fixtures
-- that know this mod's banks and panels.
--
-- Banks and panels live on the authority, so their fixtures are built through T.server by the
-- dev mod's server handlers (RenewableEnergyTestServer.lua) and removed there when the test ends.
-- A fixture's square is picked at once, so later fixtures can be placed near it; its `object` is
-- filled in once this client has its copy of what the server built.
RenewableEnergyTest = setmetatable({}, { __index = PZHarness.Test })
local T = RenewableEnergyTest

--- The parts, items and appliances the tests place, wire in and craft.
T.PLUG_IN_INVERTER, T.POWER_INVERTER = "RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter"
T.INVERTER_CHARGER = "RenewableEnergy.InverterCharger"
T.CAR_BATTERY, T.DEEP_CYCLE = VehicleBattery.CAR_BATTERY, VehicleBattery.ITEM
T.L16, T.JAR_BATTERY = "RenewableEnergy.L16Battery", "RenewableEnergy.JarBattery"
T.FACTORY_MODULE, T.HOMEMADE_MODULE = Specs.factoryModule, "RenewableEnergy.HomemadeSolarModule"
T.MINI_FRIDGE = "appliances_refrigeration_01_25"

--- Expects the character to stand in the dark (IsoPlayer.tooDarkToRead), as T.makeDark leaves them.
function T.expectDark()
    return T.expect(T.player():tooDarkToRead(), "midnight with the grid off isn't dark where the character stands")
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
--- a player's placed bank starts. Returns its record handle (T.where, kind "bank").
function T.bank(self, kind, items, opts)
    opts = opts or {}
    local square = opts.square or T.square(self, { indoors = not opts.outdoors, near = opts.near },
        "a free " .. (opts.outdoors and "outdoor" or "indoor") .. " square for a bank")
    if not square then
        return nil
    end
    local bank = T.where(square)
    bank.kind = "bank"
    local count = #(items or {})
    local connected = opts.connected ~= false
    T.server(self, "placeBank",
        T.at(square, { kind = kind, facing = opts.facing, items = items, charge = opts.charge, connected = connected }), function()
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
    return placedOn(panel.square) ~= nil
        and (not panel.connected or Squares.samePosition(PowerBank.bankOfSource(panel.x, panel.y, panel.z), bank))
end

--- Queues a source tile of `sprite` (a panel mount, a wind charger, a treadmill) on
--- `opts.square`, else outdoors near `opts.near`, a mount holding `opts.modules` ({ { type,
--- condition } }) and placed as the moveables cursor places one. When `opts.connect`, the server's
--- character connects it to the bank handle `opts.near`; the handle gets `connected` and `reason`
--- (the refusal) from the server. A treadmill comes wired when `opts.wired`; a wind charger is its
--- build-menu entity when `opts.built`, and its blades come broken when `opts.broken`. Returns its
--- handle (T.where).
function T.panel(self, sprite, opts)
    opts = opts or {}
    local square = opts.square or T.square(self, { near = opts.near }, "a free outdoor square for a panel")
    if not square then
        return nil
    end
    local panel = T.where(square)
    local bank = opts.connect and opts.near
    T.server(self, "placePanel", T.at(square, { sprite = sprite, modules = opts.modules, bank = bank and T.at(bank),
        wired = opts.wired, built = opts.built, broken = opts.broken }), function(reply)
        panel.connected, panel.reason = reply.connected, reply.reason
        panel.object = panelArrived(panel, bank) and placedOn(square) or nil
        return panel.object ~= nil
    end, "this client's copy of the panel")
    return panel
end

--- A panel's `modules` (T.panel's opts.modules): a T.FACTORY_MODULE at each condition given, in
--- mount order.
function T.factoryModules(...)
    local modules = {}
    for i, condition in ipairs({ ... }) do
        modules[i] = { type = T.FACTORY_MODULE, condition = condition }
    end
    return modules
end

--- Queues the character doing the job `job` of `feature` (RenewableEnergyAction) on the tile of
--- `handle` (a fixture or record handle), as its menu queues it, through T.doJob. `with` is what
--- the job works with: an item, a name or slot, or a handle at the far end (its object is taken);
--- or a function, called when the job is queued, returning one, for what the queue gives first.
function T.actionJob(self, feature, handle, job, with)
    T.doJob(self, handle.square, function()
        local what = type(with) == "function" and with() or with
        if type(what) == "table" then
            what = what.object
        end
        return RenewableEnergyAction:new(T.player(), feature, job, handle.object, what)
    end)
end

--- Queues a lit flashlight in the character's secondary hand: light to work by indoors, where the
--- tests' daylight hour doesn't reach. A light in hand is never too dark (IsoPlayer.tooDarkToRead).
function T.holdLight(self)
    T.give(self, "light", { { type = "Base.Torch", equip = "secondary" } })
    T.step(function() self.items.light[1]:setActivated(true) end)
end

--- The battery in this client's copy of the vehicle of a T.placeVehicle handle, or nil.
function T.vehicleBattery(vehicle)
    local part = VehicleBattery.partOf(vehicle.vehicle)
    return part and part:getInventoryItem()
end

--- Queues the server handler `name` on the vehicle with `args` (a table, or a function called
--- when the call goes out); its answer goes in self.reads[label] when given (T.read), and any
--- state in it in vehicle.state, which waits on this client's copy compare against.
function T.onVehicle(self, vehicle, name, args, label)
    local function allArgs()
        local all = T.at(vehicle, type(args) == "function" and args() or args)
        all.id = vehicle.id
        return all
    end
    -- Queued once the vehicle is placed, the call can go out ahead of its turn (T.server, T.batch).
    T.read(self, name, (vehicle.id and type(args) ~= "function") and allArgs() or allArgs, label)
    T.step(function() vehicle.state = self.server[name].state or vehicle.state end)
end

--- The shared T.placeVehicle, then, on the server, the battery replaced by a new `opts.battery`
--- and charged to `opts.charge`, and a wait until this client's copy has that battery.
function T.placeVehicle(self, script, opts)
    opts = opts or {}
    local vehicle = PZHarness.Test.placeVehicle(self, script, opts)
    if opts.battery or opts.charge then
        T.onVehicle(self, vehicle, "vehicleBattery", { type = opts.battery, uses = opts.charge })
        T.waitFor(self, function()
            local item = T.vehicleBattery(vehicle)
            return item ~= nil and (not opts.battery or item:getFullType() == opts.battery)
                and (not opts.charge or math.abs(item:getCurrentUsesFloat() - opts.charge) < 0.001)
        end, "this client's copy of the vehicle's new battery")
    end
    return vehicle
end

-- Banks ----------------------------------------------------------------------------------------
-- A bank's reads (T.readRecord and the handlers below, through T.onRecord) land in bank.state,
-- which waits on this client's copy compare against.

--- Queues the bank system's own pass of `bank` over the last `opts.hours` (1 if nil) on the
--- server, with the sky the test sets: `light` W/m² on every mount, snow falling if
--- `opts.snowing`, else clear, at `opts.airC` °C (mild if nil), `opts.stormHours` of storm and a
--- wind of `opts.windKph`. Runs a bank whose chunk is unloaded too. Its read lands as
--- T.readRecord's, in self.reads[opts.label] too when given.
function T.bankPass(self, bank, light, opts)
    opts = opts or {}
    T.onRecord(self, bank, "bankPass", { light = light, hours = opts.hours, stormHours = opts.stormHours,
        windKph = opts.windKph, snowing = opts.snowing, airC = opts.airC }, opts.label)
end

--- Queues a snowfall on `bank`'s panels on the server: its pass over the last `hours` (1 if nil)
--- of a frosty night with snow falling, which settles on every mount that holds snow. Its read
--- lands as T.bankPass's, in self.reads[label] too when given.
function T.snowfall(self, bank, hours, label)
    T.bankPass(self, bank, 0, { hours = hours or 1, snowing = true, airC = -10, label = label })
end

--- What a fridge adds to a bank's load, at vanilla's figures (Yardsticks.applianceWatts). The
--- tests' area has appliances of its own, so each test reads what one fridge it places adds.
function T.fridgeW()
    return Yardsticks.applianceWatts("fridgeFreezer")
end

--- Queues replacing the measured load of `bank` with appliances of the kinds `names`, and letting
--- the bank cut or restore its power and send its status. For the window tests, which are about
--- how a load of given kinds shows; a pass measures the real load again.
function T.applyLoad(self, bank, names)
    local appliances = {}
    for i, name in ipairs(names) do
        appliances[i] = { name = name, watts = Yardsticks.applianceWatts(name) }
    end
    T.onRecord(self, bank, "applyLoad", { appliances = appliances })
end

--- Queues charging every battery in `bank` to `charge` on the server, as the batteries carry their
--- charge, and the bank reading them again.
function T.setCharge(self, bank, charge)
    T.onRecord(self, bank, "setCharge", { charge = charge })
end

--- Queues changing the first `fullType` in `bank` on the server (the "bankPart" handler):
--- `changes` { condition, repaired, wear, remove, recount }.
function T.bankPart(self, bank, fullType, changes)
    changes.type = fullType
    T.onRecord(self, bank, "bankPart", changes)
end

--- The condition a new `fullType` battery keeps after one day's discharge `depth` deep at a
--- Battery Wear of 100: Battery.cycleWear's fraction of its ConditionMax, in whole points.
function T.conditionAfterDischarge(fullType, depth)
    local battery = instanceItem(fullType)
    local max = battery:getConditionMax()
    return max - math.floor(Battery.cycleWear(battery, depth) * max)
end

--- The whole status of `bank` as this client last received it, or nil. It comes only while this
--- client watches the bank (T.watch, or an open status window).
function T.clientStatus(bank)
    return bank.object and PowerBank.statusOf(bank.object)
end

--- Queues a wait until this client's status of `bank` satisfies `check(status)`; missing `what`
--- if it never does.
function T.waitForStatus(self, bank, check, what)
    T.waitFor(self, function()
        local status = T.clientStatus(bank)
        return status ~= nil and check(status)
    end, what)
end

--- Queues moving the clock to a minute before `hour` at ten times speed, so that the clock itself
--- crosses the hour (a jump fires EveryTenMinutes, but EveryHours needs a crossing inside
--- GameTime.update), and a wait until this client has the status of `bank`'s pass at that crossing;
--- missing `what` if it never comes. `bank` is watched (T.watch). A pass is
--- stamped with the world's age (Clock.now), which can lag the time of day setTime sets by most of a
--- minute, so the time of day can't pick it out: the jump puts it about an hour past the last
--- status, while anything else that settles the bank meanwhile counts minutes.
function T.runToHourlyPass(self, bank, hour, what)
    local last
    T.step(function()
        last = T.clientStatus(bank).hour
        T.setTime(self, hour - 1 / 60)
        T.setMultiplier(self, 10)
    end)
    T.waitForStatus(self, bank, function(status) return status.hour >= last + 0.5 end, what)
end

--- Queues watching `bank`'s status as the status window does, until the test ends, and a wait
--- until this client has it.
function T.watch(self, bank)
    T.step(function()
        local p = T.player()
        ClientBankSystem.watchStatus(p, bank.object)
        T.defer(self, function() ClientBankSystem.unwatchStatus(p, bank.object) end)
    end)
    T.waitFor(self, function() return T.clientStatus(bank) ~= nil end, "this client's copy of the bank's status")
end

--- The server's entry for the first `fullType` in a bank state's items, or nil.
function T.stateItem(state, fullType)
    return T.findIn(state and state.items, "type", fullType)
end

--- The condition of the first `fullType` in a bank state, or nil.
function T.stateCondition(state, fullType)
    local item = T.stateItem(state, fullType)
    return item and item.condition
end

--- The status entry of the source at `position` (a handle, or { x, y, z }) in a bank state, or nil.
function T.stateSource(state, position)
    for _, source in ipairs(state and state.status and state.status.sources or {}) do
        if Squares.samePosition(source, position) then
            return source
        end
    end
    return nil
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

--- Checks that the panel fixture `panel` connected, saying why not.
function T.expectConnected(panel)
    return T.expect(panel.connected, "connecting the panel failed (" .. tostring(panel.reason) .. ")")
end

--- Queues switching `bank` on with its Turn On, and a wait until this client's summary says it is
--- on, whatever the bank then does.
function T.switchOn(self, bank)
    T.job(self, "bank", BankJobs.TURN_ON, bank)
    T.waitForSummary(self, bank, function(summary) return summary.on == true end,
        "this client's copy of the bank's summary, switched on")
end

-- Menus and the status window -----------------------------------------------------------------

--- The panel's Connect to `bank` (`one`) and the bank's Connect Sources in Reach with `loose`
--- sources in its reach (`all`), read from fresh menus on this client's copies, as T.optionState.
function T.connectOptions(bank, panel, loose)
    local context = T.newContext()
    local sourceMenu = SourceMenu.addSourceOptions(0, context, panel.object)
    local bankMenu = BankMenu.addBankOptions(0, context, bank.object)
    local options = {
        one = T.optionState(T.optionNamed(sourceMenu, getText("ContextMenu_RenewableEnergy_ConnectSource",
            BankMenu.bankLabel(bank.object), Format.away(panel, bank)))),
        all = T.optionState(T.optionNamed(bankMenu, getText("ContextMenu_RenewableEnergy_ConnectSourcesInReach", loose))),
    }
    context:hideAndChildren()
    return options
end

--- Queues opening the status window on `bank`, closed when the test ends, and a wait until it has
--- laid its rows out from the bank's status and the UI has drawn them; the window lands in
--- self.window. The character stands next to the bank first, where the menu's Status walks them,
--- as the window closes once they are out of reach.
function T.openWindow(self, bank)
    T.step(function()
        T.standNextTo(bank.square)
        local window = StatusWindow:openOn(0, bank.object)
        self.window = window
        T.defer(self, function() window:close() end)
        local drawn
        T.waitFor(self, function()
            drawn = drawn or (window.status ~= nil and Capture.drawn(1))
            return drawn and drawn()
        end, "the status window drawing the bank's status")
    end)
end

--- Whether the status summary `lines` (StatusRows.summary, a window's summaryLines) hold `text`.
function T.hasLine(lines, text)
    return T.findIn(lines, "text", text) ~= nil
end

--- The status row labelled `label` in `rows` (StatusRows.rows' columns), or nil.
function T.rowLabelled(rows, label)
    return T.findIn(rows, "label", label)
end

return T
