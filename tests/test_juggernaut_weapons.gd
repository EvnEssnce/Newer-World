extends TestCase
## Halberd and Greataxe rules: crits (Headsman), the ability range upgrade
## (Maelstrom), Brace's charge stagger, Iron Hide's crowd scaling, the Hooked
## mark's source, removing a status as a server event, range copies, and
## (last test) every weapon tree's default build in data/.

var tree: MasteryTree
var defs: StatusDefs
var braced: int
var iron_hide: int
var hooked: int


func before_each() -> void:
	tree = MasteryTree.new()
	tree.branches = PackedStringArray(["a"])
	tree.branch_names = PackedStringArray(["A"])
	tree.tier_requirements = PackedInt32Array([0])
	tree.points = 10
	tree.add_node("spin", "a", 1, MasteryTree.KIND_ACTIVE, 1, "vortex")
	var n := tree.add_node("verdict", "a", 1, MasteryTree.KIND_PASSIVE, 1)
	n.effect = "crit_staggered"
	n.applies_to = "heavy"
	n = tree.add_node("maelstrom", "a", 1, MasteryTree.KIND_PASSIVE, 1)
	n.effect = "ability_range"
	n.applies_to = "vortex"
	n.amount = 2.0

	defs = StatusDefs.new()
	var d := StatusDef.new()
	d.id = "braced"
	d.category = StatusDef.CATEGORY_BUFF
	d.duration_ticks = 180
	d.force_immune = true
	d.charge_stagger_ticks = 60
	d.charge_window_ticks = 60
	braced = defs.add(d)
	d = StatusDef.new()
	d.id = "iron_hide"
	d.category = StatusDef.CATEGORY_BUFF
	d.duration_ticks = 360
	d.crowd_damage_taken = -0.08
	d.crowd_radius = 5.0
	d.crowd_max = 5
	iron_hide = defs.add(d)
	d = StatusDef.new()
	d.id = "hooked"
	d.duration_ticks = 150
	hooked = defs.add(d)


# --- Crits (Headsman's Verdict) ---

func test_heavy_on_a_staggered_target_crits() -> void:
	var nodes := PackedStringArray(["verdict"])
	assert_almost(tree.crit_multiplier(nodes, "heavy", "", true, 1.5), 1.5)


func test_no_crit_without_stagger_or_on_other_attacks() -> void:
	var nodes := PackedStringArray(["verdict"])
	assert_almost(tree.crit_multiplier(nodes, "heavy", "", false, 1.5), 1.0, 0.001, "not staggered")
	assert_almost(tree.crit_multiplier(nodes, "light", "", true, 1.5), 1.0, 0.001, "light")
	assert_almost(tree.crit_multiplier(nodes, "ability", "vortex", true, 1.5), 1.0, 0.001, "ability")


func test_no_crit_without_the_node() -> void:
	assert_almost(tree.crit_multiplier(PackedStringArray(["spin"]), "heavy", "", true, 1.5), 1.0)


func test_covers_matches_damage_node_rules() -> void:
	assert_true(MasteryTree.covers("all", "light", ""))
	assert_true(MasteryTree.covers("abilities", "ability", "vortex"))
	assert_true(MasteryTree.covers("vortex", "ability", "vortex"))
	assert_false(MasteryTree.covers("vortex", "ability", "hurl"))
	assert_false(MasteryTree.covers("heavy", "light", ""))


# --- Maelstrom ---

func test_range_upgrade_only_for_its_ability() -> void:
	var nodes := PackedStringArray(["spin", "maelstrom"])
	assert_almost(tree.range_multiplier(nodes, "vortex"), 2.0)
	assert_almost(tree.range_multiplier(nodes, "hurl"), 1.0)
	assert_almost(tree.range_multiplier(PackedStringArray(["spin"]), "vortex"), 1.0, 0.001,
			"not allocated")


