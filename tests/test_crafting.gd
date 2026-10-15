extends TestCase
## Recipes and stations (RecipeDefs), the craft rules (CraftingRules: level,
## materials, bag room, all-or-nothing), stations (CraftingStation.pick) and
## the F key's choice with stations. Data is built by hand, except the
## real-data check.

var db: ItemDatabase
var skills: TradeskillDefs
var defs: RecipeDefs
var ingot: RecipeDefs.Recipe


func before_each() -> void:
	db = ItemDatabase.new()
	_resource("ore", "Ore", 10)
	_resource("ingot", "Ingot", 10)
	_resource("coal", "Coal", 10)
	var cap := ItemDatabase.ItemDef.new()
	cap.id = "cap"
	cap.name = "Cap"
	cap.slot = "head"
	cap.primary_stat = "armor"
	db.items["cap"] = cap
	_resource("linen", "Linen", 10)
	for rarity in ["common", "rare", "epic", "legendary"]:
		var def := ItemDatabase.RarityDef.new()
		def.id = rarity
		def.name = rarity.capitalize()
		db.rarities[rarity] = def
		db.rarity_order.append(rarity)
	skills = TradeskillDefs.new()
	skills.add_skill("mining", "Mining", "gathering")
	skills.add_skill("smelting", "Smelting", "refining")
	skills.add_skill("armoring", "Armorcraft", "crafting")
	skills.rarity_weights_start = {"common": 85, "rare": 14, "epic": 1, "legendary": 0}
	skills.rarity_weights_end = {"common": 30, "rare": 50, "epic": 20, "legendary": 0}
	defs = RecipeDefs.new()
	defs.max_batch = 20
	var forge := defs.add_station("forge", "Forge")
	forge.reach = 3.0
	ingot = defs.add_recipe("ingot", "smelting", "forge")
	ingot.level = 1
	ingot.craft_ticks = 120
	ingot.xp = 30
	ingot.inputs = {"ore": 3}
	ingot.output = "ingot"
	ingot.output_count = 1


func _resource(id: String, display_name: String, stack: int) -> void:
	var def := ItemDatabase.ItemDef.new()
	def.id = id
	def.name = display_name
	def.slot = "resource"
	def.max_stack = stack
	db.items[id] = def


func _gear(item_id: String) -> Item:
	var item := Item.new()
	item.item_id = item_id
	item.rarity = "common"
	item.gear_score = 100
	return item


func _check(quantity: int, bag: Inventory, level: int = 1) -> String:
	return CraftingRules.check(ingot, quantity, bag, level, db, defs.max_batch, skills)


# --- Data ---

func test_hand_built_data_validates() -> void:
	assert_eq(defs.validate(db, skills), PackedStringArray())


func test_validate_catches_bad_recipes() -> void:
	var bad := defs.add_recipe("bad", "mining", "anvil")
	bad.level = 0
	bad.inputs = {"cap": 1, "nothing": 0}
	bad.output = "cap"
	var problems := defs.validate(db, skills)
	# gathering skill, level, station, input not a resource, uses its own
	# output, unknown input, count 0, output not a resource
	assert_eq(problems.size(), 8, "\n".join(problems))


## A level-1 Armorcraft recipe: 4 linen + 1 ingot -> one rolled Cap.
func _cap_recipe() -> RecipeDefs.Recipe:
	var recipe := defs.add_recipe("cap", "armoring", "forge")
	recipe.level = 1
	recipe.craft_ticks = 240
	recipe.xp = 150
	recipe.inputs = {"linen": 4, "ingot": 1}
	recipe.output_kind = RecipeDefs.OUTPUT_GEAR
	recipe.output = "cap"
	return recipe


func test_unknown_output_kind() -> void:
	ingot.output_kind = "potion"
	assert_eq(defs.validate(db, skills).size(), 1, "unknown kind")
	var bag := Inventory.new(5)
	bag.add_stack("ore", 9, 10)
	assert_false(_check(1, bag).is_empty(), "and can't be crafted")


func test_batch_time_and_station_lists() -> void:
	assert_eq(ingot.ticks_for(1), 120)
	assert_eq(ingot.ticks_for(5), 600, "one lock for the whole batch")
	assert_eq(ingot.display_name(db), "Ingot", "no name: the output's")
	defs.add_station("loom", "Loom")
	var cloth := defs.add_recipe("cloth", "smelting", "loom")
	assert_eq(defs.recipes_for("forge"), [ingot] as Array[RecipeDefs.Recipe])
	assert_eq(defs.recipes_for("loom"), [cloth] as Array[RecipeDefs.Recipe])


