class_name CraftingRules
extends RefCounted
## Whether a player can craft N of a recipe, and doing it. Pure logic, unit
## tested (tests/test_crafting.gd). The server runs `check` before starting the
## crafting lock and `apply` when it ends (the bag may have changed meanwhile, so
## apply checks again and changes nothing when it fails); the client's crafting
## panel uses `check` and `max_quantity` for its buttons.
##
## A craft is all or nothing: `check` makes the whole change on a copy of the bag
## first (inputs out, then the output in as stacks, so the slots the inputs free
## count as room), and `apply` only touches the real bag once that worked.


## "" if `quantity` crafts of `recipe` can be made from `bag` at tradeskill
## level `level`, else why not (shown to the player). `skills` only names the
## skill in the message (null: the recipe's skill id).
static func check(recipe: RecipeDefs.Recipe, quantity: int, bag: Inventory, level: int,
		db: ItemDatabase, max_batch: int, skills: TradeskillDefs = null) -> String:
	if recipe == null:
		return "Unknown recipe."
	if quantity < 1 or quantity > max_batch:
		return "Craft 1 to %d at a time." % max_batch
	if recipe.output_kind != RecipeDefs.OUTPUT_ITEM:
		# Milestone 3 item 4: gear recipes roll their output through LootRoller here.
		return "That recipe can't be crafted yet."
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
## stacks. "" when done; otherwise why not, and the bag is unchanged.
static func apply(recipe: RecipeDefs.Recipe, quantity: int, bag: Inventory, level: int,
		db: ItemDatabase, max_batch: int, skills: TradeskillDefs = null) -> String:
	var error := check(recipe, quantity, bag, level, db, max_batch, skills)
	if not error.is_empty():
		return error
	# The same steps just worked on a copy, so they can't fail here.
	_make(recipe, quantity, bag, db)
	return ""


## How many of `recipe` one request could craft now (0 = none), at most `max_batch`.
static func max_quantity(recipe: RecipeDefs.Recipe, bag: Inventory, level: int,
		db: ItemDatabase, max_batch: int) -> int:
	# Not check(1): a full bag can have room for a bigger batch, whose inputs
	# empty a stack.
	if recipe == null or level < recipe.level or recipe.output_kind != RecipeDefs.OUTPUT_ITEM:
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
	return recipe.output_count * quantity


## Takes the inputs and adds the output to `bag`; false (with `bag` partly
## changed: only ever called on a copy first) if something didn't fit.
static func _make(recipe: RecipeDefs.Recipe, quantity: int, bag: Inventory, db: ItemDatabase) -> bool:
	for item_id in recipe.inputs:
		if not bag.remove_count(item_id, recipe.inputs[item_id] * quantity):
			return false
	var def: ItemDatabase.ItemDef = db.items.get(recipe.output)
	if def == null:
		return false
	return bag.add_stack(recipe.output, made(recipe, quantity), def.max_stack) == 0


static func _item_name(item_id: String, db: ItemDatabase) -> String:
	var def: ItemDatabase.ItemDef = db.items.get(item_id) if db else null
	return def.name if def else item_id
