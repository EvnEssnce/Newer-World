extends TestCase
## MasteryTree rules: tier gates, point budget, respec/prune, unlocking and
## slotting abilities, server-side modifiers. A hand-built tree:
##
##   branch a: tier 1: a_act (active "slash", 1), a_pas (passive, 1)
##             tier 2: a_two (active "spin", 1)
##             tier 3: a_three (upgrade on "spin", 1)
##   branch b: tier 1: b_act (active "leap", 1), b_big (passive, 2)
## Tier gates: 0, 2, 3 points in lower tiers of the branch. Budget: 5.

var tree: MasteryTree


func before_each() -> void:
	tree = MasteryTree.new()
	tree.branches = PackedStringArray(["a", "b"])
	tree.branch_names = PackedStringArray(["A", "B"])
	tree.tier_requirements = PackedInt32Array([0, 2, 3])
	tree.points = 5
	tree.add_node("a_act", "a", 1, MasteryTree.KIND_ACTIVE, 1, "slash")
	tree.add_node("a_pas", "a", 1, MasteryTree.KIND_PASSIVE, 1)
	tree.add_node("a_two", "a", 2, MasteryTree.KIND_ACTIVE, 1, "spin")
	tree.add_node("a_three", "a", 3, MasteryTree.KIND_UPGRADE, 1)
	tree.add_node("b_act", "b", 1, MasteryTree.KIND_ACTIVE, 1, "leap")
	tree.add_node("b_big", "b", 1, MasteryTree.KIND_PASSIVE, 2)


func _ok(nodes: Array) -> bool:
	return tree.validate(PackedStringArray(nodes)) == ""


func test_empty_allocation_is_valid() -> void:
	assert_true(_ok([]))


func test_tier_one_is_open() -> void:
	assert_true(_ok(["a_act"]))
	assert_true(_ok(["b_big"]))


func test_tier_needs_points_in_its_branch() -> void:
	assert_false(_ok(["a_two"]), "no points in a")
	assert_false(_ok(["a_act", "a_two"]), "1 of 2")
	assert_true(_ok(["a_act", "a_pas", "a_two"]), "2 of 2")


func test_points_in_the_other_branch_do_not_count() -> void:
	assert_false(_ok(["b_act", "b_big", "a_two"]))


func test_same_tier_points_do_not_open_the_next_tier_of_themselves() -> void:
	# a_three needs 3 points below tier 3: a_act + a_pas + a_two.
	assert_true(_ok(["a_act", "a_pas", "a_two", "a_three"]))
	tree.get_node("a_two").tier = 3
	assert_false(_ok(["a_act", "a_pas", "a_two", "a_three"]), "tier 3 nodes don't count for tier 3")


func test_order_does_not_matter() -> void:
	assert_true(_ok(["a_three", "a_two", "a_pas", "a_act"]))


func test_point_budget() -> void:
	assert_true(_ok(["a_act", "a_pas", "a_two", "b_act", "a_three"]), "5 of 5")
	assert_false(_ok(["a_act", "a_pas", "a_two", "a_three", "b_big"]), "6 of 5")
	assert_eq(tree.spent(PackedStringArray(["a_act", "b_big"])), 3)


func test_unknown_and_duplicate_nodes_are_invalid() -> void:
	assert_false(_ok(["nope"]))
	assert_false(_ok(["a_act", "a_act"]))


func test_can_add() -> void:
	var nodes := PackedStringArray(["a_act"])
	assert_true(tree.can_add(nodes, "a_pas"))
	assert_false(tree.can_add(nodes, "a_two"), "tier gate")
	assert_false(tree.can_add(nodes, "a_act"), "already learned")


func test_is_tier_open() -> void:
	var nodes := PackedStringArray(["a_act", "a_pas"])
	assert_true(tree.is_tier_open(nodes, "a", 2))
	assert_false(tree.is_tier_open(nodes, "a", 3))
	assert_false(tree.is_tier_open(nodes, "b", 2))


