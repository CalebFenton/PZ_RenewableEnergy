require "Moveables/ISMoveableDefinitions"

-- What dismantling (Scrap) a placed bank gives back, by the tile's Material. Panels, mounts,
-- the failsafe and the cell charger have no CanScrap: they are picked up whole (their tiles'
-- CustomItem) and unmounted by recipe, which returns the modules.
--
-- Shared, not client: scrapping completes on the server (ISMoveablesAction:complete), and a
-- dedicated server never loads client Lua.

local function addBankScrap(defs, material, items)
    defs.addScrapDefinition(material, { "Base.Screwdriver" }, {}, Perks.Electricity, 2000, "Dismantle", true, 10)
    for _, entry in ipairs(items) do
        defs.addScrapItem(material, entry[1], entry[2], entry[3], true)
    end
end

-- After vanilla's own OnGameBoot handler, which resets the definitions before filling them.
Events.OnGameBoot.Add(function()
    local defs = ISMoveableDefinitions:getInstance()
    addBankScrap(defs, "RenewableEnergyBatteryBox", {
        { "Base.Plank", 2, 70 },
        { "Base.Nails", 4, 60 },
        { "Base.ElectricWire", 2, 80 },
    })
    addBankScrap(defs, "RenewableEnergyBatteryBank", {
        { "Base.SmallSheetMetal", 2, 70 },
        { "Base.MetalBar", 2, 70 },
        { "Base.ElectricWire", 4, 80 },
        { "Base.Screws", 4, 60 },
    })
end)
