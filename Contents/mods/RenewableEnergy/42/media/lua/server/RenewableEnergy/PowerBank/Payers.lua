-- What each running payer must supply, and who pays for an appliance that more than one running
-- payer reaches: one of them, alone. Vanilla bills every generator for everything in its reach,
-- so overlapping generators each burn fuel for the same fridge, and banks, measuring their load the
-- same way, would each drain for it.
--
-- A payer is a running vanilla generator or a bank that may power its squares. The nearest that
-- reaches an appliance pays for it, unless that leaves a bank more than its inverters carry: then
-- the bank hands what lies farthest from it to the nearest other payer with room for it, until it
-- fits. A generator has room for anything. A bank that still doesn't fit overloads and drops out,
-- and the rest share again without it. Nearest is by tiles, each level counting as one; a tie goes
-- to the lower position (Squares.placeKey), so every payer agrees on who pays. A bank measures its
-- own load against the payers that may run now (Payers.scan). A generator's bill is vanilla's
-- totalPowerUsing, which the engine rebuilds whenever anything in its reach switches
-- (IsoGenerator.setSurroundingElectricity) and burns at the hour (IsoGenerator.update); so its
-- share is set after each rebuild, before the next hour. A generator also pays for an unwired
-- treadmill it powers, which vanilla doesn't know of, for the load of each bank it backs up
-- (Bank.backupCarriesLoad), and for the chargers of each bank that charges from it, within what its
-- gas line carries (GasKit.capW).

if isClient() then return end

local Places = require "RenewableEnergy/Places"
local Sprites = require "RenewableEnergy/Sprites"
local Specs = require "RenewableEnergy/Specs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local Loads = require "RenewableEnergy/PowerBank/Loads"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local GeneratorReach = require "cf_commonlib/GeneratorReach"
local PlaceTracker = require "cf_commonlib/PlaceTracker"
local Squares = require "cf_commonlib/Squares"
local Telemetry = require "cf_commonlib/Telemetry"

local Payers = {}

local EPSILON = 1e-6

local function generatorSprites()
    local sprites = {}
    for name in pairs(Sprites.gasKit.bySprite) do
        table.insert(sprites, name)
    end
    return sprites
end

-- Generators found as their chunk loads, as a player starts one (ISActivateGenerator.complete, in
-- Fumes), and as a bank comes on one in its reach. A generator dropped from the hands fires no
-- event, so it is found once started.
local generators = PlaceTracker.new({ sprites = generatorSprites(), matches = GeneratorReach.isVanillaGenerator })

--- Track `generator`, found running some other way.
function Payers.track(generator)
    generators:add(generator)
end

--- fn(generator) for every loaded vanilla generator that can take a gas kit.
function Payers.eachGenerator(fn)
    generators:each(fn)
end

local function newPayer(x, y, z, fields)
    fields.x, fields.y, fields.z, fields.key = x, y, z, Squares.placeKey(x, y, z)
    return fields
end

--- The payer a bank is: it carries what its inverters do, and anything while a backup generator
--- carries its load.
function Payers.ofBank(bank)
    return newPayer(bank.x, bank.y, bank.z, { capW = not bank:backupCarriesLoad() and bank:limitW() or nil })
end

local function ofGenerator(generator)
    return newPayer(generator:getX(), generator:getY(), generator:getZ(), { generator = generator })
end

-- A bank may run unless something besides its load keeps it off: an overload is for the share to
-- decide (Payers.scan), so a bank that overloaded comes back once its share fits.
local function bankMayRun(bank)
    return bank:canCarryLoad() and not bank.empty
end

--- The payers that may run now: the running generators and the banks that may.
function Payers.running()
    local list = {}
    generators:each(function(generator)
        if generator:isActivated() then
            table.insert(list, ofGenerator(generator))
        end
    end)
    PowerBank.each(function(bank)
        if bankMayRun(bank) then
            table.insert(list, Payers.ofBank(bank))
        end
    end)
    return list
end

local function reaches(payer, x, y, z)
    return GeneratorReach.covers(payer.x, payer.y, payer.z, x, y, z)
end

--- `payer` and the payers in `payers` that reach any square it does: those it may share with.
function Payers.sharers(payer, payers)
    local radius, levels = GeneratorReach.range()
    local span = 2 * radius
    local list = { payer }
    for _, other in ipairs(payers) do
        local dx, dy = other.x - payer.x, other.y - payer.y
        if other.key ~= payer.key and math.abs(other.z - payer.z) <= 2 * levels and dx * dx + dy * dy <= span * span then
            table.insert(list, other)
        end
    end
    return list
