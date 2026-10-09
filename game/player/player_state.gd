class_name PlayerState
extends RefCounted
## A player's simulated state besides position and velocity: stamina, dodge,
## attacks, abilities and their cooldowns, weapon loadout and swap, block,
## stagger, death, facing, statuses, Wing abilities, Ember and Rebirth. step()
## advances it one tick from one input (tests/test_ember_wings.gd covers the
## last three).
## No physics here, so it can be unit tested (tests/test_player_state.gd,
## tests/test_attacks.gd, tests/test_block.gd, tests/test_death_stagger.gd,
## tests/test_abilities.gd, tests/test_weapon_swap.gd, tests/test_status_sim.gd).
##
## The server sends this in every snapshot, and the client restores it when it
## reconciles, so everything that affects the simulation must live here.
##
## Blocked hits, stagger, death, respawn, parries (start_counter), an ability
## stopping on hit (end_active_window), loadout changes (set_loadout), statuses the
## server applies or removes (apply_status, take_on_hit_statuses, cleanse), forced
## movement (start_force), Wing loadout changes (set_wings), Ember gains
## (gain_ember) and Rebirth (start_rebirth, finish_rebirth) are applied by the
## server outside step() (the client can't predict them). Each one bumps
## server_events, so the client knows the resulting correction was expected. A
## self-buff from the player's own attack or ability (self_status), spending Ember
## on a Wing ability and Ember settling out of combat happen inside step(), so
## they're predicted.

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
## Wing slots 1-2 (Z / C) are BUTTON_WING_1 << slot. Sent on press, buffered.
const BUTTON_WING_1 := 256
const BUTTON_WING_2 := 512
const ALL_BUTTONS := (BUTTON_JUMP | BUTTON_DODGE | BUTTON_ATTACK | BUTTON_BLOCK | BUTTON_SWAP
		| BUTTON_ABILITY_1 | BUTTON_ABILITY_2 | BUTTON_ABILITY_3 | BUTTON_WING_1 | BUTTON_WING_2)

const ATTACK_NONE := 0
const ATTACK_LIGHT := 1
const ATTACK_HEAVY := 2
## An ability from the equipped weapon's pool (see `ability`).
const ATTACK_ABILITY := 3
## A Wing ability: `ability` indexes the class's Wing pool (wings()).
const ATTACK_WING := 4

## Equipped weapons, and ability slots per weapon.
const WEAPON_SLOTS := 2
const ABILITY_SLOTS := 3
## Wing ability slots (the same whichever weapon is out).
const WING_SLOTS := 2

## attack_hold values besides a tick count.
const HOLD_RELEASED := -1
## The held press already became a heavy attack; nothing more until released.
const HOLD_SPENT := -2

var stamina := 0.0
## Ticks left before stamina regen starts again.
var stamina_regen_wait := 0
## Ticks since the current dodge started, or -1 when not dodging.
var dodge_tick := -1
## Ticks left after a roll ends before another dodge can start ([dodge] cooldown).
var dodge_cooldown := 0
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
## The ability slot (0-2) of a queued ATTACK_ABILITY, or the Wing slot (0-1)
## of a queued ATTACK_WING.
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
## World-space XZ direction of the ability's dash (its facing when it started,
## or the opposite for a backward dash like Vault). Its length is the fraction
## of the dash distance covered (below 1 only for a pitch-aimed dash).
var ability_dir := Vector2.ZERO

# Statuses (indices into PlayerParams.statuses)
## Buffs and debuffs, ticked down in step(). Slow and root change movement
## (PlayerMovement), stun staggers; damage effects are the server's business.
var statuses := StatusEffects.new()
## Output of the last step(), not state (so not in to_array): damage over time
## (bleed) due that tick. The server applies it; clients ignore it.
var status_damage := 0.0
## Output of the last step(), not state: healing over time (Pyre Heart) due
## that tick. The server applies it; clients ignore it.
var status_heal := 0.0
# Forced movement (knockback, pull, launch). Started by the server
# (start_force); PlayerMovement moves the body by it.
var force := ForcedMotion.new()

# Wings (set by the server with set_wings, from the character's build)
## The class whose Wing abilities these are (PlayerParams.wings key); "" = none.
var wing_set := ""
## Per Wing slot (Z, C): an index into the Wing pool, or -1 for an empty slot.
var wing_slots := PackedInt32Array()
## Ticks left on each Wing ability's cooldown, by pool index.
var wing_cooldowns := PackedInt32Array()