func test_real_recipe_data_is_consistent() -> void:
	var real := RecipeDefs.from_tuning()
	assert_eq(real.validate(ItemDatabase.from_tuning(), TradeskillDefs.from_tuning()), PackedStringArray())
	assert_true(real.stations.has("forge"), "a Forge")
	for id in ["rustvein_ingot", "pine_plank", "thistle_linen"]:
		var recipe := real.get_recipe(id)
		assert_true(recipe != null, id)
		if recipe:
			assert_eq(recipe.station, "forge", id)
			assert_eq(recipe.output_kind, RecipeDefs.OUTPUT_ITEM, id)
			assert_true(recipe.inputs.size() >= 1 and recipe.xp > 0, id)
	assert_eq(real.get_recipe("rustvein_ingot").tradeskill, "smelting")
	assert_true(real.get_recipe("rustvein_ingot").inputs.has("rustvein_ore"))


func test_real_gear_recipes() -> void:
	var real := RecipeDefs.from_tuning()
	var real_db := ItemDatabase.from_tuning()
	var level_one := {}
	var made := {}
	for recipe: RecipeDefs.Recipe in real.recipes.values():
		if recipe.output_kind != RecipeDefs.OUTPUT_GEAR:
			continue
		made[recipe.output] = true
		assert_true(recipe.tradeskill in ["weaponsmithing", "armoring"], recipe.id)
		assert_true(recipe.xp > 0, recipe.id + " gives XP")
		for item_id in recipe.inputs:
			assert_true(item_id in ["rustvein_ingot", "pine_plank", "thistle_linen"], recipe.id + ": refined materials")
		if recipe.level == 1:
			level_one[recipe.tradeskill] = true
	assert_true(level_one.has("weaponsmithing") and level_one.has("armoring"), "a level-1 recipe per skill")
	for item_id in real_db.items:
		var def := real_db.items[item_id]
		if def.slot == "weapon" or def.slot in ["head", "chest", "legs"]:
			assert_true(made.has(item_id), "a recipe makes " + item_id)


# --- Gear ---

func test_gear_recipes_validate() -> void:
	var recipe := _cap_recipe()
	assert_eq(defs.validate(db, skills), PackedStringArray())
	recipe.output = "ore"
	assert_eq(defs.validate(db, skills).size(), 1, "a gear output must be gear")
	recipe.output = "cap"
	recipe.output_count = 2
	assert_eq(defs.validate(db, skills).size(), 1, "one per craft")
	recipe.output_count = 1
	skills.rarity_weights_end = {"mythic": 5, "rare": 1}
	assert_eq(defs.validate(db, skills).size(), 1, "unknown rarity")
	skills.rarity_weights_start = {"common": 0}
	skills.rarity_weights_end = {"common": 0}
	assert_eq(defs.validate(db, skills).size(), 2, "nothing to roll at level 1 or the cap")
	ingot.output_kind = RecipeDefs.OUTPUT_GEAR
	defs.recipes.erase("cap")
	assert_eq(defs.validate(db, skills).size(), 3, "a resource output, plus the empty weights")


func test_gear_score_range_rises_with_level() -> void:
	assert_eq(skills.gear_score_range(1), Vector2i(100, 110))
	assert_eq(skills.gear_score_range(10), Vector2i(103, 113))
	assert_eq(skills.gear_score_range(50), Vector2i(115, 125))
	assert_eq(skills.gear_score_range(100), Vector2i(130, 140))
	skills.gear_score_cap = 120
	assert_eq(skills.gear_score_range(100), Vector2i(120, 120), "both ends capped")
	assert_eq(skills.gear_score_range(0), Vector2i(100, 110), "never below level 1's")


