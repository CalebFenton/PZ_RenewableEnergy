require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "Moveables/ISMoveableSpriteProps"

-- Tests of the art: the tiles in renewable_energy.tiles and the pack, as Sprites.lua names them,
-- and the items' icons and ground models. See RenewableEnergyTestLib.lua for how the runner works.

local test, expect = RenewableEnergyTest.test, RenewableEnergyTest.expect

local Sprites = RenewableEnergy.Sprites
local Specs = RenewableEnergy.Specs

local MATERIALS = { wood = "Wood", metal = "Metal" }

-- Placed tile -> the item picking it up gives, what Sprites.kindOf reports, and whether it holds
-- items.
local PLACED = {
    { sprite = Sprites.flat, item = "RenewableEnergy.SolarFlat", kind = "flat" },
    { sprite = Sprites.failsafe, item = "RenewableEnergy.SolarFailsafe", kind = "failsafe" },
    { sprite = Sprites.cellCharger, item = "RenewableEnergy.SolarCellCharger", kind = "cellCharger", container = true },
    { sprite = Sprites.gardenLight.off, item = "RenewableEnergy.SolarGardenLight", kind = "gardenLight" },
    { sprite = Sprites.gardenLight.lit, item = "RenewableEnergy.SolarGardenLight", kind = "gardenLight" },
}
for material, suffix in pairs(MATERIALS) do
    for _, mount in ipairs({ "wall", "rack" }) do
        local item = "RenewableEnergy.Solar" .. (mount == "wall" and "Wall" or "Rack") .. suffix
        for facing, sprite in pairs(Sprites[mount][material]) do
            table.insert(PLACED, { sprite = sprite, item = item, kind = mount, facing = facing, material = material })
        end
    end
    for _, tier in ipairs({ "Box", "Rack", "Bank" }) do
        local field = "battery" .. tier .. suffix
        table.insert(PLACED, { sprite = Sprites[field], item = "RenewableEnergy.Battery" .. tier .. suffix, kind = field,
            material = material, container = true })
    end
end

local function overlays()
    local all = { Sprites.crateOverlays.full, Sprites.crateOverlays.closed, Sprites.snow.flat }
    local function add(list)
        for _, name in pairs(list) do
            table.insert(all, name)
        end
    end
    for _, facings in pairs(Sprites.snow.rack) do
        add(facings)
    end
    for _, fill in pairs(Sprites.bankFill) do
        add(fill.batteries)
        add(fill.meter)
    end
    return all
end

local function properties(spriteName)
    local sprite = getSprite(spriteName)
    return sprite and sprite:getProperties()
end

test("renewable_energy_art_tiles_have_pictures", {
    validate = function()
        local names = { Sprites.crate }
        for _, placed in ipairs(PLACED) do
            table.insert(names, placed.sprite)
        end
        for _, name in ipairs(overlays()) do
            table.insert(names, name)
        end
        for _, name in ipairs(names) do
            expect(getSprite(name) ~= nil, name .. " is not a tile in renewable_energy.tiles")
            expect(getTexture(name) ~= nil, name .. " has no picture in the pack")
        end
    end,
})

test("renewable_energy_art_placed_tiles_give_their_item", {
    validate = function()
        for _, placed in ipairs(PLACED) do
            local props = properties(placed.sprite)
            if expect(props ~= nil, placed.sprite .. " has no properties") then
                expect(props:has("IsMoveAble"), placed.sprite .. " can't be picked up")
                expect(props:get("CustomItem") == placed.item,
                    placed.sprite .. " gives " .. tostring(props:get("CustomItem")) .. ", expected " .. placed.item)
                expect(props:has("container") == (placed.container == true),
                    placed.sprite .. (placed.container and " has no container" or " has a container"))
            end
            expect(instanceItem(placed.item) ~= nil, placed.item .. " does not exist")
        end
    end,
})

