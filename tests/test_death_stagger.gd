extends TestCase
## Server-applied stagger, death and respawn rules in PlayerState.

const ATTACK := PlayerState.BUTTON_ATTACK
const DODGE := PlayerState.BUTTON_DODGE
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState


func before_each() -> void:
	params = PlayerParams.new()
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.stamina_regen_per_tick = 1.0
	params.dodge_stamina_cost = 30.0
	params.dodge_ticks = 20
	params.dodge_buffer_ticks = 5
	params.attack_buffer_ticks = 4
	params.attack_turn_speed = TAU
	var light := AttackParams.new()
	light.windup_ticks = 3
	light.active_ticks = 2
	light.recovery_ticks = 4
	params.light_attack = light
	params.heavy_attack = light
	params.heavy_hold_ticks = 5
	state = PlayerState.new()
	state.stamina = params.max_stamina


func _step(buttons: int = 0) -> void:
	state.step(Vector2.RIGHT, buttons, 0.0, true, params, DELTA)


func _steps(count: int, buttons: int = 0) -> void:
	for i in count:
		_step(buttons)


## Press and release: a light attack starts on the release tick.
func _tap() -> void:
	_step(ATTACK)
	_step()


func test_stagger_interrupts_an_attack() -> void:
	_tap()
	state.apply_stagger(5)
	assert_false(state.is_attacking())
	assert_true(state.is_staggered())
	assert_eq(state.server_events, 1)


func test_stagger_interrupts_a_dodge() -> void:
	_step(DODGE)
	state.apply_stagger(5)
	assert_false(state.is_dodging())


func test_cannot_attack_or_dodge_while_staggered() -> void:
	state.apply_stagger(10)
	_tap()
	_step(DODGE)
	assert_false(state.is_attacking())
	assert_false(state.is_dodging())


func test_stagger_lasts_its_ticks() -> void:
	state.apply_stagger(3)
	_steps(2)
	assert_true(state.is_staggered())
	_step()
	assert_false(state.is_staggered())


func test_press_during_stagger_fires_when_it_ends() -> void:
	state.apply_stagger(3)
	_step(ATTACK)
	_step()
	assert_false(state.is_attacking(), "still staggered")
	_step()
	assert_true(state.is_attacking(), "buffered attack fires as the stagger ends")


func test_zero_stagger_does_nothing() -> void:
	_tap()
	state.apply_stagger(0)
	assert_true(state.is_attacking())
	assert_eq(state.server_events, 0)


func test_dead_player_cannot_act_or_regen() -> void:
	state.stamina = 50.0
	state.kill()
	_steps(10, ATTACK | DODGE)
	assert_false(state.is_attacking())
	assert_false(state.is_dodging())
	assert_almost(state.stamina, 50.0)


func test_death_cancels_attack_and_stagger() -> void:
	_tap()
	state.apply_stagger(5)
	state.kill()
	assert_false(state.is_attacking())
	assert_false(state.is_staggered())
	assert_true(state.dead)


func test_dead_players_are_not_staggered() -> void:
	state.kill()
	state.apply_stagger(5)
	assert_false(state.is_staggered())
	assert_eq(state.server_events, 1, "only the death")


func test_revive_restores_stamina_and_control() -> void:
	state.stamina = 10.0
	state.kill()
	state.revive(params)
	assert_true(state.can_act())
	assert_almost(state.stamina, 100.0)
	assert_eq(state.server_events, 2)
	_tap()
	assert_true(state.is_attacking())


func test_network_round_trip_keeps_death_and_stagger() -> void:
	state.apply_stagger(4)
	var copy := PlayerState.from_array(state.to_array())
	assert_true(copy.matches(state))
	assert_eq(copy.stagger_ticks, 4)
	state.kill()
	copy = PlayerState.from_array(state.to_array())
	assert_true(copy.dead)
	assert_eq(copy.server_events, 2)
