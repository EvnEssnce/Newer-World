class_name PlayerState
extends RefCounted
## A player's simulated state besides position and velocity: stamina, dodge,
## attacks, abilities and their cooldowns, weapon loadout and swap, block,
## stagger, death, facing. step() advances it one tick from one input. No
## physics here, so it can be unit tested (tests/test_player_state.gd,
## tests/test_attacks.gd, tests/test_block.gd, tests/test_death_stagger.gd,
## tests/test_abilities.gd, tests/test_weapon_swap.gd).
##
## The server sends this in every snapshot, and the client restores it when it
## reconciles, so everything that affects the simulation must live here.
##
## Blocked hits, stagger, death, respawn, parries (start_counter), an ability
## stopping on hit (end_active_window) and loadout changes (set_loadout) are
## applied by the server outside step() (the client can't predict them). Each
## one bumps server_events, so the client knows the resulting correction was
## expected.

## Jump, attack and block are set on every tick they're held; dodge, swap and
## the ability buttons only on the tick they're pressed. Tap attack = light (on
## release), hold = heavy.
const BUTTON_JUMP := 1
const BUTTON_DODGE := 2
const BUTTON_ATTACK := 4
const BUTTON_BLOCK := 8
const BUTTON_SWAP := 16
## Ability slots 1-3 (Q / E / R) are BUTTON_ABILITY_1 << slot.
const BUTTON_ABILITY_1 := 32
const BUTTON_ABILITY_2 := 64
const BUTTON_ABILITY_3 := 128
const ALL_BUTTONS := (BUTTON_JUMP | BUTTON_DODGE | BUTTON_ATTACK | BUTTON_BLOCK | BUTTON_SWAP
		| BUTTON_ABILITY_1 | BUTTON_ABILITY_2 | BUTTON_ABILITY_3)

const ATTACK_NONE := 0
const ATTACK_LIGHT := 1
const ATTACK_HEAVY := 2
## An ability from the equipped weapon's pool (see `ability`).
const ATTACK_ABILITY := 3

## Equipped weapons, and ability slots per weapon.
const WEAPON_SLOTS := 2
const ABILITY_SLOTS := 3

## attack_hold values besides a tick count.
const HOLD_RELEASED := -1
## The held press already became a heavy attack; nothing more until released.
const HOLD_SPENT := -2

var stamina := 0.0
## Ticks left before stamina regen starts again.
var stamina_regen_wait := 0
## Ticks since the current dodge started, or -1 when not dodging.
var dodge_tick := -1
## World-space XZ direction of the current dodge, normalized.
var dodge_dir := Vector2.ZERO
## Ticks a dodge press stays queued while a dodge isn't possible.
var dodge_buffer := 0
## Dodges started since last on the floor.
var air_dodges_used := 0
## ATTACK_* of the current attack.
var attack_type := ATTACK_NONE
## Ticks since the current attack started, or -1 when not attacking.
var attack_tick := -1
## Counts attacks and abilities started, so a new one is told apart from the
## last even when both are the same kind (hit tracking, interpolation).
var attack_serial := 0
## Ticks the attack button has been held, or HOLD_RELEASED / HOLD_SPENT.
var attack_hold := HOLD_RELEASED
## An attack waiting to start (pressed mid-attack or mid-roll), and ticks it stays queued.
var queued_attack := ATTACK_NONE
var queued_attack_ticks := 0
## The ability slot (0-2) of a queued ATTACK_ABILITY.
var queued_ability_slot := -1
## Guarding this tick: block held, and not attacking, dodging, swapping or staggered.
var blocking := false
## Facing around Y. 0 faces -Z.
var yaw := 0.0
## Ticks left in a stagger (interrupted; can't act). Applied by the server.
var stagger_ticks := 0
## Down at 0 health: can't act and can't be hit. Applied and cleared by the server.
var dead := false
## Counts server-applied changes (stagger, death, respawn, parry, loadout...).
var server_events := 0
## Whether the body ended its last step on the floor. Kept here rather than read
## from CharacterBody3D.is_on_floor(), so a reconciling client restores it along
## with the position (otherwise a stale flag makes the replay diverge).
var on_floor := false

# Loadout. Set by the server (set_loadout), from the character's build.
## Equipped weapon ids, one per weapon slot. Empty (tests, or before the first
## snapshot) means PlayerParams.default_weapon.
var weapons := PackedStringArray()
## The weapon slot that's out (0 or 1).
var equipped := 0
## Per weapon slot, per ability slot (index weapon_slot * ABILITY_SLOTS + slot):
## an index into that weapon's ability pool, or -1 for an empty slot.
var ability_slots := PackedInt32Array()
## Ticks left on each ability's cooldown, index
## weapon_slot * WeaponParams.MAX_ABILITIES + pool index. Counts down for both
## weapons, holstered or not.
var cooldowns := PackedInt32Array()