# Ember (the phoenix resource). Spending (Wing abilities) and settling toward
# the resting level happen in step(), so they're predicted; gains (damage dealt,
# damage taken, healing) are server events (gain_ember).
var ember := 0.0
## "In combat": ticks left since the server last reported this player dealing
## or taking damage (gain_ember with in_combat). Counted down in step(); Ember
## only settles toward its resting level once it reaches 0. Synced, so the
## client predicts the settling exactly.
var combat_ticks := 0

# Rebirth (server-decided; see can_rebirth)
## Ticks left in a Rebirth in progress (dead, rising where they fell), counted
## down in step(); 0 = done, waiting for the server to raise them; -1 = not
## rebirthing.
var rebirth_left := -1
## Ticks before the next Rebirth. Counts down in step() once the Rebirth that
## started it is over.
var rebirth_cooldown := 0
## Extra Rebirths that ignore the cooldown (still need the Ember). Nothing
## grants them yet: the Paladin's Phoenix Blessing will (grant_rebirth_charge).
var rebirth_charges := 0


func _init() -> void:
	ability_slots.resize(WEAPON_SLOTS * ABILITY_SLOTS)
	ability_slots.fill(-1)
	cooldowns.resize(WEAPON_SLOTS * WeaponParams.MAX_ABILITIES)
	cooldowns.fill(0)
	wing_slots.resize(WING_SLOTS)
	wing_slots.fill(-1)
	wing_cooldowns.resize(WeaponParams.MAX_ABILITIES)
	wing_cooldowns.fill(0)


## Advances one tick. move is the world-space XZ input (length <= 1); aim_yaw is
## the camera's facing: an attack starts facing it and keeps turning toward it.
## aim_pitch is the camera's pitch (radians, up = positive), for dashes aimed by
## it (AbilityParams.dash_aim_pitch).
func step(move: Vector2, buttons: int, aim_yaw: float, on_floor: bool, params: PlayerParams,
		delta: float, aim_pitch := 0.0) -> void:
	if on_floor:
		air_dodges_used = 0
	for i in cooldowns.size():
		if cooldowns[i] > 0:
			cooldowns[i] -= 1
	for i in wing_cooldowns.size():
		if wing_cooldowns[i] > 0:
			wing_cooldowns[i] -= 1
	_step_ember_and_rebirth(params)
	status_damage = statuses.tick(params.statuses)
	status_heal = statuses.heal_due
	if dodge_cooldown > 0:
		dodge_cooldown -= 1
	if dodge_tick >= 0:
		dodge_tick += 1
		if dodge_tick >= params.dodge_ticks:
			dodge_tick = -1
			dodge_cooldown = params.dodge_cooldown_ticks
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
	_handle_attack_input(move, buttons, aim_yaw, aim_pitch, params)
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


## False while staggered, being moved (forced movement) or dead: no moving,
## dodging, attacking or jumping.
func can_act() -> bool:
	return not dead and stagger_ticks == 0 and not force.is_active()


func is_staggered() -> bool:
	return stagger_ticks > 0


## False while rooted: no walking, dodging, jumping or dashing.
func can_move(params: PlayerParams) -> bool:
	return statuses.can_move(params.statuses)


## Walking speed multiplier from slows (1.0 = none).
func status_move_multiplier(params: PlayerParams) -> float:
	return statuses.move_multiplier(params.statuses)


# --- Server-applied events ---

## Interrupts the current attack, ability, dodge or swap and stops the player
## acting for ticks. (An interrupted swap keeps the new weapon out.) Refused
## while dead or stagger immune (a stagger_immune status: Steadfast, Unbowed).
func apply_stagger(ticks: int, params: PlayerParams) -> void:
	if ticks <= 0 or dead or statuses.stagger_immune(params.statuses):
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
		apply_stagger(params.guard_break_stagger_ticks, params)
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
	statuses.clear()
	force.stop()
	server_events += 1


## Server: back from the dead (a respawn): full stamina, Ember back at its
## resting level, out of combat. finish_rebirth keeps the Ember instead.
func revive(params: PlayerParams) -> void:
	dead = false
	stamina = params.max_stamina
	stamina_regen_wait = 0
	statuses.clear()
	ember = params.ember_resting
	combat_ticks = 0
	rebirth_left = -1
	server_events += 1


