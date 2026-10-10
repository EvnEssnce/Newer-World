extends TestCase
## Second charges (Second Wind: rolls; Second Step: a Wing ability): a spare
## lets the thing be used again while its cooldown runs, and comes back when the
## cooldown is over. Built on the real tuning (data/), like the sim tests.

const DT := 1.0 / 60.0

var p: PlayerParams
var state: PlayerState


func before_each() -> void:
	p = PlayerParams.current()
	state = PlayerState.new()
	state.stamina = p.max_stamina
	state.on_floor = true


func _step(buttons := 0, move := Vector2.ZERO) -> void:
	state.step(move, buttons, 0.0, true, p, DT)


func _finish_roll() -> void:
	for i in p.dodge_ticks + 1:
		_step()


func test_a_second_roll_while_the_cooldown_runs() -> void:
	state.set_charge_mask(1)
	_step()  # the spare fills (no cooldown yet)
	assert_true(state.has_spare_charge(0))
	_step(PlayerState.BUTTON_DODGE)
	assert_true(state.is_dodging(), "first roll")
	_finish_roll()
	assert_true(state.dodge_cooldown > 0, "cooling down")
	_step(PlayerState.BUTTON_DODGE)
	assert_true(state.is_dodging(), "second roll on the spare")
	assert_false(state.has_spare_charge(0))
	_finish_roll()
	_step(PlayerState.BUTTON_DODGE)
	assert_false(state.is_dodging(), "no third roll during the cooldown")


func test_no_spare_without_the_capstone() -> void:
	_step()
	assert_false(state.has_spare_charge(0))
	_step(PlayerState.BUTTON_DODGE)
	_finish_roll()
	_step(PlayerState.BUTTON_DODGE)
	assert_false(state.is_dodging(), "the cooldown holds")


func test_the_spare_comes_back_after_the_cooldown() -> void:
	state.set_charge_mask(1)
	state.spare_charges = 0
	state.dodge_cooldown = 3
	_step()
	assert_false(state.has_spare_charge(0))
	for i in 3:
		_step()
	assert_true(state.has_spare_charge(0))


func test_charge_mask_is_a_server_event_and_drops_spares() -> void:
	var events := state.server_events
	state.set_charge_mask(1 | 4)
	assert_eq(state.server_events, events + 1)
	state.spare_charges = 1 | 4
	state.set_charge_mask(4)
	assert_eq(state.spare_charges, 4, "the roll spare went with its charge")


func test_charges_survive_the_snapshot_round_trip() -> void:
	state.charge_mask = 5
	state.spare_charges = 4
	var copy := PlayerState.from_array(state.to_array())
	assert_eq(copy.charge_mask, 5)
	assert_eq(copy.spare_charges, 4)
	assert_true(copy.matches(state))
