-- Setup helpers for the debug scenario, the tests and the dev harness, and a count of the frames
-- each status window drew. Debug mode only.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/ClientBankSystem"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/UI/StatusWindow"
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

--- The names of the mod's build menu recipes (scripts/RenewableEnergy/Entities.txt), which
--- getAllCraftRecipes, and so PZHarness.Test.learnRecipes, leaves out.
function Debug.buildRecipes()
    local names, recipes = {}, getScriptManager():getAllBuildableRecipes()
    local prefix = PZHarness.testSettings.recipePrefix
    for i = 0, recipes:size() - 1 do
        local name = recipes:get(i):getName()
        if PZHarness.startsWith(name, prefix) then
            table.insert(names, name)
        end
    end
    return names
end

--- Teaches `player` every recipe of the mod, the build menu's included.
function Debug.learnRecipes(player)
    PZHarness.Test.learnRecipes(player)
    PZHarness.Fixtures.learnRecipes(player, Debug.buildRecipes())
end

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
        and not RenewableEnergy.findObjectOn(square, isContainerGeneratorOrSource)
end

-- Lets this multiplayer client's chunks go of the squares a test generator at x, y, z powered,
-- before the server's undo switches it off and removes it. That switch-off can miss this client's
-- copy: it names the generator by its place on the square and isn't ordered with the removal that
-- follows (SyncIsoObject against RemoveItemFromSquare), and the chunks then keep its squares
-- powered until they load again.
function Debug.releaseGeneratorPower(x, y, z)
    if isClient() then
        RenewableEnergy.PowerBank.releaseGeneratorPower(x, y, z)
    end
end

-- A character with the electrical and building skills the mod gates on, every recipe, a
-- screwdriver and a table to craft at.
function Debug.setupPlayer(player)
    player:setPerkLevelDebug(Perks.Electricity, 8)
    player:setPerkLevelDebug(Perks.MetalWelding, 4)
    player:setPerkLevelDebug(Perks.Woodwork, 3)
    Debug.learnRecipes(player)
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
