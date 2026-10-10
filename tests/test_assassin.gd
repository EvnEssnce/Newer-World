extends TestCase
## Assassin rules: backstab damage and crits (Dual Talons' Predator), stacking
## attack speed (Talon Storm), Primed (Feint), Marked (Marked Blade), and (last
## test) the Assassin's Wing tree default build in data/.

var tree: MasteryTree
var defs: StatusDefs
var rampage: int
var storm: int
var primed: int
var marked: int


func before_each() -> void:
	tree = MasteryTree.new()
	tree.branches = PackedStringArray(["a"])
	tree.branch_names = PackedStringArray(["A"])
	tree.tier_requirements = PackedInt32Array([0])
	tree.points = 10
	var n := tree.add_node("backstab", "a", 1, MasteryTree.KIND_PASSIVE, 1)
	n.effect = "backstab_damage"
	n.applies_to = "all"
	n.amount = 0.2
	n = tree.add_node("shadows", "a", 1, MasteryTree.KIND_PASSIVE, 1)
	n.effect = "backstab_damage"
	n.applies_to = "heavy"
	n.amount = 0.25
	n = tree.add_node("unseen", "a", 1, MasteryTree.KIND_PASSIVE, 1)
	n.effect = "crit_backstab"
	n.applies_to = "all"

	defs = StatusDefs.new()
	var d := StatusDef.new()
	d.id = "rampage"
	d.category = StatusDef.CATEGORY_BUFF
	d.affects = StatusDef.AFFECTS_SIM
	d.duration_ticks = 480
	d.attack_speed = 1.25
	rampage = defs.add(d)
	d = StatusDef.new()
	d.id = "talon_storm"
	d.category = StatusDef.CATEGORY_BUFF
	d.affects = StatusDef.AFFECTS_SIM
	d.duration_ticks = 90
	d.max_stacks = 8
	d.attack_speed = 1.04
	storm = defs.add(d)
	d = StatusDef.new()
	d.id = "primed"
	d.category = StatusDef.CATEGORY_BUFF
	d.duration_ticks = 240
	d.next_hit_crits = true
	primed = defs.add(d)
	d = StatusDef.new()
	d.id = "marked"
	d.duration_ticks = 360
	d.marked_bonus = 0.5
	marked = defs.add(d)


# --- Backstabs (Predator) ---

func test_backstab_damage_adds_up_for_covered_attacks() -> void:
	var nodes := PackedStringArray(["backstab", "shadows"])
	assert_almost(tree.backstab_multiplier(nodes, "heavy", ""), 1.45)
	assert_almost(tree.backstab_multiplier(nodes, "light", ""), 1.2)
	assert_almost(tree.backstab_multiplier(nodes, "ability", "pounce"), 1.2)
	assert_almost(tree.backstab_multiplier(PackedStringArray(), "heavy", ""), 1.0, 0.001, "none")


func test_unseen_strike_crits_backstabs_only() -> void:
	var nodes := PackedStringArray(["unseen"])
	assert_almost(tree.crit_multiplier(nodes, "light", "", false, 1.5, true), 1.5)
	assert_almost(tree.crit_multiplier(nodes, "light", "", false, 1.5, false), 1.0, 0.001,
			"not a backstab")
	assert_almost(tree.crit_multiplier(nodes, "light", "", true, 1.5, false), 1.0, 0.001,
			"staggered isn't enough for crit_backstab")
	assert_almost(tree.crit_multiplier(PackedStringArray(["backstab"]), "light", "", false, 1.5,
			true), 1.0, 0.001, "without the capstone")


func test_behind_is_the_rear_half() -> void:
	# A target at the origin facing yaw 0 looks toward -Z: an attacker at +Z is
	# behind it, one at -Z in front, one straight to the side is on the edge.
	var at := Vector3.ZERO
	assert_true(MeleeHitbox.is_in_front(at, 0.0 + PI, Vector3(0, 0, 2), PI), "behind")
	assert_false(MeleeHitbox.is_in_front(at, 0.0 + PI, Vector3(0, 0, -2), PI), "in front")
	assert_true(MeleeHitbox.is_in_front(at, 0.0 + PI, Vector3(1.5, 0, 1.0), PI), "behind, offset")


# --- Talon Storm (stacking attack speed) ---

func test_attack_speed_stacks_per_stack_and_caps() -> void:
	var s := StatusEffects.new()
	s.apply(defs, storm, 5)
	assert_almost(s.attack_speed(defs, 1.0), 1.2)
	s.apply(defs, storm, 3)
	assert_almost(s.attack_speed(defs, 1.0), 1.32, 0.001, "8 stacks")
	s.apply(defs, rampage)
	assert_almost(s.attack_speed(defs, 1.0), 1.32, 0.001, "the fastest status counts")


func test_attack_speed_never_goes_over_the_cap() -> void:
	defs.get_def(storm).attack_speed = 1.5
	var s := StatusEffects.new()
	s.apply(defs, storm, 8)
	assert_almost(s.attack_speed(defs, 1.0), StatusEffects.MAX_ATTACK_SPEED)


func test_one_stack_of_rampage_is_unchanged() -> void:
	var s := StatusEffects.new()
	s.apply(defs, rampage)
	assert_almost(s.attack_speed(defs, 1.0), 1.25)


# --- Primed (Feint) and Marked (Marked Blade) ---

func test_primed_is_found_and_removed() -> void:
	var s := StatusEffects.new()
	assert_eq(s.next_hit_crit_status(defs), -1)
	s.apply(defs, primed)
	assert_eq(s.next_hit_crit_status(defs), primed)
	s.remove(primed)
	assert_eq(s.next_hit_crit_status(defs), -1)


func test_a_mark_only_counts_for_whoever_applied_it() -> void:
	var s := StatusEffects.new()
	s.apply(defs, marked, 1, -1, 7)
	assert_eq(s.mark_from(defs, 7), marked)
	assert_eq(s.mark_from(defs, 9), -1, "someone else's mark")
	s.apply(defs, primed, 1, -1, 7)
	s.remove(marked)
	assert_eq(s.mark_from(defs, 7), -1, "Primed isn't a mark")


func test_feint_reads_into_primed() -> void:
	var feint := AttackParams.new()
	feint.read_status = "primed"
	assert_eq(defs.index_of(feint.read_status), primed)


# --- Data ---

func test_assassin_wing_tree_default_build_is_valid() -> void:
	var t := MasteryTree.for_wings("assassin")
	assert_true(t != null, "data/mastery_wings_assassin.cfg")
	assert_eq(t.validate(t.default_nodes), "", "default nodes")
	assert_eq(t.validate_slots(t.default_nodes, t.default_slots), "", "default slots")
	var wings := PlayerParams.current().wing_set("assassin")
	for id in t.node_order:
		var n := t.get_node(id)
		if n.kind == MasteryTree.KIND_ACTIVE:
			assert_true(wings.ability_index(n.ability) >= 0, "%s's ability %s" % [id, n.ability])
