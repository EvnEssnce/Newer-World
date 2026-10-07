class_name PlayerState
extends RefCounted
## A player's simulated state besides position and velocity: stamina, dodge,
## facing. step() advances it one tick from one input. No physics here, so it
## can be unit tested (tests/test_player_state.gd).
##
## The server sends this in every snapshot, and the client restores it when it
## reconciles, so everything that affects the simulation must live here.

const BUTTON_JUMP := 1
const BUTTON_DODGE := 2
const ALL_BUTTONS := BUTTON_JUMP | BUTTON_DODGE

var stamina := 0.0
## Ticks left before stamina regen starts again.
var stamina_regen_wait := 0
## Ticks since the current dodge started, or -1 when not dodging.
var dodge_tick := -1
## World-space XZ direction of the current dodge, normalized.
var dodge_dir := Vector2.ZERO
## True if the current dodge is a backstep (dodged with no movement input).
var backstep := false
## Ticks a dodge press stays queued while a dodge isn't possible.
var dodge_buffer := 0
## Dodges started since last on the floor.
var air_dodges_used := 0
## Facing around Y. 0 faces -Z.
var yaw := 0.0


## Advances one tick. move is the world-space XZ input (length <= 1).
func step(move: Vector2, buttons: int, on_floor: bool, params: PlayerParams, delta: float) -> void:
	if on_floor:
		air_dodges_used = 0
	if dodge_tick >= 0:
		dodge_tick += 1
		if dodge_tick >= params.dodge_ticks:
			dodge_tick = -1

	if buttons & BUTTON_DODGE:
		dodge_buffer = params.dodge_buffer_ticks + 1
	if dodge_buffer > 0:
		dodge_buffer -= 1
		if can_dodge(on_floor, params):
			_start_dodge(move, params)
			if not on_floor:
				air_dodges_used += 1

	if dodge_tick < 0:
		if stamina_regen_wait > 0:
			stamina_regen_wait -= 1
		else:
			stamina = minf(params.max_stamina, stamina + params.stamina_regen_per_tick)
		if move.length_squared() > 0.01:
			yaw = rotate_toward(yaw, yaw_for_direction(move), params.turn_speed * delta)


func can_dodge(on_floor: bool, params: PlayerParams) -> bool:
	return (dodge_tick < 0 and stamina >= params.dodge_stamina_cost
			and (on_floor or air_dodges_used < params.max_air_dodges))


func is_dodging() -> bool:
	return dodge_tick >= 0


func is_invulnerable(params: PlayerParams) -> bool:
	return dodge_tick >= params.iframe_start_tick and dodge_tick < params.iframe_end_tick


## 0..1 through the current dodge, or -1 when not dodging.
func dodge_progress(params: PlayerParams) -> float:
	return dodge_tick / float(params.dodge_ticks) if dodge_tick >= 0 else -1.0


func _start_dodge(move: Vector2, params: PlayerParams) -> void:
	dodge_tick = 0
	dodge_buffer = 0
	stamina -= params.dodge_stamina_cost
	stamina_regen_wait = params.stamina_regen_delay_ticks
	backstep = move.length_squared() <= 0.01
	if backstep:
		# Straight back from where the character faces, without turning.
		dodge_dir = Vector2(sin(yaw), cos(yaw))
	else:
		dodge_dir = move.normalized()
		yaw = yaw_for_direction(dodge_dir)


## The yaw that faces a world-space XZ direction.
static func yaw_for_direction(direction: Vector2) -> float:
	# Godot models face -Z, so forward is (-sin(yaw), -cos(yaw)).
	return atan2(-direction.x, -direction.y)


# --- Network / reconciliation ---

func to_array() -> Array:
	return [stamina, stamina_regen_wait, dodge_tick, dodge_dir, backstep, dodge_buffer, yaw,
			air_dodges_used]


static func from_array(data: Array) -> PlayerState:
	var s := PlayerState.new()
	s.stamina = data[0]
	s.stamina_regen_wait = data[1]
	s.dodge_tick = data[2]
	s.dodge_dir = data[3]
	s.backstep = data[4]
	s.dodge_buffer = data[5]
	s.yaw = data[6]
	s.air_dodges_used = data[7]
	return s


func copy() -> PlayerState:
	return from_array(to_array())


## True if other is the same state, allowing for float rounding.
func matches(other: PlayerState) -> bool:
	return (absf(stamina - other.stamina) < 0.001
			and stamina_regen_wait == other.stamina_regen_wait
			and dodge_tick == other.dodge_tick
			and dodge_buffer == other.dodge_buffer
			and air_dodges_used == other.air_dodges_used)