## A parry succeeded: starts the parry ability's counter, facing face_yaw (toward
## whoever was parried). Returns false if there's nothing to counter with.
func start_counter(params: PlayerParams, face_yaw: float) -> bool:
	var parry := current_ability(params)
	if parry == null or attack_type != ATTACK_ABILITY:
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


## Server: applies a status (index into params.statuses) from someone else,
## e.g. a debuff from a hit. duration_ticks -1 = the status's own. A stun also
## staggers for its duration (stun and stagger are one mechanic). Returns false
## if nothing was applied (dead, not a status, or immune: StatusEffects.refuses,
## a stun while stagger immune or any crowd control while CC immune). A taunt
## (forces_target) only does something on enemies.
func apply_status(params: PlayerParams, index: int, stacks: int = 1, duration_ticks: int = -1,
		source: int = 0) -> bool:
	if dead or not statuses.apply(params.statuses, index, stacks, duration_ticks, source):
		return false
	server_events += 1
	var def := params.statuses.get_def(index)
	if def.stuns:
		apply_stagger(statuses.ticks_left(index), params)
	return true


## Server: this player landed a damaging hit. Returns the statuses it applies to
## the target from the player's own on-hit statuses ([index, stacks] each, e.g.
## Bloodlust's bleed), using up their stacks.
func take_on_hit_statuses(params: PlayerParams) -> Array[Vector2i]:
	var before := statuses.to_packed()
	var result := statuses.take_on_hit_statuses(params.statuses)
	if statuses.to_packed() != before:
		server_events += 1
	return result


## Server: removes every debuff (a cleanse). Removing a stun also ends its
## stagger. Returns how many were removed.
func cleanse(params: PlayerParams) -> int:
	var stunned := false
	for e in statuses.entries:
		var def := params.statuses.get_def(e.status)
		stunned = stunned or (def != null and def.stuns)
	var removed := statuses.remove_debuffs(params.statuses)
	if removed > 0:
		if stunned:
			stagger_ticks = 0
		server_events += 1
	return removed


## Inside the sim: an attack or ability with a self_status (Bloodlust) applies
## it to its user as it starts, so the client predicts it.
func _apply_self_status(attack: AttackParams, params: PlayerParams) -> void:
	if attack == null or attack.self_status.is_empty():
		return
	statuses.apply(params.statuses, params.statuses.index_of(attack.self_status),
			attack.self_status_stacks)
# --- Forced movement (the FORCE tag) ---

## Being pushed, pulled or launched: can't act until it ends.
func is_forced() -> bool:
	return force.is_active()


## Can't be pushed, pulled or launched. The one place forced movement asks, so
## other sources only change this. Today: a force_immune status (the
## Juggernaut's Braced, Steadfast, Unbowed). Statuses are synced, but only the
## server applies force, so a refusal never needs predicting.
func is_force_immune(params: PlayerParams) -> bool:
	return statuses.force_immune(params.statuses)


## Server: moves this player `displacement` meters (world XZ) over `ticks`
## steps of `delta` seconds, launching it at launch_speed m/s (0 = no launch).
## Like a stagger it interrupts the current attack, ability, dodge, swap and
## guard, and the player can't act until it ends (presses made meanwhile stay
## buffered). Refused (false) while dead, in i-frames, or immune.
func start_force(params: PlayerParams, displacement: Vector2, ticks: int, launch_speed: float,
		delta: float) -> bool:
	if dead or ticks <= 0 or is_invulnerable(params) or is_force_immune(params):
		return false
	_end_attack()
	queued_attack = ATTACK_NONE
	dodge_tick = -1
	swap_tick = -1
	blocking = false
	force.start(displacement, ticks, launch_speed, delta)
	server_events += 1
	return true


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


# --- Wings ---

## Server: sets the Wing abilities: the class's pool (set_id, a PlayerParams.wings
## key) and new_slots (pool indices for Z and C, -1 = empty). Cooldowns stay
## (they're per pool index), so a respec can't reset them. Nothing happens (no
## server event) if that's already the Wing loadout.
func set_wings(set_id: String, new_slots: PackedInt32Array) -> void:
	var padded := new_slots.slice(0, WING_SLOTS)
	while padded.size() < WING_SLOTS:
		padded.append(-1)
	if set_id == wing_set and padded == wing_slots:
		return
	if set_id != wing_set:
		wing_cooldowns.fill(0)
	wing_set = set_id
	wing_slots.fill(-1)
	for i in mini(new_slots.size(), WING_SLOTS):
		wing_slots[i] = new_slots[i]
	if queued_attack == ATTACK_WING:
		queued_attack = ATTACK_NONE
	server_events += 1


