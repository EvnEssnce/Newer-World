extends TestCase
## Magazines in PlayerState (Throwing Knives' ammo): light/heavy costs, an empty
## magazine holding presses back while it reloads, the refill after a pause,
## holstered timers, loadout changes, sync. Fixed params.

const ATTACK := PlayerState.BUTTON_ATTACK
const SWAP := PlayerState.BUTTON_SWAP
const DELTA := 1.0 / 60.0
const RELOAD := 30
const REFILL := 40

var params: PlayerParams
var state: PlayerState
var knives: WeaponParams
var talons: WeaponParams


func before_each() -> void:
	params = PlayerParams.new()
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.swap_ticks = 5
	params.swap_buffer_ticks = 3
	params.ability_buffer_ticks = 4
	knives = _weapon("knives", 6)
	talons = _weapon("talons", 0)
	params.weapons = {"knives": knives, "talons": talons}
	state = PlayerState.new()
	state.stamina = params.max_stamina
	state.set_loadout(PackedStringArray(["knives", "talons"]), PackedInt32Array([-1, -1, -1, -1, -1, -1]))


## A weapon with a magazine of `ammo` (0 = none): light costs 1, heavy 3.
func _weapon(id: String, ammo: int) -> WeaponParams:
	var w := WeaponParams.new()
	w.id = id
	w.heavy_hold_ticks = 5
	w.attack_buffer_ticks = 4
	w.attack_turn_speed = TAU
	w.ammo = ammo
	w.reload_ticks = RELOAD
	w.refill_ticks = REFILL
	w.light_attack = _attack(1)
	w.heavy_attack = _attack(3)
	return w


func _attack(cost: int) -> AttackParams:
	var a := AttackParams.new()
	a.windup_ticks = 1
	a.active_ticks = 1
	a.recovery_ticks = 1
	a.ammo_cost = cost
	return a


func _step(buttons: int = 0) -> void:
	state.step(Vector2.ZERO, buttons, 0.0, true, params, DELTA)


func _steps(count: int, buttons: int = 0) -> void:
	for i in count:
		_step(buttons)


## Tap: press, then release (the light starts on the release), then let it end.
func _light() -> void:
	_step(ATTACK)
	_step()
	_steps(4)


func _heavy() -> void:
	_steps(knives.heavy_hold_ticks + 1, ATTACK)
	_steps(4)


func test_starts_full() -> void:
	assert_eq(state.ammo_left(params), 6)
	assert_eq(state.ammo_left(params, 1), 0, "no magazine: nothing to count")


func test_light_takes_one_and_starts_the_refill() -> void:
	_step(ATTACK)
	_step()
	assert_true(state.is_attacking())
	assert_eq(state.ammo_left(params), 5)
	assert_eq(state.ammo_timer[0], REFILL)


func test_heavy_takes_three() -> void:
	_heavy()
	assert_eq(state.ammo_left(params), 3)


func test_empty_magazine_holds_the_press_and_reloads() -> void:
	for i in 6:
		_light()
	assert_eq(state.ammo_left(params), 0)
	assert_eq(state.ammo_timer[0], RELOAD - 4 * 1, "the last throw started the reload")
	_step(ATTACK)
	_step()
	assert_false(state.is_attacking(), "no knives: it can't start")
	assert_eq(state.queued_attack, PlayerState.ATTACK_LIGHT, "the press stays buffered")
	_steps(RELOAD)
	assert_eq(state.ammo_left(params), 6, "reloaded")
	_light()
	assert_eq(state.ammo_left(params), 5)


func test_press_buffered_through_the_end_of_the_reload_fires() -> void:
	knives.reload_ticks = 3
	for i in 5:
		_light()
	_step(ATTACK)
	_step()  # the last knife: a 3-tick reload starts
	assert_eq(state.ammo_left(params), 0)
	var serial := state.attack_serial
	_step(ATTACK)
	_step()  # pressed mid-throw with none left: buffered
	_step()
	assert_eq(state.attack_serial, serial + 1, "fires as the reload finishes, within the buffer")
	assert_eq(state.ammo_left(params), 5)


func test_refills_after_a_pause() -> void:
	_light()
	_light()
	assert_eq(state.ammo_left(params), 4)
	_steps(REFILL)
	assert_eq(state.ammo_left(params), 6)
	assert_eq(state.ammo_timer[0], 0)


func test_each_throw_restarts_the_refill() -> void:
	_light()
	_steps(REFILL - 10)
	_light()
	_steps(REFILL - 10)
	assert_eq(state.ammo_left(params), 4, "not yet: the second throw restarted it")
	_steps(10)
	assert_eq(state.ammo_left(params), 6)


func test_unaffordable_heavy_waits_and_shortens_the_refill_to_the_reload() -> void:
	knives.refill_ticks = 100
	for i in 4:
		_light()
	assert_eq(state.ammo_left(params), 2)
	_steps(knives.heavy_hold_ticks + 1, ATTACK)
	assert_false(state.is_attacking(), "a heavy needs 3")
	assert_eq(state.ammo_timer[0], RELOAD, "the refill (90 ticks left) became the reload")
	_steps(RELOAD)
	assert_eq(state.ammo_left(params), 6)


func test_holstered_magazine_keeps_its_count_and_refills() -> void:
	_light()
	_step(SWAP)
	_steps(params.swap_ticks)
	assert_eq(state.equipped, 1)
	assert_eq(state.ammo_left(params, 0), 5, "kept while holstered")
	_light()  # talons: no magazine, no cost
	assert_eq(state.ammo_left(params, 0), 5)
	_steps(REFILL)
	assert_eq(state.ammo_left(params, 0), 6, "the refill ran while holstered")


func test_loadout_change_moves_the_magazine_with_its_weapon() -> void:
	_light()
	state.set_loadout(PackedStringArray(["talons", "knives"]), PackedInt32Array([-1, -1, -1, -1, -1, -1]))
	assert_eq(state.ammo_spent, PackedInt32Array([0, 1]))
	assert_eq(state.ammo_timer[1], REFILL - 4)
	state.set_loadout(PackedStringArray(["talons", "spare"]), PackedInt32Array([-1, -1, -1, -1, -1, -1]))
	assert_eq(state.ammo_spent, PackedInt32Array([0, 0]), "a new weapon starts full")


func test_respawn_and_class_change_fill_it() -> void:
	_light()
	state.kill()
	state.revive(params)
	assert_eq(state.ammo_left(params), 6)
	_light()
	state.reset_for_class_change(params)
	assert_eq(state.ammo_left(params), 6)


func test_synced_and_compared_but_not_shown_to_others() -> void:
	_light()
	var data := state.to_array()
	assert_eq(data[36], PackedInt32Array([1, 0, REFILL - 4, 0]))
	var copy := PlayerState.from_array(data)
	assert_true(copy.matches(state))
	copy.ammo_spent[0] = 2
	assert_false(copy.matches(state), "ammo is compared")
	assert_eq(state.view_array()[36], PackedInt32Array([0, 0, 0, 0]), "owner only")
