-- Development only. Where the promo shots stand: the layouts of the setups and shots, measured from
-- a place (PZHarness/StageLots.lua's places), and the specs PZHarness.Stage.findPlaces searches the
-- world around the character with, which only read it. RenewableEnergyDevPromo.lua builds and
-- shoots them.

local Sprites = require "RenewableEnergy/Sprites"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Debug = require "RenewableEnergy/Debug/RenewableEnergyDebug"
local Stage = require "RenewableEnergyDevStage"
local Harness = require "PZHarness/Stage"
require "PZHarness/StageLots"


local Places = {}

-- Both setups stand at an outside wall that the camera sees: the north edge of a square south of
-- a building (preferred: wall panels face south), or the west edge of one east of it. Positions
-- are (along, out) from the square outside the wall: `along` runs along the wall, `out` away
-- from it, so out -1 is indoors; panels face `out`.
local SITES = {
    { wallNorth = true, along = { 1, 0 }, out = { 0, 1 }, facing = "S" },
    { wallNorth = false, along = { 0, 1 }, out = { 1, 0 }, facing = "E" },
}
-- The homestead. Banks stand indoors, so the bank is in the room behind the wall the wall panels
-- hang on (`inside` is the square behind it), out of the yard shots, against the room's north wall
-- with the character off to its side for a shot of its own (bankPlace). Outdoors, the character
-- stands beside the last wall panel, where nothing is behind them, and the backup generator is
-- within a failsafe's reach of the bank. An insulated digester beside the generator feeds it gas
-- through its kit, and a propeller wind charger stands at the far end of the wall, where its
-- mast rises in front of the house rather than over the panels.
Places.HOMESTEAD = {
    inside = { 0, -1 },
    generator = { -1, 1 },
    digester = { -2, 1 },
    windCharger = { 5, 1 },
    wallPanels = { { 0, 0, "wood" }, { 1, 0, "wood" }, { 2, 0, "metal" } },
    player = { 3, 1 },
    racks = { { -1, 3, "wood" }, { 0, 3, "wood" }, { 1, 3, "metal" }, { 2, 3, "metal" } },
    flatPanels = { { 0, 5 }, { 1, 5 }, { 2, 5 }, { 3, 5 } },
    -- Where the character looks around first, out in the yard the shots also show.
    scouts = { { -4, 3 }, { -3, 8 }, { 2, 9 } },
}
-- The ground that must be clear (grass and weeds are cleared), and the plain wall the wall panels
-- hang on.
Places.OPEN = { along = { -2, 5 }, out = { 1, 5 } }
local AT_WALL = { 0, 2 }

-- Stage 0, at another building: a battery box indoors beside a window, the character at the
-- window, and the panels, a solar battery charger and a garden light outside in their sight.
-- Positions are (along, out) from the square outside the window, as the homestead's.
Places.STAGE0 = {
    box = { 1, -1 },
    player = { 0, -1 },
    flatPanels = { { 0, 1 }, { 1, 2 } },
    cellCharger = { -1, 1 },
    gardenLight = { 2, 1 },
    -- Where the character looks around first, among the panels.
    scout = { 0, 2 },
    open = { along = { -1, 2 }, out = { 1, 2 } },
}

-- Every setup stands at least this far from the others along x or y, out of each other's shots.
Places.GAP = 12

-- The trailer shot, on a road: positions are (ahead, side) squares from the car, `side` towards
-- the far side of the road from the camera, so a heading's frame runs `along` ahead and `out` to
-- the side. Road cones taper across the lane behind the trailer, and the character stands on the
-- far side of the trailer's battery box, where the arrow board hides none of them.
Places.ROAD = {
    -- The car faces north on a north-south road, else west on an east-west one, so that the
    -- arrow board on the trailer's back faces the camera.
    headings = { { facing = "N", along = { 0, -1 }, out = { -1, 0 } }, { facing = "W", along = { -1, 0 }, out = { 0, -1 } } },
    -- The open road the setup needs: room on the near side keeps hedges and fences there from
    -- hiding the car.
    open = { along = { -11, 3 }, out = { -3, 3 } },
    -- Where Stage.spawnTrailer puts the trailer.
    trailer = { -Stage.TRAILER_GAP, 0 },
    cones = { { -8, 1 }, { -9, 0 }, { -10, -1 } },
    cone = "street_decoration_01_26",
    player = { -3, 3 },
    -- Other vehicles this close to the car go, so that only the car and trailer are in the shot.
    clearRadius = 14,
}

-- The garden lights shot, at night: lights on both sides of a house's front walk, the character
-- at the door. Positions are (along, out) from the square outside the door, as the homestead's.
Places.WALK = {
    -- The door stands on the square at out 0, so the open ground starts past it. It reaches a
    -- square past the lights, so that no fence stands between them and the camera.
    open = { along = { -1, 1 }, out = { 1, 4 } },
    -- Each with its own bulb, to show the colours a light takes.
    lights = {
        { -1, 1, bulb = "Base.LightBulb" }, { 1, 1, bulb = "Base.LightBulbBlue" },
        { -1, 3, bulb = "Base.LightBulbRed" }, { 1, 3, bulb = "Base.LightBulbGreen" },
    },
    -- On the walk between the far pair of lights, clear of the door: a square nearer it would
    -- stand straight in front of a near light.
    player = { 0, 3 },
    scout = { 0, 4 },
    -- Late enough for the sky to be dark in any season.
    hour = 23,
}
-- The poster and the Workshop preview, by day and close in, so that it reads where Steam shows it
-- smallest: a homebuilt turbine turning over a house's yard, racks of panels before its windows, a
-- brick dome feeding a kitted generator, and the settler beside them, all run by a bank indoors
-- behind the window. Positions are (along, out) from the square outside the window, as the
-- homestead's; each stands clear of the others on the screen, the racks across the middle, the
-- dome and generator to their left, the turbine and the settler to their right.
Places.POSTER = {
    -- A wall with windows reads as a home rather than a shed.
    windows = { along = { -4, 4 }, count = 2 },
    rooms = 3,
    bank = { 0, -1 },
    open = { along = { -2, 3 }, out = { 1, 3 } },
    -- In front of the yard, where the shot reaches below it.
    front = { along = { -3, 5 }, out = { 4, 6 } },
    racks = { { 0, 2, "metal" }, { 1, 2, "metal" }, { 2, 2, "metal" } },
    generator = { -2, 2 },
    digester = { -2, 1 },
    windCharger = { 3, 1 },
    player = { 3, 2 },
    -- Where the character looks around first, so that the house and the yard are drawn rather than
    -- left black as unseen: indoors where the floor is free, then outdoors.
    indoors = { { -3, -2 }, { 0, -2 }, { 3, -2 } },
    scouts = { { -4, 4 }, { 0, 8 }, { 6, 4 }, { 6, 0 } },
    -- A step out from the closest zoom: the closest leaves the turbine's rotor off the top.
    zoomOut = 1,
}

-- The gas, wind and treadmill setups, by the name of their place: the yards (biogas, woodgas,
-- wind), each on open ground of its own, and the treadmill indoors (gym). Positions are (east,
-- south) squares from the place found, and `shot` names the positions the shot frames. A yard lays
-- its things out along a line across the screen, nearest the camera in front, so `open` is the
-- band of squares that must be clear (trees may stand there; they go).
Places.LAYOUTS = {
    -- Every digester, working and full of gas, the brick dome feeding a kitted generator through
    -- its hose, and a lit gas heater warming the steel barrel.
    biogas = {
        open = { along = { -2, 6 }, out = { -1, 6 }, sum = 4, half = 3 },
        barrelSteel = { 0, 4 },
        heater = { -1, 4 },
        barrelOrange = { 1, 3 },
        insulated = { 2, 2 },
        dome = { 3, 1 },
        generator = { 4, 1 },
        player = { 5, 0 },
        scout = { 2, 4 },
        shot = { "barrelSteel", "heater", "barrelOrange", "insulated", "dome", "generator", "player" },
    },
    -- The gasifier and the advanced gasifier lit, each piped to a kitted generator to its east, and
    -- the primitive gasifier with wood and charcoal beside it.
    woodgas = {
        open = { along = { -1, 6 }, out = { -1, 6 }, sum = 5, half = 3 },
        primitive = { 0, 4 },
        fuel = { 1, 4 },
        standard = { 1, 3 },
        standardGenerator = { 2, 3 },
        advanced = { 3, 1 },
        advancedGenerator = { 4, 1 },
        player = { 4, 3 },
        scout = { 2, 5 },
        shot = { "primitive", "fuel", "standard", "standardGenerator", "advanced", "advancedGenerator", "player" },
        -- On the ground beside the primitive gasifier, what it burns, as a player brings it: where
        -- each lies on its square, as fractions of it, and which way it is turned.
        fuelItems = {
            { "Base.Log", 0.3, 0.3, 20 }, { "Base.Log", 0.62, 0.36, 110 }, { "Base.Firewood", 0.36, 0.66, 300 },
            { "Base.Firewood", 0.7, 0.7, 200 }, { "Base.Charcoal", 0.5, 0.5, 45 },
        },
    },
    -- The wind chargers in a row across the screen, smallest first, every rotor facing south.
    wind = {
        open = { along = { -1, 8 }, out = { -1, 8 }, sum = 6, half = 3 },
        chargers = {
            { 0, 6, sprite = Sprites.windScoop }, { 2, 4, sprite = Sprites.windCharger.propeller.wood.S },
            { 4, 2, sprite = Sprites.windCharger.carAlternator.pipe.S }, { 6, 0, sprite = Sprites.windCharger.alternator.steel.S },
        },
        player = { 2, 6 },
        scout = { 4, 5 },
        shot = { "player" },
    },
    -- The treadmill, wired to a battery box beside it, the character running on it across the
    -- screen, side on to the camera. The treadmill's two tiles, by the way its runner faces
    -- (Sprites): the rear tile the runner stands on, and the console in front. The
    -- box stands past the rear end, and the character waits beside the belt.
    gym = {
        rear = { 1, 0 },
        console = { 0, 0 },
        box = { 2, 0 },
        stand = { 1, 1 },
        facing = "W",
        shot = { "rear", "console", "box", "stand" },
        -- Floor of the same room between the treadmill and the camera, where furniture or the
        -- room's near walls, drawn see-through, would stand in front of the runner.
        front = { { -1, 1 }, { 0, 1 }, { 2, 1 }, { 3, 1 }, { -1, 2 }, { 0, 2 }, { 1, 2 }, { 2, 2 }, { 3, 2 },
            { 0, 3 }, { 1, 3 }, { 2, 3 } },
        -- Real time the run plays before the shot, past the blend into the run.
        runMs = 2500,
    },
}

-- Open ground (Harness.isOpenGround) the character isn't standing on.
local function isUnoccupiedGround(square, player)
    return Harness.isOpenGround(square) and square ~= player:getCurrentSquare()
end

-- Walls, their trim and what hangs on them: lamps, pipes, signs.
local WALL_FLAGS = { IsoFlagType.cutN, IsoFlagType.cutW, IsoFlagType.WallOverlay, IsoFlagType.attachedN,
    IsoFlagType.attachedW, IsoFlagType.attachedS, IsoFlagType.attachedE }

function Places.isOnWall(object)
    local props = object:getProperties()
    if not props then
        return false
    end
    for _, flag in ipairs(WALL_FLAGS) do
        if props:has(flag) then
            return true
        end
    end
    return false
end

-- Fits -------------------------------------------------------------------------------------------

local function hasOpenGround(place, player, area)
    return Harness.everyAreaSquare(place, area, function(square)
        return isUnoccupiedGround(square, player)
    end)
end

-- Outdoors, against a wall of a room. A panel hangs on a `plain` wall: not a door, a garage door
-- or a window.
local function isAtWall(place, along, plain)
    local square, inside, wallNorth = Harness.at(place, { along, 0 }), Harness.at(place, { along, -1 }), place.frame.wallNorth
    if not (square and inside and inside:getRoom() and square:getWall(wallNorth)
        and Harness.isOpenGround(square, { allows = Places.isOnWall })) then
        return false
    end
    return not plain or (square:getDoorOrWindow(wallNorth) == nil and square:getGarageDoor(wallNorth) == nil)
end

-- Whether the outside wall at `along` has a door or window of class `class` ("IsoDoor",
-- "IsoWindow") into a room.
local function hasOpening(place, along, class)
    local square, inside = Harness.at(place, { along, 0 }), Harness.at(place, { along, -1 })
    return square ~= nil and inside ~= nil and inside:getRoom() ~= nil and square:isOutside()
        and instanceof(square:getDoorOrWindow(place.frame.wallNorth), class)
end

local function isFreeIndoorsAt(place, position)
    return Debug.isFreeSquare(Harness.at(place, position), true)
end

-- North from `square` through its room to the room's north wall: a bank faces south, so it stands
-- there with its back to the wall. Nil outside a room.
local function againstNorthWall(square)
    local room = square and square:getRoom()
    while square and room and square:getRoom() == room do
        if square:getWall(true) then
            return square
        end
        square = getCell():getGridSquare(square:getX(), square:getY() - 1, square:getZ())
    end
    return nil
end

-- Where along the panels' wall the bank's column may be, nearest the panels first.
local ALONG_PANELS = { 0, -1, 1, -2, 2 }
-- The character's square from the bank's, (east, south), the first that fits: in front of it and
-- far enough off to one side that the character hides none of it. In the shot a square south
-- moves the character left as far as a square west does, so a square further east it stands a
-- square further south.
local BESIDE_BANK = { { 0, 2 }, { 1, 3 }, { -2, 1 } }
-- How far east of the bank the room's floor runs on: the game draws the room's east wall faded
-- rather than cut away, and closer it stands over the bank.
local BANK_EAST_CLEAR = 4

-- The squares of the bank shot: from the bank to the character, a square around the character,
-- and the floor east of the bank.
function Places.eachShotSquare(bank, player, fn)
    for y = bank:getY(), player:getY() + 1 do
        for x = math.min(bank:getX(), player:getX() - 1), math.max(bank:getX() + BANK_EAST_CLEAR, player:getX() + 1) do
            fn(getCell():getGridSquare(x, y, bank:getZ()))
        end
    end
end

-- Whether the bank shot's squares are open floor of the bank's room, so that the character stands
-- clear of every wall: no wall between them, and no door or window but in the back wall beside the
-- bank. A room may have a wall through it, which the shot would show the character in.
local function isOpenShot(bank, player)
    local room, open = bank:getRoom(), true
    Places.eachShotSquare(bank, player, function(square)
        local backWall = square and square:getY() == bank:getY() and square ~= bank
        if not (square and square:getRoom() == room) or square:getDoorOrWindow(false)
            or (square:getDoorOrWindow(true) and not backWall) then
            open = false
            return
        end
        local cell, x, y, z = getCell(), square:getX(), square:getY(), square:getZ()
        for _, beyond in ipairs({ cell:getGridSquare(x + 1, y, z), cell:getGridSquare(x, y + 1, z) }) do
            if beyond:getRoom() == room and square:isSomethingTo(beyond) then
                open = false
            end
        end
    end)
    return open
end

-- The homestead bank's square and the character's. The panels' wall faces south (SITES[1]), so the
-- bank stands across the room from it, against the north wall, facing it, with open floor around it
-- and the character. Nil if the room has no such place.
local function bankPlace(place)
    for _, along in ipairs(ALONG_PANELS) do
        local bank = againstNorthWall(Harness.at(place, { Places.HOMESTEAD.inside[1] + along, Places.HOMESTEAD.inside[2] }))
        if bank and PowerBank.canPlaceBank(bank) then
            for _, offset in ipairs(BESIDE_BANK) do
                local player = getCell():getGridSquare(bank:getX() + offset[1], bank:getY() + offset[2], bank:getZ())
                if player and isOpenShot(bank, player) then
                    return bank, player
                end
            end
        end
    end
    return nil
end

local function fitsHomestead(place, player)
    for along = AT_WALL[1], AT_WALL[2] do
        if not isAtWall(place, along, true) then
            return false
        end
    end
    return bankPlace(place) ~= nil and hasOpenGround(place, player, Places.OPEN)
end

-- At a window if `needWindow`, else at any outside wall.
local function fitsStage0(place, player, needWindow)
    local window = hasOpening(place, 0, "IsoWindow")
    if (needWindow and not window) or not (window or isAtWall(place, 0, false)) then
        return false
    end
    return isFreeIndoorsAt(place, Places.STAGE0.box) and isFreeIndoorsAt(place, Places.STAGE0.player)
        and hasOpenGround(place, player, Places.STAGE0.open)
end

-- A window into a house (a building with a bedroom and POSTER.rooms rooms), on a wall with
-- POSTER.windows.count windows near it, with free floor for the bank behind it and open ground for
-- the panels in front.
local function fitsPoster(place, player)
    if not (hasOpening(place, 0, "IsoWindow") and isFreeIndoorsAt(place, Places.POSTER.bank)
        and hasOpenGround(place, player, Places.POSTER.open)) then
        return false
    end
    local building = Harness.at(place, { 0, -1 }):getBuilding()
    if not (building and building:isResidential() and building:getDef():getRooms():size() >= Places.POSTER.rooms) then
        return false
    end
    local windows = 0
    for along = Places.POSTER.windows.along[1], Places.POSTER.windows.along[2] do
        windows = windows + (hasOpening(place, along, "IsoWindow") and 1 or 0)
    end
    return windows >= Places.POSTER.windows.count
end

-- The markings and blends painted over a road's floor.
local function isRoadPaint(object)
    local name = Sprites.nameOf(object)
    return name ~= nil and (luautils.stringStarts(name, "floors_overlay") or luautils.stringStarts(name, "blends_"))
end

local function isClearRoad(square, player)
    return Harness.isOpenGround(square, { floor = "blends_street", allows = isRoadPaint })
        and square ~= player:getCurrentSquare()
end

-- Outdoors on natural ground (grass or dirt, not a road or a yard's paving) with nothing on it but
-- ground cover and trees, which the setups take away.
local function isYardSquare(square, player)
    return Harness.isOpenGround(square, { floor = Harness.NATURAL_FLOOR, trees = true })
        and square ~= player:getCurrentSquare()
end

-- Whether `square` is floor of `room` with nothing standing on it, such as furniture or a pot
-- plant: what lies flat, such as a rug, may.
local function isBareFloor(square, room)
    if not (square and square:getRoom() == room) then
        return false
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local props = objects:get(i):getProperties()
        if props and (props:has(IsoFlagType.solid) or props:has(IsoFlagType.solidtrans)) then
            return false
        end
    end
    return true
end

-- Indoors, with free floor of one room for the treadmill, its battery box and the character beside
-- it, nothing between them, and bare floor in front.
local function fitsGym(place)
    local gym, origin = Places.LAYOUTS.gym, place.origin
    local room = origin:getRoom()
    if not room then
        return false
    end
    for _, key in ipairs(gym.shot) do
        local square = Harness.at(place, gym[key])
        if not (square and square:getRoom() == room and Debug.isFreeSquare(square, true)
            and not origin:isSomethingTo(square)) then
            return false
        end
    end
    for _, spot in ipairs(gym.front) do
        if not isBareFloor(Harness.at(place, spot), room) then
            return false
        end
    end
    return true
end

-- Finding the places ------------------------------------------------------------------------------

-- The place closest to the character in the first of `frames` for which fits(place) holds, apart
-- from the places `found` before it.
local function closestPlace(player, found, frames, fits)
    return Harness.closestPlace(player, frames, fits, found, Places.GAP)
end

-- A yard: a band of natural ground (LAYOUTS[name].open) clear for it.
local function yard(name)
    return {
        name = name,
        label = name,
        missing = "open ground for the " .. name .. " shot",
        frames = { Harness.GRID },
        fits = function(place, player)
            return Harness.everyAreaSquare(place, Places.LAYOUTS[name].open, function(square)
                return isYardSquare(square, player)
            end)
        end,
    }
end

--- Every place a group may need (Promo's GROUPS' `places`), as PZHarness.Stage.findPlaces specs,
--- in the order they are looked for.
Places.PLACES = {
    {
        name = "homestead",
        label = "homestead",
        missing = "plain building wall with open ground in front and a room behind it with open floor along its north wall",
        find = function(player, found)
            -- SITES[1], the south-facing wall: the bank stands against the north wall across from it.
            local place = closestPlace(player, found, { SITES[1] }, function(candidate)
                return fitsHomestead(candidate, player)
            end)
            if place then
                place.bank, place.beside = bankPlace(place)
            end
            return place
        end,
        detail = function(place)
            return string.format(", bank %d,%d, character beside it %d,%d", place.bank:getX(), place.bank:getY(),
                place.beside:getX(), place.beside:getY())
        end,
    },
    {
        name = "stage0",
        label = "stage 0",
        missing = "outside wall with free floor indoors behind it and open ground in front, for stage 0",
        -- At a window if any.
        find = function(player, found)
            for _, needWindow in ipairs({ true, false }) do
                local place = closestPlace(player, found, SITES, function(candidate)
                    return fitsStage0(candidate, player, needWindow)
                end)
                if place then
                    place.atWindow = needWindow
                    return place
                end
            end
            return nil
        end,
        detail = function(place)
            return place.atWindow and ", at a window" or ", at a wall"
        end,
    },
    {
        name = "road",
        label = "trailer",
        missing = "stretch of open road for the trailer",
        frames = Places.ROAD.headings,
        fits = function(place, player)
            return Harness.everyAreaSquare(place, Places.ROAD.open, function(square)
                return isClearRoad(square, player)
            end)
        end,
    },
    Harness.STUDIO_PLACE,
    {
        name = "walk",
        label = "garden lights",
        missing = "door with open ground in front, for the garden lights",
        frames = SITES,
        fits = function(place, player)
            return hasOpening(place, 0, "IsoDoor") and hasOpenGround(place, player, Places.WALK.open)
        end,
    },
    {
        name = "poster",
        label = "poster",
        missing = "wall with " .. Places.POSTER.windows.count .. " windows and open ground in front, for the poster",
        frames = SITES,
        fits = fitsPoster,
    },
    yard("biogas"),
    yard("woodgas"),
    yard("wind"),
    {
        name = "gym",
        label = "treadmill",
        missing = "room with free floor for the treadmill",
        frames = { Harness.GRID },
        fits = fitsGym,
    },
}

return Places
