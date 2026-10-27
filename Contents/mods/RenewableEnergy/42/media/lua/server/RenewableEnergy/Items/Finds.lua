-- The condition and charge of the mod's items as the world gives them: found in loot, in the banks,
-- crates and trailers the mod places, and on the panels of its sites. Whatever stocks a container
-- readies its items here, so a find is worn and charged by one set of rules wherever it turns up.

if isClient() then return end

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local Distributions = require "RenewableEnergy/Items/Distributions"
local Chance = require "cf_commonlib/Chance"

local Finds = {}
RenewableEnergy.Finds = Finds

local MODULE = Specs.factoryModule

-- Module conditions. A cracked module lies in a garage with a broken cover glass; a weathered
-- one has stood on a roof since the late 1980s. Site panels and crates hold a mix of both.
Finds.CRACKED = { min = 20, max = 50 }
Finds.WEATHERED = { min = 60, max = 100 }
Finds.SITE_CRACKED_SHARE = 0.35
-- How used found batteries are, by profile: a condition about `mean`, give or take a third of
-- `halfWidth`, never further off than `halfWidth` and no better than new; and the chance `dud` of
-- a dud (DUD). A `uniform` profile spreads it evenly over mean ± halfWidth instead. Batteries
-- where the danger is come better than the quiet countryside's (docs/design.md, risk buys
-- reward). Repairs stop at Battery.REPAIR_LIMIT, so a worn battery is worth reconditioning, a
-- used one hardly, and store stock needs none.
Finds.BATTERY_WEAR = {
    -- Years on an old wind charger.
    tired = { mean = 50, halfWidth = 15 },
    -- Sheds, garages and farm storerooms: never as good as new.
    worn = { mean = 65, halfWidth = 30, dud = 0.08 },
    -- Homesteads, storage units and utility sites: a few as good as new.
    used = { mean = 80, halfWidth = 35, dud = 0.04 },
    -- An electronics store's backstock: nearly new.
    stock = { mean = 95, halfWidth = 15 },
    -- Years on the road in an arrow board's box, run flat and left: anywhere from dead to fair.
    road = { mean = 40, halfWidth = 40, uniform = true },
}
-- A dud: nearly dead, condition from min to max, and nursed along with `repairs` repairs, which
-- leave its repair limit too low for reconditioning to pay. Stripped, it still gives a whole
-- battery's case, plates and acid for a rebuild.
Finds.DUD = { min = 5, max = 20, repairs = 5 }
-- Found inverters and charge controllers, worn as a BATTERY_WEAR profile: solid-state boxes seldom
-- wear out on a shelf, so they come near new and bunched close, with the odd dud.
Finds.PART_WEAR = { mean = 85, halfWidth = 15, dud = 0.05 }
-- A part dud: broken (0) or a scrap's repair from it (Specs.partRepair), so it needs mending first.
Finds.PART_DUD = { min = 0, max = 10 }

-- Rarity

--- The mod's loot rarity option `option` as a multiplier, for what the mod places in the world
--- itself (banks, crates, trailers, site panels): the game's loot rolls never reach those, so its
--- own loot settings don't either.
function Finds.placedRarity(option)
    return SandboxVars.RenewableEnergy[option]
end

--- The multiplier for `fullType` added to a container the game's loot just filled: the mod's
--- option `option` times the game's loot setting for the item's category, which is 0 for an item
--- on the server's loot removal list (ItemPickerJava.getLootModifier), as an entry of a loot list
--- would get.
function Finds.lootScaled(fullType, option)
    return ItemPickerJava.getLootModifier(fullType) * SandboxVars.RenewableEnergy[option]
end

--- `count` × the placed rarity of `option`, rounded up or down at random so that the average
--- scales exactly: a rarity of 0.5 halves the items on average, even where the count is 1.
function Finds.scaled(count, option)
    local expected = count * Finds.placedRarity(option)
    local whole = math.floor(expected)
    return Chance.hit(expected - whole) and whole + 1 or whole
end

-- Modules

function Finds.crackedCondition()
    return Chance.between(Finds.CRACKED.min, Finds.CRACKED.max)
end

function Finds.weatheredCondition()
    return Chance.between(Finds.WEATHERED.min, Finds.WEATHERED.max)
end

--- A site module's condition: cracked or weathered.
function Finds.siteModuleCondition()
    if Chance.hit(Finds.SITE_CRACKED_SHARE) then
        return Finds.crackedCondition()
    end
    return Finds.weatheredCondition()
end

