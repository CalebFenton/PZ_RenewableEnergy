require "PZHarness/TestLib"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Battery"

-- Helpers for the RenewableEnergyTests*.lua files: the shared harness's test library
-- (dev/harness/mod/42/media/lua/client/PZHarness/TestLib.lua explains the runner and the rules
-- every helper keeps), plus the fixtures that know this mod's objects, which push their undos the
-- same way. RenewableEnergyDevHarness.lua gives the library this mod's settings.
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

local function positionOf(square)
    return { x = square:getX(), y = square:getY(), z = square:getZ() }
end

-- Fixtures -------------------------------------------------------------------------------------

-- This client's copy of the bank on `square` once it holds `count` items and has a status.
local function bankCopy(square, count)
    local bank = PowerBank.bankOn(square)
    local container = bank and bank:getContainer()
    if container and container:getItems():size() >= count and PowerBank.statusOf(bank) then
        return bank
    end
    return nil
end

--- Queues a working bank of Sprites field `kind` holding `items` (full types), filled straight
--- into its container as world spawns do, its batteries charged to `opts.charge` (full by default).
--- It stands on `opts.square`, else on a free square near `opts.near` (a handle, object or square):
--- indoors unless `opts.outdoors`. Returns its handle { square, position }; `object` is this
--- client's copy of the bank (its IsoGenerator) once it has arrived with its parts and status.
function T.bank(self, kind, items, opts)
    opts = opts or {}
    local square = opts.square or (T.squares(self, 1, { indoors = not opts.outdoors, near = squareOf(opts.near) }) or {})[1]
    if not T.need(self, square, "a free " .. (opts.outdoors and "outdoor" or "indoor") .. " square for a bank") then
        return nil
    end
    local bank = { square = square, position = positionOf(square) }
    local count = #(items or {})
    T.server(self, "placeBank", { x = square:getX(), y = square:getY(), z = square:getZ(), kind = kind, items = items,
        charge = opts.charge })
    T.waitUntil(function() return bankCopy(square, count) ~= nil end, COPY_FRAMES)
    T.step(function()
        bank.object = T.need(self, bankCopy(square, count), "this client's copy of the bank, with its parts and status")
    end)
    return bank
end

-- Whether this client has its copy of the panel and, if it was connected, sees the bank's status
-- list it.
local function panelArrived(panel, bank)
    local here = panel.position
    return PowerBank.sourceOn(panel.square) ~= nil
        and (not panel.connected or PowerBank.samePosition(PowerBank.bankOfSource(here.x, here.y, here.z), bank.position))
end

--- Queues a panel tile of `sprite` on a free outdoor square near `opts.near` (a handle, object or
--- square), holding `opts.modules` ({ { type, condition } }) if given, placed as the moveables
--- cursor places one and, when `opts.connect`, connected by the server's character to the bank
--- handle `opts.near`. Returns its handle { square, position }; the server's answer fills in
--- `connected` and `reason` (the refusal), and `object` is this client's copy once it has arrived,
--- connection included.
function T.panel(self, sprite, opts)
    opts = opts or {}
    local square = (T.squares(self, 1, { near = squareOf(opts.near) }) or {})[1]
    if not T.need(self, square, "a free outdoor square for a panel") then
        return nil
    end
    local panel = { square = square, position = positionOf(square) }
    local bank = opts.connect and opts.near
    T.server(self, "placePanel", { x = square:getX(), y = square:getY(), z = square:getZ(), sprite = sprite,
        modules = opts.modules, bank = bank and bank.position })
    T.step(function()
        panel.connected, panel.reason = self.server.placePanel.connected, self.server.placePanel.reason
    end)
    T.waitUntil(function() return panelArrived(panel, bank) end, COPY_FRAMES)
    T.step(function()
        panel.object = T.need(self, panelArrived(panel, bank) and PowerBank.sourceOn(square), "this client's copy of the panel")
    end)
    return panel
end

--- The server handlers' name for the vehicle of a T.placeVehicle handle: its id and the square
--- it went on. Call it once the server has answered, as in a T.server args function.
function T.vehicleArgs(vehicle)
    return { id = vehicle.id, x = vehicle.x, y = vehicle.y, z = vehicle.z }
end

--- The battery in this client's copy of the vehicle of a T.placeVehicle handle, or nil.
function T.vehicleBattery(vehicle)
    local part = vehicle.vehicle and vehicle.vehicle:getPartById("Battery")
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
        T.waitForCopy(function()
            local item = T.vehicleBattery(vehicle)
            return item ~= nil and (not opts.battery or item:getFullType() == opts.battery)
                and (not opts.charge or math.abs(item:getCurrentUsesFloat() - opts.charge) < 0.001)
        end)
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

--- Queues a pass of `opts.hours` (1 by default) of `bank` on the server, with the weather fixed:
--- `light` W/m² on every mount, clear, 25 °C, no snow, and `opts.stormHours` of storm.
function T.bankPass(self, bank, light, opts)
    opts = opts or {}
    onBank(self, bank, "bankPass", { light = light, hours = opts.hours, stormHours = opts.stormHours })
end

--- Queues replacing the measured load of `bank` with appliances of the Specs.loads kinds
--- `names`, as if the scan had found them switched on, and letting the bank react: cut or restore
--- its power and send its status. The next pass measures the real load again.
function T.applyLoad(self, bank, names)
    onBank(self, bank, "applyLoad", { names = names })
end

--- Queues setting fields of the server's record of `bank` (`charge`, `on`), and writing its
--- charge into its batteries if `writeBatteries`.
function T.bankSet(self, bank, fields, writeBatteries)
    onBank(self, bank, "bankSet", { fields = fields, writeBatteries = writeBatteries })
end

--- Queues setting the condition of the first `fullType` in `bank` on the server, and letting the
--- bank read its parts again if `recount`.
function T.setPartCondition(self, bank, fullType, condition, recount)
    onBank(self, bank, "setPartCondition", { type = fullType, condition = condition, recount = recount })
end

--- The status of `bank` (a handle) as this client last received it, or nil.
function T.clientStatus(bank)
    return bank.object and PowerBank.statusOf(bank.object)
end

--- Queues switching `bank` on the way a client does, with the bank system's command, and a wait
--- until this client's copy of its status says it is on, whatever the bank then does.
function T.switchOn(self, bank)
    T.step(function()
        PowerBank.command(T.player(), "setBankOn", { bank = bank.position, on = true })
    end)
    T.waitUntil(function()
        local status = T.clientStatus(bank)
        return status ~= nil and status.on == true
    end, COPY_FRAMES)
end

--- Queues a wait, as long as a fixture's, until `condition()` holds on this client.
function T.waitForCopy(condition)
    T.waitUntil(condition, COPY_FRAMES)
end

--- The overlays `object` shows, as their sprite names joined by commas, in order; a server's
--- answer lists them the same way (`overlays` in a bank state), joined with table.concat.
function T.overlays(object)
    local names = {}
    local attached = object and object:getAttachedAnimSprite()
    for i = 0, (attached and attached:size() or 0) - 1 do
        table.insert(names, attached:get(i):getName())
    end
    return table.concat(names, ",")
end

-- Data -----------------------------------------------------------------------------------------

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

return T
