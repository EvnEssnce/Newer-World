class_name CraftingRules
extends RefCounted
## Whether a player can craft N of a recipe, and doing it. Pure logic, unit
## tested (tests/test_crafting.gd). The server runs `check` before starting the
## crafting lock and `apply` when it ends (the bag may have changed meanwhile, so
## apply checks again and changes nothing when it fails); the client's crafting
## panel uses `check` and `max_quantity` for its buttons.
##
## A craft is all or nothing: `check` makes the whole change on a copy of the bag
## first (inputs out, then the output in, so the slots the inputs free count as
## room), and `apply` only touches the real bag once that worked.
##
## Gear recipes (RecipeDefs.OUTPUT_GEAR): each craft of a batch is its own roll
## (roll_gear: LootRoller.roll_item at a gear score and rarity from the level)
## and needs its own free bag slot. Server only, with the server's seeded RNG.


## "" if `quantity` crafts of `recipe` can be made from `bag` at tradeskill
## level `level`, else why not (shown to the player). `skills` only names the
## skill in the message (null: the recipe's skill id).
static func check(recipe: RecipeDefs.Recipe, quantity: int, bag: Inventory, level: int,
		db: ItemDatabase, max_batch: int, skills: TradeskillDefs = null) -> String:
	if recipe == null:
		return "Unknown recipe."
	if quantity < 1 or quantity > max_batch:
		return "Craft 1 to %d at a time." % max_batch
	if not recipe.output_kind in RecipeDefs.OUTPUT_KINDS:
		return "That recipe can't be crafted."
	if level < recipe.level:
		var skill_name := skills.display_name(recipe.tradeskill) if skills else recipe.tradeskill
		return "Requires %s %d." % [skill_name, recipe.level]
	for item_id in recipe.inputs:
		var need := recipe.inputs[item_id] * quantity
		var have := bag.count_of(item_id)
		if have < need:
			return "Not enough %s (%d/%d)." % [_item_name(item_id, db), have, need]
	if not _make(recipe, quantity, bag.copy(), db):
		return "Your inventory is full."
	return ""


## Crafts `quantity` of `recipe` in `bag`: takes the inputs and adds the output
## (stacks, or for gear one rolled piece per craft, which needs `rng` and
## `skills`). "" when done; otherwise why not, and the bag is unchanged. What
## was made is appended to `made_items` when given (the feed: one stack of a
## resource, or each piece of gear).
static func apply(recipe: RecipeDefs.Recipe, quantity: int, bag: Inventory, level: int,
		db: ItemDatabase, max_batch: int, skills: TradeskillDefs = null,
		rng: RandomNumberGenerator = null, made_items: Array[Item] = []) -> String:
	var error := check(recipe, quantity, bag, level, db, max_batch, skills)
	if not error.is_empty():
		return error
	if recipe.output_kind == RecipeDefs.OUTPUT_GEAR:
		if skills == null or rng == null:
			return "That recipe can't be crafted."
		# check() just made the same room on a copy, so these can't fail.
		_take_inputs(recipe, quantity, bag)
		for i in quantity:
			var item := roll_gear(recipe, level, db, skills, rng)
			bag.add(item)
			made_items.append(item)
		return ""
	# The same steps just worked on a copy, so they can't fail here.
	_make(recipe, quantity, bag, db)
	made_items.append(Item.resource(recipe.output, made(recipe, quantity)))
	return ""


## One piece of a gear recipe's output made at crafting `level`: the item rolled
## like loot (LootRoller.roll_item: main stat, affixes), its gear score evenly in
## skills.gear_score_range(level) and its rarity from gear_rarity_weights(level).
static func roll_gear(recipe: RecipeDefs.Recipe, level: int, db: ItemDatabase,
		skills: TradeskillDefs, rng: RandomNumberGenerator) -> Item:
	var gs_range := skills.gear_score_range(level)
	var rarity := LootRoller.pick_weighted(skills.gear_rarity_weights(level), rng)
	if not db.rarities.has(rarity):  # no weights (validate() reports it): the lowest
		rarity = db.rarity_order[0] if not db.rarity_order.is_empty() else rarity
	var gear_score := rng.randi_range(gs_range.x, gs_range.y)
	var item := LootRoller.roll_item(db.items[recipe.output], rarity, gear_score, db, rng)
	item.crafted = true  # the inventory marks crafted gear
	return item


## How many of `recipe` one request could craft now (0 = none), at most `max_batch`.
static func max_quantity(recipe: RecipeDefs.Recipe, bag: Inventory, level: int,
		db: ItemDatabase, max_batch: int) -> int:
	# Not check(1): a full bag can have room for a bigger batch, whose inputs
	# empty a stack.
	if recipe == null or level < recipe.level or not recipe.output_kind in RecipeDefs.OUTPUT_KINDS:
		return 0
	var most := max_batch
	for item_id in recipe.inputs:
		@warning_ignore("integer_division")
		most = mini(most, bag.count_of(item_id) / maxi(1, recipe.inputs[item_id]))
	# Bag room is the only other limit; usually `most` fits at once.
	for quantity in range(most, 0, -1):
		if check(recipe, quantity, bag, level, db, max_batch).is_empty():
			return quantity
	return 0


## Items a batch of `quantity` makes.
static func made(recipe: RecipeDefs.Recipe, quantity: int) -> int:
	if recipe.output_kind == RecipeDefs.OUTPUT_GEAR:
		return quantity
	return recipe.output_count * quantity


## Takes the inputs and adds the output to `bag` (gear: only checks there's a
## free slot per piece; apply rolls them); false (with `bag` partly changed:
## only ever called on a copy first) if something didn't fit.
static func _make(recipe: RecipeDefs.Recipe, quantity: int, bag: Inventory, db: ItemDatabase) -> bool:
	if not _take_inputs(recipe, quantity, bag):
		return false
	var def: ItemDatabase.ItemDef = db.items.get(recipe.output)
	if def == null:
		return false
	if recipe.output_kind == RecipeDefs.OUTPUT_GEAR:
		return not def.is_resource() and bag.free_slots() >= quantity
	return bag.add_stack(recipe.output, made(recipe, quantity), def.max_stack) == 0


static func _take_inputs(recipe: RecipeDefs.Recipe, quantity: int, bag: Inventory) -> bool:
	for item_id in recipe.inputs:
		if not bag.remove_count(item_id, recipe.inputs[item_id] * quantity):
			return false
	return true


static func _item_name(item_id: String, db: ItemDatabase) -> String:
	var def: ItemDatabase.ItemDef = db.items.get(item_id) if db else null
	return def.name if def else item_id
