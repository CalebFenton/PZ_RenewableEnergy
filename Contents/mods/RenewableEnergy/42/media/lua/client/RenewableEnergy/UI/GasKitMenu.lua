-- The Gas Conversion Kit's options in a vanilla generator's right-click menu, and its Take
-- Generator greyed out while a kit is fitted (GasKit refuses the action itself).

local GasKit = require "RenewableEnergy/GasLine/GasKit"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local JobOptions = require "cf_commonlib/JobOptions"
local Needs = require "cf_commonlib/Needs"

local GasKitMenu = {}

-- "Barrel Digester (6 squares)": a source Connect Gas Line can run to, by its name and distance.
local function sourceLabel(generator, source)
    local owner = GasKit.SOURCES[GasKit.sourceKind(source)].owner
    return getText("ContextMenu_RenewableEnergy_LineTo", getText(owner.nameKey(owner.tierOf(source))),
        round(GasKit.lineLength(generator, source)))
end

--- Adds the kit's options for `generator` to `menu`.
function GasKitMenu.addOptions(playerNum, menu, generator)
    local state = GasKit.stateOf(generator)
    if not state then
        JobOptions.add(menu, playerNum, GasKit, GasKit.INSTALL, generator)
        return
    end
    if state.source then
        JobOptions.add(menu, playerNum, GasKit, GasKit.DISCONNECT, generator)
    else
        local sources = GasKit.sourcesNear(generator)
        local label = getText(Action.labelKey(GasKit.CONNECT))
        if #sources == 0 then
            Needs.refuse(menu:addOption(label), "Tooltip_RenewableEnergy_NoDigesterInReach", GasKit.REACH)
        else
            local submenu = JobOptions.addSubMenu(menu, label)
            for _, source in ipairs(sources) do
                JobOptions.add(submenu, playerNum, GasKit, GasKit.CONNECT, generator, source, sourceLabel(generator, source))
            end
        end
    end
    for _, job in ipairs({ GasKit.TO_GAS, GasKit.TO_PETROL, GasKit.REMOVE }) do
        JobOptions.add(menu, playerNum, GasKit, job, generator)
    end
end

-- The kit's options go in vanilla's generator submenu, where the generator's other jobs are.
JobOptions.onWorldMenu(JobOptions.clicked(GeneratorReach.isVanillaGenerator), function(context, playerNum, character, generator)
    local name = getText("ContextMenu_Generator")
    local menu = JobOptions.subMenuOf(context, name) or JobOptions.addSubMenu(context, name)
    GasKitMenu.addOptions(playerNum, menu, generator)
    if GasKit.hasKit(generator) then
        local take = menu:getOptionFromName(getText("ContextMenu_GeneratorTake"))
        if take then
            Needs.refuse(take, "Tooltip_RenewableEnergy_RemoveKitFirst")
        end
    end
end)

return GasKitMenu
