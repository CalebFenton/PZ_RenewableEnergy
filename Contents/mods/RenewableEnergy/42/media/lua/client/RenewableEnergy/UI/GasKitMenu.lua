-- The Gas Conversion Kit's options in a vanilla generator's right-click menu, the generator info
-- window's fuel and gas lines, and Take Generator refused while a kit is fitted.

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISGeneratorInfoWindow"
require "TimedActions/ISTakeGenerator"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/UI/Needs"
require "RenewableEnergy/UI/GasJobMenu"

RenewableEnergy = RenewableEnergy or {}
local GasKitMenu = {}
RenewableEnergy.GasKitMenu = GasKitMenu

local GasKit, Needs, GasJobMenu = RenewableEnergy.GasKit, RenewableEnergy.Needs, RenewableEnergy.GasJobMenu

local function sourceLabel(generator, source)
    local spec = GasKit.SOURCES[GasKit.sourceKind(source)]
    local squares = math.floor(IsoUtils.DistanceTo(generator:getX(), generator:getY(), source:getX(), source:getY()) + 0.5)
    return getText("ContextMenu_RenewableEnergy_LineTo", getText(spec.nameKey .. spec.tierOf(source)), squares)
end

-- Adds the option for `job` (to `source`, for Connect Gas Line, named for it) (GasJobMenu.add).
local function addJob(menu, playerNum, job, generator, source)
    GasJobMenu.add(menu, playerNum, "kit", job, generator, source, source and sourceLabel(generator, source))
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
        local label = getText("ContextMenu_RenewableEnergy_" .. GasKit.CONNECT)
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

local isValid = ISTakeGenerator.isValid
function ISTakeGenerator:isValid()
    return not GasKit.hasKit(self.generator) and isValid(self)
end

-- Generator info window: fuel and gas lines.

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
