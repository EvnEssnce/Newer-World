extends TestCase
## Hyper armor (AttackParams armor_start / armor_end: Greataxe and War Hammer
## heavies and big abilities): the window from the attack timeline, and
## PlayerState refusing hit staggers and forced movement inside it while stuns
## and roots still land. Fixed params, not the weapon files.

const ATTACK := PlayerState.BUTTON_ATTACK
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState
var defs: StatusDefs
var stun: int
var root: int


func before_each() -> void:
	defs = StatusDefs.new()
	stun = defs.add(_def("stun"))
	defs.get_def(stun).stuns = true
	root = defs.add(_def("root"))
	defs.get_def(root).stops_movement = true
	params = PlayerParams.new()
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.guard_break_stagger_ticks = 30
	params.statuses = defs
	params.default_weapon.heavy_hold_ticks = 5
	params.default_weapon.attack_buffer_ticks = 4
	params.default_weapon.attack_turn_speed = TAU
	params.default_weapon.light_attack = _attack(3, 2, 4)
	# Heavy: windup 10, one 4-tick hit window, recovery 8; armor ticks [0, 14).
	var heavy := _attack(10, 4, 8)
	heavy.set_hyper_armor(0.0, -1.0, 60.0)
	params.default_weapon.heavy_attack = heavy
	state = PlayerState.new()
	state.stamina = params.max_stamina


func _def(id: String) -> StatusDef:
	var d := StatusDef.new()
	d.id = id
	d.display_name = id.capitalize()
	d.category = StatusDef.CATEGORY_DEBUFF
	d.duration_ticks = 120
	return d


func _attack(windup: int, active: int, recovery: int) -> AttackParams:
	var a := AttackParams.new()
	a.windup_ticks = windup
	a.active_ticks = active
	a.recovery_ticks = recovery
	return a


## Puts the state mid-heavy at `tick`.
func _heavy_at(tick: int) -> void:
	state.attack_type = PlayerState.ATTACK_HEAVY
	state.attack_tick = tick


func test_no_armor_by_default() -> void:
	var a := _attack(10, 4, 8)
	for tick in [0, 5, 12, 20]:
		assert_false(a.has_hyper_armor(tick))


func test_armor_end_minus_one_runs_through_the_last_hit_window() -> void:
	var a := _attack(10, 4, 8)
	a.windows = 3
	a.window_interval_ticks = 6
	a.set_hyper_armor(0.0, -1.0, 60.0)
	assert_eq(a.armor_end_tick, a.recovery_start_tick())
	assert_true(a.has_hyper_armor(0))
	assert_true(a.has_hyper_armor(a.recovery_start_tick() - 1), "last hit window tick")
	assert_false(a.has_hyper_armor(a.recovery_start_tick()), "recovery")


func test_armor_seconds_round_to_ticks() -> void:
	var a := _attack(30, 6, 30)
	a.set_hyper_armor(0.1, 0.4, 60.0)
	assert_eq(a.armor_start_tick, 6)
	assert_eq(a.armor_end_tick, 24)
	assert_false(a.has_hyper_armor(5))
	assert_true(a.has_hyper_armor(6))
	assert_true(a.has_hyper_armor(23))
	assert_false(a.has_hyper_armor(24))


func test_state_armor_follows_the_attack_timeline() -> void:
	assert_false(state.has_hyper_armor(params), "not attacking")
	_heavy_at(0)
	assert_true(state.has_hyper_armor(params), "windup")
	_heavy_at(12)
	assert_true(state.has_hyper_armor(params), "hit window")
	_heavy_at(14)
	assert_false(state.has_hyper_armor(params), "recovery")
	state.attack_type = PlayerState.ATTACK_LIGHT
	state.attack_tick = 1
	assert_false(state.has_hyper_armor(params), "the light has none")


func test_a_held_heavy_gets_armor_through_the_sim() -> void:
	for i in params.default_weapon.heavy_hold_ticks + 1:
		state.step(Vector2.ZERO, ATTACK, 0.0, true, params, DELTA)
	assert_eq(state.attack_type, PlayerState.ATTACK_HEAVY)
	assert_true(state.has_hyper_armor(params))


func test_stagger_refused_inside_armor() -> void:
	_heavy_at(5)
	var events := state.server_events
	state.apply_stagger(30, params)
	assert_true(state.is_attacking(), "the heavy goes on")
	assert_false(state.is_staggered())
	assert_eq(state.server_events, events, "a refusal changes nothing to predict")


func test_stagger_lands_outside_armor() -> void:
	_heavy_at(15)
	state.apply_stagger(30, params)
	assert_false(state.is_attacking(), "recovery is interrupted")
	assert_true(state.is_staggered())


func test_stagger_through_armor_lands() -> void:
	_heavy_at(5)
	state.apply_stagger(30, params, true)
	assert_false(state.is_attacking())
	assert_true(state.is_staggered(), "Brace's counter")


func test_force_refused_inside_armor_and_lands_outside() -> void:
	_heavy_at(5)
	assert_true(state.is_force_immune(params))
	assert_false(state.start_force(params, Vector2(2.0, 0.0), 10, 0.0, DELTA))
	assert_false(state.is_forced())
	assert_true(state.is_attacking())
	_heavy_at(16)
	assert_false(state.is_force_immune(params))
	assert_true(state.start_force(params, Vector2(2.0, 0.0), 10, 0.0, DELTA))
	assert_true(state.is_forced())


func test_stun_and_root_still_land_inside_armor() -> void:
	_heavy_at(5)
	assert_true(state.apply_status(params, root), "rooted")
	assert_true(state.is_attacking(), "a root doesn't interrupt")
	assert_true(state.apply_status(params, stun), "stunned")
	assert_false(state.is_attacking(), "the stun interrupts the heavy")
	assert_true(state.is_staggered())


func test_no_armor_while_dead() -> void:
	_heavy_at(5)
	state.dead = true
	assert_false(state.has_hyper_armor(params))
