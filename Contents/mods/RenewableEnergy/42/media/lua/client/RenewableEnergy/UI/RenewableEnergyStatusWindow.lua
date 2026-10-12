require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
---@class RenewableEnergy
require "RenewableEnergy/Utilities"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/RenewableEnergyFormat"

-- The battery bank's status window: what comes in, what goes out and what is stored, on the left;
-- the batteries and the panels on the right. It draws the status snapshot the server sends with
-- the bank, so it reads the same in single player and multiplayer.
local StatusWindow = ISCollapsableWindow:derive("RenewableEnergyStatusWindow")

local Format = RenewableEnergy.Format
local Action = RenewableEnergyAction

local PAD = 10
local COLUMN_GAP = 24
local LABEL_GAP = 16
local MIN_COLUMN_WIDTH = 220
local BAR_HEIGHT = 8
-- Lines of the right column kept for "and N more" when the panels don't fit.
local MORE_LINE = 1

-- One window per local player.
StatusWindow.windows = {}

local COLORS = {
    text = { r = 1, g = 1, b = 1 },
    label = { r = 0.8, g = 0.8, b = 0.8 },
    header = { r = 1, g = 1, b = 0.8 },
    dim = { r = 0.6, g = 0.6, b = 0.6 },
}

local function color(name)
    if name == "good" then
        local c = getCore():getGoodHighlitedColor()
        return { r = c:getR(), g = c:getG(), b = c:getB() }
    elseif name == "bad" then
        local c = getCore():getBadHighlitedColor()
        return { r = c:getR(), g = c:getG(), b = c:getB() }
    end
    return COLORS[name] or COLORS.text
end

-- Rows ----------------------------------------------------------------------------------------
-- A row is { header = text }, { label = text, value = text, color = name }, { bar = 0..1 } or
-- { gap = true }. They are built from the status alone, so the tests can check them for any bank.

local function header(rows, key, ...)
    if #rows > 0 then
        table.insert(rows, { gap = true })
    end
    table.insert(rows, { header = getText(key, ...) })
end

local function row(rows, key, value, colorName)
    table.insert(rows, { label = getText(key), value = value, color = colorName })
end

-- Full sun on a flat panel, the irradiance at which panels are rated.
local FULL_SUN = 1000

local function powerRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Power")
    if status.sunElevation > 0 then
        row(rows, "IGUI_RenewableEnergy_Sunlight", Format.percent(status.irradiance / FULL_SUN))
    else
        row(rows, "IGUI_RenewableEnergy_Sunlight", getText("IGUI_RenewableEnergy_Night"), "dim")
    end
    row(rows, "IGUI_RenewableEnergy_PanelsNow", Format.watts(status.solarW))
    row(rows, "IGUI_RenewableEnergy_PanelsToday", Format.wattHours(status.solarWhToday))
    if status.sunElevation > 0 then
        row(rows, "IGUI_RenewableEnergy_PanelHeat", Format.change(status.panelTempFactor))
    end
    if status.vehicle then
        local vehicle = status.vehicle
        local value = vehicle.running and Format.watts(vehicle.watts) or getText("IGUI_RenewableEnergy_EngineOff")
        row(rows, "IGUI_RenewableEnergy_Vehicle", value, not vehicle.running and "dim" or nil)
    end
    if status.generator then
        local generator = status.generator
        local value = generator.running and Format.watts(generator.chargeW) or getText("IGUI_RenewableEnergy_GeneratorStopped")
        row(rows, "IGUI_RenewableEnergy_Generator", value, not generator.running and "dim" or nil)
    end
    row(rows, "IGUI_RenewableEnergy_Load", Format.watts(status.loadW))
    row(rows, "IGUI_RenewableEnergy_UsedToday", Format.wattHours(status.loadWhToday))
    local net = status.inW - status.drawW
    row(rows, "IGUI_RenewableEnergy_Net", Format.signedWatts(net), net > 0 and "good" or net < 0 and "bad" or nil)
end

