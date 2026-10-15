extends TestCase
## Stackable resources in the inventory, gathering nodes (charges, respawn,
## yields), the F key's choice and target, and the gather lock in PlayerState.
## Params are built by hand.

var params: GatherNodeParams
var rng: RandomNumberGenerator


func before_each() -> void:
	params = GatherNodeParams.new()
	params.id = "ore"
	params.name = "Test Deposit"
	params.resource = "ore_chunk"
	params.tradeskill = "mining"
	params.yield_min = 2
	params.yield_max = 4
	params.charges = 3
	params.gather_ticks = 120
	params.respawn_ticks = 600
	params.reach = 2.5
	rng = RandomNumberGenerator.new()
	rng.seed = 777


func _gear(item_id: String) -> Item:
	var item := Item.new()
	item.item_id = item_id
	item.rarity = "common"
	item.gear_score = 100
	return item


# --- Stacks ---

func test_add_stack_fills_existing_stacks_before_new_slots() -> void:
	var bag := Inventory.new(5)
	assert_eq(bag.add_stack("ore", 70, 100), 0)
	assert_eq(bag.items.size(), 1)
	assert_eq(bag.add_stack("ore", 50, 100), 0)
	assert_eq(bag.items.size(), 2, "70 + 50: one full stack and a new one")
	assert_eq(bag.items[0].count, 100)
	assert_eq(bag.items[1].count, 20)
	assert_true(bag.items[1].uid > 0 and bag.items[1].uid != bag.items[0].uid)
	assert_eq(bag.count_of("ore"), 120)


func test_stacks_of_different_resources_dont_merge() -> void:
	var bag := Inventory.new(5)
	bag.add_stack("ore", 10, 100)
	bag.add_stack("log", 10, 100)
	assert_eq(bag.items.size(), 2)
	assert_eq(bag.count_of("ore"), 10)
	assert_eq(bag.count_of("log"), 10)


func test_full_bag_keeps_what_fits_and_reports_the_rest() -> void:
	var bag := Inventory.new(2)
	bag.add(_gear("sword"))
	bag.add_stack("ore", 95, 100)
	assert_eq(bag.room_for("ore", 100), 5)
	assert_eq(bag.room_for("log", 100), 0, "no free slot, no stack of it")
	assert_eq(bag.add_stack("ore", 8, 100), 3, "5 topped up the stack, 3 left over")
	assert_eq(bag.count_of("ore"), 100)
	assert_eq(bag.add_stack("log", 4, 100), 4, "nothing fits")
	assert_eq(bag.items.size(), 2)


func test_gear_never_stacks() -> void:
	var bag := Inventory.new(3)
	bag.add(_gear("cap"))
	bag.add(_gear("cap"))
	assert_eq(bag.items.size(), 2)
	assert_eq(bag.items[0].count, 1)


func test_remove_count_takes_from_newest_stacks_and_frees_slots() -> void:
	var bag := Inventory.new(5)
	bag.add_stack("ore", 130, 100)  # 100 + 30
	assert_true(bag.remove_count("ore", 40))
	assert_eq(bag.count_of("ore"), 90)
	assert_eq(bag.items.size(), 1, "the 30 stack emptied and left")
	assert_eq(bag.items[0].count, 90)
	assert_false(bag.remove_count("ore", 91), "not enough")
	assert_eq(bag.count_of("ore"), 90, "unchanged when refused")
	assert_true(bag.remove_count("ore", 90))
	assert_eq(bag.items.size(), 0)


func test_stack_count_round_trips() -> void:
	var bag := Inventory.new(5)
	bag.add_stack("ore", 42, 100)
	var copy := Inventory.items_from_array(bag.to_array())
	assert_eq(copy[0].count, 42)
	assert_eq(copy[0].item_id, "ore")
	assert_eq(Item.from_dict({"item": "old"}).count, 1, "older dicts without a count are 1")


