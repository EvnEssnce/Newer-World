extends TestCase
## Tradeskills: the XP curve, level-ups, the cap, gathering effects (time,
## bonus yield) and the dict round trip. Defs are built by hand.

var defs: TradeskillDefs
var skills: Tradeskills


func before_each() -> void:
	defs = TradeskillDefs.new()
	defs.level_cap = 10
	defs.xp_base = 100.0
	defs.xp_exponent = 1.5
	defs.time_reduction_per_level = 0.04
	defs.time_floor = 0.7
	defs.bonus_chance_per_level = 0.05
	defs.bonus_chance_max = 0.3
	defs.bonus_units = 2
	var mining := defs.add_skill("mining", "Mining", "gathering")
	mining.xp_per_gather = 10
	mining.xp_per_unit = 5
	mining.node_xp = {"rich_ore": 2.0}
	defs.add_skill("smelting", "Smelting", "refining")
	defs.add_skill("weaponsmithing", "Weaponforging", "crafting")
	skills = Tradeskills.new(defs)


func test_xp_curve_is_base_times_level_to_the_exponent() -> void:
	assert_eq(defs.xp_to_next(1), 100)
	assert_eq(defs.xp_to_next(4), 800, "100 * 4^1.5")
	assert_eq(defs.xp_to_next(9), 2700, "100 * 9^1.5")
	assert_eq(defs.xp_to_next(10), 0, "nothing past the cap")


func test_skills_start_at_level_one_with_no_xp() -> void:
	assert_eq(skills.level("mining"), 1)
	assert_eq(skills.xp("mining"), 0)
	assert_almost(skills.progress("mining"), 0.0)


func test_xp_below_the_need_only_fills_the_bar() -> void:
	assert_eq(skills.add_xp("mining", 40), 0)
	assert_eq(skills.level("mining"), 1)
	assert_almost(skills.progress("mining"), 0.4)


func test_one_level_up_carries_the_leftover() -> void:
	assert_eq(skills.add_xp("mining", 130), 1)
	assert_eq(skills.level("mining"), 2)
	assert_eq(skills.xp("mining"), 30)
	# Level 2 needs round(100 * 2^1.5) = 283.
	assert_eq(skills.xp_needed("mining"), 283)


func test_a_big_grant_gains_several_levels() -> void:
	# 100 (1->2) + 283 (2->3) + 520 (3->4) = 903, then 7 into level 4.
	assert_eq(skills.add_xp("mining", 910), 3)
	assert_eq(skills.level("mining"), 4)
	assert_eq(skills.xp("mining"), 7)


func test_the_cap_stops_levels_and_drops_extra_xp() -> void:
	assert_eq(skills.add_xp("mining", 10_000_000), 9, "1 -> 10")
	assert_eq(skills.level("mining"), 10)
	assert_eq(skills.xp("mining"), 0)
	assert_true(skills.is_capped("mining"))
	assert_almost(skills.progress("mining"), 1.0)
	assert_eq(skills.add_xp("mining", 500), 0)
	assert_eq(skills.xp("mining"), 0)


func test_unknown_skills_and_non_positive_xp_change_nothing() -> void:
	assert_eq(skills.add_xp("fishing", 500), 0)
	assert_eq(skills.add_xp("mining", 0), 0)
	assert_eq(skills.add_xp("mining", -50), 0)
	assert_eq(skills.xp("mining"), 0)
	assert_false(skills.to_dict().has("fishing"))


func test_gather_time_multiplier_drops_per_level_to_a_floor() -> void:
	assert_almost(skills.gather_time_multiplier("mining"), 1.0, 0.0001, "level 1")
	skills.add_xp("mining", 100)  # level 2
	assert_almost(skills.gather_time_multiplier("mining"), 0.96, 0.0001)
	assert_almost(defs.time_multiplier(6), 0.8, 0.0001)
	assert_almost(defs.time_multiplier(10), 0.7, 0.0001, "1 - 0.36 is under the 0.7 floor")
	assert_almost(skills.gather_time_multiplier("smelting"), 1.0, 0.0001, "not a gathering skill")


