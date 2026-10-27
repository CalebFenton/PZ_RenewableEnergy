-- Clean Out Ash in a vanilla wood fire's right-click submenu, beside its fuel (FireAsh).

local FireAsh = require "RenewableEnergy/WoodGas/FireAsh"
local JobOptions = require "cf_commonlib/JobOptions"

-- Vanilla names a fire's submenu by its tile (ISCampingMenu, ISBBQMenu).
JobOptions.onWorldMenu(JobOptions.clicked(FireAsh.isFire), function(context, playerNum, character, fire)
    local name = fire:getTileName()
    local menu = JobOptions.subMenuOf(context, name) or JobOptions.addSubMenu(context, name)
    JobOptions.add(menu, playerNum, FireAsh, FireAsh.CLEAN_ASH, fire)
end)
