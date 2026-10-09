extends TestCase
## Block rules in PlayerState, and the frontal arc check. Fixed params.

const ATTACK := PlayerState.BUTTON_ATTACK
const BLOCK := PlayerState.BUTTON_BLOCK
const DODGE := PlayerState.BUTTON_DODGE
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState


func before_each() -> void:
	params = PlayerParams.new()
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.stamina_regen_per_tick = 1.0
	params.stamina_regen_delay_ticks = 10
	params.dodge_stamina_cost = 30.0
	params.dodge_ticks = 20
	params.dodge_buffer_ticks = 5
	params.default_weapon.heavy_hold_ticks = 5
	params.default_weapon.attack_buffer_ticks = 4
	params.default_weapon.attack_turn_speed = TAU
	params.block_arc = deg_to_rad(120.0)
	params.block_regen_multiplier = 0.5
	params.block_turn_speed = TAU
	params.guard_break_stagger_ticks = 30
	var light := AttackParams.new()
	light.windup_ticks = 3
	light.active_ticks = 2
	light.recovery_ticks = 4
	light.block_stamina_damage = 20.0
	params.default_weapon.light_attack = light
	state = PlayerState.new()
	state.stamina = params.max_stamina


func _step(buttons: int = 0, aim_yaw: float = 0.0, move: Vector2 = Vector2.ZERO) -> void:
	state.step(move, buttons, aim_yaw, true, params, DELTA)


func _steps(count: int, buttons: int = 0) -> void:
	for i in count:
		_step(buttons)


func _hit(stamina_damage: float, breaks: bool = false) -> bool:
	var attack := AttackParams.new()
	attack.block_stamina_damage = stamina_damage
	attack.breaks_block = breaks
	return state.take_blocked_hit(attack, params)


func test_holding_block_blocks() -> void:
	_step(BLOCK)
	assert_true(state.blocking)
	_step()
	assert_false(state.blocking, "released")


func test_cannot_block_while_staggered() -> void:
	state.apply_stagger(5, params)
	_step(BLOCK)
	assert_false(state.blocking)


func test_attack_while_blocking_drops_the_guard_then_it_returns() -> void:
	_step(BLOCK)
	_step(BLOCK | ATTACK)
	_step(BLOCK)  # released attack: light starts
	assert_true(state.is_attacking())
	assert_false(state.blocking, "no guard while swinging")
	_steps(params.default_weapon.light_attack.total_ticks(), BLOCK)
	assert_false(state.is_attacking())
	assert_true(state.blocking, "guard back up while still held")


func test_dodge_while_blocking_drops_the_guard() -> void:
	_step(BLOCK)
	_step(BLOCK | DODGE)
	assert_true(state.is_dodging())
	assert_false(state.blocking)


func test_guard_turns_toward_aim() -> void:
	_step(BLOCK, 1.0)
	assert_almost(state.yaw, TAU / 60.0, 0.001, "one tick of turning")


func test_blocking_slows_stamina_regen() -> void:
	state.stamina = 50.0
	_steps(4, BLOCK)
	assert_almost(state.stamina, 52.0)


func test_blocked_hit_costs_stamina_and_delays_regen() -> void:
	_step(BLOCK)
	var broke := _hit(20.0)
	assert_false(broke)
	assert_almost(state.stamina, 80.0)
	assert_true(state.blocking)
	assert_eq(state.server_events, 1)
	_steps(params.stamina_regen_delay_ticks, BLOCK)
	assert_almost(state.stamina, 80.0, 0.001, "no regen during the delay")


func test_hit_with_more_stamina_damage_than_left_breaks_guard() -> void:
	state.stamina = 10.0
	_step(BLOCK)
	assert_true(_hit(20.0))
	assert_almost(state.stamina, 0.0)
	assert_false(state.blocking)
	assert_eq(state.stagger_ticks, params.guard_break_stagger_ticks)


func test_guard_breaking_attack_breaks_even_with_stamina() -> void:
	_step(BLOCK)
	assert_true(_hit(40.0, true))
	assert_almost(state.stamina, 60.0)
	assert_true(state.is_staggered())


func test_guard_stays_down_until_guard_break_stagger_ends() -> void:
	_step(BLOCK)
	_hit(0.0, true)
	_steps(params.guard_break_stagger_ticks - 1, BLOCK)
	assert_false(state.blocking, "still staggered")
	_step(BLOCK)
	assert_true(state.blocking)


func test_in_front_respects_the_arc() -> void:
	var arc := deg_to_rad(120.0)
	# Facing -Z (yaw 0).
	assert_true(MeleeHitbox.is_in_front(Vector3.ZERO, 0.0, Vector3(0, 0, -2), arc), "straight ahead")
	assert_true(MeleeHitbox.is_in_front(Vector3.ZERO, 0.0, Vector3(1.5, 0, -1), arc), "56 degrees off")
	assert_false(MeleeHitbox.is_in_front(Vector3.ZERO, 0.0, Vector3(2, 0, 0), arc), "90 degrees off")
	assert_false(MeleeHitbox.is_in_front(Vector3.ZERO, 0.0, Vector3(0, 0, 2), arc), "behind")


func test_in_front_follows_facing() -> void:
	var facing_right := PlayerState.yaw_for_direction(Vector2.RIGHT)
	assert_true(MeleeHitbox.is_in_front(Vector3.ZERO, facing_right, Vector3(2, 0, 0), deg_to_rad(120.0)))


func test_network_round_trip_keeps_blocking() -> void:
	_step(BLOCK)
	var copy := PlayerState.from_array(state.to_array())
	assert_true(copy.matches(state))
	assert_true(copy.blocking)
