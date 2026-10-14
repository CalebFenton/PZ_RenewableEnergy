-- The mechanics window's tooltip lists a part's skills as recommended, in its good colour at any
-- level, since for vanilla's parts they only lower the odds of the job
-- (VehicleUtils.calculateInstallationSuccess). The arrow board's panels require theirs
-- (ArrowBoard.panelInstallTest), so their tooltip lists the skills among what the job needs, in
-- the bad colour when short, as vanilla lists the Mechanics level taking engine parts needs.
-- Vanilla's odds lines go with them: with the skills met the job always succeeds, and short of
-- them it can't start, and the window greys it out (BaseVehicle.canUninstallPart runs the test).

require "Vehicles/ISUI/ISVehicleMechanics"
require "RenewableEnergy/UI/Needs"

local Needs = RenewableEnergy.Needs

local JOBS = { install = true, uninstall = true }

local vanillaDoMenuTooltip = ISVehicleMechanics.doMenuTooltip

function ISVehicleMechanics:doMenuTooltip(part, option, lua, name)
    vanillaDoMenuTooltip(self, part, option, lua, name)
    -- ArrowBoard is server Lua, which loads after this file.
    local skills = JOBS[lua] and RenewableEnergy.ArrowBoard.isPanel(part) and part:getTable(lua).skills
    if not (skills and option.toolTip) then
        return
    end
    local needs, first = {}, nil
    for _, skill in ipairs(skills:split(";")) do
        local perkName, level = VehicleUtils.split(skill, ":")
        local perk = Perks.FromString(perkName)
        table.insert(needs, { perk = perk, have = self.chr:getPerkLevel(perk), need = tonumber(level) })
        -- Vanilla's own line for the first skill, where its skills and odds begin.
        first = first or " " .. ISVehicleMechanics.ghs .. " " .. getText("Tooltip_vehicle_recommendedSkill",
            getText("IGUI_perks_" .. perkName), self.chr:getPerkLevel(perk) .. "/" .. level) .. " <LINE> <LINE>"
    end
    -- They end where vanilla's line for a part that can be repaired once off begins, or the text does.
    local text = option.toolTip.description
    local from = text:find(first, 1, true) or #text + 1
    local to = text:find(" <LINE> <RGB:1,1,1>" .. getText("Tooltip_RepairableUninstalled"), from, true) or #text + 1
    option.toolTip.description = text:sub(1, from - 1) .. Needs.lines(needs) .. text:sub(to)
end
