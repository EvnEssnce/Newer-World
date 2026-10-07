class_name PlayerState
extends RefCounted
## A player's simulated state besides position and velocity: stamina, dodge,
## attacks, block, stagger, death, facing. step() advances it one tick from one
## input. No physics here, so it can be unit tested (tests/test_player_state.gd,
## tests/test_attacks.gd, tests/test_block.gd, tests/test_death_stagger.gd).
##
## The server sends this in every snapshot, and the client restores it when it
## reconciles, so everything that affects the simulation must live here.
##
## Blocked hits, stagger, death and respawn are applied by the server outside
## step() (the client can't predict being hit). Each one bumps server_events, so
## the client knows the resulting correction was expected.

## Jump, attack and block are set on every tick they're held; dodge only on the
## tick it's pressed. Tap attack = light (on release), hold = heavy.
const BUTTON_JUMP := 1
const BUTTON_DODGE := 2
const BUTTON_ATTACK := 4
const BUTTON_BLOCK := 8
const ALL_BUTTONS := BUTTON_JUMP | BUTTON_DODGE | BUTTON_ATTACK | BUTTON_BLOCK

const ATTACK_NONE := 0
const ATTACK_LIGHT := 1
const ATTACK_HEAVY := 2

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
## Ticks the attack button has been held, or HOLD_RELEASED / HOLD_SPENT.
var attack_hold := HOLD_RELEASED
## An attack waiting to start (pressed mid-attack or mid-roll), and ticks it stays queued.
var queued_attack := ATTACK_NONE
var queued_attack_ticks := 0
## Guarding this tick: block held, and not attacking, dodging or staggered.
var blocking := false
## Facing around Y. 0 faces -Z.
var yaw := 0.0
## Ticks left in a stagger (interrupted; can't act). Applied by the server.
var stagger_ticks := 0
## Down at 0 health: can't act and can't be hit. Applied and cleared by the server.
var dead := false
## Counts server-applied changes (stagger, death, respawn).
var server_events := 0
## Whether the body ended its last step on the floor. Kept here rather than read
## from CharacterBody3D.is_on_floor(), so a reconciling client restores it along
## with the position (otherwise a stale flag makes the replay diverge).
var on_floor := false


## Advances one tick. move is the world-space XZ input (length <= 1); aim_yaw is
## the camera's facing: an attack starts facing it and keeps turning toward it.
func step(move: Vector2, buttons: int, aim_yaw: float, on_floor: bool, params: PlayerParams,
		delta: float) -> void:
	if on_floor:
		air_dodges_used = 0
	if dodge_tick >= 0:
		dodge_tick += 1
		if dodge_tick >= params.dodge_ticks:
			dodge_tick = -1
	if attack_tick >= 0:
		attack_tick += 1
		if attack_tick >= params.attack(attack_type).total_ticks():
			_end_attack()
	if stagger_ticks > 0:
		stagger_ticks -= 1
	blocking = false
	if dead:
		return

	# Presses while staggered stay buffered and fire when the stagger ends.
	_handle_dodge_input(move, buttons, on_floor, params)
	_handle_attack_input(buttons, aim_yaw, params)
	# Attacking and dodging take priority; holding block resumes the guard after.
	blocking = (buttons & BUTTON_BLOCK) != 0 and can_act() and dodge_tick < 0 and attack_tick < 0

	if attack_tick > 0:
		yaw = rotate_toward(yaw, aim_yaw, params.attack_turn_speed * delta)
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

## Interrupts the current attack or dodge and stops the player acting for ticks.
func apply_stagger(ticks: int) -> void:
	if ticks <= 0 or dead:
		return
	_end_attack()
	queued_attack = ATTACK_NONE
	dodge_tick = -1
	blocking = false
	stagger_ticks = maxi(stagger_ticks, ticks)
	server_events += 1


## A hit landed on this player's guard. Costs stamina instead of health; breaks
## the guard (long stagger) if the attack always breaks blocks or the stamina
## runs out. Returns true on a guard break.
func take_blocked_hit(attack: AttackParams, params: PlayerParams) -> bool:
	var broke := attack.breaks_block or stamina < attack.block_stamina_damage
	stamina = maxf(0.0, stamina - attack.block_stamina_damage)
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
	stagger_ticks = 0
	server_events += 1


func revive(params: PlayerParams) -> void:
	dead = false
	stamina = params.max_stamina
	stamina_regen_wait = 0
	server_events += 1


# --- Dodge ---

## A dodge can start when not already dodging, with enough stamina, on the floor
## or with an air dodge left, and not mid-attack (except during recovery, which
## the dodge cancels).
func can_dodge(on_floor: bool, params: PlayerParams) -> bool:
	return (can_act() and dodge_tick < 0 and stamina >= params.dodge_stamina_cost
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
		dodge_dir = Vector2(-sin(yaw), -cos(yaw))
	else:
		dodge_dir = move.normalized()
		yaw = yaw_for_direction(dodge_dir)


# --- Attacks ---

func can_attack() -> bool:
	return can_act() and dodge_tick < 0 and attack_tick < 0


func is_attacking() -> bool:
	return attack_tick >= 0


## The current attack's params, or null when not attacking.
func current_attack(params: PlayerParams) -> AttackParams:
	return params.attack(attack_type) if attack_tick >= 0 else null


## True while the current attack's hitbox is live.
func is_attack_active(params: PlayerParams) -> bool:
	var attack := current_attack(params)
	return (attack != null and attack_tick >= attack.windup_ticks
			and attack_tick < attack.windup_ticks + attack.active_ticks)


func is_attack_recovering(params: PlayerParams) -> bool:
	var attack := current_attack(params)
	return attack != null and attack_tick >= attack.windup_ticks + attack.active_ticks


func _handle_attack_input(buttons: int, aim_yaw: float, params: PlayerParams) -> void:
	var requested := ATTACK_NONE
	if buttons & BUTTON_ATTACK:
		if attack_hold == HOLD_RELEASED:
			attack_hold = 0
		elif attack_hold >= 0:
			attack_hold += 1
		if attack_hold >= params.heavy_hold_ticks:
			requested = ATTACK_HEAVY
			attack_hold = HOLD_SPENT
	else:
		if attack_hold >= 0:
			requested = ATTACK_LIGHT  # released before it became a heavy
		attack_hold = HOLD_RELEASED

	if requested != ATTACK_NONE:
		queued_attack = requested
		queued_attack_ticks = params.attack_buffer_ticks + 1
	if queued_attack == ATTACK_NONE:
		return
	queued_attack_ticks -= 1
	if can_attack():
		attack_type = queued_attack
		attack_tick = 0
		yaw = aim_yaw
		queued_attack = ATTACK_NONE
	elif queued_attack_ticks <= 0:
		queued_attack = ATTACK_NONE


func _end_attack() -> void:
	attack_tick = -1
	attack_type = ATTACK_NONE


## The yaw that faces a world-space XZ direction.
static func yaw_for_direction(direction: Vector2) -> float:
	# Godot models face -Z, so forward is (-sin(yaw), -cos(yaw)).
	return atan2(-direction.x, -direction.y)


# --- Network / reconciliation ---

func to_array() -> Array:
	return [stamina, stamina_regen_wait, dodge_tick, dodge_dir, dodge_buffer, yaw,
			air_dodges_used, attack_type, attack_tick, queued_attack, queued_attack_ticks,
			stagger_ticks, dead, server_events, attack_hold, blocking, on_floor]


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
			and on_floor == other.on_floor)