test("renewable_energy_art_moveable_items_place_their_tiles", {
    validate = function()
        for _, placed in ipairs(PLACED) do
            local script = getScriptManager():getItem(placed.item)
            local kind, _, material = Sprites.kindOf(script and script:getWorldObjectSprite())
            expect(kind == placed.kind and material == placed.material, string.format("%s places a %s %s tile, expected %s %s",
                placed.item, tostring(material), tostring(kind), tostring(placed.material), placed.kind))
        end
    end,
})

test("renewable_energy_art_kind_of_reads_every_placed_tile", {
    validate = function()
        for _, placed in ipairs(PLACED) do
            local kind, facing, material = Sprites.kindOf(placed.sprite)
            expect(kind == placed.kind and facing == placed.facing and material == placed.material,
                string.format("kindOf(%s) is %s %s %s, expected %s %s %s", placed.sprite, tostring(kind), tostring(facing),
                    tostring(material), placed.kind, tostring(placed.facing), tostring(placed.material)))
            expect(not Sprites.isOverlay(placed.sprite), placed.sprite .. " counts as an overlay")
        end
        for _, name in ipairs(overlays()) do
            expect(Sprites.isOverlay(name), name .. " does not count as an overlay")
            expect(Sprites.kindOf(name) == nil, name .. " has a kind")
        end
        expect(Sprites.kindOf("carpentry_01_16") == nil, "a vanilla crate has a kind")
    end,
})

-- The placing cursor turns a rack through all four facings and a wall panel between its two,
-- without turning wood into metal.
test("renewable_energy_art_mounts_rotate", {
    validate = function()
        for _, mount in ipairs({ "rack", "wall" }) do
            for material in pairs(MATERIALS) do
                local set = Sprites[mount][material]
                for facing, name in pairs(set) do
                    local faces = ISMoveableSpriteProps.new(name):getFaces()
                    for otherFacing, otherName in pairs(set) do
                        expect(faces[otherFacing] == otherName, string.format("%s (%s %s) turns %s to %s, expected %s",
                            name, material, facing, otherFacing, tostring(faces[otherFacing]), otherName))
                    end
                end
            end
        end
    end,
})

