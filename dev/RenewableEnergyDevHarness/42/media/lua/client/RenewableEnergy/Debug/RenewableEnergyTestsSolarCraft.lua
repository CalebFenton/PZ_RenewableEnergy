require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibCraft"
local Specs = require "RenewableEnergy/Specs"
local Recipes = require "RenewableEnergy/Recipes"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local Items = require "cf_commonlib/Items"
local Sprites = require "RenewableEnergy/Sprites"

-- Solar crafting: what a module shows through its life (Sprites.lua) and mount, module and glass
-- recipes (Recipes.lua, ModuleRepair.lua).

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual, player = T.test, T.expect, T.expectNear, T.expectEqual, T.player
local MODULES_KEY = Panel.MODULES_KEY

-- What a flat panel shows of a module through its life (Sprites.crackOverlays): whole when new,
-- light cracks from the first storm crack until under half its ConditionMax, heavy cracks below,
-- still cracked once sealed (where Seal Cracked Module takes it) and whole once reglazed; a
-- homemade module the same. Each row: the module, how many storm cracks it took from new, and
-- what it shows then.
local LIFE_LOOKS = {
    { T.FACTORY_MODULE, 0, nil },
    { T.FACTORY_MODULE, 1, "light" },
    { T.FACTORY_MODULE, 2, "heavy" },
    { T.HOMEMADE_MODULE, 0, nil },
    { T.HOMEMADE_MODULE, 1, "light" },
    { T.HOMEMADE_MODULE, 2, "heavy" },
}
test("renewable_energy_solar_crack_looks_follow_the_module", {
    run = function(self)
        local function shows(record)
            return table.concat(Sprites.crackOverlays("flat", nil, nil, { record }), ",")
        end
        self.rows = {}
        local function reglazed(record)
            return shows({ type = record.type, condition = Items.conditionMaxOf(record.type) })
        end
        for _, row in ipairs(LIFE_LOOKS) do
            local module, cracks = row[1], row[2]
            local condition = Items.conditionMaxOf(module) - cracks * Specs.storm.crack
            local record = { type = module, condition = condition, repaired = 0 }
            local sealed, sealedReglazed = nil, nil
            if ModuleRepair.sealable(record.type, record.condition, record.repaired) then
                local copy = { type = module }
                copy.condition, copy.repaired = ModuleRepair.sealed(module, condition, 0)
                sealed, sealedReglazed = { look = ModuleRepair.crackLookOf(module, copy.condition), shows = shows(copy) },
                    reglazed(copy)
            end
            table.insert(self.rows, { row = row, condition = condition, cracked = shows(record), sealed = sealed,
                reglazed = reglazed(record), sealedReglazed = sealedReglazed })
        end
    end,
    validate = function(self)
        for _, result in ipairs(self.rows) do
            local module, cracks, look = result.row[1], result.row[2], result.row[3]
            local what = module .. " at " .. result.condition .. " after " .. cracks .. " cracks"
            local expected = look and Sprites.cracks[look].flat[1] or ""
            expectEqual(what .. ": its look", result.cracked, expected)
            if result.sealed then
                local look = result.sealed.look
                if expect(look ~= nil, what .. ", sealed once: shows whole") then
                    expectEqual(what .. ", sealed once: its look", result.sealed.shows, Sprites.cracks[look].flat[1])
                end
            end
            expectEqual(what .. ", reglazed: its look", result.reglazed, "")
            if result.sealedReglazed then
                expectEqual(what .. ", sealed then reglazed: its look", result.sealedReglazed, "")
            end
        end
        -- Rows whose modules Seal Cracked Module takes, so the sealed look above was tested.
        local sealedRows = 0
        for _, result in ipairs(self.rows) do
            sealedRows = sealedRows + (result.sealed and 1 or 0)
        end
        expect(sealedRows >= 2, "only " .. sealedRows .. " rows could be sealed")
    end,
})

-- Panel mounts --------------------------------------------------------------------------------

