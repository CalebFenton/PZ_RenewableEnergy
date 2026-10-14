-- Tooltip text listing what a job takes the way vanilla lists what fixing an item takes
-- (ISInventoryPaneContextMenu, "Needs" over a line per need) and the mechanics window colours it
-- (ISVehicleMechanics.doMenuTooltip): "<what> <have>/<need>" in the good colour when the character
-- has enough and the bad colour when short. The needs are the lists the refusals read
-- (RenewableEnergy.firstUnmet), so the colours agree with what the job allows.

require "Vehicles/ISUI/ISVehicleMechanics"

RenewableEnergy = RenewableEnergy or {}
local Needs = {}
RenewableEnergy.Needs = Needs

-- An item to name for each tool tag, as vanilla names the wrench its jobs take.
local TOOL_ITEMS = { WRENCH = "Base.Wrench", SCREWDRIVER = "Base.Screwdriver" }

local function nameOf(need)
    if need.perk then
        return need.perk:getName()
    elseif need.tool then
        return getItemNameFromFullType(TOOL_ITEMS[need.tool])
    elseif need.item then
        return getItemNameFromFullType(need.item)
    end
    return need.input:getPossibleInputItems():get(0):getDisplayName()
end

-- One need's line; a recipe gets vanilla's recipe line, which has no count.
local function line(need)
    local colour = need.have >= need.need and ISVehicleMechanics.ghs or ISVehicleMechanics.bhs
    if need.recipe then
        return " " .. colour .. " " .. getText("Tooltip_vehicle_requireRecipe", need.recipe:getTranslationName()) .. " <LINE>"
    end
    return " " .. colour .. nameOf(need) .. " " .. need.have .. "/" .. need.need .. " <LINE>"
end

--- The tooltip text: "Needs" over a line for each of `needs`.
function Needs.describe(needs)
    local text = getText("Tooltip_craft_Needs") .. " : <LINE>"
    for _, need in ipairs(needs) do
        text = text .. line(need)
    end
    return text
end

return Needs
