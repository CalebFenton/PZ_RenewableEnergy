-- A lamppost a drawing side keeps lit at one place, for the mod's lights that vanilla has no light
-- source for: a garden light's lamp, a lit lamp board's glow on the ground. `lamp` is the caller's
-- table ({} for none yet), holding the light source and where and in what colour it was made.

local Lamppost = {}

--- Takes away `lamp`'s light, if it has one.
function Lamppost.clear(lamp)
    if lamp.source then
        -- By object, as vanilla's lamps do: the cell drops it on its next lighting pass. By place
        -- it would clear its light at once, which the native lighting refuses.
        getCell():removeLamppost(lamp.source)
        lamp.source = nil
    end
end

--- Lights `lamp` at x, y, z in r, g, b over `radius` squares: kept as it is when it is already
--- there, recoloured in place when only the colour changed, made anew when it moved or the cell
--- dropped it, as it drops the lamps of a chunk that unloads.
function Lamppost.show(lamp, x, y, z, r, g, b, radius)
    local cell, source = getCell(), lamp.source
    -- Whether the cell still holds this very source: getLightSourceAt answers the first at the
    -- place, which can be one removed by object that the next lighting pass has yet to drop.
    if source and lamp.x == x and lamp.y == y and lamp.z == z and cell:getLamppostPositions():contains(source) then
        if lamp.r ~= r or lamp.g ~= g or lamp.b ~= b then
            -- As a vanilla lamp takes a new bulb's colour (IsoLightSwitch.setPrimaryR); the next
            -- lighting pass hands it to the native lighting.
            source:setR(r)
            source:setG(g)
            source:setB(b)
            lamp.r, lamp.g, lamp.b = r, g, b
        end
        return
    end
    Lamppost.clear(lamp)
    lamp.source = cell:addLamppost(x, y, z, r, g, b, radius)
    lamp.x, lamp.y, lamp.z, lamp.r, lamp.g, lamp.b = x, y, z, r, g, b
end

return Lamppost