-- The module record (Panel.moduleRecord's fields) of the T.carriedItems entry `item` of `fullType`.
local function recordOf(item, fullType)
    local data = item and item.modData
    return item and { type = fullType, condition = item.condition, repaired = item.repaired,
        mounted = data[Panel.MOUNTED_ONCE_KEY] == true, connected = data[Panel.CONNECTED_ONCE_KEY] == true }
end

-- Expects the module record `got` to be `want`: its type at its condition, seals and marks.
local function expectModule(what, got, want)
    if not expect(got ~= nil, what .. " is missing") then return end
    expectEqual(what .. "'s type", got.type, want.type)
    expectEqual(what .. "'s condition", got.condition, want.condition)
    expectEqual(what .. "'s seals", got.repaired or 0, want.repaired or 0)
    expectEqual(what .. " marked as mounted before", got.mounted == true, want.mounted == true)
    expectEqual(what .. " marked as connected before", got.connected == true, want.connected == true)
end

local FLAT, RACK, METAL_RACK = "RenewableEnergy.SolarFlat", "RenewableEnergy.SolarRackWood", "RenewableEnergy.SolarRackMetal"
-- A module off a found panel a player connected to a bank and sealed twice: a world panel's record has no mounted mark, so it still teaches mounting. Its condition and seals
-- are none a new module has, so a mount that recorded a new module instead would give back
-- something else.
local FOUND = { type = T.FACTORY_MODULE, condition = 72, repaired = 2, mounted = true, connected = true }
-- The rack's second module: new to mounting, and of the other type.
local NEW_HOMEMADE = { type = T.HOMEMADE_MODULE, condition = 41 }
-- What loads the character past what they can carry.
local LOAD = "Base.Log"

-- Mounting records each module's type, condition, seals and marks, and unmounting gives it back as
-- it went in. A module teaches its share of the mount's XP only the first time it is ever mounted:
-- mounted, unmounted and mounted again it teaches nothing, and a rack of it and a new module teaches
-- the new one's share. A mount nobody wrote modules to, as debug spawns make, holds new factory
-- modules. The XP is the authority's character's, read around each craft. The rack's item on this
-- client shows its one homemade module (its model index), carried or, crafted by a character
-- carrying too much, dropped on the floor, its icon too.
test("renewable_energy_solar_craft_mounts_keep_their_modules_and_teach_once", {
    instant = true,
    run = function(self)
        local names = { "RenewableEnergy_MakeSolarFlat", "RenewableEnergy_UnmountSolarFlat", "RenewableEnergy_MakeSolarRackWood",
            "RenewableEnergy_UnmountSolarRackMetal" }
        local recipes = T.readyToCraft(self, names)
        if not recipes then return end
        local makeFlat, unmountFlat, makeRack, unmountRack = recipes[names[1]], recipes[names[2]], recipes[names[3]], recipes[names[4]]
        local function readXp(label) T.readCharacter(self, label, { perks = { "Electricity" } }) end
        readXp("start")
        self.flat = T.craftFrom(self, makeFlat, { type = FOUND.type, condition = FOUND.condition, repaired = FOUND.repaired,
            modData = { [Panel.CONNECTED_ONCE_KEY] = true } }, { read = { FLAT } })
        readXp("mounted")
        self.unmounted = T.craftFrom(self, unmountFlat, FLAT, { read = { T.FACTORY_MODULE } })
        readXp("unmounted")
        self.remounted = T.craftFrom(self, makeFlat, T.FACTORY_MODULE)
        readXp("remounted")
        T.craftFrom(self, unmountFlat, FLAT)
        readXp("beforeRack")
        local function withNewHomemade(items)
            for _, item in ipairs(items) do
                if item.type == T.FACTORY_MODULE then
                    item.count = item.count - 1
                end
            end
            table.insert(items, NEW_HOMEMADE)
        end
        self.rack = T.craftFrom(self, makeRack, T.FACTORY_MODULE, { inputs = withNewHomemade, read = { RACK } })
        T.waitFor(self, function()
            local rack = T.carried(RACK)
            return rack ~= nil and rack:getModelIndex() == 1
        end, "this client's rack with model index 1, for its one homemade module")
        readXp("rack")
        -- Loaded past what the character can carry, the next rack drops on their square.
        local stand = T.player():getCurrentSquare()
        self.droppedRack = T.craftFrom(self, makeRack, { type = T.FACTORY_MODULE, condition = 100 }, {
            inputs = withNewHomemade,
            setup = function()
                local p = T.player()
                local load = math.ceil(p:getInventory():getEffectiveCapacity(p) / getScriptManager():getItem(LOAD):getActualWeight()) + 1
                T.give(self, "load", { { type = LOAD, count = load } })
            end,
        })
        T.waitFor(self, function()
            local objects = stand:getWorldObjects()
            for i = 0, objects:size() - 1 do
                local item = objects:get(i):getItem()
                if item and item:getFullType() == RACK then
                    local icon = item:getTex()
                    self.dropped = { index = item:getModelIndex(), icon = icon and icon:getName() }
                    return self.dropped.index == 1
                end
            end
            return false
        end, "this client's dropped rack with model index 1, for its one homemade module")
        T.takeFloorItems(self, { stand })
        T.takeItems(self, nil, LOAD)
        self.spawned = T.craftFrom(self, unmountRack, { type = METAL_RACK }, { read = { T.FACTORY_MODULE } })
        T.batch(function()
            -- What the game gives this character for each award, through the call CraftRecipe.addXP
            -- makes: the flat's for one new module, the rack's share for one of its two, and the
            -- rack's own xpAward for building the frame, given whatever the modules.
            T.xpAward(self, "Electricity", Recipes.MOUNTS[FLAT].xp.Electricity, "flatAward")
            T.xpAward(self, "Electricity", Recipes.MOUNTS[RACK].xp.Electricity / 2, "rackShareAward")
            local frame = 0
            for i = 0, makeRack:getXPAwardCount() - 1 do
                local award = makeRack:getXPAward(i)
                if award:getPerk() == Perks.Electricity then frame = frame + award:getAmount() end
            end
            T.xpAward(self, "Electricity", frame, "rackFrameAward")
        end)
    end,
    validate = function(self)
        for _, craft in ipairs({ { self.flat, "mounting the found module" }, { self.unmounted, "unmounting it" },
            { self.remounted, "mounting it again" }, { self.rack, "mounting it in a rack" }, { self.spawned, "unmounting a spawned rack" },
            { self.droppedRack, "mounting a rack too heavy to carry" } }) do
            T.expectCrafted(craft[1], craft[2])
        end
        expectEqual("the dropped rack's model index on this client", self.dropped and self.dropped.index, 1)
        expectEqual("the dropped rack's icon on this client", self.dropped and self.dropped.icon,
            "Item_RenewableEnergy_SolarRackWood_Homemade1")
        local flat = T.carriedFirst(self, FLAT, self.flat.label)
        local held = flat and flat.modData[MODULES_KEY] or {}
        expectEqual("modules the flat mount holds", #held, 1)
        expectModule("the flat mount's module", held[1], FOUND)
        expectModule("the module unmounted", recordOf(T.carriedFirst(self, T.FACTORY_MODULE, self.unmounted.label), T.FACTORY_MODULE),
            FOUND)
        local rack = T.carriedFirst(self, RACK, self.rack.label)
        held = rack and rack.modData[MODULES_KEY] or {}
        expectEqual("modules the rack holds", #held, 2)
        -- Which input the craft lists first is its own business.
        local byType = {}
        for _, module in ipairs(held) do
            byType[module.type] = module
        end
        expectModule("the rack's factory module", byType[T.FACTORY_MODULE], FOUND)
        expectModule("the rack's homemade module", byType[T.HOMEMADE_MODULE],
            { type = NEW_HOMEMADE.type, condition = NEW_HOMEMADE.condition, mounted = true })
        local spawned = T.carriedItems(self, T.FACTORY_MODULE, self.spawned.label)
        expectEqual("modules a spawned rack gives", #spawned, Specs.mounts.rack.modules)
        for i, item in ipairs(spawned) do
            expectModule("the spawned rack's module " .. i, recordOf(item, T.FACTORY_MODULE),
                { type = T.FACTORY_MODULE, condition = Items.conditionMaxOf(T.FACTORY_MODULE) })
        end
        local reads = self.reads
        local function gained(from, to) return reads[to].xp.Electricity - reads[from].xp.Electricity end
        expect(reads.flatAward.gained > 0, "the flat mount's award gives no XP, so the XP checks prove nothing")
        expectNear("Electricity XP from mounting the found module", gained("start", "mounted"), reads.flatAward.gained, 0.01)
        expectEqual("Electricity XP from unmounting", gained("mounted", "unmounted"), 0)
        expectEqual("Electricity XP from mounting the same module again", gained("unmounted", "remounted"), 0)
        expectNear("Electricity XP from a rack of a used and a new module", gained("beforeRack", "rack"),
            reads.rackShareAward.gained + reads.rackFrameAward.gained, 0.01)
    end,
})

-- Solar modules -------------------------------------------------------------------------------

-- What each module recipe does to a factory module, or refuses, by its condition and seals. Seal
-- Cracked Module adds ModuleRepair.SEAL_ADDS up to its cap, a Wear.REPAIR_LIMIT_STEP lower for each
-- earlier seal, and its OnTest refuses a module at that cap. Reglaze Module's new glass brings any
-- damaged module, heavily cracked and sealed or barely scratched, back to new, and the old glass's
-- seals no longer count; its OnTest refuses only a module at new. Only a shattered module comes apart: one that still makes power is worth
-- more whole. A homemade module differs only in its watts.
local SEAL, REGLAZE, TAKE_APART = "RenewableEnergy_RepairCrackedModule", "RenewableEnergy_ReglazeModule",
    "RenewableEnergy_TakeApartShatteredModule"
local CAP = ModuleRepair.SEAL_CAP
local function sealCap(seals) return CAP - seals * Wear.REPAIR_LIMIT_STEP end
local function share(part) return math.floor(Items.conditionMaxOf(T.FACTORY_MODULE) * part) end
local HEAVY, NEW = share(Specs.crackLooks.heavyBelow) - 1, share(1)
T.conditionCraftsTest("renewable_energy_solar_craft_module_by_condition_and_seals", T.FACTORY_MODULE, {
    { SEAL, "adds a step", before = CAP - ModuleRepair.SEAL_ADDS - 1, repaired = 0, after = CAP - 1, repairedAfter = 1 },
    { SEAL, "just below the cap stops at it", before = CAP - 1, repaired = 0, after = CAP, repairedAfter = 1 },
    { SEAL, "after two seals stops at the lower cap", before = sealCap(2) - 1, repaired = 2, after = sealCap(2), repairedAfter = 3 },
    { SEAL, "at the cap refused", before = CAP, repaired = 0, refused = true },
    { REGLAZE, "heavy cracks and seals come back as new", before = HEAVY, repaired = 3, after = NEW, repairedAfter = 0 },
    { REGLAZE, "a little wear comes back as new", before = NEW - 5, repaired = 0, after = NEW, repairedAfter = 0 },
    { REGLAZE, "at new refused", before = NEW, repaired = 0, refused = true },
    { TAKE_APART, "a working module refused", before = 1, repaired = 0, refused = true },
    { TAKE_APART, "a shattered module comes apart", before = 0, repaired = 0, used = true },
})

-- A seal on a module in a nearby crate reaches this client with its repair count as well as its
-- condition: the recipe's OnTest reads the count here, and a stale one offers a seal the server
-- refuses (InventoryItem.syncItemFields sends the count only for an item a player holds).
test("renewable_energy_solar_craft_seal_in_a_crate_reaches_clients", {
    run = function(self)
        local square = player():getSquare()
        local at = { x = square:getX() + 1, y = square:getY(), z = square:getZ() }
        T.server(self, "moduleInCrate", { x = at.x, y = at.y, z = at.z, condition = CAP - ModuleRepair.SEAL_ADDS - 1 })
        local function copy()
            local here = getSquare(at.x, at.y, at.z)
            local objects = here and here:getObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local container = objects:get(i):getContainer()
                local module = container and container:getItemWithID(self.server.moduleInCrate.id)
                if module then
                    return module
                end
            end
            return nil
        end
        T.waitFor(self, function() return copy() ~= nil end, "this client's copy of the crate's module")
        T.server(self, "sealModuleInCrate", function()
            return { x = at.x, y = at.y, z = at.z, id = self.server.moduleInCrate.id }
        end)
        T.waitFor(self, function()
            local module = copy()
            return module ~= nil and module:getHaveBeenRepaired() == 1 and module:getCondition() == CAP - 1
        end, "the sealed module's repair count and condition on this client")
    end,
    validate = function(self)
        expectEqual("the server's module, repairs", self.server.sealModuleInCrate.repaired, 1)
        expectEqual("the server's module, condition", self.server.sealModuleInCrate.condition, CAP - 1)
    end,
})

-- Take Out Window Glass's OnTest. Every picked-up tile is the same script item, so only the
-- window's sprite may pass; the tools it is also asked about aren't its business.
test("renewable_energy_solar_take_out_window_glass_takes_only_windows", {
    run = function(self)
        local function passes(fullType) return Recipes.isWindow(instanceItem(fullType), player()) end
        expect(passes("Moveables.fixtures_windows_01_0"), "a picked-up window was refused")
        expect(not passes("Moveables.furniture_seating_indoor_02_0"), "a picked-up chair passed")
        expect(passes("Base.Screwdriver"), "the tool was refused")
    end,
})