func test_validate_checks_resources() -> void:
	var db := ItemDatabase.new()
	var ore := ItemDatabase.ItemDef.new()
	ore.id = "ore_chunk"
	ore.name = "Ore"
	ore.slot = "resource"
	ore.max_stack = 100
	db.items["ore_chunk"] = ore
	assert_eq(db.validate().size(), 1, "a resource needs an icon")
	ore.icon = "rock"
	assert_eq(db.validate().size(), 1, "an unknown icon")
	ore.icon = "ore"
	assert_eq(db.validate(), PackedStringArray())
	ore.max_stack = 0
	ore.primary_stat = "armor"
	assert_eq(db.validate().size(), 2, "no max_stack, and a stat")
	ore.max_stack = 100
	ore.primary_stat = ""
	var cap := ItemDatabase.ItemDef.new()
	cap.id = "cap"
	cap.slot = "head"
	cap.primary_stat = "armor"
	cap.max_stack = 5
	db.items["cap"] = cap
	assert_eq(db.validate().size(), 1, "gear doesn't stack")
	cap.max_stack = 1
	var table := ItemDatabase.LootTable.new()
	table.id = "t"
	table.item_weights = {"ore_chunk": 1}
	db.tables["t"] = table
	assert_eq(db.validate().size(), 1, "loot tables roll gear only")


func test_icons_come_from_the_data() -> void:
	var def := ItemDatabase.ItemDef.new()
	def.slot = "weapon"
	assert_eq(def.icon_id(), "melee")
	def.ranged = true
	assert_eq(def.icon_id(), "ranged")
	def.slot = "head"
	def.ranged = false
	assert_eq(def.icon_id(), "head", "armor: its slot")
	def.icon = "wings"
	assert_eq(def.icon_id(), "wings", "icon overrides the slot")
	def.slot = "resource"
	def.icon = ""
	assert_eq(def.icon_id(), "", "resources have no default")
	var real := ItemDatabase.from_tuning()
	for item_id in real.items:
		assert_true(real.items[item_id].icon_id() in ItemDatabase.ICONS, item_id)
	var expected := {"iron_broadsword": "melee", "iron_maul": "melee", "iron_talons": "melee",
		"oakheart_shortstaffs": "melee", "ashwood_longbow": "ranged", "iron_crossbow": "ranged",
		"cinder_wraps": "ranged", "iron_knives": "ranged", "emberwood_staff": "ranged",
		"lifeweave_gauntlet": "ranged", "padded_cap": "head", "padded_jerkin": "chest",
		"padded_leggings": "legs", "cinder_plumes": "wings", "rustvein_ore": "ore",
		"rustvein_ingot": "ingot", "pine_log": "log", "pine_plank": "plank",
		"thistle_fiber": "fiber", "thistle_linen": "cloth"}
	for item_id: String in expected:
		assert_eq(real.items[item_id].icon_id(), expected[item_id], item_id)


# --- Nodes ---

func test_node_depletes_after_its_charges_then_respawns() -> void:
	var node := GatherNode.new(0, "ore", Vector3.ZERO, params.charges)
	node.take(10, params)
	node.take(11, params)
	assert_true(node.is_available())
	node.take(12, params)
	assert_false(node.is_available())
	assert_eq(node.respawn_tick, 612)
	assert_false(node.step(611, params))
	assert_true(node.step(612, params), "grows back on its tick")
	assert_eq(node.charges_left, 3)
	assert_false(node.step(613, params), "only once")


func test_take_on_a_depleted_node_does_nothing() -> void:
	var node := GatherNode.new(0, "ore", Vector3.ZERO, 1)
	node.take(5, params)
	node.take(6, params)
	assert_eq(node.charges_left, 0)
	assert_eq(node.respawn_tick, 605, "the first depletion's timer")


func test_reach_is_horizontal() -> void:
	var node := GatherNode.new(0, "ore", Vector3(0.0, 0.0, 0.0), 1)
	assert_true(node.in_reach(Vector3(2.0, 3.0, 0.0), 2.5), "height doesn't count")
	assert_false(node.in_reach(Vector3(2.0, 0.0, 1.6), 2.5))


