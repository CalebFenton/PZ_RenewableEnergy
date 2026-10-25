require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/UI/Menu"
require "Moveables/ISMoveableSpriteProps"

-- The solar garden light (Gadgets/SolarGardenLight.lua, its options in UI/Menu.lua): it lights by
-- night on what its cell stored by day, in the colour of its bulb. The authority runs it, so the
-- tests drive it through T.server and check this client's copies.

local T = RenewableEnergyTest
local test, expect, expectNear = T.test, T.expect, T.expectNear
local Sprites, Specs, SolarGardenLight = RenewableEnergy.Sprites, RenewableEnergy.Specs, RenewableEnergy.SolarGardenLight

local NOON, MIDNIGHT = 12, 0

-- A garden light holding `charge` Wh and `bulb` (default: the plain bulb) that the character
-- places on a free outdoor square; see T.placeAsPlayer.
local function placeGardenLight(self, charge, bulb)
    local square = T.square(self, { bare = true }, "a free outdoor square")
    return square and T.placeAsPlayer(self, square, SolarGardenLight.ITEM, Sprites.gardenLight.off,
        { [SolarGardenLight.CHARGE_KEY] = charge, [SolarGardenLight.BULB_KEY] = bulb })
end

-- The lamp this client draws on `square`, or nil.
local function lampAt(square)
    return getCell():getLightSourceAt(square:getX(), square:getY(), square:getZ())
end

-- Whether this client draws a lamp on `square`.
local function lampOn(square)
    return lampAt(square) ~= nil
end

-- The colour the lamp shows: the native lighting doubles a lamp's colour and clips it at 1.
local function shownColour(lamp)
    return { r = math.min(1, lamp:getR() * 2), g = math.min(1, lamp:getG() * 2), b = math.min(1, lamp:getB() * 2) }
end

-- The colour of the bulb `fullType`, from its script.
local function bulbColour(fullType)
    local script = getScriptManager():FindItem(fullType)
    return { r = script:getColorRed(), g = script:getColorGreen(), b = script:getColorBlue() }
end

local function sameColour(a, b)
    return a ~= nil and b ~= nil and math.abs(a.r - b.r) < 0.01 and math.abs(a.g - b.g) < 0.01 and math.abs(a.b - b.b) < 0.01
end

local function describeColour(colour)
    return colour and string.format("(%.2f, %.2f, %.2f)", colour.r, colour.g, colour.b) or "none"
end

-- Whether this client draws a lamp on `square` that shines the colour of the bulb `fullType`.
local function lampShines(square, fullType)
    local lamp = lampAt(square)
    return lamp ~= nil and sameColour(shownColour(lamp), bulbColour(fullType))
end

-- Queues running the light on the server through the gadget pass for `hours` of the clock, from
-- `charge` Wh if given, and a wait until this client's tile and lamp match the server's answer.
local function runLight(self, light, charge, hours)
    T.server(self, "gardenLightUpdate", T.at(light, { charge = charge, hours = hours }))
    T.waitFor(self, function()
        local reply = self.server.gardenLightUpdate
        return light.object:getTextureName() == reply.sprite and lampOn(light.square) == reply.lit
    end, "this client's garden light showing what the server's does")
end

-- The game minute on this client's clock.
local function gameMinute()
    return math.floor(getGameTime():getWorldAgeHours() * 60)
end

-- Queues moving the clock to the start of its minute, left in self.minute. A multiplayer client
-- redraws lamps every game minute, so a change within the minute came from the server's word.
local function startOfMinute(self)
    T.step(function()
        T.setTime(self, (math.floor(getGameTime():getTimeOfDay() * 60) + 0.05) / 60)
        T.step(function() self.minute = gameMinute() end)
    end)
end

-- At night a light stays lit while its battery holds any charge: a little more than the night
-- draws leaves it lit, exactly that much puts it out. By day the cell charges it, never past full.
local NIGHT_HOURS = 0.5
local NIGHT_WH = Specs.gardenLight.nightWatts * NIGHT_HOURS
-- A full battery: lasts the night hours the tests run.
local LIT_WH = Specs.gardenLight.wh
local GARDEN_LIGHT_HOURS = {
    { what = "with a little more than the night draws", hour = MIDNIGHT, charge = NIGHT_WH + 0.01, hours = NIGHT_HOURS,
        lit = true, after = 0.01 },
    { what = "with just what the night draws", hour = MIDNIGHT, charge = NIGHT_WH, hours = NIGHT_HOURS, lit = false, after = 0 },
    { what = "empty at noon", hour = NOON, charge = 0, hours = 1, lit = false, low = 0, high = Specs.gardenLight.wh },
    { what = "nearly full at noon", hour = NOON, charge = Specs.gardenLight.wh - 0.01, hours = 1, lit = false,
        after = Specs.gardenLight.wh },
}

