-- What every side reads of a feature the authority keeps in a Global Object System: its summary,
-- which the server sends every client, and on the authority its record. The server and client
-- object systems set owner.serverSystem and owner.clientSystem.

require "RenewableEnergy/Utilities"

RenewableEnergy = RenewableEnergy or {}
local GlobalObjects = {}
RenewableEnergy.GlobalObjects = GlobalObjects

--- Adds to `owner`:
--- owner.summaryOf(isoObject), what this client keeps of the object, or nil before it arrives;
--- owner.recordAt(x, y, z) and owner.recordOf(isoObject), its record on the authority, loaded or
--- not, nil elsewhere;
--- owner.currentSummary(isoObject), the summary as this side knows it: the authority builds it
--- from its record, which a job may have changed since the last summary went out.
--- `decorate(summary, isoObject)` adds to each summary read what this side's copies of the
--- object's containers hold now. Every side has those copies, and the summary is only as fresh as
--- the authority's last pass, so values that follow from the containers aren't sent.
function GlobalObjects.addAccessors(owner, decorate)
    function owner.summaryOf(isoObject)
        local system = owner.clientSystem
        local globalObject = system and system.system:getObjectAt(isoObject:getX(), isoObject:getY(), isoObject:getZ())
        local received = globalObject and globalObject:getModData().summary
        if not received then
            return nil
        end
        -- A copy: the received summary is the system's own table.
        local summary = {}
        for key, value in pairs(received) do
            summary[key] = value
        end
        decorate(summary, isoObject)
        return summary
    end

    function owner.recordAt(x, y, z)
        local system = not isClient() and owner.serverSystem
        return system and system:getLuaObjectAt(x, y, z) or nil
    end

    function owner.recordOf(isoObject)
        return owner.recordAt(isoObject:getX(), isoObject:getY(), isoObject:getZ())
    end

    function owner.currentSummary(isoObject)
        local record = owner.recordOf(isoObject)
        if not record then
            return owner.summaryOf(isoObject)
        end
        local summary = record:buildSummary()
        decorate(summary, isoObject)
        return summary
    end
end

return GlobalObjects
