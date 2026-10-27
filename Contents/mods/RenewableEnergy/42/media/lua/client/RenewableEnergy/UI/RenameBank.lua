-- The box a local player names a battery bank in, from its menu or its status window.

require "ISUI/ISTextBox"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"

local RenameBank = {}

local function onNameEntered(target, button, playerNum, bank)
    if button.internal == "OK" then
        Action.queue(playerNum, "bank", BankJobs.RENAME, bank, button.parent.entry:getText())
    end
end

--- Asks a local player for a new name for `bank` and queues the renaming. An empty name gives
--- the bank back its tier's name. Returns the box.
function RenameBank.ask(playerNum, bank)
    local summary = PowerBank.summaryOf(bank)
    local modal = ISTextBox:new(0, 0, 280, 180, getText("IGUI_RenewableEnergy_NameThisBank"), summary and summary.name or "",
        nil, onNameEntered, playerNum, playerNum, bank)
    modal:initialise()
    modal.entry:setMaxTextLength(BankJobs.NAME_LENGTH)
    modal:addToUIManager()
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, modal)
    end
    return modal
end

return RenameBank
