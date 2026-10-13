extends TestCase
## Animation canceling in PlayerState: a dodge or ability press in a light/heavy
## attack's windup cancels it, in its recovery skips the rest, and during its hit
## windows (or projectile release) stays buffered. Fixed params.

const ATTACK := PlayerState.BUTTON_ATTACK
const DODGE := PlayerState.BUTTON_DODGE
const Q := PlayerState.BUTTON_ABILITY_1
const Z := PlayerState.BUTTON_WING_1
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState
var weapon: WeaponParams
var strike: AbilityParams


func before_each() -> void:
	params = PlayerParams.new()
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.dodge_stamina_cost = 30.0
	params.dodge_ticks = 20
	params.dodge_buffer_ticks = 5
	params.ability_buffer_ticks = 4
	params.ember_cap = 100.0
	params.ember_resting = 50.0
	params.ember_settle_per_tick = 0.0
	weapon = params.default_weapon
	weapon.heavy_hold_ticks = 5
	weapon.attack_buffer_ticks = 4
	weapon.attack_turn_speed = TAU
	weapon.light_attack = _attack(AttackParams.new(), 3, 2, 4)   # live 3-4, recovery 5-8
	weapon.heavy_attack = _attack(AttackParams.new(), 6, 2, 5)   # live 6-7, recovery 8-12
	strike = _attack(AbilityParams.new(), 3, 2, 4) as AbilityParams
	strike.id = "strike"
	strike.cooldown_ticks = 30
	strike.turn_speed = TAU
	var strike_2 := _attack(AbilityParams.new(), 3, 2, 4) as AbilityParams
	strike_2.id = "strike_2"
	strike_2.cooldown_ticks = 30
	strike_2.turn_speed = TAU
	weapon.abilities = [strike, strike_2]
	var wings := WingParams.new()
	wings.id = "test"
	var gust := _attack(AbilityParams.new(), 2, 2, 3) as AbilityParams
	gust.id = "gust"
	gust.cooldown_ticks = 50
	gust.ember_cost = 20.0
	gust.turn_speed = TAU
	wings.abilities = [gust]
	params.wings = {"test": wings}

	state = PlayerState.new()
	state.stamina = params.max_stamina
	state.ember = 50.0
	state.set_loadout(PackedStringArray(), PackedInt32Array([0, 1, -1, -1, -1, -1]))
	state.set_wings("test", PackedInt32Array([0, -1]))


func _attack(a: AttackParams, windup: int, active: int, recovery: int) -> AttackParams:
	a.windup_ticks = windup
	a.active_ticks = active
	a.recovery_ticks = recovery
	return a


func _step(buttons: int = 0) -> void:
	state.step(Vector2.ZERO, buttons, 0.0, true, params, DELTA)


func _steps(count: int, buttons: int = 0) -> void:
	for i in count:
		_step(buttons)


## Press and release: the light starts on the release tick (attack_tick 0).
func _tap() -> void:
	_step(ATTACK)
	_step()


func test_dodge_in_windup_cancels_the_same_tick() -> void:
	_tap()
	_step()  # tick 1, windup
	assert_eq(state.attack_cancel_phase(params), PlayerState.CANCEL_WINDUP)
	_step(DODGE)  # tick 2
	assert_true(state.is_dodging(), "the dodge starts at once")
	assert_eq(state.dodge_tick, 0)
	assert_false(state.is_attacking(), "the light is gone")
	assert_almost(state.stamina, 70.0, 0.001, "the dodge costs as usual")
	var live := false
	for i in 25:
		live = live or state.is_attack_active(params)
		_step()
	assert_false(live, "no hit window ever went live")


func test_ability_in_windup_cancels_and_starts() -> void:
	_tap()
	var serial := state.attack_serial
	_step(Q)  # tick 1, windup
	assert_true(state.is_using_ability())
	assert_eq(state.ability, 0)
	assert_eq(state.attack_tick, 0, "starts the same tick")
	assert_eq(state.attack_serial, serial + 1, "a new attack, not the light")
	assert_eq(state.cooldown_left(0), strike.cooldown_ticks, "cooldown as usual")


func test_wing_ability_in_windup_cancels_and_starts() -> void:
	_steps(weapon.heavy_hold_ticks + 1, ATTACK)  # heavy starts
	assert_eq(state.attack_type, PlayerState.ATTACK_HEAVY)
	_step(ATTACK | Z)
	assert_true(state.is_using_wing())
	assert_almost(state.ember, 30.0, 0.001, "Ember cost as usual")


