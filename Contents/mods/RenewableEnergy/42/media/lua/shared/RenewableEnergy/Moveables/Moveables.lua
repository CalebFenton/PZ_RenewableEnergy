-- How the mod's placed objects move: what dismantling a bank gives back, where each may be
-- placed, what may not be picked up yet, and what an object carries into its item when picked up.
--
-- Shared, not client: picking up, placing and scrapping complete on the server
-- (ISMoveablesAction:complete), and a dedicated server never loads client Lua.

require "Moveables/ISMoveableDefinitions"
require "Moveables/ISMoveableSpriteProps"
local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local Recipes = require "RenewableEnergy/Recipes"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local Digester = require "RenewableEnergy/Biogas/Digester"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local Wind = require "RenewableEnergy/Wind"
local BuiltScrap = require "RenewableEnergy/Moveables/BuiltScrap"
local Chance = require "cf_commonlib/Chance"

-- What dismantling (Scrap) a placed bank gives back, by the tile's Material. Digesters, gasifiers
-- and wind chargers give back what built them (BuiltScrap). Other placed objects have no CanScrap:
-- they are picked up whole (their tiles' CustomItem), and mounts are unmounted by recipe, which
-- returns the modules.

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

-- The container type of the tile `sprite`, or nil. A refrigerator is a tile whose container is a
-- fridge, not its Material: vanilla gives stoves, washers, dryers and plastic chairs the Fridge
-- scrap material too, and leaves it off shop coolers and trailer fridges (newtiledefinitions.tiles).
local function containerOf(sprite)
    return sprite and sprite:getProperties():get("container")
end

-- The chance that `character` takes a part out whole of a tile `props` with the scrap material
-- `material`: vanilla's own scrap skill chance for it (ISMoveableSpriteProps.getChanceByDef, the
-- movables cheat included). A refrigerator's compressor goes by the Fridge material's perk,
-- Metalworking, one roll a fridge, whatever its size, since a fridge has one compressor. A
-- microwave's transformer goes by the Electric material microwave tiles carry, so it rises with
-- Electricity as the oven's electronics do.
local function scrapChance(props, material, character)
    local def = ISMoveableDefinitions:getInstance().getScrapDefinition(material)
    return def and props:getChanceByDef(def, character) / 100 or 0
end

-- What a microwave oven may give: the transformer a homemade inverter is wound on.
local TRANSFORMER = "RenewableEnergy.MicrowaveTransformer"

-- A dismantled treadmill gives its motor, a dismantled refrigerator may give its compressor,
-- which a digester uses to fill propane tanks, and a dismantled microwave its transformer. Vanilla
-- scraps each tile of a multi-tile object in turn (ISMoveableSpriteProps.scrapObject), so each
-- comes only with the clicked tile. What is built in place gives what built it instead of its
-- Material's scrap: its plan is read before vanilla takes the object and its record away, and its
-- fittings, which keep their condition, land beside the rest.
local vanillaScrapInternal = ISMoveableSpriteProps.scrapObjectInternal
function ISMoveableSpriteProps:scrapObjectInternal(character, scrapDef, square, object, ...)
    self.scrappingMainTile = object == self.object
    self.builtScrap = BuiltScrap.planOf(object)
    local added = vanillaScrapInternal(self, character, scrapDef, square, object, ...)
    for _, fitting in ipairs(self.builtFittings or {}) do
        square:AddWorldInventoryItem(fitting, ZombRandFloat(0.1, 0.9), ZombRandFloat(0.1, 0.9), 0)
    end
    self.scrappingMainTile, self.builtScrap, self.builtFittings = nil, nil, nil
    return added
end

local vanillaScrapItems = ISMoveableSpriteProps.getScrapItemsList
function ISMoveableSpriteProps:getScrapItemsList(character)
    if self.builtScrap and character then
        local types, fittings = BuiltScrap.itemsOf(self.builtScrap, character)
        self.builtFittings = fittings
        return { usable = types, unusable = {} }
    end
    local items = vanillaScrapItems(self, character)
    if items and self.scrappingMainTile ~= false then
        if Treadmill.isSprite(self.spriteName) then
            table.insert(items.usable, Treadmill.MOTOR)
        elseif containerOf(self.sprite) == "fridge" and character and Chance.hit(scrapChance(self, "Fridge", character)) then
            table.insert(items.usable, Digester.COMPRESSOR)
        elseif containerOf(self.sprite) == "microwave" and character and Chance.hit(scrapChance(self, "Electric", character)) then
            table.insert(items.usable, TRANSFORMER)
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

-- Whether `isoObject` is a gasifier still burning, which, like a running generator
-- (ISTakeGenerator.isValid), must be put out before it is taken.
local function isLitGasifier(isoObject)
    if not Gasifier.isGasifier(isoObject) then
        return false
    end
    local summary = Gasifier.summaryOf(isoObject)
    return summary ~= nil and summary.lit == true
end

-- Whether `isoObject` is connected, which, like a connected generator (ISTakeGenerator.isValid),
-- must be disconnected before it is taken or turned: a bank connected itself, or a source
-- connected to a bank. Either tile of a treadmill counts as its wired half.
local function isConnected(isoObject)
    if PowerBank.isBank(isoObject) then
        return isoObject:isConnected()
    end
    local source = Treadmill.isTreadmill(isoObject) and Treadmill.wiredHalf(isoObject) or isoObject
    return source ~= nil and Sources.kindOf(source) ~= nil and PowerBank.connectedBank(source) ~= nil
