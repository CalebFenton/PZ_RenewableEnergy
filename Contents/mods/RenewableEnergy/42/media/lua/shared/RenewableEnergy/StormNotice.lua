-- What players near storm damage hear and read. Blades break (WindSource) and modules crack
-- (PanelSource, PanelStorms, ArrowBoard) on the authority, which tells every client where; each
-- plays the sound there, if it has the square loaded, and tells its local players in earshot.

require "RenewableEnergy/Specs"

RenewableEnergy = RenewableEnergy or {}
local StormNotice = {}
RenewableEnergy.StormNotice = StormNotice

local Specs = RenewableEnergy.Specs

StormNotice.COMMAND_MODULE, StormNotice.DAMAGE_COMMAND = "RenewableEnergyStorm", "damage"
-- What `what` names for a cracked module; any other is the material of blades that broke.
StormNotice.CRACKED_MODULE = "module"

-- Squares within which a player is told of the damage: about as far as the sound carries.
local EARSHOT = 30

local function noticeOf(what)
    local blades = Specs.wind.blades[what]
    if blades then
        return blades.breakSound, "IGUI_RenewableEnergy_BladesBroke"
    end
    return Specs.storm.crackSound, "IGUI_RenewableEnergy_ModuleCracked"
end

local function hear(args)
    local sound, text = noticeOf(args.what)
    local square = getCell():getGridSquare(args.x, args.y, args.z)
    if square then
        square:playSound(sound)
    end
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and not player:isDead() then
            local dx, dy = player:getX() - args.x, player:getY() - args.y
            if dx * dx + dy * dy <= EARSHOT * EARSHOT then
                HaloTextHelper.addBadText(player, getText(text))
            end
        end
    end
end

--- On the authority: a storm did `what` at x, y, z, breaking the blades of that material
--- (Specs.wind.blades) or cracking a module (StormNotice.CRACKED_MODULE).
function StormNotice.tell(what, x, y, z)
    local args = { what = what, x = x, y = y, z = z }
    if isServer() then
        sendServerCommand(StormNotice.COMMAND_MODULE, StormNotice.DAMAGE_COMMAND, args)
    else
        hear(args)
    end
end

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module == StormNotice.COMMAND_MODULE and command == StormNotice.DAMAGE_COMMAND then
            hear(args)
        end
    end)
end

return StormNotice
