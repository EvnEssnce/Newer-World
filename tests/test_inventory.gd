extends TestCase
## Inventory rules, personal ground loot (owner, reach, expiry, partial pickups)
## and the per-contributor kill roll. Items are built by hand.

var rng: RandomNumberGenerator


func before_each() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 4242


func _item(item_id: String) -> Item:
	var item := Item.new()
	item.item_id = item_id
	item.rarity = "common"
	item.gear_score = 100
	return item


func _items(count: int) -> Array[Item]:
	var items: Array[Item] = []
	for i in count:
		items.append(_item("thing_%d" % i))
	return items


func test_add_gives_unique_uids_until_full() -> void:
	var bag := Inventory.new(2)
	var a := _item("a")
	var b := _item("b")
	assert_true(bag.add(a))
	assert_true(bag.add(b))
	assert_true(a.uid > 0 and b.uid > 0 and a.uid != b.uid)
	assert_true(bag.is_full())
	assert_false(bag.add(_item("c")), "a full bag refuses")
	assert_eq(bag.items.size(), 2)


func test_remove_by_uid_frees_a_slot_and_uids_are_never_reused() -> void:
	var bag := Inventory.new(2)
	var a := _item("a")
	bag.add(a)
	bag.add(_item("b"))
	assert_eq(bag.remove(a.uid), a)
	assert_eq(bag.remove(a.uid), null, "already gone")
	assert_eq(bag.free_slots(), 1)
	var c := _item("c")
	bag.add(c)
	assert_true(c.uid != a.uid)
	assert_eq(bag.get_item(c.uid), c)


func test_inventory_round_trips_with_uids() -> void:
	var bag := Inventory.new(5)
	bag.add(_item("a"))
	bag.add(_item("b"))
	var copy := Inventory.items_from_array(bag.to_array())
	assert_eq(copy.size(), 2)
	assert_eq(copy[1].uid, bag.items[1].uid)
	assert_eq(copy[1].item_id, "b")


func test_only_the_owner_reaches_a_drop() -> void:
	var ground := GroundLoot.new()
	ground.add(7, Vector3(1, 0, 0), _items(1), 0, 100)
	assert_eq(ground.in_reach(7, Vector3.ZERO, 2.0).size(), 1)
	assert_eq(ground.in_reach(8, Vector3.ZERO, 2.0).size(), 0, "personal loot")


func test_reach_is_horizontal_and_sorted_nearest_first() -> void:
	var ground := GroundLoot.new()
	var far := ground.add(7, Vector3(1.8, 0, 0), _items(1), 0, 100)
	var near := ground.add(7, Vector3(0.5, 3.0, 0), _items(1), 0, 100)
	ground.add(7, Vector3(5, 0, 0), _items(1), 0, 100)
	var found := ground.in_reach(7, Vector3.ZERO, 2.0)
	assert_eq(found.size(), 2, "the one 5 m away is out of reach")
	assert_eq(found[0], near, "height doesn't count")
	assert_eq(found[1], far)


func test_drops_expire_at_their_tick() -> void:
	var ground := GroundLoot.new()
	var drop := ground.add(7, Vector3.ZERO, _items(1), 10, 50)
	assert_eq(ground.expire(59).size(), 0)
	var gone := ground.expire(60)
	assert_eq(gone.size(), 1)
	assert_eq(gone[0], drop)
	assert_false(ground.drops.has(drop.id))


func test_pickup_into_a_nearly_full_bag_leaves_the_rest() -> void:
	var ground := GroundLoot.new()
	var drop := ground.add(7, Vector3.ZERO, _items(3), 0, 100)
	var bag := Inventory.new(2)
	var moved := ground.take_into(drop, bag)
	assert_eq(moved.size(), 2)
	assert_eq(bag.items.size(), 2)
	assert_eq(drop.items.size(), 1, "one left on the ground")
	assert_true(ground.drops.has(drop.id))
	bag.remove(bag.items[0].uid)
	assert_eq(ground.take_into(drop, bag).size(), 1)
	assert_false(ground.drops.has(drop.id), "an emptied drop is gone")


func test_remove_owner_clears_only_their_drops() -> void:
	var ground := GroundLoot.new()
	ground.add(7, Vector3.ZERO, _items(1), 0, 100)
	ground.add(7, Vector3.ZERO, _items(1), 0, 100)
	ground.add(8, Vector3.ZERO, _items(1), 0, 100)
	assert_eq(ground.remove_owner(7), 2)
	assert_eq(ground.drops.size(), 1)


func test_every_contributor_gets_their_own_roll() -> void:
	var db := _one_item_db()
	var table: ItemDatabase.LootTable = db.tables["t"]
	var loot := LootRoller.roll_kill(table, db, [3, 5, 9] as Array[int], rng)
	assert_eq(loot.keys(), [3, 5, 9])
	for peer: int in loot:
		assert_eq(loot[peer].size(), 1)
	assert_true(loot[3][0] != loot[5][0], "separate items, not one shared drop")


func test_contributors_with_an_empty_roll_are_left_out() -> void:
	var db := _one_item_db()
	var table: ItemDatabase.LootTable = db.tables["t"]
	table.drop_chance = 0.0
	assert_eq(LootRoller.roll_kill(table, db, [3, 5] as Array[int], rng).size(), 0)
	table.drop_chance = 0.5
	var drops := 0
	for i in 4000:
		drops += LootRoller.roll_kill(table, db, [3, 5] as Array[int], rng).size()
	assert_almost(drops / 8000.0, 0.5, 0.03, "each player rolls the drop chance separately")


func _one_item_db() -> ItemDatabase:
	var db := ItemDatabase.new()
	db.rarity_order = ["common"]
	var rarity := ItemDatabase.RarityDef.new()
	rarity.id = "common"
	db.rarities["common"] = rarity
	var def := ItemDatabase.ItemDef.new()
	def.id = "cap"
	def.slot = "head"
	def.primary_stat = "armor"
	db.items["cap"] = def
	var table := ItemDatabase.LootTable.new()
	table.id = "t"
	table.drop_chance = 1.0
	table.rolls = 1
	table.gear_score_min = 100
	table.gear_score_max = 100
	table.item_weights = {"cap": 1}
	table.rarity_weights = {"common": 1}
	db.tables["t"] = table
	return db


func test_stat_text_reads_as_bonuses() -> void:
	assert_eq(Item.display_stat("crit_chance", 0.031), "+3.1% crit chance")
	assert_eq(Item.display_stat("max_health", 41.6), "+42 max health")
	assert_eq(Item.display_stat("block_stamina_reduction", 0.06), "-6.0% stamina cost of blocked hits")
	assert_eq(Item.display_stat("mystery", 2.0), "mystery +2", "unknown stats fall back")
