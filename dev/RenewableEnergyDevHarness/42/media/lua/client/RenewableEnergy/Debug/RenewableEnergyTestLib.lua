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
RenewableEnergyTest = setmetatable({}, { __index = PZHarness.Test })
local T = RenewableEnergyTest

local PowerBank, Battery, Sprites = RenewableEnergy.PowerBank, RenewableEnergy.Battery, RenewableEnergy.Sprites

local function placeWord(opts)
    return opts.indoors and "indoor" or "outdoor"
end

-- Fixtures -------------------------------------------------------------------------------------

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

--- The shared T.vehicle, with its battery replaced by a new `opts.battery` (a full type) if given
--- and charged to `opts.charge` if given. Returns the vehicle and its battery.
function T.vehicle(self, script, opts)
    opts = opts or {}
    local vehicle = PZHarness.Test.vehicle(self, script, opts)
    local part = vehicle and vehicle:getPartById("Battery")
    if part and opts.battery then
        part:setInventoryItem(instanceItem(opts.battery))
    end
    local battery = part and part:getInventoryItem()
    if battery and opts.charge then
        battery:setCurrentUsesFloat(opts.charge)
    end
    return vehicle, battery
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
