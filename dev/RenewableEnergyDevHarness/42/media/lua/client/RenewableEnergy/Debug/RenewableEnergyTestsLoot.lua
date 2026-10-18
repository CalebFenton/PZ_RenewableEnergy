require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"

-- The mod's loot (Distributions.lua, WorldSpawns.lua): its tables live only where loot is rolled, so
-- the checks run there (RenewableEnergyTestServerLoot.lua).

local T = RenewableEnergyTest
local test, serverCheck = T.test, T.serverCheck

-- Lists ----------------------------------------------------------------------------------------

-- Every entry names an item that exists, since the game drops an unknown item silently, and sits
-- once in a list the game rolls: a room's procList, a vehicle's container, a stash house's spawn
-- table or a corpse's outfit list.
serverCheck("renewable_energy_loot_lists_in_use", "lootListsInUse")

-- Every list actually hands out every item it lists, through the game's own rolls. The loot
-- rarity options are at their maximum, so a few rolls are enough even for the rarest entries.
serverCheck("renewable_energy_loot_items_spawn", "lootItemsSpawn")

-- Stage 0 gear turns up more often than stage 1 gear, and that more often than stage 2 gear.
serverCheck("renewable_energy_loot_later_stages_rarer", "lootLaterStagesRarer", { ladders = {
    { "RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter", "RenewableEnergy.InverterCharger" },
    { "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery" },
    { "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2" },
    { "RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarModule" },
} })

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
        T.server(self, "lootFoundBatteries", { x = square:getX(), y = square:getY(), z = square:getZ() })
    end,
    validate = function(self) T.expectNoFailures(self.server.lootFoundBatteries) end,
})

-- Containers the player owns -----------------------------------------------------------------------

-- Loot respawn (LootRespawn.respawnInContainer) never refills a player's bank, charger or crate
-- with free items, in any room near the character.
serverCheck("renewable_energy_loot_player_containers_not_refilled", "lootPlayerContainers", { sprites = {
    "batteryBoxWood", "batteryBoxMetal", "batteryRackWood", "batteryRackMetal", "batteryBankWood", "batteryBankMetal",
    "cellCharger", "crate",
} })
