-- Clean Out Ash in a vanilla wood fire's right-click submenu, beside its fuel (FireAsh).

local FireAsh = require "RenewableEnergy/WoodGas/FireAsh"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local JobOptions = require "cf_commonlib/JobOptions"
local Needs = require "cf_commonlib/Needs"

-- Vanilla names a fire's submenu by its tile (ISCampingMenu, ISBBQMenu).
JobOptions.onWorldMenu(FireAsh.isFire, function(context, playerNum, character, fire)
    local name = fire:getTileName()
    local menu = Needs.subMenuOf(context, name) or Needs.addSubMenu(context, name)
    JobOptions.add(menu, playerNum, Action, "fire", FireAsh.CLEAN_ASH, fire)
end)
