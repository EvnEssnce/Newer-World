extends TestCase
## Ember (gain, spend, settling, cap, in-combat tracking), Wing abilities (cost,
## cooldown, can't-afford buffering, weapon swap), Rebirth (eligibility,
## cooldown, extra charges, health), healing over time, and the Wing tree.
## Fixed params, not the data files (except one check that the real Wing tree's
## defaults are valid).

const ATTACK := PlayerState.BUTTON_ATTACK
const SWAP := PlayerState.BUTTON_SWAP
const Z := PlayerState.BUTTON_WING_1
const C := PlayerState.BUTTON_WING_2
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState
var ward: int
var mend: int


func before_each() -> void:
	params = PlayerParams.new()
	params.max_stamina = 100.0
	params.max_health = 1000.0
	params.ability_buffer_ticks = 4
	params.swap_ticks = 10
	params.swap_buffer_ticks = 4

	params.ember_cap = 100.0
	params.ember_resting = 50.0
	# No settling unless a test turns it on, so Ember costs add up exactly.
	params.ember_settle_per_tick = 0.0
	params.ember_combat_ticks = 30
	params.ember_per_damage_dealt = 0.1
	params.ember_per_damage_taken = 0.05
	params.ember_per_heal = 0.05
	params.rebirth_threshold = 50.0
	params.rebirth_cost = 50.0
	params.rebirth_ticks = 20
	params.rebirth_health_fraction = 0.3
	params.rebirth_cooldown_ticks = 100

	var defs := StatusDefs.new()
	ward = defs.add(_def("ward", 60))
	defs.get_def(ward).damage_taken = -0.4
	mend = defs.add(_def("mend", 60))
	defs.get_def(mend).tick_interval_ticks = 30
	defs.get_def(mend).heal_per_interval = 20.0
	params.statuses = defs

	var weapon := params.default_weapon
	weapon.heavy_hold_ticks = 5
	weapon.attack_buffer_ticks = 4
	weapon.light_attack = _attack(AttackParams.new(), 3, 2, 4)
	weapon.heavy_attack = _attack(AttackParams.new(), 6, 2, 5)

	var wings := WingParams.new()
	wings.id = "test"
	var mantle := _wing("mantle", 25.0, 200)
	mantle.self_status = "ward"
	var dive := _wing("dive", 20.0, 100)
	dive.dash_start_tick = 1
	dive.dash_end_tick = 4
	dive.dash_speed = 10.0
	wings.abilities = [mantle, dive]
	params.wings = {"test": wings}

	state = PlayerState.new()
	state.stamina = params.max_stamina
	state.ember = params.ember_resting
	state.set_wings("test", PackedInt32Array([0, 1]))


func _def(id: String, duration: int) -> StatusDef:
	var d := StatusDef.new()
	d.id = id
	d.display_name = id.capitalize()
	d.category = StatusDef.CATEGORY_BUFF
	d.duration_ticks = duration
	d.max_stacks = 1
	return d


func _attack(a: AttackParams, windup: int, active: int, recovery: int) -> AttackParams:
	a.windup_ticks = windup
	a.active_ticks = active
	a.recovery_ticks = recovery
	return a


func _wing(id: String, cost: float, cooldown: int) -> AbilityParams:
	var a := AbilityParams.new()
	_attack(a, 2, 2, 2)
	a.id = id
	a.display_name = id.capitalize()
	a.ember_cost = cost
	a.cooldown_ticks = cooldown
	a.shape = AttackParams.SHAPE_NONE
	return a


func _step(buttons: int = 0) -> void:
	state.step(Vector2.ZERO, buttons, 0.0, true, params, DELTA)


func _steps(count: int, buttons: int = 0) -> void:
	for i in count:
		_step(buttons)


# --- Ember ---

