-- Setup helpers for the debug scenario, the tests and the dev harness, and a count of the frames
-- each status window drew. Debug mode only.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/ClientBankSystem"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/UI/StatusWindow"
require "PZHarness/TestLib"
require "PZHarness/QA"
local Squares = require "cf_commonlib/Squares"

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
    "RenewableEnergy.MakeshiftInverter", "RenewableEnergy.HomemadeInverter", "RenewableEnergy.MicrowaveTransformer",
    "RenewableEnergy.ChargeController", "RenewableEnergy.SolarFailsafe",
    "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery", "RenewableEnergy.JarBattery",
    "RenewableEnergy.CarBatteryCase", "RenewableEnergy.DeepCycleBatteryCase", "RenewableEnergy.L16BatteryCase",
    "RenewableEnergy.WornBatteryPlates", "RenewableEnergy.BatteryPlates", "RenewableEnergy.WoodenBatteryPlatePattern",
    "RenewableEnergy.BatteryPlateMoldUnfired", "RenewableEnergy.BatteryPlateMold", "RenewableEnergy.BatteryElectrolyte",
    "RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger", "RenewableEnergy.SolarGardenLight",
    "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2", "RenewableEnergy.HomesteadPowerMag3",
    "RenewableEnergy.CrowcallRoadMap", "RenewableEnergy.DixieTrailerParkMap",
    "RenewableEnergy.WoodAsh", "RenewableEnergy.GasConversionKit", "RenewableEnergy.FridgeCompressor",
    "RenewableEnergy.GasHeater", "RenewableEnergy.TarryPacking", "RenewableEnergy.FemaPamphlet",
    "RenewableEnergy.TreadmillMotor", "RenewableEnergy.WoodenBlades", "RenewableEnergy.PipeBlades",
    "RenewableEnergy.SteelBlades", "RenewableEnergy.BrokenWoodenBlades", "RenewableEnergy.BrokenPipeBlades",
    "RenewableEnergy.BrokenSteelBlades", "RenewableEnergy.HomemadeAlternator", "RenewableEnergy.HomesteadPowerMag4",
    "RenewableEnergy.CarAlternator",
}
-- Items that only ever sit in a vehicle part.
Debug.PART_ITEMS = { "RenewableEnergy.TrailerFrame" }
-- Inputs naming several items take the first listed here, else the harness's pick (T.inputItem),
-- which for a tag can differ from run to run; so every tag input the recipes have is listed, and
-- the QA layout, its toolboxes and the promo's recipe sheet come out the same each run.
Debug.PREFERRED_INPUTS = {
    "Base.EmptyJar", "Base.MetalDrum", "Base.Bucket", "Base.WaterBottle", "Base.Charcoal", "Base.HandDrill",
    "Base.Screwdriver", "Base.Wrench", "Base.Hammer", "Base.SmithingHammer", "Base.Saw", "Base.KitchenKnife",
    "Base.Pliers", "Base.Tongs", "Base.WeldingMask", "Base.Shovel2", "Base.MasonsTrowel", "Base.Matches",
    "Base.Garbagebag", "Base.BucketConcreteFull", "Base.NormalBrake1",
}

local function isContainerGeneratorOrSource(object)
    return object:getContainer() ~= nil or instanceof(object, "IsoGenerator")
        or RenewableEnergy.Sources.kindOf(object) ~= nil
end

-- Whether a test or the dev harness may put a bank or panel on `square`: free to walk on, with no
-- vehicle, container, generator or placed source (panel, wind charger, wired treadmill) there, and
-- indoors where a bank may stand if `indoors`, else outdoors.
function Debug.isFreeSquare(square, indoors)
    return square ~= nil and square:isFree(false) and square:getVehicleContainer() == nil
        and RenewableEnergy.PowerBank.canPlaceBank(square) == indoors and (indoors or square:isOutside())
        and not Squares.findObjectOn(square, isContainerGeneratorOrSource)
end

-- A character with the electrical and building skills the mod gates on, every recipe, a
-- screwdriver and a table to craft at.
function Debug.setupPlayer(player)
    player:setPerkLevelDebug(Perks.Electricity, 8)
    player:setPerkLevelDebug(Perks.MetalWelding, 4)
    player:setPerkLevelDebug(Perks.Woodwork, 3)
    PZHarness.QA.learnAllRecipes(player)
    player:getInventory():AddItem("Base.Screwdriver")
    PZHarness.Test.placeWorkTable(player)
end

-- The tests and the promo shots wait on `renderedFrames`, the frames a status window drew a bank's
-- status in, so that they read and shoot a window that has its status and has drawn it.
local StatusWindow = RenewableEnergy.StatusWindow
local render = StatusWindow.render
function StatusWindow:render()
    render(self)
    if not self.isCollapsed and self.status then
        self.renderedFrames = (self.renderedFrames or 0) + 1
    end
end

return Debug
