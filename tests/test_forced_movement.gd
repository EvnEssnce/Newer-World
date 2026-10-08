extends TestCase
## Forced movement (knockback, pull, launch): ForceParams math, ForcedMotion,
## the PlayerState rules (start, can't act, i-frames, ending, network round
## trip), PlayerMovement physics and determinism, and the backward dash (Vault).
## Fixed params, not the data files.

const ATTACK := PlayerState.BUTTON_ATTACK
const DODGE := PlayerState.BUTTON_DODGE
const Q := PlayerState.BUTTON_ABILITY_1
const DELTA := 1.0 / 60.0
const TPS := 60.0

var params: PlayerParams
var state: PlayerState
var vault: AbilityParams


func before_each() -> void:
	params = PlayerParams.new()
	params.move_speed = 6.0
	params.ground_acceleration = 60.0
	params.ground_deceleration = 50.0
	params.air_acceleration = 12.0
	params.gravity = 18.0
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.dodge_stamina_cost = 30.0
	params.dodge_ticks = 20
	params.dodge_speed = 9.0
	params.iframe_start_tick = 0
	params.iframe_end_tick = 10
	params.dodge_buffer_ticks = 5
	params.ability_buffer_ticks = 4
	params.max_air_dodges = 1
	var weapon := params.default_weapon
	weapon.heavy_hold_ticks = 5
	weapon.attack_buffer_ticks = 4
	weapon.attack_turn_speed = TAU
	weapon.light_attack = _attack(AttackParams.new(), 3, 2, 4)
	weapon.heavy_attack = _attack(AttackParams.new(), 6, 2, 5)
	vault = AbilityParams.new()
	_attack(vault, 2, 10, 3)
	vault.id = "vault"
	vault.cooldown_ticks = 30
	vault.shape = AttackParams.SHAPE_NONE
	vault.dash_start_tick = 2
	vault.dash_end_tick = 12
	vault.dash_speed = 9.0
	vault.dash_backward = true
	weapon.abilities = [vault]

	state = PlayerState.new()
	state.stamina = params.max_stamina
	state.set_loadout(PackedStringArray(), PackedInt32Array([0, -1, -1, -1, -1, -1]))


func _attack(a: AttackParams, windup: int, active: int, recovery: int) -> AttackParams:
	a.windup_ticks = windup
	a.active_ticks = active
	a.recovery_ticks = recovery
	return a


func _force(direction: int, distance: float, height: float = 0.0, ticks: int = 10) -> ForceParams:
	var f := ForceParams.new()
	f.direction = direction
	f.distance = distance
	f.height = height
	f.duration_ticks = ticks
	return f


## One sim tick without physics: PlayerState.step plus the forced-motion step
## PlayerMovement would take.
func _tick(buttons: int = 0, move: Vector2 = Vector2.ZERO) -> void:
	state.step(move, buttons, 0.0, true, params, DELTA)
	if state.is_forced():
		state.force.step_velocity()


# --- ForceParams ---

func test_knockback_pushes_away_from_the_attacker() -> void:
	var f := _force(ForceParams.DIRECTION_AWAY, 3.0)
	var d := f.displacement(Vector3.ZERO, 0.0, Vector3(2.0, 0.0, 0.0), 10.0, 1.0)
	assert_almost(d.x, 3.0)
	assert_almost(d.y, 0.0)


func test_knockback_on_an_overlapping_target_uses_the_attacker_facing() -> void:
	var f := _force(ForceParams.DIRECTION_AWAY, 2.0)
	var d := f.displacement(Vector3.ZERO, 0.0, Vector3.ZERO, 10.0, 1.0)
	assert_true(d.is_equal_approx(Vector2(0.0, -2.0)), "yaw 0 faces -Z: %s" % d)


func test_forward_push_follows_the_attacker_facing() -> void:
	var f := _force(ForceParams.DIRECTION_FORWARD, 2.0)
	# Target off to the side; the push still goes where the attacker faces.
	var d := f.displacement(Vector3.ZERO, PI / 2.0, Vector3(0.0, 0.0, -3.0), 10.0, 1.0)
	assert_true(d.is_equal_approx(PlayerState.forward(PI / 2.0) * 2.0), str(d))


