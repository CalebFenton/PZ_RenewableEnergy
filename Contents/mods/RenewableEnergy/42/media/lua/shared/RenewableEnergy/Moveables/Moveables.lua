require "Moveables/ISMoveableDefinitions"
require "Moveables/ISMoveableSpriteProps"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Chance"

-- How the mod's placed objects move: what dismantling a bank gives back, where each may be
-- placed, and what an object's modData carries into its item when picked up.
--
-- Shared, not client: picking up, placing and scrapping complete on the server
-- (ISMoveablesAction:complete), and a dedicated server never loads client Lua.

local Specs, PowerBank = RenewableEnergy.Specs, RenewableEnergy.PowerBank
local Treadmill, SolarGardenLight = RenewableEnergy.Treadmill, RenewableEnergy.SolarGardenLight
local Sprites = RenewableEnergy.Sprites

-- What dismantling (Scrap) a placed bank gives back, by the tile's Material. Other placed objects
-- have no CanScrap: they are picked up whole (their tiles' CustomItem), and mounts are unmounted by
-- recipe, which returns the modules.

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

-- Added after vanilla's own OnGameBoot handler, which resets the definitions before filling them.
Events.OnGameBoot.Add(function()
    local defs = ISMoveableDefinitions:getInstance()
    for material, items in pairs(BANK_SCRAP) do
        defs.addScrapDefinition(material, { "Base.Screwdriver" }, {}, Perks.Electricity, 2000, "Dismantle", true, 10)
        for _, entry in ipairs(items) do
            defs.addScrapItem(material, entry[1], entry[2], entry[3], true)
        end
    end
end)

-- Whether the tile `sprite` is a refrigerator: its container is a fridge. Not its Material: vanilla
-- gives stoves, washers, dryers and plastic chairs the Fridge scrap material too, and leaves it off
-- shop coolers and trailer fridges (newtiledefinitions.tiles).
local function isFridge(sprite)
    return sprite ~= nil and sprite:getProperties():get("container") == "fridge"
end

-- The chance that `character` cuts a refrigerator's compressor out whole: vanilla's own scrap skill
-- chance (ISMoveableSpriteProps.getChanceByDef: 10% and 10% a level, certain with the movables
-- cheat) on Metalworking, the perk vanilla's Fridge scrap trains. One roll a fridge, whatever its
-- size, since a fridge has one compressor.
local function compressorChance(character)
    if ISMoveableDefinitions.cheat or character:isMovablesCheat() then
        return 1
    end
    return math.min(1, (10 + 10 * character:getPerkLevel(Perks.MetalWelding)) / 100)
end

-- A dismantled treadmill gives its motor, and a dismantled refrigerator may give its compressor,
-- which a digester uses to fill propane tanks. Vanilla scraps each tile of a multi-tile object in
-- turn (ISMoveableSpriteProps.scrapObject), so each comes only with the clicked tile.
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
    if items and self.scrappingMainTile ~= false then
        if Treadmill.isSprite(self.spriteName) then
            table.insert(items.usable, Treadmill.MOTOR)
        elseif isFridge(self.sprite) and character and RenewableEnergy.Chance.hit(compressorChance(character)) then
            table.insert(items.usable, RenewableEnergy.Digester.COMPRESSOR)
        end
    end
    return items
end

--- Why the item `fullType` may not be placed on `square`: a translation key, or nil if it may.
local function placementRefusal(fullType, square)
    if Specs.banks[fullType] then
        local allowed, reason = PowerBank.canPlaceBank(square)
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

-- A connected bank, like a connected generator, must be disconnected before it is taken
-- (ISTakeGenerator.isValid).
local vanillaCanPickUp = ISMoveableSpriteProps.canPickUpMoveableInternal
function ISMoveableSpriteProps:canPickUpMoveableInternal(character, square, object, isMulti)
    if object and PowerBank.isBank(object) and object:isConnected() then
        return false
    end
    return vanillaCanPickUp(self, character, square, object, isMulti)
end

-- Placing copies an item's modData onto the object, but picking up copies an object's back only
-- for an IsoThumpable. These keys go back with the item, so a mount keeps its modules'
-- conditions and a garden light its charge and bulb.

local CARRIED_KEYS = { PowerBank.MODULES, SolarGardenLight.CHARGE_KEY, SolarGardenLight.BULB_KEY }

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

-- Copies the keys before vanilla adds the item to the inventory and sends it to the client. Save
-- compatibility: a fixed tile (Sprites.fixedTiles) picks up as its turnable twin, so its item turns.
local vanillaInstanceItem = ISMoveableSpriteProps.instanceItem
function ISMoveableSpriteProps:instanceItem(spriteNameOverride)
    local from = pickingUp
    pickingUp = nil
    local item = vanillaInstanceItem(self, spriteNameOverride or (self.spriteName and Sprites.fixedTiles[self.spriteName]))
    if item and from and from:hasModData() then
        local fromData, to = from:getModData(), item:getModData()
        for _, key in ipairs(CARRIED_KEYS) do
            to[key] = fromData[key]
        end
    end
    return item
end

-- Save compatibility: an item may still carry a fixed tile (Sprites.fixedTiles). The cursor offers
-- it only facing S, and it goes down as the turnable twin.
local vanillaPlace = ISMoveableSpriteProps.placeMoveableInternal
function ISMoveableSpriteProps:placeMoveableInternal(character, square, item, spriteName)
    return vanillaPlace(self, character, square, item, Sprites.turnable(spriteName))
end
