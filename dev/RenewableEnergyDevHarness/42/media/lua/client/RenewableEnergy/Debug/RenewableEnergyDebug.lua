-- Setup helpers for the debug scenario, the tests and the dev harness. Debug mode only.

local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/ClientBankSystem"
local Sources = require "RenewableEnergy/PowerBank/Sources"
require "PZHarness/TestCraft"
require "PZHarness/QA"
local Squares = require "cf_commonlib/Squares"

local Debug = {}

-- Items that only ever sit in a vehicle part, by full type.
Debug.PART_ITEMS = { ["RenewableEnergy.TrailerFrame"] = true }

-- Inputs naming several items take the first listed here, before the harness's vanilla picks
-- (T.VANILLA_PREFERRED), so the QA layout, its toolboxes and the promo's recipe sheet come out the
-- same each run.
Debug.PREFERRED_INPUTS = {
    "Base.EmptyJar", "Base.MetalDrum", "Base.Garbagebag", "Base.NormalBrake1", "Base.Needle", "Base.Thread",
    "Base.File",
}

-- What stands in for the picked-up window Take Out Window Glass takes: every picked-up tile is the
-- one script item Base.Moveable, and only the recipe's OnTest says it must be a window.
Debug.PICKED_UP = { RenewableEnergy_TakeOutWindowGlass = "Moveables.fixtures_windows_01_0" }

local function isContainerGeneratorOrSource(object)
    return object:getContainer() ~= nil or instanceof(object, "IsoGenerator")
        or Sources.kindOf(object) ~= nil
end

-- Whether a test or the dev harness may put a bank or panel on `square`: free to walk on, with no
-- vehicle, container, generator or placed source (panel, wind charger, wired treadmill) there, and
-- indoors where a bank may stand if `indoors`, else outdoors.
function Debug.isFreeSquare(square, indoors)
    return square ~= nil and square:isFree(false) and square:getVehicleContainer() == nil
        and PowerBank.canPlaceBank(square) == indoors and (indoors or square:isOutside())
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

return Debug