func test_yield_and_time_follow_the_hooks() -> void:
	for i in 50:
		var amount := params.roll_yield(rng, 0)
		assert_true(amount >= 2 and amount <= 4)
	for i in 20:
		var amount := params.roll_yield(rng, 3)
		assert_true(amount >= 5 and amount <= 7, "a tradeskill bonus adds")
	assert_eq(params.ticks_for(1.0), 120)
	assert_eq(params.ticks_for(0.75), 90)
	assert_eq(params.ticks_for(0.0), 1, "never instant")


func test_node_params_validate_against_items() -> void:
	var db := ItemDatabase.new()
	assert_eq(params.validate(db).size(), 1, "unknown item")
	var cap := ItemDatabase.ItemDef.new()
	cap.id = "ore_chunk"
	cap.slot = "head"
	db.items["ore_chunk"] = cap
	assert_eq(params.validate(db).size(), 1, "not a resource")
	cap.slot = "resource"
	assert_eq(params.validate(db), PackedStringArray())


func test_real_gathering_data_is_consistent() -> void:
	var db := ItemDatabase.from_tuning()
	var kinds := GatherNodeParams.all_kinds()
	assert_true(kinds.size() >= 3, "ore, wood and fiber")
	for kind in kinds:
		assert_eq(kind.validate(db), PackedStringArray(), kind.id)
	for id in ["ore", "wood", "fiber"]:
		assert_true(GatherNodeParams.get_kind(id) != null, id)


# --- F ---

func test_f_picks_up_loot_first_then_gathers() -> void:
	assert_eq(GatherNode.interact_choice(true, 3), GatherNode.Interact.PICKUP, "loot wins")
	assert_eq(GatherNode.interact_choice(false, 3), GatherNode.Interact.GATHER)
	assert_eq(GatherNode.interact_choice(false, -1), GatherNode.Interact.PICKUP,
			"nothing near: the server says there's nothing to pick up")


func test_f_means_the_node_nearest_the_crosshair_in_reach() -> void:
	var nodes: Array[GatherNode] = [
		GatherNode.new(0, "ore", Vector3(2.0, 0.0, 0.0), 1),    # right
		GatherNode.new(1, "ore", Vector3(0.0, 0.0, -2.0), 1),   # straight ahead (-Z)
		GatherNode.new(2, "ore", Vector3(0.0, 0.0, -10.0), 1),  # ahead but out of reach
	]
	var reach := {"ore": 2.5}
	var eye := Vector3(0.0, 1.6, 0.0)
	assert_eq(GatherNode.pick(nodes, reach, Vector3.ZERO, eye, Vector3.FORWARD), 1)
	assert_eq(GatherNode.pick(nodes, reach, Vector3.ZERO, eye, Vector3.RIGHT), 0)
	nodes[1].charges_left = 0
	assert_eq(GatherNode.pick(nodes, reach, Vector3.ZERO, eye, Vector3.FORWARD), 0,
			"a depleted node is skipped")
	assert_eq(GatherNode.pick(nodes, reach, Vector3(0.0, 0.0, 9.0), eye, Vector3.FORWARD), -1)


# --- The gather lock ---

func test_gather_lock_is_a_server_event_and_refused_when_busy() -> void:
	var state := PlayerState.new()
	var events := state.server_events
	assert_true(state.start_gather(30))
	assert_true(state.is_equipping())
	assert_true(state.server_events > events)
	assert_false(state.can_change_loadout(), "walk only")
	assert_false(state.start_gather(30), "already busy")
	events = state.server_events
	state.cancel_equip()
	assert_false(state.is_equipping())
	assert_true(state.server_events > events, "cancelling is a server event too")
	state.dodge_tick = 3
	assert_false(state.start_gather(30), "mid-roll")
	state.dodge_tick = -1
	state.stagger_ticks = 10
	assert_false(state.start_gather(30), "staggered")
	state.stagger_ticks = 0
	state.attack_tick = 4
	assert_false(state.start_gather(30), "mid-attack")
	state.attack_tick = -1
	state.dead = true
	assert_false(state.start_gather(30), "defeated")