func test_bonus_chance_grows_per_level_up_to_its_max() -> void:
	assert_almost(defs.bonus_chance(1), 0.0)
	assert_almost(defs.bonus_chance(3), 0.1)
	assert_almost(defs.bonus_chance(10), 0.3, 0.0001, "0.45 capped at 0.3")


func test_no_bonus_yield_at_level_one_or_for_other_skills() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		assert_eq(skills.bonus_yield("mining", rng), 0)
		assert_eq(skills.bonus_yield("smelting", rng), 0)


func test_bonus_yield_matches_its_chance_with_a_seeded_rng() -> void:
	skills.add_xp("mining", 100 + 283)  # level 3: 10% chance of +2
	assert_eq(skills.level("mining"), 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var hits := 0
	var trials := 20000
	for i in trials:
		var bonus := skills.bonus_yield("mining", rng)
		assert_true(bonus == 0 or bonus == 2, "only 0 or bonus_units")
		if bonus > 0:
			hits += 1
	assert_almost(hits / float(trials), 0.1, 0.01)


func test_bonus_yield_is_repeatable_for_the_same_seed() -> void:
	skills.add_xp("mining", 10_000_000)
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	for i in 100:
		assert_eq(skills.bonus_yield("mining", a), skills.bonus_yield("mining", b))


func test_gather_xp_per_gather_per_unit_and_node_kind() -> void:
	assert_eq(defs.gather_xp("mining", "ore", 3), 25, "10 + 5 * 3")
	assert_eq(defs.gather_xp("mining", "rich_ore", 3), 50, "doubled by node_xp")
	assert_eq(defs.gather_xp("mining", "ore", 0), 0, "nothing gathered")
	assert_eq(defs.gather_xp("smelting", "ore", 3), 0, "not a gathering skill")


func test_dict_round_trip() -> void:
	skills.add_xp("mining", 910)
	skills.add_xp("smelting", 150)
	var copy := Tradeskills.from_dict(skills.to_dict(), defs)
	for id in defs.order:
		assert_eq(copy.level(id), skills.level(id), id)
		assert_eq(copy.xp(id), skills.xp(id), id)
	assert_eq(copy.to_dict(), skills.to_dict())


func test_from_dict_clamps_and_skips_bad_entries() -> void:
	var copy := Tradeskills.from_dict({
		"mining": [50, 99999],     # level over the cap -> 10, no XP
		"smelting": [3.0, 9999.0],  # floats (JSON) accepted; XP below the need
		"weaponsmithing": "junk",
		"fishing": [5, 0],
		7: [2, 0],
	}, defs)
	assert_eq(copy.level("mining"), 10)
	assert_eq(copy.xp("mining"), 0)
	assert_eq(copy.level("smelting"), 3)
	assert_eq(copy.xp("smelting"), defs.xp_to_next(3) - 1)
	assert_eq(copy.level("weaponsmithing"), 1)
	assert_false(copy.to_dict().has("fishing"))


func test_ids_by_category_keep_the_order() -> void:
	assert_eq(defs.ids_in("gathering"), PackedStringArray(["mining"]))
	assert_eq(defs.ids_in("crafting"), PackedStringArray(["weaponsmithing"]))


func test_hand_built_defs_validate() -> void:
	assert_eq(defs.validate(), PackedStringArray())
	defs.add_skill("fishing", "", "cooking")
	assert_eq(defs.validate().size(), 2, "no name, unknown category")
	defs.add_skill("logging", "Logging", "gathering")
	assert_eq(defs.validate().size(), 3, "a gathering skill that gives no XP")


func test_real_data_validates() -> void:
	var real := TradeskillDefs.from_tuning()
	assert_eq(real.validate(), PackedStringArray())
	for id in ["mining", "logging", "harvesting"]:
		assert_true(real.is_gathering(id), id)
	assert_true(real.has_skill("smelting"))
	assert_true(real.ids_in("crafting").size() >= 2)
