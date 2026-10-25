-- The base of the status windows of an object: a bank's (StatusWindow), a digester's and a
-- gasifier's (SummaryWindow). Each family keeps one window per local player in its class's
-- `windows`; a new one opens where the player's last one of the family stood, takes the
-- controller's focus, and closes with B, as vanilla's windows do. It closes once its object is
-- gone or the character walked away (InfoAction.inReach), as vanilla's animal windows close. A
-- derived class defines refresh(), which brings it up to date before each frame is drawn and
-- returns false when there is nothing left to show.

require "ISUI/ISCollapsableWindow"
require "RenewableEnergy/TimedActions/InfoAction"

RenewableEnergy = RenewableEnergy or {}
local ObjectWindow = ISCollapsableWindow:derive("RenewableEnergyObjectWindow")
RenewableEnergy.ObjectWindow = ObjectWindow

-- Where a player's first window of a family opens, from their screen's top left corner.
local FIRST_OFFSET = 100

function ObjectWindow:prerender()
    if not (RenewableEnergy.InfoAction.inReach(self.playerNum, self.object) and self:refresh() ~= false) then
        self:close()
        return
    end
    ISCollapsableWindow.prerender(self)
end

function ObjectWindow:close()
    self.windows[self.playerNum] = nil
    self:removeFromUIManager()
    if JoypadState.players[self.playerNum + 1] then
        setPrevFocusForPlayer(self.playerNum)
    end
end

function ObjectWindow:onJoypadDown(button)
    if button == Joypad.BButton then
        self:close()
    end
end

function ObjectWindow:new(x, y, width, height, playerNum, object)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.playerNum = playerNum
    o.object = object
    o:setResizable(false)
    return o
end

--- Opens `playerNum`'s window of this class on `object` (the class's new(x, y, playerNum,
--- object)), in place of the one of its family they had open.
function ObjectWindow:openOn(playerNum, object)
    local open = self.windows[playerNum]
    local x, y = getPlayerScreenLeft(playerNum) + FIRST_OFFSET, getPlayerScreenTop(playerNum) + FIRST_OFFSET
    if open then
        x, y = open:getX(), open:getY()
        open:close()
    end
    local window = self:new(x, y, playerNum, object)
    window:initialise()
    window:addToUIManager()
    self.windows[playerNum] = window
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, window)
    end
    return window
end

return ObjectWindow
