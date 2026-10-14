require "RenewableEnergy/Debug/RenewableEnergyDebug"

-- Listed in the SCENARIOS panel on the main menu when the game runs with -debug
-- (DebugScenarios.lua), and started by every dev harness mode, whose world has no zombies
-- (PZHarness Runner). Starts in the morning with an electrician and carpenter who knows every
-- recipe, a screwdriver and a table to craft at.
debugScenarios = debugScenarios or {}

debugScenarios.RenewableEnergyScenario = {
    name = "Renewable Energy",
    startLoc = { x = 10835, y = 10144, z = 0 }, -- Muldraugh; DebugScenarios requires a start location
    onStart = function()
        -- Crafting needs light, and the panels need sun.
        getGameTime():setTimeOfDay(10)
        RenewableEnergy.Debug.setupPlayer(getPlayer())
    end,
}
