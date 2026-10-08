extends TestCase
## Light/heavy attack rules in PlayerState. Fixed params, not the weapon file.

const ATTACK := PlayerState.BUTTON_ATTACK
const DODGE := PlayerState.BUTTON_DODGE
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState


func before_each() -> void:
	params = PlayerParams.new()
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.dodge_stamina_cost = 30.0
	params.dodge_ticks = 20
	params.dodge_buffer_ticks = 5
	params.default_weapon.heavy_hold_ticks = 5
	params.default_weapon.attack_buffer_ticks = 4
	params.default_weapon.attack_turn_speed = TAU  # one full turn per second = TAU / 60 per tick
	params.default_weapon.light_attack = _attack(3, 2, 4)
	params.default_weapon.heavy_attack = _attack(6, 2, 5)
	state = PlayerState.new()
	state.stamina = params.max_stamina


func _attack(windup: int, active: int, recovery: int) -> AttackParams:
	var a := AttackParams.new()
	a.windup_ticks = windup
	a.active_ticks = active
	a.recovery_ticks = recovery
	return a


func _step(buttons: int = 0, aim_yaw: float = 0.0, move: Vector2 = Vector2.ZERO) -> void:
	state.step(move, buttons, aim_yaw, true, params, DELTA)


func _steps(count: int, buttons: int = 0, aim_yaw: float = 0.0) -> void:
	for i in count:
		_step(buttons, aim_yaw)


## Press and release: the light attack starts on the release tick.
func _tap(aim_yaw: float = 0.0) -> void:
	_step(ATTACK, aim_yaw)
	_step(0, aim_yaw)


func test_tap_starts_light_attack_on_release() -> void:
	_step(ATTACK)
	assert_false(state.is_attacking(), "still held")
	_step()
	assert_eq(state.attack_type, PlayerState.ATTACK_LIGHT)
	assert_eq(state.attack_tick, 0)


func test_hold_starts_heavy_attack_without_release() -> void:
	_steps(params.default_weapon.heavy_hold_ticks, ATTACK)
	assert_false(state.is_attacking(), "not held long enough yet")
	_step(ATTACK)
	assert_eq(state.attack_type, PlayerState.ATTACK_HEAVY)


func test_holding_on_gives_one_heavy_and_release_gives_nothing() -> void:
	_steps(params.default_weapon.heavy_hold_ticks + 1 + params.default_weapon.heavy_attack.total_ticks() + 10, ATTACK)
	assert_false(state.is_attacking(), "heavy ended, no repeat while held")
	_step()
	assert_false(state.is_attacking(), "releasing after a heavy is not a light")


func test_attack_starts_facing_aim() -> void:
	_tap(1.0)
	assert_almost(state.yaw, 1.0)


func test_attack_turns_toward_aim_during_the_swing() -> void:
	_steps(params.default_weapon.heavy_hold_ticks + 1, ATTACK, 0.0)  # heavy: 13 ticks, time to turn 1 rad
	_step(ATTACK, 1.0)
	assert_almost(state.yaw, TAU / 60.0, 0.001, "one tick of turning")
	_steps(10, ATTACK, 1.0)
	assert_true(state.is_attacking())
	assert_almost(state.yaw, 1.0, 0.001, "caught up with the aim")


func test_attack_stops_turning_when_it_ends() -> void:
	_tap(0.0)
	_steps(params.default_weapon.light_attack.total_ticks(), 0, 1.0)
	assert_false(state.is_attacking())
	var yaw_at_end := state.yaw
	_step(0, 2.0)
	assert_almost(state.yaw, yaw_at_end, 0.001, "aim alone doesn't turn you")


func test_movement_does_not_turn_during_attack() -> void:
	_tap(0.0)
	_step(0, 0.0, Vector2.RIGHT)
	assert_almost(state.yaw, 0.0)


func test_hitbox_only_live_in_active_window() -> void:
	_tap()
	var active_ticks := []
	for i in params.default_weapon.light_attack.total_ticks():
		if state.is_attack_active(params):
			active_ticks.append(state.attack_tick)
		_step()
	assert_eq(active_ticks, [3, 4])


func test_attack_lasts_its_total_ticks() -> void:
	_tap()
	_steps(params.default_weapon.light_attack.total_ticks() - 1)
	assert_true(state.is_attacking(), "last tick")
	_step()
	assert_false(state.is_attacking(), "over")


func test_press_during_attack_queues_the_next_one() -> void:
	_tap()
	_steps(5)
	_tap()  # released at tick 7 of 9
	_steps(2)
	assert_eq(state.attack_tick, 0, "next light starts as soon as the first ends")
	assert_eq(state.attack_type, PlayerState.ATTACK_LIGHT)


func test_queued_attack_expires() -> void:
	_tap()
	_tap()  # queued at tick 2, buffer runs out before tick 9
	_steps(params.default_weapon.light_attack.total_ticks())
	assert_false(state.is_attacking())


func test_attack_pressed_late_in_a_roll_starts_after_it() -> void:
	_step(DODGE)
	_steps(params.dodge_ticks - 3)
	_tap()
	assert_false(state.is_attacking(), "can't attack mid-roll")
	_step()
	assert_true(state.is_attacking(), "starts the tick the roll ends")


func test_dodge_cancels_recovery() -> void:
	_tap()
	_steps(params.default_weapon.light_attack.windup_ticks + params.default_weapon.light_attack.active_ticks)
	assert_true(state.is_attack_recovering(params))
	_step(DODGE)
	assert_true(state.is_dodging())
	assert_false(state.is_attacking())


func test_dodge_cooldown_after_a_roll_buffers_the_next_dodge() -> void:
	params.dodge_cooldown_ticks = 3
	_step(DODGE)
	assert_true(state.is_dodging())
	_steps(params.dodge_ticks)
	assert_false(state.is_dodging(), "roll over")
	_step(DODGE)  # cooldown 3 -> 2
	assert_false(state.is_dodging(), "still cooling down")
	_step()  # 1
	assert_false(state.is_dodging())
	_step()  # 0: the buffered press fires
	assert_true(state.is_dodging())
	var restored := PlayerState.from_array(state.to_array())
	assert_true(restored.matches(state))


func test_dodge_waits_through_windup_and_active() -> void:
	_tap()
	_step(DODGE)  # tick 1, windup
	assert_false(state.is_dodging(), "windup")
	_steps(3)  # tick 4, active
	assert_false(state.is_dodging(), "active")
	_step()  # tick 5, recovery: the buffered dodge fires
	assert_true(state.is_dodging())


func test_network_round_trip_keeps_attack_state() -> void:
	_tap()
	_step(ATTACK)
	_steps(2, ATTACK)
	var copy := PlayerState.from_array(state.to_array())
	assert_true(copy.matches(state))
	assert_eq(copy.attack_type, state.attack_type)
	assert_eq(copy.attack_tick, state.attack_tick)
	assert_eq(copy.attack_hold, state.attack_hold)
