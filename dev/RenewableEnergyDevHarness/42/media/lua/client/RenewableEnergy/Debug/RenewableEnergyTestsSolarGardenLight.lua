require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Specs = require "RenewableEnergy/Specs"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local GardenLightMenu = require "RenewableEnergy/UI/GardenLightMenu"
local Sprites = require "RenewableEnergy/Sprites"
local Sun = require "RenewableEnergy/Sun"

-- The solar garden light (Gadgets/SolarGardenLight.lua, its options in UI/GardenLightMenu.lua): it lights by
-- night on what its cell stored by day, in the colour of its bulb. The authority runs it, so the
-- tests drive it through T.server and check this client's copies.

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual = T.test, T.expect, T.expectNear, T.expectEqual

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
-- `charge` Wh if given, and a wait until this client's tile and lamp match the server's answer,
-- read under `label` when given.
local function runLight(self, light, charge, hours, label)
    T.read(self, "gardenLightUpdate", T.at(light, { kind = "light", charge = charge, hours = hours }), label)
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
-- draws leaves it lit, exactly that much puts it out. By day the cell charges it at its rating in
-- the sky the pass ran under (`sunlit`), never past full. The hour after the game's dusk and the
-- hour before its dawn are after sunset but not yet dark, as the game draws its sky: a full light
-- stays off there and keeps its charge. A row's `hour` and `hours` may be worked out from today's
-- dusk and dawn (ErosionSeason) as the test runs, `hours` from the row's hour.
local NIGHT_HOURS = 0.5
local SPEC = SolarGardenLight.SPEC
local NIGHT_WH = SPEC.nightWatts * NIGHT_HOURS
-- A full battery: lasts the night hours the tests run.
local LIT_WH = SPEC.wh
local function season()
    return getClimateManager():getSeason()
end
local GARDEN_LIGHT_HOURS = {
    { what = "with a little more than the night draws", hour = MIDNIGHT, charge = NIGHT_WH + 0.01, hours = NIGHT_HOURS,
        lit = true, after = 0.01 },
    { what = "with just what the night draws", hour = MIDNIGHT, charge = NIGHT_WH, hours = NIGHT_HOURS, lit = false, after = 0 },
    { what = "empty at noon", hour = NOON, charge = 0, hours = 1, lit = false, sunlit = true },
    { what = "nearly full at noon", hour = NOON, charge = SPEC.wh - 0.01, hours = 1, lit = false,
        after = SPEC.wh },
    -- The pass runs from the whole hour, so it starts and ends within the hour after dusk.
    { what = "full just after dusk", hour = function() return math.ceil(season():getDusk()) end, charge = LIT_WH,
        hours = 0.25, lit = false, after = LIT_WH },
    { what = "full just before dawn", hour = function() return math.ceil(season():getDawn()) - 1 end, charge = LIT_WH,
        hours = function(hour) return (season():getDawn() - hour) / 2 end, lit = false, after = LIT_WH },
}

-- `value`, or what it works out to from `...` if it is a function.
local function resolve(value, ...)
    if type(value) == "function" then
        return value(...)
    end
    return value
end

test("renewable_energy_gadgets_garden_light_update", {
    instant = true,
    run = function(self)
        self.copies = {}
        local light = placeGardenLight(self, GARDEN_LIGHT_HOURS[1].charge)
        if not light then return end
        for _, row in ipairs(GARDEN_LIGHT_HOURS) do
            local hour = resolve(row.hour)
            T.step(function() T.setTime(self, hour) end)
            -- The photocell reads the server's sky, which follows its clock at a later update.
            T.serverUntil(self, "skyFollowsClock", {}, function(reply) return reply.follows end)
            runLight(self, light, row.charge, resolve(row.hours, hour), row.what)
            T.step(function()
                self.copies[row.what] = { sprite = light.object:getTextureName(), lamp = lampOn(light.square) }
            end)
        end
    end,
    validate = function(self)
        for _, row in ipairs(GARDEN_LIGHT_HOURS) do
            local reply, copy = self.reads[row.what], self.copies[row.what]
            local sprite = row.lit and Sprites.gardenLight.lit or Sprites.gardenLight.off
            expectEqual("whether the server lights a light " .. row.what, reply.lit, row.lit)
            expectEqual("the server's tile of a light " .. row.what, reply.sprite, sprite)
            expectEqual("this client's tile of a light " .. row.what, copy.sprite, sprite)
            expectEqual("whether this client draws the lamp of a light " .. row.what, copy.lamp, row.lit)
            local after = row.after
            if row.sunlit then
                expect(reply.flat > 0, "no sun for a light " .. row.what)
                after = Sun.wattsFrom(SPEC.watts, reply.flat, 0) * row.hours
            end
            expectNear("charge of a light " .. row.what, reply.charge, after)
        end
    end,
})

