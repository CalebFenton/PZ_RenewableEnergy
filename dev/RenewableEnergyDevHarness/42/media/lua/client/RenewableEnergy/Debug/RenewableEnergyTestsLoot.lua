require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
local Stash = require "RenewableEnergy/Stash"

-- The mod's loot (Distributions.lua, LootEntries.lua, Finds.lua): its tables live only where loot
-- is rolled, so the checks run there (RenewableEnergyTestServerLoot.lua). They feed the mod's
-- code what the game hands it rather than sampling the game's rolls, which the --loot report
-- measures.

local T = RenewableEnergyTest
local test, serverCheck = T.test, T.serverCheck

-- Lists ----------------------------------------------------------------------------------------

-- Every entry names an item that exists, since the game drops an unknown item silently, and sits
-- in a list the game rolls: a room's procList, a vehicle's container, a stash house's spawn
-- table, a corpse's or a bag's. The game hands each item out: not obsolete, light enough for a
-- crate, and with a weight and loot multiplier above 0 at the default settings. The utility vans
-- and camper trailers roll the mod's lists and keep their vanilla loot, and the prepper's map
-- drops from every survivalist and bandit outfit.
serverCheck("renewable_energy_loot_lists_in_use", "lootListsInUse")

-- Options ---------------------------------------------------------------------------------------

-- Each rarity option scales its items' weights everywhere; at 0 it removes them, since the zombie
-- density bonus would still spawn a weight-0 item. The Stash Houses option puts the stash maps in
-- at their own weights when it hands out maps and removes them otherwise. Applying again replaces
-- entries instead of adding more.
local MODE = Stash.MODE
serverCheck("renewable_energy_loot_options_scale_weights", "lootOptions", { rows = {
    { options = { LRMSolarPanels = 0, LRMBatteries = 0, LRMMisc = 0, StashMode = MODE.NONE }, maps = false },
    { options = { LRMSolarPanels = 0, LRMBatteries = 1, LRMMisc = 1, StashMode = MODE.MAPS }, maps = true },
    { options = { LRMSolarPanels = 2.5, LRMBatteries = 0.5, LRMMisc = 3, StashMode = MODE.STOCKED }, maps = false },
    { options = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1, StashMode = MODE.MAPS_AND_STOCKED }, maps = true },
} })

-- Found items ------------------------------------------------------------------------------------

-- A container's fill, or the first sight of its room for the safehouse and stash house fills that
-- fire no fill event, readies the mod's finds once: batteries at a part charge, inverters and
-- controllers worn. A refill leaves what has a charge or condition of its own alone, and nothing
-- in a bank is worn.
test("renewable_energy_loot_finds_readied_once", {
    run = function(self)
        local square = T.square(self, nil, "a free outdoor square")
        if not square then return end
        T.read(self, "lootFindsReadied", T.at(square), "finds")
    end,
    validate = function(self) T.expectNoFailures(self.reads.finds) end,
})

-- Containers the player owns --------------------------------------------------------------------

-- Loot respawn (LootRespawn.respawnInContainer) never refills a player's bank, charger or crate
-- with free items: every room's table for the tiles' container types is empty, and they get no
-- cracked modules.
serverCheck("renewable_energy_loot_player_containers_not_refilled", "lootPlayerContainers", { sprites = {
    "batteryBoxWood", "batteryBoxMetal", "batteryRackWood", "batteryRackMetal", "batteryBankWood", "batteryBankMetal",
    "cellCharger", "crate",
} })
