require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/PowerBank/PowerBank"

-- Solar crafting: what a module shows through its life (Sprites.lua) and mount and module recipes
-- (Recipes.lua).

local T = RenewableEnergyTest
local test, craftTest, expect, expectNear, player = T.test, T.craftTest, T.expect, T.expectNear, T.player
local Specs, Sprites, Recipes = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Recipes
local PowerBank = RenewableEnergy.PowerBank
local MODULES_KEY = PowerBank.MODULES_KEY
local FACTORY, HOMEMADE = "RenewableEnergy.SolarModule", "RenewableEnergy.HomemadeSolarModule"
local function craftName(recipe, behavior) return T.craftName("solar", recipe, behavior) end

-- What a flat panel shows of a module through its life (Sprites.crackOverlays): whole when new,
-- light cracks from the first storm crack until under half its ConditionMax, heavy cracks below,
-- light once sealed (where Seal Cracked Module takes it) and whole once reglazed; a homemade
-- module the same by its own max. Each row: the module, how many storm cracks it took from new,
-- and what it shows then.
local LIFE_LOOKS = {
    { FACTORY, 0, nil },
    { FACTORY, 1, "light" },
    { FACTORY, 2, "light" },
    { FACTORY, 3, "heavy" },
    { HOMEMADE, 0, nil },
    { HOMEMADE, 1, "light" },
    { HOMEMADE, 2, "heavy" },
}
test("renewable_energy_solar_crack_looks_follow_the_module", {
    run = function(self)
        local function shows(record)
            return table.concat(Sprites.crackOverlays("flat", nil, nil, { record }), ",")
        end
        self.rows = {}
        local function reglazed(record)
            local glass = Recipes.reglazedCondition(record.type, record.condition, record.repaired)
            return shows({ type = record.type, condition = math.max(record.condition, glass) })
        end
        for _, row in ipairs(LIFE_LOOKS) do
            local module, cracks = row[1], row[2]
            local condition = RenewableEnergy.conditionMaxOf(module) - cracks * Specs.storm.crack
            local record = { type = module, condition = condition, repaired = 0 }
            local sealed, sealedReglazed = nil, nil
            if Recipes.canSealRecord(record) then
                local copy = { type = module, condition = condition, repaired = 0 }
                Recipes.sealRecord(copy)
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
            local expected = look and Sprites.cracks[look].flat or ""
            expect(result.cracked == expected, what .. " shows '" .. result.cracked .. "', expected '" .. expected .. "'")
            if result.sealed then
                expect(result.sealed == Sprites.cracks.light.flat, what .. ", sealed once, shows '" .. result.sealed .. "'")
            end
            expect(result.reglazed == "", what .. ", reglazed, shows '" .. result.reglazed .. "'")
            if result.sealedReglazed then
                expect(result.sealedReglazed == "", what .. ", sealed then reglazed, shows '" .. result.sealedReglazed .. "'")
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
    if not expect(modules ~= nil and #modules == #expected,
        "the mount holds " .. tostring(modules and #modules) .. " modules, expected " .. #expected) then
        return
    end
    -- Which input the craft lists first is its own business.
    if #modules == 2 and modules[1].type ~= expected[1].type then
        expected = { expected[2], expected[1] }
    end
    for i, want in ipairs(expected) do
        local got, wantRepaired = modules[i], want.repaired or 0
        expect(got.type == want.type and got.condition == want.condition and (got.repaired or 0) == wantRepaired,
            "module " .. i .. " is " .. tostring(got.type) .. " at " .. tostring(got.condition) .. " sealed "
            .. tostring(got.repaired) .. "x, expected " .. want.type .. " at " .. want.condition .. " sealed " .. wantRepaired .. "x")
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
local FACTORY_MODULE = { type = FACTORY, condition = 72, repaired = 2 }
local HOMEMADE_MODULE = { type = HOMEMADE, condition = 41 }
for _, entry in ipairs(MOUNTS) do
    local mount, count = entry.mount, entry.count
    local recipe = "RenewableEnergy_Make" .. entry.name
    craftTest(craftName(recipe, "keeps_module_condition"), {
        recipe = recipe,
        from = FACTORY,
        prefer = { FACTORY },
        setup = function(self)
            local modules = T.inputsOf(self, FACTORY)
            T.changeItem(self, modules[1], { condition = FACTORY_MODULE.condition })
            T.setRepaired(self, FACTORY, FACTORY_MODULE.repaired)
            if count == 2 then
                -- One of the two a homemade module instead. This client must have lost the
                -- factory one before the craft picks its inputs from its own copy.
                local taken = modules[2]:getID()
                T.server(self, "takeItems", { ids = { taken } })
                T.give(self, "homemade", { { type = HOMEMADE, condition = HOMEMADE_MODULE.condition } })
                T.waitFor(self, function() return player():getInventory():getItemById(taken) == nil end,
                    "this client losing the second factory module")
            end
        end,
        counts = { [FACTORY] = 0, [HOMEMADE] = 0, [mount] = 1 },
        after = function(self) T.readCarried(self, { mount }) end,
        validate = function(self)
            expectModules(T.carriedFirst(self, mount), count == 2 and { FACTORY_MODULE, HOMEMADE_MODULE } or { FACTORY_MODULE })
        end,
    })
end

-- Unmounting gives back each module as the type, at the condition and with the seals it went in,
-- still marked as mounted and connected before if it was, and a module not so marked comes back
-- unmarked.
local MOUNTED_HOMEMADE = { type = HOMEMADE, condition = 41, repaired = 2, mounted = true, connected = true }
local PLAIN_FACTORY = { type = FACTORY, condition = 12 }
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
        counts = { [mount] = 0, [HOMEMADE] = 1, [FACTORY] = count == 2 and 1 or 0 },
        after = function(self) T.readCarried(self, { HOMEMADE, FACTORY }) end,
        validate = function(self)
            local homemade = T.carriedFirst(self, HOMEMADE)
            if expect(homemade ~= nil, "no homemade module came back") then
                local data = homemade.modData
                expect(homemade.condition == MOUNTED_HOMEMADE.condition, "the homemade module came back at " .. homemade.condition)
                expect(homemade.repaired == MOUNTED_HOMEMADE.repaired, "the homemade module came back sealed " .. homemade.repaired .. "x")
                expect(data[PowerBank.MOUNTED_ONCE_KEY] == true and data[PowerBank.CONNECTED_ONCE_KEY] == true,
                    "the homemade module came back without its mounted and connected marks")
            end
            local factory = T.carriedFirst(self, FACTORY)
            if count == 2 and expect(factory ~= nil, "no factory module came back") then
                expect(factory.condition == PLAIN_FACTORY.condition, "the factory module came back at " .. factory.condition)
                expect(factory.repaired == 0, "the factory module came back sealed " .. factory.repaired .. "x")
                expect(factory.modData[PowerBank.MOUNTED_ONCE_KEY] ~= true, "the factory module came back marked as mounted before")
            end
        end,
    })
end

-- A mount nobody wrote modules to, as debug spawns make, holds new factory modules.
craftTest(craftName("RenewableEnergy_UnmountSolarRackMetal", "without_record_returns_new_modules"), {
    recipe = "RenewableEnergy_UnmountSolarRackMetal",
    from = "RenewableEnergy.SolarRackMetal",
    counts = { ["RenewableEnergy.SolarRackMetal"] = 0, [FACTORY] = Specs.mounts.rack.modules },
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
        local module, flat = FACTORY, "RenewableEnergy.SolarFlat"
        T.learnRecipes(p)
        T.placeWorkTable(p)
        T.setPerk(self, Perks.Electricity, 3)
        T.setPerk(self, Perks.Woodwork, 4)
        self.xp = {}
        local function readXp(key)
            T.server(self, "perkXp", { perk = "Electricity" })
            T.step(function() self.xp[key] = self.server.perkXp.value end)
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
            T.server(self, "electricityAward", { xp = mounts[flat].xp.Electricity })
            T.step(function() self.flatAward = self.server.electricityAward.gained end)
            T.server(self, "electricityAward", { xp = mounts["RenewableEnergy.SolarRackWood"].xp.Electricity / 2 })
            T.step(function() self.rackShareAward = self.server.electricityAward.gained end)
            -- The rack's own xpAward for building the frame, given whatever the modules.
            local frame = 0
            for i = 0, recipes.rack:getXPAwardCount() - 1 do
                local award = recipes.rack:getXPAward(i)
                if award:getPerk() == Perks.Electricity then frame = frame + award:getAmount() end
            end
            T.server(self, "electricityAward", { xp = frame })
            T.step(function() self.rackFrameAward = self.server.electricityAward.gained end)
        end)
    end,
    validate = function(self)
        local refusal = self.refusal and "; the game refused: " .. self.refusal or ""
        local xp, made = self.xp, self.counts.made or {}
        if not expect(xp.rack ~= nil and made["RenewableEnergy.SolarRackWood"] == 1,
            "the crafts never got to the rack" .. refusal) then return end
        expect(xp.mounted > xp.start, "mounting a new module gave no Electricity XP")
        expectNear("Electricity XP from mounting a new module", xp.mounted - xp.start, self.flatAward, 0.01)
        expectNear("Electricity XP from unmounting", xp.unmounted - xp.mounted, 0, 0)
        expectNear("Electricity XP from mounting the same module again", xp.remounted - xp.unmounted, 0, 0)
        expectNear("Electricity XP from a rack of a used and a new module", xp.rack - xp.unmountedAgain,
            self.rackShareAward + self.rackFrameAward, 0.01)
    end,
})

-- Solar modules -------------------------------------------------------------------------------

-- Seal Cracked Module adds Recipes.MODULE_REPAIR up to the module type's cap, lowered a step for
-- each earlier seal, and is refused at that limit with the module untouched. Each seal counts
-- once, on this client's copy too, and a sealed module still shows cracked.
-- Each row: the behaviour, the module, its seal count, and its condition before.
local MODULE_REPAIRS = {
    { "factory_adds_a_step", FACTORY, 0, T.sealCap(FACTORY, 0) - Recipes.MODULE_REPAIR - 1 },
    { "factory_below_limit_stops_at_limit", FACTORY, 0, T.sealCap(FACTORY, 0) - 1 },
    { "factory_at_limit_refused", FACTORY, 0, T.sealCap(FACTORY, 0) },
    { "factory_after_two_seals_stops_at_lower_limit", FACTORY, 2, T.sealCap(FACTORY, 2) - 1 },
    { "factory_after_three_seals_at_limit_refused", FACTORY, 3, T.sealCap(FACTORY, 3) },
    { "homemade_below_limit_stops_at_limit", HOMEMADE, 0, T.sealCap(HOMEMADE, 0) - 1 },
    { "homemade_after_one_seal_stops_at_lower_limit", HOMEMADE, 1, T.sealCap(HOMEMADE, 1) - 1 },
}
for _, entry in ipairs(MODULE_REPAIRS) do
    local behavior, module, repaired, before = entry[1], entry[2], entry[3], entry[4]
    local limit = T.sealCap(module, repaired)
    local refused = before >= limit
    local after = refused and before or math.min(limit, before + Recipes.MODULE_REPAIR)
    local repairedAfter = refused and repaired or repaired + 1
    craftTest(craftName("RenewableEnergy_RepairCrackedModule", behavior), {
        recipe = "RenewableEnergy_RepairCrackedModule",
        from = module,
        prefer = { module },
        setup = function(self)
            T.changeItem(self, T.inputsOf(self, module)[1], { condition = before })
            T.setRepaired(self, module, repaired)
        end,
        counts = { [module] = 1 },
        after = function(self)
            T.readCarried(self, { module })
            T.waitForRepaired(self, module, repairedAfter)
        end,
        validate = function(self)
            local item = T.carriedFirst(self, module)
            if not expect(item ~= nil, "the module is gone") then return end
            expect(item.condition == after, "the module is at " .. item.condition .. ", expected " .. after)
            expect(item.repaired == repairedAfter, "the module reads repaired " .. item.repaired .. "x, expected " .. repairedAfter)
            -- The seal leaves the glass cracked, and the module showing it.
            expect(RenewableEnergy.crackLookOf(module, item.condition) ~= nil, "a sealed module shows whole")
            if refused then
                expect(self.refusal ~= nil, "the game would start the seal")
            end
        end,
    })
end

-- Seal Cracked Module and its glue twin each take exactly their adhesive's uses, which a line
-- scaling one adhesive against the other gets wrong (DEVELOPMENT.md, craftRecipe).
-- Each row: the behaviour, the recipe, its adhesive, and the uses of it a seal takes.
local SEAL_ADHESIVES = {
    { "takes_one_use_of_epoxy", "RenewableEnergy_RepairCrackedModule", "Base.Epoxy", 1 },
    { "takes_two_uses_of_glue", "RenewableEnergy_RepairCrackedModuleWithGlue", "Base.Glue", 2 },
}
for _, entry in ipairs(SEAL_ADHESIVES) do
    local behavior, recipe, adhesive, uses = entry[1], entry[2], entry[3], entry[4]
    craftTest(craftName(recipe, behavior), {
        recipe = recipe,
        from = FACTORY,
        prefer = { FACTORY },
        setup = function(self)
            T.changeItem(self, T.inputsOf(self, FACTORY)[1], { condition = T.sealCap(FACTORY, 0) - Recipes.MODULE_REPAIR - 1 })
        end,
        counts = { [FACTORY] = 1 },
        after = function(self) T.readCarried(self, { adhesive }) end,
        validate = function(self)
            -- T.recipeInputs gave one full tube; "carried" reads the fraction of it left.
            local tube = T.carriedFirst(self, adhesive)
            local left = 1 - uses * getScriptManager():FindItem(adhesive):getUseDelta()
            expectNear("the " .. adhesive .. " left of a full tube", tube and tube.uses or 0, left, 0.001)
        end,
    })
end

-- Reglaze Module brings a module below what new glass brings it to, and is refused there with the
-- module and the pane untouched, and the new glass clears the old seals.
-- New glass on light cracks brings a module back to new; on heavy cracks, or on a sealed module, to
-- the cells-cracked share of new. Each row: the behaviour, the module, its condition and seal count
-- before, the condition after, and whether the game refuses.
local REGLAZE, LOOKS = Recipes.REGLAZE, Specs.crackLooks
local function share(module, part) return math.floor(RenewableEnergy.conditionMaxOf(module) * part) end
local function heavy(module) return share(module, LOOKS.heavyBelow) - 1 end
local function light(module) return share(module, (LOOKS.heavyBelow + LOOKS.lightBelow) / 2) end
local function new(module) return share(module, REGLAZE.glassOnly) end
local function cellsCracked(module) return share(module, REGLAZE.cellsCracked) end
local REGLAZES = {
    { "factory_heavy_cracks_cells_stay_cracked", FACTORY, heavy(FACTORY), 0, cellsCracked(FACTORY) },
    { "factory_light_cracks_back_to_new", FACTORY, light(FACTORY), 0, new(FACTORY) },
    { "factory_sealed_three_times_clears_seals", FACTORY, light(FACTORY), 3, cellsCracked(FACTORY) },
    { "factory_just_below_new_back_to_new", FACTORY, new(FACTORY) - 1, 0, new(FACTORY) },
    { "factory_at_new_refused", FACTORY, new(FACTORY), 0, new(FACTORY), true },
    { "homemade_heavy_cracks_cells_stay_cracked", HOMEMADE, heavy(HOMEMADE), 0, cellsCracked(HOMEMADE) },
    { "homemade_light_cracks_back_to_new", HOMEMADE, light(HOMEMADE), 0, new(HOMEMADE) },
    { "homemade_at_new_refused", HOMEMADE, new(HOMEMADE), 0, new(HOMEMADE), true },
}
for _, entry in ipairs(REGLAZES) do
    local behavior, module, before, repaired, reglazed, refused = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
    local after = refused and before or reglazed
    local repairedAfter = refused and repaired or 0
    craftTest(craftName("RenewableEnergy_ReglazeModule", behavior), {
        recipe = "RenewableEnergy_ReglazeModule",
        from = module,
        prefer = { module },
        setup = function(self)
            T.changeItem(self, T.inputsOf(self, module)[1], { condition = before })
            if repaired > 0 then
                T.setRepaired(self, module, repaired)
            end
        end,
        counts = { [module] = 1, ["Base.GlassPanel"] = refused and 1 or 0 },
        after = function(self)
            T.readCarried(self, { module })
        end,
        validate = function(self)
            local item = T.carriedFirst(self, module)
            if not expect(item ~= nil, "the module is gone") then return end
            expect(item.condition == after, "the module is at " .. item.condition .. ", expected " .. after)
            expect(item.repaired == repairedAfter, "the module reads repaired " .. item.repaired .. "x, expected " .. repairedAfter)
            if refused then
                expect(self.refusal ~= nil, "the game would start the reglaze")
            else
                expect(RenewableEnergy.crackLookOf(module, item.condition) == nil, "a reglazed module shows cracked")
            end
        end,
    })
end

-- Only a module that makes no power comes apart; one that still works is worth more whole.
for _, entry in ipairs({ { nil, 0 }, { "refuses_working_module", 1 } }) do
    local behavior, condition = entry[1], entry[2]
    local refused = condition > 0
    craftTest(craftName("RenewableEnergy_TakeApartShatteredModule", behavior), {
        recipe = "RenewableEnergy_TakeApartShatteredModule",
        from = FACTORY,
        setup = function(self)
            T.changeItem(self, T.inputsOf(self, FACTORY)[1], { condition = condition })
        end,
        counts = refused and { [FACTORY] = 1, ["RenewableEnergy.SolarCells"] = 0 } or { [FACTORY] = 0 },
        validate = function(self)
            if refused then
                expect(self.refusal ~= nil, "the game would take a working module apart")
            end
        end,
    })
end