func wings(params: PlayerParams) -> WingParams:
	return params.wing_set(wing_set)


## The Wing-pool index in Wing slot `slot` (0 = Z, 1 = C), or -1.
func wing_slot_ability(slot: int) -> int:
	return wing_slots[slot] if slot >= 0 and slot < wing_slots.size() else -1


## Ticks left on Wing ability `index` (pool index).
func wing_cooldown_left(index: int) -> int:
	return wing_cooldowns[index] if index >= 0 and index < wing_cooldowns.size() else 0


## Enough Ember for an ability's ember_cost.
func can_afford(started: AbilityParams) -> bool:
	return started != null and ember >= started.ember_cost


# --- Ember ---

## The most Ember this player can hold. The one place that reads the cap, so
## progression upgrades only change this.
func ember_cap(params: PlayerParams) -> float:
	return params.ember_cap


func in_combat() -> bool:
	return combat_ticks > 0


## Server: adds Ember (damage dealt or taken, healing), capped. in_combat: it
## came from dealing or taking damage, so the player is in combat for
## ember_combat_ticks (no settling). A server event. Ignored while dead.
func gain_ember(params: PlayerParams, amount: float, in_combat_now: bool = true) -> void:
	if dead or (amount <= 0.0 and not in_combat_now):
		return
	ember = clampf(ember + maxf(0.0, amount), 0.0, ember_cap(params))
	if in_combat_now:
		combat_ticks = params.ember_combat_ticks
	server_events += 1


## Inside step(): the combat timer, settling toward the resting level out of
## combat, and the Rebirth countdown and cooldown. Ember doesn't change while
## dead.
func _step_ember_and_rebirth(params: PlayerParams) -> void:
	if combat_ticks > 0:
		combat_ticks -= 1
	elif not dead:
		ember = move_toward(ember, params.ember_resting, params.ember_settle_per_tick)
	if rebirth_left > 0:
		rebirth_left -= 1
	elif rebirth_cooldown > 0 and not is_rebirthing():
		rebirth_cooldown -= 1


# --- Rebirth ---

## Ember needed to Rebirth. The one place for modifiers (the Paladin's "allies
## near you need 10 less Ember").
func rebirth_ember_needed(params: PlayerParams) -> float:
	return params.rebirth_threshold


## True if dying now would start a Rebirth: enough Ember, and Rebirth off
## cooldown or an extra charge (rebirth_charges) to use.
func can_rebirth(params: PlayerParams) -> bool:
	return (ember >= rebirth_ember_needed(params)
			and (rebirth_cooldown == 0 or rebirth_charges > 0))


func is_rebirthing() -> bool:
	return dead and rebirth_left >= 0


## 0..1 through a Rebirth in progress, or -1.
func rebirth_progress(params: PlayerParams) -> float:
	if not is_rebirthing():
		return -1.0
	return 1.0 - rebirth_left / float(maxi(1, params.rebirth_ticks))


## Server, right after kill(): starts a Rebirth if can_rebirth. Spends the
## Ember; on cooldown it uses an extra charge instead (the cooldown is left
## alone), otherwise it starts the cooldown, which only counts down once the
## player has risen. Returns false (normal respawn) if not eligible.
func start_rebirth(params: PlayerParams) -> bool:
	if not dead or is_rebirthing() or not can_rebirth(params):
		return false
	if rebirth_cooldown > 0:
		rebirth_charges -= 1
	else:
		rebirth_cooldown = params.rebirth_cooldown_ticks
	ember = maxf(0.0, ember - params.rebirth_cost)
	rebirth_left = params.rebirth_ticks
	server_events += 1
	return true


## True once a Rebirth's countdown has run out: the server raises the player.
func rebirth_done() -> bool:
	return is_rebirthing() and rebirth_left == 0


## Server: rises from a Rebirth (where they fell; the server sets the health,
## rebirth_health). Like revive, but keeps the Ember left after the cost.
func finish_rebirth(params: PlayerParams) -> void:
	var kept := ember
	revive(params)
	ember = kept


