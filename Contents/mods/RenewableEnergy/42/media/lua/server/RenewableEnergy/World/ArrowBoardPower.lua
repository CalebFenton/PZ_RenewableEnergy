require "RenewableEnergy/Chance"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Gadgets/VehicleBattery"
require "RenewableEnergy/PowerBank/PanelSource"
require "RenewableEnergy/World/ArrowBoard"

-- The arrow board trailer's power: its panels charge the batteries in its box, and the lamps run
-- off them through the controller: lit while the switch is on, the lamp board isn't wrecked and a
-- battery is above the controller's cutoff; after dark they also light the ground. Once every
-- battery hits the cutoff the lamps stay off until one reaches the reconnect level, so a board
-- that barely charges doesn't flicker from pass to pass.
--
-- The authority sets the lamps' state in the battery box part's modData, which the part saves and
-- the server sends its clients (transmitPartModData). Every game that draws the trailer flashes
-- them itself by the real clock, through the vehicle's windowLightsOn flag, which nothing else
-- sets and which lights the board's zone of the lamps texture. After dark the board also gets a
-- steady lamppost, since moving a lamppost relights the cell, too dear to do every flash.

local ArrowBoard = RenewableEnergy.ArrowBoard
local Chance, Specs = RenewableEnergy.Chance, RenewableEnergy.Specs

-- Battery box part modData. The box tracks its discharge cycle of the day as a bank tracks its
-- own (Battery.trackCycle).
ArrowBoard.SWITCH_KEY = "RenewableEnergy_switchOn"
local LAMPS_KEY, CUT_OFF_KEY = "RenewableEnergy_lamps", "RenewableEnergy_cutOff"
local CYCLE_DAY, CYCLE_HIGH, CYCLE_DEPTH = "RenewableEnergy_cycleDay", "RenewableEnergy_cycleHigh", "RenewableEnergy_cycleDepth"
local LAMPS_DAY, LAMPS_NIGHT = "day", "night"

-- The lamps' amber, halved, since the native lighting doubles a lamp's colour (SolarGardenLight).
local GROUND_LIGHT = { r = 0.5, g = 0.35, b = 0.08 }

local function boxOf(vehicle)
    return vehicle:getPartById(ArrowBoard.BATTERY_BOX)
end

-- Batteries

-- A battery in the box that can still hold a charge.
local function holdsCharge(item)
    return RenewableEnergy.Battery.nominalWh(item) > 0
end

-- `charge` in whole uses of the battery. The game keeps a charge in uses and rounds a charge it is
-- given to the nearest (InventoryItem.setCurrentUsesFloat), and reads it back as a float a hair
-- off it (0.1 comes back as 0.09999999), so charges are compared in uses.
local function usesAt(battery, charge)
    return math.floor(charge / battery:getUseDelta() + 0.5)
end

-- The battery in the box furthest from `target` on the side `direction` gives (1: below it,
-- -1: above it), and how far, as a charge; nil if every battery is there.
local function furthestFrom(container, target, direction)
    local furthest, furthestGap
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if holdsCharge(item) then
            local gap = (usesAt(item, target) - item:getCurrentUses()) * direction * item:getUseDelta()
            if gap > 0 and (not furthest or gap > furthestGap) then
                furthest, furthestGap = item, gap
            end
        end
    end
    return furthest, furthestGap
end

-- Moves up to `wh` into or out of the batteries in the box, toward `target`: 1 to charge them,
-- the controller's cutoff to drain them. The one furthest from it goes first, so that a mixed set
-- evens out. Authority only. Returns the watt-hours moved.
local function shift(container, wh, target, direction)
    local Battery = RenewableEnergy.Battery
    local moved = 0
    local battery, gap = furthestFrom(container, target, direction)
    while battery and wh > 0 do
        local before, nominal = Battery.getCharge(battery), Battery.nominalWh(battery)
        local room = gap * nominal
        local step = math.min(wh, room)
        -- Exactly at the target when it gets there, so the next pick moves on.
        Battery.setCharge(battery, step == room and target or before + direction * step / nominal)
        -- As the maintainer does: clients hear of the charge once it shows at two decimals.
        if VehicleUtils.compareFloats(before, Battery.getCharge(battery), 2) then
            sendItemStats(battery)
        end
        wh, moved = wh - step, moved + step
        battery, gap = furthestFrom(container, target, direction)
    end
    return moved
end

-- How many uses the fullest battery in the box that holds a charge has over `charge` (negative
-- when under it), or nil when the box holds none.
local function fullestOver(container, charge)
    local most
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if holdsCharge(item) then
            local over = item:getCurrentUses() - usesAt(item, charge)
            most = most and math.max(most, over) or over
        end
    end
    return most
end

-- Charging

