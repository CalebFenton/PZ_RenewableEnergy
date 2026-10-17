-- Gives the game's four drums, which the barrel digesters are built from, a ground model. Vanilla's
-- scripts give these moveables only an icon and a tile, so a dropped drum lies on the floor as its
-- flat icon; with a WorldStaticModel the floor draws the model instead (ItemModelRenderer.itemHasModel).
-- art/models builds each drum lying on its side, so a dropped one can't pass for one installed.
--
-- Shared: a dedicated server loads no client Lua, and both sides should hold the same scripts. The
-- game loads the scripts before the Lua on every boot and mod reload, then fires OnGameBoot
-- (Core.ResetLua, GameServer). An item reads its script's model whenever it is drawn
-- (InventoryItem.getWorldStaticItem), so drums already on the floor change too. The model is named
-- with its module: the script's own names were resolved before Lua ran (Item.resolveModelScripts).

require "RenewableEnergy/Sprites"

Events.OnGameBoot.Add(function()
    for itemType in pairs(RenewableEnergy.Sprites.digester.barrel) do
        local item = getScriptManager():getItem("Base." .. itemType)
        if item then
            item:DoParam("WorldStaticModel = RenewableEnergy." .. itemType .. "_Ground")
        end
    end
end)
