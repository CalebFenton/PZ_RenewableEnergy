-- Setup helpers for the debug scenario, the tests and the dev harness. Debug mode only.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/PowerBank/PowerBank"
require "PZHarness/TestLib"

RenewableEnergy = RenewableEnergy or {}
local Debug = {}
RenewableEnergy.Debug = Debug

-- Every item this mod defines that a player can hold, in the order the README shows them.
Debug.ITEMS = {
    "RenewableEnergy.SolarModule", "RenewableEnergy.HomemadeSolarModule", "RenewableEnergy.SolarCells",
    "RenewableEnergy.SolarFlat", "RenewableEnergy.SolarWallWood", "RenewableEnergy.SolarWallMetal",
    "RenewableEnergy.SolarRackWood", "RenewableEnergy.SolarRackMetal",
    "RenewableEnergy.BatteryBoxWood", "RenewableEnergy.BatteryBoxMetal",
    "RenewableEnergy.BatteryRackWood", "RenewableEnergy.BatteryRackMetal",
    "RenewableEnergy.BatteryBankWood", "RenewableEnergy.BatteryBankMetal",
    "RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter", "RenewableEnergy.InverterCharger",
    "RenewableEnergy.ChargeController", "RenewableEnergy.SolarFailsafe",
    "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery",
    "RenewableEnergy.CarBatteryCase", "RenewableEnergy.DeepCycleBatteryCase", "RenewableEnergy.L16BatteryCase",
    "RenewableEnergy.WornBatteryPlates", "RenewableEnergy.BatteryPlates", "RenewableEnergy.WoodenBatteryPlatePattern",
    "RenewableEnergy.BatteryPlateMoldUnfired", "RenewableEnergy.BatteryPlateMold", "RenewableEnergy.BatteryElectrolyte",
    "RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger", "RenewableEnergy.SolarGardenLight",
    "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2",
    "RenewableEnergy.CrowcallRoadMap", "RenewableEnergy.DixieTrailerParkMap",
}
-- Items that only ever sit in a vehicle part.
Debug.PART_ITEMS = { "RenewableEnergy.TrailerFrame" }

local function isContainerGeneratorOrPanel(object)
    return object:getContainer() ~= nil or instanceof(object, "IsoGenerator")
        or RenewableEnergy.PowerBank.sourceKind(object) ~= nil
end

-- Whether a test or the dev harness may put a bank or panel on `square`: free to walk on, with no
-- vehicle, container, generator or panel there, and indoors where a bank may stand if `indoors`,
-- else outdoors.
function Debug.isFreeSquare(square, indoors)
    return square ~= nil and square:isFree(false) and square:getVehicleContainer() == nil
        and RenewableEnergy.PowerBank.canPlaceBank(square) == indoors and (indoors or square:isOutside())
        and not RenewableEnergy.findObjectOn(square, isContainerGeneratorOrPanel)
end

-- An electrician and carpenter who knows every recipe, with a screwdriver and a table to craft at.
function Debug.setupPlayer(player)
    player:setPerkLevelDebug(Perks.Electricity, 8)
    player:setPerkLevelDebug(Perks.MetalWelding, 4)
    player:setPerkLevelDebug(Perks.Woodwork, 3)
    PZHarness.Test.learnRecipes(player)
    player:getInventory():AddItem("Base.Screwdriver")
    PZHarness.Test.placeWorkTable(player)
end

return Debug