func test_gain_adds_up_to_the_cap_and_is_a_server_event() -> void:
	var events := state.server_events
	state.gain_ember(params, 30.0)
	assert_almost(state.ember, 80.0)
	assert_eq(state.server_events, events + 1)
	state.gain_ember(params, 500.0)
	assert_almost(state.ember, 100.0, 0.001, "capped")
	assert_almost(state.ember_cap(params), 100.0)


func test_gain_from_damage_starts_combat_but_healing_doesnt() -> void:
	state.gain_ember(params, 5.0, false)
	assert_false(state.in_combat(), "healing isn't combat")
	state.gain_ember(params, 5.0)
	assert_eq(state.combat_ticks, params.ember_combat_ticks)
	assert_true(state.in_combat())


func test_no_gain_while_dead() -> void:
	state.kill()
	state.gain_ember(params, 30.0)
	assert_almost(state.ember, 50.0)


func test_settles_down_toward_resting_out_of_combat() -> void:
	params.ember_settle_per_tick = 1.0
	state.ember = 55.0
	_steps(3)
	assert_almost(state.ember, 52.0)
	_steps(10)
	assert_almost(state.ember, 50.0, 0.001, "stops at the resting level")


func test_refills_toward_resting_out_of_combat() -> void:
	params.ember_settle_per_tick = 1.0
	state.ember = 10.0
	_steps(5)
	assert_almost(state.ember, 15.0)


func test_no_settling_while_in_combat() -> void:
	params.ember_settle_per_tick = 1.0
	state.gain_ember(params, 20.0)
	_steps(params.ember_combat_ticks)
	assert_almost(state.ember, 70.0, 0.001, "still in combat for the whole window")
	assert_false(state.in_combat())
	_step()
	assert_almost(state.ember, 69.0, 0.001, "settles once combat ends")


func test_ember_frozen_while_dead() -> void:
	params.ember_settle_per_tick = 1.0
	state.ember = 80.0
	state.kill()
	_steps(10)
	assert_almost(state.ember, 80.0)


func test_ember_and_rebirth_fields_round_trip() -> void:
	state.ember = 63.5
	state.combat_ticks = 12
	state.rebirth_cooldown = 40
	state.rebirth_charges = 2
	state.wing_cooldowns[1] = 9
	var data := state.to_array()
	assert_eq(data.size(), 35)
	assert_eq(data[32], 63.5)
	assert_eq(data[33], "test")
	# combat, rebirth left/cooldown/charges, Z and C slots, cooldowns without
	# trailing zeros.
	assert_eq(data[34], PackedInt32Array([12, -1, 40, 2, 0, 1, 0, 9]))
	var copy := PlayerState.from_array(data)
	assert_true(copy.matches(state))
	assert_eq(copy.wing_cooldowns.size(), state.wing_cooldowns.size())
	copy.ember = 60.0
	assert_false(copy.matches(state), "Ember is compared")
	state.wing_cooldowns.fill(0)
	assert_eq(state.to_array()[34].size(), PlayerState.PACKED_WING_HEADER, "no cooldowns, none sent")


# --- Wing abilities ---

func test_wing_ability_spends_ember_and_starts_its_cooldown() -> void:
	_step(Z)
	assert_true(state.is_using_wing())
	assert_true(state.is_using_ability())
	assert_eq(state.ability, 0)
	assert_almost(state.ember, 25.0)
	assert_eq(state.wing_cooldown_left(0), 200)
	assert_eq(state.wing_cooldown_left(1), 0, "only its own cooldown")


func test_wing_ability_on_cooldown_doesnt_start() -> void:
	state.ember = 100.0
	_step(Z)
	_steps(10)
	assert_false(state.is_attacking())
	_step(Z)
	_steps(4)
	assert_false(state.is_attacking(), "still on cooldown")
	assert_almost(state.ember, 75.0, 0.001, "nothing spent")


func test_wing_ability_cant_start_without_enough_ember() -> void:
	state.ember = 24.0
	_step(Z)
	assert_false(state.is_attacking())
	assert_almost(state.ember, 24.0)
	assert_eq(state.wing_cooldown_left(0), 0, "no cooldown started")


