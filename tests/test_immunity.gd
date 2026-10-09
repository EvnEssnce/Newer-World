extends TestCase
## Immunity statuses (the Juggernaut's Braced, Steadfast, Unbowed) and the taunt
## status: what StatusEffects refuses, and PlayerState's stagger, stun, guard
## break and forced-movement refusals. Fixed defs, not the data file.

const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState
var defs: StatusDefs
var bleed: int
var slow: int
var root: int
var stun: int
var taunted: int
var empowered: int
var braced: int
var steadfast: int
var unbowed: int


func before_each() -> void:
	defs = StatusDefs.new()
	bleed = defs.add(_def("bleed", StatusDef.CATEGORY_DEBUFF))
	slow = defs.add(_def("slow", StatusDef.CATEGORY_DEBUFF))
	defs.get_def(slow).move_multiplier = 0.6
	root = defs.add(_def("root", StatusDef.CATEGORY_DEBUFF))
	defs.get_def(root).stops_movement = true
	stun = defs.add(_def("stun", StatusDef.CATEGORY_DEBUFF))
	defs.get_def(stun).stuns = true
	taunted = defs.add(_def("taunted", StatusDef.CATEGORY_DEBUFF))
	defs.get_def(taunted).forces_target = true
	empowered = defs.add(_def("empowered", StatusDef.CATEGORY_BUFF))
	defs.get_def(empowered).damage_dealt = 0.2
	braced = defs.add(_def("braced", StatusDef.CATEGORY_BUFF))
	defs.get_def(braced).force_immune = true
	steadfast = defs.add(_def("steadfast", StatusDef.CATEGORY_BUFF))
	defs.get_def(steadfast).force_immune = true
	defs.get_def(steadfast).stagger_immune = true
	unbowed = defs.add(_def("unbowed", StatusDef.CATEGORY_BUFF))
	defs.get_def(unbowed).force_immune = true
	defs.get_def(unbowed).stagger_immune = true
	defs.get_def(unbowed).cc_immune = true

	params = PlayerParams.new()
	params.max_stamina = 100.0
	params.guard_break_stagger_ticks = 30
	params.statuses = defs
	state = PlayerState.new()
	state.stamina = 100.0


func _def(id: String, category: String) -> StatusDef:
	var d := StatusDef.new()
	d.id = id
	d.display_name = id.capitalize()
	d.category = category
	d.duration_ticks = 120
	return d


func _give(index: int) -> void:
	assert_true(state.statuses.apply(defs, index), "self-applied")


func test_crowd_control_is_slow_root_stun_taunt() -> void:
	for index in [slow, root, stun, taunted]:
		assert_true(defs.get_def(index).is_crowd_control(), defs.get_def(index).id)
	for index in [bleed, empowered, unbowed]:
		assert_false(defs.get_def(index).is_crowd_control(), defs.get_def(index).id)


func test_nobody_is_immune_by_default() -> void:
	assert_false(state.is_force_immune(params))
	for index in [slow, root, stun, taunted]:
		assert_false(state.statuses.refuses(defs, index))


func test_braced_refuses_force_only() -> void:
	_give(braced)
	assert_true(state.is_force_immune(params))
	assert_false(state.start_force(params, Vector2(2.0, 0.0), 10, 0.0, DELTA))
	assert_false(state.is_forced())
	state.apply_stagger(10, params)
	assert_false(state.can_act(), "still staggers")
	assert_true(state.apply_status(params, slow), "still slowed")


func test_steadfast_refuses_stagger_and_stun() -> void:
	_give(steadfast)
	assert_true(state.is_force_immune(params))
	state.apply_stagger(10, params)
	assert_true(state.can_act(), "no stagger")
	var events := state.server_events
	assert_false(state.apply_status(params, stun), "no stun")
	assert_false(state.statuses.has(stun))
	assert_eq(state.server_events, events, "a refusal changes nothing to predict")
	assert_true(state.apply_status(params, root), "still rooted")


func test_steadfast_guard_break_takes_stamina_but_no_stagger() -> void:
	_give(steadfast)
	var attack := AttackParams.new()
	attack.block_stamina_damage = 20.0
	attack.breaks_block = true
	state.blocking = true
	assert_true(state.take_blocked_hit(attack, params), "still a guard break")
	assert_almost(state.stamina, 80.0)
	assert_true(state.can_act(), "but no stagger")


func test_unbowed_refuses_every_crowd_control() -> void:
	_give(unbowed)
	for index in [slow, root, stun, taunted]:
		assert_false(state.apply_status(params, index), defs.get_def(index).id)
	assert_eq(state.statuses.entries.size(), 1, "only Unbowed itself")
	assert_true(state.apply_status(params, bleed), "damage debuffs still land")
	assert_true(state.apply_status(params, empowered), "buffs still land")
	assert_false(state.start_force(params, Vector2(2.0, 0.0), 10, 0.0, DELTA))
	state.apply_stagger(10, params)
	assert_true(state.can_act())


func test_immunity_doesnt_remove_what_is_already_there() -> void:
	state.apply_status(params, slow)
	_give(unbowed)
	assert_true(state.statuses.has(slow))


func test_immunity_ends_with_the_status() -> void:
	_give(steadfast)
	state.statuses.remove(steadfast)
	state.apply_stagger(10, params)
	assert_false(state.can_act())


func test_forced_target_is_the_taunt_source() -> void:
	var effects := StatusEffects.new()
	assert_eq(effects.forced_target(defs), 0)
	effects.apply(defs, slow, 1, -1, 3)
	assert_eq(effects.forced_target(defs), 0, "only taunts force a target")
	effects.apply(defs, taunted, 1, -1, 5)
	assert_eq(effects.forced_target(defs), 5)
	effects.apply(defs, taunted, 1, -1, 6)
	assert_eq(effects.forced_target(defs), 6, "the latest taunter")
	for i in 120:
		effects.tick(defs)
	assert_eq(effects.forced_target(defs), 0, "ends with the status")


func test_unbowed_enemy_refuses_a_taunt() -> void:
	var effects := StatusEffects.new()
	effects.apply(defs, unbowed)
	assert_false(effects.apply(defs, taunted, 1, -1, 5))
	assert_eq(effects.forced_target(defs), 0)
	assert_true(effects.force_immune(defs))
	assert_true(effects.stagger_immune(defs))


func test_a_taunt_must_be_a_debuff() -> void:
	defs.get_def(taunted).category = StatusDef.CATEGORY_BUFF
	assert_false(defs.validate().is_empty())