func test_rarity_odds_shift_with_level() -> void:
	var low := skills.gear_rarity_odds(1)
	assert_almost(low["common"], 0.85, 0.0001)
	assert_almost(low["epic"], 0.01, 0.0001)
	var high := skills.gear_rarity_odds(100)
	assert_almost(high["rare"], 0.5, 0.0001)
	assert_almost(high["epic"], 0.2, 0.0001)
	var mid := skills.gear_rarity_odds(50)
	assert_true(mid["common"] < low["common"] and mid["common"] > high["common"], "blended")
	assert_true(mid["epic"] > low["epic"] and mid["epic"] < high["epic"], "blended")
	for odds: Dictionary in [low, mid, high]:
		assert_eq(odds["legendary"], 0.0, "never Legendary")
	assert_almost(skills.gear_rarity_odds(500)["rare"], 0.5, 0.0001, "past the cap: the cap's")


func _cap_bag() -> Inventory:
	var bag := Inventory.new(6)
	bag.add_stack("linen", 10, 10)
	bag.add_stack("ingot", 2, 10)
	return bag


func _roll_caps(seed_value: int, quantity: int, level: int) -> Array:
	var recipe := _cap_recipe()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bag := _cap_bag()
	var made: Array[Item] = []
	assert_eq(CraftingRules.apply(recipe, quantity, bag, level, db, defs.max_batch, skills, rng, made), "")
	var dicts := []
	for item in made:
		dicts.append(item.to_dict())
	return dicts


func test_gear_craft_rolls_items_into_the_bag() -> void:
	var recipe := _cap_recipe()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bag := _cap_bag()
	var made: Array[Item] = []
	assert_eq(CraftingRules.apply(recipe, 2, bag, 1, db, defs.max_batch, skills, rng, made), "")
	assert_eq(made.size(), 2, "one piece per craft")
	assert_eq(CraftingRules.made(recipe, 2), 2)
	assert_eq(bag.count_of("linen"), 2)
	assert_eq(bag.count_of("ingot"), 0, "the emptied ingot stack's slot freed")
	for item in made:
		assert_eq(item.item_id, "cap")
		assert_true(item.gear_score >= 100 and item.gear_score <= 110, "GS %d in level 1's range" % item.gear_score)
		assert_true(db.rarities.has(item.rarity), item.rarity)
		assert_true(item.uid > 0 and bag.get_item(item.uid) == item, "in the bag")


func test_gear_rolls_are_seeded() -> void:
	var first := _roll_caps(42, 2, 60)
	assert_eq(first, _roll_caps(42, 2, 60), "same seed, same pieces")
	assert_eq(first.size(), 2)
	var scores := {}
	for seed_value in 30:
		for entry: Dictionary in _roll_caps(seed_value, 1, 100):
			var item := Item.from_dict(entry)
			assert_true(item.gear_score >= 130 and item.gear_score <= 140, "level 100: GS %d" % item.gear_score)
			assert_true(item.rarity != "legendary")
			scores[item.gear_score] = true
	assert_true(scores.size() > 3, "spread over the range")


func test_rarity_follows_the_level() -> void:
	var recipe := _cap_recipe()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var counts := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	for i in 2000:
		counts[CraftingRules.roll_gear(recipe, 100, db, skills, rng).rarity] += 1
	assert_true(counts["rare"] > 850 and counts["rare"] < 1150, "about 50%% Rare: %d" % counts["rare"])
	assert_true(counts["epic"] > 300 and counts["epic"] < 500, "about 20%% Epic: %d" % counts["epic"])
	assert_eq(counts["legendary"], 0)


func test_full_bag_refuses_gear_and_keeps_the_inputs() -> void:
	var recipe := _cap_recipe()
	var bag := Inventory.new(3)
	bag.add_stack("linen", 10, 10)
	bag.add_stack("ingot", 5, 10)
	bag.add(_gear("cap"))
	var before := bag.to_array()
	var rng := RandomNumberGenerator.new()
	var made: Array[Item] = []
	# 4 linen + 1 ingot leave both stacks: no slot for the piece.
	assert_eq(CraftingRules.check(recipe, 1, bag, 1, db, defs.max_batch, skills), "Your inventory is full.")
	assert_eq(CraftingRules.apply(recipe, 1, bag, 1, db, defs.max_batch, skills, rng, made),
			"Your inventory is full.")
	assert_eq(bag.to_array(), before, "nothing taken")
	assert_true(made.is_empty())
	assert_eq(CraftingRules.max_quantity(recipe, bag, 1, db, defs.max_batch), 0)
	# One more free slot: one piece, not two (each needs its own slot).
	bag.capacity = 4
	assert_eq(CraftingRules.max_quantity(recipe, bag, 1, db, defs.max_batch), 1)
	assert_eq(CraftingRules.check(recipe, 2, bag, 1, db, defs.max_batch, skills), "Your inventory is full.")
	assert_eq(CraftingRules.apply(recipe, 1, bag, 1, db, defs.max_batch, skills, rng, made), "")
	assert_eq(made.size(), 1)