## Health on rising from a Rebirth.
static func rebirth_health(params: PlayerParams) -> float:
	return params.max_health * params.rebirth_health_fraction


## Server hook (the Paladin's Phoenix Blessing): extra Rebirths that ignore the
## cooldown.
func grant_rebirth_charge(count: int = 1) -> void:
	if count <= 0:
		return
	rebirth_charges += count
	server_events += 1


## Server hook (the Paladin's Cleansing Flame): takes ticks off the Rebirth
## cooldown.
func reduce_rebirth_cooldown(ticks: int) -> void:
	if ticks <= 0 or rebirth_cooldown == 0:
		return
	rebirth_cooldown = maxi(0, rebirth_cooldown - ticks)
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
	# A queued press was meant for the other weapon (Wing presses aren't).
	if queued_attack != ATTACK_WING:
		queued_attack = ATTACK_NONE


# --- Dodge ---

## A dodge can start when not already dodging or swapping, with enough stamina,
## on the floor or with an air dodge left, not rooted, and not mid-attack
## (except during recovery, which the dodge cancels).
func can_dodge(on_floor: bool, params: PlayerParams) -> bool:
	return (can_act() and can_move(params) and dodge_tick < 0 and dodge_cooldown == 0
			and swap_tick < 0
			and stamina >= params.dodge_stamina_cost
			and (on_floor or air_dodges_used < params.max_air_dodges)
			and (attack_tick < 0 or is_attack_recovering(params)))


func is_dodging() -> bool:
	return dodge_tick >= 0


func is_invulnerable(params: PlayerParams) -> bool:
	if dodge_tick >= params.iframe_start_tick and dodge_tick < params.iframe_end_tick:
		return true
	# Abilities with i-frames (Vault).
	var a := current_ability(params)
	return a != null and a.has_iframes(attack_tick)


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


## True during weapon abilities and Wing abilities.
func is_using_ability() -> bool:
	return attack_tick >= 0 and (attack_type == ATTACK_ABILITY or attack_type == ATTACK_WING)


func is_using_wing() -> bool:
	return attack_tick >= 0 and attack_type == ATTACK_WING


## The params of attack_type (and `ability`) with the equipped weapon (or the
## Wing pool), whether or not it's running. Null for ATTACK_NONE.
func attack_params(params: PlayerParams) -> AttackParams:
	if attack_type == ATTACK_ABILITY:
		return weapon(params).ability(ability)
	if attack_type == ATTACK_WING:
		return wings(params).ability(ability)
	return weapon(params).attack(attack_type)


## The current attack's (or ability's) params, or null when not attacking.
func current_attack(params: PlayerParams) -> AttackParams:
	return attack_params(params) if attack_tick >= 0 else null


## The current weapon or Wing ability's params, or null when not using one.
func current_ability(params: PlayerParams) -> AbilityParams:
	return attack_params(params) as AbilityParams if is_using_ability() else null


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


func _handle_attack_input(move: Vector2, buttons: int, aim_yaw: float, aim_pitch: float,
		params: PlayerParams) -> void:
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
	for slot in WING_SLOTS:
		if buttons & (BUTTON_WING_1 << slot):
			queued_attack = ATTACK_WING
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
		if can_attack() and cooldown_left(index) == 0 and can_afford(w.ability(index)):
			_start_ability(index, aim_yaw, aim_pitch, params, move)
			queued_attack = ATTACK_NONE
			return
	elif queued_attack == ATTACK_WING:
		# Not enough Ember (or on cooldown): stays buffered, so Ember the server
		# grants within the buffer still lets it start.
		var wing_index := wing_slot_ability(queued_ability_slot)
		var wing := wings(params).ability(wing_index)
		if wing == null:
			queued_attack = ATTACK_NONE  # empty slot
			return
		if can_attack() and wing_cooldowns[wing_index] == 0 and can_afford(wing):
			_start_ability(wing_index, aim_yaw, aim_pitch, params, move, true)
			queued_attack = ATTACK_NONE
			return
	elif can_attack():
		attack_type = queued_attack
		attack_tick = 0
		attack_serial += 1
		yaw = aim_yaw
		queued_attack = ATTACK_NONE
		_apply_self_status(attack_params(params), params)
		return
	if queued_attack_ticks <= 0:
		queued_attack = ATTACK_NONE


