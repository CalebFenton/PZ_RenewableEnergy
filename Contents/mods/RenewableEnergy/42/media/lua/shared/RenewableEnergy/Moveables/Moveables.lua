require "Moveables/ISMoveableDefinitions"
require "Moveables/ISMoveableSpriteProps"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Biogas/Digester"

-- How the mod's placed objects move: what dismantling a bank gives back, where each may be
-- placed, and what an object's modData carries into its item when picked up.
--
-- Shared, not client: picking up, placing and scrapping complete on the server
-- (ISMoveablesAction:complete), and a dedicated server never loads client Lua.

local SolarGardenLight = RenewableEnergy.SolarGardenLight

-- Scrapping ---------------------------------------------------------------------------------------
-- What dismantling (Scrap) a placed bank gives back, by the tile's Material. Panels, mounts,
-- the failsafe, the cell charger and the garden light have no CanScrap: they are picked up whole
-- (their tiles' CustomItem), and mounts are unmounted by recipe, which returns the modules.

local BANK_SCRAP = {
    RenewableEnergyBatteryBoxWood = {
        { "Base.Plank", 2, 70 }, { "Base.Nails", 4, 60 }, { "Base.ElectricWire", 1, 80 },
    },
    RenewableEnergyBatteryBoxMetal = {
        { "Base.SmallSheetMetal", 1, 70 }, { "Base.ElectricWire", 1, 80 },
    },
    RenewableEnergyBatteryRackWood = {
        { "Base.Plank", 3, 70 }, { "Base.Nails", 6, 60 }, { "Base.ElectricWire", 2, 80 }, { "Base.Screws", 2, 60 },
    },
    RenewableEnergyBatteryRackMetal = {
        { "Base.SmallSheetMetal", 2, 70 }, { "Base.MetalBar", 1, 70 }, { "Base.ElectricWire", 2, 80 },
        { "Base.Screws", 2, 60 },
    },
    RenewableEnergyBatteryBankWood = {
        { "Base.Plank", 5, 70 }, { "Base.Nails", 10, 60 }, { "Base.ElectricWire", 3, 80 }, { "Base.Screws", 4, 60 },
    },
    RenewableEnergyBatteryBankMetal = {
        { "Base.SheetMetal", 1, 70 }, { "Base.MetalBar", 2, 70 }, { "Base.ElectricWire", 3, 80 },
        { "Base.Screws", 4, 60 },
    },
}

-- After vanilla's own OnGameBoot handler, which resets the definitions before filling them. A fridge
-- cut up with a blowtorch also gives its compressor (vanilla's "Fridge" material), which a digester
-- uses to fill propane tanks.
Events.OnGameBoot.Add(function()
    local defs = ISMoveableDefinitions:getInstance()
    for material, items in pairs(BANK_SCRAP) do
        defs.addScrapDefinition(material, { "Base.Screwdriver" }, {}, Perks.Electricity, 2000, "Dismantle", true, 10)
        for _, entry in ipairs(items) do
            defs.addScrapItem(material, entry[1], entry[2], entry[3], true)
        end
    end
    defs.addScrapItem("Fridge", RenewableEnergy.Digester.COMPRESSOR, 1, 80, true)
end)

-- A treadmill (vanilla's "Hamster Wheel" moveable, two tiles in four facings) gives its motor when
-- dismantled: the wind charger's generator. Vanilla scraps each tile of a multi-tile object in
-- turn (ISMoveableSpriteProps.scrapObject), so the motor comes with the tile that was clicked.
RenewableEnergy.TREADMILL_MOTOR = "RenewableEnergy.TreadmillMotor"
local TREADMILL_SPRITES = {}
for _, index in ipairs({ 28, 29, 30, 31, 36, 37, 38, 39 }) do
    TREADMILL_SPRITES["recreational_sports_01_" .. index] = true
end

local vanillaScrapInternal = ISMoveableSpriteProps.scrapObjectInternal
function ISMoveableSpriteProps:scrapObjectInternal(character, scrapDef, square, object, ...)
    self.scrappingMainTile = object == self.object
    local added = vanillaScrapInternal(self, character, scrapDef, square, object, ...)
    self.scrappingMainTile = nil
    return added
end

local vanillaScrapItems = ISMoveableSpriteProps.getScrapItemsList
function ISMoveableSpriteProps:getScrapItemsList(character)
    local items = vanillaScrapItems(self, character)
    if items and TREADMILL_SPRITES[self.spriteName] and self.scrappingMainTile ~= false then
        table.insert(items.usable, RenewableEnergy.TREADMILL_MOTOR)
    end
    return items
end

-- Placing -----------------------------------------------------------------------------------------

--- Why the item `fullType` may not be placed on `square`: a translation key, or nil if it may.
local function placementRefusal(fullType, square)
    if RenewableEnergy.Specs.banks[fullType] then
        local allowed, reason = RenewableEnergy.PowerBank.canPlaceBank(square)
        return not allowed and reason or nil
    elseif fullType == SolarGardenLight.ITEM and not SolarGardenLight.canPlaceOn(square) then
        return "Tooltip_RenewableEnergy_GardenLightOutdoors"
    end
    return nil
end

local vanillaCanPlace = ISMoveableSpriteProps.canPlaceMoveableInternal
function ISMoveableSpriteProps:canPlaceMoveableInternal(character, square, item, forceTypeObject)
    return vanillaCanPlace(self, character, square, item, forceTypeObject)
        and not (item and placementRefusal(item:getFullType(), square))
end

-- The placing cursor's panel says why, in the red vanilla gives its own refusals.
local vanillaInfoPanel = ISMoveableSpriteProps.getInfoPanelDescription
function ISMoveableSpriteProps:getInfoPanelDescription(square, object, player, mode)
    local infoTable = vanillaInfoPanel(self, square, object, player, mode)
    local refusal = mode == "place" and self.customItem and placementRefusal(self.customItem, square)
    if refusal then
        local bad = ISMoveableSpriteProps.bhc
        ISMoveableSpriteProps.addLineToInfoTable(infoTable, "- " .. getText(refusal),
            bad:getR() * 255, bad:getG() * 255, bad:getB() * 255)
    end
    return infoTable
end

-- Picking up --------------------------------------------------------------------------------------
-- Placing copies an item's modData onto the object, but picking up copies an object's back only
-- for an IsoThumpable. These keys go back with the item, so a mount keeps its modules'
-- conditions and a garden light its charge and bulb.

local CARRIED_KEYS = { RenewableEnergy.PowerBank.MODULES, SolarGardenLight.CHARGE_KEY, SolarGardenLight.BULB_KEY }

-- The object being picked up, until vanilla makes its item. Each pick-up makes one item, which
-- takes it, so an error in vanilla's pick-up can't leave it for an unrelated item later.
local pickingUp

local vanillaPickUp = ISMoveableSpriteProps.pickUpMoveableInternal
function ISMoveableSpriteProps:pickUpMoveableInternal(character, square, object, sprInstance, spriteName, createItem, rotating)
    pickingUp = object
    local item = vanillaPickUp(self, character, square, object, sprInstance, spriteName, createItem, rotating)
    pickingUp = nil
    return item
end

-- Copies the keys before vanilla adds the item to the inventory and sends it to the client.
local vanillaInstanceItem = ISMoveableSpriteProps.instanceItem
function ISMoveableSpriteProps:instanceItem(spriteNameOverride)
    local from = pickingUp
    pickingUp = nil
    local item = vanillaInstanceItem(self, spriteNameOverride)
    if item and from and from:hasModData() then
        local fromData, to = from:getModData(), item:getModData()
        for _, key in ipairs(CARRIED_KEYS) do
            to[key] = fromData[key]
        end
    end
    return item
end
