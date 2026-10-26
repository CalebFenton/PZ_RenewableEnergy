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

-- Items that only ever sit in a vehicle part, by full type.
Debug.PART_ITEMS = { ["RenewableEnergy.TrailerFrame"] = true }

--- Every item of this mod's scripts by full type, sorted so the layouts come out the same each run.
function Debug.items()
    local found, items = {}, getScriptManager():getAllItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getModuleName() == "RenewableEnergy" then
            table.insert(found, item:getFullName())
        end
    end
    table.sort(found)
    return found
end

-- Inputs naming several items take the first listed here, else the harness's pick (T.inputItem),
-- which for a tag can differ from run to run; so every tag input the recipes have is listed, and
-- the QA layout, its toolboxes and the promo's recipe sheet come out the same each run.
Debug.PREFERRED_INPUTS = {
    "Base.EmptyJar", "Base.MetalDrum", "Base.Bucket", "Base.WaterBottle", "Base.Charcoal", "Base.HandDrill",
    "Base.Screwdriver", "Base.Wrench", "Base.Hammer", "Base.SmithingHammer", "Base.Saw", "Base.KitchenKnife",
    "Base.Pliers", "Base.Tongs", "Base.WeldingMask", "Base.Shovel2", "Base.MasonsTrowel", "Base.Matches",
    "Base.Garbagebag", "Base.BucketConcreteFull", "Base.NormalBrake1", "Base.Needle", "Base.Thread", "Base.File",
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
