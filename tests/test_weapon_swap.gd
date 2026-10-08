extends TestCase
## Weapon swap and per-weapon rules in PlayerState: two equipped weapons, swap
## timing and buffering, attacks and abilities from the weapon that's out,
## cooldowns that keep running while holstered, loadout changes. Fixed params.

const ATTACK := PlayerState.BUTTON_ATTACK
const BLOCK := PlayerState.BUTTON_BLOCK
const DODGE := PlayerState.BUTTON_DODGE
const SWAP := PlayerState.BUTTON_SWAP
const Q := PlayerState.BUTTON_ABILITY_1
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState
var sword: WeaponParams
var axes: WeaponParams


func before_each() -> void:
	params = PlayerParams.new()
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.dodge_stamina_cost = 30.0
	params.dodge_ticks = 20
	params.dodge_buffer_ticks = 5
	params.ability_buffer_ticks = 4
	params.swap_ticks = 10
	params.swap_buffer_ticks = 5
	params.guard_break_stagger_ticks = 30
	sword = _weapon("sword", 3, 1.0)
	axes = _weapon("axes", 2, 1.5)
	params.weapons = {"sword": sword, "axes": axes}
	state = PlayerState.new()
	state.stamina = params.max_stamina
	state.set_loadout(PackedStringArray(["sword", "axes"]), PackedInt32Array([0, -1, -1, 0, -1, -1]))


## A weapon whose light attack has `windup` ticks (so tests can tell them apart)
## and one ability with a 50-tick cooldown.
func _weapon(id: String, windup: int, block_multiplier: float) -> WeaponParams:
	var w := WeaponParams.new()
	w.id = id
	w.heavy_hold_ticks = 5
	w.attack_buffer_ticks = 4
	w.attack_turn_speed = TAU
	w.block_stamina_multiplier = block_multiplier
	w.light_attack = AttackParams.new()
	w.light_attack.windup_ticks = windup
	w.light_attack.active_ticks = 2
	w.light_attack.recovery_ticks = 4
	w.heavy_attack = w.light_attack
	var a := AbilityParams.new()
	a.id = id + "_ability"
	a.windup_ticks = 2
	a.active_ticks = 2
	a.recovery_ticks = 2
	a.cooldown_ticks = 50
	w.abilities = [a]
	return w


func _step(buttons: int = 0) -> void:
	state.step(Vector2.ZERO, buttons, 0.0, true, params, DELTA)


func _steps(count: int, buttons: int = 0) -> void:
	for i in count:
		_step(buttons)


func test_starts_with_the_first_weapon_out() -> void:
	assert_eq(state.equipped, 0)
	assert_eq(state.weapon(params), sword)


func test_swap_switches_weapon_and_takes_its_time() -> void:
	_step(SWAP)
	assert_eq(state.weapon(params), axes)
	assert_true(state.is_swapping())
	_steps(params.swap_ticks - 1)
	assert_true(state.is_swapping(), "last swap tick")
	_step()
	assert_false(state.is_swapping())


func test_swapping_back() -> void:
	_step(SWAP)
	_steps(params.swap_ticks)
	_step(SWAP)
	assert_eq(state.weapon(params), sword)


func test_no_attack_block_dodge_or_ability_while_swapping() -> void:
	_step(SWAP)
	_step(ATTACK)
	_step()
	assert_false(state.is_attacking(), "attack")
	_step(BLOCK)
	assert_false(state.blocking, "block")
	_step(DODGE)
	assert_false(state.is_dodging(), "dodge")
	_step(Q)
	assert_false(state.is_attacking(), "ability")


func test_attack_pressed_during_swap_fires_after_it() -> void:
	_step(SWAP)
	_steps(params.swap_ticks - 3)
	_step(ATTACK)
	_step()  # released: light queued
	assert_false(state.is_attacking())
	_step()
	assert_true(state.is_attacking(), "starts the tick the swap ends")
	assert_eq(state.current_attack(params), axes.light_attack, "with the new weapon")


func test_no_swap_mid_attack_but_buffered() -> void:
	_step(ATTACK)
	_step()  # sword light starts
	_steps(sword.light_attack.total_ticks() - 3)
	_step(SWAP)
	assert_eq(state.weapon(params), sword, "can't swap mid-attack")
	_steps(2)
	assert_eq(state.weapon(params), axes, "swapped as soon as the attack ended")


func test_no_swap_mid_ability() -> void:
	_step(Q)
	_step(SWAP)
	assert_eq(state.weapon(params), sword)
	assert_true(state.is_using_ability())