--- Adds `hours` of its panels' output under `sky` (Sun.skyNow, now if nil) to the batteries in
--- its battery box, the emptiest first, so that a mixed set fills evenly. The panels count as
--- flat, since the trailer may face any way, and make nothing under a roof. Authority only.
--- Returns the watt-hours stored.
---@param vehicle BaseVehicle
function ArrowBoard.charge(vehicle, hours, sky)
    if not ArrowBoard.isTrailer(vehicle) then
        return 0
    end
    local box = boxOf(vehicle)
    local container = box and box:getItemContainer()
    if not container then
        return 0
    end
    local wh = RenewableEnergy.Sun.squareWatts(vehicle:getSquare(), ArrowBoard.panelWatts(vehicle), sky) * hours
    return shift(container, wh, 1, 1)
end

-- Switch and lamps

function ArrowBoard.isSwitchedOn(vehicle)
    local box = boxOf(vehicle)
    return box ~= nil and box:getModData()[ArrowBoard.SWITCH_KEY] == true
end

--- The lamps as the authority last set them: "day", "night" (lighting the ground), or nil while dark.
function ArrowBoard.lamps(vehicle)
    local box = boxOf(vehicle)
    return box and box:getModData()[LAMPS_KEY] or nil
end

-- Whether the lamp board can light: on the trailer, and not beaten to nothing.
local function boardIntact(vehicle)
    local board = vehicle:getPartById(ArrowBoard.BOARD)
    return board ~= nil and board:getInventoryItem() ~= nil and board:getCondition() > 0
end

--- Whether a character at the box can reach the switch: inside the box, so only with the lid open
--- or off, as the padlock means it to be.
function ArrowBoard.switchReachable(vehicle)
    local lid = vehicle:getPartById(ArrowBoard.LID)
    local door = lid and lid:getDoor()
    if not (door and lid:getInventoryItem()) then
        return true
    end
    return door:isOpen()
end

--- Whether the switch can be set to `on`: on an arrow board, reachable, and not there already.
function ArrowBoard.canSwitch(vehicle, on)
    return ArrowBoard.isTrailer(vehicle) and ArrowBoard.switchReachable(vehicle) and ArrowBoard.isSwitchedOn(vehicle) ~= on
end

--- Sets the switch of a trailer that has none yet: on by STOCK.switchedOnChance. Authority only.
function ArrowBoard.rollSwitch(vehicle)
    local box = vehicle and boxOf(vehicle)
    local modData = box and box:getModData()
    if modData and modData[ArrowBoard.SWITCH_KEY] == nil then
        modData[ArrowBoard.SWITCH_KEY] = Chance.hit(ArrowBoard.STOCK.switchedOnChance)
        vehicle:transmitPartModData(box)
    end
end

-- The lit lamps' draw in watts, day or night: vanilla's lightbar share of a car battery an hour.
local function lampWatts()
    return Specs.arrowBoard.lampShare * Specs.batteries[RenewableEnergy.VehicleBattery.CAR_BATTERY].wh
end

-- Follows the box's discharge cycle, and on a new day wears its batteries by the day before's
-- deepest discharge, as a bank does.
local function trackCycle(box, container)
    local Battery = RenewableEnergy.Battery
    local charge, nominalWh = Battery.containerCharge(container)
    if nominalWh <= 0 then
        return
    end
    local modData, day = box:getModData(), Battery.today()
    local high, depth, finished = Battery.trackCycle(modData[CYCLE_DAY], modData[CYCLE_HIGH], modData[CYCLE_DEPTH], charge, day)
    if finished and finished > 0 then
        Battery.wearAll(container, finished)
    end
    modData[CYCLE_DAY], modData[CYCLE_HIGH], modData[CYCLE_DEPTH] = day, high, depth
end

-- Sets the lamps by the switch, the board, the batteries and the photocell, which sees dark at
-- `night`, and sends them to the clients when they change.
local function setLamps(vehicle, box, night)
    local spec, modData = Specs.arrowBoard, box:getModData()
    local container = box:getItemContainer()
    local overCutoff = fullestOver(container, spec.cutoff)
    if not overCutoff or overCutoff <= 0 then
        modData[CUT_OFF_KEY] = true
    elseif fullestOver(container, spec.reconnect) >= 0 then
        modData[CUT_OFF_KEY] = nil
    end
    local lit = modData[ArrowBoard.SWITCH_KEY] == true and not modData[CUT_OFF_KEY] and boardIntact(vehicle)
    local lamps = lit and (night and LAMPS_NIGHT or LAMPS_DAY) or nil
    if modData[LAMPS_KEY] ~= lamps then
        modData[LAMPS_KEY] = lamps
        vehicle:transmitPartModData(box)
    end
end

