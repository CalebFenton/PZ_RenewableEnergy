-- Tooltip text listing what a job takes the way vanilla's mechanics window lists what taking
-- engine parts takes (ISVehicleMechanics.doMenuTooltip): "Needs" over a line per need, "<what>
-- <have>/<need>" in vanilla's good colour when the character has enough and its bad colour when
-- short, then anything else that stands in the way in the bad colour. The needs are the lists the
-- refusals read (RenewableEnergy.firstUnmet), so the colours agree with what the job allows.

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

--- Whether the character has enough of `need`, which picks its line's colour.
function Needs.met(need)
    return need.have >= need.need
end

--- One need's line; a recipe gets vanilla's recipe line, which has no count.
function Needs.line(need)
    local colour = Needs.met(need) and ISVehicleMechanics.ghs or ISVehicleMechanics.bhs
    if need.recipe then
        return " " .. colour .. " " .. getText("Tooltip_vehicle_requireRecipe", need.recipe:getTranslationName()) .. " <LINE>"
    end
    return " " .. colour .. nameOf(need) .. " " .. need.have .. "/" .. need.need .. " <LINE>"
end

--- A line for each of `needs`.
function Needs.lines(needs)
    local text = ""
    for _, need in ipairs(needs) do
        text = text .. Needs.line(need)
    end
    return text
end

--- Vanilla's "One of:" over a line for each of `needs`, any one of which will do.
function Needs.oneOf(needs)
    local text = " " .. getText("IGUI_CraftUI_OneOf") .. " <LINE> "
    for _, need in ipairs(needs) do
        text = text .. " <INDENT:20> " .. Needs.line(need) .. " <INDENT:0> "
    end
    return text
end

--- A line in the bad colour, for what stops the job however much the character has.
function Needs.warning(text)
    return " " .. ISVehicleMechanics.bhs .. " " .. text .. " <LINE>"
end

--- The tooltip text: "Needs" over `lines` (from Needs.lines or Needs.oneOf), then the
--- translation key `blocker`, if any, as a warning.
function Needs.describe(lines, blocker)
    local text = getText("Tooltip_craft_Needs") .. " : <LINE>" .. lines
    if blocker then
        text = text .. Needs.warning(getText(blocker))
    end
    return text
end

return Needs