local function storageRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Storage")
    if #status.batteries == 0 then
        row(rows, "IGUI_RenewableEnergy_Stored", getText("IGUI_RenewableEnergy_NoBatteries"), "bad")
        return
    end
    table.insert(rows, { bar = status.charge })
    row(rows, "IGUI_RenewableEnergy_Stored", Format.wattHours(status.storedWh) .. " / " .. Format.wattHours(status.capacityWh)
        .. " (" .. Format.percent(status.charge) .. ")")
    local temperature = Format.temperature(status.tempC)
    local cold = status.coldFactor < 0.995
    if cold then
        temperature = temperature .. " (" .. getText("IGUI_RenewableEnergy_CapacityChange", Format.change(status.coldFactor)) .. ")"
    end
    row(rows, "IGUI_RenewableEnergy_BankTemperature", temperature, cold and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_CycleDepth", Format.percent(status.cycleDepth))
    if status.hoursLeft then
        row(rows, "IGUI_RenewableEnergy_EmptyIn", Format.duration(status.hoursLeft), status.hoursLeft < 12 and "bad" or nil)
    end
end

local TRIPS = {
    overload = "IGUI_RenewableEnergy_TripOverload",
    surge = "IGUI_RenewableEnergy_TripSurge",
    volts240 = "IGUI_RenewableEnergy_Trip240",
}

local function inverterState(inverter)
    if inverter.state == "tripped" then
        local reason = getText(TRIPS[inverter.trip] or "IGUI_RenewableEnergy_TripOverload")
        if inverter.tripW then
            reason = reason .. ", " .. Format.watts(inverter.tripW)
        end
        return getText("IGUI_RenewableEnergy_Tripped", reason), "bad"
    elseif inverter.state == "empty" then
        return getText("IGUI_RenewableEnergy_InverterEmpty"), "bad"
    elseif inverter.state == "on" then
        return getText("IGUI_RenewableEnergy_On"), "good"
    end
    return getText("IGUI_RenewableEnergy_Off"), "dim"
end

local function inverterRows(rows, status)
    local inverter = status.inverter
    header(rows, "IGUI_RenewableEnergy_Inverter")
    if inverter.state == "none" then
        row(rows, "IGUI_RenewableEnergy_Model", getText("IGUI_RenewableEnergy_NoInverter"), "bad")
        return
    end
    row(rows, "IGUI_RenewableEnergy_Model", getItemNameFromFullType(inverter.fullType))
    row(rows, "IGUI_RenewableEnergy_Rating", getText("IGUI_RenewableEnergy_RatingValue", Format.watts(inverter.watts), Format.watts(inverter.surge)))
    row(rows, "IGUI_RenewableEnergy_State", inverterState(inverter))
end

local function controllerRows(rows, status)
    local controllers = status.controllers
    header(rows, "IGUI_RenewableEnergy_Controllers")
    row(rows, "IGUI_RenewableEnergy_ControllerCount", controllers.count .. " (" .. Format.watts(controllers.ratedWatts) .. ")")
    row(rows, "IGUI_RenewableEnergy_PanelRating", Format.watts(controllers.panelWatts))
    -- The allowance already counts the controllers' rating and the modules a bank takes without one.
    local headroom = controllers.allowanceWatts - controllers.panelWatts
    row(rows, "IGUI_RenewableEnergy_Headroom", Format.watts(headroom), headroom < 0 and "bad" or nil)
    if controllers.overcharging then
        row(rows, "IGUI_RenewableEnergy_Overcharging", Format.watts(controllers.uncontrolledWatts), "bad")
    end
end

local function batteryRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Batteries", #status.batteries)
    for _, battery in ipairs(status.batteries) do
        local value
        if battery.frozen then
            value = getText("IGUI_RenewableEnergy_Frozen")
        else
            value = getText("IGUI_RenewableEnergy_BatteryValue", Format.percent(battery.charge), Format.percent(battery.condition / 100))
        end
        table.insert(rows, {
            label = getItemNameFromFullType(battery.fullType),
            value = value,
            color = (battery.frozen or battery.condition <= 0) and "bad" or nil,
        })
    end
end

local SOURCE_KINDS = {
    flat = "IGUI_RenewableEnergy_Flat",
    wall = "IGUI_RenewableEnergy_Wall",
    rack = "IGUI_RenewableEnergy_Rack",
}

local function sourceLabel(source)
    local label = getText(SOURCE_KINDS[source.kind] or "IGUI_RenewableEnergy_Flat")
    if source.facing then
        label = label .. " (" .. Format.compass(source.facing) .. ")"
    end
    return label
end

local function sourceRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Panels", #status.sources)
    for _, source in ipairs(status.sources) do
        local value = Format.watts(source.watts)
        local snowy = source.snow > 0
        if snowy then
            value = value .. ", " .. getText("IGUI_RenewableEnergy_Snow", Format.percent(source.snow))
        end
        table.insert(rows, { label = sourceLabel(source), value = value, color = snowy and "bad" or nil })
    end
end

--- The rows of both columns for a status snapshot.
function StatusWindow.rows(status)
    local left, right = {}, {}
    powerRows(left, status)
    storageRows(left, status)
    inverterRows(left, status)
    controllerRows(left, status)
    batteryRows(right, status)
    sourceRows(right, status)
    return left, right
end

-- Layout --------------------------------------------------------------------------------------

local function lineHeight()
    return getTextManager():getFontHeight(UIFont.Small)
end

local function rowHeight(r)
    if r.bar then
        return BAR_HEIGHT + 4
    elseif r.header then
        return lineHeight() + 4
    elseif r.gap then
        return math.floor(lineHeight() / 2)
    end
    return lineHeight()
end

local function measure(rows)
    local textManager = getTextManager()
    local labelWidth, valueWidth, height, headerWidth = 0, 0, 0, 0
    for _, r in ipairs(rows) do
        if r.header then
            headerWidth = math.max(headerWidth, textManager:MeasureStringX(UIFont.Small, r.header))
        elseif r.label then
            labelWidth = math.max(labelWidth, textManager:MeasureStringX(UIFont.Small, r.label))
            valueWidth = math.max(valueWidth, textManager:MeasureStringX(UIFont.Small, r.value))
        end
        height = height + rowHeight(r)
    end
    local width = math.max(MIN_COLUMN_WIDTH, headerWidth, labelWidth + LABEL_GAP + valueWidth)
    return { width = width, height = height, labelWidth = labelWidth }
end

-- Keeps as many right-column rows as fit beside the left column, then one "and N more" line
-- counting the entries left out.
local function fit(rows, height)
    local used, kept = 0, {}
    for i, r in ipairs(rows) do
        if used + rowHeight(r) + MORE_LINE * lineHeight() > height and i < #rows then
            local hidden = 0
            for j = i, #rows do
                if rows[j].label then
                    hidden = hidden + 1
                end
            end
            table.insert(kept, { label = getText("IGUI_RenewableEnergy_More", hidden), value = "", color = "dim" })
            return kept
        end
        table.insert(kept, r)
        used = used + rowHeight(r)
    end
    return kept
end

-- Window --------------------------------------------------------------------------------------

function StatusWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local height = math.floor(lineHeight() * 1.5)
    self.switchButton = ISButton:new(PAD, 0, 100, height, getText("ContextMenu_Turn_On"), self, StatusWindow.onSwitch)
    self.switchButton:initialise()
    self:addChild(self.switchButton)
    self.resetButton = ISButton:new(PAD, 0, 100, height, getText("IGUI_RenewableEnergy_Reset"), self, StatusWindow.onReset)
    self.resetButton:initialise()
    self:addChild(self.resetButton)
end

function StatusWindow:bankPosition()
    return self.bank:getX(), self.bank:getY(), self.bank:getZ()
end

function StatusWindow:queue(mode)
    local character = getSpecificPlayer(self.playerNum)
    if luautils.walkAdj(character, self.bank:getSquare(), true) then
        ISTimedActionQueue.add(Action:new(character, mode, nil, self.bank))
    end
end

function StatusWindow:onSwitch()
    self:queue(self.status and self.status.on and Action.TURN_OFF or Action.TURN_ON)
end

function StatusWindow:onReset()
    self:queue(Action.RESET_INVERTER)
end

-- Rebuilds the rows and the layout when a new snapshot arrives.
function StatusWindow:setStatus(status)
    self.status = status
    self.statusHour = status and status.hour
    local th = self:titleBarHeight()
    if not status then
        self.left, self.right = { { label = getText("IGUI_RenewableEnergy_Waiting"), value = "", color = "dim" } }, {}
    else
        self.left, self.right = StatusWindow.rows(status)
    end
    local left = measure(self.left)
    local right = measure(self.right)
    self.right = fit(self.right, math.max(left.height, lineHeight() * 8))
    right = measure(self.right)
    self.leftLayout, self.rightLayout = left, right

    local buttonY = th + PAD + math.max(left.height, right.height) + PAD
    self.switchButton:setTitle(getText(status and status.on and "ContextMenu_Turn_Off" or "ContextMenu_Turn_On"))
    self.switchButton:setWidth(getTextManager():MeasureStringX(UIFont.Small, self.switchButton:getTitle()) + 20)
    self.switchButton:setY(buttonY)
    self.switchButton:setEnable(status ~= nil and (status.on or status.inverter.state ~= "none"))
    self.resetButton:setWidth(getTextManager():MeasureStringX(UIFont.Small, self.resetButton:getTitle()) + 20)
    self.resetButton:setX(self.switchButton:getRight() + PAD)
    self.resetButton:setY(buttonY)
    self.resetButton:setEnable(status ~= nil and status.inverter.state == "tripped")

    self:setWidth(PAD + left.width + COLUMN_GAP + right.width + PAD)
    self:setHeight(buttonY + self.switchButton:getHeight() + PAD)
end

function StatusWindow:prerender()
    if self.bank:getObjectIndex() == -1 then
        self:close()
        return
    end
    local status = RenewableEnergy.PowerBank.getStatus(self:bankPosition())
    if status ~= self.status or (status and status.hour ~= self.statusHour) or not self.left then
        self:setStatus(status)
    end
    ISCollapsableWindow.prerender(self)
end

function StatusWindow:drawRows(rows, layout, x, y)
    local width = layout.width
    for _, r in ipairs(rows) do
        if r.header then
            local c = COLORS.header
            self:drawText(r.header, x, y + 2, c.r, c.g, c.b, 1, UIFont.Small)
            self:drawRect(x, y + rowHeight(r) - 2, width, 1, 0.4, c.r, c.g, c.b)
        elseif r.bar then
            local c = color(r.bar < 0.25 and "bad" or "good")
            self:drawProgressBar(x, y + 2, width, BAR_HEIGHT, r.bar, { r = c.r, g = c.g, b = c.b, a = 1 })
        elseif r.label then
            local label, value = COLORS.label, color(r.color)
            self:drawText(r.label, x, y, label.r, label.g, label.b, 1, UIFont.Small)
            self:drawTextRight(r.value, x + width, y, value.r, value.g, value.b, 1, UIFont.Small)
        end
        y = y + rowHeight(r)
    end
end

function StatusWindow:render()
    if not self.isCollapsed and self.left then
        local top = self:titleBarHeight() + PAD
        self:drawRows(self.left, self.leftLayout, PAD, top)
        self:drawRows(self.right, self.rightLayout, PAD + self.leftLayout.width + COLUMN_GAP, top)
        self.renderedFrames = (self.renderedFrames or 0) + 1
    end
    ISCollapsableWindow.render(self)
end

function StatusWindow:close()
    self:removeFromUIManager()
    StatusWindow.windows[self.playerNum] = nil
    if JoypadState.players[self.playerNum + 1] then
        setPrevFocusForPlayer(self.playerNum)
    end
end

function StatusWindow:onJoypadDown(button)
    if button == Joypad.BButton then
        self:close()
    end
end

function StatusWindow:new(x, y, playerNum, bank)
    local o = ISCollapsableWindow.new(self, x, y, 400, 300)
    o.title = getText("IGUI_RenewableEnergy_StatusTitle")
    o.playerNum = playerNum
    o.bank = bank
    -- Nearly opaque: the vanilla 0.8 lets the text of windows behind show through the rows.
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.95 }
    o:setResizable(false)
    return o
end

--- Opens the status window of `bank` (the bank's IsoGenerator) for a local player, replacing
--- the one already open, and asks the server for a fresh snapshot.
function StatusWindow.open(playerNum, bank)
    local open = StatusWindow.windows[playerNum]
    local x, y = getPlayerScreenLeft(playerNum) + 100, getPlayerScreenTop(playerNum) + 100
    if open then
        x, y = open:getX(), open:getY()
        open:close()
    end
    local window = StatusWindow:new(x, y, playerNum, bank)
    window:initialise()
    window:addToUIManager()
    StatusWindow.windows[playerNum] = window
    local bx, by, bz = window:bankPosition()
    RenewableEnergy.PowerBank.command(getSpecificPlayer(playerNum), "refresh", { bank = { x = bx, y = by, z = bz } })
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, window)
    end
    return window
end

RenewableEnergy.StatusWindow = StatusWindow
return StatusWindow
