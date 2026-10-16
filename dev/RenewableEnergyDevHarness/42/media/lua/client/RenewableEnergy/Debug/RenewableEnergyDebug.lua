-- Setup helpers for the debug scenario, the tests and the dev harness, and a count of the frames
-- each status window drew. Debug mode only.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/PowerBank/PowerBank"
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
    "RenewableEnergy.ChargeController", "RenewableEnergy.SolarFailsafe",
    "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery",
    "RenewableEnergy.CarBatteryCase", "RenewableEnergy.DeepCycleBatteryCase", "RenewableEnergy.L16BatteryCase",
    "RenewableEnergy.WornBatteryPlates", "RenewableEnergy.BatteryPlates", "RenewableEnergy.WoodenBatteryPlatePattern",
    "RenewableEnergy.BatteryPlateMoldUnfired", "RenewableEnergy.BatteryPlateMold", "RenewableEnergy.BatteryElectrolyte",
    "RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger", "RenewableEnergy.SolarGardenLight",
    "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2", "RenewableEnergy.HomesteadPowerMag3",
    "RenewableEnergy.CrowcallRoadMap", "RenewableEnergy.DixieTrailerParkMap",
    "RenewableEnergy.WoodAsh", "RenewableEnergy.GasConversionKit", "RenewableEnergy.FridgeCompressor",
    "RenewableEnergy.GasHeater", "RenewableEnergy.TarryPacking", "RenewableEnergy.FemaPamphlet",
    "RenewableEnergy.TreadmillMotor",
}
-- Items that only ever sit in a vehicle part.
Debug.PART_ITEMS = { "RenewableEnergy.TrailerFrame" }
-- The build menu's recipes, which getAllCraftRecipes (and so PZHarness.Test.learnRecipes) leaves out:
-- they belong to entity scripts (scripts/RenewableEnergy/Entities.txt).
Debug.DIGESTER_RECIPES = {
    "RenewableEnergy_BarrelDigesterSteel", "RenewableEnergy_BarrelDigesterPlastic",
    "RenewableEnergy_InsulatedDigester", "RenewableEnergy_BrickDome",
}
Debug.GASIFIER_RECIPES = {
    "RenewableEnergy_PrimitiveGasifier", "RenewableEnergy_Gasifier", "RenewableEnergy_AdvancedGasifier",
}
Debug.WIND_RECIPES = { "RenewableEnergy_ScoopRotor" }
Debug.ENTITY_RECIPES = {}
for _, list in ipairs({ Debug.DIGESTER_RECIPES, Debug.GASIFIER_RECIPES, Debug.WIND_RECIPES }) do
    for _, name in ipairs(list) do
        table.insert(Debug.ENTITY_RECIPES, name)
    end
end

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

-- Squares a generator powers are listed in the chunks around it (IsoChunk.addGeneratorPos), 8
-- squares a side.
local CHUNK_SQUARES = 8

-- Lets this multiplayer client's chunks go of the squares a test generator at x, y, z powered,
-- before the server's undo switches it off and removes it. That switch-off can miss this client's
-- copy: it names the generator by its place on the square and isn't ordered with the removal that
-- follows (SyncIsoObject against RemoveItemFromSquare), and the chunks then keep its squares
-- powered until they load again.
function Debug.releaseGeneratorPower(x, y, z)
    if not isClient() then return end
    local radius, cell = SandboxVars.GeneratorTileRange, getCell()
    for wx = math.floor((x - radius) / CHUNK_SQUARES), math.floor((x + radius) / CHUNK_SQUARES) do
        for wy = math.floor((y - radius) / CHUNK_SQUARES), math.floor((y + radius) / CHUNK_SQUARES) do
            local chunk = cell:getChunk(wx, wy)
            if chunk then
                chunk:removeGeneratorPos(x, y, z)
            end
        end
    end
end

-- An electrician and carpenter who knows every recipe, with a screwdriver and a table to craft at.
function Debug.setupPlayer(player)
    player:setPerkLevelDebug(Perks.Electricity, 8)
    player:setPerkLevelDebug(Perks.MetalWelding, 4)
    player:setPerkLevelDebug(Perks.Woodwork, 3)
    PZHarness.Test.learnRecipes(player)
    PZHarness.Fixtures.learnRecipes(player, Debug.ENTITY_RECIPES)
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