# Weapon swap
## Ticks since the current swap started, or -1 when not swapping.
var swap_tick := -1
## Ticks a swap press stays queued while a swap isn't possible.
var swap_buffer := 0

# Abilities (attack_type == ATTACK_ABILITY)
## Index into the equipped weapon's ability pool, or -1.
var ability := -1
## World-space XZ direction of the ability's dash (its facing when it started).
var ability_dir := Vector2.ZERO


func _init() -> void:
	ability_slots.resize(WEAPON_SLOTS * ABILITY_SLOTS)
	ability_slots.fill(-1)
	cooldowns.resize(WEAPON_SLOTS * WeaponParams.MAX_ABILITIES)
	cooldowns.fill(0)


## Advances one tick. move is the world-space XZ input (length <= 1); aim_yaw is
## the camera's facing: an attack starts facing it and keeps turning toward it.
func step(move: Vector2, buttons: int, aim_yaw: float, on_floor: bool, params: PlayerParams,
		delta: float) -> void:
	if on_floor:
		air_dodges_used = 0
	for i in cooldowns.size():
		if cooldowns[i] > 0:
			cooldowns[i] -= 1
	if dodge_tick >= 0:
		dodge_tick += 1
		if dodge_tick >= params.dodge_ticks:
			dodge_tick = -1
	if swap_tick >= 0:
		swap_tick += 1
		if swap_tick >= params.swap_ticks:
			swap_tick = -1
	if attack_tick >= 0:
		attack_tick += 1
		if attack_tick >= attack_params(params).total_ticks():
			_end_attack()
	if stagger_ticks > 0:
		stagger_ticks -= 1
	blocking = false
	if dead:
		return

	# Presses while staggered stay buffered and fire when the stagger ends.
	_handle_dodge_input(move, buttons, on_floor, params)
	_handle_swap_input(buttons, params)
	_handle_attack_input(buttons, aim_yaw, params)
	# Attacking and dodging take priority; holding block resumes the guard after.
	blocking = ((buttons & BUTTON_BLOCK) != 0 and can_act() and dodge_tick < 0
			and attack_tick < 0 and swap_tick < 0)

	if attack_tick > 0:
		yaw = rotate_toward(yaw, aim_yaw, _attack_turn_speed(params) * delta)
	elif blocking:
		yaw = rotate_toward(yaw, aim_yaw, params.block_turn_speed * delta)

	if dodge_tick < 0:
		if stamina_regen_wait > 0:
			stamina_regen_wait -= 1
		else:
			var regen := params.stamina_regen_per_tick
			if blocking:
				regen *= params.block_regen_multiplier
			stamina = minf(params.max_stamina, stamina + regen)
		if attack_tick < 0 and not blocking and can_act() and move.length_squared() > 0.01:
			yaw = rotate_toward(yaw, yaw_for_direction(move), params.turn_speed * delta)


## False while staggered or dead: no moving, dodging, attacking or jumping.
func can_act() -> bool:
	return not dead and stagger_ticks == 0


func is_staggered() -> bool:
	return stagger_ticks > 0


# --- Server-applied events ---

## Interrupts the current attack, ability, dodge or swap and stops the player
## acting for ticks. (An interrupted swap keeps the new weapon out.)
func apply_stagger(ticks: int) -> void:
	if ticks <= 0 or dead:
		return
	_end_attack()
	queued_attack = ATTACK_NONE
	dodge_tick = -1
	swap_tick = -1
	blocking = false
	stagger_ticks = maxi(stagger_ticks, ticks)
	server_events += 1


## A hit landed on this player's guard. Costs stamina instead of health (times
## the equipped weapon's block_stamina_multiplier and `multiplier`, the
## server's passive modifiers); breaks the guard (long stagger) if the attack
## always breaks blocks or the stamina runs out. Returns true on a guard break.
func take_blocked_hit(attack: AttackParams, params: PlayerParams, multiplier: float = 1.0) -> bool:
	var cost := attack.block_stamina_damage * weapon(params).block_stamina_multiplier * multiplier
	var broke := attack.breaks_block or stamina < cost
	stamina = maxf(0.0, stamina - cost)
	stamina_regen_wait = params.stamina_regen_delay_ticks
	server_events += 1
	if broke:
		blocking = false
		apply_stagger(params.guard_break_stagger_ticks)
	return broke


