-- The fixed spots of FixedSpawns.lua, by the map they are on: { x, y, z, kind, facing }. kind is
-- "crate" or a panel mount of RenewableEnergy.Sprites, facing the side a rack or wall panel faces.
-- Places where someone in 1993 would have had solar: farms, hardware, camping and outdoor stores,
-- a ranger station, a remote control building and factories that made batteries, wire and radios.
-- Crates stand on an empty floor square of a room; racks on open ground; wall panels on the
-- outside of a south wall; flat panels on a flat roof. Each was read off the map's lotheader and
-- lotpack files of build 42.21.
return {
    ["Muldraugh, KY"] = {
        -- Farms: a rack by the house, a crate in the barn.
        { 8795, 11612, 0, "rack", "S" }, -- east of Rosewood
        { 8797, 11630, 0, "crate" },
        { 10576, 7197, 0, "rack", "S" }, -- west of West Point
        { 10526, 7165, 0, "crate" },
        { 10487, 10082, 0, "rack", "S" }, -- west of Muldraugh
        { 10450, 10107, 0, "crate" },
        { 7341, 5985, 0, "wall", "S" }, -- south of Riverside
        { 7351, 6014, 0, "crate" },
        { 4025, 10111, 0, "rack", "S" }, -- north of Echo Creek
        -- Hardware stores.
        { 8178, 11295, 0, "crate" }, -- Rosewood
        { 7465, 8396, 0, "crate" }, -- Fallas Lake
        { 7463, 8396, 1, "flat" },
        { 2076, 5887, 0, "crate" }, -- Brandenburg
        { 13946, 4863, 0, "crate" }, -- Valley Station general store
        { 13943, 4865, 1, "flat" },
        -- Camping, outdoor and garden stores.
        { 3807, 8555, 0, "crate" }, -- Coalfield
        { 3803, 8558, 0, "wall", "S" },
        { 7135, 6143, 0, "crate" }, -- Doe Valley Lake
        { 352, 9923, 0, "crate" }, -- Ekron
        { 3465, 11511, 0, "crate" }, -- Echo Creek garden centre
        -- Deerhead Lake ranger station.
        { 4686, 8600, 0, "crate" },
        { 4683, 8603, 0, "wall", "S" },
        { 4688, 8603, 0, "wall", "S" },
        -- The control building in the woods west of Riverside.
        { 4832, 6286, 0, "wall", "S" },
        { 4833, 6286, 0, "wall", "S" },
        { 4832, 6288, 0, "rack", "S" },
        -- Louisville factories: batteries, radios, wire.
        { 12203, 1262, 0, "crate" },
        { 12555, 3703, 0, "crate" },
        { 12552, 3716, 0, "wall", "S" },
        { 12187, 1459, 0, "crate" },
        { 12170, 1455, 1, "flat" },
        -- Dixie trailer park: the warehouse and a mobile home.
        { 11612, 8844, 0, "crate" },
        { 11715, 8833, 0, "rack", "S" },
    },
}