test("renewable_energy_gadgets_garden_light_update", {
    instant = true,
    run = function(self)
        self.rows = {}
        local light = placeGardenLight(self, GARDEN_LIGHT_HOURS[1].charge)
        if not light then return end
        for _, row in ipairs(GARDEN_LIGHT_HOURS) do
            T.step(function() T.setTime(self, row.hour) end)
            runLight(self, light, row.charge, row.hours)
            T.step(function()
                local reply = self.server.gardenLightUpdate
                table.insert(self.rows, { row = row, lit = reply.lit, sprite = reply.sprite, charge = reply.charge,
                    copySprite = light.object:getTextureName(), lamp = lampOn(light.square) })
            end)
        end
    end,
    validate = function(self)
        for _, r in ipairs(self.rows) do
            local row = r.row
            local sprite = row.lit and Sprites.gardenLight.lit or Sprites.gardenLight.off
            expect(r.lit == row.lit and r.sprite == sprite and r.copySprite == sprite and r.lamp == row.lit,
                string.format("a light %s: lit %s, sprite %s, this client's sprite %s, lamp %s; expected lit %s", row.what,
                    tostring(r.lit), r.sprite, r.copySprite, tostring(r.lamp), tostring(row.lit)))
            if row.after then
                expectNear("charge of a light " .. row.what, r.charge, row.after)
            else
                expect(r.charge > row.low and r.charge <= row.high, "a light " .. row.what .. " ended at " .. r.charge .. " Wh")
            end
        end
    end,
})

-- Light bulbs ------------------------------------------------------------------------------------

local RED, GREEN = "Base.LightBulbRed", "Base.LightBulbGreen"

-- This client's right-click menu of the garden light `light` (a handle): the context menu, to hide
-- once read, its Add Light Bulb submenu or nil, and its Remove Light Bulb option or nil.
local function bulbMenu(light)
    local context = T.newContext()
    local menu = RenewableEnergy.Menu.addGardenLightOptions(0, context, light.object)
    return context, T.subMenu(context, menu:getOptionFromName(getText("ContextMenu_AddLightbulb"))),
        menu:getOptionFromName(getText("ContextMenu_RemoveLightbulb"))
end

-- Queues choosing, in this client's right-click menu of the garden light `light` (a handle),
-- Remove Light Bulb or, given `bulbType`, that bulb under Add Light Bulb, as a click does: the
-- option walks the character over and queues the job.
local function chooseBulbOption(self, light, bulbType)
    T.step(function()
        local context, add, remove = bulbMenu(light)
        local option = remove
        if bulbType then
            option = add and add:getOptionFromName(getItemName(bulbType))
        end
        context:hideAndChildren()
        if not T.need(self, option and not option.notAvailable and option,
            "the garden light's " .. (bulbType and "Add Light Bulb " .. bulbType or "Remove Light Bulb") .. " option") then
            return
        end
        T.standNextTo(light.square)
        T.choose(option)
    end)
end

-- Queues a wait until this client's copy of the light shows the unlit tile and draws no lamp.
local function waitForDark(self, light)
    T.waitFor(self, function()
        return light.object:getTextureName() == Sprites.gardenLight.off and not lampOn(light.square)
    end, "this client's garden light dark")
end