-- Every battery a bank can hold shows, and the meter reads its charge.
test("renewable_energy_art_bank_overlays", {
    validate = function()
        for itemType, bank in pairs(Specs.banks) do
            local fill = Sprites.bankFill[bank.sprite]
            if expect(fill ~= nil, itemType .. " has no battery overlays") then
                expect(#fill.batteries == bank.maxBatteries, string.format("%s shows up to %d batteries but holds %d",
                    itemType, #fill.batteries, bank.maxBatteries))
                local full = Sprites.bankOverlays(bank.sprite, bank.maxBatteries, 1)
                expect(full[1] == fill.batteries[bank.maxBatteries] and full[2] == fill.meter[5],
                    "a full " .. itemType .. " shows " .. table.concat(full, ", "))
                local one = Sprites.bankOverlays(bank.sprite, 1, 0.05)
                expect(one[1] == fill.batteries[1] and one[2] == fill.meter[1],
                    "one battery at 5% in " .. itemType .. " shows " .. table.concat(one, ", "))
                expect(#Sprites.bankOverlays(bank.sprite, 0, 1) == 0, "an empty " .. itemType .. " shows overlays")
            end
        end
        for fraction, level in pairs({ [0] = 1, [0.2] = 2, [0.5] = 3, [0.8] = 4, [0.96] = 5, [1] = 5 }) do
            expect(Sprites.meterLevel(fraction) == level,
                "charge " .. fraction .. " shows meter level " .. Sprites.meterLevel(fraction) .. ", expected " .. level)
        end
    end,
})

test("renewable_energy_art_items_have_icons_and_ground_models", {
    validate = function()
        local items = getScriptManager():getAllItems()
        local checked = 0
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item:getModuleName() == "RenewableEnergy" then
                checked = checked + 1
                local model = item:getWorldStaticModel()
                expect(model ~= nil and getScriptManager():getModelScript(model) ~= nil,
                    item:getFullName() .. " has no ground model (" .. tostring(model) .. ")")
                local icon = item:getIcon()
                expect(icon ~= nil and getTexture("Item_" .. icon) ~= nil, item:getFullName() .. " has no icon (" .. tostring(icon) .. ")")
            end
        end
        expect(checked > 0, "no RenewableEnergy items")
    end,
})

-- The arrow board trailer ------------------------------------------------------------------------

local TRAILER = "Base.RenewableEnergyArrowBoardTrailer"
local TOWING_CAR = "Base.OffRoad"
-- How far ahead of the car, and behind the trailer, the strip they stand on runs, in squares:
-- the car is pushed a few squares north.
local STRIP_AHEAD, STRIP_BEHIND = 7, 9

local Wait = RenewableEnergyTest.Wait

local function isClear(x, y, z)
    local square = getSquare(x, y, z)
    return square ~= nil and square:isOutside() and square:isFree(false) and not square:HasTree()
        and square:getVehicleContainer() == nil
end

-- The closest square with three open squares across it from STRIP_AHEAD north to STRIP_BEHIND
-- south, room for a car and the trailer hitched behind it.
local function openStrip()
    local here = RenewableEnergyTest.player():getSquare()
    local best, bestDistance
    for dx = -25, 25 do
        for dy = -25, 25 do
            local x, y, z = here:getX() + dx, here:getY() + dy, here:getZ()
            local distance = dx * dx + dy * dy
            if not bestDistance or distance < bestDistance then
                local open = true
                for sx = x - 1, x + 1 do
                    for sy = y - STRIP_AHEAD, y + STRIP_BEHIND do
                        open = open and isClear(sx, sy, z)
                    end
                end
                if open then
                    best, bestDistance = { x = x, y = y, z = z }, distance
                end
            end
        end
    end
    return best
end

-- A vehicle facing north on the square, or nil where the game left it out of the world (only a
-- vehicle in the world gets an id).
local function spawnVehicle(scriptName, x, y, z)
    local vehicle = addVehicleDebug(scriptName, IsoDirections.N, 0, getSquare(x, y, z))
    if vehicle and vehicle:getId() ~= -1 then
        vehicle:repair()
        return vehicle
    end
end

local function removeVehicles(self)
    for _, vehicle in ipairs({ self.car, self.trailer }) do
        if vehicle then
            vehicle:permanentlyRemove()
        end
    end
    if self.home then
        RenewableEnergyTest.player():teleportTo(self.home.x, self.home.y, self.home.z)
    end
end

local function hitchGap(car, trailer)
    local hitch = car:getTowingWorldPos("trailer", Vector3f.new())
    local coupler = trailer:getTowedByWorldPos("trailer", Vector3f.new())
    if not (hitch and coupler) then
        return math.huge
    end
    return math.sqrt((hitch:x() - coupler:x()) ^ 2 + (hitch:y() - coupler:y()) ^ 2)
end

-- Ticks to let the hitched pair settle, to push the car, and to let them roll to a stop.
local SETTLE, PUSH, ROLL = 60, 40, 140
-- A car with nobody at the wheel holds its brakes, so the push has to beat them.
local PUSH_IMPULSE = 6000
-- The push stops once the car is moving, after this many squares: an impulse each tick adds up
-- faster at a higher frame rate, and a car shoved far off the open strip hits something and
-- can snap the hitch. It rolls on a good way after.
local PUSH_SQUARES = 0.5

-- It spawns, a vanilla car hitches it as the game's own attachTrailerToPlayerVehicle does, and
-- when the car is pushed north the trailer follows, still on the hitch. The screenshot
-- (renewable_energy_art_trailer.png in the cache's Screenshots) shows the pair after the pull.
test("renewable_energy_art_trailer_tows", {
    run = function(self)
        local strip = openStrip()
        if not strip then return end
        self.car = spawnVehicle(TOWING_CAR, strip.x, strip.y, strip.z)
        self.trailer = spawnVehicle(TRAILER, strip.x, strip.y + 5, strip.z)
        if not (self.car and self.trailer) then return end
        local p = RenewableEnergyTest.player()
        self.home = { x = p:getX(), y = p:getY(), z = p:getZ() }
        ISTimedActionQueue.add(Wait:new(p, SETTLE + PUSH + ROLL, function(tick)
            if tick == 2 then
                self.car:addPointConstraint(p, self.trailer, "trailer", "trailer")
                p:teleportTo(strip.x + 3.5, strip.y + 2.5, strip.z)
            elseif tick == SETTLE then
                self.start = { x = self.trailer:getX(), y = self.trailer:getY() }
                self.carStartY = self.car:getY()
            elseif tick > SETTLE and tick <= SETTLE + PUSH and self.carStartY - self.car:getY() < PUSH_SQUARES then
                self.car:applyImpulseGeneric(self.car:getX(), self.car:getY(), self.car:getZ(), 0, -1, 0, PUSH_IMPULSE)
            elseif tick == SETTLE + PUSH + ROLL - 1 then
                getCore():TakeFullScreenshot("renewable_energy_art_trailer.png")
            end
        end))
    end,
    validate = function(self)
        if not expect(self.car ~= nil and self.trailer ~= nil, "no room to spawn a car and the trailer") then return end
        expect(self.trailer:getScript():getFullName() == TRAILER, "the trailer spawned as " .. self.trailer:getScript():getFullName())
        expect(self.trailer:getVehicleTowedBy() == self.car, "the trailer is not hitched to the car")
        local moved = self.start and math.sqrt((self.trailer:getX() - self.start.x) ^ 2 + (self.trailer:getY() - self.start.y) ^ 2) or 0
        print(string.format("RETrailer moved %.2f squares, hitch gap %.2f", moved, hitchGap(self.car, self.trailer)))
        expect(moved > 1.5, string.format("the trailer moved %.2f squares behind the pushed car", moved))
        expect(hitchGap(self.car, self.trailer) < 1, "the trailer's coupler is off the car's hitch")
    end,
    cleanup = removeVehicles,
})

-- Its battery box opens only with its lid open, from beside it, and holds a battery.
test("renewable_energy_art_trailer_battery_box", {
    run = function(self)
        local strip = openStrip()
        if not strip then return end
        self.trailer = spawnVehicle(TRAILER, strip.x, strip.y + 5, strip.z)
        if not self.trailer then return end
        local p = RenewableEnergyTest.player()
        self.home = { x = p:getX(), y = p:getY(), z = p:getZ() }
        ISTimedActionQueue.add(Wait:new(p, 30, function(tick)
            if tick == 2 then
                local spot = self.trailer:getAreaCenter("RenewableEnergyBatteryBox")
                if spot then
                    p:teleportTo(spot:getX(), spot:getY(), strip.z)
                end
            end
        end))
    end,
    validate = function(self)
        if not expect(self.trailer ~= nil, "no room to spawn the trailer") then return end
        local p = RenewableEnergyTest.player()
        local lid, box = self.trailer:getPartById("TrunkDoor"), self.trailer:getPartById("RenewableEnergyBatteryBox")
        local container = box and box:getItemContainer()
        if not (expect(lid ~= nil and lid:getDoor() ~= nil, "the battery box has no lid")
                and expect(container ~= nil, "the battery box holds nothing")) then
            return
        end
        expect(not lid:getDoor():isLocked(), "the battery box starts locked")
        expect(not self.trailer:canAccessContainer(box:getIndex(), p), "the battery box opens with its lid shut")
        lid:getDoor():setOpen(true)
        expect(self.trailer:canAccessContainer(box:getIndex(), p), "the battery box doesn't open beside it with its lid open")
        -- A spawned trailer may come stocked, so count from what it already holds.
        local before = container:getCountType("RenewableEnergy.DeepCycleBattery")
        container:AddItem("RenewableEnergy.DeepCycleBattery")
        expect(container:getCountType("RenewableEnergy.DeepCycleBattery") == before + 1, "the battery box doesn't take a battery")
    end,
    cleanup = removeVehicles,
})
