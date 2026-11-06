require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Specs = require "RenewableEnergy/Specs"
local Format = require "RenewableEnergy/UI/Format"
local Items = require "cf_commonlib/Items"

-- Item and recipe data as the game loaded it, for what the static check can't see. See
-- RenewableEnergyTestLib.lua for the runner and the helpers.

local T = RenewableEnergyTest
local test, expect, expectEqual = T.test, T.expect, T.expectEqual

-- Every item a recipe of the mod's accepts, vanilla's included, has an icon: the crafting window's
-- "Possible Items" throws on one without (ISCraftInventoryPanel.populate). Each fluid input fits a
-- fluid: an unknown fluid name fails only as the game resolves the scripts
-- (InputScript.OnPostWorldDictionaryInit). The static check covers the rest of a recipe's shape.
test("renewable_energy_items_recipes_load", {
    validate = function()
        local names = T.recipeNames()
        expect(#names > 0, "no RenewableEnergy_ recipe loaded")
        for _, name in ipairs(names) do
            local recipe = getScriptManager():getCraftRecipe(name)
            local inputs = recipe and recipe:getInputs()
            for i = 0, (inputs and inputs:size() or 0) - 1 do
                local input = inputs:get(i)
                if input:getResourceType() == ResourceType.Item then
                    local possible = input:getPossibleInputItems()
                    for j = 0, possible:size() - 1 do
                        local item = possible:get(j)
                        expect(item:getNormalTexture() ~= nil, name .. " accepts " .. item:getFullName() .. ", which has no icon")
                    end
                elseif input:getResourceType() == ResourceType.Fluid then
                    expect(input:getPossibleInputFluids():size() > 0, name .. ": no fluid fits " .. input:getOriginalLine())
                end
            end
        end
    end,
})

-- Shows a tooltip of `item` and returns it, with what its strip shows: how many texts it drew, and
-- each text mapped to the next it drew, a label to its value. Vanilla draws the tooltip's own lines
-- in Java, so only the mod's strip draws text from Lua.
local function showTooltip(self, item)
    local tooltip = ISToolTipInv:new(item)
    tooltip:initialise()
    local strip, last = { count = 0, values = {} }, nil
    tooltip.drawText = function(panel, text, ...)
        strip.count = strip.count + 1
        if last then strip.values[last] = text end
        last = text
        return ISToolTipInv.drawText(panel, text, ...)
    end
    tooltip:setVisible(true)
    tooltip:addToUIManager()
    T.defer(self, function() tooltip:removeFromUIManager() end)
    return tooltip, strip
end

-- A battery's tooltip strip shows what it holds now that wear took its share: a worn battery holds
-- less than its rating, which decides which battery goes into a bank. The inventory tooltip also
-- shows a fluid container, as the Transfer Fluids window's bar does (ISFluidBar): the strip draws
-- nothing for it, without the item methods it lacks.
local WORN, CHARGE = 0.5, 0.5
test("renewable_energy_items_tooltip_strip", {
    run = function(self)
        local battery = instanceItem(T.CAR_BATTERY)
        battery:setCondition(Items.conditionMaxOf(T.CAR_BATTERY) * WORN)
        battery:setCurrentUsesFloat(CHARGE)
        self.charge = battery:getCurrentUsesFloat()
        local batteryTip, fluidTip
        batteryTip, self.battery = showTooltip(self, battery)
        fluidTip, self.fluid = showTooltip(self, instanceItem("Base.WaterBottle"):getFluidContainer())
        -- Vanilla's render sizes a tooltip, and the mod's strip is drawn in the same call.
        T.waitFor(self, function() return batteryTip:getHeight() > 0 and fluidTip:getHeight() > 0 end,
            "both tooltips drawn")
    end,
    validate = function(self)
        -- 600 Wh × 0.5 of its condition = 300 Wh, holding 0.5 of that.
        local capacityWh = Specs.batteries[T.CAR_BATTERY].wh * WORN
        local values = self.battery.values
        expectEqual("the worn battery's capacity", values[getText("IGUI_RenewableEnergy_Capacity") .. ":"],
            Format.wattHours(capacityWh))
        expectEqual("the worn battery's stored energy", values[getText("IGUI_RenewableEnergy_Stored") .. ":"],
            Format.wattHours(capacityWh * self.charge))
        expectEqual("texts the fluid container's tooltip strip draws", self.fluid.count, 0)
    end,
})
