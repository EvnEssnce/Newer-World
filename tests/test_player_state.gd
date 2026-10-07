extends TestCase
## Stamina and dodge rules. Uses fixed params, not data/combat.cfg, so tuning
## edits don't break tests.

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
	params.dodge_speed = 8.0
	params.iframe_start_tick = 2
	params.iframe_end_tick = 12
	params.dodge_buffer_ticks = 5
	params.max_air_dodges = 1
	state = PlayerState.new()
	state.stamina = params.max_stamina


func _step(buttons: int = 0, move: Vector2 = Vector2.RIGHT, on_floor: bool = true) -> void:
	state.step(move, buttons, on_floor, params, DELTA)


func _steps(count: int, buttons: int = 0, move: Vector2 = Vector2.RIGHT, on_floor: bool = true) -> void:
	for i in count:
		_step(buttons, move, on_floor)


func test_dodge_costs_stamina() -> void:
	_step(DODGE)
	assert_true(state.is_dodging())
	assert_almost(state.stamina, 70.0)


func test_cannot_dodge_without_enough_stamina() -> void:
	state.stamina = 29.0
	state.stamina_regen_wait = 100
	_step(DODGE)
	_steps(10)
	assert_false(state.is_dodging())
	assert_almost(state.stamina, 29.0)


func test_can_dodge_in_the_air() -> void:
	_step(DODGE, Vector2.RIGHT, false)
	assert_true(state.is_dodging())
	assert_almost(state.stamina, 70.0)


func test_air_dodges_limited_per_jump() -> void:
	_step(DODGE, Vector2.RIGHT, false)
	_steps(params.dodge_ticks, 0, Vector2.RIGHT, false)
	_step(DODGE, Vector2.RIGHT, false)
	assert_false(state.is_dodging(), "second air dodge")
	assert_almost(state.stamina, 70.0)


func test_landing_resets_air_dodges() -> void:
	_step(DODGE, Vector2.RIGHT, false)
	_steps(params.dodge_ticks, 0, Vector2.RIGHT, false)
	_step()  # land
	_step(DODGE, Vector2.RIGHT, false)  # jumped again
	assert_true(state.is_dodging())


func test_zero_air_dodges_means_ground_only() -> void:
	params.max_air_dodges = 0
	_step(DODGE, Vector2.RIGHT, false)
	assert_false(state.is_dodging())
	assert_almost(state.stamina, 100.0)


func test_dodge_lasts_its_duration() -> void:
	_step(DODGE)
	_steps(params.dodge_ticks - 1)
	assert_true(state.is_dodging(), "last tick of the roll")
	_step()
	assert_false(state.is_dodging(), "roll over")


func test_iframes_only_inside_window() -> void:
	_step(DODGE)
	var invulnerable_ticks := []
	for i in params.dodge_ticks:
		if state.is_invulnerable(params):
			invulnerable_ticks.append(state.dodge_tick)
		_step()
	assert_eq(invulnerable_ticks, range(params.iframe_start_tick, params.iframe_end_tick))
	assert_false(state.is_invulnerable(params), "after the roll")


func test_cannot_dodge_again_mid_roll() -> void:
	_step(DODGE)
	_step(DODGE)
	assert_eq(state.dodge_tick, 1)
	assert_almost(state.stamina, 70.0)


func test_buffered_press_dodges_as_soon_as_roll_ends() -> void:
	_step(DODGE)
	_steps(params.dodge_ticks - 3)
	_step(DODGE)  # 2 ticks before the roll ends, within the 5-tick buffer
	_step()
	_step()
	assert_eq(state.dodge_tick, 0, "second roll starts the tick the first one ends")
	assert_almost(state.stamina, 40.0)


func test_buffered_press_fires_on_landing() -> void:
	state.air_dodges_used = 1  # air dodge already spent, so it has to wait
	_step(DODGE, Vector2.RIGHT, false)
	_steps(4, 0, Vector2.RIGHT, false)
	_step()
	assert_true(state.is_dodging())


func test_buffered_press_expires() -> void:
	state.air_dodges_used = 1
	_step(DODGE, Vector2.RIGHT, false)
	_steps(5, 0, Vector2.RIGHT, false)
	_step()
	assert_false(state.is_dodging())


func test_stamina_waits_after_roll_before_regen() -> void:
	_step(DODGE)
	_steps(params.dodge_ticks)  # the roll ends on the last of these
	_steps(params.stamina_regen_delay_ticks - 1)
	assert_almost(state.stamina, 70.0, 0.001, "still waiting")
	_step()
	assert_almost(state.stamina, 71.0, 0.001, "regen started")


func test_stamina_regen_caps_at_max() -> void:
	state.stamina = 99.5
	_steps(3)
	assert_almost(state.stamina, 100.0)


func test_dodge_goes_in_move_direction_and_faces_it() -> void:
	_step(DODGE, Vector2.RIGHT)
	assert_eq(state.dodge_dir, Vector2.RIGHT)
	assert_almost(state.yaw, PlayerState.yaw_for_direction(Vector2.RIGHT))


func test_no_input_rolls_forward() -> void:
	state.yaw = 0.0  # facing -Z
	_step(DODGE, Vector2.ZERO)
	assert_true(state.dodge_dir.is_equal_approx(Vector2(0.0, -1.0)), "moves toward -Z")
	assert_almost(state.yaw, 0.0)


func test_no_input_rolls_whichever_way_you_face() -> void:
	state.yaw = PlayerState.yaw_for_direction(Vector2(1.0, 1.0).normalized())
	_step(DODGE, Vector2.ZERO)
	assert_true(state.dodge_dir.is_equal_approx(Vector2(1.0, 1.0).normalized()))


func test_network_round_trip_keeps_state() -> void:
	_step(DODGE)
	_steps(3)
	var copy := PlayerState.from_array(state.to_array())
	assert_true(copy.matches(state))
	assert_eq(copy.dodge_dir, state.dodge_dir)
	assert_almost(copy.yaw, state.yaw)