func test_unaffordable_press_stays_buffered_until_ember_arrives() -> void:
	state.ember = 10.0
	_step(Z)
	_step()
	assert_false(state.is_attacking())
	state.gain_ember(params, 20.0)  # the server grants Ember within the buffer
	_step()
	assert_true(state.is_using_wing(), "buffered press fires once affordable")
	assert_almost(state.ember, 5.0)


func test_unaffordable_press_expires_after_the_buffer() -> void:
	state.ember = 10.0
	_step(Z)
	_steps(params.ability_buffer_ticks + 1)
	state.gain_ember(params, 40.0)
	_step()
	assert_false(state.is_attacking(), "the press expired")


func test_wing_self_status_is_applied_in_the_sim() -> void:
	_step(Z)
	assert_true(state.statuses.has(ward))


func test_second_wing_slot_and_its_dash() -> void:
	_step(C)
	assert_eq(state.ability, 1)
	assert_almost(state.ember, 30.0)
	_step()
	assert_true(state.is_dashing(params))


func test_empty_wing_slot_does_nothing() -> void:
	state.set_wings("test", PackedInt32Array([0, -1]))
	_step(C)
	assert_false(state.is_attacking())
	assert_eq(state.queued_attack, PlayerState.ATTACK_NONE)


func test_wings_stay_the_same_through_a_weapon_swap() -> void:
	state.set_loadout(PackedStringArray(["a", "b"]), PackedInt32Array([-1, -1, -1, -1, -1, -1]))
	_step(SWAP)
	assert_eq(state.equipped, 1)
	_steps(params.swap_ticks)
	_step(Z)
	assert_true(state.is_using_wing())
	assert_eq(state.current_ability(params).id, "mantle")


func test_wing_press_during_a_swap_stays_queued() -> void:
	state.set_loadout(PackedStringArray(["a", "b"]), PackedInt32Array([-1, -1, -1, -1, -1, -1]))
	params.ability_buffer_ticks = 20
	_step(SWAP)
	_step(Z)
	assert_false(state.is_attacking(), "can't use it mid-swap")
	_steps(params.swap_ticks)
	assert_true(state.is_using_wing(), "fires after the swap")


func test_set_wings_keeps_cooldowns_and_is_a_server_event() -> void:
	_step(Z)
	var events := state.server_events
	state.set_wings("test", PackedInt32Array([1, 0]))
	assert_eq(state.server_events, events + 1)
	assert_eq(state.wing_cooldown_left(0), 200, "a respec doesn't reset cooldowns")
	state.set_wings("test", PackedInt32Array([1, 0]))
	assert_eq(state.server_events, events + 1, "no change, no event")


func test_wing_cooldowns_tick_down() -> void:
	_step(Z)
	_steps(199)
	assert_eq(state.wing_cooldown_left(0), 1)
	_step()
	assert_eq(state.wing_cooldown_left(0), 0)


# --- Rebirth ---

func test_can_rebirth_needs_the_threshold() -> void:
	state.ember = 49.9
	assert_false(state.can_rebirth(params))
	state.ember = 50.0
	assert_true(state.can_rebirth(params))


func test_can_rebirth_needs_cooldown_or_a_charge() -> void:
	state.ember = 80.0
	state.rebirth_cooldown = 10
	assert_false(state.can_rebirth(params))
	state.grant_rebirth_charge()
	assert_true(state.can_rebirth(params), "an extra charge ignores the cooldown")
	state.ember = 40.0
	assert_false(state.can_rebirth(params), "but still needs the Ember")