func kill() -> void:
	dead = true
	blocking = false
	_end_attack()
	queued_attack = ATTACK_NONE
	dodge_tick = -1
	dodge_buffer = 0
	swap_tick = -1
	swap_buffer = 0
	stagger_ticks = 0
	server_events += 1


func revive(params: PlayerParams) -> void:
	dead = false
	stamina = params.max_stamina
	stamina_regen_wait = 0
	server_events += 1


## A parry succeeded: starts the parry ability's counter, facing face_yaw (toward
## whoever was parried). Returns false if there's nothing to counter with.
func start_counter(params: PlayerParams, face_yaw: float) -> bool:
	var parry := current_ability(params)
	if parry == null:
		return false
	var index := weapon(params).ability_index(parry.counter)
	if index < 0:
		return false
	attack_type = ATTACK_ABILITY
	ability = index
	attack_tick = 0
	attack_serial += 1
	yaw = face_yaw
	ability_dir = forward(yaw)
	server_events += 1
	return true


## The current attack hit what it was allowed to (AttackParams.max_targets):
## skips the rest of its hit windows (and any dash) to its recovery.
func end_active_window(params: PlayerParams) -> void:
	var attack := current_attack(params)
	if attack == null or attack_tick >= attack.recovery_start_tick():
		return
	attack_tick = attack.recovery_start_tick()
	server_events += 1


## Loadout changes (weapons, slotted abilities) can't happen mid-attack,
## mid-ability or mid-swap.
func can_change_loadout() -> bool:
	return attack_tick < 0 and swap_tick < 0


## Equips new_weapons (ids, one per weapon slot) with new_slots (see
## ability_slots). A weapon that stays equipped keeps its cooldowns, even if it
## moves to the other slot.
func set_loadout(new_weapons: PackedStringArray, new_slots: PackedInt32Array) -> void:
	var new_cooldowns := PackedInt32Array()
	new_cooldowns.resize(WEAPON_SLOTS * WeaponParams.MAX_ABILITIES)
	new_cooldowns.fill(0)
	for slot in mini(new_weapons.size(), WEAPON_SLOTS):
		var old_slot := weapons.find(new_weapons[slot])
		if old_slot < 0 or old_slot >= WEAPON_SLOTS:
			continue
		for i in WeaponParams.MAX_ABILITIES:
			new_cooldowns[slot * WeaponParams.MAX_ABILITIES + i] = (
					cooldowns[old_slot * WeaponParams.MAX_ABILITIES + i])
	weapons = new_weapons.duplicate()
	ability_slots.fill(-1)
	for i in mini(new_slots.size(), ability_slots.size()):
		ability_slots[i] = new_slots[i]
	cooldowns = new_cooldowns
	if queued_attack == ATTACK_ABILITY:
		queued_attack = ATTACK_NONE
	server_events += 1


# --- Weapons ---

## The equipped weapon's id ("" with no loadout).
func weapon_id() -> String:
	return weapons[equipped] if equipped < weapons.size() else ""


func weapon(params: PlayerParams) -> WeaponParams:
	return params.weapon(weapon_id())


func can_swap() -> bool:
	return (can_act() and weapons.size() >= WEAPON_SLOTS and dodge_tick < 0
			and attack_tick < 0 and swap_tick < 0)


func is_swapping() -> bool:
	return swap_tick >= 0


func _handle_swap_input(buttons: int, params: PlayerParams) -> void:
	if buttons & BUTTON_SWAP:
		swap_buffer = params.swap_buffer_ticks + 1
	if swap_buffer <= 0:
		return
	swap_buffer -= 1
	if not can_swap():
		return
	swap_buffer = 0
	equipped = 1 - equipped
	swap_tick = 0
	# A queued press was meant for the other weapon.
	queued_attack = ATTACK_NONE


# --- Dodge ---

## A dodge can start when not already dodging or swapping, with enough stamina,
## on the floor or with an air dodge left, and not mid-attack (except during
## recovery, which the dodge cancels).
func can_dodge(on_floor: bool, params: PlayerParams) -> bool:
	return (can_act() and dodge_tick < 0 and swap_tick < 0
			and stamina >= params.dodge_stamina_cost
			and (on_floor or air_dodges_used < params.max_air_dodges)
			and (attack_tick < 0 or is_attack_recovering(params)))


func is_dodging() -> bool:
	return dodge_tick >= 0


func is_invulnerable(params: PlayerParams) -> bool:
	return dodge_tick >= params.iframe_start_tick and dodge_tick < params.iframe_end_tick


