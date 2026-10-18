-- The arrow board's battery box lid is a trunk lid to vanilla (scripts/RenewableEnergy/Vehicles.txt
-- says why), so vanilla's UI would call it a trunk and open no container for it. These hooks of
-- vanilla's UI give it the box's words and container on the trailer only, tell a player who tries
-- the padlocked box how to get in, and offer Cut Padlock and the lamps' switch.

require "ISUI/ISButtonPrompt"
require "ISUI/ISWorldObjectContextMenu"
require "ISUI/LootWindow/Handlers/VehicleCloseTrunk"
require "Vehicles/ISUI/ISVehicleMenu"
require "Vehicles/ISUI/ISVehicleMechanics"
require "Vehicles/TimedActions/ISPathFindAction"
require "Vehicles/TimedActions/ISOpenVehicleDoor"
require "Vehicles/TimedActions/ISUnlockVehicleDoor"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"

RenewableEnergy = RenewableEnergy or {}
local BatteryBoxLid = {}
RenewableEnergy.BatteryBoxLid = BatteryBoxLid

local Action = RenewableEnergyAction

-- The lid's own text for each of vanilla's trunk texts it would show.
local TEXTS = {
    IGUI_VehiclePartTrunkDoor = "IGUI_RenewableEnergy_BatteryBoxLid",
    IGUI_OpenTrunk = "IGUI_RenewableEnergy_OpenBatteryBox",
    IGUI_CloseTrunk = "IGUI_RenewableEnergy_CloseBatteryBox",
}

-- Whether `part` is an arrow board's battery box lid. ArrowBoard is server Lua, which loads after
-- this file, so it is looked up only when a hook runs.
local function isLid(part)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    return part ~= nil and part:getId() == ArrowBoard.LID and ArrowBoard.isTrailer(part:getVehicle())
end

-- The lid's words where vanilla shows `key`'s.
local function lidText(key)
    return getText(TEXTS[key])
end

-- An item with the bolt cutters tag, to name where a player has none.
BatteryBoxLid.CUTTERS = "Base.BoltCutters"

--- The bolt cutters `character` would cut the lid's padlock with, those in hand first, or nil when
--- there is no padlock to cut or no working pair to cut it with.
function BatteryBoxLid.padlockCutters(character, lid)
    if not (isLid(lid) and RenewableEnergy.ArrowBoard.isPadlocked(lid)) then
        return nil
    end
    local held = character:getPrimaryHandItem()
    if Action.isBoltCutters(held) then
        return held
    end
    return character:getInventory():getFirstEvalRecurse(Action.isBoltCutters)
end

--- Walks to the box, takes the cutters in hand and cuts the padlock off, as vanilla's part jobs
--- walk to the part's area and equip their tools (ISVehiclePartMenu).
function BatteryBoxLid.cutPadlock(character, lid, cutters)
    local vehicle = lid:getVehicle()
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, vehicle, lid:getArea()))
    local twoHands = instanceof(cutters, "HandWeapon") and cutters:isTwoHandWeapon()
    ISWorldObjectContextMenu.equip(character, character:getPrimaryHandItem(), cutters, true, twoHands)
    ISTimedActionQueue.add(Action:new(character, Action.CUT_PADLOCK, nil, nil, vehicle, cutters))
end

--- Walks to the box and flips the lamps' switch inside it to `on`.
function BatteryBoxLid.flipSwitch(character, vehicle, on)
    local box = vehicle:getPartById(RenewableEnergy.ArrowBoard.BATTERY_BOX)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, vehicle, box:getArea()))
    ISTimedActionQueue.add(Action:new(character, on and Action.BOARD_ON or Action.BOARD_OFF, nil, nil, vehicle))
end

-- Adds the switch's slice for a character standing at an arrow board's battery box: Switch Lamps
-- On or Off, with vanilla's headlight icons, where the switch can be reached, else one that says
-- why not and does nothing, as vanilla's radial does for what it can't do (ISVehicleMenu).
local function addSwitchSlice(menu, character)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local vehicle = ISVehicleMenu.getVehicleToInteractWith(character)
    local box = ArrowBoard.isTrailer(vehicle) and vehicle:getPartById(ArrowBoard.BATTERY_BOX)
    if not (box and vehicle:isInArea(box:getArea(), character)) then
        return
    end
    local on = ArrowBoard.isSwitchedOn(vehicle)
    local texture = getTexture(on and "media/ui/vehicles/vehicle_lightsOFF.png" or "media/ui/vehicles/vehicle_lightsON.png")
    if ArrowBoard.switchReachable(vehicle) then
        menu:addSlice(getText(on and "IGUI_RenewableEnergy_LampsOff" or "IGUI_RenewableEnergy_LampsOn"), texture,
            BatteryBoxLid.flipSwitch, character, vehicle, not on)
    else
        menu:addSlice(getText("IGUI_RenewableEnergy_LampsSwitchShut"), texture, nil)
    end
end

local vanillaShowRadialMenuOutside = ISVehicleMenu.showRadialMenuOutside