func test_pull_stops_at_the_gap_and_never_pushes() -> void:
	var f := _force(ForceParams.DIRECTION_TOWARD, 10.0)
	var d := f.displacement(Vector3.ZERO, 0.0, Vector3(5.0, 0.0, 0.0), 20.0, 1.5)
	assert_almost(d.x, -3.5, 0.001, "pulled to 1.5 m away")
	var near := f.displacement(Vector3.ZERO, 0.0, Vector3(1.0, 0.0, 0.0), 20.0, 1.5)
	assert_true(near.is_zero_approx(), "already inside the gap: %s" % near)
	var short := _force(ForceParams.DIRECTION_TOWARD, 2.0)
	assert_almost(short.displacement(Vector3.ZERO, 0.0, Vector3(5.0, 0.0, 0.0), 20.0, 1.5).x, -2.0,
			0.001, "pull limited by its own distance")


func test_distance_and_height_are_capped_by_the_limits() -> void:
	var f := _force(ForceParams.DIRECTION_AWAY, 9.0, 5.0)
	assert_almost(f.displacement(Vector3.ZERO, 0.0, Vector3(1.0, 0.0, 0.0), 4.0, 1.0).length(), 4.0)
	var speed := f.launch_speed(18.0, 2.0)
	assert_almost(speed * speed / (2.0 * 18.0), 2.0, 0.001, "peak height capped at 2 m")


func test_launch_speed_reaches_the_height_and_ticks_cover_the_airtime() -> void:
	var f := _force(ForceParams.DIRECTION_AWAY, 0.5, 0.9, 6)
	var speed := f.launch_speed(18.0, 2.0)
	assert_almost(speed * speed / (2.0 * 18.0), 0.9, 0.001)
	var airtime := 2.0 * speed / 18.0 * TPS
	assert_true(f.ticks(18.0, 2.0, TPS) >= airtime, "lasts the whole airtime")
	assert_eq(_force(ForceParams.DIRECTION_AWAY, 1.0, 0.0, 6).ticks(18.0, 2.0, TPS), 6,
			"no launch: its own duration")


# --- ForcedMotion ---

func test_motion_covers_its_distance_and_eases_out() -> void:
	var m := ForcedMotion.new()
	m.start(Vector2(3.0, -1.0), 12, 0.0, DELTA)
	var moved := Vector2.ZERO
	var last_speed := INF
	for i in 12:
		var v := m.step_velocity()
		assert_true(v.length() < last_speed, "slows every step")
		last_speed = v.length()
		moved += v * DELTA
	assert_true(moved.is_equal_approx(Vector2(3.0, -1.0)), "moved %s" % moved)
	assert_false(m.is_active())
	assert_eq(m.step_velocity(), Vector2.ZERO, "nothing after it ends")


func test_launch_is_taken_once() -> void:
	var m := ForcedMotion.new()
	m.start(Vector2.ZERO, 5, 4.0, DELTA)
	assert_almost(m.take_launch(), 4.0)
	assert_almost(m.take_launch(), 0.0)


# --- PlayerState rules ---

func test_start_force_is_a_server_event_and_stops_acting() -> void:
	var events := state.server_events
	assert_true(state.start_force(params, Vector2(2.0, 0.0), 10, 0.0, DELTA))
	assert_eq(state.server_events, events + 1)
	assert_true(state.is_forced())
	assert_false(state.can_act())


func test_force_interrupts_an_attack_like_stagger() -> void:
	_tick(ATTACK)
	_tick()  # released: light attack starts
	assert_true(state.is_attacking())
	state.start_force(params, Vector2(2.0, 0.0), 10, 0.0, DELTA)
	assert_false(state.is_attacking())


func test_cannot_attack_or_dodge_while_forced_and_presses_stay_buffered() -> void:
	state.start_force(params, Vector2(2.0, 0.0), 4, 0.0, DELTA)
	_tick(DODGE)
	assert_false(state.is_dodging(), "no dodge while being moved")
	_tick()
	_tick()
	_tick()  # the 4th forced step: done after it
	assert_false(state.is_forced())
	_tick()
	assert_true(state.is_dodging(), "the buffered dodge fires once it ends")


