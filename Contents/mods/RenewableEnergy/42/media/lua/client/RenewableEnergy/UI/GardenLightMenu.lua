-- A solar garden light's right-click menu: its bulb put in or taken out. The jobs' options are
-- cf_commonlib's JobOptions'.

local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local Format = require "RenewableEnergy/UI/Format"
local JobOptions = require "cf_commonlib/JobOptions"

local GardenLightMenu = {}

--- Remove Light Bulb for a light that has one, else Add Light Bulb with one option for each type
--- of bulb the character carries, shown in its colour as vanilla shows a lamp's. Returns the
--- light's submenu.
function GardenLightMenu.addOptions(playerNum, context, light)
    local menu = JobOptions.addSubMenu(context, Format.tileName(light))
    if SolarGardenLight.getBulb(light) then
        JobOptions.add(menu, playerNum, SolarGardenLight, SolarGardenLight.REMOVE_BULB, light)
        return menu
    end
    local bulbs = SolarGardenLight.bulbsOf(getSpecificPlayer(playerNum))
    if #bulbs == 0 then
        JobOptions.add(menu, playerNum, SolarGardenLight, SolarGardenLight.ADD_BULB, light)
        return menu
    end
    local submenu = JobOptions.addSubMenu(menu, getText("ContextMenu_AddLightbulb"))
    for _, bulb in ipairs(bulbs) do
        local option = JobOptions.add(submenu, playerNum, SolarGardenLight, SolarGardenLight.ADD_BULB, light, bulb,
            bulb:getDisplayName())
        option.iconTexture = bulb:getTex()
        option.color = { r = bulb:getColorRed(), g = bulb:getColorGreen(), b = bulb:getColorBlue() }
    end
    return menu
end

GardenLightMenu.onFill = JobOptions.onWorldMenu(JobOptions.clicked(SolarGardenLight.isLight),
    function(context, playerNum, character, light)
        GardenLightMenu.addOptions(playerNum, context, light)
    end)

return GardenLightMenu