func test_removing_a_node_drops_what_needed_it() -> void:
	var nodes := PackedStringArray(["a_act", "a_pas", "a_two", "a_three", "b_act"])
	assert_eq(tree.remove(nodes, "a_pas"), PackedStringArray(["a_act", "b_act"]))
	assert_eq(tree.remove(nodes, "b_act"), PackedStringArray(["a_act", "a_pas", "a_two", "a_three"]))


func test_prune_keeps_lower_tiers_within_budget() -> void:
	var nodes := PackedStringArray(["a_three", "a_two", "a_act", "a_pas", "b_big"])
	# Tier 1 first (a_act, a_pas, b_big = 4 points), then a_two (5), then a_three (over budget).
	assert_eq(tree.prune(nodes), PackedStringArray(["a_act", "a_pas", "b_big", "a_two"]))


func test_respec_is_any_valid_allocation() -> void:
	var build_a := PackedStringArray(["a_act", "a_pas", "a_two"])
	var build_b := PackedStringArray(["b_act", "b_big"])
	assert_true(tree.validate(build_a) == "" and tree.validate(build_b) == "")


func test_unlocked_abilities_come_from_active_nodes() -> void:
	var nodes := PackedStringArray(["a_act", "a_pas", "a_two", "b_big"])
	assert_eq(tree.unlocked_abilities(nodes), PackedStringArray(["slash", "spin"]))


func test_slots_hold_only_unlocked_abilities() -> void:
	var nodes := PackedStringArray(["a_act", "b_act"])
	assert_eq(tree.validate_slots(nodes, PackedStringArray(["slash", "leap", ""])), "")
	assert_eq(tree.validate_slots(nodes, PackedStringArray(["", "", ""])), "", "empty is fine")
	assert_true(tree.validate_slots(nodes, PackedStringArray(["spin", "", ""])) != "", "locked")
	assert_true(tree.validate_slots(nodes, PackedStringArray(["slash", "slash", ""])) != "", "twice")
	assert_true(tree.validate_slots(nodes, PackedStringArray(["slash", "leap"])) != "", "3 slots")


func test_damage_modifiers() -> void:
	tree.get_node("a_pas").effect = "damage"
	tree.get_node("a_pas").applies_to = "light"
	tree.get_node("a_pas").amount = 0.1
	tree.get_node("a_three").effect = "damage"
	tree.get_node("a_three").applies_to = "spin"
	tree.get_node("a_three").amount = 0.5
	tree.get_node("b_big").effect = "damage"
	tree.get_node("b_big").applies_to = "abilities"
	tree.get_node("b_big").amount = 0.2
	var nodes := PackedStringArray(["a_act", "a_pas", "a_two", "a_three"])
	assert_almost(tree.damage_multiplier(nodes, "light", "", 1.0), 1.1)
	assert_almost(tree.damage_multiplier(nodes, "heavy", "", 1.0), 1.0)
	assert_almost(tree.damage_multiplier(nodes, "ability", "spin", 1.0), 1.5)
	assert_almost(tree.damage_multiplier(nodes, "ability", "slash", 1.0), 1.0)
	var with_b := PackedStringArray(["b_big", "a_act", "a_pas", "a_two"])
	assert_almost(tree.damage_multiplier(with_b, "ability", "slash", 1.0), 1.2)
	assert_almost(tree.damage_multiplier(PackedStringArray(), "light", "", 1.0), 1.0, 0.001,
			"nothing learned")


func test_all_and_low_health_damage() -> void:
	tree.get_node("a_pas").effect = "damage"
	tree.get_node("a_pas").applies_to = "all"
	tree.get_node("a_pas").amount = 0.05
	tree.get_node("b_big").effect = "low_health_damage"
	tree.get_node("b_big").amount = 0.25
	tree.get_node("b_big").threshold = 0.5
	var nodes := PackedStringArray(["a_pas", "b_big"])
	assert_almost(tree.damage_multiplier(nodes, "heavy", "", 0.9), 1.05)
	assert_almost(tree.damage_multiplier(nodes, "heavy", "", 0.4), 1.3)


