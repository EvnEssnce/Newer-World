extends TestCase
## Ability rules in PlayerState (cooldowns, phases, hit windows, buffering,
## parry and counter, stopping on hit) and the ability dash in PlayerMovement.
## Fixed params, not the weapon files.

const ATTACK := PlayerState.BUTTON_ATTACK
const DODGE := PlayerState.BUTTON_DODGE
const Q := PlayerState.BUTTON_ABILITY_1
const E := PlayerState.BUTTON_ABILITY_2
const R := PlayerState.BUTTON_ABILITY_3
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState
## Pool indices in the test weapon.
var strike: AbilityParams   # 0: plain, slot Q
var flurry: AbilityParams   # 1: three hit windows, slot E
var parry: AbilityParams    # 2: parry stance, slot R
var counter: AbilityParams  # 3: the parry's counter (internal)
var dash: AbilityParams     # 4: dashes forward (not slotted by default)


func before_each() -> void:
	params = PlayerParams.new()
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.dodge_stamina_cost = 30.0
	params.dodge_ticks = 20
	params.dodge_buffer_ticks = 5
	params.ability_buffer_ticks = 4
	var weapon := params.default_weapon
	weapon.heavy_hold_ticks = 5
	weapon.attack_buffer_ticks = 4
	weapon.attack_turn_speed = TAU
	weapon.light_attack = _attack(AttackParams.new(), 3, 2, 4)
	weapon.heavy_attack = _attack(AttackParams.new(), 6, 2, 5)

	strike = _ability("strike", 3, 2, 4, 30)
	flurry = _ability("flurry", 2, 2, 3, 20)
	flurry.windows = 3
	flurry.window_interval_ticks = 4
	parry = _ability("parry", 0, 10, 5, 40)
	parry.shape = AttackParams.SHAPE_NONE
	parry.parry_arc = deg_to_rad(120.0)
	parry.counter = "counter"
	counter = _ability("counter", 2, 2, 3, 0)
	counter.internal = true
	dash = _ability("dash", 2, 6, 3, 30)
	dash.dash_start_tick = 2
	dash.dash_end_tick = 8
	dash.dash_speed = 9.0
	weapon.abilities = [strike, flurry, parry, counter, dash]

	state = PlayerState.new()
	state.stamina = params.max_stamina
	state.set_loadout(PackedStringArray(), PackedInt32Array([0, 1, 2, -1, -1, -1]))


func _attack(a: AttackParams, windup: int, active: int, recovery: int) -> AttackParams:
	a.windup_ticks = windup
	a.active_ticks = active
	a.recovery_ticks = recovery
	return a


func _ability(id: String, windup: int, active: int, recovery: int, cooldown: int) -> AbilityParams:
	var a := AbilityParams.new()
	_attack(a, windup, active, recovery)
	a.id = id
	a.cooldown_ticks = cooldown
	a.turn_speed = TAU
	return a


func _step(buttons: int = 0, aim_yaw: float = 0.0, move: Vector2 = Vector2.ZERO) -> void:
	state.step(move, buttons, aim_yaw, true, params, DELTA)


func _steps(count: int, buttons: int = 0, aim_yaw: float = 0.0) -> void:
	for i in count:
		_step(buttons, aim_yaw)


func test_press_starts_ability_facing_aim() -> void:
	_step(Q, 1.0)
	assert_true(state.is_using_ability())
	assert_eq(state.ability, 0)
	assert_eq(state.attack_tick, 0)
	assert_almost(state.yaw, 1.0)
	assert_eq(state.current_ability(params), strike)


func test_each_key_uses_its_slot() -> void:
	_step(E)
	assert_eq(state.ability, 1)
	state = PlayerState.new()
	state.set_loadout(PackedStringArray(), PackedInt32Array([0, 1, 2, -1, -1, -1]))
	_step(R)
	assert_eq(state.ability, 2)


func test_empty_slot_does_nothing() -> void:
	state.set_loadout(PackedStringArray(), PackedInt32Array([-1, 1, 2, -1, -1, -1]))
	_step(Q)
	assert_false(state.is_attacking())
	assert_eq(state.queued_attack, PlayerState.ATTACK_NONE, "not left queued")


