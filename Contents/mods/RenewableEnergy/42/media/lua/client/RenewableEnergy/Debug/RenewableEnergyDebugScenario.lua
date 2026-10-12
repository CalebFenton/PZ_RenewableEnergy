require "RenewableEnergy/Debug/RenewableEnergyDebug"

-- Listed in the SCENARIOS panel on the main menu when the game runs with -debug
-- (DebugScenarios.lua). Starts a zombie-free world in the morning with an electrician who knows
-- every recipe, the materials for all of them and a table to craft at.
debugScenarios = debugScenarios or {}

debugScenarios.RenewableEnergyScenario = {
    name = "Renewable Energy",
    startLoc = { x = 10835, y = 10144, z = 0 }, -- Muldraugh; DebugScenarios requires a start location
    setSandbox = function()
        -- DebugScenarios doesn't record the active mods for the new save (see MainScreen.resetLuaIfNeeded).
        ActiveMods.getById("currentGame"):copyFrom(ActiveMods.getById("default"))
        SandboxVars.Zombies = 6 -- none
    end,
    onStart = function()
        -- Crafting needs light, and the panels need sun.
        getGameTime():setTimeOfDay(10)
        RenewableEnergyDebug.setupPlayer(getPlayer())
    end,
}