func test_execute_bonus_from_nodes() -> void:
	assert_eq(tree.execute_bonus(PackedStringArray(["a_pas"])), Vector2.ZERO)
	tree.get_node("b_big").effect = "execute_damage"
	tree.get_node("b_big").amount = 0.6
	tree.get_node("b_big").threshold = 0.3
	assert_eq(tree.execute_bonus(PackedStringArray(["a_pas"])), Vector2.ZERO, "not allocated")
	var bonus := tree.execute_bonus(PackedStringArray(["a_pas", "b_big"]))
	assert_almost(bonus.x, 0.6)
	assert_almost(bonus.y, 0.3)
	# It's a target-health bonus, not part of the attacker's damage multiplier.
	assert_almost(tree.damage_multiplier(PackedStringArray(["b_big"]), "light", "", 0.1), 1.0)


func test_execute_multiplier_ramps_below_the_threshold() -> void:
	var bonus := Vector2(0.6, 0.3)
	assert_almost(MasteryTree.execute_multiplier(bonus, 1.0), 1.0, 0.001, "full health")
	assert_almost(MasteryTree.execute_multiplier(bonus, 0.3), 1.0, 0.001, "at the threshold")
	assert_almost(MasteryTree.execute_multiplier(bonus, 0.15), 1.3, 0.001, "halfway down")
	assert_almost(MasteryTree.execute_multiplier(bonus, 0.0), 1.6, 0.001, "at 0 health")
	assert_almost(MasteryTree.execute_multiplier(bonus, -0.5), 1.6, 0.001, "clamped")
	assert_almost(MasteryTree.execute_multiplier(Vector2.ZERO, 0.0), 1.0, 0.001, "no bonus")


func test_block_stamina_modifier() -> void:
	tree.get_node("a_pas").effect = "block_stamina"
	tree.get_node("a_pas").amount = -0.15
	assert_almost(tree.block_stamina_multiplier(PackedStringArray(["a_pas"])), 0.85)
	assert_almost(tree.block_stamina_multiplier(PackedStringArray()), 1.0)


# --- requires (ability combos) ---

func _requires(id: String, ids: Array) -> void:
	tree.get_node(id).requires = PackedStringArray(ids)


func test_requires_needs_the_required_node_learned() -> void:
	_requires("b_act", ["a_act"])
	assert_false(_ok(["b_act"]), "without a_act")
	assert_true(tree.validate(PackedStringArray(["b_act"])).contains("requires a_act"))
	assert_true(_ok(["a_act", "b_act"]))
	assert_true(_ok(["b_act", "a_act"]), "order doesn't matter")
	assert_false(tree.can_add(PackedStringArray(["a_pas"]), "b_act"))
	assert_true(tree.can_add(PackedStringArray(["a_act"]), "b_act"))


func test_unlearning_a_required_node_unlearns_what_needs_it() -> void:
	_requires("b_act", ["a_act"])
	var nodes := PackedStringArray(["a_act", "a_pas", "b_act"])
	assert_eq(tree.remove(nodes, "a_act"), PackedStringArray(["a_pas"]))
	assert_eq(tree.lost_with(nodes, "a_act"), PackedStringArray(["b_act"]))
	assert_eq(tree.lost_with(nodes, "b_act"), PackedStringArray())
	# Tier gates cascade too: a_pas pays for a_two's gate.
	var deeper := PackedStringArray(["a_act", "a_pas", "a_two"])
	assert_eq(tree.lost_with(deeper, "a_pas"), PackedStringArray(["a_two"]))


func test_prune_keeps_a_node_listed_before_its_same_tier_requirement() -> void:
	_requires("a_pas", ["a_act"])
	assert_eq(tree.prune(PackedStringArray(["a_pas", "a_act"])), PackedStringArray(["a_act", "a_pas"]))