func test_gear_needs_the_level_and_an_rng() -> void:
	var recipe := _cap_recipe()
	recipe.level = 5
	var bag := _cap_bag()
	var rng := RandomNumberGenerator.new()
	assert_eq(CraftingRules.apply(recipe, 1, bag, 4, db, defs.max_batch, skills, rng), "Requires Armorcraft 5.")
	recipe.level = 1
	assert_false(CraftingRules.apply(recipe, 1, bag, 1, db, defs.max_batch, skills).is_empty(), "no rng: refused")
	assert_eq(bag.count_of("linen"), 10, "nothing taken")


func test_gear_craft_xp_raises_the_roll() -> void:
	var recipe := _cap_recipe()
	skills.gear_score_per_level = 2.0
	var mine := Tradeskills.new(skills)
	var before := skills.gear_score_range(mine.level("armoring"))
	# What CraftingSystem.finish_craft gives (TradeskillSystem.on_crafted): xp x quantity.
	assert_eq(mine.add_xp(recipe.tradeskill, recipe.xp * 2), 1, "300 XP: level 2 (100), not 3 (283 more)")
	assert_eq(mine.level("armoring"), 2)
	assert_eq(skills.gear_score_range(mine.level("armoring")), before + Vector2i(2, 2))


# --- Rules ---

func test_can_craft_with_materials_and_level() -> void:
	var bag := Inventory.new(5)
	bag.add_stack("ore", 7, 10)
	assert_eq(_check(1, bag), "")
	assert_eq(_check(2, bag), "")
	assert_eq(_check(3, bag), "Not enough Ore (7/9).")
	assert_false(_check(0, bag).is_empty(), "at least one")
	assert_false(_check(21, bag).is_empty(), "at most max_batch")


func test_level_lock() -> void:
	ingot.level = 5
	var bag := Inventory.new(5)
	bag.add_stack("ore", 9, 10)
	assert_eq(_check(1, bag, 4), "Requires Smelting 5.")
	assert_eq(_check(1, bag, 5), "")
	assert_eq(CraftingRules.apply(ingot, 1, bag, 4, db, defs.max_batch), "Requires smelting 5.",
			"without skill names: the id")
	assert_eq(bag.count_of("ore"), 9, "nothing taken")


func test_apply_takes_inputs_and_adds_output_stacks() -> void:
	var bag := Inventory.new(5)
	bag.add_stack("ore", 10, 10)
	bag.add_stack("ore", 4, 10)
	bag.add_stack("ingot", 9, 10)
	assert_eq(CraftingRules.apply(ingot, 4, bag, 1, db, defs.max_batch, skills), "")
	assert_eq(bag.count_of("ore"), 2)
	assert_eq(bag.count_of("ingot"), 13, "9 + 4: topped up, then a new stack")
	assert_eq(CraftingRules.made(ingot, 4), 4)
	ingot.output_count = 2
	assert_eq(CraftingRules.made(ingot, 3), 6)


func test_full_bag_fails_and_changes_nothing() -> void:
	var bag := Inventory.new(2)
	bag.add_stack("ore", 10, 10)
	bag.add(_gear("cap"))
	var before := bag.to_array()
	# 3 ore -> 1 ingot: the ore stack stays (7 left), no slot for the ingot.
	assert_eq(_check(1, bag), "Your inventory is full.")
	assert_eq(CraftingRules.apply(ingot, 1, bag, 1, db, defs.max_batch, skills), "Your inventory is full.")
	assert_eq(bag.to_array(), before, "nothing lost, nothing gained")


func test_inputs_that_free_a_slot_make_room() -> void:
	var bag := Inventory.new(2)
	bag.add_stack("ore", 9, 10)
	bag.add(_gear("cap"))
	# 9 ore -> 3 ingots: the ore stack empties and its slot takes the ingots.
	assert_eq(CraftingRules.apply(ingot, 3, bag, 1, db, defs.max_batch, skills), "")
	assert_eq(bag.count_of("ore"), 0)
	assert_eq(bag.count_of("ingot"), 3)
	assert_eq(bag.items.size(), 2)