func test_force_ends_after_its_ticks() -> void:
	state.start_force(params, Vector2(2.0, 0.0), 6, 0.0, DELTA)
	for i in 5:
		_tick()
	assert_true(state.is_forced(), "one step left")
	_tick()
	assert_false(state.is_forced())
	assert_true(state.can_act())


func test_iframes_refuse_force() -> void:
	_tick(DODGE)
	assert_true(state.is_invulnerable(params))
	var events := state.server_events
	assert_false(state.start_force(params, Vector2(2.0, 0.0), 10, 0.0, DELTA))
	assert_true(state.is_dodging(), "the roll goes on")
	assert_eq(state.server_events, events, "no server event")


func test_dodge_after_iframes_is_interrupted() -> void:
	_tick(DODGE)
	for i in params.iframe_end_tick:
		_tick()
	assert_false(state.is_invulnerable(params))
	assert_true(state.start_force(params, Vector2(2.0, 0.0), 10, 0.0, DELTA))
	assert_false(state.is_dodging())


func test_dead_players_are_not_moved_and_death_stops_force() -> void:
	state.start_force(params, Vector2(2.0, 0.0), 10, 0.0, DELTA)
	state.kill()
	assert_false(state.is_forced(), "death ends it")
	assert_false(state.start_force(params, Vector2(2.0, 0.0), 10, 0.0, DELTA))


func test_nobody_is_force_immune_yet() -> void:
	assert_false(state.is_force_immune())


func test_network_round_trip_keeps_force() -> void:
	state.start_force(params, Vector2(2.0, 1.0), 10, 5.0, DELTA)
	_tick()
	var copy := PlayerState.from_array(state.to_array())
	assert_true(copy.matches(state))
	assert_eq(copy.force.ticks, state.force.ticks)
	assert_eq(copy.force.velocity, state.force.velocity)
	copy.force.ticks += 1
	assert_false(copy.matches(state), "force is compared")


# --- PlayerMovement physics ---

## A player in empty space (always airborne), forced with `displacement` over
## 10 ticks and launch_speed, holding a move input (+Z) the whole time.
## Returns [position change, velocity, state] after `ticks` steps.
func _forced_run(displacement: Vector2, launch_speed: float, ticks: int) -> Array:
	state = PlayerState.new()
	state.stamina = params.max_stamina
	var body := CharacterBody3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	var start := body.global_position
	state.start_force(params, displacement, 10, launch_speed, DELTA)
	for i in ticks:
		PlayerMovement.step(body, state, Vector2(0.0, 1.0), 0, 0.0, params, DELTA)
	var result := [body.global_position - start, body.velocity, state.copy()]
	body.free()
	return result


func test_forced_movement_moves_its_distance_ignoring_input() -> void:
	var run := _forced_run(Vector2(3.0, 0.0), 0.0, 10)
	var moved: Vector3 = run[0]
	assert_almost(moved.x, 3.0, 0.0001, "pushed 3 m along +X")
	assert_almost(moved.z, 0.0, 0.0001, "the move input (+Z) is ignored")
	assert_false((run[2] as PlayerState).is_forced())


func test_launch_sets_vertical_speed_then_gravity_takes_over() -> void:
	var plain := _forced_run(Vector2.ZERO, 0.0, 1)
	var launched := _forced_run(Vector2.ZERO, 6.0, 1)
	assert_almost((launched[1] as Vector3).y, 6.0, 0.0001, "launch speed on the first step")
	assert_true((launched[0] as Vector3).y > (plain[0] as Vector3).y, "rises")
	var later := _forced_run(Vector2.ZERO, 6.0, 5)
	assert_almost((later[1] as Vector3).y, 6.0 - 4.0 * params.gravity * DELTA, 0.0001,
			"gravity from the second step on")