func test_ability_in_recovery_skips_it() -> void:
	_tap()
	_steps(5)  # tick 5: recovery
	assert_true(state.is_attack_recovering(params))
	assert_eq(state.attack_cancel_phase(params), PlayerState.CANCEL_RECOVERY)
	_step(Q)
	assert_true(state.is_using_ability())
	assert_eq(state.attack_tick, 0)


func test_presses_during_the_hit_window_stay_buffered() -> void:
	_tap()
	_steps(2)  # tick 2
	_step(Q)  # tick 3: live
	assert_eq(state.attack_type, PlayerState.ATTACK_LIGHT, "the hit isn't cut")
	assert_eq(state.attack_cancel_phase(params), PlayerState.CANCEL_NONE)
	_step()  # tick 4: live
	assert_eq(state.attack_type, PlayerState.ATTACK_LIGHT)
	assert_true(state.is_attack_active(params))
	_step()  # tick 5: recovery, the buffered press fires
	assert_true(state.is_using_ability())
	assert_eq(state.attack_tick, 0)


func test_dodge_in_the_hit_window_waits_for_recovery() -> void:
	_tap()
	_steps(3)  # tick 3: live
	_step(DODGE)  # tick 4: live
	assert_false(state.is_dodging())
	_step()  # tick 5: recovery
	assert_true(state.is_dodging())


func test_abilities_are_not_canceled_by_abilities() -> void:
	_step(Q)
	_step(PlayerState.BUTTON_ABILITY_2)  # strike's windup
	assert_eq(state.ability, 0, "the first ability keeps going")
	assert_eq(state.attack_cancel_phase(params), PlayerState.CANCEL_NONE)


func test_dodge_still_waits_through_an_ability_windup() -> void:
	_step(Q)
	_step(DODGE)
	assert_false(state.is_dodging())
	assert_true(state.is_using_ability())


func test_canceled_heavy_does_not_restart_while_held() -> void:
	_steps(weapon.heavy_hold_ticks + 1, ATTACK)
	assert_eq(state.attack_type, PlayerState.ATTACK_HEAVY)
	_step(ATTACK | DODGE)  # windup: canceled
	assert_true(state.is_dodging())
	_steps(params.dodge_ticks + 10, ATTACK)  # still held after the roll
	assert_false(state.is_attacking(), "no new heavy from the same hold")
	_step()
	assert_false(state.is_attacking(), "releasing it isn't a light either")


func test_rampage_carry_resets_on_cancel() -> void:
	_tap()
	state.attack_speed_carry = 0.5
	_step(DODGE)
	assert_almost(state.attack_speed_carry, 0.0)


func test_projectile_release_is_committed() -> void:
	var throw := weapon.light_attack
	throw.shape = AttackParams.SHAPE_NONE
	throw.projectile = "knife"
	throw.projectile_tick = 2
	throw.windup_ticks = 1  # no hitbox: only the release tick is committed
	throw.active_ticks = 1
	_tap()
	_step()  # tick 1: before the release
	assert_eq(state.attack_cancel_phase(params), PlayerState.CANCEL_WINDUP)
	_step()  # tick 2: the release
	assert_eq(state.attack_cancel_phase(params), PlayerState.CANCEL_NONE)
	_step()  # tick 3
	assert_eq(state.attack_cancel_phase(params), PlayerState.CANCEL_RECOVERY)


func test_windup_cancel_refunds_ammo_recovery_cancel_does_not() -> void:
	weapon.ammo = 6
	weapon.reload_ticks = 30
	weapon.refill_ticks = 40
	weapon.light_attack.ammo_cost = 1
	state.set_loadout(PackedStringArray(), PackedInt32Array([0, 1, -1, -1, -1, -1]))
	_tap()
	assert_eq(state.ammo_left(params), 5)
	_step(DODGE)  # windup: nothing thrown, the knife comes back
	assert_true(state.is_dodging())
	assert_eq(state.ammo_left(params), 6)
	_steps(params.dodge_ticks + 2)
	_tap()
	_steps(5)  # recovery: thrown
	_step(Q)
	assert_true(state.is_using_ability())
	assert_eq(state.ammo_left(params), 5, "a thrown knife stays thrown")


func test_canceled_state_round_trips() -> void:
	_tap()
	_step(DODGE)
	assert_true(PlayerState.from_array(state.to_array()).matches(state))