func test_failed_check_leaves_every_stack_alone() -> void:
	ingot.inputs = {"ore": 2, "coal": 1}
	var bag := Inventory.new(4)
	bag.add_stack("ore", 6, 10)
	bag.add_stack("coal", 2, 10)
	var before := bag.to_array()
	assert_eq(CraftingRules.apply(ingot, 3, bag, 1, db, defs.max_batch, skills), "Not enough Coal (2/3).")
	assert_eq(bag.to_array(), before, "the ore wasn't taken either")
	assert_eq(CraftingRules.apply(ingot, 2, bag, 1, db, defs.max_batch, skills), "")
	assert_eq(bag.count_of("ore"), 2)
	assert_eq(bag.count_of("coal"), 0)


func test_max_quantity() -> void:
	var bag := Inventory.new(3)
	assert_eq(CraftingRules.max_quantity(ingot, bag, 1, db, defs.max_batch), 0, "no ore")
	bag.add_stack("ore", 20, 10)  # two full stacks
	assert_eq(CraftingRules.max_quantity(ingot, bag, 1, db, defs.max_batch), 6, "materials")
	assert_eq(CraftingRules.max_quantity(ingot, bag, 1, db, 4), 4, "max_batch")
	assert_eq(CraftingRules.max_quantity(ingot, bag, 0, db, defs.max_batch), 0, "level")
	bag.add(_gear("cap"))  # bag full: 2 ore stacks + cap
	# 1 ingot needs a slot: only when a whole ore stack (10, so 4 crafts = 12 ore) goes.
	assert_eq(CraftingRules.max_quantity(ingot, bag, 1, db, defs.max_batch), 6)
	assert_eq(_check(3, bag), "Your inventory is full.", "9 ore leaves both stacks")
	assert_eq(_check(4, bag), "")


func test_copy_is_separate() -> void:
	var bag := Inventory.new(3)
	bag.add_stack("ore", 5, 10)
	var copy := bag.copy()
	copy.remove_count("ore", 5)
	copy.add(_gear("cap"))
	assert_eq(bag.count_of("ore"), 5)
	assert_eq(bag.items.size(), 1)
	var added := _gear("cap")
	bag.add(added)
	assert_eq(added.uid, copy.items[0].uid, "the copy continues the same uids")


# --- Stations and F ---

func test_f_order_is_loot_then_node_then_station() -> void:
	assert_eq(GatherNode.interact_choice(true, 3, 1), GatherNode.Interact.PICKUP, "loot wins")
	assert_eq(GatherNode.interact_choice(false, 3, 1), GatherNode.Interact.GATHER, "then nodes")
	assert_eq(GatherNode.interact_choice(false, -1, 1), GatherNode.Interact.CRAFT, "then stations")
	assert_eq(GatherNode.interact_choice(false, -1, -1), GatherNode.Interact.PICKUP, "nothing: ask for a pickup")
	assert_eq(GatherNode.interact_choice(false, -1), GatherNode.Interact.PICKUP, "no station given")


func test_f_means_the_station_nearest_the_crosshair_in_reach() -> void:
	var stations: Array[CraftingStation] = [
		CraftingStation.new(0, "forge", Vector3(2.5, 0.0, 0.0)),    # right
		CraftingStation.new(1, "forge", Vector3(0.0, 0.0, -2.5)),   # straight ahead (-Z)
		CraftingStation.new(2, "forge", Vector3(0.0, 0.0, -9.0)),   # ahead, out of reach
		CraftingStation.new(3, "loom", Vector3(-1.0, 0.0, 0.0)),    # unknown kind: no reach
	]
	var reach := {"forge": 3.0}
	var eye := Vector3(0.0, 1.6, 0.0)
	assert_eq(CraftingStation.pick(stations, reach, Vector3.ZERO, eye, Vector3.FORWARD), 1)
	assert_eq(CraftingStation.pick(stations, reach, Vector3.ZERO, eye, Vector3.RIGHT), 0)
	assert_eq(CraftingStation.pick(stations, reach, Vector3(20.0, 0.0, 0.0), eye, Vector3.FORWARD), -1)
	assert_true(stations[0].in_reach(Vector3(2.5, 5.0, 2.9), 3.0), "height doesn't count")