func test_phases_follow_the_timeline() -> void:
	_step(Q)
	var active := []
	var recovering := []
	for i in strike.total_ticks():
		if state.is_attack_active(params):
			active.append(state.attack_tick)
		if state.is_attack_recovering(params):
			recovering.append(state.attack_tick)
		_step()
	assert_eq(active, [3, 4])
	assert_eq(recovering, [5, 6, 7, 8])
	assert_false(state.is_attacking(), "over after total_ticks")


func test_multi_window_ability_has_separate_hit_windows() -> void:
	assert_eq(flurry.recovery_start_tick(), 2 + 2 * 4 + 2)
	assert_eq(flurry.total_ticks(), flurry.recovery_start_tick() + 3)
	_step(E)
	var windows := []
	for i in flurry.total_ticks():
		windows.append(state.attack_window(params))
		_step()
	assert_eq(windows, [-1, -1, 0, 0, -1, -1, 1, 1, -1, -1, 2, 2, -1, -1, -1])


func test_cooldown_starts_with_the_ability_and_blocks_reuse() -> void:
	_step(Q)
	assert_eq(state.cooldown_left(0), strike.cooldown_ticks)
	_steps(strike.total_ticks())
	assert_false(state.is_attacking())
	_step(Q)
	assert_false(state.is_attacking(), "still cooling down")


func test_cooldown_runs_out_after_its_ticks() -> void:
	_step(Q)
	_steps(strike.cooldown_ticks - 1)
	assert_eq(state.cooldown_left(0), 1)
	_step()
	assert_eq(state.cooldown_left(0), 0)
	_step(Q)
	assert_true(state.is_using_ability(), "ready again")


func test_press_just_before_cooldown_ends_is_buffered() -> void:
	_step(Q)
	_steps(strike.cooldown_ticks - 3)  # 2 ticks of cooldown left after the next step
	_step(Q)
	assert_false(state.is_attacking())
	_steps(2)
	assert_true(state.is_using_ability(), "fired when the cooldown ran out")


func test_ability_pressed_mid_attack_starts_after_it() -> void:
	_step(ATTACK)
	_step()  # light attack starts (on release)
	_steps(params.default_weapon.light_attack.total_ticks() - 3)
	_step(Q)
	assert_eq(state.attack_type, PlayerState.ATTACK_LIGHT, "can't interrupt the attack")
	_steps(2)
	assert_true(state.is_using_ability(), "starts the tick the attack ends")


func test_buffered_ability_expires() -> void:
	_step(DODGE)
	_step(Q)  # mid-roll, 18 ticks left: longer than the 4-tick buffer
	_steps(params.dodge_ticks)
	assert_false(state.is_attacking())


func test_dodge_cancels_ability_recovery_only() -> void:
	_step(Q)
	_step(DODGE)  # windup: buffered
	assert_false(state.is_dodging())
	_steps(3)  # tick 4, active
	assert_false(state.is_dodging())
	_step()  # tick 5, recovery: the buffered dodge fires
	assert_true(state.is_dodging())
	assert_false(state.is_attacking())


func test_zero_turn_speed_locks_facing() -> void:
	strike.turn_speed = 0.0
	_step(Q, 0.0)
	_steps(3, 0, 1.0)
	assert_almost(state.yaw, 0.0)


func test_turn_speed_follows_aim() -> void:
	_step(Q, 0.0)
	_step(0, 1.0)
	assert_almost(state.yaw, TAU / 60.0, 0.001)


func test_cannot_block_during_ability() -> void:
	_step(Q)
	_step(PlayerState.BUTTON_BLOCK)
	assert_false(state.blocking)


func test_parry_window_is_the_active_phase() -> void:
	_step(R)
	var parrying := []
	for i in parry.total_ticks():
		parrying.append(state.is_parrying(params))
		_step()
	assert_eq(parrying.count(true), parry.active_ticks)
	assert_true(parrying[0], "no windup")
	assert_false(parrying[parry.active_ticks], "recovery")


func test_parry_has_no_hitbox() -> void:
	_step(R)
	assert_false(state.is_attack_active(params))
	assert_eq(state.attack_window(params), -1)


func test_counter_replaces_the_parry_and_faces_the_attacker() -> void:
	_step(R)
	_steps(3)
	var events := state.server_events
	assert_true(state.start_counter(params, 2.0))
	assert_eq(state.current_ability(params), counter)
	assert_eq(state.attack_tick, 0)
	assert_almost(state.yaw, 2.0)
	assert_eq(state.server_events, events + 1, "a server event")
	assert_false(state.is_parrying(params))
	_steps(counter.windup_ticks)
	assert_true(state.is_attack_active(params), "the counter can hit")


