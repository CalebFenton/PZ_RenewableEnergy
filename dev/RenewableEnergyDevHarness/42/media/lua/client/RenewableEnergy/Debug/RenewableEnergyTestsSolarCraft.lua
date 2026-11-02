require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibCraft"
local Specs = require "RenewableEnergy/Specs"
local Recipes = require "RenewableEnergy/Recipes"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Items = require "cf_commonlib/Items"
local Sprites = require "RenewableEnergy/Sprites"

-- Solar crafting: what a module shows through its life (Sprites.lua) and mount, module and glass
-- recipes (Recipes.lua, ModuleRepair.lua).

local T = RenewableEnergyTest
local test, craftTest, expect, expectNear, expectEqual, player = T.test, T.craftTest, T.expect, T.expectNear, T.expectEqual,
    T.player
local MODULES_KEY = Panel.MODULES_KEY
local function craftName(recipe, behavior) return T.craftName("solar", recipe, behavior) end

-- What a flat panel shows of a module through its life (Sprites.crackOverlays): whole when new,
-- light cracks from the first storm crack until under half its ConditionMax, heavy cracks below,
-- light once sealed (where Seal Cracked Module takes it) and whole once reglazed; a homemade
-- module the same by its own max. Each row: the module, how many storm cracks it took from new,
-- and what it shows then.
local LIFE_LOOKS = {
    { T.FACTORY_MODULE, 0, nil },
    { T.FACTORY_MODULE, 1, "light" },
    { T.FACTORY_MODULE, 2, "light" },
    { T.FACTORY_MODULE, 3, "heavy" },
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
            local glass = ModuleRepair.reglazedCondition(record.type, record.condition, record.repaired)
            return shows({ type = record.type, condition = math.max(record.condition, glass) })
        end
        for _, row in ipairs(LIFE_LOOKS) do
            local module, cracks = row[1], row[2]
            local condition = Items.conditionMaxOf(module) - cracks * Specs.storm.crack
            local record = { type = module, condition = condition, repaired = 0 }
            local sealed, sealedReglazed = nil, nil
            if ModuleRepair.sealable(record.type, record.condition, record.repaired) then
                local copy = { type = module }
                copy.condition, copy.repaired = ModuleRepair.sealed(module, condition, 0)
                sealed, sealedReglazed = shows(copy), reglazed(copy)
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
                expectEqual(what .. ", sealed once: its look", result.sealed, Sprites.cracks.light.flat[1])
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

-- Expects the mount's record of its modules to hold `expected`, each type at its condition and
-- seal count.
local function expectModules(mount, expected)
    local modules = mount and mount.modData[MODULES_KEY]
    if not expectEqual("modules the mount holds", modules and #modules, #expected) then return end
    -- Which input the craft lists first is its own business.
    if #modules == 2 and modules[1].type ~= expected[1].type then
        expected = { expected[2], expected[1] }
    end
    for i, want in ipairs(expected) do
        local got = modules[i]
        expectEqual("module " .. i .. "'s type", got.type, want.type)
        expectEqual("module " .. i .. "'s condition", got.condition, want.condition)
        expectEqual("module " .. i .. "'s seals", got.repaired or 0, want.repaired or 0)
    end
end

-- Every mount item (Recipes.MOUNTS), the modules its Specs.mounts kind holds, and its name, by
-- which its recipes are RenewableEnergy_Make<name> and RenewableEnergy_Unmount<name>.
local MOUNTS = {}
for mount, row in pairs(Recipes.MOUNTS) do
    table.insert(MOUNTS, { mount = mount, count = Specs.mounts[row.kind].modules, name = mount:match("%.(.+)") })
end

-- Mounting records each module's type, condition and seals, at conditions a new module doesn't
-- have; a two-module rack gets one of each type. A mount that recorded new modules instead, or
-- only the first of two, would unmount as something else than went in.
local USED_FACTORY = { type = T.FACTORY_MODULE, condition = 72, repaired = 2 }
local USED_HOMEMADE = { type = T.HOMEMADE_MODULE, condition = 41 }
for _, entry in ipairs(MOUNTS) do
    local mount, count = entry.mount, entry.count
    local recipe = "RenewableEnergy_Make" .. entry.name
    craftTest(craftName(recipe, "keeps_module_condition"), {
        recipe = recipe,
        from = T.FACTORY_MODULE,
        prefer = { T.FACTORY_MODULE },
        setup = function(self)
            local modules = T.inputsOf(self, T.FACTORY_MODULE)
            T.changeItem(self, modules[1], { condition = USED_FACTORY.condition, repaired = USED_FACTORY.repaired })
            if count == 2 then
                -- One of the two a homemade module instead. This client must have lost the
                -- factory one before the craft picks its inputs from its own copy.
                local taken = modules[2]:getID()
                T.takeItems(self, { taken })
                T.give(self, "homemade", { { type = T.HOMEMADE_MODULE, condition = USED_HOMEMADE.condition } })
                T.waitFor(self, function() return player():getInventory():getItemById(taken) == nil end,
                    "this client losing the second factory module")
            end
        end,
        counts = { [T.FACTORY_MODULE] = 0, [T.HOMEMADE_MODULE] = 0, [mount] = 1 },
        after = function(self) T.readCarried(self, { mount }) end,
        validate = function(self)
            expectModules(T.carriedFirst(self, mount), count == 2 and { USED_FACTORY, USED_HOMEMADE } or { USED_FACTORY })
        end,
    })
end

-- Unmounting gives back each module as the type, at the condition and with the seals it went in,
-- still marked as mounted and connected before if it was, and a module not so marked comes back
-- unmarked.
local MOUNTED_HOMEMADE = { type = T.HOMEMADE_MODULE, condition = 41, repaired = 2, mounted = true, connected = true }
local PLAIN_FACTORY = { type = T.FACTORY_MODULE, condition = 12 }
for _, entry in ipairs(MOUNTS) do
    local mount, count = entry.mount, entry.count
    local recipe = "RenewableEnergy_Unmount" .. entry.name
    craftTest(craftName(recipe, "returns_modules"), {
        recipe = recipe,
        from = mount,
        setup = function(self)
            local modules = { MOUNTED_HOMEMADE }
            if count == 2 then
                table.insert(modules, PLAIN_FACTORY)
            end
            T.changeItem(self, T.inputsOf(self, mount)[1], { modData = { [MODULES_KEY] = modules } })
        end,
        counts = { [mount] = 0, [T.HOMEMADE_MODULE] = 1, [T.FACTORY_MODULE] = count == 2 and 1 or 0 },
        after = function(self) T.readCarried(self, { T.HOMEMADE_MODULE, T.FACTORY_MODULE }) end,
        validate = function(self)
            local homemade = T.carriedFirst(self, T.HOMEMADE_MODULE)
            if expect(homemade ~= nil, "no homemade module came back") then
                local data = homemade.modData
                expectEqual("the homemade module's condition", homemade.condition, MOUNTED_HOMEMADE.condition)
                expectEqual("the homemade module's seals", homemade.repaired, MOUNTED_HOMEMADE.repaired)
                expect(data[Panel.MOUNTED_ONCE_KEY] == true and data[Panel.CONNECTED_ONCE_KEY] == true,
                    "the homemade module came back without its mounted and connected marks")
            end
            local factory = T.carriedFirst(self, T.FACTORY_MODULE)
            if count == 2 and expect(factory ~= nil, "no factory module came back") then
                expectEqual("the factory module's condition", factory.condition, PLAIN_FACTORY.condition)
                expectEqual("the factory module's seals", factory.repaired, 0)
                expect(factory.modData[Panel.MOUNTED_ONCE_KEY] ~= true, "the factory module came back marked as mounted before")
            end
        end,
    })
end

-- A mount nobody wrote modules to, as debug spawns make, holds new factory modules.
craftTest(craftName("RenewableEnergy_UnmountSolarRackMetal", "without_record_returns_new_modules"), {
    recipe = "RenewableEnergy_UnmountSolarRackMetal",
    from = "RenewableEnergy.SolarRackMetal",
    counts = { ["RenewableEnergy.SolarRackMetal"] = 0, [T.FACTORY_MODULE] = Specs.mounts.rack.modules },
})

-- Mounting teaches only modules never mounted before: a module mounted, unmounted and mounted
-- again teaches nothing the second time, and a rack of that module and a new one teaches the new
-- one's share. The XP is the authority's character's, read before and after each craft.
test("renewable_energy_solar_mount_xp_only_for_new_modules", {
    instant = true,
    run = function(self)
        local manager = getScriptManager()
        local recipes = {}
        for key, name in pairs({ flat = "RenewableEnergy_MakeSolarFlat", unmount = "RenewableEnergy_UnmountSolarFlat",
            rack = "RenewableEnergy_MakeSolarRackWood" }) do
            recipes[key] = T.need(self, manager:getCraftRecipe(name), "the recipe " .. name)
            if not recipes[key] then return end
        end
        local p = player()
        local module, flat = T.FACTORY_MODULE, "RenewableEnergy.SolarFlat"
        T.learnRecipes(p)
        T.placeWorkTable(p)
        T.setPerk(self, Perks.Electricity, 3)
        T.setPerk(self, Perks.Woodwork, 4)
        local function readXp(label)
            T.readCharacter(self, label, { perks = { "Electricity" } })
        end
        local function craft(recipe, fullType)
            T.waitForCarried(self, fullType, "this client's " .. fullType .. " to craft from")
            T.step(function() T.startCraft(self, recipe, T.carried(fullType)) end)
        end
        -- The flat mount's wire and screws, for each time it is made.
        local fixings = {}
        for _, input in ipairs(T.recipeInputs(recipes.flat, { module })) do
            if input.type ~= module and input.type ~= "Base.Screwdriver" then
                table.insert(fixings, input)
            end
        end
        T.give(self, "flat", T.recipeInputs(recipes.flat, { module }))
        readXp("start")
        craft(recipes.flat, module)
        readXp("mounted")
        craft(recipes.unmount, flat)
        T.give(self, "again", fixings)
        readXp("unmounted")
        craft(recipes.flat, module)
        readXp("remounted")
        craft(recipes.unmount, flat)
        -- The rack's inputs with one new module, beside the one mounted twice.
        local rack = {}
        for _, input in ipairs(T.recipeInputs(recipes.rack, { module })) do
            if input.type == module then
                input.count = input.count - 1
            end
            table.insert(rack, input)
        end
        T.waitForCarried(self, module, "this client's unmounted module")
        T.give(self, "rack", rack)
        readXp("unmountedAgain")
        craft(recipes.rack, module)
        T.batch(function()
            readXp("rack")
            T.count(self, "made", { flat, "RenewableEnergy.SolarRackWood", module })
            -- What the game gives this character for each award, through the call CraftRecipe.addXP
            -- makes.
            local mounts = Recipes.MOUNTS
            T.xpAward(self, "Electricity", mounts[flat].xp.Electricity, "flatAward")
            T.xpAward(self, "Electricity", mounts["RenewableEnergy.SolarRackWood"].xp.Electricity / 2, "rackShareAward")
            -- The rack's own xpAward for building the frame, given whatever the modules.
            local frame = 0
            for i = 0, recipes.rack:getXPAwardCount() - 1 do
                local award = recipes.rack:getXPAward(i)
                if award:getPerk() == Perks.Electricity then frame = frame + award:getAmount() end
            end
            T.xpAward(self, "Electricity", frame, "rackFrameAward")
        end)
    end,
    validate = function(self)
        local refusal = self.refusal and "; the game refused: " .. self.refusal or ""
        local reads, made = self.reads, self.counts.made or {}
        if not expect(reads.rack ~= nil and made["RenewableEnergy.SolarRackWood"] == 1,
            "the crafts never got to the rack" .. refusal) then return end
        local function xp(label) return reads[label].xp.Electricity end
        expect(xp("mounted") > xp("start"), "mounting a new module gave no Electricity XP")
        expectNear("Electricity XP from mounting a new module", xp("mounted") - xp("start"), reads.flatAward.gained, 0.01)
        expectEqual("Electricity XP from unmounting", xp("unmounted") - xp("mounted"), 0)
        expectEqual("Electricity XP from mounting the same module again", xp("remounted") - xp("unmounted"), 0)
        expectNear("Electricity XP from a rack of a used and a new module", xp("rack") - xp("unmountedAgain"),
            reads.rackShareAward.gained + reads.rackFrameAward.gained, 0.01)
    end,
})

-- Solar modules -------------------------------------------------------------------------------

-- Seal Cracked Module adds 20 condition up to the module type's cap (a factory module's 55), 10
-- lower for each earlier seal, and is refused at that limit with the module untouched. Each seal
-- counts once, on this client's copy too, and a sealed module still shows cracked. Each row: the
-- behaviour, the module, its seal count, its condition before, and after (nil where the game
-- refuses). Factory modules only: the homemade module's cap is another row of the same table.
local MODULE_REPAIRS = {
    { "factory_adds_a_step", T.FACTORY_MODULE, 0, 34, 54 },
    { "factory_below_limit_stops_at_limit", T.FACTORY_MODULE, 0, 54, 55 },
    { "factory_at_limit_refused", T.FACTORY_MODULE, 0, 55 },
    { "factory_after_two_seals_stops_at_lower_limit", T.FACTORY_MODULE, 2, 34, 35 },
}
for _, entry in ipairs(MODULE_REPAIRS) do
    local behavior, module, repaired, before, after = entry[1], entry[2], entry[3], entry[4], entry[5]
    local seal = "RenewableEnergy_RepairCrackedModule"
    T.repairCraftTest(craftName(seal, behavior), seal, module, {
        before = before,
        repaired = repaired,
        after = after or before,
        repairedAfter = after and repaired + 1 or repaired,
        refused = after == nil,
        validate = function(_, item)
            -- The seal leaves the glass cracked, and the module showing it.
            expect(ModuleRepair.crackLookOf(module, item.condition) ~= nil, "a sealed module shows whole")
        end,
    })
end

-- Reglaze Module brings a module below what new glass brings it to, and is refused there with the
-- module and the pane untouched, and the new glass clears the old seals.
-- New glass on light cracks brings a module back to new; on heavy cracks, or on a sealed module, to
-- the cells-cracked share of new. Each row: the behaviour, the module, its condition and seal count
-- before, the condition after, and whether the game refuses. Factory modules only: the shares are
-- of the type's ConditionMax, whichever module it is.
local REGLAZE, LOOKS = ModuleRepair.REGLAZE, Specs.crackLooks
local function share(module, part) return math.floor(Items.conditionMaxOf(module) * part) end
local function heavy(module) return share(module, LOOKS.heavyBelow) - 1 end
local function light(module) return share(module, (LOOKS.heavyBelow + LOOKS.lightBelow) / 2) end
local function new(module) return share(module, REGLAZE.glassOnly) end
local function cellsCracked(module) return share(module, REGLAZE.cellsCracked) end
local REGLAZES = {
    { "factory_heavy_cracks_cells_stay_cracked", T.FACTORY_MODULE, heavy(T.FACTORY_MODULE), 0, cellsCracked(T.FACTORY_MODULE) },
    { "factory_light_cracks_back_to_new", T.FACTORY_MODULE, light(T.FACTORY_MODULE), 0, new(T.FACTORY_MODULE) },
    { "factory_sealed_three_times_clears_seals", T.FACTORY_MODULE, light(T.FACTORY_MODULE), 3, cellsCracked(T.FACTORY_MODULE) },
    { "factory_just_below_new_back_to_new", T.FACTORY_MODULE, new(T.FACTORY_MODULE) - 1, 0, new(T.FACTORY_MODULE) },
    { "factory_at_new_refused", T.FACTORY_MODULE, new(T.FACTORY_MODULE), 0, new(T.FACTORY_MODULE), true },
}
for _, entry in ipairs(REGLAZES) do
    local behavior, module, before, repaired, reglazed, refused = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
    local reglaze = "RenewableEnergy_ReglazeModule"
    T.repairCraftTest(craftName(reglaze, behavior), reglaze, module, {
        before = before,
        repaired = repaired,
        after = refused and before or reglazed,
        repairedAfter = refused and repaired or 0,
        refused = refused,
        counts = { [module] = 1, ["Base.GlassPanel"] = refused and 1 or 0 },
        validate = function(_, item)
            if not refused then
                expect(ModuleRepair.crackLookOf(module, item.condition) == nil, "a reglazed module shows cracked")
            end
        end,
    })
end

-- Only a module that makes no power comes apart; one that still works is worth more whole.
for _, entry in ipairs({ { nil, 0 }, { "refuses_working_module", 1 } }) do
    local behavior, condition = entry[1], entry[2]
    craftTest(craftName("RenewableEnergy_TakeApartShatteredModule", behavior), {
        recipe = "RenewableEnergy_TakeApartShatteredModule",
        from = T.FACTORY_MODULE,
        refused = condition > 0,
        setup = function(self)
            T.changeItem(self, T.inputsOf(self, T.FACTORY_MODULE)[1], { condition = condition })
        end,
        counts = condition > 0 and { [T.FACTORY_MODULE] = 1, ["RenewableEnergy.SolarCells"] = 0 } or { [T.FACTORY_MODULE] = 0 },
    })
end

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
