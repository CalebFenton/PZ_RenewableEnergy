-- The Gas Conversion Kit's options in a vanilla generator's right-click menu, the generator info
-- window's fuel and gas lines, and Take Generator refused while a kit is fitted.

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISGeneratorInfoWindow"
require "TimedActions/ISTakeGenerator"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/TimedActions/RenewableEnergyGasAction"
local JobOptions = require "cf_commonlib/JobOptions"
local Needs = require "cf_commonlib/Needs"

RenewableEnergy = RenewableEnergy or {}
local GasKitMenu = {}
RenewableEnergy.GasKitMenu = GasKitMenu

local GasKit = RenewableEnergy.GasKit
local Action = RenewableEnergyGasAction

-- "Barrel Digester (6 squares)": a source Connect Gas Line can run to, by its name and distance.
local function sourceLabel(generator, source)
    local owner = GasKit.SOURCES[GasKit.sourceKind(source)].owner
    return getText("ContextMenu_RenewableEnergy_LineTo", getText(owner.nameKey(owner.tierOf(source))),
        round(GasKit.lineLength(generator, source)))
end

-- Adds the option for `job` (to `source`, for Connect Gas Line, named for it).
local function addJob(menu, playerNum, job, generator, source)
    local label = source and sourceLabel(generator, source) or getText(Action.labelKey(job))
    JobOptions.add(menu, playerNum, Action, "kit", job, generator, source, label)
end

--- Adds the kit's options for `generator` to `menu`.
function GasKitMenu.addOptions(playerNum, menu, generator)
    local state = GasKit.stateOf(generator)
    if not state then
        addJob(menu, playerNum, GasKit.INSTALL, generator)
        return
    end
    if state.source then
        addJob(menu, playerNum, GasKit.DISCONNECT, generator)
    else
        local sources = GasKit.sourcesNear(generator)
        local label = getText(Action.labelKey(GasKit.CONNECT))
        if #sources == 0 then
            Needs.refuse(menu:addOption(label), "Tooltip_RenewableEnergy_NoDigesterInReach", GasKit.REACH)
        else
            local submenu = Needs.addSubMenu(menu, label)
            for _, source in ipairs(sources) do
                addJob(submenu, playerNum, GasKit.CONNECT, generator, source)
            end
        end
    end
    for _, job in ipairs({ GasKit.TO_GAS, GasKit.TO_PETROL, GasKit.REMOVE }) do
        addJob(menu, playerNum, job, generator)
    end
end

-- The kit's options go in vanilla's generator submenu, where the generator's other jobs are.
local function generatorMenu(context)
    return Needs.subMenuOf(context, getText("ContextMenu_Generator"))
end

function GasKitMenu.onFill(playerNum, context, worldobjects, test)
    local generator = Needs.findClicked(worldobjects, RenewableEnergy.isGenerator)
    if not generator then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    local menu = generatorMenu(context) or Needs.addSubMenu(context, getText("ContextMenu_Generator"))
    GasKitMenu.addOptions(playerNum, menu, generator)
    if GasKit.hasKit(generator) then
        local take = menu:getOptionFromName(getText("ContextMenu_GeneratorTake"))
        if take then
            Needs.refuse(take, "Tooltip_RenewableEnergy_RemoveKitFirst")
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(GasKitMenu.onFill)

-- Take Generator is refused while a kit is fitted.

local vanillaIsValid = ISTakeGenerator.isValid
function ISTakeGenerator:isValid()
    return not GasKit.hasKit(self.generator) and vanillaIsValid(self)
end

-- Generator info window: fuel and gas lines.

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
    local line
    if state.stalled then
        line = " <RED> " .. getText("IGUI_RenewableEnergy_GasStalled")
    elseif state.outOfGas then
        line = " <RED> " .. getText("IGUI_RenewableEnergy_GasOut")
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

return GasKitMenu