func test_rebirth_spends_ember_and_counts_down() -> void:
	state.ember = 70.0
	state.kill()
	var events := state.server_events
	assert_true(state.start_rebirth(params))
	assert_eq(state.server_events, events + 1)
	assert_true(state.is_rebirthing())
	assert_almost(state.ember, 20.0)
	assert_eq(state.rebirth_cooldown, params.rebirth_cooldown_ticks)
	_steps(params.rebirth_ticks - 1)
	assert_false(state.rebirth_done())
	assert_almost(state.rebirth_progress(params), 0.95)
	_step()
	assert_true(state.rebirth_done())
	_steps(5)
	assert_eq(state.rebirth_cooldown, params.rebirth_cooldown_ticks,
			"the cooldown waits for the Rebirth to finish")


func test_finish_rebirth_keeps_the_ember_left_then_cooldown_runs() -> void:
	state.ember = 70.0
	state.kill()
	state.start_rebirth(params)
	_steps(params.rebirth_ticks)
	state.finish_rebirth(params)
	assert_false(state.dead)
	assert_false(state.is_rebirthing())
	assert_eq(state.rebirth_left, -1)
	assert_almost(state.ember, 20.0, 0.001, "not reset to resting")
	_steps(10)
	assert_eq(state.rebirth_cooldown, params.rebirth_cooldown_ticks - 10)
	assert_false(state.can_rebirth(params))


func test_rebirth_refused_when_not_eligible_or_alive() -> void:
	state.ember = 80.0
	assert_false(state.start_rebirth(params), "alive")
	state.ember = 30.0
	state.kill()
	assert_false(state.start_rebirth(params), "not enough Ember")
	assert_false(state.is_rebirthing())


func test_rebirth_on_cooldown_uses_a_charge_and_leaves_the_cooldown() -> void:
	state.ember = 60.0
	state.rebirth_cooldown = 50
	state.grant_rebirth_charge()
	state.kill()
	assert_true(state.start_rebirth(params))
	assert_eq(state.rebirth_charges, 0)
	assert_eq(state.rebirth_cooldown, 50)


func test_rebirth_health_is_a_fraction_of_max() -> void:
	assert_almost(PlayerState.rebirth_health(params), 300.0)


func test_respawn_resets_ember_to_resting() -> void:
	state.ember = 12.0
	state.combat_ticks = 5
	state.kill()
	state.revive(params)
	assert_almost(state.ember, 50.0)
	assert_false(state.in_combat())


func test_reduce_rebirth_cooldown_hook() -> void:
	state.rebirth_cooldown = 100
	var events := state.server_events
	state.reduce_rebirth_cooldown(30)
	assert_eq(state.rebirth_cooldown, 70)
	assert_eq(state.server_events, events + 1)
	state.reduce_rebirth_cooldown(500)
	assert_eq(state.rebirth_cooldown, 0)


# --- Healing over time ---

func test_heal_over_time_ticks_on_its_interval() -> void:
	var effects := StatusEffects.new()
	effects.apply(params.statuses, mend, 1, -1, 7)
	var healed := 0.0
	for i in 60:
		effects.tick(params.statuses)
		healed += effects.heal_due
	assert_almost(healed, 40.0, 0.001, "two intervals of 20")
	assert_eq(effects.last_heal_source, 7)
	assert_false(effects.has(mend), "expired")


func test_heal_over_time_is_a_step_output() -> void:
	state.statuses.apply(params.statuses, mend)
	_steps(29)
	assert_almost(state.status_heal, 0.0)
	_step()
	assert_almost(state.status_heal, 20.0)
	_step()
	assert_almost(state.status_heal, 0.0, 0.001, "only on the interval tick")


# --- Wing tree ---

