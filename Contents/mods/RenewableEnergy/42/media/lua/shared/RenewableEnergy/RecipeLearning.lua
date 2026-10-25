-- Teaching the mod's recipes by skill level (their AutoLearnAny and AutoLearnAll). Shared: vanilla's
-- own AutoLearn check runs wherever LevelPerk fires (XpUpdate.lua, which every side loads).
--
-- Vanilla's check (ScriptManager.checkAutoLearn) walks only the craftRecipe scripts, and an
-- entity's build recipe is not one of them (CraftRecipeComponentScript.load builds it apart), so
-- without this no build recipe is ever learned by level. The craftRecipes are checked here too, so
-- that a level up on a multiplayer server that teaches one reaches the client whichever LevelPerk
-- hook runs first.

RenewableEnergy = RenewableEnergy or {}
local RecipeLearning = {}
RenewableEnergy.RecipeLearning = RecipeLearning

local PREFIX = "RenewableEnergy_"

-- The mod's recipes, craftRecipes and build recipes, that have an AutoLearn skill, read from the
-- scripts, which each side loads before its Lua; and the perks those skills name, by perk id.
local AUTO_LEARN, AUTO_LEARN_PERKS = {}, {}
do
    local function notePerks(recipe)
        for i = 0, recipe:getAutoLearnAnySkillCount() - 1 do
            AUTO_LEARN_PERKS[recipe:getAutoLearnAnySkill(i):getPerk():getId()] = true
        end
        for i = 0, recipe:getAutoLearnAllSkillCount() - 1 do
            AUTO_LEARN_PERKS[recipe:getAutoLearnAllSkill(i):getPerk():getId()] = true
        end
    end
    local scripts = getScriptManager()
    for _, recipes in ipairs({ scripts:getAllCraftRecipes(), scripts:getAllBuildableRecipes() }) do
        for i = 0, recipes:size() - 1 do
            local recipe = recipes:get(i)
            if recipe:getName():sub(1, #PREFIX) == PREFIX
                    and recipe:getAutoLearnAnySkillCount() + recipe:getAutoLearnAllSkillCount() > 0 then
                table.insert(AUTO_LEARN, recipe)
                notePerks(recipe)
            end
        end
    end
end

-- The packet field of sendSyncPlayerFields that sends the known recipes (SyncPlayerFieldsPacket).
local SYNC_RECIPES = 1

-- The client command that asks the server to catch a joining character up (RecipeLearning.catchUp).
RecipeLearning.COMMAND_MODULE, RecipeLearning.CATCH_UP = "RenewableEnergyRecipes", "catchUp"

--- Teaches `character` each of AUTO_LEARN whose AutoLearn skills it has, through the recipe's own
--- check, so the Inventive trait counts as it does for vanilla's recipes.
local function autoLearn(character)
    for _, recipe in ipairs(AUTO_LEARN) do
        recipe:checkAutoLearnAnySkills(character)
        recipe:checkAutoLearnAllSkills(character)
    end
end

local function knownCount(character)
    local count = 0
    for _, recipe in ipairs(AUTO_LEARN) do
        if character:isRecipeActuallyKnown(recipe) then
            count = count + 1
        end
    end
    return count
end

--- Teaches `character` what its levels already earn, and on a multiplayer server sends its client
--- what that changed. A server runs no check of its own when a player joins (IsoWorld.init checks
--- the local player only, and no event marks a join on the server), so a character who earned a
--- recipe before the mod was added, or before this check existed, would otherwise know it only on
--- its client, and the server would refuse the build. The client asks for this as it enters the
--- world; the server judges by its own copy's levels.
function RecipeLearning.catchUp(character)
    local before = knownCount(character)
    autoLearn(character)
    if isServer() and knownCount(character) ~= before then
        sendSyncPlayerFields(character, SYNC_RECIPES)
    end
end

-- When vanilla checks its own AutoLearn: on every level up (XpUpdate.levelPerk) and when the
-- local player enters the world (IsoWorld.init), here OnCreatePlayer, which on a multiplayer client
-- also asks the server to catch up.
--
-- On a multiplayer server, a level up of a perk the AutoLearn skills name sends the client its
-- known recipes: the server's level up teaches only its own copy of the character, since the
-- client's copy gets the new level in PlayerXpPacket, which fires no LevelPerk, and learnRecipe
-- sends nothing (ISResearchRecipe sends what it taught the same way). It is sent whether or not
-- this hook taught anything: vanilla's own hook may have taught a craftRecipe first, and a level up
-- can teach a recipe of a lower level that the character was never taught.
Events.LevelPerk.Add(function(character, perk)
    autoLearn(character)
    if isServer() and AUTO_LEARN_PERKS[perk:getId()] then
        sendSyncPlayerFields(character, SYNC_RECIPES)
    end
end)
Events.OnCreatePlayer.Add(function(playerNum)
    local character = getSpecificPlayer(playerNum)
    autoLearn(character)
    if isClient() then
        sendClientCommand(character, RecipeLearning.COMMAND_MODULE, RecipeLearning.CATCH_UP, {})
    end
end)
Events.OnClientCommand.Add(function(module, command, player)
    if module == RecipeLearning.COMMAND_MODULE and command == RecipeLearning.CATCH_UP then
        RecipeLearning.catchUp(player)
    end
end)

return RecipeLearning