-- Taking the bulb out of a lit light puts its lamp out within the minute and gives the bulb back;
-- the light then stays dark at night without draining, and offers to take a bulb.
test("renewable_energy_gadgets_garden_light_remove_bulb", {
    hour = MIDNIGHT,
    instant = true,
    run = function(self)
        local light = placeGardenLight(self, LIT_WH)
        if not light then return end
        self.light = light
        runLight(self, light, LIT_WH, NIGHT_HOURS)
        T.step(function() self.litBefore = lampOn(light.square) end)
        startOfMinute(self)
        chooseBulbOption(self, light, nil)
        waitForDark(self, light)
        T.step(function() self.darkMinute = gameMinute() end)
        T.count(self, "removed", { SolarGardenLight.PLAIN_BULB })
        runLight(self, light, LIT_WH, 1)
        T.step(function()
            self.night = self.server.gardenLightUpdate
            self.copyDarkAtNight = light.object:getTextureName() == Sprites.gardenLight.off and not lampOn(light.square)
        end)
    end,
    validate = function(self)
        if not expect(self.litBefore, "the light never lit") then return end
        expect(self.darkMinute == self.minute, "this client's lamp went out only at a later game minute")
        expect(self.counts.removed[SolarGardenLight.PLAIN_BULB] == 1, "taking the bulb out gave "
            .. tostring(self.counts.removed[SolarGardenLight.PLAIN_BULB]) .. " light bulbs, expected 1")
        expect(self.night and not self.night.lit and self.copyDarkAtNight, "the light without a bulb lit at night")
        expectNear("charge of a light without a bulb after an hour of night", self.night and self.night.charge, LIT_WH)
        local context, add, remove = bulbMenu(self.light)
        local plain = add and add:getOptionFromName(getItemName(SolarGardenLight.PLAIN_BULB))
        expect(plain ~= nil and not plain.notAvailable, "the light without a bulb doesn't offer the carried bulb under Add Light Bulb")
        expect(remove == nil, "the light without a bulb offers Remove Light Bulb")
        context:hideAndChildren()
    end,
})

-- The plain bulb shines warm, and swapping it for a red one through the menu takes the red bulb
-- and shines red.
test("renewable_energy_gadgets_garden_light_coloured_bulb", {
    hour = MIDNIGHT,
    instant = true,
    run = function(self)
        local light = placeGardenLight(self, LIT_WH)
        if not light then return end
        runLight(self, light, LIT_WH, NIGHT_HOURS)
        T.step(function()
            local lamp = lampAt(light.square)
            self.plain = lamp and shownColour(lamp)
        end)
        chooseBulbOption(self, light, nil)
        waitForDark(self, light)
        T.give(self, "red", { { type = RED } })
        chooseBulbOption(self, light, RED)
        T.waitFor(self, function() return lampShines(light.square, RED) end, "this client's lamp shining red")
        T.count(self, "added", { RED })
        T.step(function() self.copyLit = light.object:getTextureName() == Sprites.gardenLight.lit end)
    end,
    validate = function(self)
        local plain = self.plain
        if not expect(plain ~= nil, "the light never lit with its plain bulb") then return end
        expect(plain.b < plain.r and not sameColour(plain, { r = 1, g = 1, b = 1 }),
            "the plain bulb's lamp shines " .. describeColour(plain) .. ", not a warm white")
        expect(self.copyLit, "with a red bulb this client's light shows the unlit tile")
        expect(self.counts.added[RED] == 0, "the red bulb is still in the inventory")
    end,
})

-- A bulb swapped while the light stays lit still recolours this client's lamp.
test("renewable_energy_gadgets_garden_light_bulb_swap_recolours_lamp", {
    hour = MIDNIGHT,
    instant = true,
    run = function(self)
        local light = placeGardenLight(self, LIT_WH)
        if not light then return end
        runLight(self, light, LIT_WH, NIGHT_HOURS)
        T.step(function() self.litBefore = lampOn(light.square) end)
        T.server(self, "gardenLightSwapBulb", T.at(light, { bulb = GREEN }))
        T.waitFor(self, function() return lampShines(light.square, GREEN) end, "this client's lamp shining green after the swap")
    end,
    validate = function(self)
        if not expect(self.litBefore, "the light never lit") then return end
        local swap = self.server.gardenLightSwapBulb
        expect(swap.lit and swap.bulb == GREEN, "after the swap the server's light is lit " .. tostring(swap.lit)
            .. " with " .. tostring(swap.bulb))
    end,
})