end

-- `payer` and every payer of `payers` linked to it by sharers of sharers: all whose shares can move
-- each other's. Sorted by place, so whichever of them asks, they share alike.
local function sharingGroup(payer, payers)
    local group, seen, i = { payer }, { [payer.key] = true }, 1
    while i <= #group do
        for _, other in ipairs(Payers.sharers(group[i], payers)) do
            if not seen[other.key] then
                seen[other.key] = true
                table.insert(group, other)
            end
        end
        i = i + 1
    end
    table.sort(group, function(a, b) return a.key < b.key end)
    return group
end

-- Every draw in the reach of any of `group`, each once, in a fixed order; and by member key, the
-- running generators powering its square, which are tracked from then on.
local function drawsOf(group)
    local draws, seen, found = {}, {}, {}
    for _, member in ipairs(group) do
        local mine = {}
        found[member.key] = mine
        local square = getCell():getGridSquare(member.x, member.y, member.z)
        if square then
            Loads.eachDraw(square, function(draw)
                local place = Squares.placeKey(draw.x, draw.y, draw.z)
                local onSquare = seen[place] or {}
                seen[place] = onSquare
                if not onSquare[draw.index] then
                    onSquare[draw.index] = true
                    draw.place = place
                    table.insert(draws, draw)
                end
            end, function(generator)
                generators:add(generator)
                table.insert(mine, generator)
            end)
        end
    end
    table.sort(draws, function(a, b) return a.place < b.place or (a.place == b.place and a.index < b.index) end)
    return draws, found
end

local function overCap(payer, watts)
    return payer.capW ~= nil and watts > payer.capW + EPSILON
end

-- Who of `payers` pays for each of `draws` (by draw), each payer's watts (by key) and how many
-- draws changed hands: the nearest that reaches it pays; then each payer over its cap, in place
-- order, hands its draws, the farthest first, to the nearest other payer with room for each, until
-- it fits.
local function shareOnce(payers, draws)
    local owner, watts, moved = {}, {}, 0
    for _, payer in ipairs(payers) do
        watts[payer.key] = 0
    end
    for _, draw in ipairs(draws) do
        local payer = Places.nearest(payers, draw.x, draw.y, draw.z, nil, function(each)
            return reaches(each, draw.x, draw.y, draw.z)
        end)
        if payer then
            owner[draw] = payer
            watts[payer.key] = watts[payer.key] + draw.watts
        end
    end
    for _, payer in ipairs(payers) do
        if overCap(payer, watts[payer.key]) then
            local mine = {}
            for _, draw in ipairs(draws) do
                if owner[draw] == payer then
                    table.insert(mine, draw)
                end
            end
            -- Farthest first: the reverse of nearest first, ties included.
            Places.sortNearest(mine, payer.x, payer.y, payer.z)
            for i = #mine, 1, -1 do
                if not overCap(payer, watts[payer.key]) then break end
                local draw = mine[i]
                local to = Places.nearest(payers, draw.x, draw.y, draw.z, nil, function(each)
                    return each ~= payer and reaches(each, draw.x, draw.y, draw.z)
                        and not overCap(each, watts[each.key] + draw.watts)
                end)
                if to then
                    owner[draw] = to
                    watts[payer.key] = watts[payer.key] - draw.watts
                    watts[to.key] = watts[to.key] + draw.watts
                    moved = moved + 1
                end
            end
        end
    end
    return owner, watts, moved
end

-- Who of `group` pays for each of `draws`: shareOnce, again without the banks it leaves over their
-- cap, until every bank left fits. A bank left over its cap pays, as its overload, for what it held
-- when it dropped out. Also the draws the last round moved, and the rounds it took.
local function share(group, draws)
    local payers, tripped, rounds = group, {}, 0
    while true do
        local owner, watts, moved = shareOnce(payers, draws)
        rounds = rounds + 1
        local fitting = {}
        for _, payer in ipairs(payers) do
            if overCap(payer, watts[payer.key]) then
                tripped[payer.key] = owner
            else
                table.insert(fitting, payer)
            end
        end
        if #fitting == #payers then
            return owner, tripped, moved, rounds
        end
        payers = fitting
    end
end

-- The sharing of each group worked out during one pass of every bank (Payers.duringPass), by its
-- members and their caps, so each group is scanned once per pass, not once per member. Nothing a
-- pass does switches an appliance; outside a pass, every scan looks again.
local sharedThisPass

