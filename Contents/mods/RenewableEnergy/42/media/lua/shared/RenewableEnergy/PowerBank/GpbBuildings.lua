-- Generator Powered Buildings (Workshop 3597471949, the global PoweredBuildings): a bank connected
-- to a building with its Generator > Connect to Building powers the whole building through it, alone
-- or pooled with fuel generators. Every touch of that mod is here, and does nothing without it; its
-- globals are read when used, since it may load after this mod or not at all.
--
-- It has no way to add a power source, but it takes a bank as the generator it is and bills each
-- member of a building's pool by lowering its fuel. So a bank keeps a full tank of fuel it never
-- burns, put back each game minute, and the litres that mod took are turned back into the watts
-- vanilla bills its appliances, which the bank's next pass adds to its load. Its strain would wear
-- and break the bank as a generator, so banks are registered to feel none, and its own Turn On/Off
-- is refused on a bank, which only the bank's own switch runs.

local Specs = require "RenewableEnergy/Specs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Squares = require "cf_commonlib/Squares"

local GpbBuildings = {}

-- The pool a generator joined (that mod's Gen_BuildingPoolID), on the generator's modData.
local POOL_KEY = "Gen_BuildingPoolID"
-- Its strain is the building's load per member times this, clamped at 0 once negative; a pool's
-- identical banks halve their modifier toward 1 for each one, so it must stay negative after that.
local NO_STRAIN = -1e9

--- Whether Generator Powered Buildings is loaded.
function GpbBuildings.present()
    return PoweredBuildings ~= nil
end

--- Whether that mod powers `square` rather than the grid: it answers the Lua-visible
--- hasGridPower for the squares it powers.
function GpbBuildings.powers(square)
    return PoweredBuildings ~= nil and square:hasGridPower() and not Squares.hasGridPower(square)
end

--- Whether the bank's `generator` belongs to a building's pool.
function GpbBuildings.linked(generator)
    return PoweredBuildings ~= nil and generator:getModData()[POOL_KEY] ~= nil
end

--- Fills the bank's `generator` up again, adding what that mod burned since to the bank's
--- `gpbLitres`. With `meter` false what went is dropped: a bank that just loaded.
function GpbBuildings.topUp(bank, generator, meter)
    local full = generator:getMaxFuel()
    local burned = full - generator:getFuel()
    if burned <= 0 then return end
    if meter then
        bank.gpbLitres = (bank.gpbLitres or 0) + burned
    end
    generator:setFuel(full)
end

--- The building's watts over the pass of `hours` that ends now, from the litres metered since the
--- last: as vanilla bills the same appliances (Specs.wattsPerFuel), since that mod burns the
--- building's vanilla bill at the GeneratorFuelConsumption option. A bank that didn't run keeps the
--- last pass's figure while still in a pool, so an overloaded bank fits again only once its share
--- does rather than the moment it stops; unloaded, there is none, since the litres that mod bills
--- for the time away come in when the chunk loads.
function GpbBuildings.takeWatts(bank, generator, hours)
    -- What it took since the last minute's top-up belongs to this pass too.
    if generator then
        GpbBuildings.topUp(bank, generator, true)
    end
    local litres = bank.gpbLitres or 0
    bank.gpbLitres = 0
    local consumption = SandboxVars.GeneratorFuelConsumption
    if not generator or consumption <= 0 or not GpbBuildings.linked(generator) then
        return 0
    end
    if litres > 0 then
        return Specs.wattsFromFuel(litres / consumption) / hours
    end
    return generator:isActivated() and 0 or (bank.gpbW or 0)
end

local function registerBanks()
    local modifiers = PoweredBuildings.Constants.GENERATOR_TYPES.MODIFIERS
    for _, name in ipairs(PowerBank.feature.sprites) do
        modifiers[name] = { fuel = 1, strain = NO_STRAIN }
    end
    local activate = PB_ActivateGenerator
    local isValid = activate.isValid
    function activate:isValid()
        return not PowerBank.isBank(self.generator) and isValid(self)
    end
end

-- Each minute, before or after that mod's own minute: either way its draw is put back before it
-- reads the fuel again, so its barrels never see a bank to refuel.
local function topUpAll()
    PowerBank.each(function(bank)
        local generator = bank:getIsoObject()
        if generator then
            GpbBuildings.topUp(bank, generator, true)
        end
    end)
end

Events.OnGameBoot.Add(function()
    if not GpbBuildings.present() then return end
    registerBanks()
    if not isClient() then
        Events.EveryOneMinute.Add(topUpAll)
    end
end)

return GpbBuildings