func test_counter_needs_a_parry_ability() -> void:
	_step(Q)
	assert_false(state.start_counter(params, 0.0))
	assert_eq(state.current_ability(params), strike)


func test_counter_is_not_on_cooldown_and_keeps_the_parry_cooldown() -> void:
	_step(R)
	state.start_counter(params, 0.0)
	assert_eq(state.cooldown_left(3), 0)
	assert_eq(state.cooldown_left(2), parry.cooldown_ticks - 0)


func test_end_active_window_skips_to_recovery() -> void:
	_step(Q)
	_steps(3)
	assert_true(state.is_attack_active(params))
	var events := state.server_events
	state.end_active_window(params)
	assert_eq(state.attack_tick, strike.recovery_start_tick())
	assert_false(state.is_attack_active(params))
	assert_eq(state.server_events, events + 1)
	state.end_active_window(params)
	assert_eq(state.server_events, events + 1, "no-op once recovering")


func test_dash_window() -> void:
	state.set_loadout(PackedStringArray(), PackedInt32Array([4, -1, -1, -1, -1, -1]))
	_step(Q, 1.0)
	var dashing := []
	for i in dash.total_ticks():
		dashing.append(state.is_dashing(params))
		_step()
	assert_eq(dashing.find(true), 2)
	assert_eq(dashing.count(true), 6)
	assert_almost(state.ability_dir.x, PlayerState.forward(1.0).x)
	assert_almost(state.ability_dir.y, PlayerState.forward(1.0).y)


func test_stagger_interrupts_ability_but_keeps_cooldown() -> void:
	_step(Q)
	state.apply_stagger(10)
	assert_false(state.is_attacking())
	assert_eq(state.cooldown_left(0), strike.cooldown_ticks)


func test_network_round_trip_keeps_ability_state() -> void:
	_step(Q, 0.5)
	_steps(2)
	_step(E)  # queued
	var copy := PlayerState.from_array(state.to_array())
	assert_true(copy.matches(state))
	assert_eq(copy.ability, state.ability)
	assert_eq(copy.cooldowns, state.cooldowns)
	assert_eq(copy.ability_slots, state.ability_slots)
	assert_eq(copy.queued_ability_slot, 1)
	assert_eq(copy.attack_serial, state.attack_serial)
	copy.cooldowns[0] = 0
	assert_false(copy.matches(state), "cooldowns are compared")
	assert_eq(state.cooldown_left(0), strike.cooldown_ticks - 3, "copy doesn't share arrays")


# --- Dash physics (PlayerMovement), in empty space ---

## Runs a dash ability from the origin, holding a sideways move input the whole
## time. Returns [position, state].
func _dash_run() -> Array:
	state = PlayerState.new()
	state.stamina = params.max_stamina
	state.set_loadout(PackedStringArray(), PackedInt32Array([4, -1, -1, -1, -1, -1]))
	params.move_speed = 6.0
	params.air_acceleration = 12.0
	params.gravity = 18.0
	var body := CharacterBody3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	PlayerMovement.step(body, state, Vector2.ZERO, Q, 0.0, params, DELTA)
	var start := body.global_position
	# Ticks 1 .. dash_end_tick - 1: the windup tick, then the whole dash.
	for i in dash.dash_end_tick - 1:
		PlayerMovement.step(body, state, Vector2.RIGHT, 0, 0.0, params, DELTA)
	var result := [body.global_position - start, state.copy()]
	body.free()
	return result


func test_dash_moves_its_distance_forward_ignoring_input() -> void:
	var run := _dash_run()
	var moved: Vector3 = run[0]
	var dash_ticks := dash.dash_end_tick - dash.dash_start_tick
	# Facing yaw 0 = -Z. The sideways input does nothing (move_multiplier 0
	# during the windup, ignored during the dash).
	assert_almost(-moved.z, dash.dash_speed * dash_ticks * DELTA, 0.0001, "forward distance")
	assert_almost(moved.x, 0.0, 0.0001, "no sideways drift")


func test_dash_is_deterministic() -> void:
	var first := _dash_run()
	var second := _dash_run()
	assert_eq(first[0], second[0])
	assert_true((first[1] as PlayerState).matches(second[1]))