--- `count` factory modules at site conditions, as a mount's Panel.MODULES_KEY list.
function Finds.siteModules(count)
    local modules = {}
    for i = 1, count do
        modules[i] = { type = MODULE, condition = Finds.siteModuleCondition() }
    end
    return modules
end

--- A factory module at `condition`.
function Finds.newModule(condition)
    local item = instanceItem(MODULE)
    Wear.setCondition(item, condition)
    return item
end

-- Batteries and parts

-- The percent of new the wear profile `wear` gives a found item that isn't a dud: the mean of
-- three rolls bunches it around the profile's mean like a bell curve with no tails past halfWidth;
-- a uniform profile's one roll spreads it evenly. No better than new.
local function foundPercent(wear)
    if wear.uniform then
        return math.min(100, Chance.between(wear.mean - wear.halfWidth, wear.mean + wear.halfWidth))
    end
    local spread = (Chance.roll() + Chance.roll() + Chance.roll()) / 3 * 2 - 1
    return math.min(100, wear.mean + wear.halfWidth * spread)
end

local function setPercent(item, percent)
    Wear.setCondition(item, math.floor(item:getConditionMax() * percent / 100 + 0.5))
end

-- A found item's percent of new by the wear profile `wear`: a dud's from `dud`, if its chance
-- comes up, or foundPercent. Also returns whether it is a dud.
local function foundOrDud(wear, dud)
    if wear.dud and Chance.hit(wear.dud) then
        return Chance.between(dud.min, dud.max), true
    end
    return foundPercent(wear), false
end

-- Wears a found battery as the BATTERY_WEAR profile `profile` says: a dud at DUD's condition with
-- its repairs, or at foundPercent.
local function wearBattery(item, profile)
    local percent, isDud = foundOrDud(Finds.BATTERY_WEAR[profile], Finds.DUD)
    if isDud then
        item:setHaveBeenRepaired(Finds.DUD.repairs)
    end
    setPercent(item, percent)
end

--- Whether `fullType` is a part PART_WEAR wears: a found inverter or a charge controller. A
--- homemade inverter is never loot, and its crafted condition is its own.
function Finds.isWornPart(fullType)
    local inverter = Specs.inverters[fullType]
    return (inverter ~= nil and not inverter.homemade) or fullType == Specs.controller
end

-- Wears a found inverter or controller as PART_WEAR says, a dud at PART_DUD's condition, and marks
-- it as having a condition of its own.
local function wearPart(item)
    setPercent(item, (foundOrDud(Finds.PART_WEAR, Finds.PART_DUD)))
    Wear.markOwnCondition(item)
end

--- Readies a found `item` the mod placed: a battery worn as the BATTERY_WEAR profile `profile`
--- says and given a part charge, an inverter or controller worn as PART_WEAR says, a factory
--- module at a site module's condition. Anything else is left as it is. Sends nothing: the caller
--- publishes the container or the item.
function Finds.ready(item, profile)
    local fullType = item:getFullType()
    if fullType == MODULE then
        Wear.setCondition(item, Finds.siteModuleCondition())
    elseif Battery.isBattery(item) then
        wearBattery(item, profile)
        Battery.setFoundCharge(item)
    elseif Finds.isWornPart(fullType) then
        wearPart(item)
    end
end

--- Adds a found `fullType` to the container, readied (Finds.ready). Returns it.
function Finds.add(container, fullType, profile)
    local item = container:AddItem(fullType)
    if item then
        Finds.ready(item, profile)
    end
    return item
end

-- Loot

local OWN_CONTAINER = {}
for _, containerType in ipairs(Distributions.OWN_CONTAINER_TYPES) do
    OWN_CONTAINER[containerType] = true
end

-- An inverter or controller as loot rolls it: with no condition of its own. Its condition may be
-- anything: the game rolls a uniform one for 40% of the tools it puts outside shops
-- (ItemPickerJava.doRollItemInternal, randomizeGeneralCondition), which PART_WEAR replaces.
local function isFreshPart(item)
    return Finds.isWornPart(item:getFullType()) and not Wear.hasOwnCondition(item)
end

local function readyItems(container, wearParts, sendParts)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:IsInventoryContainer() then
            readyItems(item:getInventory(), wearParts, sendParts)
        elseif item:getModule() == "RenewableEnergy" then
            if Battery.isBattery(item) and not Battery.hasCharge(item) then
                Battery.setFoundCharge(item)
                sendItemStats(item)
            elseif wearParts and isFreshPart(item) then
                wearPart(item)
                if sendParts then
                    sendItemStats(item)
                end
            end
        end
    end
