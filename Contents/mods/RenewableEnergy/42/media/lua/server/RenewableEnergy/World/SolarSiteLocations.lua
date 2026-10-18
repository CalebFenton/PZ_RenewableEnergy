-- The named solar sites of SolarSites.lua, by the map they are on. Places where someone in 1993
-- would have had solar: stock tank pumps out in the pastures, farms off the grid, campers,
-- telephone relay sheds on the hills, the power company's yard, ranger stations, and arrow
-- boards at road works and at the army's checkpoints on the roads into Louisville. Coordinates
-- were read off the map's lotheader and lotpack files.
--
-- A site lists the spots its kind (SolarSites.KINDS) may use:
--   panels: { x, y, z, mount, facing }, mount "flat", "wallMetal", "rackMetal" or "rackWood";
--     flats on a flat roof, wall panels on the outside of a south wall, racks on open ground;
--   bank and crate: { x, y, z }, an empty floor square of a room;
--   house: { x, y }, a square of the building that gets garden lights along its front;
--   arrowBoard: { x, y, z, facing }, the middle of a road lane, facing along the road.
-- A site with `always` skips the Solar Sites roll, so that every world has a few things a
-- player can count on finding; the option at 0 still leaves it out.
return {
    ["Muldraugh, KY"] = {
        -- Stock tank pumps: a pole mount by the big metal water tank of a pasture.
        { kind = "stockTank", name = "Pasture north of Rosewood", panels = { { 8007, 11018, 0, "rackMetal", "S" } } },
        { kind = "stockTank", name = "Pasture south-east of Rosewood", panels = { { 8728, 12422, 0, "rackMetal", "S" } } },
        { kind = "stockTank", name = "Pasture west of Muldraugh", panels = { { 8719, 9442, 0, "rackMetal", "S" } } },
        { kind = "stockTank", name = "Pasture north-west of Muldraugh", panels = { { 9274, 8474, 0, "rackMetal", "S" } } },
        { kind = "stockTank", name = "Pasture west of West Point", panels = { { 10023, 7384, 0, "rackMetal", "S" } } },
        { kind = "stockTank", name = "Pasture by Valley Station", panels = { { 13551, 5010, 0, "rackMetal", "S" } } },
        { kind = "stockTank", name = "Pasture by Brandenburg", panels = { { 1264, 7322, 0, "rackMetal", "S" } } },
        -- Farms: flat panels on the house's flat roof, the battery box inside.
        {
            kind = "farmRoof", name = "Farm south of Riverside",
            panels = {
                { 7343, 5990, 1, "flat" }, { 7344, 5990, 1, "flat" }, { 7345, 5991, 1, "flat" }, { 7346, 5990, 1, "flat" },
            },
            bank = { 7344, 5991, 0 }, house = { 7340, 5993 },
        },
        {
            kind = "farmRoof", name = "Farm east of Rosewood",
            panels = {
                { 8474, 11548, 1, "flat" }, { 8475, 11549, 1, "flat" }, { 8476, 11548, 1, "flat" }, { 8474, 11550, 1, "flat" },
            },
            bank = { 8468, 11553, 0 }, house = { 8470, 11552 },
        },
        {
            kind = "farmRoof", name = "Barn west of West Point",
            panels = {
                { 9789, 7742, 1, "flat" }, { 9790, 7743, 1, "flat" }, { 9791, 7742, 1, "flat" }, { 9789, 7744, 1, "flat" },
            },
            bank = { 9790, 7749, 0 }, house = { 9794, 7749 },
        },
        -- Campers: mobile homes and a cabin with panels on the roof.
        {
            kind = "camper", name = "Scenic Grove Trailer Park",
            panels = { { 5364, 5941, 1, "flat" }, { 5366, 5942, 1, "flat" } }, bank = { 5368, 5941, 0 },
        },
        {
            kind = "camper", name = "Dixie Trailer Park",
            panels = { { 11689, 8776, 1, "flat" }, { 11690, 8778, 1, "flat" } }, bank = { 11689, 8775, 0 },
        },
        {
            kind = "camper", name = "Bright Valley Trailer Park",
            panels = { { 2673, 6220, 1, "flat" }, { 2675, 6221, 1, "flat" } }, bank = { 2678, 6222, 0 },
        },
        {
            kind = "camper", name = "Camp Fitzgerald cabin",
            panels = { { 13857, 6642, 1, "flat" }, { 13858, 6644, 1, "flat" } }, bank = { 13864, 6645, 0 },
        },
        -- Knox Telecommunications relay sheds at the radio masts on the hills.
        {
            kind = "relay", name = "Relay shed north of Brandenburg",
            panels = { { 1620, 5755, 0, "rackMetal", "S" }, { 1620, 5758, 0, "rackMetal", "S" } }, bank = { 1626, 5760, 0 },
        },
        {
            kind = "relay", name = "Relay shed by Irvington",
            panels = { { 1510, 14858, 0, "rackMetal", "S" }, { 1512, 14858, 0, "rackMetal", "S" } }, bank = { 1516, 14852, 0 },
        },
        {
            kind = "relay", name = "Relay hut west of Irvington",
            panels = { { 884, 12806, 0, "rackMetal", "S" }, { 884, 12814, 0, "rackMetal", "S" } }, bank = { 889, 12814, 0 },
        },
        {
            kind = "relay", name = "Relay station west of Riverside",
            panels = { { 4831, 6288, 0, "rackMetal", "S" }, { 4831, 6273, 0, "rackMetal", "S" } }, bank = { 4836, 6278, 0 },
        },
        -- Deer Valley Power's substation west of Muldraugh, with the yard office.
        {
            kind = "powerYard", name = "Deer Valley Power yard",
            panels = { { 10376, 10064, 0, "rackMetal", "S" }, { 10376, 10066, 0, "rackMetal", "S" } },
            bank = { 10380, 10062, 0 }, crate = { 10382, 10062, 0 },
        },
        -- Ranger stations: wall panels on the south side, the battery box in the office.
        {
            kind = "ranger", name = "Deerhead Lake ranger station",
            panels = {
                { 4683, 8603, 0, "wallMetal", "S" }, { 4688, 8603, 0, "wallMetal", "S" },
                { 4669, 8603, 0, "wallMetal", "S" }, { 4690, 8603, 0, "wallMetal", "S" },
            },
            bank = { 4664, 8601, 0 },
        },
        {
            kind = "ranger", name = "Doe Valley ranger station",
            panels = {
                { 6997, 6033, 0, "wallMetal", "S" }, { 7000, 6033, 0, "wallMetal", "S" },
                { 6997, 6035, 0, "rackMetal", "S" }, { 7000, 6036, 0, "rackMetal", "S" },
            },
            bank = { 6998, 6025, 0 },
        },
        -- Road works with a solar arrow board.
        { kind = "roadWorks", name = "Road works north of Muldraugh", arrowBoard = { 10598, 9128, 0, "N" }, always = true },
        { kind = "roadWorks", name = "Road works east of Riverside", arrowBoard = { 7053, 5467, 0, "E" } },
        { kind = "roadWorks", name = "Road works in Rosewood", arrowBoard = { 8200, 11507, 0, "N" } },
        -- The army's checkpoints at the Louisville fence, an arrow board a little short of the
        -- barrier: on the highway at the back of the queue of cars that never got through, the
        -- camp beyond it; and on two country roads east of it.
        { kind = "checkpoint", name = "Checkpoint on the highway south of Louisville", arrowBoard = { 12519, 4628, 0, "N" }, always = true },
        { kind = "checkpoint", name = "Checkpoint on the road south-east of Louisville", arrowBoard = { 13425, 4117, 0, "N" } },
        { kind = "checkpoint", name = "Checkpoint on the road east of Louisville", arrowBoard = { 14534, 4068, 0, "N" } },
    },
}