func test_forced_movement_is_deterministic() -> void:
	var first := _forced_run(Vector2(2.0, -1.5), 5.0, 14)
	var second := _forced_run(Vector2(2.0, -1.5), 5.0, 14)
	assert_eq(first[0], second[0])
	assert_eq(first[1], second[1])
	assert_true((first[2] as PlayerState).matches(second[2]))


func test_replay_from_a_mid_force_snapshot_matches() -> void:
	# What reconciliation does: restore position, velocity and state mid-push and
	# replay the same inputs; it must land where the uninterrupted run did.
	state = PlayerState.new()
	state.stamina = params.max_stamina
	var body := CharacterBody3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	state.start_force(params, Vector2(2.5, 1.0), 12, 4.0, DELTA)
	for i in 5:
		PlayerMovement.step(body, state, Vector2.ZERO, 0, 0.0, params, DELTA)
	var saved := [body.global_position, body.velocity, state.copy()]
	for i in 10:
		PlayerMovement.step(body, state, Vector2.RIGHT, 0, 0.0, params, DELTA)
	var straight := [body.global_position, state.copy()]
	body.global_position = saved[0]
	body.velocity = saved[1]
	state = saved[2]
	for i in 10:
		PlayerMovement.step(body, state, Vector2.RIGHT, 0, 0.0, params, DELTA)
	assert_eq(body.global_position, straight[0])
	assert_true(state.matches(straight[1]))
	body.free()


# --- Vault: a backward dash ---

func test_vault_dashes_away_from_its_facing() -> void:
	state.step(Vector2.ZERO, Q, 0.5, true, params, DELTA)
	assert_true(state.is_using_ability())
	assert_almost(state.yaw, 0.5, 0.0001, "faces the aim")
	assert_true(state.ability_dir.is_equal_approx(-PlayerState.forward(0.5)),
			"dash direction is behind: %s" % state.ability_dir)


func test_vault_moves_backward_ignoring_input() -> void:
	var body := CharacterBody3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	PlayerMovement.step(body, state, Vector2.ZERO, Q, 0.0, params, DELTA)
	var start := body.global_position
	for i in vault.dash_end_tick - 1:
		PlayerMovement.step(body, state, Vector2.RIGHT, 0, 0.0, params, DELTA)
	var moved := body.global_position - start
	body.free()
	var dash_ticks := vault.dash_end_tick - vault.dash_start_tick
	# Yaw 0 faces -Z, so backward is +Z.
	assert_almost(moved.z, vault.dash_speed * dash_ticks * DELTA, 0.0001, "backward distance")
	assert_almost(moved.x, 0.0, 0.0001, "no sideways drift")

# --- Vault: dash_direction="input" and i-frames (the real Vault) ---

func test_input_dash_follows_the_movement_input() -> void:
	vault.dash_backward = false
	vault.dash_from_input = true
	state.step(Vector2(1.0, 0.0), Q, 0.5, true, params, DELTA)
	assert_true(state.ability_dir.is_equal_approx(Vector2(1.0, 0.0)),
			"dashes the way you move: %s" % state.ability_dir)


func test_input_dash_goes_backward_with_no_input() -> void:
	vault.dash_backward = false
	vault.dash_from_input = true
	state.step(Vector2.ZERO, Q, 0.5, true, params, DELTA)
	assert_true(state.ability_dir.is_equal_approx(-PlayerState.forward(0.5)))


func test_ability_iframes_only_inside_their_window() -> void:
	vault.iframe_start_tick = 2
	vault.iframe_end_tick = 6
	state.step(Vector2.ZERO, Q, 0.0, true, params, DELTA)  # attack_tick 0
	assert_false(state.is_invulnerable(params), "before the window")
	state.step(Vector2.ZERO, 0, 0.0, true, params, DELTA)
	state.step(Vector2.ZERO, 0, 0.0, true, params, DELTA)  # tick 2
	assert_true(state.is_invulnerable(params), "inside the window")
	for i in 4:
		state.step(Vector2.ZERO, 0, 0.0, true, params, DELTA)  # tick 6
	assert_false(state.is_invulnerable(params), "after the window")