## 0..1 through the current dodge, or -1 when not dodging.
func dodge_progress(params: PlayerParams) -> float:
	return dodge_tick / float(params.dodge_ticks) if dodge_tick >= 0 else -1.0


func _handle_dodge_input(move: Vector2, buttons: int, on_floor: bool, params: PlayerParams) -> void:
	if buttons & BUTTON_DODGE:
		dodge_buffer = params.dodge_buffer_ticks + 1
	if dodge_buffer <= 0:
		return
	dodge_buffer -= 1
	if not can_dodge(on_floor, params):
		return
	_end_attack()
	queued_attack = ATTACK_NONE
	dodge_tick = 0
	dodge_buffer = 0
	stamina -= params.dodge_stamina_cost
	stamina_regen_wait = params.stamina_regen_delay_ticks
	if not on_floor:
		air_dodges_used += 1
	if move.length_squared() <= 0.01:
		# No movement input: roll the way the character faces.
		dodge_dir = forward(yaw)
	else:
		dodge_dir = move.normalized()
		yaw = yaw_for_direction(dodge_dir)


# --- Attacks and abilities ---

func can_attack() -> bool:
	return can_act() and dodge_tick < 0 and attack_tick < 0 and swap_tick < 0


## True during light/heavy attacks and abilities.
func is_attacking() -> bool:
	return attack_tick >= 0


func is_using_ability() -> bool:
	return attack_tick >= 0 and attack_type == ATTACK_ABILITY


## The params of attack_type (and `ability`) with the equipped weapon, whether
## or not it's running. Null for ATTACK_NONE.
func attack_params(params: PlayerParams) -> AttackParams:
	if attack_type == ATTACK_ABILITY:
		return weapon(params).ability(ability)
	return weapon(params).attack(attack_type)


## The current attack's (or ability's) params, or null when not attacking.
func current_attack(params: PlayerParams) -> AttackParams:
	return attack_params(params) if attack_tick >= 0 else null


## The current ability's params, or null when not using one.
func current_ability(params: PlayerParams) -> AbilityParams:
	return weapon(params).ability(ability) if is_using_ability() else null


## True while the current attack's hitbox is live.
func is_attack_active(params: PlayerParams) -> bool:
	return attack_window(params) >= 0


## The current attack's live hit window (0-based), or -1.
func attack_window(params: PlayerParams) -> int:
	var attack := current_attack(params)
	if attack == null or attack.shape == AttackParams.SHAPE_NONE:
		return -1
	return attack.window_at(attack_tick)


func is_attack_recovering(params: PlayerParams) -> bool:
	var attack := current_attack(params)
	return attack != null and attack_tick >= attack.recovery_start_tick()


## True during a parry ability's parry window.
func is_parrying(params: PlayerParams) -> bool:
	var a := current_ability(params)
	return a != null and a.is_parry() and a.window_at(attack_tick) >= 0


## True while the current ability moves the player (see AbilityParams.is_dashing).
func is_dashing(params: PlayerParams) -> bool:
	var a := current_ability(params)
	return a != null and a.is_dashing(attack_tick)


## The ability-pool index in ability slot `slot` of the equipped weapon, or -1.
func slot_ability(slot: int) -> int:
	return ability_slots[equipped * ABILITY_SLOTS + slot]


## Ticks left on the equipped weapon's ability `index`.
func cooldown_left(index: int) -> int:
	return cooldowns[equipped * WeaponParams.MAX_ABILITIES + index]


func _handle_attack_input(buttons: int, aim_yaw: float, params: PlayerParams) -> void:
	var w := weapon(params)
	var requested := ATTACK_NONE
	if buttons & BUTTON_ATTACK:
		if attack_hold == HOLD_RELEASED:
			attack_hold = 0
		elif attack_hold >= 0:
			attack_hold += 1
		if attack_hold >= w.heavy_hold_ticks:
			requested = ATTACK_HEAVY
			attack_hold = HOLD_SPENT
	else:
		if attack_hold >= 0:
			requested = ATTACK_LIGHT  # released before it became a heavy
		attack_hold = HOLD_RELEASED

	if requested != ATTACK_NONE:
		queued_attack = requested
		queued_attack_ticks = w.attack_buffer_ticks + 1
	for slot in ABILITY_SLOTS:
		if buttons & (BUTTON_ABILITY_1 << slot):
			queued_attack = ATTACK_ABILITY
			queued_ability_slot = slot
			queued_attack_ticks = params.ability_buffer_ticks + 1
	if queued_attack == ATTACK_NONE:
		return
	queued_attack_ticks -= 1
	if queued_attack == ATTACK_ABILITY:
		var index := slot_ability(queued_ability_slot)
		if w.ability(index) == null:
			queued_attack = ATTACK_NONE  # empty slot
			return
		if can_attack() and cooldown_left(index) == 0:
			_start_ability(index, aim_yaw, params)
			queued_attack = ATTACK_NONE
			return
	elif can_attack():
		attack_type = queued_attack
		attack_tick = 0
		attack_serial += 1
		yaw = aim_yaw
		queued_attack = ATTACK_NONE
		return
	if queued_attack_ticks <= 0:
		queued_attack = ATTACK_NONE


