require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"

-- Distributions.lua puts the loot in at OnInitGlobalModData where loot is rolled: in single player,
-- or on a multiplayer server, whose tables alone hold the mod's entries. So the checks run there,
-- in the handlers of RenewableEnergyTestServerLoot.lua, and answer what they found wrong.

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

-- Each option scales the weights of its items in every list, the mod's own lists included. At 0
-- it takes its items out of every list rather than leaving them at weight 0, because
-- ItemPickerJava adds the zombie density bonus to every weight, so they would still spawn in
-- towns; the other options' items stay. Applying the options again, as a second load does,
-- replaces the entries instead of adding more.
serverCheck("renewable_energy_loot_rarity_options_scale_weights", "lootRarityOptions", { rows = {
    { LRMSolarPanels = 0, LRMBatteries = 0, LRMMisc = 0 },
    { LRMSolarPanels = 0, LRMBatteries = 1, LRMMisc = 1 },
    { LRMSolarPanels = 2.5, LRMBatteries = 0.5, LRMMisc = 3 },
} })

-- Found batteries -------------------------------------------------------------------------------

-- Batteries that rooms and corpses hand out hold a part charge, once: a refill of the container by
-- loot respawn leaves a battery already there alone. The server fills crates on a free outdoor
-- square the way the game fills them.
test("renewable_energy_loot_found_batteries_part_charged", {
    run = function(self)
        local square = (T.need(self, T.squares(self, 1), "a free outdoor square") or {})[1]
        if not square then return end
        T.server(self, "lootFoundBatteries", { x = square:getX(), y = square:getY(), z = square:getZ() })
    end,
    validate = function(self) T.expectNoFailures(self.server.lootFoundBatteries) end,
})

-- Containers the player owns -----------------------------------------------------------------------

-- Loot respawn refills an explored, looted container that isn't an IsoThumpable by calling
-- ItemPickerJava.fillContainer(container, nil) (LootRespawn.respawnInContainer). A player's battery
-- bank is an IsoGenerator; if any room handed its container type a loot list, a bank someone took a
-- battery out of would refill with free batteries every respawn. Checked in rooms near the
-- character.
serverCheck("renewable_energy_loot_player_containers_not_refilled", "lootPlayerContainers", { containers = {
    { sprite = "batteryBoxWood", type = "RenewableEnergyBatteryBoxWood" },
    { sprite = "batteryBoxMetal", type = "RenewableEnergyBatteryBoxMetal" },
    { sprite = "batteryRackWood", type = "RenewableEnergyBatteryRackWood" },
    { sprite = "batteryRackMetal", type = "RenewableEnergyBatteryRackMetal" },
    { sprite = "batteryBankWood", type = "RenewableEnergyBatteryBankWood" },
    { sprite = "batteryBankMetal", type = "RenewableEnergyBatteryBankMetal" },
    { sprite = "cellCharger", type = "RenewableEnergyCellCharger" },
    { sprite = "crate", type = "RenewableEnergySolarBox" },
} })
