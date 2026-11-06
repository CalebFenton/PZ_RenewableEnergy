-- The authority's half of the Generator Powered Buildings tests (RenewableEnergyTestsGpb.lua): what
-- that mod and a bank in a building's pool look like on the server, and a bank's pass over the time
-- since its last, as the bank system runs one.

require "PZHarness/ServerHandlers"
require "PZHarness/ServerRecords"
local Squares = require "cf_commonlib/Squares"

local handler, need = PZHarness.serverHandler, PZHarness.need
local Records = PZHarness.Records

local function bankAt(args)
    local record, bank = Records.at({ kind = "bank", x = args.x, y = args.y, z = args.z })
    return need(record, "the bank's record on the server"), need(bank, "the bank's tile on the server")
end

local function hoursNow()
    return getGameTime():getWorldAgeHours()
end

-- The generator `generator` as that mod sees it: in a pool, its fuel and the pool's fuel an hour
-- (its Gen_Stats_FuelRateLph, every member's share at every multiplier), the world hour up to which
-- it billed the generator (its Gen_LastCalcWorldAge), and whether its own Turn On/Off would go ahead.
local function generatorRead(player, generator)
    local modData = generator:getModData()
    return { linked = modData.Gen_BuildingPoolID ~= nil, pool = modData.Gen_BuildingPoolID, fuel = generator:getFuel(), maxFuel = generator:getMaxFuel(),
        condition = generator:getCondition(), activated = generator:isActivated(), poolLph = modData.Gen_Stats_FuelRateLph,
        billedTo = modData.Gen_LastCalcWorldAge,
        switchable = PB_ActivateGenerator:new(player, generator, not generator:isActivated()):isValid() }
end

-- The bank at x, y, z and the generator at `generator` ({ x, y, z }, if given), and whether that
-- mod powers the square `at` ({ x, y, z }): the Lua-visible hasGridPower it answers for its
-- squares, and the grid's own. `sinceHours` is the time since the bank's last pass.
handler("gpbRead", function(player, args)
    local record, bank = bankAt(args)
    local square = need(PZHarness.squareAt(args.at), "the appliance's square on the server")
    local read = { bank = generatorRead(player, bank), gridPowered = record.gridPowered, gpbLitres = record.gpbLitres or 0,
        gpbW = record.gpbW or 0, sinceHours = hoursNow() - record.lastHour, hooked = square:hasGridPower(),
        grid = Squares.hasGridPower(square), consumption = SandboxVars.GeneratorFuelConsumption }
    if args.generator then
        read.generator = generatorRead(player, need(PZHarness.squareAt(args.generator):getGenerator(),
            "the fuel generator on the server"))
    end
    return read
end)

-- A pass of the bank over the hours since its last, as the bank system's runs, with the litres that
-- mod took meanwhile and what the batteries held before; then the bank's state, as
-- RenewableEnergyTest.bankPass answers.
handler("gpbPass", function(_, args)
    local record, bank = bankAt(args)
    local hours = hoursNow() - record.lastHour
    local litres = (record.gpbLitres or 0) + bank:getMaxFuel() - bank:getFuel()
    local storedBefore = record.charge * record.nominalWh
    record:catchUp()
    record:afterChange()
    local state = Records.read("bank", record, record:getIsoObject())
    state.passLitres, state.passHours, state.storedBefore, state.gpbW = litres, hours, storedBefore, record.gpbW or 0
    return state
end)
