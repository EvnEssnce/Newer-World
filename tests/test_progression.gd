extends TestCase
## Progression: the character level and weapon mastery curves, level-ups, the
## caps, tree points per level and the dict round trip (stale saves clamped).
## Defs are built by hand.

var defs: ProgressionDefs
var levels: Progression


func before_each() -> void:
	defs = ProgressionDefs.new()
	defs.character = ProgressionDefs.LevelCurve.new(5, 100.0, 1.5)
	defs.mastery = ProgressionDefs.LevelCurve.new(4, 50.0, 1.0)
	defs.wing_points_per_level = 1
	defs.mastery_points_per_level = 2
	levels = Progression.new(defs)


func test_curves_are_base_times_level_to_the_exponent() -> void:
	assert_eq(defs.character.xp_to_next(1), 100)
	assert_eq(defs.character.xp_to_next(4), 800, "100 * 4^1.5")
	assert_eq(defs.character.xp_to_next(5), 0, "nothing past the cap")
	assert_eq(defs.mastery.xp_to_next(3), 150, "50 * 3")
	assert_eq(defs.character.xp_to_reach(3), 100 + 283)
	assert_eq(defs.character.xp_to_reach(1), 0)


func test_everything_starts_at_level_one() -> void:
	assert_eq(levels.level(), 1)
	assert_eq(levels.xp(), 0)
	assert_eq(levels.xp_needed(), 100)
	assert_eq(levels.mastery_level("spear"), 1)
	assert_eq(levels.mastery_xp("spear"), 0)
	assert_eq(levels.wing_points(), 0)
	assert_eq(levels.weapon_points("spear"), 0)
	assert_eq(levels.mastered_weapons(), PackedStringArray())


func test_character_xp_levels_up_and_carries_the_leftover() -> void:
	assert_eq(levels.add_xp(40), 0)
	assert_eq(levels.level(), 1)
	assert_eq(levels.add_xp(400), 2, "100 then 283: two levels")
	assert_eq(levels.level(), 3)
	assert_eq(levels.xp(), 440 - 383)


func test_xp_at_the_cap_is_dropped() -> void:
	assert_eq(levels.add_xp(1_000_000), 4)
	assert_eq(levels.level(), 5)
	assert_eq(levels.xp(), 0)
	assert_eq(levels.xp_needed(), 0)
	assert_eq(levels.add_xp(500), 0)
	assert_eq(levels.xp(), 0)


func test_nothing_or_negative_xp_changes_nothing() -> void:
	assert_eq(levels.add_xp(0), 0)
	assert_eq(levels.add_xp(-50), 0)
	assert_eq(levels.xp(), 0)
	assert_eq(levels.add_mastery_xp("spear", -5), 0)
	assert_eq(levels.add_mastery_xp("", 500), 0, "no weapon")
	assert_eq(levels.mastered_weapons(), PackedStringArray())


func test_mastery_is_per_weapon() -> void:
	assert_eq(levels.add_mastery_xp("spear", 160), 2, "50 then 100")
	assert_eq(levels.mastery_level("spear"), 3)
	assert_eq(levels.mastery_xp("spear"), 10)
	assert_eq(levels.mastery_level("sword"), 1, "other weapons untouched")
	assert_eq(levels.level(), 1, "mastery isn't character XP")
	assert_eq(levels.add_mastery_xp("spear", 10_000), 1)
	assert_eq(levels.mastery_level("spear"), 4, "the mastery cap")
	assert_eq(levels.mastery_xp("spear"), 0)
	assert_eq(levels.mastered_weapons(), PackedStringArray(["spear"]))


func test_tree_points_come_from_levels() -> void:
	levels.add_xp(100 + 283)
	assert_eq(levels.wing_points(), 2, "1 per level after the first")
	levels.add_mastery_xp("spear", 50)
	assert_eq(levels.weapon_points("spear"), 2, "2 per mastery level after the first")
	assert_eq(levels.weapon_points("sword"), 0)
	assert_eq(defs.mastery_points(4), 6)
	assert_eq(defs.wing_points(0), 0, "never negative")


func test_dict_round_trip() -> void:
	levels.add_xp(150)
	levels.add_mastery_xp("spear", 70)
	levels.add_mastery_xp("sword", 20)
	var data := levels.to_dict()
	assert_eq(data, {"level": 2, "xp": 50, "mastery": {"spear": [2, 20], "sword": [1, 20]}})
	var copy := Progression.from_dict(Persistence.decode(Persistence.encode(data)), defs)
	assert_eq(copy.to_dict(), data)


func test_from_dict_clamps_stale_saves() -> void:
	var copy := Progression.from_dict({"level": 99, "xp": 7, "mastery": {
			"spear": [0, 999], "sword": [3.0, 5000.0], "axes": [1, 0], "bow": "junk", "": [2, 0]}},
			defs)
	assert_eq(copy.level(), 5, "clamped to the cap")
	assert_eq(copy.xp(), 0, "no XP at the cap")
	assert_eq(copy.mastery_level("spear"), 1)
	assert_eq(copy.mastery_xp("spear"), 49, "below level 1's need")
	assert_eq(copy.mastery_level("sword"), 3, "JSON floats accepted")
	assert_eq(copy.mastery_xp("sword"), 149)
	assert_eq(copy.mastered_weapons(), PackedStringArray(["spear", "sword"]),
			"level 1 with no XP, junk and empty ids aren't kept")


func test_from_an_empty_or_broken_dict_is_a_new_character() -> void:
	for data: Dictionary in [{}, {"level": "x"}, {"mastery": []}]:
		var copy := Progression.from_dict(data, defs)
		assert_eq(copy.level(), 1)
		assert_eq(copy.mastered_weapons(), PackedStringArray())


func test_validate() -> void:
	assert_eq(defs.validate(), PackedStringArray())
	defs.character.level_cap = 0
	defs.mastery.xp_base = 0.0
	defs.wing_points_per_level = -1
	assert_eq(defs.validate().size(), 3)
