extends TestCase
## Gear score curve, armor mitigation, equip rules (slots, class locks, weapon
## slots following the loadout) and the stat totals combat uses. Hand-built
## ItemDatabase and GearScore (its defaults are New World's numbers).

var db: ItemDatabase
var curve: GearScore


func before_each() -> void:
	curve = GearScore.new()
	db = ItemDatabase.new()
	db.gear = curve
	_def("sword", "weapon", "broadsword", "", "weapon_power", 100.0)
	_def("hatchets", "weapon", "dual_axes", "", "weapon_power", 100.0)
	_def("maul", "weapon", "war_hammer", "", "weapon_power", 100.0)
	_def("cap", "head", "", "", "armor", 15.0)
	_def("jerkin", "chest", "", "", "armor", 35.0)
	_def("plumes", "wings", "", "fighter", "wing_power", 100.0)
	var affix := ItemDatabase.AffixDef.new()
	affix.id = "sear"
	affix.stat = "crit_chance"
	db.affixes["sear"] = affix


func _def(id: String, slot: String, weapon_type: String, class_id: String, primary: String,
		base: float) -> void:
	var def := ItemDatabase.ItemDef.new()
	def.id = id
	def.name = id.capitalize()
	def.slot = slot
	def.weapon_type = weapon_type
	def.class_id = class_id
	def.primary_stat = primary
	def.primary_base = base
	db.items[id] = def


func _item(id: String, gear_score: int = 100) -> Item:
	var item := Item.new()
	item.item_id = id
	item.rarity = "common"
	item.gear_score = gear_score
	item.primary_value = db.items[id].primary_base * curve.factor(gear_score)
	return item


const FIGHTER_WEAPONS: PackedStringArray = ["broadsword", "spear", "dual_axes"]


# --- Gear score curve and armor ---

func test_factor_is_one_at_base_and_steps_every_five() -> void:
	assert_almost(curve.factor(100), 1.0)
	assert_almost(curve.factor(104), 1.0, 0.0001, "no whole step yet")
	assert_almost(curve.factor(105), 1.0112)
	assert_almost(curve.factor(140), pow(1.0112, 8))
	assert_almost(curve.factor(50), 1.0, 0.0001, "never below the base")


func test_factor_grows_slower_above_the_soft_cap() -> void:
	var at_cap := pow(1.0112, 80)
	assert_almost(curve.factor(500), at_cap, 0.0001)
	assert_almost(curve.factor(600), at_cap * pow(1.0 + 0.0112 * 0.6667, 20), 0.0001)
	assert_true(curve.factor(505) / curve.factor(500) < curve.factor(500) / curve.factor(495))


func test_mitigation_depends_on_the_attackers_gear_score() -> void:
	assert_almost(curve.mitigation(0.0, 120), 0.0)
	var husk := pow(120.0, 1.2)
	assert_almost(curve.mitigation(75.0, 120), 75.0 / (75.0 + husk))
	assert_true(curve.mitigation(75.0, 300) < curve.mitigation(75.0, 120),
			"stronger weapons punch through more")
	assert_true(curve.mitigation(150.0, 120) > curve.mitigation(75.0, 120), "more armor, less damage")


# --- Equip rules ---

func test_items_only_fit_their_slot() -> void:
	assert_eq(Equipment.check(_item("cap"), "head", db, "fighter", FIGHTER_WEAPONS), "")
	assert_true(Equipment.check(_item("cap"), "chest", db, "fighter", FIGHTER_WEAPONS) != "")
	assert_eq(Equipment.check(_item("sword"), "weapon_2", db, "fighter", FIGHTER_WEAPONS), "")
	assert_true(Equipment.check(_item("sword"), "head", db, "fighter", FIGHTER_WEAPONS) != "")
	assert_true(Equipment.check(_item("cap"), "hands", db, "fighter", FIGHTER_WEAPONS) != "",
			"no hands slot")


