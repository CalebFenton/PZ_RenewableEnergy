-- Wind chargers' output: the game's wind (ClimateManager.getWindspeedKph, stronger in winter, no
-- day and night), the turbine's power curve, how high it stands and what shelters it.
--
-- Shelter has no direction: the game's wind angle is a screen-space value for its weather effects
-- (ClimateManager.getWindAngleDegrees), so a turbine counts what stands around it on every side.

require "RenewableEnergy/Specs"

RenewableEnergy = RenewableEnergy or {}
local Wind = {}
RenewableEnergy.Wind = Wind

local Specs = RenewableEnergy.Specs

--- The watts a turbine of `spec` (Specs.wind.turbines) makes in a wind of `kph`, standing on level
--- `z` with `shelter` (0 open .. 1 walled in) around it: nothing below its cut-in speed, rising
--- with the cube of the speed to its rating at its rated speed, and no more above it.
function Wind.watts(spec, kph, z, shelter)
    local wind = Specs.wind
    if kph <= spec.cutInKph then
        return 0
    end
    local share = math.min(1, (kph - spec.cutInKph) / (spec.ratedKph - spec.cutInKph))
    local height = 1 + wind.heightBonusPerLevel * math.min(math.max(z, 0), wind.maxBonusLevel)
    return spec.ratedW * share ^ 3 * height * (1 - wind.shelterLoss * shelter)
end

-- How much a square shelters a turbine on level `z`: a tree, or a wall or a building's square that
-- stands as high, blocks it; low growth and lower buildings don't.
local function blocks(square, z)
    if not square then
        return 0
    end
    if z <= 1 and square:HasTree() then
        return 1
    end
    local building = square:getBuilding()
    if building and building:getDef() and building:getDef():getMaxLevel() >= z then
        return 1
    end
    return 0
end

--- The share of the ring of squares around (x, y) on the ground, out to Specs.wind.shelterRadius,
--- that shelters a turbine on level `z`: 0 in the open, 1 hemmed in.
function Wind.shelterAt(x, y, z)
    local radius = Specs.wind.shelterRadius
    local blocked, count = 0, 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance >= 1 and distance <= radius then
                -- Nearer obstacles count for more.
                local weight = 1 - (distance - 1) / radius
                blocked = blocked + weight * blocks(getSquare(x + dx, y + dy, 0), z)
                count = count + weight
            end
        end
    end
    return count > 0 and blocked / count or 0
end

return Wind
