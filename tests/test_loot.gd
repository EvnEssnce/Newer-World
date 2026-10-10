extends TestCase
## Loot rolls: weighted picks, rarity -> affix count, affix rules, gear score
## scaling, drop chance, serialization. Uses a hand-built ItemDatabase, plus one
## check that the real data files are consistent with each other.

var db: ItemDatabase
var rng: RandomNumberGenerator


func before_each() -> void:
	db = ItemDatabase.new()
	db.rarity_order = ["common", "rare", "legendary"]
	_rarity("common", 0)
	_rarity("rare", 2)
	_rarity("legendary", 9)  # more than any slot's pool
	_item("sword", "weapon", "broadsword", "weapon_power", 100.0)
	_item("cap", "head", "", "armor", 20.0)
	_affix("fierce", "damage_pct", 0.02, 0.06, ["weapon"])
	_affix("precise", "crit_chance", 0.01, 0.04, ["weapon", "head"])
	_affix("hale", "max_health", 20.0, 60.0, ["head"])
	var table := ItemDatabase.LootTable.new()
	table.id = "test"
	table.drop_chance = 1.0
	table.rolls = 2
	table.gear_score_min = 100
	table.gear_score_max = 140
	table.item_weights = {"sword": 1, "cap": 1}
	table.rarity_weights = {"common": 1, "rare": 1}
	db.tables["test"] = table
	rng = RandomNumberGenerator.new()
	rng.seed = 12345


func _rarity(id: String, affix_count: int) -> void:
	var r := ItemDatabase.RarityDef.new()
	r.id = id
	r.name = id.capitalize()
	r.affix_count = affix_count
	db.rarities[id] = r


func _item(id: String, slot: String, weapon_type: String, primary: String, base: float) -> void:
	var item := ItemDatabase.ItemDef.new()
	item.id = id
	item.name = id.capitalize()
	item.slot = slot
	item.weapon_type = weapon_type
	item.primary_stat = primary
	item.primary_base = base
	db.items[id] = item


func _affix(id: String, stat: String, low: float, high: float, slots: PackedStringArray) -> void:
	var affix := ItemDatabase.AffixDef.new()
	affix.id = id
	affix.name = id.capitalize()
	affix.stat = stat
	affix.min_per_100_gs = low
	affix.max_per_100_gs = high
	affix.slots = slots
	db.affixes[id] = affix


func test_weighted_pick_follows_weights() -> void:
	var counts := {"a": 0, "b": 0}
	for i in 20000:
		counts[LootRoller.pick_weighted({"a": 3, "b": 1}, rng)] += 1
	assert_almost(counts["a"] / 20000.0, 0.75, 0.02)


func test_weighted_pick_never_picks_zero_weight() -> void:
	for i in 2000:
		assert_eq(LootRoller.pick_weighted({"a": 0, "b": 2.5, "c": -1}, rng), "b")


func test_weighted_pick_with_no_positive_weight_picks_nothing() -> void:
	assert_eq(LootRoller.pick_weighted({}, rng), "")
	assert_eq(LootRoller.pick_weighted({"a": 0}, rng), "")


func test_rarity_sets_affix_count() -> void:
	assert_eq(LootRoller.roll_item(db.items["sword"], "common", 100, db, rng).affixes.size(), 0)
	assert_eq(LootRoller.roll_item(db.items["sword"], "rare", 100, db, rng).affixes.size(), 2)


func test_affix_count_is_capped_by_the_slot_pool() -> void:
	var item := LootRoller.roll_item(db.items["cap"], "legendary", 100, db, rng)
	assert_eq(item.affixes.size(), 2, "head can only roll precise and hale")


func test_affixes_match_the_slot_and_never_repeat() -> void:
	for i in 200:
		var item := LootRoller.roll_item(db.items["cap"], "rare", 100, db, rng)
		assert_false(item.affixes.has("fierce"), "fierce is weapon-only")
		assert_eq(item.affixes.size(), 2)


func test_affix_values_scale_with_gear_score() -> void:
	for i in 200:
		var item := LootRoller.roll_item(db.items["cap"], "rare", 150, db, rng)
		var hale: float = item.affixes["hale"]
		assert_true(hale >= 30.0 - 0.001 and hale <= 90.0 + 0.001,
				"20-60 per 100 gear score, at 150: %s" % hale)


func test_primary_stat_follows_the_gear_score_curve() -> void:
	# 4 whole steps of 5 above 100, +1.12% each, compounding.
	assert_almost(LootRoller.roll_item(db.items["sword"], "common", 123, db, rng).primary_value,
			100.0 * pow(1.0112, 4))
	assert_almost(LootRoller.roll_item(db.items["cap"], "common", 150, db, rng).primary_value,
			20.0 * pow(1.0112, 10))


func test_table_rolls_items_in_its_gear_score_range() -> void:
	for i in 200:
		var drops := LootRoller.roll_table(db.tables["test"], db, rng)
		assert_eq(drops.size(), 2)
		for item in drops:
			assert_true(item.gear_score >= 100 and item.gear_score <= 140)
			assert_true(item.rarity in ["common", "rare"])


func test_drop_chance() -> void:
	var table: ItemDatabase.LootTable = db.tables["test"]
	table.drop_chance = 0.0
	for i in 200:
		assert_eq(LootRoller.roll_table(table, db, rng).size(), 0)
	table.drop_chance = 0.25
	var dropped := 0
	for i in 20000:
		if not LootRoller.roll_table(table, db, rng).is_empty():
			dropped += 1
	assert_almost(dropped / 20000.0, 0.25, 0.02)


func test_same_seed_same_loot() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	for i in 50:
		var drops_a := LootRoller.roll_table(db.tables["test"], db, a)
		var drops_b := LootRoller.roll_table(db.tables["test"], db, b)
		for j in drops_a.size():
			assert_eq(drops_a[j].to_dict(), drops_b[j].to_dict())


func test_item_round_trips_through_a_dictionary() -> void:
	var item := LootRoller.roll_item(db.items["sword"], "rare", 117, db, rng)
	var copy := Item.from_dict(item.to_dict())
	assert_eq(copy.to_dict(), item.to_dict())


func test_validate_catches_broken_references() -> void:
	assert_eq(db.validate().size(), 0, "the test database is consistent")
	db.tables["test"].item_weights["ghost"] = 1
	db.items["cap"].weapon_type = "broadsword"
	assert_eq(db.validate().size(), 2)


func test_real_data_files_are_consistent() -> void:
	var real := ItemDatabase.from_tuning()
	assert_eq(real.validate(), PackedStringArray(), "data/loot.cfg, items.cfg and affixes.cfg")
	assert_true(real.tables.has("husk"), "Husks have a loot table")
	for def: ItemDatabase.ItemDef in real.items.values():
		if not def.class_id.is_empty():
			assert_true(ClassDef.for_id(def.class_id) != null,
					"%s's class %s exists" % [def.id, def.class_id])
		if not def.weapon_type.is_empty():
			assert_true(Tuning.has_file("weapon_" + def.weapon_type),
					"%s's weapon %s exists" % [def.id, def.weapon_type])