-- Light bulbs ------------------------------------------------------------------------------------

local RED, GREEN = "Base.LightBulbRed", "Base.LightBulbGreen"

-- This client's right-click menu of the garden light `light` (a handle): the context menu, to hide
-- once read, its Add Light Bulb submenu or nil, and its Remove Light Bulb option or nil.
local function bulbMenu(light)
    local context = T.newContext()
    local menu = GardenLightMenu.addOptions(0, context, light.object)
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
        if not T.need(self, T.offered(option) and option,
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

-- The plain bulb shines warm. Taking it out of the lit light puts its lamp out within the minute
-- and gives the bulb back; the light then stays dark at night without draining, and offers only
-- to take a bulb. Putting a red one in through the menu takes it and shines red.
test("renewable_energy_gadgets_garden_light_bulb_swap", {
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
        startOfMinute(self)
        chooseBulbOption(self, light, nil)
        waitForDark(self, light)
        T.step(function() self.darkMinute = gameMinute() end)
        T.count(self, "removed", { SolarGardenLight.PLAIN_BULB })
        runLight(self, light, LIT_WH, 1, "night")
        T.waitForCarried(self, SolarGardenLight.PLAIN_BULB, "this client's copy of the bulb taken out")
        T.step(function()
            self.copyDarkAtNight = light.object:getTextureName() == Sprites.gardenLight.off and not lampOn(light.square)
            local context, add, remove = bulbMenu(light)
            local plain = add and add:getOptionFromName(getItemName(SolarGardenLight.PLAIN_BULB))
            self.offersPlain, self.offersRemove = T.offered(plain), remove ~= nil
            context:hideAndChildren()
        end)
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
        expect(self.darkMinute == self.minute, "this client's lamp went out only at a later game minute")
        expectEqual("light bulbs taking the bulb out gave", self.counts.removed[SolarGardenLight.PLAIN_BULB], 1)
        expect(not self.reads.night.lit and self.copyDarkAtNight, "the light without a bulb lit at night")
        expectNear("charge of a light without a bulb after an hour of night", self.reads.night.charge, LIT_WH)
        expect(self.offersPlain, "the light without a bulb doesn't offer the carried bulb under Add Light Bulb")
        expect(not self.offersRemove, "the light without a bulb offers Remove Light Bulb")
        expect(self.copyLit, "with a red bulb this client's light shows the unlit tile")
        expectEqual("red bulbs left in the inventory", self.counts.added[RED], 0)
    end,
})

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
        -- As the lit tile it was picked up as, which the moveables cursor places it as.
        local placed = T.placeAsPlayer(self, light.square, SolarGardenLight.ITEM, Sprites.gardenLight.lit, nil, true)
        runLight(self, placed, nil, NIGHT_HOURS)
        T.waitFor(self, function() return lampShines(light.square, GREEN) end, "this client's lamp shining green placed again")
    end,
    validate = function(self)
        expectEqual("the picked-up light's bulb", self.carriedBulb, GREEN)
    end,
})

-- Taking a light apart gives back the bulb in it, not the plain one it came with, and none from a
-- light without one. A light without the bulb key holds the plain bulb; the other tests' lights
-- show that.
for _, entry in ipairs({ { "returns_its_bulb", RED }, { "without_bulb", SolarGardenLight.NO_BULB } }) do
    local behavior, bulb = entry[1], entry[2]
    T.craftTest("renewable_energy_gadgets_garden_light_take_apart_" .. behavior, {
        recipe = "RenewableEnergy_TakeApartSolarGardenLight",
        from = SolarGardenLight.ITEM,
        setup = function(self)
            for _, item in ipairs(self.items.inputs) do
                if item:getFullType() == SolarGardenLight.ITEM then
                    T.changeItem(self, item, { modData = { [SolarGardenLight.BULB_KEY] = bulb } })
                end
            end
        end,
        counts = { [SolarGardenLight.ITEM] = 0, [RED] = bulb == RED and 1 or 0, [SolarGardenLight.PLAIN_BULB] = 0 },
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
