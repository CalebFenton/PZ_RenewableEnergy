-- The Gas Conversion Kit's options in a vanilla generator's right-click menu, the generator info
-- window's fuel and gas lines, and Take Generator refused while a kit is fitted.

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISGeneratorInfoWindow"
require "TimedActions/ISTakeGenerator"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/TimedActions/RenewableEnergyGasAction"
require "RenewableEnergy/UI/Needs"

RenewableEnergy = RenewableEnergy or {}
local GasKitMenu = {}
RenewableEnergy.GasKitMenu = GasKitMenu

local GasKit, Digester, Needs = RenewableEnergy.GasKit, RenewableEnergy.Digester, RenewableEnergy.Needs
local Action = RenewableEnergyGasAction

local function queue(playerNum, job, generator, digester)
    local character = getSpecificPlayer(playerNum)
    if luautils.walkAdj(character, generator:getSquare(), true) then
        ISTimedActionQueue.add(Action:new(character, job, generator, digester))
    end
end

local function disable(option, description)
    option.notAvailable = true
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = description
end

local function addJob(menu, playerNum, label, job, generator, digester)
    local character = getSpecificPlayer(playerNum)
    local option = menu:addOption(label, playerNum, queue, job, generator, digester)
    local blocker = GasKit.blocker(job, generator, digester)
    if blocker then
        disable(option, getText(blocker))
        return option
    end
    local needs = GasKit.needs(character, job, generator, digester)
    if #needs > 0 then
        option.notAvailable = RenewableEnergy.firstUnmet(needs) ~= nil
        option.toolTip = ISWorldObjectContextMenu.addToolTip()
        option.toolTip.description = Needs.describe(needs)
    end
    return option
end

local function digesterLabel(generator, digester)
    local summary = Digester.summaryOf(digester)
    local name = getText("IGUI_RenewableEnergy_Digester_" .. (summary and summary.tier or "barrel"))
    local squares = math.floor(IsoUtils.DistanceTo(generator:getX(), generator:getY(), digester:getX(), digester:getY()) + 0.5)
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
        local digesters = GasKit.digestersInReach(generator)
        local connect = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectLine"))
        if #digesters == 0 then
            disable(connect, getText("Tooltip_RenewableEnergy_NoDigesterInReach", GasKit.REACH))
        else
            local submenu = ISContextMenu:getNew(menu)
            menu:addSubMenu(connect, submenu)
            for _, digester in ipairs(digesters) do
                addJob(submenu, playerNum, digesterLabel(generator, digester), GasKit.CONNECT, generator, digester)
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

local function findGenerator(worldobjects)
    local seen = {}
    for _, clicked in ipairs(worldobjects) do
        local square = clicked:getSquare()
        if square and not seen[square] then
            seen[square] = true
            local found = RenewableEnergy.findObjectOn(square, GasKit.isGenerator)
            if found then
                return found
            end
        end
    end
    return nil
end

-- The kit's options go in vanilla's generator submenu, where the generator's other jobs are.
local function generatorMenu(context)
    local option = context:getOptionFromName(getText("ContextMenu_Generator"))
    return option and option.subOption and context:getSubMenu(option.subOption)
end

function GasKitMenu.onFill(playerNum, context, worldobjects, test)
    local generator = findGenerator(worldobjects)
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
            disable(take, getText("Tooltip_RenewableEnergy_RemoveKitFirst"))
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
