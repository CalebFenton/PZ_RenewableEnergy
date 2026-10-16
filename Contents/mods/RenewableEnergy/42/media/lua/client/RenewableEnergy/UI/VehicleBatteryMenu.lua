-- Offers the deep cycle battery under Install in the vehicle mechanics window's menu for an empty
-- battery slot, the way vanilla offers the car batteries the slot's script lists, which the deep
-- cycle battery isn't among (see RenewableEnergy.VehicleBattery). Picking one runs vanilla's own
-- install (ISVehiclePartMenu.onInstallPart), with the slot's tools, time and hood.

require "Vehicles/ISUI/ISVehicleMechanics"
require "RenewableEnergy/Gadgets/VehicleBattery"

local VehicleBattery = RenewableEnergy.VehicleBattery

-- Adds the deep cycle battery to the Install submenu that `mechanics:doPartContextMenu` built
-- for `part` in `mechanics.context`. Vanilla builds no submenu when the slot is full or can't
-- be worked on now, and then there is nothing to add to.
local function addInstallOptions(mechanics, part)
    if not (VehicleBattery.isBatteryPart(part) and not part:getInventoryItem() and mechanics.context) then
        return
    end
    local install = mechanics.context:getOptionFromName(getText("IGUI_Install"))
    local subMenu = install and install.subOption and mechanics.context:getSubMenu(install.subOption)
    if not subMenu then
        return
    end
    local character = mechanics.chr
    local fullType = VehicleBattery.ITEM
    local script = getItem(fullType)
    local option = subMenu:addOption(getItemName(fullType), character, nil)
    option.iconTexture = script and script:getNormalTexture()
    mechanics:doMenuTooltip(part, option, "install", fullType)
    local items = VehicleUtils.getItems(character:getPlayerNum())[fullType]
    if not items then
        option.notAvailable = true
        return
    end
    local itemMenu = ISContextMenu:getNew(subMenu)
    mechanics.context:addSubMenu(option, itemMenu)
    for _, item in ipairs(items) do
        local itemOption = itemMenu:addOption(item:getDisplayName() .. " (" .. item:getCondition() .. "%)", character,
            ISVehiclePartMenu.onInstallPart, part, item)
        itemOption.itemForTexture = item
        mechanics:doMenuTooltip(part, itemOption, "install", fullType)
    end
end

local vanillaDoPartContextMenu = ISVehicleMechanics.doPartContextMenu

function ISVehicleMechanics:doPartContextMenu(part, x, y)
    vanillaDoPartContextMenu(self, part, x, y)
    -- Vanilla returns before building a menu while the game is paused or the character sits in
    -- the vehicle; self.context is then the last menu, closed.
    if self.context and self.context:getIsVisible() then
        addInstallOptions(self, part)
    end
end