func _wing_tree() -> MasteryTree:
	var t := MasteryTree.new()
	t.slot_count = PlayerState.WING_SLOTS
	t.branches = PackedStringArray(["bulwark", "fury"])
	t.tier_requirements = PackedInt32Array([0, 2])
	t.points = 4
	t.add_node("mantle_node", "bulwark", 1, MasteryTree.KIND_ACTIVE, 1, "mantle")
	t.add_node("hide", "bulwark", 1, MasteryTree.KIND_PASSIVE, 1)
	t.get_node("hide").effect = "damage_taken"
	t.get_node("hide").amount = -0.1
	t.add_node("dive_node", "fury", 2, MasteryTree.KIND_ACTIVE, 1, "dive")
	t.add_node("fury_1", "fury", 1, MasteryTree.KIND_PASSIVE, 1)
	t.add_node("fury_2", "fury", 1, MasteryTree.KIND_PASSIVE, 1)
	t.default_nodes = PackedStringArray(["mantle_node", "hide"])
	t.default_slots = PackedStringArray(["mantle", ""])
	return t


func test_wing_tree_has_two_slots() -> void:
	var t := _wing_tree()
	var nodes := PackedStringArray(["mantle_node"])
	assert_eq(t.validate_slots(nodes, PackedStringArray(["mantle", ""])), "")
	assert_true(t.validate_slots(nodes, PackedStringArray(["mantle", "", ""])) != "", "3 slots")
	assert_true(t.validate_slots(nodes, PackedStringArray(["dive", ""])) != "", "locked")


func test_wing_tree_follows_tier_gates_and_points() -> void:
	var t := _wing_tree()
	assert_true(t.validate(PackedStringArray(["dive_node"])) != "", "tier 2 needs 2 points")
	assert_eq(t.validate(PackedStringArray(["fury_1", "fury_2", "dive_node"])), "")
	assert_true(t.validate(PackedStringArray(["fury_1", "fury_2", "dive_node", "mantle_node",
			"hide"])) != "", "over the 4 points")


func test_build_wing_respec_is_validated() -> void:
	var class_def := ClassDef.new()
	class_def.id = "test"
	class_def.display_name = "Tester"
	class_def.default_loadout = PackedStringArray(["a", "b"])
	var build := CharacterBuild.create(class_def, {}, _wing_tree())
	assert_eq(build.wing_slots, PackedStringArray(["mantle", ""]))
	assert_true(build.set_wing_mastery(PackedStringArray(["mantle_node"]),
			PackedStringArray(["dive", ""])) != "", "dive isn't learned")
	assert_eq(build.wing_slots, PackedStringArray(["mantle", ""]), "unchanged when refused")
	assert_eq(build.set_wing_mastery(PackedStringArray(["fury_1", "fury_2", "dive_node"]),
			PackedStringArray(["", "dive"])), "")
	assert_eq(build.wing_state_slots(params), PackedInt32Array([-1, 1]))
	build.apply_to_state(state, params)
	assert_eq(state.wing_slots, PackedInt32Array([-1, 1]))
	assert_eq(state.wing_set, "test")


func test_wing_tree_damage_taken_modifier() -> void:
	var class_def := ClassDef.new()
	class_def.id = "test"
	var build := CharacterBuild.create(class_def, {}, _wing_tree())
	assert_almost(build.damage_taken_multiplier(), 0.9)
	var without := CharacterBuild.create(class_def, {})
	assert_almost(without.damage_taken_multiplier(), 1.0)
	assert_eq(without.wing_set_id(), "")


func test_real_wing_trees_defaults_are_valid() -> void:
	# Like the item data check: the shipped Wing trees' defaults must follow their
	# own rules, and every active must name an ability in the class's Wing pool.
	for file in Tuning.files_with_prefix("mastery_wings_"):
		var class_id := file.trim_prefix("mastery_wings_")
		var tree := MasteryTree.for_wings(class_id)
		assert_eq(tree.validate(tree.default_nodes), "", file)
		assert_eq(tree.validate_slots(tree.default_nodes, tree.default_slots), "", file)
		var pool := WingParams.from_tuning(class_id, 60.0)
		for id in tree.node_order:
			var n := tree.get_node(id)
			if n.kind == MasteryTree.KIND_ACTIVE:
				assert_true(pool.ability_index(n.ability) >= 0, "%s: %s" % [file, n.ability])
