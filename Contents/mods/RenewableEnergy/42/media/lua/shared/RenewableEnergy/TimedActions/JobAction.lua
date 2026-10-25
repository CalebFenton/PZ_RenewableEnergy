-- The base of the hands-on jobs at a world object or a vehicle (RenewableEnergyAction,
-- RenewableEnergyGasAction). In multiplayer the client runs start() and perform(), and the server
-- rebuilds the action from new()'s parameters and runs complete(); single player runs both. Each
-- job class defines its own new(), as NetTimedAction reads the parameter names off the class's
-- new, and gives:
-- - REACH: how far from the middle of the target's square, on each axis, the character may work.
-- - target(): the object or vehicle worked at.
-- - row(): the job's row: `light`, it needs light to see by; `metabolics`, the exertion it keeps
--   the character at; how it looks: `begin(self)`, which starts its animation, else `anim`, else
--   the "Loot" reach, with LootPosition `position` ("Low" for the reach unless it says); `sound`
--   while it runs and `doneSound` once done.
-- - units(): its length in action units.
-- - keeps(): what the job needs from moment to moment, cheap enough for isValid to ask every tick.
--   These are what another player or the world can take away mid-job, and the character's own
--   copy of the world shows them, so a multiplayer client asks them too.
-- - canPerform(): every rule of the job, as this side knows it.
-- - findItems(): looks the inventory items the job works with up again by their IDs.
-- - REPORTS_LOOT, if set: the "Loot" reach also reports EventLootItem.

require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/Utilities"

RenewableEnergy = RenewableEnergy or {}
local JobAction = ISBaseTimedAction:derive("RenewableEnergyJobAction")
RenewableEnergy.JobAction = JobAction

function JobAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return self:units()
end

--- Whether the character stands where the menu would have walked them for the job
--- (RenewableEnergy.withinReach).
function JobAction:atJob()
    return RenewableEnergy.withinReach(self.character, self:target(), self.REACH)
end

--- Whether the authority may take the character as at the job. The server never calls isValid()
--- and NetTimedAction checks no distance, so a modified client could otherwise send a job for any
--- object in the world.
function JobAction:atJobForAuthority()
    return not isServer() or self:atJob()
end

function JobAction:isValid()
    -- Past here the server's complete() may already have moved what the job works with (into a
    -- bank, onto a vehicle, out of the inventory) while this client's action is still finishing;
    -- failing then would stop the action and empty the player's queue (ISBaseTimedAction.stop).
    -- Vanilla stops checking there too (ISInstallVehiclePart.isValid).
    if self.action and self.action:getJobDelta() >= 0.9 then
        return true
    end
    -- The game asks every tick (IsoGameCharacter.update), so this asks only what can change
    -- mid-job and is cheap to see. The rest waits for start() and complete().
    if not self:keeps() then
        return false
    end
    -- The server can't tell whether a remote player stands in the dark
    -- (IsoPlayer.tooDarkToRead), so the player's own side checks the light.
    if self:row().light and self.character:tooDarkToRead() then
        HaloTextHelper.addBadText(self.character, getText("Tooltip_RenewableEnergy_TooDark"))
        return false
    end
    return self:atJob()
end

function JobAction:waitToStart()
    self.character:faceThisObject(self:target())
    return self.character:shouldBeTurning()
end

function JobAction:update()
    self.character:faceThisObject(self:target())
    local metabolics = self:row().metabolics
    if metabolics then
        self.character:setMetabolicTarget(metabolics)
    end
end

function JobAction:startJob()
    local row = self:row()
    if row.begin then
        row.begin(self)
        return
    end
    self:setActionAnim(row.anim or "Loot")
    if not row.anim then
        self.character:SetVariable("LootPosition", row.position or "Low")
        if self.REPORTS_LOOT then
            self.character:reportEvent("EventLootItem")
        end
    elseif row.position then
        self.character:SetVariable("LootPosition", row.position)
    end
    if row.sound then
        self.sound = self.character:playSound(row.sound)
    end
end

function JobAction:start()
    -- Single player checks every rule once here, and again in complete(), as vanilla's crafting
    -- checks its recipe in start() and leaves isValid to whether the bench is still in use
    -- (ISHandcraftAction). A multiplayer client leaves them to the server's complete().
    if not isClient() and not self:canPerform() then
        self:forceStop()
        return
    end
    -- Server syncs can replace the item objects while the action waits in the queue.
    if isClient() then
        self:findItems()
    end
    self:startJob()
end

local function stopSound(self)
    if self.sound then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function JobAction:stop()
    stopSound(self)
    ISBaseTimedAction.stop(self)
end

function JobAction:perform()
    stopSound(self)
    local doneSound = self:row().doneSound
    if doneSound then
        self.character:playSound(doneSound)
    end
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

return JobAction
