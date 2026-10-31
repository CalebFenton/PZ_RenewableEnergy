"""The static check's rules for the mod's items (dev/harness/docs/static-check.md, "Plugins").

| Check | What it catches |
| --- | --- |
| `item-ground-model` | An item of module RenewableEnergy with no `WorldStaticModel`: dropped, it has nothing to show on the ground. |
| `taught-recipe-learning` | A recipe an item teaches (`LearnedRecipes`) that is neither a build-menu entity's nor a craftRecipe with `NeedToBeLearn = true`, or one it offers to research (`ResearchableRecipes`) that is no such craftRecipe: the item would teach what every character knows. Research offers only crafting recipes (Item.getResearchableRecipes skips a name getCraftRecipe doesn't resolve). |
"""
from moddata import check

MODULE = "RenewableEnergy"


def _needs_learning(mod, name):
    recipe = mod.recipes.get(name)
    learned = recipe and recipe.block.get("NeedToBeLearn")
    return learned is not None and learned.value.lower() == "true"


@check
def item_ground_model(mod, game, report):
    for full_type, item in sorted(mod.items.items()):
        if item.module == MODULE and item.block.get("WorldStaticModel") is None:
            report.fail("item-ground-model", item.path, item.block.line, "%s has no WorldStaticModel" % full_type)


@check
def taught_recipe_learning(mod, game, report):
    taught = 0
    for full_type, item in sorted(mod.items.items()):
        if item.module != MODULE:
            continue
        for key, allowed, what in (("LearnedRecipes", mod.entity_recipes, "needs no learning"),
                                   ("ResearchableRecipes", (), "is no crafting recipe that needs learning")):
            for value in item.block.all(key):
                for name in filter(None, (n.strip() for n in value.value.split(";"))):
                    taught += 1
                    if name not in allowed and not _needs_learning(mod, name):
                        report.fail("taught-recipe-learning", item.path, value.line,
                                    "%s's %s names %s, which %s" % (full_type, key, name, what))
    if taught == 0:
        report.fail("taught-recipe-learning", __file__, None, "no item of module %s teaches a recipe" % MODULE)
