-- The Gas Conversion Kit's options in a vanilla generator's right-click menu, the generator info
-- window's fuel and gas lines, and Take Generator refused while a kit is fitted.

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISGeneratorInfoWindow"
require "TimedActions/ISTakeGenerator"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/TimedActions/RenewableEnergyGasAction"
require "RenewableEnergy/UI/Needs"

RenewableEnergy = RenewableEnergy or {}
local GasKitMenu = {}
RenewableEnergy.GasKitMenu = GasKitMenu

local GasKit, Digester, Gasifier, Needs = RenewableEnergy.GasKit, RenewableEnergy.Digester, RenewableEnergy.Gasifier, RenewableEnergy.Needs
local queue = RenewableEnergyGasAction.queue

local function addJob(menu, playerNum, label, job, generator, source)
    local option = menu:addOption(label, playerNum, queue, "kit", job, generator, nil, source)
    Needs.show(option, GasKit.needs(getSpecificPlayer(playerNum), job, generator, source), GasKit.blocker(job, generator, source))
    return option
end

local function sourceLabel(generator, source)
    local name
    if GasKit.sourceKind(source) == "gasifier" then
        name = getText("IGUI_RenewableEnergy_Gasifier_" .. Gasifier.tierOf(source))
    else
        name = getText("IGUI_RenewableEnergy_Digester_" .. Digester.tileOf(source))
    end
    local squares = math.floor(IsoUtils.DistanceTo(generator:getX(), generator:getY(), source:getX(), source:getY()) + 0.5)
    return getText("ContextMenu_RenewableEnergy_LineTo", name, squares)
end

--- Adds the kit's options for `generator` to `menu`.
function GasKitMenu.addOptions(playerNum, menu, generator)
    local state = GasKit.stateOf(generator)
    if not state then
        addJob(menu, playerNum, getText("ContextMenu_RenewableEnergy_InstallKit"), GasKit.INSTALL, generator)
        return
    end
    if state.source then
        addJob(menu, playerNum, getText("ContextMenu_RenewableEnergy_DisconnectLine"), GasKit.DISCONNECT, generator)
    else
        local sources = GasKit.gasifiersBeside(generator)
        for _, digester in ipairs(GasKit.digestersInReach(generator)) do
            table.insert(sources, digester)
        end
        local connect = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectLine"))
        if #sources == 0 then
            Needs.disable(connect, getText("Tooltip_RenewableEnergy_NoDigesterInReach", GasKit.REACH))
        else
            local submenu = ISContextMenu:getNew(menu)
            menu:addSubMenu(connect, submenu)
            for _, source in ipairs(sources) do
                addJob(submenu, playerNum, sourceLabel(generator, source), GasKit.CONNECT, generator, source)
            end
        end
    end
    if state.mode == "petrol" then
        addJob(menu, playerNum, getText("ContextMenu_RenewableEnergy_RunOnGas"), GasKit.TO_GAS, generator)
    else
        addJob(menu, playerNum, getText("ContextMenu_RenewableEnergy_RunOnPetrol"), GasKit.TO_PETROL, generator)
    end
    addJob(menu, playerNum, getText("ContextMenu_RenewableEnergy_RemoveKit"), GasKit.REMOVE, generator)
end

-- The kit's options go in vanilla's generator submenu, where the generator's other jobs are.
local function generatorMenu(context)
    local option = context:getOptionFromName(getText("ContextMenu_Generator"))
    return option and option.subOption and context:getSubMenu(option.subOption)
end

function GasKitMenu.onFill(playerNum, context, worldobjects, test)
    local generator = Needs.findClicked(worldobjects, GasKit.isGenerator)
    if not generator then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    local menu = generatorMenu(context)
    if not menu then
        menu = ISContextMenu:getNew(context)
        context:addSubMenu(context:addOption(getText("ContextMenu_Generator")), menu)
    end
    GasKitMenu.addOptions(playerNum, menu, generator)
    if GasKit.hasKit(generator) then
        local take = menu:getOptionFromName(getText("ContextMenu_GeneratorTake"))
        if take then
            Needs.disable(take, getText("Tooltip_RenewableEnergy_RemoveKitFirst"))
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(GasKitMenu.onFill)

-- Take Generator ------------------------------------------------------------------------------------

local isValid = ISTakeGenerator.isValid
function ISTakeGenerator:isValid()
    return not GasKit.hasKit(self.generator) and isValid(self)
end

-- Info window ----------------------------------------------------------------------------------------

local getRichText = ISGeneratorInfoWindow.getRichText
function ISGeneratorInfoWindow.getRichText(object, displayStats)
    local text = getRichText(object, displayStats)
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
