extends TestCase
## Statuses inside the predicted simulation: PlayerState (ticking down,
## server events vs predicted self-buffs, stun = stagger, root, cleanse,
## death, network round trip, determinism) and PlayerMovement (slow, root).
## Fixed params, not the data files.

const ATTACK := PlayerState.BUTTON_ATTACK
const DODGE := PlayerState.BUTTON_DODGE
const JUMP := PlayerState.BUTTON_JUMP
const Q := PlayerState.BUTTON_ABILITY_1
const E := PlayerState.BUTTON_ABILITY_2
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState
var bleed: int
var slow: int
var root: int
var stun: int
var exposed: int
var bloodlust: int


func before_each() -> void:
	params = PlayerParams.new()
	params.move_speed = 6.0
	params.ground_acceleration = 60.0
	params.ground_deceleration = 60.0
	params.air_acceleration = 60.0
	params.gravity = 18.0
	params.jump_velocity = 6.0
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.dodge_stamina_cost = 30.0
	params.dodge_ticks = 20
	params.dodge_speed = 9.0
	params.max_air_dodges = 1
	params.ability_buffer_ticks = 4

	var defs := StatusDefs.new()
	bleed = defs.add(_def("bleed", 120, 5, StatusDef.CATEGORY_DEBUFF))
	defs.get_def(bleed).tick_interval_ticks = 30
	defs.get_def(bleed).damage_per_interval = 5.0
	slow = defs.add(_def("slow", 60, 1, StatusDef.CATEGORY_DEBUFF))
	defs.get_def(slow).move_multiplier = 0.5
	root = defs.add(_def("root", 40, 1, StatusDef.CATEGORY_DEBUFF))
	defs.get_def(root).stops_movement = true
	stun = defs.add(_def("stun", 30, 1, StatusDef.CATEGORY_DEBUFF))
	defs.get_def(stun).stuns = true
	exposed = defs.add(_def("exposed", 200, 1, StatusDef.CATEGORY_DEBUFF))
	defs.get_def(exposed).damage_taken = 0.25
	bloodlust = defs.add(_def("bloodlust", 300, 4, StatusDef.CATEGORY_BUFF))
	defs.get_def(bloodlust).on_hit_status = "bleed"
	defs.get_def(bloodlust).on_hit_stacks = 1
	defs.get_def(bloodlust).consume_on_hit = true
	params.statuses = defs

	var weapon := params.default_weapon
	weapon.heavy_hold_ticks = 5
	weapon.attack_buffer_ticks = 4
	weapon.attack_turn_speed = TAU
	weapon.light_attack = _attack(AttackParams.new(), 3, 2, 4)
	weapon.heavy_attack = _attack(AttackParams.new(), 6, 2, 5)
	var war_cry := AbilityParams.new()
	_attack(war_cry, 2, 2, 2)
	war_cry.id = "war_cry"
	war_cry.cooldown_ticks = 100
	war_cry.shape = AttackParams.SHAPE_NONE
	war_cry.self_status = "bloodlust"
	war_cry.self_status_stacks = 4
	var opener := AbilityParams.new()
	_attack(opener, 3, 2, 4)
	opener.id = "opener"
	opener.cooldown_ticks = 100
	opener.applies_status = "exposed"
	weapon.abilities = [war_cry, opener]

	state = PlayerState.new()
	state.stamina = params.max_stamina
	state.set_loadout(PackedStringArray(), PackedInt32Array([0, 1, -1, -1, -1, -1]))


func _def(id: String, duration: int, max_stacks: int, category: String) -> StatusDef:
	var d := StatusDef.new()
	d.id = id
	d.display_name = id.capitalize()
	d.category = category
	d.duration_ticks = duration
	d.max_stacks = max_stacks
	return d


func _attack(a: AttackParams, windup: int, active: int, recovery: int) -> AttackParams:
	a.windup_ticks = windup
	a.active_ticks = active
	a.recovery_ticks = recovery
	return a


func _step(buttons: int = 0, move: Vector2 = Vector2.ZERO) -> void:
	state.step(move, buttons, 0.0, true, params, DELTA)


func _steps(count: int, buttons: int = 0) -> void:
	for i in count:
		_step(buttons)


# --- PlayerState ---

func test_statuses_tick_down_in_step() -> void:
	state.apply_status(params, slow)
	_steps(59)
	assert_true(state.statuses.has(slow))
	_step()
	assert_false(state.statuses.has(slow))


func test_server_debuff_is_a_server_event() -> void:
	var events := state.server_events
	assert_true(state.apply_status(params, slow, 1, -1, 7))
	assert_eq(state.server_events, events + 1)


func test_no_status_while_dead() -> void:
	state.kill()
	assert_false(state.apply_status(params, slow))
	assert_true(state.statuses.is_empty())


func test_self_buff_is_predicted_not_a_server_event() -> void:
	var events := state.server_events
	_step(Q)
	assert_true(state.is_using_ability())
	assert_eq(state.statuses.stacks(bloodlust), 4, "applied as the ability starts")
	assert_eq(state.server_events, events, "inside the sim, not a server event")


