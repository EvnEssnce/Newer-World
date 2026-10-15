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
	skills = TradeskillDefs.new()
	skills.add_skill("mining", "Mining", "gathering")
	skills.add_skill("smelting", "Smelting", "refining")
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


func test_gear_output_kind_is_reserved_for_later() -> void:
	ingot.output_kind = RecipeDefs.OUTPUT_GEAR
	assert_eq(defs.validate(db, skills).size(), 1, "gear recipes aren't built yet")
	var bag := Inventory.new(5)
	bag.add_stack("ore", 9, 10)
	assert_false(_check(1, bag).is_empty(), "and can't be crafted")
	ingot.output_kind = "potion"
	assert_eq(defs.validate(db, skills).size(), 1, "unknown kind")


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
