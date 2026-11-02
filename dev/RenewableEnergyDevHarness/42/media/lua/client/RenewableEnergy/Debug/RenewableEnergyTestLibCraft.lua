require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Items = require "cf_commonlib/Items"

local T = RenewableEnergyTest

-- `name` in snake case, for test names: "HomesteadPowerMag1" -> "homestead_power_mag1".
local function snake(name)
    return string.lower((name:gsub("(%l)(%u)", "%1_%2"):gsub("(%d)(%u)", "%1_%2")))
end

--- The test name for `recipe` in `system`'s tests: "solar", "RenewableEnergy_TakeApartSolarCellCharger",
--- "returns_x" -> "renewable_energy_solar_craft_take_apart_solar_cell_charger_returns_x".
function T.craftName(system, recipe, behavior)
    return "renewable_energy_" .. system .. "_craft_" .. snake((recipe:gsub("^RenewableEnergy_", "")))
        .. (behavior and "_" .. behavior or "")
end

--- The given inputs (T.craftTest's self.items.inputs) of `fullType`.
function T.inputsOf(self, fullType)
    local found = {}
    for _, item in ipairs(self.items.inputs or {}) do
        if item:getFullType() == fullType then
            table.insert(found, item)
        end
    end
    return found
end

--- Queues knowing the recipes `names` until the test ends, the highest level each skill they
--- require, and a table in reach: a test that crafts them in turn (T.craftFrom) pays the setup of
--- one craft test however many it crafts. Returns the CraftRecipes by name, or nil when a name
--- doesn't resolve, which the test then misses.
function T.readyToCraft(self, names)
    local recipes, levels = {}, {}
    for _, name in ipairs(names) do
        local recipe = T.need(self, getScriptManager():getCraftRecipe(name), "the recipe " .. name)
        if not recipe then return nil end
        recipes[name] = recipe
        for i = 0, recipe:getRequiredSkillCount() - 1 do
            local skill = recipe:getRequiredSkill(i)
            levels[skill:getPerk()] = math.max(levels[skill:getPerk()] or 0, skill:getLevel())
        end
    end
    T.knowRecipes(self, names)
    T.placeWorkTable(T.player())
    for perk, level in pairs(levels) do
        T.setPerk(self, perk, level)
    end
    return recipes
end

-- `items` (T.give items) less one of `fullType`.
local function withoutOne(items, fullType)
    for i, item in ipairs(items) do
        if item.type == fullType then
            item.count = item.count - 1
            if item.count == 0 then
                table.remove(items, i)
            end
            return
        end
    end
end

--- Queues one craft of the CraftRecipe `recipe` (T.readyToCraft's) from `from`: a T.give item
--- ({ type, condition, repaired, uses, modData }) given for it, or the full type of one the
--- character already carries, such as an earlier craft's output. The rest of one craft's inputs
--- come with it (T.recipeInputs, preferring `from`'s type, then `opts.prefer`); `opts.inputs(items)`
--- may change that list before it is given, and `opts.setup(self)` queues what else the craft needs,
--- such as water in a bottle. Afterwards it reads the authority's items of `from`'s type and of
--- `opts.read` (T.readCarried, under `result.label`), and waits until this client's copy of `from`,
--- which the inventory and its tooltip show, matches the authority's. The `from` left is taken away
--- then, so that a later craft can't pick it. Returns `result`, filled in as the queue runs:
--- `item`, the authority's `from` (T.carriedItems' entry, nil once the craft used it up), and
--- `refusal`, why the game wouldn't start the craft (nil if it started), kept out of the test's own
--- refusal so that a row expected to be refused doesn't read as the test's failure.
function T.craftFrom(self, recipe, from, opts)
    opts = opts or {}
    self.crafts = (self.crafts or 0) + 1
    local label = "craft" .. self.crafts
    local result = { label = label }
    local fromType = type(from) == "table" and from.type or from
    local prefer = { fromType }
    for _, other in ipairs(opts.prefer or {}) do
        table.insert(prefer, other)
    end
    local items, unmatched = T.recipeInputs(recipe, prefer)
    if not T.need(self, #unmatched == 0, "an item for " .. table.concat(unmatched, "; ")) then return result end
    withoutOne(items, fromType)
    if opts.inputs then
        opts.inputs(items)
    end
    if type(from) == "table" then
        table.insert(items, 1, from)
    end
    T.give(self, label, items)
    if opts.setup then
        opts.setup(self)
    end
    local what = "this client's " .. fromType .. " to craft " .. recipe:getName() .. " from"
    if type(from) ~= "table" then
        T.waitForCarried(self, fromType, what)
    end
    T.step(function()
        local item
        if type(from) == "table" then
            item = (self.items[label] or {})[1]
        else
            item = T.carried(fromType)
        end
        if not T.need(self, item, what) then return end
        local id, refusal = item:getID(), self.refusal
        self.refusal = nil
        T.startCraft(self, recipe, item)
        T.step(function() result.refusal, self.refusal = self.refusal, refusal end)
        local types = { fromType }
        for _, other in ipairs(opts.read or {}) do
            table.insert(types, other)
        end
        T.readCarried(self, types, nil, label)
        T.step(function()
            local served = T.findIn(T.carriedItems(self, fromType, label), "id", id)
            result.item = served
            if not served then return end
            T.waitFor(self, function()
                local copy = T.player():getInventory():getItemWithIDRecursiv(id)
                return copy ~= nil and copy:getCondition() == served.condition
                    and copy:getHaveBeenRepaired() == served.repaired and math.abs(copy:getCurrentUsesFloat() - served.uses) < 0.001
            end, "this client's copy of the " .. fromType .. " matching the authority's after " .. recipe:getName())
            T.takeItems(self, { id })
        end)
    end)
    return result
end

--- Expects the craft T.craftFrom's `result` to have started, saying why the game refused if not.
function T.expectCrafted(result, what)
    return T.expect(result.refusal == nil, what .. ": the game refused: " .. tostring(result.refusal))
end

-- The definition of `recipe`'s first input that takes `fullType`.
local function inputLineFor(recipe, fullType)
    local item, inputs = getScriptManager():getItem(fullType), recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        if inputs:get(i):containsItem(item) then
            return inputs:get(i):getOriginalLine()
        end
    end
    return nil
end

--- Expects the game to have refused the craft T.craftFrom's `result` started from a `fullType` for
--- want of that item and nothing else: the recipe's OnTest turned it down. A craft refused for the
--- dark, a skill or another input would otherwise pass for the rule under test.
function T.expectRefusedFor(result, recipe, fullType, what)
    return T.expectEqual(what .. ": why the game refused", result.refusal,
        recipe:getName() .. ": missing " .. tostring(inputLineFor(recipe, fullType)))
end

--- Registers the test `name`, which crafts each row of `rows` in turn (T.craftFrom) from a new
--- `fullType` at condition `row.before`, repaired `row.repaired` times and charged to `opts.uses`
--- when given. A row is { recipe name, behaviour, before, repaired, and one of: `after` and
--- `repairedAfter`, what the authority's item comes out at; `refused`, the recipe's OnTest turning
--- the item down (T.expectRefusedFor), which leaves it as it was; `used`, the craft using it up }.
--- `opts.prefer` adds to the inputs preferred, `opts.setup(self)` to every craft's setup, and
--- `opts.validate(row, item, what)` checks more of each item left.
function T.conditionCraftsTest(name, fullType, rows, opts)
    opts = opts or {}
    T.test(name, {
        instant = true,
        run = function(self)
            local names = {}
            for _, row in ipairs(rows) do
                table.insert(names, row[1])
            end
            local recipes = T.readyToCraft(self, names)
            if not recipes then return end
            self.rows = {}
            for i, row in ipairs(rows) do
                self.rows[i] = T.craftFrom(self, recipes[row[1]],
                    { type = fullType, condition = row.before, repaired = row.repaired, uses = opts.uses },
                    { prefer = opts.prefer, setup = opts.setup })
            end
        end,
        validate = function(self)
            for i, row in ipairs(rows) do
                local result, what = self.rows[i], row[1]:gsub("^RenewableEnergy_", "") .. ", " .. row[2]
                if row.refused then
                    T.expectRefusedFor(result, getScriptManager():getCraftRecipe(row[1]), fullType, what)
                else
                    T.expectCrafted(result, what)
                end
                local item = result.item
                if row.used then
                    T.expect(item == nil, what .. ": the " .. fullType .. " is still there")
                elseif T.expect(item ~= nil, what .. ": the " .. fullType .. " is gone") then
                    T.expectEqual(what .. ": its condition", item.condition, row.refused and row.before or row.after)
                    T.expectEqual(what .. ": its repairs", item.repaired, row.refused and row.repaired or row.repairedAfter)
                    if opts.validate then
                        opts.validate(row, item, what)
                    end
                end
            end
        end,
    })
end

--- The condition at `share` of `fullType`'s ConditionMax, such as a Specs.crackLooks threshold.
function T.conditionAt(fullType, share)
    return math.floor(share * Items.conditionMaxOf(fullType) + 0.5)
end

return T