end

-- Why `isoObject` may not be picked up or turned now: a translation key, or nil if it may.
local function takeRefusal(isoObject)
    if isLitGasifier(isoObject) then
        return "Tooltip_RenewableEnergy_PutOutFirst"
    elseif isConnected(isoObject) then
        return "Tooltip_RenewableEnergy_DisconnectFirst"
    end
    return nil
end

local vanillaCanPlace = ISMoveableSpriteProps.canPlaceMoveableInternal
function ISMoveableSpriteProps:canPlaceMoveableInternal(character, square, item, forceTypeObject)
    return vanillaCanPlace(self, character, square, item, forceTypeObject)
        and not (item and placementRefusal(item:getFullType(), square))
end

-- The cursor's panel says why it refuses, in the red vanilla gives its own refusals: placing an
-- item where it may not go, or picking up or turning a gasifier still burning or anything
-- connected.
local vanillaInfoPanel = ISMoveableSpriteProps.getInfoPanelDescription
function ISMoveableSpriteProps:getInfoPanelDescription(square, object, player, mode)
    local infoTable = vanillaInfoPanel(self, square, object, player, mode)
    local refusal = mode == "place" and self.customItem and placementRefusal(self.customItem, square)
        or (mode == "pickup" or mode == "rotate") and object and takeRefusal(object)
    if refusal then
        local bad = ISMoveableSpriteProps.bhc
        ISMoveableSpriteProps.addLineToInfoTable(infoTable, "- " .. getText(refusal),
            bad:getR() * 255, bad:getG() * 255, bad:getB() * 255)
    end
    return infoTable
end

-- Vanilla asks this on the authority too, before it picks up (pickUpMoveable), so a connected
-- object stays put even if a client's cursor let it through. A multi-tile object is asked tile by
-- tile.
local vanillaCanPickUp = ISMoveableSpriteProps.canPickUpMoveableInternal
function ISMoveableSpriteProps:canPickUpMoveableInternal(character, square, object, isMulti)
    if object and takeRefusal(object) then
        return false
    end
    return vanillaCanPickUp(self, character, square, object, isMulti)
end

-- Turning an object picks it up and places it again (rotateMoveable), which would disconnect it
-- unseen. Vanilla asks canRotateMoveable only at the cursor, so the authority refuses in
-- rotateMoveable too.
local vanillaCanRotate = ISMoveableSpriteProps.canRotateMoveable
function ISMoveableSpriteProps:canRotateMoveable(square, object, origProps)
    if object and takeRefusal(object) then
        return false
    end
    return vanillaCanRotate(self, square, object, origProps)
end

local vanillaRotate = ISMoveableSpriteProps.rotateMoveable
function ISMoveableSpriteProps:rotateMoveable(character, square, origSpriteName)
    local object = ISMoveableSpriteProps.new(origSpriteName):findOnSquare(square, origSpriteName)
    if object and takeRefusal(object) then
        return
    end
    return vanillaRotate(self, character, square, origSpriteName)
end

-- Placing copies an item's modData onto the object, but picking up copies an object's back only
-- for an IsoThumpable. These keys go back with the item, so a mount keeps its modules'
-- conditions, a garden light its charge and bulb, and a wind charger its broken blades, its brake
-- and that its first connection already taught its XP.

local CARRIED_KEYS = { Panel.MODULES_KEY, SolarGardenLight.CHARGE_KEY, SolarGardenLight.BULB_KEY, Wind.BROKEN_KEY,
    Wind.BRAKED_KEY, Panel.CONNECTED_ONCE_KEY }

-- The record of `isoObject` if it is a digester or gasifier, on the authority; nil elsewhere.
local function recordOf(isoObject)
    if Digester.isDigester(isoObject) then
        return Digester.recordOf(isoObject)
    elseif Gasifier.isGasifier(isoObject) then
        return Gasifier.recordOf(isoObject)
    end
    return nil
end

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

-- Copies the keys, and a digester's or gasifier's record (cf_commonlib's Object:carryOn), before
-- vanilla adds the item to the inventory and sends it to the client; placing the item gives them
-- to the tile it puts down. A mount's item shows the modules it now holds. Save compatibility: a
-- fixed tile (Sprites.fixedTiles) picks up as its turnable twin, so its item turns.
local vanillaInstanceItem = ISMoveableSpriteProps.instanceItem
function ISMoveableSpriteProps:instanceItem(spriteNameOverride)
    local from = pickingUp
    pickingUp = nil
    local item = vanillaInstanceItem(self, spriteNameOverride or (self.spriteName and Sprites.fixedTiles[self.spriteName]))
    if not (item and from) then
        return item
    end
    if from:hasModData() then
        local fromData, to = from:getModData(), item:getModData()
        for _, key in ipairs(CARRIED_KEYS) do
            to[key] = fromData[key]
        end
    end
    if Recipes.MOUNTS[item:getFullType()] then
        Recipes.showMountModules(item)
    end
    local record = recordOf(from)
    if record then
        record:carryOn(item)
    end
    return item
end

-- Save compatibility: an item may still carry a fixed tile (Sprites.fixedTiles). The cursor offers
-- it only facing S, and it goes down as the turnable twin.
local vanillaPlace = ISMoveableSpriteProps.placeMoveableInternal
function ISMoveableSpriteProps:placeMoveableInternal(character, square, item, spriteName)
    return vanillaPlace(self, character, square, item, Sprites.turnable(spriteName))
end
