require "Tests/TimedActionsTests"
require "RenewableEnergy/Debug/RenewableEnergyDebug"

-- Helpers for the RenewableEnergyTests*.lua files, which register tests with the vanilla timed action test
-- runner: Debug menu > Dev > Unit Tests > Timed Actions, in debug mode. The runner calls run(),
-- waits for the action queue to empty, then calls validate(). Before each test it empties the
-- inventory and clears worn items, but it keeps perks, known recipes, modData, world objects and
-- sandbox options, so test() sets those. Each result is also printed to console.txt as
-- "RETest PASS <name>" or "RETest FAIL <name>: <reasons>".
--
-- A Lua error stops the game in the debug-mode error handler, pcall or not, and the runner never
-- finishes, so tests check for nil before they index anything.
RenewableEnergyTest = {}

function RenewableEnergyTest.player()
    return getSpecificPlayer(0)
end

-- Unmet expectations of the test being validated.
local failures = {}

function RenewableEnergyTest.expect(condition, message)
    if not condition then
        table.insert(failures, message)
    end
    return condition
end

function RenewableEnergyTest.expectNear(label, actual, expected, tolerance)
    return RenewableEnergyTest.expect(type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 0.0001),
        label .. " is " .. tostring(actual) .. ", expected " .. expected)
end

function RenewableEnergyTest.expectCount(fullType, expected)
    local actual = RenewableEnergyTest.player():getInventory():getCountTypeRecurse(fullType)
    return RenewableEnergyTest.expect(actual == expected, actual .. " " .. fullType .. " in the inventory, expected " .. expected)
end

-- Registers a test. Before run(), the `spec.sandbox` options (SandboxVars.RenewableEnergy) take effect;
-- validate() restores them, then runs spec.validate.
function RenewableEnergyTest.test(name, spec)
    TimedActionTests.getTests()[name] = {
        run = function(self)
            self.savedSandbox = {}
            for option, value in pairs(spec.sandbox or {}) do
                self.savedSandbox[option] = SandboxVars.RenewableEnergy[option]
                SandboxVars.RenewableEnergy[option] = value
            end
            if spec.run then
                spec.run(self)
            end
        end,
        validate = function(self)
            failures = {}
            if spec.validate then
                spec.validate(self)
            end
            for option, value in pairs(self.savedSandbox) do
                SandboxVars.RenewableEnergy[option] = value
            end
            if spec.cleanup then
                spec.cleanup(self)
            end
            if #failures > 0 then
                print("RETest FAIL " .. name .. ": " .. table.concat(failures, "; "))
                return false
            end
            print("RETest PASS " .. name)
            return true
        end,
    }
end

-- Why the crafting window or the right-click menu would refuse to start this craft, or nil if
-- it would start it. Both refuse without saying why.
function RenewableEnergyTest.craftRefusal(recipe, selectedItem)
    local p = RenewableEnergyTest.player()
    local logic = HandcraftLogic.new(p, nil, nil)
    logic:setIsoObject(logic:findCraftSurface(p, 2))
    logic:setContainers(ISInventoryPaneContextMenu.getContainers(p))
    logic:setRecipeFromContextClick(recipe, selectedItem)
    if logic:canPerformCurrentRecipe() then
        return nil
    elseif not p:isRecipeActuallyKnown(recipe) then
        return "recipe not known"
    elseif not recipe:characterHasRequiredSkills(p) then
        return "skills too low"
    elseif recipe:isAnySurfaceCraft() and not logic:isCharacterInRangeOfWorkbench() then
        return "no table in reach"
    elseif p:tooDarkToRead() then
        return "too dark"
    end
    local missing = {}
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local data = logic:getRecipeData():getDataForInputScript(inputs:get(i))
        if data and not data:isInputItemsSatisfied() then
            table.insert(missing, inputs:get(i):getOriginalLine())
        end
    end
    return "missing " .. table.concat(missing, "; ")
end

-- Registers a test that crafts `spec.recipe` the way the right-click menu does, from the first
-- `spec.from` item. The character is an electrician who knows every recipe and stands by a
-- table, carrying exactly the inputs of one craft (RenewableEnergyDebug.addRecipeInputs with `spec.prefer`)
-- and whatever `spec.setup(self)` adds. validate() expects the inventory counts in
-- `spec.counts`, then runs `spec.validate(self)`. A failing test also reports why the game
-- refused the craft, since the menu refuses without a word.
function RenewableEnergyTest.craftTest(name, spec)
    RenewableEnergyTest.test(name, {
        sandbox = spec.sandbox,
        run = function(self)
            local p = RenewableEnergyTest.player()
            RenewableEnergyDebug.setupPlayer(p)
            local recipe = getScriptManager():getCraftRecipe(spec.recipe)
            if not recipe then
                self.refusal = "no recipe " .. spec.recipe
                return
            end
            local unmatched = RenewableEnergyDebug.addRecipeInputs(p, recipe, spec.prefer)
            if #unmatched > 0 then
                self.refusal = "no item fits " .. table.concat(unmatched, "; ")
                return
            end
            if spec.setup then
                spec.setup(self)
            end
            local from = p:getInventory():getFirstTypeRecurse(spec.from)
            if not from then
                self.refusal = "no " .. spec.from
                return
            end
            self.refusal = RenewableEnergyTest.craftRefusal(recipe, from)
            ISInventoryPaneContextMenu.OnNewCraft(from, recipe, p:getPlayerNum(), false)
        end,
        validate = function(self)
            local before = #failures
            for fullType, count in pairs(spec.counts or {}) do
                RenewableEnergyTest.expectCount(fullType, count)
            end
            if spec.validate then
                spec.validate(self)
            end
            if #failures > before and self.refusal then
                table.insert(failures, "the game refused the craft: " .. self.refusal)
            end
        end,
    })
end