--- `hours` of the lamps as they were lit, drawn from the box, then the lamps set again for the
--- switch, the board, the batteries and the photocell (`night`, now if nil) as they are now.
--- Authority only. Returns the watt-hours the lamps drew.
function ArrowBoard.runLamps(vehicle, hours, night)
    local box = boxOf(vehicle)
    local container = box and box:getItemContainer()
    if not container then
        return 0
    end
    local lamps = box:getModData()[LAMPS_KEY]
    local drawn = lamps and shift(container, lampWatts() * hours, Specs.arrowBoard.cutoff, -1) or 0
    trackCycle(box, container)
    if night == nil then
        night = RenewableEnergy.Sun.isDark()
    end
    setLamps(vehicle, box, night)
    return drawn
end

--- Sets the switch on or off, the lamps following at once. Authority only, from the switch
--- action's complete(). Returns whether it could.
function ArrowBoard.setSwitch(vehicle, on)
    local box = boxOf(vehicle)
    if not (box and box:getItemContainer()) then
        return false
    end
    box:getModData()[ArrowBoard.SWITCH_KEY] = on
    vehicle:transmitPartModData(box)
    setLamps(vehicle, box, RenewableEnergy.Sun.isDark())
    return true
end

--- The charge pass for one loaded vehicle under `sky` (Sun.skyNow, now if nil): if it is an
--- arrow board, storms may crack its panels, its panels show what they hold, they charge its box
--- and its lamps draw from it. Authority only. Returns the watt-hours its panels stored.
function ArrowBoard.update(vehicle, hours, sky)
    if not ArrowBoard.isTrailer(vehicle) then
        return 0
    end
    sky = sky or RenewableEnergy.Sun.skyNow()
    ArrowBoard.stormCrack(vehicle, RenewableEnergy.PanelSource.stormHours(hours))
    ArrowBoard.showPanels(vehicle)
    local stored = ArrowBoard.charge(vehicle, hours, sky)
    ArrowBoard.runLamps(vehicle, hours, RenewableEnergy.Sun.isDark(sky))
    return stored
end

-- Flashing

--- Whether the flashing lamps are lit at real time `ms`, and how many milliseconds they have been
--- lit or dark.
function ArrowBoard.flashPhase(ms)
    local spec = Specs.arrowBoard
    local period = 60000 / spec.flashesPerMinute
    local into, litFor = ms % period, period * spec.onShare
    if into < litFor then
        return true, into
    end
    return false, into - litFor
end

-- Every loaded trailer this game draws, by vehicle, with its ground lamppost while it has one.
local boards = {}

local function removeGroundLight(entry)
    if entry.light then
        getCell():removeLamppost(entry.light)
        entry.light = nil
    end
end

-- Gives the board a lamppost on the trailer's square, moved only when the trailer moves to another.
local function placeGroundLight(entry, vehicle)
    local x, y, z = math.floor(vehicle:getX()), math.floor(vehicle:getY()), math.floor(vehicle:getZ())
    if entry.light and entry.x == x and entry.y == y and entry.z == z then
        return
    end
    removeGroundLight(entry)
    entry.light = getCell():addLamppost(x, y, z, GROUND_LIGHT.r, GROUND_LIGHT.g, GROUND_LIGHT.b, Specs.arrowBoard.radius)
    entry.x, entry.y, entry.z = x, y, z
end

-- OnTick, except on a dedicated server: flashes the lamps of every loaded trailer that is lit, and
-- lights the ground around those lit at night. Runs every frame because the flag lights only the
-- frame it is set in, and no event announces the authority's modData changing. Allocates nothing
-- unless a lamppost moves.
local function flashLamps()
    local flashLit = ArrowBoard.flashPhase(getTimestampMs())
    for vehicle, entry in pairs(boards) do
        if vehicle:isRemovedFromWorld() then
            removeGroundLight(entry)
            boards[vehicle] = nil
        else
            local lamps = entry.box:getModData()[LAMPS_KEY]
            local show = lamps ~= nil and flashLit
            if vehicle:getWindowLightsOn() ~= show then
                vehicle:setWindowLightsOn(show)
            end
            if lamps == LAMPS_NIGHT then
                placeGroundLight(entry, vehicle)
            else
                removeGroundLight(entry)
            end
        end
    end
end

--- Part `init` of the lamp board: runs on every side each time the trailer loads. A trailer saved
--- before it had the board and the switch gets them here.
function ArrowBoard.initBoard(vehicle, part)
    ArrowBoard.initFrame(vehicle, part)
    if not isClient() then
        ArrowBoard.rollSwitch(vehicle)
    end
    local box = boxOf(vehicle)
    if box and not isServer() and not boards[vehicle] then
        boards[vehicle] = { box = box }
    end
end

if not isServer() then
    Events.OnTick.Add(flashLamps)
end
