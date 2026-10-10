extends TestCase
## Ranger rules: hastes with slows (Tailwind), roll speed and cost (Gust Roll,
## Tailwind), slow descent (Updraft), Hunter's Mark, stack cap overrides
## (Inferno), one-hit buffs (Parting Shot), Skirmisher's free movement in the
## sim, and (last test) the Ranger's Wing tree default build in data/.

var defs: StatusDefs
var slow: int
var tailwind: int
var gust: int
var updraft: int
var hunted: int
var burn: int
var parting: int


func before_each() -> void:
	defs = StatusDefs.new()
	slow = defs.add(_def("slow", func(d: StatusDef) -> void: d.move_multiplier = 0.6))
	tailwind = defs.add(_def("tailwind", func(d: StatusDef) -> void:
		d.move_multiplier = 1.3
		d.dodge_cost_multiplier = 0.5))
	gust = defs.add(_def("gust_roll", func(d: StatusDef) -> void: d.dodge_speed_multiplier = 1.8))
	updraft = defs.add(_def("updraft", func(d: StatusDef) -> void: d.fall_gravity_multiplier = 0.2))
	hunted = defs.add(_def("hunted", func(d: StatusDef) -> void: d.damage_taken_from_source = 0.15))
	burn = defs.add(_def("burn", func(d: StatusDef) -> void: d.max_stacks = 6))
	parting = defs.add(_def("parting_shot", func(d: StatusDef) -> void:
		d.damage_dealt = 0.3
		d.consume_on_hit = true))


func _def(id: String, setup: Callable) -> StatusDef:
	var d := StatusDef.new()
	d.id = id
	d.duration_ticks = 300
	setup.call(d)
	return d


# --- Movement statuses ---

func test_haste_and_slow_multiply() -> void:
	var s := StatusEffects.new()
	s.apply(defs, tailwind)
	assert_almost(s.move_multiplier(defs), 1.3)
	s.apply(defs, slow)
	assert_almost(s.move_multiplier(defs), 0.78, 0.001, "0.6 x 1.3")


func test_roll_speed_cost_and_descent() -> void:
	var s := StatusEffects.new()
	assert_almost(s.dodge_speed_multiplier(defs), 1.0)
	assert_almost(s.dodge_cost_multiplier(defs), 1.0)
	assert_almost(s.fall_gravity_multiplier(defs), 1.0)
	s.apply(defs, gust)
	s.apply(defs, tailwind)
	s.apply(defs, updraft)
	assert_almost(s.dodge_speed_multiplier(defs), 1.8)
	assert_almost(s.dodge_cost_multiplier(defs), 0.5)
	assert_almost(s.fall_gravity_multiplier(defs), 0.2)


func test_tailwind_rolls_cost_half_in_the_sim() -> void:
	var params := PlayerParams.new()
	params.statuses = defs
	params.dodge_stamina_cost = 30.0
	var state := PlayerState.new()
	assert_almost(state.dodge_cost(params), 30.0)
	state.statuses.apply(defs, tailwind)
	assert_almost(state.dodge_cost(params), 15.0)


func test_movement_statuses_must_be_sim() -> void:
	var d := _def("bad", func(x: StatusDef) -> void: x.dodge_speed_multiplier = 1.5)
	var bad := StatusDefs.new()
	bad.add(d)
	assert_true(bad.validate().contains("sim"), bad.validate())
	d.affects = StatusDef.AFFECTS_SIM
	assert_eq(bad.validate(), "")


# --- Server-side statuses ---

func test_hunters_mark_only_from_its_marker() -> void:
	var s := StatusEffects.new()
	s.apply(defs, hunted, 1, -1, 7)
	assert_almost(s.damage_taken_from(defs, 7), 1.15)
	assert_almost(s.damage_taken_from(defs, 9), 1.0, 0.001, "another attacker")


func test_stack_cap_override() -> void:
	var s := StatusEffects.new()
	s.apply(defs, burn, 10)
	assert_eq(s.stacks_of(burn), 6, "its own max_stacks")
	s.apply(defs, burn, 10, -1, 0, 12)
	assert_eq(s.stacks_of(burn), 12, "Inferno doubles it")


func test_a_one_hit_buff_is_used_by_the_next_hit() -> void:
	var s := StatusEffects.new()
	s.apply(defs, parting)
	assert_almost(s.damage_dealt_multiplier(defs), 1.3)
	assert_eq(s.take_on_hit_statuses(defs).size(), 0, "applies nothing to the target")
	assert_false(s.has(parting), "used up")


# --- Skirmisher (free_draw) ---

func test_free_move_only_for_light_and_heavy_of_its_slot() -> void:
	var state := PlayerState.new()
	var events := state.server_events
	state.set_free_move(1)
	assert_eq(state.server_events, events + 1, "a server event")
	state.set_free_move(1)
	assert_eq(state.server_events, events + 1, "unchanged: no event")
	state.attack_type = PlayerState.ATTACK_HEAVY
	state.equipped = 0
	assert_true(state.moves_freely())
	state.attack_type = PlayerState.ATTACK_ABILITY
	assert_false(state.moves_freely(), "abilities still slow")
	state.attack_type = PlayerState.ATTACK_LIGHT
	state.equipped = 1
	assert_false(state.moves_freely(), "the other weapon")


func test_free_move_survives_the_snapshot_round_trip() -> void:
	var state := PlayerState.new()
	state.free_move_mask = 2
	var copy := PlayerState.from_array(state.to_array())
	assert_eq(copy.free_move_mask, 2)
	assert_true(copy.matches(state))


# --- Data ---

func test_ranger_wing_tree_default_build_is_valid() -> void:
	var t := MasteryTree.for_wings("ranger")
	assert_true(t != null, "data/mastery_wings_ranger.cfg")
	assert_eq(t.validate(t.default_nodes), "", "default nodes")
	assert_eq(t.validate_slots(t.default_nodes, t.default_slots), "", "default slots")
	var wings := PlayerParams.current().wing_set("ranger")
	for id in t.node_order:
		var n := t.get_node(id)
		if n.kind == MasteryTree.KIND_ACTIVE:
			assert_true(wings.ability_index(n.ability) >= 0, "%s's ability %s" % [id, n.ability])


func test_updraft_launches_for_real() -> void:
	var wings := PlayerParams.current().wing_set("ranger")
	var up := wings.ability(wings.ability_index("updraft"))
	assert_true(up.launch_height > 0.0)
