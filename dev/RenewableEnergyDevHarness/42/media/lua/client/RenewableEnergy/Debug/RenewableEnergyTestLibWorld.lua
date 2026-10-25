require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Fixtures of the world and loot tests. What they build and read lives on the authority, so they
-- go through the dev mod's server handlers (RenewableEnergyTestServer*.lua).

local T = RenewableEnergyTest

-- Spawns ----------------------------------------------------------------------------------------

--- Whether `value` lies in `range` ({ min, max }), both ends included.
function T.inRange(value, range)
    return value >= range.min and value <= range.max
end

--- Expects every charge of `charges` to be one a found battery holds (Specs.foundCharge).
function T.expectFoundCharges(charges, what)
    local range = RenewableEnergy.Specs.foundCharge
    for _, charge in ipairs(charges) do
        T.expect(T.inRange(charge, range), what .. " holds a battery at " .. charge .. ", expected " .. range.min .. " to "
            .. range.max)
    end
end

--- Expects a count range read from the authority to be one a player can meet: at least one, and
--- no more at its low end than at its high. The test checks spawns against it.
function T.expectSaneRange(range, what)
    T.expect(range.min >= 1 and range.min <= range.max, what .. " runs from " .. range.min .. " to " .. range.max)
end

-- Visits ----------------------------------------------------------------------------------------
-- A visit takes the character to a far place and waits there for this client to load it and for
-- the authority's answer about it.

--- Spots go down, and houses are rolled, on the game minute after their chunks load; a clock this
--- much faster brings that minute sooner.
T.VISIT_SPEED = 10
-- How long the authority is given to roll a visited place once this client has loaded it.
local ROLL_MS = 60000
-- How far around the start the squares must be loaded again before the next test: as far as
-- T.squares looks for free squares.
local HOME_RADIUS = 30

-- Whether every chunk within `radius` squares of the point is loaded: one square per chunk tells.
local function loadedAround(x, y, z, radius)
    for sx = x - radius, x + radius, 8 do
        for sy = y - radius, y + radius, 8 do
            if not getSquare(sx, sy, z) then
                return false
            end
        end
    end
    return getSquare(x + radius, y + radius, z) ~= nil
end

--- Speeds the clock to T.VISIT_SPEED and lets visits move the character through
--- self.teleportTo(x, y, z) (T.teleporter). Keeps the start in self.home, and puts the character
--- back there when the test ends, should a visit leave them elsewhere.
function T.startVisits(self)
    T.setMultiplier(self, T.VISIT_SPEED)
    local p = T.player()
    local home = { x = p:getX(), y = p:getY(), z = p:getZ() }
    self.home = home
    T.defer(self, function()
        if math.abs(p:getX() - home.x) > 1 or math.abs(p:getY() - home.y) > 1 then
            p:teleportTo(home.x, home.y, home.z)
        end
    end)
    self.teleportTo = T.teleporter(self)
end

--- Queues the character's move to x, y, a wait for this client to load it (`where` names it), and
--- the authority's handler `name` asked with `args` until `done(answer)` holds or ROLL_MS pass.
function T.visitUntil(self, x, y, where, name, args, done)
    T.step(function() self.teleportTo(x + 0.5, y + 0.5, 0) end)
    T.waitFor(self, function() return getSquare(x, y, 0) ~= nil end, where .. " loaded on this client", T.CHUNK_MS)
    T.serverUntil(self, name, args, done, ROLL_MS)
end

--- Queues the character's way back to self.home and a wait for the squares around it to load
--- again.
function T.returnHome(self)
    local home = self.home
    T.step(function() self.teleportTo(home.x, home.y, home.z) end)
    T.waitFor(self, function() return loadedAround(math.floor(home.x), math.floor(home.y), home.z, HOME_RADIUS) end,
        "the start loaded again", T.CHUNK_MS)
end

return T