func _start_ability(index: int, aim_yaw: float, params: PlayerParams) -> void:
	attack_type = ATTACK_ABILITY
	ability = index
	attack_tick = 0
	attack_serial += 1
	yaw = aim_yaw
	ability_dir = forward(yaw)
	cooldowns[equipped * WeaponParams.MAX_ABILITIES + index] = weapon(params).ability(index).cooldown_ticks


func _attack_turn_speed(params: PlayerParams) -> float:
	var a := current_ability(params)
	return a.turn_speed if a else weapon(params).attack_turn_speed


func _end_attack() -> void:
	attack_tick = -1
	attack_type = ATTACK_NONE
	ability = -1


## The yaw that faces a world-space XZ direction.
static func yaw_for_direction(direction: Vector2) -> float:
	# Godot models face -Z, so forward is (-sin(yaw), -cos(yaw)).
	return atan2(-direction.x, -direction.y)


## The world-space XZ direction a yaw faces.
static func forward(facing: float) -> Vector2:
	return Vector2(-sin(facing), -cos(facing))


# --- Network / reconciliation ---

func to_array() -> Array:
	return [stamina, stamina_regen_wait, dodge_tick, dodge_dir, dodge_buffer, yaw,
			air_dodges_used, attack_type, attack_tick, queued_attack, queued_attack_ticks,
			stagger_ticks, dead, server_events, attack_hold, blocking, on_floor,
			weapons.duplicate(), equipped, ability_slots.duplicate(), cooldowns.duplicate(),
			swap_tick, swap_buffer, ability, ability_dir, queued_ability_slot, attack_serial]


static func from_array(data: Array) -> PlayerState:
	var s := PlayerState.new()
	s.stamina = data[0]
	s.stamina_regen_wait = data[1]
	s.dodge_tick = data[2]
	s.dodge_dir = data[3]
	s.dodge_buffer = data[4]
	s.yaw = data[5]
	s.air_dodges_used = data[6]
	s.attack_type = data[7]
	s.attack_tick = data[8]
	s.queued_attack = data[9]
	s.queued_attack_ticks = data[10]
	s.stagger_ticks = data[11]
	s.dead = data[12]
	s.server_events = data[13]
	s.attack_hold = data[14]
	s.blocking = data[15]
	s.on_floor = data[16]
	s.weapons = (data[17] as PackedStringArray).duplicate()
	s.equipped = data[18]
	s.ability_slots = (data[19] as PackedInt32Array).duplicate()
	s.cooldowns = (data[20] as PackedInt32Array).duplicate()
	s.swap_tick = data[21]
	s.swap_buffer = data[22]
	s.ability = data[23]
	s.ability_dir = data[24]
	s.queued_ability_slot = data[25]
	s.attack_serial = data[26]
	return s


func copy() -> PlayerState:
	return from_array(to_array())


## True if other is the same state, allowing for float rounding.
func matches(other: PlayerState) -> bool:
	return (absf(stamina - other.stamina) < 0.001
			and stamina_regen_wait == other.stamina_regen_wait
			and dodge_tick == other.dodge_tick
			and dodge_buffer == other.dodge_buffer
			and air_dodges_used == other.air_dodges_used
			and attack_type == other.attack_type
			and attack_tick == other.attack_tick
			and queued_attack == other.queued_attack
			and queued_attack_ticks == other.queued_attack_ticks
			and stagger_ticks == other.stagger_ticks
			and dead == other.dead
			and server_events == other.server_events
			and attack_hold == other.attack_hold
			and blocking == other.blocking
			and on_floor == other.on_floor
			and weapons == other.weapons
			and equipped == other.equipped
			and ability_slots == other.ability_slots
			and cooldowns == other.cooldowns
			and swap_tick == other.swap_tick
			and swap_buffer == other.swap_buffer
			and ability == other.ability
			and queued_ability_slot == other.queued_ability_slot
			and attack_serial == other.attack_serial)