func test_missing_requirements_and_names() -> void:
	_requires("b_big", ["a_act", "a_two"])
	assert_eq(tree.missing_requirements(PackedStringArray(["a_act"]), "b_big"), PackedStringArray(["a_two"]))
	assert_eq(tree.all_requirements("b_big"), PackedStringArray(["a_act", "a_two"]))
	tree.get_node("a_act").display_name = "Slash"
	assert_eq(tree.display_names(PackedStringArray(["a_act"])), "Slash")
	assert_eq(tree.display_names(PackedStringArray(["a_act", "a_two", "b_act"])), "Slash, a_two and b_act")


func _has_problem(text: String) -> bool:
	for problem in tree.check():
		if problem.contains(text):
			return true
	return false


func test_check_accepts_a_sound_tree() -> void:
	_requires("b_act", ["a_act"])
	_requires("a_three", ["a_two"])
	assert_eq(tree.check(), PackedStringArray())


func test_check_reports_bad_requires() -> void:
	_requires("a_pas", ["nope"])
	assert_true(_has_problem("unknown node \"nope\""), "unknown id")
	_requires("a_pas", ["a_pas"])
	assert_true(_has_problem("requires itself"), "itself")
	_requires("a_pas", [])
	_requires("a_act", ["a_two"])
	assert_true(_has_problem("a higher tier"), "higher tier")
	_requires("a_act", ["a_pas"])
	_requires("a_pas", ["a_act"])
	assert_true(_has_problem("cycle"), "cycle")


func test_check_reports_unreachable_nodes() -> void:
	tree.tier_requirements = PackedInt32Array([0, 2, 4])
	assert_true(_has_problem("a_three can't be reached: tier 3 needs 4"), "tier gate past the branch")
	tree.tier_requirements = PackedInt32Array([0, 2, 3])
	_requires("a_three", ["b_big"])
	# a: 3 below tier 3 + a_three; b: b_big = 6 points of 5.
	assert_eq(tree.min_cost("a_three"), 6)
	assert_true(_has_problem("a_three can't be reached: it needs at least 6"), "over budget")
	tree.default_nodes = PackedStringArray(["a_two"])
	assert_true(_has_problem("[default]"), "bad default allocation")


## Every real tree file loads without problems, and every upgrade or capstone
## aimed at one of its tree's abilities requires the node that unlocks it.
func test_every_real_tree_is_sound() -> void:
	# Upgrades that work without their ability (Endless Flurry fires Fan of
	# Knives itself), and the Throwing Knives tree (another session's file)
	# until it gets its requires: Heavy Pin, Wide Fan.
	var exempt := ["endless_flurry", "heavy_pin", "wide_fan"]
	var count := 0
	for file in DirAccess.get_files_at("res://data"):
		if not (file.begins_with("mastery_") and file.ends_with(".cfg")) or file == "mastery.cfg":
			continue
		var key := file.trim_prefix("mastery_").trim_suffix(".cfg")
		var t := (MasteryTree.for_wings(key.trim_prefix("wings_")) if key.begins_with("wings_")
				else MasteryTree.for_weapon(key))
		assert_true(t != null, file)
		if t == null:
			continue
		count += 1
		assert_eq(t.check(), PackedStringArray(), file)
		var unlocks := {}
		for id in t.node_order:
			var n := t.get_node(id)
			if n.kind == MasteryTree.KIND_ACTIVE:
				unlocks[n.ability] = id
		for id in t.node_order:
			var n := t.get_node(id)
			if n.kind != MasteryTree.KIND_ACTIVE and unlocks.has(n.applies_to) and not (id in exempt):
				assert_true(unlocks[n.applies_to] in t.all_requirements(id),
						"%s: %s should require %s" % [file, id, unlocks[n.applies_to]])
	assert_true(count >= 21, "found %d tree files" % count)
