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
    if need.label then
        return need.label
    elseif need.labelKey then
        return getText(need.labelKey)
    elseif need.perk then
        return need.perk:getName()
    elseif need.tool then
        return getItemNameFromFullType(TOOL_ITEMS[need.tool] or need.item)
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

--- Greys `option` out with `description` as its tooltip.
function Needs.disable(option, description)
    option.notAvailable = true
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = description
end

--- An option whose job takes several things (skill, tools, materials) lists them all with have and
--- need, as vanilla's item repair and build menu do, so the character sees everything they lack at
--- once; greyed out while any is short. A `blocker` (a translation key) that no amount of carrying
--- fixes replaces the list with its plain sentence, as vanilla's generator options do. A job that
--- takes nothing gets no tooltip.
function Needs.show(option, needs, blocker)
    if blocker then
        Needs.disable(option, getText(blocker))
        return
    end
    if #needs == 0 then return end
    option.notAvailable = RenewableEnergy.firstUnmet(needs) ~= nil
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = Needs.describe(needs)
end

--- The first object on the right-clicked squares for which `matches(object)` is true, or nil.
function Needs.findClicked(worldobjects, matches)
    local seen = {}
    for _, clicked in ipairs(worldobjects) do
        local square = clicked:getSquare()
        if square and not seen[square] then
            seen[square] = true
            local found = RenewableEnergy.findObjectOn(square, matches)
            if found then
                return found
            end
        end
    end
    return nil
end

return Needs
