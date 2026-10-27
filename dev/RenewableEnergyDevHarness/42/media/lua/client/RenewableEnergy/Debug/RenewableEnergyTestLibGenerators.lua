require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Vanilla generators in the tests, added to RenewableEnergyTest: placing, reading and setting them
-- on the authority (RenewableEnergyTestServer.lua, ...Gas.lua), their kit's gas passes and the
-- bills vanilla and the gas line run on them. The bank tests charge from them and the gas tests fit
-- kits to them.

local T = RenewableEnergyTest

--- Queues a Base.Generator plugged in on `opts.square`, else near `opts.near` but at least
--- `opts.minDistance` away, with `opts.fuel` litres, running if `opts.running`, with a failsafe
--- on its square if `opts.failsafe`. When the test ends the server removes it and this client lets
--- go of its squares (PZHarness.Fixtures.releaseGeneratorPower). Returns its handle (T.where),
--- whose object is this client's copy once it has one.
function T.generator(self, opts)
    opts = opts or {}
    local square = opts.square
        or T.square(self, { near = opts.near, minDistance = opts.minDistance or 2 }, "a free square for a generator")
    if not square then
        return nil
    end
    local handle = T.where(square)
    T.server(self, "placeGenerator", T.at(square, { fuel = opts.fuel, running = opts.running, failsafe = opts.failsafe }),
        function()
            handle.object = square:getGenerator()
            return handle.object ~= nil
        end, "this client's copy of the generator")
    T.step(function()
        -- Pushed after the server's undo, so it runs first: a multiplayer client lets its chunks
        -- go of the squares the generator powered before the server's undo switches it off and
        -- removes it, a switch-off that can miss this client's copy.
        T.defer(self, function()
            if isClient() then
                PZHarness.Fixtures.releaseGeneratorPower(handle.x, handle.y, handle.z, handle)
            end
        end)
    end)
    return handle
end

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
    T.server(self, "generatorSet", T.at(generator, { pour = fields.pour, running = fields.running, rebuild = fields.rebuild }))
    if fields.rebuild then
        T.waitForFrameAfter(self, function() return self.server.generatorSet.frame end)
    end
end

--- Queues taking `litres` from the generator's fuel, as vanilla's hourly bill and a bank charging
--- from it take it, but at once and with no pass running; the next gas pass or job bills them to a
--- line on gas.
function T.burnFuel(self, generator, litres)
    T.server(self, "burnFuel", T.at(generator, { litres = litres }))
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

return T
