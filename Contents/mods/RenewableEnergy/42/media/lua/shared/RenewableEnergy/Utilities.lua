-- The mod's only global. Every module hangs its table off it, so any file may be loaded first:
-- each one creates the table if nothing has yet.
RenewableEnergy = RenewableEnergy or {}

return RenewableEnergy
