require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Sprites"

-- World spawns (WorldSpawns.lua, Distributions.lua): banks, crates and cracked modules the world
-- places and stocks on the authority (RenewableEnergyTestServerSpawns.lua). Arrow boards are in
-- RenewableEnergyTestsArrowBoard*.lua.

local T = RenewableEnergyTest
local test, expect, serverCheck = T.test, T.expect, T.serverCheck

local Sprites = RenewableEnergy.Sprites

local MODULE = RenewableEnergy.Specs.factoryModule

-- This client's copy of the first object of `sprite` on `square`, and how many items its
-- container holds (nil without one).
local function copyOf(square, sprite)
    local object = T.objectWithSprite(square, sprite)
    local container = object and object:getContainer()
    return object, container and container:getItems():size()
end

-- Stock names of WorldSpawns.BANK_STOCK, one per bank tier.
local SPAWNED_BANKS = { "shed", "electronicsStorage", "powerYard" }

-- A bank appears stocked with era batteries at a part charge, explored so that neither its room's
-- loot nor loot respawn ever adds to it, and players see what it holds. It was installed, so it is
-- connected, unlike one a player places. Placing needs no player, as on a dedicated server.
test("renewable_energy_world_bank_spawns_stocked", {
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local squares = T.need(self, T.squares(self, #SPAWNED_BANKS, { indoors = true }), "free indoor squares for banks")
        if not squares then return end
        self.banks = {}
        T.batch(function()
            for i, stockName in ipairs(SPAWNED_BANKS) do
                local square = squares[i]
                T.server(self, "worldBank", T.at(square, { stock = stockName }))
                T.step(function()
                    local bank = self.server.worldBank
                    bank.square, bank.stockName = square, stockName
                    self.banks[i] = bank
                    T.need(self, bank.placed, "a " .. stockName .. " bank")
                end)
            end
            T.server(self, "worldSpawnStock", { names = SPAWNED_BANKS })
        end)
        T.waitFor(self, function()
            for _, bank in ipairs(self.banks) do
                if select(2, copyOf(bank.square, bank.sprite)) ~= bank.stock.items then
                    return false
                end
            end
            return true
        end, "this client's copies of the banks with all they hold")
    end,
    validate = function(self)
        local stocks = self.server.worldSpawnStock.banks
        for _, bank in ipairs(self.banks) do
            local stock = stocks[bank.stockName]
            local what = "the " .. bank.stockName .. " bank"
            local count = #bank.stock.charges
            expect(Sprites.kindOf(bank.sprite) == stock.sprite, what .. " has the wrong tile")
            expect(bank.stock.explored, what .. " is not explored")
            local copy = copyOf(bank.square, bank.sprite)
            expect(copy ~= nil and copy:isConnected(), what .. " isn't connected on this client")
            T.expectSaneRange(stock.batteries, "the battery count of " .. what)
            expect(T.inRange(count, stock.batteries),
                count .. " batteries in " .. what .. ", expected " .. stock.batteries.min .. " to " .. stock.batteries.max)
            T.expectFoundCharges(bank.stock.charges, what)
        end
    end,
})

-- A room seen for the first time never puts a bank on an outdoor square: the world spawn honours
-- the indoors-only rule that placement by a player also obeys (the bank tests cover that rule).
test("renewable_energy_world_bank_spawn_refused_outdoors", {
    run = function(self)
        local square = T.square(self, nil, "a free outdoor square")
        if not square then return end
        T.server(self, "worldBank", T.at(square, { stock = "shed" }))
    end,
    validate = function(self)
        expect(not self.server.worldBank.placed, "a bank was placed outdoors")
        expect(not self.server.worldBank.boxOnSquare, "a bank's tile stands outdoors")
    end,
})

-- Vanilla brick walls: one on a square's north edge, one on its west edge.
local WALL_NORTH, WALL_WEST = "walls_exterior_house_01_1", "walls_exterior_house_01_0"
-- Where a test wall goes for a bank square, and the facing that puts the bank's back to it: the
-- wall tile, and the square it stands on as a step from the bank's.
local BACKS = {
    { wall = WALL_NORTH, dx = 0, dy = 0, facing = "S" },
    { wall = WALL_WEST, dx = 0, dy = 0, facing = "E" },
    { wall = WALL_NORTH, dx = 0, dy = 1, facing = "N" },
    { wall = WALL_WEST, dx = 1, dy = 0, facing = "W" },
}

-- Whether `square` has no wall on any edge.
local function unwalled(square)
    for _, step in ipairs({ { 0, -1 }, { -1, 0 }, { 0, 1 }, { 1, 0 } }) do
        local beside = getSquare(square:getX() + step[1], square:getY() + step[2], square:getZ())
        if not beside or square:isWallTo(beside) then
            return false
        end
    end
    return true
end

-- A world bank stands with its back to the wall of its square, on whichever edge the wall is, as
-- furniture does.
test("renewable_energy_world_bank_backs_onto_wall", {
    run = function(self)
        local free = T.need(self, T.squares(self, 24, { indoors = true }), "free indoor squares for banks") or {}
        -- Squares with no wall of their own, none beside another, so no test wall stands at
        -- another's edge.
        local picked = {}
        for _, square in ipairs(free) do
            local apart = unwalled(square)
            for _, other in ipairs(picked) do
                apart = apart and math.max(math.abs(other:getX() - square:getX()), math.abs(other:getY() - square:getY())) > 1
            end
            if apart and #picked < #BACKS then
                table.insert(picked, square)
            end
        end
        if not T.need(self, #picked == #BACKS and picked, #BACKS .. " unwalled indoor squares apart") then return end
        self.placed = {}
        for i, back in ipairs(BACKS) do
            local square = picked[i]
            T.placeTile(self, getSquare(square:getX() + back.dx, square:getY() + back.dy, square:getZ()), back.wall)
            T.server(self, "worldBank", T.at(square, { stock = "shed" }))
            T.step(function() self.placed[i] = self.server.worldBank.sprite end)
        end
    end,
    validate = function(self)
        for i, back in ipairs(BACKS) do
            local sprite = self.placed[i]
            local kind, facing = Sprites.kindOf(sprite)
            expect(kind == "batteryBoxWood" and facing == back.facing, "the bank with a wall on the "
                .. ({ S = "north", E = "west", N = "south", W = "east" })[back.facing] .. " edge stands as "
                .. tostring(sprite) .. ", facing " .. tostring(facing) .. ", not " .. back.facing)
        end
    end,
})

-- Bank tiers whose tile is a battery box, which has no slot for a charge controller.
local BOX_TILES = { batteryBoxWood = true, batteryBoxMetal = true }

-- Each part turns up when the roll comes in under its chance × the misc loot option, in a farm
-- storage rack, which has a slot for every part; and a battery box never comes with a charge
-- controller.
serverCheck("renewable_energy_world_bank_stock_parts", "bankStockParts", { stock = "farmStorage", boxTiles = BOX_TILES })

-- With the battery and misc loot options at 0, world banks spawn empty, even with the lowest roll
-- there is.
test("renewable_energy_world_bank_stock_option_zero", {
    sandbox = { LRMBatteries = 0, LRMMisc = 0 },
    run = function(self) T.server(self, "bankStockCount", { stock = "electronicsStorage", roll = 0 }) end,
    validate = function(self)
        local items = self.server.bankStockCount.items
        expect(items == 0, items .. " items in a bank with the options at 0")
    end,
})

-- How each wear profile wears a battery, and its duds.
serverCheck("renewable_energy_world_bank_battery_wear", "batteryWear")

-- How found inverters and controllers wear, their duds, and that banks, crates and the arrow
-- board's battery box hand them out worn.
serverCheck("renewable_energy_world_part_wear", "partWear")

-- A placed bank's batteries are worn as its stock says, so a farm storeroom's come more worn than
-- an electronics store's: at middling rolls every battery is at its stock's profile's mean.
local WORN_STOCKS = { "farmStorage", "electronicsStorage" }
test("renewable_energy_world_bank_batteries_worn_by_stock", {
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local squares = T.need(self, T.squares(self, #WORN_STOCKS, { indoors = true }), "free indoor squares for banks")
        if not squares then return end
        self.banks = {}
        T.batch(function()
            for i, stockName in ipairs(WORN_STOCKS) do
                local square = squares[i]
                T.server(self, "worldBank", T.at(square, { stock = stockName, roll = 0.5 }))
                T.step(function()
                    self.banks[stockName] = self.server.worldBank
                    T.need(self, self.server.worldBank.placed, "a " .. stockName .. " bank")
                end)
            end
            T.server(self, "worldSpawnStock", { names = WORN_STOCKS })
        end)
    end,
    validate = function(self)
        local answer = self.server.worldSpawnStock
        local means = {}
        for _, stockName in ipairs(WORN_STOCKS) do
            local wearName = answer.banks[stockName].wear
            local condition = answer.batteryWear[wearName].mean
            means[stockName] = condition
            local conditions = self.banks[stockName].stock.batteryConditions
            local wrong = {}
            for _, found in ipairs(conditions) do
                if found ~= condition then table.insert(wrong, found) end
            end
            expect(#conditions > 0 and #wrong == 0, string.format("a %s bank holds %d batteries, of which %s aren't at its %s profile's %d",
                stockName, #conditions, table.concat(wrong, ", "), wearName, condition))
        end
        expect(means.farmStorage < means.electronicsStorage, "a farm storeroom's batteries come at "
            .. means.farmStorage .. ", no more worn than an electronics store's " .. means.electronicsStorage)
    end,
})

-- A battery box a garage or storage unit spawns may have the panel that charged it beside it: with
-- the rolls just under its stock's module chance, as many modules as the stock says lie on the
-- floor next to the bank, in its room, at a site module's condition (weathered, as that roll also
-- misses the cracked share); with the rolls at the chance, none.
test("renewable_energy_world_bank_modules_beside", {
    sandbox = { LRMSolarPanels = 1 },
    run = function(self)
        local squares = T.need(self, T.squares(self, 2, { indoors = true }), "free indoor squares for banks")
        if not squares then return end
        T.server(self, "worldSpawnStock", { names = { "shed" } })
        T.step(function()
            local chance = self.server.worldSpawnStock.banks.shed.modules.chance
            self.cases = {}
            for i, roll in ipairs({ chance - T.UNDER, chance }) do
                local square = squares[i]
                T.server(self, "bankModulesBeside", T.at(square, { stock = "shed", roll = roll }))
                T.step(function() self.cases[i] = self.server.bankModulesBeside end)
            end
        end)
    end,
    validate = function(self)
        local answer = self.server.worldSpawnStock
        local spec, weathered = answer.banks.shed.modules, answer.weathered
        local under, at = self.cases[1], self.cases[2]
        local found = #under.conditions
        expect(under.laid == found and T.inRange(found, spec), string.format("under the chance it laid %d and %d lie by the bank, expected %d to %d",
            under.laid, found, spec.min, spec.max))
        expect(under.inRoom, "a module lies outside the bank's room")
        for _, condition in ipairs(under.conditions) do
            expect(T.inRange(condition, weathered), "a module beside the bank is at condition " .. condition)
        end
        expect(at.laid == 0 and #at.conditions == 0, "at the chance " .. #at.conditions .. " modules lie by the bank")
    end,
})

-- The item count from which vanilla's container overlays show a container full rather than
-- holding a few items (ContainerOverlays.updateContainerOverlaySprite).
local FEW_ITEMS = 7

-- A crate appears stocked with modules at cracked or weathered conditions and batteries at a part
-- charge, as many as CRATE_STOCK's kit says, explored, showing its full or closed lid by how much
-- it holds, and players see what it holds and its lid.
test("renewable_energy_world_crate_spawns_stocked", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local square = T.square(self, { indoors = true }, "a free indoor square")
        if not square then return end
        T.batch(function()
            T.server(self, "worldCrate", T.at(square, { stock = "kit" }))
            T.server(self, "worldSpawnStock", { names = {}, crate = "kit" })
        end)
        T.waitFor(self, function()
            local crate = self.server.worldCrate
            local copy, items = copyOf(square, Sprites.crate)
            local overlay = copy and copy:getOverlaySprite()
            return items == crate.stock.items and overlay ~= nil and overlay:getName() == crate.overlay
        end, "this client's copy of the crate with all it holds and its lid")
    end,
    validate = function(self)
        local crate, ranges = self.server.worldCrate, self.server.worldSpawnStock
        local lines = ranges.crate
        expect(crate.stock.explored, "the crate is not explored")
        local conditions = crate.stock.modules
        expect(T.inRange(#conditions, lines[MODULE]), #conditions .. " modules in the crate")
        for _, condition in ipairs(conditions) do
            expect(T.inRange(condition, ranges.cracked) or T.inRange(condition, ranges.weathered), "a crate module is at condition " .. condition)
        end
        local charges = crate.stock.charges
        expect(T.inRange(#charges, lines["RenewableEnergy.DeepCycleBattery"]), #charges .. " batteries in the crate")
        T.expectFoundCharges(charges, "the crate")
        local overlays = Sprites.crateOverlays
        local lid = crate.stock.items < FEW_ITEMS and overlays.closed or overlays.full
        expect(crate.overlay == lid, "the crate holding " .. crate.stock.items .. " items shows " .. tostring(crate.overlay))
    end,
})

-- Cracked modules -------------------------------------------------------------------------------

-- Farm storage shelves get cracked modules, at cracked conditions, at a chance that follows the
-- Solar Panels loot option, and a bedroom's furniture none.
serverCheck("renewable_energy_world_cracked_modules", "crackedModules")

-- Vanilla's barns, farm storerooms and survivalist camps are dressed with the mod's magazines,
-- pamphlet and charger, the biogas and wind magazines weighted up.
serverCheck("renewable_energy_world_rural_clutter", "ruralClutter")

-- A room seen for the first time gets a bank of its room's stock (a shed's or garage's a wooden
-- battery box, a farm storeroom's a wooden rack) on a roll just under one in its odds × the Battery
-- Bank Spawn setting's rarity and none at it, and none at all at None or in a room not listed. A
-- garage gets a crate of solar gear on a roll just under its crate odds and none at it, while its
-- likelier bank comes up either way.
local SEEN_ROOMS = {
    { trial = { room = "shed", setting = 3, edge = "bank", roll = "under" }, bank = "batteryBoxWood" },
    { trial = { room = "shed", setting = 3, edge = "bank", roll = "at" } },
    { trial = { room = "shed", setting = 1, roll = 0 } },
    { trial = { room = "farmstorage", setting = 4, roll = 0 }, bank = "batteryRackWood" },
    { trial = { room = "kitchen", setting = 4, roll = 0 } },
    { trial = { room = "garagestorage", setting = 2, edge = "crate", roll = "under" }, bank = "batteryBoxWood", crate = true },
    { trial = { room = "garagestorage", setting = 2, edge = "crate", roll = "at" }, bank = "batteryBoxWood" },
}

test("renewable_energy_world_bank_rooms_seen_first_time", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local square = T.square(self, { indoors = true }, "a free indoor square")
        if not square then return end
        local trials = {}
        for i, entry in ipairs(SEEN_ROOMS) do
            trials[i] = entry.trial
        end
        T.server(self, "seenRoom", T.at(square, { trials = trials }))
    end,
    validate = function(self)
        for i, entry in ipairs(SEEN_ROOMS) do
            local trial, tiles = entry.trial, {}
            -- By kind: a bank stands in whichever facing puts its back to a wall.
            for _, tile in ipairs(self.server.seenRoom.results[i].tiles) do
                table.insert(tiles, Sprites.kindOf(tile) or tile)
            end
            local wanted = {}
            if entry.bank then table.insert(wanted, entry.bank) end
            if entry.crate then table.insert(wanted, "crate") end
            table.sort(wanted)
            table.sort(tiles)
            expect(table.concat(tiles, ",") == table.concat(wanted, ","), string.format(
                "a %s seen at setting %d with roll %s placed '%s', expected '%s'", trial.room, trial.setting,
                tostring(trial.roll) .. (trial.edge and " " .. trial.edge .. " odds" or ""), table.concat(tiles, ","),
                table.concat(wanted, ",")))
        end
    end,
})
