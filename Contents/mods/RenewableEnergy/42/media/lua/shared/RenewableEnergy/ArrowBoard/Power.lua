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

local Specs = require "RenewableEnergy/Specs"
local Sun = require "RenewableEnergy/Sun"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Trailer"
local Chance = require "cf_commonlib/Chance"
local VehicleParts = require "cf_commonlib/VehicleParts"

-- The lamps draw what vanilla's lightbar takes from a vehicle battery with the engine off
-- (Vehicles.Update.Lightbar, applied twice by VehicleUtils.chargeBattery), as a share of a car
-- battery an hour. Flash rate and duty follow MUTCD 6F.61. The controller cuts the lamps below
-- `cutoff` charge in every battery and relights at `reconnect`; at night they light `radius` squares.
ArrowBoard.SPEC = {
    lampShare = 0.003, flashesPerMinute = 30, onShare = 0.5,
    cutoff = 0.1, reconnect = 0.25, radius = 3,
}

-- Battery box part modData. The box tracks its discharge cycle of the day as a bank tracks its
-- own (Battery.trackCycle).
ArrowBoard.SWITCH_KEY = "RenewableEnergy_switchOn"
-- The lamps as the authority last set them: "day", "night" (lighting the ground), or nil while dark.
ArrowBoard.LAMPS_KEY = "RenewableEnergy_lamps"
local CUT_OFF_KEY = "RenewableEnergy_cutOff"
local CYCLE_DAY_KEY, CYCLE_HIGH_KEY, CYCLE_DEPTH_KEY = "RenewableEnergy_cycleDay", "RenewableEnergy_cycleHigh", "RenewableEnergy_cycleDepth"
local LAMPS_DAY, LAMPS_NIGHT = "day", "night"

-- The lamps' amber, halved, since the native lighting doubles a lamp's colour (SolarGardenLight).
local GROUND_LIGHT = { r = 0.5, g = 0.35, b = 0.08 }

local function boxOf(vehicle)
    return vehicle:getPartById(ArrowBoard.BATTERY_BOX)
end

-- Batteries

-- A battery in the box that can still hold a charge.
local function holdsCharge(item)
    return Battery.nominalWh(item) > 0
end

-- `charge` in whole uses of the battery: a charge is kept in uses and read back a hair off.
local function usesAt(battery, charge)
    return math.floor(charge / battery:getUseDelta() + 0.5)
end

-- Moves up to `wh` into or out of the batteries in the box, toward `target`: 1 to charge them,
-- the controller's cutoff to drain them (Battery.shift). Authority only. Returns the watt-hours
-- moved.
local function shift(container, wh, target, direction)
    return (Battery.shift(container, wh, target, direction, holdsCharge, Battery.nominalWh))
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
    local wh = Sun.squareWatts(vehicle:getSquare(), ArrowBoard.panelWatts(vehicle), sky) * hours
    return shift(container, wh, 1, 1)
end

-- Switch and lamps

function ArrowBoard.isSwitchedOn(vehicle)
    local box = boxOf(vehicle)
    return box ~= nil and box:getModData()[ArrowBoard.SWITCH_KEY] == true
end

-- Whether the lamp board can light: on the trailer, and not beaten to nothing.
local function boardIntact(vehicle)
    local board = vehicle:getPartById(ArrowBoard.BOARD)
    return board ~= nil and board:getInventoryItem() ~= nil and board:getCondition() > 0
end

--- Whether a character at the box can reach the switch: inside the box, so only with the lid open
--- or off, as the padlock means it to be.
function ArrowBoard.switchReachable(vehicle)
    return VehicleParts.isOpen(vehicle, ArrowBoard.LID)
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
    return ArrowBoard.SPEC.lampShare * Specs.batteries[VehicleBattery.CAR_BATTERY].wh
end

-- Follows the box's discharge cycle, and on a new day wears its batteries by the day before's
-- deepest discharge, as a bank does.
local function trackCycle(box, container)
    local charge, nominalWh = Battery.containerCharge(container)
    if nominalWh <= 0 then
        return
    end
    local modData, day = box:getModData(), Battery.today()
    local high, depth, finished = Battery.trackCycle(modData[CYCLE_DAY_KEY], modData[CYCLE_HIGH_KEY], modData[CYCLE_DEPTH_KEY], charge, day)
    if finished and finished > 0 then
        Battery.wearAll(container, finished)
    end
    modData[CYCLE_DAY_KEY], modData[CYCLE_HIGH_KEY], modData[CYCLE_DEPTH_KEY] = day, high, depth
