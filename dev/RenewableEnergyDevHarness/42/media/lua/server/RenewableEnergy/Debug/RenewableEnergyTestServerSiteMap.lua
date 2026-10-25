-- The authority's half of the check that the map's solar sites make sense where they stand: what
-- the metagrid says of each spot, read without loading it. Only registers a check, so a --stay
-- rerun loads it again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how checks work.

require "RenewableEnergy/Sprites"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local Sprites = RenewableEnergy.Sprites

-- Site kinds that are an arrow board on the road and nothing else.
local ARROW_BOARD_KINDS = { roadWorks = true, checkpoint = true }

-- A homestead kind's spots make sense on the map: its find and generator outdoors, its wind
-- charger within reach of its bank in a room, its generator beside a gasifier or within a
-- digester's hose reach on the same level, its pamphlet's house a building.
local function expectHomesteadSpots(expect, metaGrid, site, kind)
    local function outdoors(field)
        local spot = site[field]
        return expect(spot ~= nil, site.name .. " has no " .. field .. " spot")
            and expect(metaGrid:getRoomAt(spot[1], spot[2], spot[3]) == nil, site.name .. "'s " .. field .. " is indoors")
    end
    if kind.wind and outdoors("windCharger") then
        local at, bank = site.windCharger, site.bank
        if expect(bank ~= nil and metaGrid:getRoomAt(bank[1], bank[2], bank[3]) ~= nil, site.name .. "'s bank is in no room") then
            expect(RenewableEnergy.PowerBank.isInReach({ x = bank[1], y = bank[2], z = bank[3] }, at[1], at[2], at[3]),
                site.name .. "'s wind charger is out of its bank's reach")
        end
    end
    if kind.gas and outdoors(kind.gas) and outdoors("generator") then
        local source, generator = site[kind.gas], site.generator
        local sameLevel = source[3] == generator[3]
        if kind.gas == "gasifier" then
            expect(sameLevel and RenewableEnergy.Gasifier.sideOf(generator[1], generator[2], source[1], source[2]) ~= nil,
                site.name .. "'s generator isn't beside its gasifier")
        else
            expect(sameLevel and IsoUtils.DistanceTo(generator[1], generator[2], source[1], source[2]) <= RenewableEnergy.GasKit.REACH,
                site.name .. "'s generator is out of its " .. kind.gas .. "'s reach")
        end
    end
    if kind.pamphlet then
        expect(site.house ~= nil and metaGrid:getRoomAt(site.house[1], site.house[2], 0) ~= nil,
            site.name .. "'s pamphlet is in no building")
    end
end

-- Every site's spots make sense on the map: banks and crates in a room (banks only work indoors),
-- panels outdoors, wall panels on a building's wall, garden lights at a building, arrow boards
-- outdoors with a facing, homestead installations as expectHomesteadSpots says; each site has a
-- unique name, a known kind, and the spots its kind uses, as many panel spots as the kind may
-- place. Every name a world that rolled all sites at once stands for is a site's, since a renamed
-- site would be rolled again in such worlds.
Helpers.check("sitesPlacedSensibly", function(expect)
    local SolarSites = RenewableEnergy.SolarSites
    local metaGrid = getWorld():getMetaGrid()
    local sites = SolarSites.sites()
    expect(#sites > 0, "this map has no solar sites")
    local names = {}
    for _, site in ipairs(sites) do
        expect(not names[site.name], "two sites are named " .. tostring(site.name))
        names[site.name] = true
        local kind = SolarSites.KINDS[site.kind]
        if expect(kind ~= nil, site.name .. " is of no known kind " .. tostring(site.kind)) then
            for _, panel in ipairs(site.panels or {}) do
                local x, y, z, mount, facing = panel[1], panel[2], panel[3], panel[4], panel[5]
                local where = site.name .. " panel at " .. x .. "," .. y .. "," .. z
                local kindOf = Sprites.kindOf(SolarSites.mountSprite(mount, facing))
                expect(kindOf == "flat" or kindOf == "wall" or kindOf == "rack", where .. " names no mount tile")
                expect(metaGrid:getRoomAt(x, y, z) == nil, where .. " is indoors")
                if mount == "wallMetal" then
                    expect(metaGrid:getRoomAt(x, y - 1, z) ~= nil, where .. " has no building wall behind it")
                end
            end
            local panels = #(site.panels or {})
            if kind.panels then
                expect(panels >= kind.panels.min and panels <= kind.panels.max, string.format(
                    "%s has %d panel spots, its kind places %d to %d", site.name, panels, kind.panels.min, kind.panels.max))
            else
                expect(panels == 0, site.name .. " has panel spots its kind never places")
            end
            for _, field in ipairs({ "bank", "crate" }) do
                if kind[field] then
                    local spot = site[field]
                    expect(spot ~= nil and metaGrid:getRoomAt(spot[1], spot[2], spot[3]) ~= nil,
                        site.name .. "'s " .. field .. " is in no room")
                end
            end
            if kind.gardenLights then
                expect(site.house ~= nil and metaGrid:getRoomAt(site.house[1], site.house[2], 0) ~= nil,
                    site.name .. "'s garden lights are at no building")
            end
            if ARROW_BOARD_KINDS[site.kind] then
                expect(site.arrowBoard ~= nil, site.name .. " has no arrow board spot")
            end
            if site.arrowBoard then
                local spot = site.arrowBoard
                expect(metaGrid:getRoomAt(spot[1], spot[2], spot[3]) == nil and IsoDirections[spot[4]] ~= nil,
                    site.name .. "'s arrow board is indoors or faces nowhere")
            end
            expectHomesteadSpots(expect, metaGrid, site, kind)
        end
    end
    for _, name in ipairs(SolarSites.ROLLED_AT_ONCE) do
        expect(names[name], "a world that rolled every site at once stands for " .. name .. ", which is no site")
    end
end)