func test_swap_buffer_expires() -> void:
	_step(DODGE)
	_step(SWAP)  # 19 roll ticks left, longer than the 5-tick buffer
	_steps(params.dodge_ticks)
	assert_eq(state.weapon(params), sword)


func test_no_swap_with_one_weapon() -> void:
	state.set_loadout(PackedStringArray(["sword"]), PackedInt32Array())
	_step(SWAP)
	assert_eq(state.equipped, 0)
	assert_false(state.is_swapping())


func test_swap_drops_an_attack_queued_before_it() -> void:
	_step(Q)  # sword ability, 6 ticks
	_steps(3)
	_step(ATTACK)
	_step(SWAP)  # attack released: light queued; swap buffered too
	_step()  # the ability ends: the swap goes first and drops the queued light
	assert_true(state.is_swapping())
	_steps(params.swap_ticks)
	assert_false(state.is_attacking(), "the light (meant for the sword) never happens")


func test_abilities_come_from_the_weapon_out() -> void:
	_step(SWAP)
	_steps(params.swap_ticks)
	_step(Q)
	assert_eq(state.current_ability(params), axes.abilities[0])


func test_cooldowns_keep_running_while_holstered() -> void:
	_step(Q)  # sword ability: 50-tick cooldown
	_steps(10)
	_step(SWAP)
	_steps(30)
	assert_eq(state.cooldowns[0], 50 - 41, "sword's cooldown kept counting")
	assert_eq(state.cooldown_left(0), 0, "axes' ability is ready")
	_step(Q)
	assert_eq(state.current_ability(params), axes.abilities[0])


func test_each_weapon_has_its_own_cooldowns() -> void:
	_step(Q)
	_steps(10)
	_step(SWAP)
	_steps(params.swap_ticks)
	_step(Q)
	assert_true(state.is_using_ability(), "the axes ability isn't on the sword's cooldown")


func test_set_loadout_keeps_cooldowns_of_a_weapon_that_moves_slot() -> void:
	_step(Q)
	var events := state.server_events
	state.set_loadout(PackedStringArray(["axes", "sword"]), PackedInt32Array([0, -1, -1, 0, -1, -1]))
	assert_eq(state.cooldowns[WeaponParams.MAX_ABILITIES], 50, "sword cooldown moved to slot 1")
	assert_eq(state.cooldowns[0], 0)
	assert_eq(state.server_events, events + 1, "a server event")


func test_set_loadout_clears_missing_slots() -> void:
	state.set_loadout(PackedStringArray(["sword", "axes"]), PackedInt32Array([0]))
	assert_eq(state.ability_slots, PackedInt32Array([0, -1, -1, -1, -1, -1]))


func test_cannot_change_loadout_mid_attack_or_swap() -> void:
	assert_true(state.can_change_loadout())
	_step(Q)
	assert_false(state.can_change_loadout(), "ability")
	_steps(10)
	_step(SWAP)
	assert_false(state.can_change_loadout(), "swap")
	_steps(params.swap_ticks)
	assert_true(state.can_change_loadout())


func test_stagger_ends_swap_but_keeps_the_new_weapon() -> void:
	_step(SWAP)
	state.apply_stagger(5)
	assert_false(state.is_swapping())
	assert_eq(state.weapon(params), axes)


func test_blocked_hit_cost_uses_the_weapon_multiplier() -> void:
	var attack := AttackParams.new()
	attack.block_stamina_damage = 20.0
	state.take_blocked_hit(attack, params)
	assert_almost(state.stamina, 80.0, 0.001, "sword: x1")
	state.stamina = 100.0
	state.equipped = 1
	state.take_blocked_hit(attack, params, 0.5)
	assert_almost(state.stamina, 100.0 - 20.0 * 1.5 * 0.5, 0.001, "axes x1.5, passive x0.5")


func test_weaker_guard_breaks_sooner() -> void:
	var attack := AttackParams.new()
	attack.block_stamina_damage = 30.0
	state.stamina = 40.0
	assert_false(state.take_blocked_hit(attack, params), "sword: 30 < 40")
	state.stamina = 40.0
	state.equipped = 1
	assert_true(state.take_blocked_hit(attack, params), "axes: 45 > 40 breaks")


func test_network_round_trip_keeps_swap_state() -> void:
	_step(SWAP)
	_steps(3)
	var copy := PlayerState.from_array(state.to_array())
	assert_true(copy.matches(state))
	assert_eq(copy.weapons, state.weapons)
	assert_eq(copy.equipped, 1)
	assert_eq(copy.swap_tick, 3)