end

-- Sets the lamps by the switch, the board, the batteries and the photocell, which sees dark at
-- `night`, and sends them to the clients when they change.
local function setLamps(vehicle, box, night)
    local spec, modData = ArrowBoard.SPEC, box:getModData()
    local container = box:getItemContainer()
    local overCutoff = fullestOver(container, spec.cutoff)
    if not overCutoff or overCutoff <= 0 then
        modData[CUT_OFF_KEY] = true
    elseif fullestOver(container, spec.reconnect) >= 0 then
        modData[CUT_OFF_KEY] = nil
    end
    local lit = modData[ArrowBoard.SWITCH_KEY] == true and not modData[CUT_OFF_KEY] and boardIntact(vehicle)
    local lamps = lit and (night and LAMPS_NIGHT or LAMPS_DAY) or nil
    if modData[ArrowBoard.LAMPS_KEY] ~= lamps then
        modData[ArrowBoard.LAMPS_KEY] = lamps
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
    local lamps = box:getModData()[ArrowBoard.LAMPS_KEY]
    local drawn = lamps and shift(container, lampWatts() * hours, ArrowBoard.SPEC.cutoff, -1) or 0
    trackCycle(box, container)
    if night == nil then
        night = Sun.isDark()
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
    setLamps(vehicle, box, Sun.isDark())
    return true
end

--- The charge pass for one loaded vehicle under `sky` (Sun.skyNow, now if nil): if it is an
--- arrow board, storms may crack its panels, its panels show what they hold, they charge its box
--- and its lamps draw from it. Authority only. Returns the watt-hours its panels stored.
function ArrowBoard.update(vehicle, hours, sky)
    if not ArrowBoard.isTrailer(vehicle) then
        return 0
    end
    local PanelStorms = require "RenewableEnergy/PowerBank/PanelStorms"
    sky = sky or Sun.skyNow()
    ArrowBoard.stormCrack(vehicle, PanelStorms.stormHours(hours))
    ArrowBoard.showPanels(vehicle)
    local stored = ArrowBoard.charge(vehicle, hours, sky)
    ArrowBoard.runLamps(vehicle, hours, Sun.isDark(sky))
    return stored
end

-- Flashing

--- Whether the flashing lamps are lit at real time `ms`, and how many milliseconds they have been
--- lit or dark.
function ArrowBoard.flashPhase(ms)
    local spec = ArrowBoard.SPEC
    local period = 60000 / spec.flashesPerMinute
    local into, litFor = ms % period, period * spec.onShare
    if into < litFor then
        return true, into
    end
    return false, into - litFor
end

--- Takes away the ground lamppost of a trailer's entry (ArrowBoard.trailerEntry), if it has one.
function ArrowBoard.forgetLamps(entry)
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
    ArrowBoard.forgetLamps(entry)
    entry.light = getCell():addLamppost(x, y, z, GROUND_LIGHT.r, GROUND_LIGHT.g, GROUND_LIGHT.b, ArrowBoard.SPEC.radius)
    entry.x, entry.y, entry.z = x, y, z
end

--- Each frame, in a game that draws the trailer: shows its lamps lit when they are on and the
--- flash is lit (`flashLit`), and lights the ground around it while they are on at night. Every
--- frame because the flag lights only the frame it is set in, and no event announces the
--- authority's modData changing.
function ArrowBoard.flashLamps(vehicle, entry, flashLit)
    local lamps = entry.box:getModData()[ArrowBoard.LAMPS_KEY]
    local show = lamps ~= nil and flashLit
    if vehicle:getWindowLightsOn() ~= show then
        vehicle:setWindowLightsOn(show)
    end
    if lamps == LAMPS_NIGHT then
        placeGroundLight(entry, vehicle)
    else
        ArrowBoard.forgetLamps(entry)
    end
end

--- Part `init` of the lamp board: runs on every side each time the trailer loads. A trailer saved
--- before it had the board and the switch gets them here. A game that draws it flashes its lamps
--- from then on.
function ArrowBoard.initBoard(vehicle, part)
    ArrowBoard.initFrame(vehicle, part)
    if not isClient() then
        ArrowBoard.rollSwitch(vehicle)
    end
    local box = boxOf(vehicle)
    if box and not isServer() then
        local entry = ArrowBoard.trailerEntry(vehicle)
        entry.box = entry.box or box
    end
end

return ArrowBoard
