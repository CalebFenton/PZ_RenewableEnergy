-- Gives the vanilla drums the barrel digesters are built from a ground model. Vanilla gives these
-- moveables only an icon and a tile, so a dropped drum lies flat as its icon; a WorldStaticModel
-- makes the floor draw the model (ItemModelRenderer.itemHasModel). The models lie on their side so a
-- dropped drum can't pass for an installed one.
--
-- Shared because a dedicated server loads no client Lua and both sides should hold the same scripts.
-- OnGameBoot fires after the scripts load, on every boot and Lua reload (Core.ResetLua), and items
-- read the model whenever drawn, so drums already on the floor change too. The model is
-- module-qualified because script names were resolved before Lua ran (Item.resolveModelScripts).

require "RenewableEnergy/Sprites"

Events.OnGameBoot.Add(function()
    for itemType in pairs(RenewableEnergy.Sprites.digester.barrel) do
        local item = getScriptManager():getItem("Base." .. itemType)
        if item then
            item:DoParam("WorldStaticModel = RenewableEnergy." .. itemType .. "_Ground")
        end
    end
end)
