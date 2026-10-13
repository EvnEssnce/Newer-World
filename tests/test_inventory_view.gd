extends TestCase
## The I panel's view of the bag: comparisons that include affixes, and the
## client-side type/class filters and sorts (InventoryPanel.bag_view).
## Hand-built ItemDatabase.

var db: ItemDatabase

const FIGHTER: PackedStringArray = ["broadsword", "spear"]
const JUGGERNAUT: PackedStringArray = ["halberd"]


func before_each() -> void:
	db = ItemDatabase.new()
	db.rarity_order = PackedStringArray(["common", "rare", "epic"])
	_def("sword", "weapon", "broadsword", "", "weapon_power")
	_def("halberd", "weapon", "halberd", "", "weapon_power")
	_def("cap", "head", "", "", "armor")
	_def("jerkin", "chest", "", "", "armor")
	_def("plumes", "wings", "", "fighter", "wing_power")
	var affix := ItemDatabase.AffixDef.new()
	affix.id = "vigor"
	affix.stat = "max_health"
	db.affixes["vigor"] = affix


func _def(id: String, slot: String, weapon_type: String, class_id: String, primary: String) -> void:
	var def := ItemDatabase.ItemDef.new()
	def.id = id
	def.name = id.capitalize()
	def.slot = slot
	def.weapon_type = weapon_type
	def.class_id = class_id
	def.primary_stat = primary
	def.primary_base = 100.0
	db.items[id] = def


func _item(id: String, gear_score: int, rarity: String = "common", primary: float = 20.0) -> Item:
	var item := Item.new()
	item.item_id = id
	item.rarity = rarity
	item.gear_score = gear_score
	item.primary_value = primary
	return item


func _ids(items: Array[Item]) -> Array:
	var ids := []
	for item in items:
		ids.append("%s%d" % [item.item_id, item.gear_score])
	return ids


func test_comparison_counts_affixes_not_only_the_primary_stat() -> void:
	var common := _item("jerkin", 120, "common", 30.0)
	var rare := _item("jerkin", 115, "rare", 28.0)
	rare.affixes["vigor"] = 42.0
	var changes := Item.stat_changes(rare.stat_totals(db), common.stat_totals(db))
	assert_eq(changes.keys(), ["armor", "max_health"], "primary first, then the affix stat")
	assert_almost(changes["armor"], -2.0, 0.001)
	assert_almost(changes["max_health"], 42.0, 0.001)
	# The other way round, the affix is a loss.
	var back := Item.stat_changes(common.stat_totals(db), rare.stat_totals(db))
	assert_almost(back["max_health"], -42.0, 0.001)


func test_tiny_changes_are_left_out_and_signs_read_right() -> void:
	var changes := Item.stat_changes({"armor": 30.2, "crit_chance": 0.0301},
			{"armor": 30.0, "crit_chance": 0.03})
	assert_true(changes.is_empty(), "under half a point / 0.05%: not shown")
	assert_eq(Item.display_change("armor", -12.0), "-12 armor")
	assert_eq(Item.display_change("max_health", 42.0), "+42 max health")
	assert_eq(Item.display_change("crit_chance", -0.015), "-1.5% crit chance")
	# A reduction stat reads as less cost when it grows.
	assert_eq(Item.display_change("block_stamina_reduction", 0.06), "-6.0% stamina cost of blocked hits")
	assert_eq(Item.display_change("block_stamina_reduction", -0.06), "+6.0% stamina cost of blocked hits")


func test_armor_fits_every_class_weapons_and_wings_only_theirs() -> void:
	assert_true(InventoryPanel.fits_class(db.items["cap"], "juggernaut", JUGGERNAUT))
	assert_true(InventoryPanel.fits_class(db.items["sword"], "fighter", FIGHTER))
	assert_false(InventoryPanel.fits_class(db.items["sword"], "juggernaut", JUGGERNAUT))
	assert_true(InventoryPanel.fits_class(db.items["plumes"], "fighter", FIGHTER))
	assert_false(InventoryPanel.fits_class(db.items["plumes"], "juggernaut", JUGGERNAUT))


func test_filters_by_type_and_class_newest_first() -> void:
	var bag: Array[Item] = [_item("cap", 101), _item("sword", 102), _item("halberd", 103),
			_item("plumes", 104), _item("cap", 105)]
	var classes := {"fighter": FIGHTER, "juggernaut": JUGGERNAUT}
	var newest := InventoryPanel.Sort.NEWEST
	assert_eq(_ids(InventoryPanel.bag_view(bag, db, "", "", classes, newest)),
			["cap105", "plumes104", "halberd103", "sword102", "cap101"])
	assert_eq(_ids(InventoryPanel.bag_view(bag, db, "head", "", classes, newest)),
			["cap105", "cap101"])
	assert_eq(_ids(InventoryPanel.bag_view(bag, db, "", "juggernaut", classes, newest)),
			["cap105", "halberd103", "cap101"])
	assert_eq(_ids(InventoryPanel.bag_view(bag, db, "weapon", "fighter", classes, newest)),
			["sword102"])
	assert_eq(bag.size(), 5, "the bag itself is untouched")


func test_sorts_by_type_gear_score_and_rarity() -> void:
	var bag: Array[Item] = [_item("jerkin", 110, "rare"), _item("sword", 120),
			_item("cap", 130, "epic"), _item("cap", 100, "rare"), _item("sword", 140)]
	assert_eq(_ids(InventoryPanel.bag_view(bag, db, "", "", {}, InventoryPanel.Sort.TYPE)),
			["sword140", "sword120", "cap130", "cap100", "jerkin110"])
	assert_eq(_ids(InventoryPanel.bag_view(bag, db, "", "", {}, InventoryPanel.Sort.GEAR_SCORE)),
			["sword140", "cap130", "sword120", "jerkin110", "cap100"])
	assert_eq(_ids(InventoryPanel.bag_view(bag, db, "", "", {}, InventoryPanel.Sort.RARITY)),
			["cap130", "jerkin110", "cap100", "sword140", "sword120"])