func test_bloodlust_next_n_hits_through_player_state() -> void:
	_step(Q)
	var events := state.server_events
	for hit in 4:
		var on_hit := state.take_on_hit_statuses(params)
		assert_eq(on_hit, [Vector2i(bleed, 1)] as Array[Vector2i], "hit %d" % hit)
	assert_eq(state.server_events, events + 4, "each used-up stack is a server event")
	assert_false(state.statuses.has(bloodlust))
	assert_eq(state.take_on_hit_statuses(params).size(), 0)
	assert_eq(state.server_events, events + 4, "nothing changed, no event")


func test_attack_status_keys_are_not_applied_to_self() -> void:
	_step(E)
	assert_true(state.is_using_ability())
	assert_true(state.statuses.is_empty(), "applies_status is for the target (server)")


func test_stun_staggers_for_its_duration() -> void:
	_step(ATTACK)
	_step()  # released: light attack starts
	assert_true(state.is_attacking())
	state.apply_status(params, stun)
	assert_false(state.is_attacking(), "interrupted")
	assert_false(state.can_act())
	assert_eq(state.stagger_ticks, 30)
	_steps(30)
	assert_true(state.can_act())
	assert_false(state.statuses.has(stun))


func test_rooted_cannot_dodge_but_can_attack() -> void:
	state.apply_status(params, root)
	assert_false(state.can_dodge(true, params))
	_step(DODGE)
	assert_false(state.is_dodging())
	_step(ATTACK)
	_step()
	assert_true(state.is_attacking(), "attacks still work")


func test_cleanse_removes_debuffs_and_ends_stun() -> void:
	_step(Q)  # bloodlust (buff)
	_steps(6)
	state.apply_status(params, slow)
	state.apply_status(params, stun)
	var events := state.server_events
	assert_eq(state.cleanse(params), 2)
	assert_eq(state.server_events, events + 1)
	assert_true(state.can_act(), "stun's stagger ended")
	assert_true(state.statuses.has(bloodlust), "buffs stay")


func test_death_clears_statuses() -> void:
	state.apply_status(params, bleed, 3)
	state.apply_status(params, exposed)
	state.kill()
	assert_true(state.statuses.is_empty())


func test_step_reports_bleed_damage() -> void:
	state.apply_status(params, bleed, 2)
	var total := 0.0
	for i in 30:
		_step()
		total += state.status_damage
	assert_almost(total, 10.0, 0.001, "2 stacks x 5 at tick 30")


func test_to_array_round_trip_keeps_statuses() -> void:
	state.apply_status(params, bleed, 3)
	state.apply_status(params, slow)
	_steps(5)
	var copy := PlayerState.from_array(state.to_array())
	assert_eq(copy.statuses.to_packed(), state.statuses.to_packed())
	assert_true(copy.matches(state))
	copy.statuses.apply(params.statuses, bleed)
	assert_false(copy.matches(state), "a stack difference is a mismatch")


## Statuses are index 27, followed by forced movement (28-30) and the dodge
## cooldown (31).
func test_statuses_are_at_index_27_in_to_array() -> void:
	state.apply_status(params, slow)
	var data := state.to_array()
	assert_true(data.size() >= 32, "later fields are appended after")
	assert_eq(data[27], state.statuses.to_packed())
	assert_true(PlayerState.from_array(data).matches(state))


func test_prediction_replay_is_deterministic() -> void:
	state.apply_status(params, slow)
	state.apply_status(params, bleed, 2)
	var replay := state.copy()
	var inputs := [Q, 0, 0, ATTACK, 0, DODGE, 0, E, 0, 0]
	for i in 80:
		var buttons: int = inputs[i % inputs.size()]
		var move := Vector2(cos(i * 0.1), sin(i * 0.1))
		state.step(move, buttons, 0.3, true, params, DELTA)
		replay.step(move, buttons, 0.3, true, params, DELTA)
		assert_true(replay.matches(state), "tick %d" % i)
	assert_eq(replay.to_array(), state.to_array())


# --- PlayerMovement ---

## Walks right for `ticks` (pressing `buttons` on the first) with the given
## statuses, in empty space (airborne). Returns [position, velocity].
func _run(statuses: Array[int], ticks: int, buttons: int = 0) -> Array:
	var body := CharacterBody3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	var s := PlayerState.new()
	s.stamina = params.max_stamina
	for index in statuses:
		s.apply_status(params, index)
	for i in ticks:
		PlayerMovement.step(body, s, Vector2.RIGHT, buttons if i == 0 else 0, 0.0, params, DELTA)
	var result := [body.global_position, body.velocity]
	body.free()
	return result


func test_slow_scales_walking_speed() -> void:
	var normal: Array = _run([] as Array[int], 30)
	var slowed: Array = _run([slow] as Array[int], 30)
	assert_almost(normal[1].x, 6.0, 0.001)
	assert_almost(slowed[1].x, 3.0, 0.001)


func test_root_stops_walking_and_dodging() -> void:
	var rooted: Array = _run([root] as Array[int], 20, DODGE)
	assert_almost(rooted[1].x, 0.0, 0.001)
	assert_almost(rooted[0].x, 0.0, 0.001)


func test_movement_with_statuses_is_deterministic() -> void:
	var a: Array = _run([slow, bleed] as Array[int], 40)
	var b: Array = _run([slow, bleed] as Array[int], 40)
	assert_eq(a[0], b[0])
	assert_eq(a[1], b[1])
