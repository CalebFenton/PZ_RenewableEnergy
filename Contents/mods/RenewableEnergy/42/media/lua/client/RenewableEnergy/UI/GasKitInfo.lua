-- The generator info window's fuel and gas lines for a generator with a Gas Conversion Kit.

require "ISUI/ISGeneratorInfoWindow"
local GasKit = require "RenewableEnergy/GasLine/GasKit"

local vanillaGetRichText = ISGeneratorInfoWindow.getRichText
function ISGeneratorInfoWindow.getRichText(object, displayStats)
    local text = vanillaGetRichText(object, displayStats)
    local state = GasKit.stateOf(object)
    if not (state and displayStats) then
        return text
    end
    if state.onGas then
        local shown = getText("IGUI_Generator_FuelAmount", math.ceil(object:getFuelPercentage()))
        local tank = getText("IGUI_Generator_FuelAmount", math.ceil(state.tank / object:getMaxFuel() * 100))
        local at = string.find(text, shown, 1, true)
        if at then
            text = string.sub(text, 1, at - 1) .. tank .. string.sub(text, at + #shown)
        end
    end
    -- Rich text drops the space before a tag (ISRichTextPanel.paginate): <SPACE> keeps the red
    -- words apart from the label.
    local line
    if state.stalled then
        line = " <SPACE> <RED> " .. getText("IGUI_RenewableEnergy_GasStalled")
    elseif state.outOfGas then
        line = " <SPACE> <RED> " .. getText("IGUI_RenewableEnergy_GasOut")
    elseif state.mode == "petrol" then
        line = getText("IGUI_RenewableEnergy_GasPetrol")
    elseif state.onGas then
        line = getText("IGUI_RenewableEnergy_GasOn")
    elseif not state.source then
        line = getText("IGUI_RenewableEnergy_GasNoLine")
    else
        line = getText("IGUI_RenewableEnergy_GasNone")
    end
    return getText("IGUI_RenewableEnergy_GasKit") .. ": " .. line .. " <LINE> <RGB:1,1,1> " .. text
end