-- Renames the lid's Open and Close, adds the lamps' switch, and adds Cut Padlock at a padlock that
-- holds (greyed, saying what it takes, without bolt cutters). The menu joins the UI only on the next
-- update (UIManager.AddUI), so whether vanilla built it shows only in its prior state: shown, which
-- the call hides, or the character in a vehicle, which builds nothing.
function ISVehicleMenu.showRadialMenuOutside(playerObj)
    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    local wasShown = menu:isReallyVisible()
    vanillaShowRadialMenuOutside(playerObj)
    if wasShown or playerObj:getVehicle() or menu:isEmpty() then
        return
    end
    local lid
    for i, slice in ipairs(menu.slices) do
        local command, part = slice.command[1], slice.command[3]
        if (command == ISVehicleMenu.onOpenDoor or command == ISVehicleMenu.onCloseDoor) and isLid(part) then
            lid = part
            menu:setSliceText(i, lidText(command == ISVehicleMenu.onOpenDoor and "IGUI_OpenTrunk" or "IGUI_CloseTrunk"))
        end
    end
    addSwitchSlice(menu, playerObj)
    if not (lid and RenewableEnergy.ArrowBoard.isPadlocked(lid)) then
        return
    end
    local cutters = BatteryBoxLid.padlockCutters(playerObj, lid)
    if cutters then
        menu:addSlice(getText("IGUI_RenewableEnergy_CutPadlock"), cutters:getTex(), BatteryBoxLid.cutPadlock, playerObj, lid, cutters)
    else
        local script = getScriptManager():FindItem(BatteryBoxLid.CUTTERS)
        menu:addSlice(getText("IGUI_RenewableEnergy_CutPadlockNeeds", script:getDisplayName()), script:getNormalTexture(), nil)
    end
end

local vanillaTestInteractButtonAction = ISButtonPrompt.testInteractButtonAction

function ISButtonPrompt:testInteractButtonAction(dir)
    vanillaTestInteractButtonAction(self, dir)
    local opens = self.aFunc == ISButtonPrompt.cmdOpenVehicleDoor
    local part = self.aParams and self.aParams[2]
    if (opens or self.aFunc == ISButtonPrompt.cmdCloseVehicleDoor) and isLid(part) then
        self.aPrompt = lidText(opens and "IGUI_OpenTrunk" or "IGUI_CloseTrunk")
    end
end

-- The loot window's Close Trunk button, shown while the box is open beside the character.
local CloseTrunk = ISLootWindowObjectControlHandler_VehicleCloseTrunk
local vanillaCloseTrunkControl = CloseTrunk.getControl
local vanillaCloseTrunkJoypadMenu = CloseTrunk.handleJoypadContextMenu

local function handlerLid(handler)
    return instanceof(handler.object, "BaseVehicle") and handler.object:getUseablePart(handler.playerObj) or nil
end

function CloseTrunk:getControl()
    local control = vanillaCloseTrunkControl(self)
    local lid = handlerLid(self)
    if isLid(lid) then
        control = self:getButtonControl(lidText("IGUI_CloseTrunk"))
    end
    return control
end

function CloseTrunk:handleJoypadContextMenu(context)
    vanillaCloseTrunkJoypadMenu(self, context)
    local lid = handlerLid(self)
    local option = isLid(lid) and context:getOptionFromName(getText("IGUI_CloseTrunk"))
    if option then
        option.name = lidText("IGUI_CloseTrunk")
        context:setWidth(context:calcWidth())
    end
end

-- Only the part list names the lid: the window's overlay, whose tooltip would too, draws only
-- vehicles ISCarMechanicsOverlay lists, and no other part of the trailer names the lid among the
-- parts it needs on or off.

local vanillaInitParts = ISVehicleMechanics.initParts

function ISVehicleMechanics:initParts()
    vanillaInitParts(self)
    for _, list in ipairs({ self.listbox, self.bodyworklist }) do
        for _, row in ipairs(list.items) do
            local part = row.item.part
            if isLid(part) then
                row.item.name = lidText("IGUI_VehiclePart" .. part:getId())
                row.text = row.item.name
            end
        end
    end
end

local vanillaUnlockStop = ISUnlockVehicleDoor.stop

-- Opening a locked trunk tries its lock first (ISVehicleMenu.onOpenDoor, Vehicles.Use.TrunkDoor),
-- and the refused unlock stops, in single player at once and on a multiplayer client when the
-- server rejects it, which empties the queue before the open. Vanilla says why only for a broken
-- lock; the box says how to get in, the way vanilla tells a player what they can't do
-- (HaloTextHelper.addBadText, as ISVehiclePartMenu does for a fuel inlet out of reach).
function ISUnlockVehicleDoor:stop()
    vanillaUnlockStop(self)
    if isLid(self.part) and RenewableEnergy.ArrowBoard.isPadlocked(self.part) then
        HaloTextHelper.addBadText(self.character, getText("IGUI_RenewableEnergy_BoxLocked"))
    end
end

local vanillaSelectContainer = ISOpenVehicleDoor.selectContainerInLootWindow

-- Opening a trunk shows its container in the loot window, which vanilla finds by the id TruckBed;
-- on the trailer that is the frame's back end, which holds nothing. So for the lid vanilla runs
-- on a stand-in for the trailer that hands it the battery box for TruckBed, keeping all its own
-- conditions. Vanilla calls this from complete(), and returns at once on a server, so a
-- multiplayer client's loot window never jumps, to a trunk or to the box.
function ISOpenVehicleDoor:selectContainerInLootWindow()
    if not isLid(self.part) then
        return vanillaSelectContainer(self)
    end
    local vehicle, box = self.vehicle, RenewableEnergy.ArrowBoard.BATTERY_BOX
    local trailer = setmetatable({
        getPartById = function(_, id)
            return vehicle:getPartById(id == "TruckBed" and box or id)
        end,
    }, {
        __index = function(_, method)
            return function(_, ...) return vehicle[method](vehicle, ...) end
        end,
    })
    return vanillaSelectContainer(setmetatable({ vehicle = trailer }, { __index = self }))
end

return BatteryBoxLid
