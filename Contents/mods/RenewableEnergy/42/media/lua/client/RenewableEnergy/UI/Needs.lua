-- The idioms every right-click menu of the mod shares: finding the clicked object, a submenu, and an
-- option greyed out saying why.
--
-- A greyed option is explained as vanilla does: one blocker as a plain sentence (Needs.refuse), or
-- several needs as "<what> <have>/<need>" lines coloured good or bad, as the fixing menu and the
-- mechanics window show them (Needs.show). Both take the shared refusal functions' answers, so the
-- menu greys an option exactly when the job's action and the authority refuse it.

require "ISUI/ISWorldObjectContextMenu"
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

local function setTooltip(option, description)
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = description
end

--- Greys `option` out with the sentence of the translation key `key` (`...` its arguments). Does
--- nothing when `key` is nil or false, so a refusal function's answer passes straight in.
function Needs.refuse(option, key, ...)
    if not key then return end
    option.notAvailable = true
    setTooltip(option, getText(key, ...))
end

--- "Too dark" as a translation key when the job needs light to see by (`needsLight`) and
--- `character` stands in the dark, else nil. Only the player's own side can tell
--- (IsoPlayer.tooDarkToRead is false for a remote player), so the menu checks it, not a refusal.
function Needs.tooDark(character, needsLight)
    if needsLight and character:tooDarkToRead() then
        return "Tooltip_RenewableEnergy_TooDark"
    end
    return nil
end

--- An option whose job takes several things (skill, tools, materials) lists them all with have and
--- need, so the character sees everything they lack at once, and is greyed out while any is short.
--- A `blocker` (a translation key) that no amount of carrying fixes replaces the list with its
--- sentence. A job that takes nothing gets no tooltip.
function Needs.show(option, needs, blocker)
    if blocker then
        Needs.refuse(option, blocker)
        return
    end
    if #needs == 0 then return end
    option.notAvailable = RenewableEnergy.firstUnmet(needs) ~= nil
    local text = getText("Tooltip_craft_Needs") .. " : <LINE>"
    for _, need in ipairs(needs) do
        text = text .. line(need)
    end
    setTooltip(option, text)
end

--- Adds an option named `name` to `context` that opens a new submenu. Returns the submenu and the
--- option.
function Needs.addSubMenu(context, name)
    local submenu = ISContextMenu:getNew(context)
    local option = context:addOption(name)
    context:addSubMenu(option, submenu)
    return submenu, option
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
