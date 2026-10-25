require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"

-- The mod's loot (Distributions.lua, WorldSpawns.lua): its tables live only where loot is rolled,
-- so the checks run there (RenewableEnergyTestServerLoot.lua).

local T = RenewableEnergyTest
local test, serverCheck = T.test, T.serverCheck

-- Lists ----------------------------------------------------------------------------------------

-- Every entry names an item that exists, since the game drops an unknown item silently, and sits
-- in a list the game rolls: a room's procList, a vehicle's container, a stash house's spawn
-- table or a corpse's outfit list. The game hands each item out: not obsolete, light enough for a
-- crate, and with a weight and loot multiplier above 0 at the default settings.
serverCheck("renewable_energy_loot_lists_in_use", "lootListsInUse")

-- Vehicles -------------------------------------------------------------------------------------

-- The utility vans keep every vanilla builder's item and get the mod's own truck bed; trailers
-- can roll a camper's.
serverCheck("renewable_energy_loot_vehicle_tables", "lootVehicleTables")

-- Rarity options ------------------------------------------------------------------------------

-- Each option scales its items' weights everywhere; at 0 it removes them, since the zombie density
-- bonus would still spawn a weight-0 item. Applying again replaces entries instead of adding more.
serverCheck("renewable_energy_loot_rarity_options_scale_weights", "lootRarityOptions", { rows = {
    { LRMSolarPanels = 0, LRMBatteries = 0, LRMMisc = 0 },
    { LRMSolarPanels = 0, LRMBatteries = 1, LRMMisc = 1 },
    { LRMSolarPanels = 2.5, LRMBatteries = 0.5, LRMMisc = 3 },
} })

-- Found batteries -------------------------------------------------------------------------------

-- Batteries that rooms and corpses hand out hold a part charge, once: a later refill leaves a
-- battery already there alone.
test("renewable_energy_loot_found_batteries_part_charged", {
    run = function(self)
        local square = T.square(self, nil, "a free outdoor square")
        if not square then return end
        T.server(self, "lootFoundBatteries", T.at(square))
    end,
    validate = function(self) T.expectNoFailures(self.server.lootFoundBatteries) end,
})

-- Inverters and controllers that rooms hand out come worn, once: a later refill leaves a found or
-- crafted part already there alone, and a bank's parts are never worn by a fill.
serverCheck("renewable_energy_loot_found_parts_worn", "lootFoundParts")

-- Containers the player owns --------------------------------------------------------------------

-- Loot respawn (LootRespawn.respawnInContainer) never refills a player's bank, charger or crate
-- with free items: every room's table for the tiles' container types is empty, and they get no
-- cracked modules.
serverCheck("renewable_energy_loot_player_containers_not_refilled", "lootPlayerContainers", { sprites = {
    "batteryBoxWood", "batteryBoxMetal", "batteryRackWood", "batteryRackMetal", "batteryBankWood", "batteryBankMetal",
    "cellCharger", "crate",
} })