-- Queues placing the carried garden light back on `light`'s square with the moveables action and
-- a wait until this client has it.
local function placeCarriedLight(self, light)
    T.step(function()
        local p = T.player()
        local item = T.need(self, T.carried(SolarGardenLight.ITEM), "the carried garden light")
        if not item then return end
        -- The tile it was picked up as, lit or not, as the moveables cursor places it.
        local sprite = item:getWorldSprite()
        local here = p:getCurrentSquare()
        PZHarness.Fixtures.teleportToMiddle(p, here:getX(), here:getY(), here:getZ())
        local props = ISMoveableSpriteProps.new(sprite)
        if not T.need(self, props:walkToAndEquip(p, light.square, "place", sprite), "a way to place the carried garden light") then
            return
        end
        ISTimedActionQueue.add(ISMoveablesAction:new(p, light.square, "place", sprite, nil,
            props:getFaceDirectionFromSpriteName(sprite), item, nil))
        T.waitFor(self, function() return T.objectWithSprite(light.square, sprite) ~= nil end,
            "this client's copy of the placed garden light")
        T.server(self, "PZHarness.trackPlaced", T.at(light, { sprite = sprite }))
        T.step(function() light.object = T.objectWithSprite(light.square, sprite) end)
    end)
end

-- A picked-up light takes its lamp away with it, keeps its bulb and shines its colour when placed
-- again.
test("renewable_energy_gadgets_garden_light_pick_up_keeps_bulb", {
    hour = MIDNIGHT,
    instant = true,
    run = function(self)
        local light = placeGardenLight(self, LIT_WH, GREEN)
        if not light then return end
        runLight(self, light, LIT_WH, NIGHT_HOURS)
        T.waitFor(self, function() return lampShines(light.square, GREEN) end, "this client's lamp shining green")
        T.pickUpAsPlayer(self, light, Sprites.gardenLight.lit)
        T.waitFor(self, function() return not lampOn(light.square) end, "this client's lamp going with the light")
        T.readCarried(self, { SolarGardenLight.ITEM })
        T.step(function()
            local item = T.carriedFirst(self, SolarGardenLight.ITEM)
            self.carriedBulb = item and item.modData[SolarGardenLight.BULB_KEY]
        end)
        placeCarriedLight(self, light)
        runLight(self, light, nil, NIGHT_HOURS)
        T.waitFor(self, function() return lampShines(light.square, GREEN) end, "this client's lamp shining green placed again")
    end,
    validate = function(self)
        expect(self.carriedBulb == GREEN, "the picked-up light holds " .. tostring(self.carriedBulb) .. ", expected " .. GREEN)
    end,
})

-- Taking a light apart gives back its bulb, whatever its colour, the plain one a light holds from
-- new (no bulb key), and none from a light without one.
for _, entry in ipairs({ { "returns_bulb", RED }, { "returns_plain_bulb", nil }, { "without_bulb", SolarGardenLight.NO_BULB } }) do
    local behavior, bulb = entry[1], entry[2]
    T.craftTest("renewable_energy_gadgets_garden_light_take_apart_" .. behavior, {
        recipe = "RenewableEnergy_TakeApartSolarGardenLight",
        from = SolarGardenLight.ITEM,
        setup = function(self)
            for _, item in ipairs(bulb and self.items.inputs or {}) do
                if item:getFullType() == SolarGardenLight.ITEM then
                    T.changeItem(self, item, { modData = { [SolarGardenLight.BULB_KEY] = bulb } })
                end
            end
        end,
        counts = { [SolarGardenLight.ITEM] = 0, [RED] = bulb == RED and 1 or 0,
            [SolarGardenLight.PLAIN_BULB] = bulb == nil and 1 or 0 },
    })
end

-- A garden light goes on the ground outdoors, where the sun reaches it.
test("renewable_energy_gadgets_garden_light_refused_indoors", {
    run = function(self)
        local indoor = T.square(self, { indoors = true }, "a free indoor square")
        local outdoor = T.square(self, { bare = true }, "a free outdoor square")
        if not (indoor and outdoor) then return end
        local props = ISMoveableSpriteProps.new(Sprites.gardenLight.off)
        local item = instanceItem(SolarGardenLight.ITEM)
        self.indoors = props:canPlaceMoveable(T.player(), indoor, item)
        self.outdoors = props:canPlaceMoveable(T.player(), outdoor, item)
    end,
    validate = function(self)
        expect(not self.indoors, "a garden light can be placed indoors")
        expect(self.outdoors, "a garden light can't be placed outdoors")
    end,
})