func test_armor_fits_any_class_but_weapons_and_wings_are_class_locked() -> void:
	var juggernaut: PackedStringArray = ["halberd", "greataxe", "war_hammer"]
	assert_eq(Equipment.check(_item("jerkin"), "chest", db, "juggernaut", juggernaut), "")
	assert_true(Equipment.check(_item("sword"), "weapon_1", db, "juggernaut", juggernaut) != "")
	assert_eq(Equipment.check(_item("maul"), "weapon_1", db, "juggernaut", juggernaut), "")
	assert_true(Equipment.check(_item("plumes"), "wings", db, "juggernaut", juggernaut) != "")
	assert_eq(Equipment.check(_item("plumes"), "wings", db, "fighter", FIGHTER_WEAPONS), "")


func test_a_weapon_goes_to_the_slot_that_already_holds_its_type() -> void:
	var loadout: PackedStringArray = ["broadsword", "dual_axes"]
	assert_eq(Equipment.weapon_target("broadsword", "weapon_2", loadout), "weapon_1")
	assert_eq(Equipment.weapon_target("spear", "weapon_2", loadout), "weapon_2")


func test_equip_returns_what_was_there() -> void:
	var worn := Equipment.new()
	var old := _item("cap")
	assert_eq(worn.equip("head", old), null)
	assert_eq(worn.equip("head", _item("cap", 130)), old)
	assert_eq(worn.unequip("head").gear_score, 130)
	assert_eq(worn.unequip("head"), null)


func test_weapon_items_follow_their_type_when_the_loadout_changes() -> void:
	var worn := Equipment.new()
	var sword := _item("sword")
	var hatchets := _item("hatchets")
	worn.equip("weapon_1", sword)
	worn.equip("weapon_2", hatchets)
	assert_eq(worn.sync_weapons(PackedStringArray(["dual_axes", "broadsword"]), db).size(), 0)
	assert_eq(worn.get_item("weapon_1"), hatchets, "swapped slots in the K panel")
	assert_eq(worn.get_item("weapon_2"), sword)
	var back := worn.sync_weapons(PackedStringArray(["spear", "broadsword"]), db)
	assert_eq(back.size(), 1)
	assert_eq(back[0], hatchets, "its type isn't equipped any more: back to the bag")
	assert_eq(worn.get_item("weapon_2"), sword)


func test_round_trips_through_a_dictionary() -> void:
	var worn := Equipment.new()
	worn.equip("chest", _item("jerkin", 120))
	var copy := Equipment.from_dict(worn.to_dict())
	assert_eq(copy.get_item("chest").to_dict(), worn.get_item("chest").to_dict())


# --- Stat totals ---

func test_stats_add_up_armor_powers_and_bonuses() -> void:
	var worn := Equipment.new()
	worn.equip("head", _item("cap", 140))
	worn.equip("chest", _item("jerkin", 140))
	var sword := _item("sword", 120)
	sword.affixes["sear"] = 0.03
	worn.equip("weapon_1", sword)
	var plumes := _item("plumes", 110)
	plumes.affixes["sear"] = 0.02
	worn.equip("wings", plumes)
	var stats := worn.stats(db, {})
	assert_almost(stats.armor, 50.0 * curve.factor(140))
	assert_almost(stats.weapon_power_for("broadsword"), curve.factor(120))
	assert_almost(stats.weapon_power_for("spear"), 1.0, 0.0001, "no item: the file's numbers")
	assert_eq(stats.weapon_gear_score_for("broadsword", 100), 120)
	assert_eq(stats.weapon_gear_score_for("spear", 100), 100)
	assert_almost(stats.wing_power, curve.factor(110))
	assert_eq(stats.wing_gear_score, 110)
	assert_almost(stats.bonus("crit_chance"), 0.05)
	assert_almost(stats.bonus("max_health"), 0.0)


func test_average_gear_score_weighs_slots() -> void:
	var worn := Equipment.new()
	var weights := {"weapon_1": 0.5, "head": 0.25, "chest": 0.25}
	assert_almost(worn.stats(db, weights).average_gear_score, 0.5 * 100,
			0.001, "a plain weapon counts as the base gear score, empty armor as 0")
	worn.equip("weapon_1", _item("sword", 120))
	worn.equip("head", _item("cap", 100))
	assert_almost(worn.stats(db, weights).average_gear_score, 0.5 * 120 + 0.25 * 100)