--- Run `fn` as one pass of every bank, sharing each group's scan among its members.
function Payers.duringPass(fn)
    sharedThisPass = {}
    local ok, err = pcall(fn)
    sharedThisPass = nil
    if not ok then error(err) end
end

local function groupKey(group)
    local parts = {}
    for i, member in ipairs(group) do
        parts[i] = string.format("%.0f:%s", member.key, tostring(member.capW))
    end
    return table.concat(parts, ";")
end

-- One line per sharing worked out: the group, what it scanned, what changed hands and who
-- overloaded, and how long it took.
local sharingLog = Telemetry.channel("RenewableEnergy.bankSharing")

local function placesOf(group, only)
    local parts = {}
    for _, member in ipairs(group) do
        if not only or only[member.key] then
            table.insert(parts, member.x .. "," .. member.y .. "," .. member.z
                .. (member.generator and ":generator" or (":" .. string.format("%.0f", member.capW or -1))))
        end
    end
    return table.concat(parts, ";")
end

-- The draws of `group`, the generators by member key, who pays for each draw and what each bank
-- that overloaded held (share).
local function sharingOf(group)
    local key = sharedThisPass and groupKey(group)
    local sharing = key and sharedThisPass[key]
    if not sharing then
        local started = sharingLog.on and Telemetry.now()
        local draws, found = drawsOf(group)
        local owner, tripped, moved, rounds = share(group, draws)
        sharing = { draws = draws, found = found, owner = owner, tripped = tripped }
        if key then
            sharedThisPass[key] = sharing
        end
        if started then
            sharingLog:log("payers", placesOf(group), "draws", #draws, "moved", moved, "rounds", rounds,
                "tripped", placesOf(group, tripped), "inPass", key ~= nil, "ms", Telemetry.now() - started)
        end
    end
    return sharing
end

--- What the payer `payer` pays for of its share among `payers` (Payers.running, it
--- among them or not), and the running generators powering its square (`generators`), which are
--- tracked from then on. With `gridGone`, what is switched on in its reach whether or not the grid
--- powers it now. A bank whose share overloads it gets what it held as it dropped out.
function Payers.scan(payer, payers, gridGone)
    local sharing = sharingOf(sharingGroup(payer, payers))
    local owner = sharing.tripped[payer.key] or sharing.owner
    local vanilla = payer.generator ~= nil
    local load = Loads.new(payer)
    load.generators = sharing.found[payer.key]
    for _, draw in ipairs(sharing.draws) do
        if reaches(payer, draw.x, draw.y, draw.z) and Loads.counts(draw, gridGone, vanilla) then
            if owner[draw] and owner[draw].key == payer.key then
                Loads.addDraw(load, draw)
            elseif draw.fuel then
                load.othersFuel = load.othersFuel + draw.fuel
            end
        end
    end
    return load
end

-- Watts of the loads of the banks the generator `payer` carries as their backup.
local function backedW(payer)
    local watts = 0
    PowerBank.each(function(bank)
        local backup = bank.generator
        if backup and backup.running and Squares.samePosition(backup, payer) and bank:shouldPower() then
            watts = watts + bank.loadW
        end
    end)
    return watts
end

local function treadmillInReach(payer)
    local found = false
    Treadmill.eachDrawing(function(tile)
        found = found or reaches(payer, tile:getX(), tile:getY(), tile:getZ())
    end)
    return found
end

-- What the running `generator` powers of its share of `payers` (default: those running now): the
-- load it pays for, plus `backedW`, the banks it carries.
local function loadOf(generator, payers)
    local payer = ofGenerator(generator)
    local load = Payers.scan(payer, payers or Payers.running())
    load.backedW = backedW(payer)
    return load
end

-- The banks whose chargers charge from `generator`, in the order they share what it can give:
-- nearest first, the lower place on a tie (Places.sortNearest).
local function chargingBanks(generator)
    local list = {}
    PowerBank.each(function(bank)
        if bank:chargesFrom(generator) then
            table.insert(list, bank)
        end
    end)
    Places.sortNearest(list, Places.objectPlace(generator))
    return list
end