func test_range_copy_keeps_shape_and_tuning() -> void:
	var a := AbilityParams.new()
	a.id = "vortex"
	a.shape = AttackParams.SHAPE_RADIAL
	a.hitbox_range = 3.5
	a.damage = 70.0
	a.force = ForceParams.new()
	var copy := a.range_copy(7.0) as AbilityParams
	assert_eq(copy.shape, AttackParams.SHAPE_RADIAL)
	assert_almost(copy.hitbox_range, 7.0)
	assert_almost(copy.damage, 70.0)
	assert_eq(copy.id, "vortex")
	assert_eq(copy.force, a.force, "same force (pull)")
	assert_almost(a.hitbox_range, 3.5, 0.001, "original unchanged")
	var box := AttackParams.new()
	box.shape = AttackParams.SHAPE_BOX
	assert_eq(box.range_copy(2.0).shape, AttackParams.SHAPE_BOX)


# --- Brace ---

func test_brace_staggers_any_hit_within_the_window() -> void:
	var s := StatusEffects.new()
	s.apply(defs, braced)
	assert_eq(s.charge_stagger_ticks(defs, false), 60)
	for i in 60:
		s.tick(defs)
	assert_eq(s.charge_stagger_ticks(defs, false), 0, "window over, attacker not dashing")
	assert_eq(s.charge_stagger_ticks(defs, true), 60, "a dashing attacker still counts")


func test_no_charge_stagger_without_brace() -> void:
	var s := StatusEffects.new()
	s.apply(defs, iron_hide)
	assert_eq(s.charge_stagger_ticks(defs, true), 0)


# --- Iron Hide ---

func test_iron_hide_scales_with_nearby_hostiles() -> void:
	var s := StatusEffects.new()
	assert_almost(s.crowd_radius(defs), 0.0, 0.001, "no status: nothing to count")
	s.apply(defs, iron_hide)
	assert_almost(s.crowd_radius(defs), 5.0)
	assert_almost(s.crowd_damage_taken_multiplier(defs, 0), 1.0)
	assert_almost(s.crowd_damage_taken_multiplier(defs, 3), 0.76)
	assert_almost(s.crowd_damage_taken_multiplier(defs, 9), 0.6, 0.001, "capped at crowd_max")


# --- Hooked (Caught on the Hook) ---

func test_hooked_remembers_its_source() -> void:
	var s := StatusEffects.new()
	assert_eq(s.source_of(hooked), 0)
	s.apply(defs, hooked, 1, -1, 7)
	assert_eq(s.source_of(hooked), 7)
	s.apply(defs, hooked, 1, -1, 9)
	assert_eq(s.source_of(hooked), 9, "the latest hooker")


func test_remove_status_is_a_server_event() -> void:
	var params := PlayerParams.new()
	params.statuses = defs
	var state := PlayerState.new()
	state.apply_status(params, hooked, 1, -1, 7)
	var events := state.server_events
	assert_true(state.remove_status(hooked))
	assert_false(state.statuses.has(hooked))
	assert_eq(state.server_events, events + 1)
	assert_false(state.remove_status(hooked), "already gone")
	assert_eq(state.server_events, events + 1)


# --- Data ---

## Every weapon mastery tree in data/: its default allocation follows the
## rules, its default slots hold unlocked abilities, and every active node
## names an ability of that weapon.
func test_every_weapon_trees_default_build_is_valid() -> void:
	var params := PlayerParams.current()
	for weapon_id: String in params.weapons:
		var t := MasteryTree.for_weapon(weapon_id)
		if t == null:
			continue
		assert_eq(t.validate(t.default_nodes), "", weapon_id + " default nodes")
		assert_eq(t.validate_slots(t.default_nodes, t.default_slots), "", weapon_id + " default slots")
		var weapon := params.weapon(weapon_id)
		for id in t.node_order:
			var n := t.get_node(id)
			if n.kind == MasteryTree.KIND_ACTIVE:
				assert_true(weapon.ability_index(n.ability) >= 0,
						"%s: %s's ability %s" % [weapon_id, id, n.ability])
