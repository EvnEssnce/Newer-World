extends TestCase
## Session 42 sim rules in PlayerState / PlayerMovement: dodging out of
## channeled abilities, root holding back teleports, Shadow Swap needing its
## decoy (a synced flag), and the speed left after an air dodge. Fixed params.

const DODGE := PlayerState.BUTTON_DODGE
const Q := PlayerState.BUTTON_ABILITY_1
const E := PlayerState.BUTTON_ABILITY_2
const R := PlayerState.BUTTON_ABILITY_3
const Z := PlayerState.BUTTON_WING_1
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState
var weapon: WeaponParams
var channel: AbilityParams
var strike: AbilityParams
var blink: AbilityParams
var swap: AbilityParams
var root: int
var hover: int


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
	var defs := StatusDefs.new()
	root = defs.add(_def("root"))
	defs.get_def(root).stops_movement = true
	hover = defs.add(_def("updraft"))
	defs.get_def(hover).max_fall_speed = 0.4
	params.statuses = defs
	weapon = params.default_weapon
	weapon.heavy_hold_ticks = 5
	weapon.attack_buffer_ticks = 4
	weapon.attack_turn_speed = TAU
	weapon.light_attack = _attack(AttackParams.new(), 3, 2, 4)
	weapon.heavy_attack = _attack(AttackParams.new(), 6, 2, 5)
	# A channel: windup 3, 4 windows of 2 ticks every 3 ticks (live 3-4, 6-7,
	# 9-10, 12-13), recovery 14-17.
	channel = _ability("channel", 3, 2, 4)
	channel.windows = 4
	channel.window_interval_ticks = 3
	channel.channel_dodge = true
	strike = _ability("strike", 3, 2, 4)
	blink = _ability("blink", 2, 1, 4)
	blink.teleport_distance = 7.0
	blink.teleport_tick = 2
	weapon.abilities = [channel, strike, blink]
	var wings := WingParams.new()
	wings.id = "test"
	swap = _ability("shadow_swap", 1, 1, 3)
	swap.ember_cost = 15.0
	swap.needs_decoy = true
	wings.abilities = [swap]
	params.wings = {"test": wings}

	state = PlayerState.new()
	state.stamina = params.max_stamina
	state.ember = 50.0
	state.set_loadout(PackedStringArray(), PackedInt32Array([0, 1, 2, -1, -1, -1]))
	state.set_wings("test", PackedInt32Array([0, -1]))


func _def(id: String) -> StatusDef:
	var d := StatusDef.new()
	d.id = id
	d.display_name = id.capitalize()
	d.category = StatusDef.CATEGORY_DEBUFF
	d.duration_ticks = 120
	return d


func _attack(a: AttackParams, windup: int, active: int, recovery: int) -> AttackParams:
	a.windup_ticks = windup
	a.active_ticks = active
	a.recovery_ticks = recovery
	return a


func _ability(id: String, windup: int, active: int, recovery: int) -> AbilityParams:
	var a := _attack(AbilityParams.new(), windup, active, recovery) as AbilityParams
	a.id = id
	a.cooldown_ticks = 60
	a.turn_speed = TAU
	return a


func _step(buttons: int = 0) -> void:
	state.step(Vector2.ZERO, buttons, 0.0, true, params, DELTA)


func _steps(count: int, buttons: int = 0) -> void:
	for i in count:
		_step(buttons)


# --- Dodging out of channels ---

func test_dodge_ends_a_channel_once_its_windows_started() -> void:
	_step(Q)  # tick 0
	_steps(4)  # tick 4: the first window's second tick
	assert_true(state.is_attack_active(params))
	_step(DODGE)  # tick 5: between windows
	assert_true(state.is_dodging(), "the dodge starts at once")
	assert_false(state.is_attacking(), "the windows left are lost")
	assert_eq(state.cooldown_left(0), 60 - 5, "the cooldown keeps running")


func test_dodge_waits_through_a_channel_windup() -> void:
	_step(Q)
	_step(DODGE)  # tick 1: windup
	assert_false(state.is_dodging())
	_steps(2)  # tick 3: the first window's first tick still happens
	assert_true(state.is_attack_active(params))
	assert_false(state.is_dodging())
	_step()  # tick 4: buffered press fires
	assert_true(state.is_dodging())
	assert_false(state.is_attacking())


func test_plain_ability_still_waits_for_recovery() -> void:
	_step(E)  # strike: one window, live 3-4, recovery 5-8
	_steps(3)  # tick 3: live
	_step(DODGE)  # tick 4: live
	assert_false(state.is_dodging())
	_step()  # tick 5: recovery
	assert_true(state.is_dodging())