-- Allocate the chargers' wants from the headroom `cap` (nil: none) leaves after appliances and
-- backup loads. A total is independent of priority, so only a request for one bank's share needs
-- the nearest-first list. Both queries use the same capped allocation; neither builds a table of
-- everyone's shares.
local function allocate(generator, cap, load, target)
    local left = cap and math.max(0, cap - load.watts - load.backedW) or math.huge
    local total, share = 0, 0
    local function take(bank)
        if not bank:chargesFrom(generator) then return end
        local watts = math.min(bank.chargeWantW or 0, left)
        left, total = left - watts, total + watts
        if bank == target then share = watts end
    end
    if target then
        for _, bank in ipairs(chargingBanks(generator)) do
            take(bank)
            if bank == target then return share end
        end
        return 0
    end
    PowerBank.each(take)
    return total
end

--- The watts `generator` delivers: its share of what it powers, the banks it carries, and the
--- chargers of the battery banks that charge from it.
function Payers.deliveredW(generator)
    local load = loadOf(generator)
    return load.watts + load.backedW + allocate(generator, GasKit.capW(generator), load)
end

--- The most watts `bank`'s chargers draw from `generator`: its share of what the gas line's cap
--- leaves (allocate), nothing once the generator's own load takes it all. Nil when the generator
--- isn't on gas, so nothing but the chargers' rating limits them.
function Payers.chargerLimitW(generator, bank)
    local cap = GasKit.capW(generator)
    if not cap then return nil end
    return allocate(generator, cap, loadOf(generator), bank)
end

-- Generators billed their share, by key: { generator, baseFuel (getBasePowerConsumption as fuel),
-- expected (what getTotalPowerUsing reads), othersFuel (vanilla's bill for what others pay),
-- extraFuel (what vanilla doesn't bill) }.
local billed = {}

local function setBill(entry, fuel)
    local generator = entry.generator
    generator:setTotalPowerUsing(math.max(entry.baseFuel, fuel))
    entry.expected = generator:getTotalPowerUsing()
end

local function unbill(key)
    local entry = billed[key]
    billed[key] = nil
    local generator = entry.generator
    if generator:getSquare() and generator:isActivated() then
        generator:setSurroundingElectricity()
    end
end

-- On gas, the load measured for the cap is the one billed, with the same running `payers`, so
-- one scan serves both; off gas, nothing is measured unless the generator shares or carries more.
local function bill(generator, payers, consumption)
    local payer = ofGenerator(generator)
    local shared = #Payers.sharers(payer, payers) > 1
    local cap = GasKit.capW(generator)
    local load = cap and loadOf(generator, payers)
    local charging = allocate(generator, cap, load)
    local backed = load and load.backedW or backedW(payer)
    if not shared and backed == 0 and charging == 0 and not treadmillInReach(payer) then
        if billed[payer.key] then unbill(payer.key) end
        return
    end
    load = load or Payers.scan(payer, payers)
    local treadmillW = Loads.kindW(load, "treadmill")
    local entry = billed[payer.key] or {}
    billed[payer.key] = entry
    -- A chunk reload puts a new generator object at the same key.
    entry.generator = generator
    entry.baseFuel = generator:getBasePowerConsumption() / consumption
    entry.othersFuel = load.othersFuel
    entry.extraFuel = Specs.fuelFromWatts(treadmillW + backed + charging)
    setBill(entry, entry.baseFuel + Specs.fuelFromWatts(load.watts + backed + charging))
end

--- Bill every running generator its share. Each one's rebuilds until the next call keep it
--- (keepShares).
function Payers.billGenerators()
    local consumption = SandboxVars.GeneratorFuelConsumption
    if consumption <= 0 then return end
    local payers = Payers.running()
    local running = {}
    for _, payer in ipairs(payers) do
        if payer.generator then
            running[payer.key] = true
            bill(payer.generator, payers, consumption)
        end
    end
    for key in pairs(billed) do
        if not running[key] then unbill(key) end
    end
end

-- After vanilla rebuilds a billed generator's bill, take off what others pay and add what it
-- doesn't know of, as of the last billing. A stopped or unloaded generator drops out.
local function keepShares()
    local consumption = SandboxVars.GeneratorFuelConsumption
    if consumption <= 0 then return end
    for key, entry in pairs(billed) do
        local generator = entry.generator
        if not generator:getSquare() or not Squares.onSquare(generator) or not generator:isActivated() then
            billed[key] = nil
        else
            local now = generator:getTotalPowerUsing()
            if math.abs(now - entry.expected) > EPSILON then
                setBill(entry, now / consumption - entry.othersFuel + entry.extraFuel)
            end
        end
    end
end

Events.OnTick.Add(keepShares)

return Payers
