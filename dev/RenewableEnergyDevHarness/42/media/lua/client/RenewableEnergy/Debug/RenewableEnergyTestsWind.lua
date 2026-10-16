require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Wind chargers: a source of the bank like a panel, on the game's wind.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local Specs, Sprites, Wind = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Wind

local CAR_BATTERY = "Base.CarBattery1"
local INVERTER = "RenewableEnergy.PlugInInverter"

local function sourceOf(state, kind)
    for _, source in ipairs(state and state.status and state.status.sources or {}) do
        if source.kind == kind then
            return source
        end
    end
    return nil
end

-- A scoop rotor wired to a bank makes power in the wind by its power curve and shelter, none in a
-- calm or with its brake on, and the status says why.
test("renewable_energy_wind_scoop_feeds_bank", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not bank then return end
        self.bank = bank
        local rotor = T.panel(self, Sprites.windScoop, { near = bank, connect = true })
        if not rotor then return end
        self.rotor = rotor
        local function pass(label, kph)
            T.bankPass(self, bank, 0, { windKph = kph })
            T.step(function() self[label] = bank.state end)
        end
        pass("windy", 30)
        pass("calm", Specs.wind.turbines.scoop.cutInKph - 1)
        T.server(self, "perform", function()
            return { command = "setBrake", args = { source = rotor.position, braked = true } }
        end)
        pass("braked", 30)
    end,
    validate = function(self)
        expect(self.rotor.connected, "the bank refused the scoop rotor: " .. tostring(self.rotor.reason))
        local windy = sourceOf(self.windy, "scoop")
        if not expect(windy ~= nil, "the bank's status lists no scoop rotor") then return end
        local expected = Wind.watts(Specs.wind.turbines.scoop, 30, windy.z, windy.shelterPct / 100)
        T.expectNear("scoop rotor watts in a 30 km/h wind", windy.watts, expected, 2)
        expect(windy.watts > 0, "the scoop rotor made nothing in a 30 km/h wind")
        T.expectNear("the bank's wind watts", self.windy.status.windW, windy.watts, 0.01)
        local calm = sourceOf(self.calm, "scoop")
        expect(calm.watts == 0 and calm.reason == "calm", "in a calm it made " .. calm.watts .. " W, reason " .. tostring(calm.reason))
        local braked = sourceOf(self.braked, "scoop")
        expect(braked.watts == 0 and braked.reason == "braked", "braked it made " .. braked.watts .. " W, reason " .. tostring(braked.reason))
    end,
})

-- A wind charger takes its input slots like a panel: a battery box's two free slots take one panel
-- and one scoop rotor, and refuse a third source.
test("renewable_energy_wind_takes_input_slots", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not bank then return end
        self.panel = T.panel(self, Sprites.flat, { near = bank, connect = true })
        self.rotor = T.panel(self, Sprites.windScoop, { near = bank, connect = true })
        self.third = T.panel(self, Sprites.flat, { near = bank, connect = true })
        T.bankState(self, bank)
        T.step(function() self.state = bank.state end)
    end,
    validate = function(self)
        expect(self.panel.connected and self.rotor.connected, "a battery box refused a panel or the scoop rotor")
        expect(not self.third.connected and self.third.reason == "Tooltip_RenewableEnergy_NoInputSlot",
            "a battery box took a third source: " .. tostring(self.third.reason))
        local slots = self.state.status.inputSlots
        expect(slots.used == 2 and slots.total == Specs.freeSlots, "input slots read " .. slots.used .. " of " .. slots.total)
    end,
})

-- Shelter takes up to its share off, each level up adds its bonus, and no wind gets more than the
-- rating out of a charger.
test("renewable_energy_wind_power_curve", {
    validate = function()
        local spec = Specs.wind.turbines.scoop
        local open = Wind.watts(spec, 30, 0, 0)
        local hemmed = Wind.watts(spec, 30, 0, 1)
        local high = Wind.watts(spec, 30, 2, 0)
        T.expectNear("hemmed-in share", hemmed / open, 1 - Specs.wind.shelterLoss, 0.001)
        T.expectNear("two levels up", high / open, 1 + 2 * Specs.wind.heightBonusPerLevel, 0.001)
        expect(Wind.watts(spec, spec.ratedKph * 2, 0, 0) == spec.ratedW, "above its rated speed it makes more than its rating")
    end,
})

-- This client draws a wind charger as its turning model, once the charger is added to the map
-- (OnObjectAdded, which the placePanel handler fires as placing does).
test("renewable_energy_wind_charger_drawn_as_model", {
    run = function(self)
        self.rotor = T.panel(self, Sprites.windScoop)
    end,
    validate = function(self)
        local object = self.rotor and self.rotor.object
        expect(object ~= nil and object:getSpriteModel() ~= nil, "the wind charger has no sprite model on this client")
    end,
})

-- Dismantling a treadmill gives its motor, the wind charger's generator, once for the clicked tile.
test("renewable_energy_wind_treadmill_gives_motor", {
    validate = function()
        local props = ISMoveableSpriteProps.new("recreational_sports_01_28")
        local function motors()
            local count = 0
            for _, fullType in ipairs((props:getScrapItemsList(T.player()) or {}).usable or {}) do
                if fullType == RenewableEnergy.TREADMILL_MOTOR then
                    count = count + 1
                end
            end
            return count
        end
        expect(motors() == 1, "a treadmill's tile scraps to " .. motors() .. " motors")
    end,
})