func test_channel_dodge_off_waits_for_recovery() -> void:
	channel.channel_dodge = false
	_step(Q)
	_steps(5)  # tick 5
	_step(DODGE)
	assert_false(state.is_dodging())
	assert_true(state.is_using_ability())


func test_abilities_still_dont_cancel_a_channel() -> void:
	_step(Q)
	_steps(5)
	_step(E)
	assert_eq(state.ability, 0, "the channel keeps going")


# --- Root and teleports ---

func test_root_holds_a_teleport_back_without_spending() -> void:
	state.statuses.apply(params.statuses, root)
	_step(R)
	assert_false(state.is_attacking(), "a rooted Blink doesn't start")
	assert_eq(state.cooldown_left(2), 0, "no cooldown")
	assert_eq(state.queued_attack, PlayerState.ATTACK_ABILITY, "the press stays buffered")
	state.statuses.remove(root)
	_step()
	assert_true(state.is_using_ability(), "starts once free, within the buffer")
	assert_eq(state.ability, 2)


func test_root_press_expires_after_the_buffer() -> void:
	state.statuses.apply(params.statuses, root)
	_step(R)
	_steps(params.ability_buffer_ticks + 1)
	assert_eq(state.queued_attack, PlayerState.ATTACK_NONE)
	state.statuses.remove(root)
	_step()
	assert_false(state.is_attacking())


func test_root_doesnt_hold_back_other_abilities() -> void:
	state.statuses.apply(params.statuses, root)
	_step(E)
	assert_true(state.is_using_ability())


# --- Shadow Swap and the decoy flag ---

func test_needs_decoy_holds_the_press_without_spending() -> void:
	_step(Z)
	assert_false(state.is_attacking(), "no decoy out: it can't start")
	assert_almost(state.ember, 50.0, 0.001, "no Ember spent")
	assert_eq(state.wing_cooldown_left(0), 0, "no cooldown")
	var events := state.server_events
	state.set_decoy_active(true)
	assert_eq(state.server_events, events + 1, "a server event")
	_step()
	assert_true(state.is_using_wing(), "the buffered press starts once it's out")
	assert_almost(state.ember, 35.0, 0.001)


func test_decoy_flag_is_synced_compared_and_owner_only() -> void:
	state.set_decoy_active(true)
	var events := state.server_events
	state.set_decoy_active(true)
	assert_eq(state.server_events, events, "no change, no event")
	var data := state.to_array()
	assert_eq((data[34] as PackedInt32Array)[10], 1)
	var copy := PlayerState.from_array(data)
	assert_true(copy.decoy_active)
	assert_true(copy.matches(state))
	copy.decoy_active = false
	assert_false(copy.matches(state), "compared")
	assert_false(PlayerState.from_array(state.view_array()).decoy_active, "owner only")


func test_ability_ready_for() -> void:
	assert_false(state.ability_ready_for(swap, params))
	state.set_decoy_active(true)
	assert_true(state.ability_ready_for(swap, params))
	state.statuses.apply(params.statuses, root)
	assert_false(state.ability_ready_for(blink, params))
	assert_true(state.ability_ready_for(strike, params))


# --- Air dodge exit speed ---

func test_air_dodge_exit_clamps_while_hovering() -> void:
	params.dodge_air_exit_speed = 4.0
	params.dodge_air_exit_hover_only = true
	var fast := Vector3(9.0, 0.0, 0.0)
	assert_almost(PlayerMovement.after_air_dodge(fast, true, params).length(), 4.0, 0.001)
	assert_almost(PlayerMovement.after_air_dodge(fast, false, params).length(), 9.0, 0.001,
			"not hovering: untouched")
	var slow := Vector3(0.0, 0.0, -3.0)
	assert_eq(PlayerMovement.after_air_dodge(slow, true, params), slow, "slower: untouched")


func test_air_dodge_exit_everywhere_or_off() -> void:
	params.dodge_air_exit_speed = 4.0
	params.dodge_air_exit_hover_only = false
	var fast := Vector3(6.0, 0.0, 8.0)
	var out := PlayerMovement.after_air_dodge(fast, false, params)
	assert_almost(out.length(), 4.0, 0.001)
	assert_almost(out.normalized().dot(fast.normalized()), 1.0, 0.001, "same direction")
	params.dodge_air_exit_speed = 0.0
	assert_eq(PlayerMovement.after_air_dodge(fast, true, params), fast, "0 = no limit")