end

--- Readies the mod's items in a container the game's loot filled, bags included: batteries get a
--- part charge, inverters and controllers their wear. A refill (loot respawn) fires this again
--- over what players left there, so it passes over a battery that has a charge of its own and a
--- part that has a condition of its own. The mod's own containers, banks among them, roll no
--- loot, so no part in one is worn, marked or not. Sends the batteries; a fill's parts go to the
--- clients with the filled items (RequestItemsForContainerPacket, LootRespawn), condition included.
---@param container ItemContainer
function Finds.readyFoundItems(container)
    readyItems(container, not OWN_CONTAINER[container:getType()], false)
end

-- Cracked modules
-- Modules whose glass broke lie around where people kept junk and spares. They are added when a
-- container is filled rather than through the loot lists, so that they come with their cracked
-- condition and the lists' modules stay whole. Weights scale like a loot list's (Finds.lootScaled).

-- Rooms, and the weight of each of their shelves, boxes, crates and cabinets.
Finds.CRACKED_MODULE_ROOMS = {
    garage = 1.5,
    garagestorage = 1.5,
    shed = 1.5,
    farmstorage = 3,
    electronicsstorage = 3,
}
Finds.CRACKED_MODULE_CONTAINERS = {
    crate = true, smallcrate = true, cardboardbox = true, smallbox = true, metal_shelves = true,
    shelves = true, toolcabinet = true, counter = true,
}
-- Weight for each trunk and truck bed of a vehicle in a junkyard (vanilla vehicle zone
-- "junkyard"): someone pulled the panel off an RV.
Finds.CRACKED_MODULE_JUNKYARD = 3

local function crackedModuleWeight(roomName, containerType, container)
    local vehicle = container:getVehicle()
    if vehicle then
        local part = container:getVehiclePart()
        local partId = part and part:getId() or ""
        local isCargo = string.find(partId, "Trunk") or string.find(partId, "TruckBed")
        return (vehicle:getZone() == "junkyard" and isCargo) and Finds.CRACKED_MODULE_JUNKYARD or 0
    end
    return Finds.CRACKED_MODULE_CONTAINERS[containerType] and Finds.CRACKED_MODULE_ROOMS[roomName] or 0
end

--- The chance that a container of this weight gets a cracked module, at the save's options.
function Finds.crackedModuleChance(weight)
    return weight * Finds.lootScaled(MODULE, "LRMSolarPanels") / 100
end

--- Maybe adds a cracked module to a freshly filled container, if its room or vehicle keeps them.
function Finds.addCrackedModules(roomName, containerType, container)
    local weight = crackedModuleWeight(roomName, containerType, container)
    if weight > 0 and Chance.hit(Finds.crackedModuleChance(weight)) then
        container:AddItem(Finds.newModule(Finds.crackedCondition()))
    end
end

-- Rooms, vehicles and corpses fire this after rolling their loot; vanilla's own drainable
-- randomizing (ItemPickerJava.rollItem) runs before it. ItemPickerJava's bag fills pass the bag's
-- loot table in place of a container.
local function onFillContainer(roomName, containerType, container)
    if instanceof(container, "ItemContainer") then
        Finds.addCrackedModules(roomName, containerType, container)
        Finds.readyFoundItems(container)
    end
end

-- Randomized survivor safehouses (RBSafehouse) and stash houses (StashSystem.doBuildingStash)
-- fill their containers through ItemPickerJava.fillContainerType, which fires no OnFillContainer,
-- and mark them explored, as their buildings load, before anyone sees their rooms. So the
-- explored containers of a room seen for the first time are readied then, parts sent as well,
-- since the clients may hold those items already. A container still unexplored is readied when
-- its loot is rolled.
local function onSeeNewRoom(room)
    local squares = room:getSquares()
    for i = 0, squares:size() - 1 do
        local objects = squares:get(i):getObjects()
        for j = 0, objects:size() - 1 do
            local object = objects:get(j)
            for k = 0, object:getContainerCount() - 1 do
                local container = object:getContainerByIndex(k)
                if container:isExplored() then
                    readyItems(container, not OWN_CONTAINER[container:getType()], true)
                end
            end
        end
    end
end

Events.OnFillContainer.Add(onFillContainer)
-- Fires on the server and in single player (IsoCell.ProcessSpottedRooms), once per room.
Events.OnSeeNewRoom.Add(onSeeNewRoom)

return Finds