## move: this step's movement input (world XZ), for dashes that follow it.
## wing: index is into the Wing pool (a Wing ability) instead of the weapon's.
## Starts its cooldown and spends its Ember cost.
func _start_ability(index: int, aim_yaw: float, aim_pitch: float, params: PlayerParams,
		move := Vector2.ZERO, wing := false) -> void:
	attack_type = ATTACK_WING if wing else ATTACK_ABILITY
	ability = index
	attack_tick = 0
	attack_serial += 1
	yaw = aim_yaw
	var started := attack_params(params) as AbilityParams
	# A backward dash moves away from where the ability faces; an input dash
	# (Vault) goes the way you're moving, or backward with no input.
	ability_dir = -forward(yaw) if started.dash_backward else forward(yaw)
	if started.dash_from_input:
		ability_dir = move.normalized() if move.length() > 0.1 else -forward(yaw)
		# Face the way it goes (its turn_speed 0 keeps it there for the vault).
		yaw = yaw_for_direction(ability_dir)
	# A pitch-aimed dash (Crashing Leap) keeps its fraction of the distance in
	# the length of ability_dir, which PlayerMovement doesn't normalize.
	ability_dir *= started.dash_fraction(aim_pitch)
	if wing:
		wing_cooldowns[index] = started.cooldown_ticks
	else:
		cooldowns[equipped * WeaponParams.MAX_ABILITIES + index] = started.cooldown_ticks
	ember = maxf(0.0, ember - started.ember_cost)
	_apply_self_status(started, params)


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
			swap_tick, swap_buffer, ability, ability_dir, queued_ability_slot, attack_serial,
			statuses.to_packed(), force.velocity, force.ticks, force.launch, dodge_cooldown,
			ember, wing_set, _pack_ember_wings()]


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
	s.statuses = StatusEffects.from_packed(data[27])
	s.force.velocity = data[28]
	s.force.ticks = data[29]
	s.force.launch = data[30]
	s.dodge_cooldown = data[31]
	s.ember = data[32]
	s.wing_set = data[33]
	s._unpack_ember_wings(data[34])
	return s


## to_array() index 34, one PackedInt32Array to keep snapshots small:
## [combat_ticks, rebirth_left, rebirth_cooldown, rebirth_charges, Z slot,
## C slot, then Wing cooldowns by pool index, without trailing zeros].
const PACKED_WING_HEADER := 6


func _pack_ember_wings() -> PackedInt32Array:
	var packed := PackedInt32Array([combat_ticks, rebirth_left, rebirth_cooldown, rebirth_charges,
			wing_slots[0], wing_slots[1]])
	var last := wing_cooldowns.size() - 1
	while last >= 0 and wing_cooldowns[last] == 0:
		last -= 1
	packed.append_array(wing_cooldowns.slice(0, last + 1))
	return packed


func _unpack_ember_wings(packed: PackedInt32Array) -> void:
	combat_ticks = packed[0]
	rebirth_left = packed[1]
	rebirth_cooldown = packed[2]
	rebirth_charges = packed[3]
	wing_slots[0] = packed[4]
	wing_slots[1] = packed[5]
	wing_cooldowns.fill(0)
	for i in mini(packed.size() - PACKED_WING_HEADER, wing_cooldowns.size()):
		wing_cooldowns[i] = packed[PACKED_WING_HEADER + i]


func copy() -> PlayerState:
	return from_array(to_array())


## True if other is the same state, allowing for float rounding.
func matches(other: PlayerState) -> bool:
	return (absf(stamina - other.stamina) < 0.001
			and stamina_regen_wait == other.stamina_regen_wait
			and dodge_tick == other.dodge_tick
			and dodge_cooldown == other.dodge_cooldown
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
			and attack_serial == other.attack_serial
			and statuses.to_packed() == other.statuses.to_packed()
			and force.matches(other.force)
			and absf(ember - other.ember) < 0.001
			and combat_ticks == other.combat_ticks
			and wing_set == other.wing_set
			and wing_slots == other.wing_slots
			and wing_cooldowns == other.wing_cooldowns
			and rebirth_left == other.rebirth_left
			and rebirth_cooldown == other.rebirth_cooldown
			and rebirth_charges == other.rebirth_charges)
