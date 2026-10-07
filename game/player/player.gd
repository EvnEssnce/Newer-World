class_name Player
extends CharacterBody3D
## A player character. The same scene plays three roles:
##
## - Server: simulates one step per input received from its client, and owns
##   health. Emits attack_stepped while an attack's hitbox is live; World
##   resolves the hits.
## - Local client player: predicts from the keyboard immediately, then corrects
##   itself when a server snapshot disagrees (reconciliation).
## - Remote client player: drawn slightly in the past, interpolating between
##   server snapshots.
##
## Inputs are [seq: int, move: Vector2, buttons: int, aim_yaw: float]. "move" is a
## world-space XZ direction with length <= 1, already rotated by the client's
## camera; "buttons" holds PlayerState.BUTTON_* bits; "aim_yaw" is the camera's yaw.

## Server only: emitted after each sim step in which an attack's hitbox is live.
signal attack_stepped(player: Player)

const MAX_PENDING_INPUTS := 120
const MAX_SNAPSHOTS := 30
## Meters the server may differ from our prediction before we rewind and replay.
const RECONCILE_TOLERANCE := 0.01
## Must match the capsule in player.tscn. Used by server hit detection.
const BODY_RADIUS := 0.4
const BODY_HEIGHT := 1.8

# Placeholder visuals (cosmetic only; replaced by real animation/VFX later).
const LOCAL_COLOR := Color(0.25, 0.55, 0.95)
const REMOTE_COLOR := Color(0.95, 0.55, 0.2)
## Body color while i-frames are active, so they're visible while tuning.
const INVULNERABLE_COLOR := Color(0.95, 0.95, 1.0)
const HIT_COLOR := Color(1.0, 0.15, 0.1)
const DEAD_COLOR := Color(0.35, 0.35, 0.38)
const HIT_FLASH_MS := 150
## Body tilt (radians, backward) while staggered.
const STAGGER_TILT := 0.4
## Shield pivot position/yaw at the left side, and raised in front while blocking.
const SHIELD_REST := Vector3(-0.5, 0.0, 0.0)
const SHIELD_REST_YAW := PI / 2.0
const SHIELD_RAISED := Vector3(-0.1, 0.2, -0.5)
## Sword pivot rotation (x = pitch, y = sweep) at rest and at each swing's extremes.
const SWORD_IDLE := Vector2(-0.7, 0.0)
const LIGHT_WOUND := Vector2(0.0, -1.4)
const LIGHT_STRUCK := Vector2(0.0, 1.4)
const HEAVY_WOUND := Vector2(1.7, 0.0)
const HEAVY_STRUCK := Vector2(-1.3, 0.0)

## Shows attack hitboxes on all players. Toggled with F3.
static var show_hitboxes := false
## --verbose: log dropped inputs (server) and unexpected corrections (client).
static var verbose := LaunchArgs.has_flag("verbose")

var peer_id := 0
var is_local := false
var state := PlayerState.new()
var params := PlayerParams.current()
## Server-authoritative; clients copy it from snapshots.
var health := 0.0
## Counted once per real simulation step (not on replays); for the smoke test.
var dodges := 0
var air_dodges := 0
var attacks := 0

# Server
var last_processed_seq := 0
## Targets the current attack has already been resolved against:
## true = hit (can't be hit again), false = evaded so far (can still be hit).
var attack_results: Dictionary[int, bool] = {}
## Server tick at which a dead player respawns.
var respawn_at_tick := -1
var _input_queue: Array[Array] = []
var _last_queued_seq := 0

# Local client
var corrections := 0
var _next_seq := 1
var _pending_inputs: Array[Array] = []
var _predictions: Dictionary[int, Array] = {}  # seq -> [position, PlayerState] after that input
var _latest_ack: Array = []  # [pos, vel, seq, state array] from the newest snapshot
var _last_ack_seq := 0
var _reconciled_seq := 0
var _camera_pivot: Node3D
var _spring_arm: SpringArm3D

# Remote client
var _snapshots: Array[Array] = []  # [server_time, pos, PlayerState]
var distance_seen := 0.0
## The state currently being drawn (remote players only); the test bot reads it.
var view_state := PlayerState.new()

var _material: StandardMaterial3D
var _base_color := REMOTE_COLOR
var _hit_flash_until := 0
var _hitbox_material: StandardMaterial3D

@onready var _model: Node3D = $Model
@onready var _roll_pivot: Node3D = $Model/RollPivot
@onready var _sword_pivot: Node3D = $Model/RollPivot/SwordPivot
@onready var _shield_pivot: Node3D = $Model/RollPivot/ShieldPivot
@onready var _hitbox_debug: MeshInstance3D = $Model/HitboxDebug
@onready var _name_label: Label3D = $NameLabel


func _ready() -> void:
	state.stamina = params.max_stamina
	health = params.max_health
	if multiplayer.is_server():
		_name_label.visible = false
		return
	_base_color = LOCAL_COLOR if is_local else REMOTE_COLOR
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	($Model/RollPivot/Body as MeshInstance3D).material_override = _material
	_hitbox_material = StandardMaterial3D.new()
	_hitbox_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hitbox_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hitbox_debug.material_override = _hitbox_material
	_update_label()
	if is_local:
		_setup_camera()


func _process(_delta: float) -> void:
	if is_local:
		_show(state, state.yaw, state.dodge_progress(params), state.attack_tick)


func _simulate(move: Vector2, buttons: int, aim_yaw: float, delta: float) -> void:
	var was_on_floor := is_on_floor()
	PlayerMovement.step(self, state, move, buttons, aim_yaw, params, delta)
	if state.dodge_tick == 0:
		dodges += 1
		if not was_on_floor:
			air_dodges += 1
	if state.attack_tick == 0:
		attacks += 1
		attack_results.clear()
	if multiplayer.is_server() and state.is_attack_active(params):
		attack_stepped.emit(self)


# --- Server ---

func server_queue_inputs(inputs: Array, max_buffer: int) -> void:
	for input: Variant in inputs:
		if not (input is Array and input.size() == 4 and input[0] is int
				and input[1] is Vector2 and input[2] is int and input[3] is float):
			continue
		var seq: int = input[0]
		var move: Vector2 = input[1]
		var aim_yaw: float = input[3]
		if seq <= _last_queued_seq or not move.is_finite() or not is_finite(aim_yaw):
			continue
		if verbose and seq != _last_queued_seq + 1 and _last_queued_seq > 0:
			print("[server] peer %d inputs %d-%d never arrived" % [peer_id, _last_queued_seq + 1, seq - 1])
		_input_queue.append([seq, move.limit_length(1.0), input[2] & PlayerState.ALL_BUTTONS,
				aim_yaw])
		_last_queued_seq = seq
	while _input_queue.size() > max_buffer:
		if verbose:
			print("[server] peer %d input queue full, dropped input %d" % [peer_id, _input_queue[0][0]])
		_input_queue.pop_front()


## Runs at most max_per_tick queued inputs. With no input queued the player
## doesn't move, so server and client always simulate the same number of steps.
func server_process_inputs(max_per_tick: int, delta: float) -> void:
	for i in mini(max_per_tick, _input_queue.size()):
		var input: Array = _input_queue.pop_front()
		_simulate(input[1], input[2], input[3], delta)
		last_processed_seq = input[0]


func get_snapshot() -> Array:
	return [peer_id, global_position, velocity, last_processed_seq, state.to_array(), health]


# --- Local client ---

## Predicts one step from this tick's input and returns the inputs to send.
## move_input is camera-relative (x right, y back).
func client_predict(move_input: Vector2, buttons: int, aim_yaw: float, delta: float,
		redundancy: int) -> Array:
	_reconcile(delta)
	var world := Vector3(move_input.x, 0.0, move_input.y).rotated(Vector3.UP, get_camera_yaw())
	var move := Vector2(world.x, world.z).limit_length(1.0)
	var input := [_next_seq, move, buttons, aim_yaw]
	_next_seq += 1
	_pending_inputs.append(input)
	if _pending_inputs.size() > MAX_PENDING_INPUTS:
		_predictions.erase(_pending_inputs.pop_front()[0])
	_simulate(move, buttons, aim_yaw, delta)
	_predictions[input[0]] = [global_position, state.copy()]
	return _pending_inputs.slice(-redundancy)


func client_receive_ack(pos: Vector3, vel: Vector3, ack_seq: int, state_data: Array) -> void:
	if ack_seq < _last_ack_seq:
		return
	_last_ack_seq = ack_seq
	_latest_ack = [pos, vel, ack_seq, state_data]


## If the server disagrees with what we predicted for its last processed input,
## rewinds to the server's state and replays every input it hasn't processed yet.
func _reconcile(delta: float) -> void:
	if _latest_ack.is_empty():
		return
	var server_pos: Vector3 = _latest_ack[0]
	var server_vel: Vector3 = _latest_ack[1]
	var ack_seq: int = _latest_ack[2]
	var server_state := PlayerState.from_array(_latest_ack[3])
	_latest_ack = []
	var predicted: Variant = _predictions.get(ack_seq)
	# Keep the entry for ack_seq itself: the next snapshot may acknowledge the same
	# input again (no new input processed in between) and needs it to compare.
	while not _pending_inputs.is_empty() and _pending_inputs[0][0] <= ack_seq:
		var seq: int = _pending_inputs.pop_front()[0]
		if seq != ack_seq:
			_predictions.erase(seq)
	if _reconciled_seq != ack_seq:
		_predictions.erase(_reconciled_seq)
		_reconciled_seq = ack_seq
	if (predicted != null and server_pos.distance_to(predicted[0]) < RECONCILE_TOLERANCE
			and server_state.matches(predicted[1])):
		return

	# Seq 0 is just the initial sync to the spawn point, and server events (stagger,
	# death, respawn) can't be predicted; only other disagreements are real errors.
	var expected: bool = ack_seq == 0 or (predicted != null
			and server_state.server_events != predicted[1].server_events)
	if not expected:
		corrections += 1
		if verbose:
			print("[client] unexpected correction at seq %d: server %s, predicted %s\n  server state %s\n  predicted state %s" % [
					ack_seq, server_pos, predicted[0] if predicted != null else "none",
					server_state.to_array(), predicted[1].to_array() if predicted != null else "none"])
	global_position = server_pos
	velocity = server_vel
	state = server_state
	# The body's own floor flag also steers move_and_slide's floor snapping.
	if state.on_floor and not is_on_floor():
		apply_floor_snap()
	_predictions[ack_seq] = [server_pos, server_state.copy()]
	for input in _pending_inputs:
		PlayerMovement.step(self, state, input[1], input[2], input[3], params, delta)
		_predictions[input[0]] = [global_position, state.copy()]


func get_camera_yaw() -> float:
	return _camera_pivot.rotation.y if _camera_pivot else 0.0


func _setup_camera() -> void:
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraPivot"
	_camera_pivot.position.y = Tuning.get_value("camera", "camera", "pivot_height")
	add_child(_camera_pivot)
	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = Tuning.get_value("camera", "camera", "distance")
	_spring_arm.collision_mask = 1
	_spring_arm.margin = 0.2
	_spring_arm.rotation.x = deg_to_rad(Tuning.get_value("camera", "camera", "start_pitch"))
	_camera_pivot.add_child(_spring_arm)
	var camera := Camera3D.new()
	_spring_arm.add_child(camera)
	camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := deg_to_rad(Tuning.get_value("camera", "camera", "mouse_sensitivity"))
		var min_pitch := deg_to_rad(Tuning.get_value("camera", "camera", "min_pitch"))
		var max_pitch := deg_to_rad(Tuning.get_value("camera", "camera", "max_pitch"))
		_camera_pivot.rotation.y -= event.relative.x * sensitivity
		_spring_arm.rotation.x = clampf(
				_spring_arm.rotation.x - event.relative.y * sensitivity, min_pitch, max_pitch)


# --- Remote client ---

func push_snapshot(server_time: float, pos: Vector3, state_data: Array) -> void:
	if _snapshots.is_empty():
		global_position = pos
	_snapshots.append([server_time, pos, PlayerState.from_array(state_data)])
	if _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


func interpolate(render_time: float) -> void:
	if _snapshots.is_empty():
		return
	while _snapshots.size() >= 2 and _snapshots[1][0] <= render_time:
		_snapshots.pop_front()
	var from: Array = _snapshots[0]
	var from_state: PlayerState = from[2]
	var new_pos: Vector3 = from[1]
	var yaw := from_state.yaw
	var dodge_progress := from_state.dodge_progress(params)
	var attack_tick := float(from_state.attack_tick)
	if _snapshots.size() >= 2 and render_time > from[0]:
		var to: Array = _snapshots[1]
		var to_state: PlayerState = to[2]
		var weight: float = (render_time - from[0]) / (to[0] - from[0])
		new_pos = from[1].lerp(to[1], weight)
		yaw = lerp_angle(from_state.yaw, to_state.yaw, weight)
		if from_state.is_dodging() and to_state.dodge_tick > from_state.dodge_tick:
			dodge_progress = lerpf(dodge_progress, to_state.dodge_progress(params), weight)
		if (from_state.is_attacking() and to_state.attack_type == from_state.attack_type
				and to_state.attack_tick > from_state.attack_tick):
			attack_tick = lerpf(from_state.attack_tick, to_state.attack_tick, weight)
	distance_seen += global_position.distance_to(new_pos)
	global_position = new_pos
	view_state = from_state
	_show(from_state, yaw, dodge_progress, attack_tick)


# --- Client feedback ---

func set_health(value: float) -> void:
	if value == health:
		return
	health = value
	_update_label()


## Shows a hit, evade, block or defeat reported by the server.
func show_hit(damage: float, result: int) -> void:
	HitFeedback.spawn_label(self, 2.4, damage, result)
	if HitFeedback.flashes(result):
		_hit_flash_until = Time.get_ticks_msec() + HIT_FLASH_MS


func _update_label() -> void:
	# Your own health is on the HUD; a label over your head just covers others'.
	_name_label.visible = not is_local
	var status := "Defeated" if health <= 0.0 else str(ceili(health))
	_name_label.text = "Player %d\n%s" % [peer_id % 10000, status]


## Applies facing, roll, stagger/death pose, sword swing, hitbox and color.
## Client only. view supplies the discrete state (attack type, dead, staggered,
## i-frames); yaw, dodge_progress and attack_tick may be interpolated, and
## attack_tick is -1 when not attacking.
func _show(view: PlayerState, yaw: float, dodge_progress: float, attack_tick: float) -> void:
	_model.rotation.y = yaw
	if view.dead:
		_roll_pivot.rotation.x = -PI / 2.0  # face down on the ground
		_roll_pivot.position.y = BODY_RADIUS
	else:
		_roll_pivot.position.y = BODY_HEIGHT / 2.0
		if dodge_progress >= 0.0:
			_roll_pivot.rotation.x = -TAU * dodge_progress  # a full forward somersault
		elif view.is_staggered():
			_roll_pivot.rotation.x = STAGGER_TILT
		else:
			_roll_pivot.rotation.x = 0.0

	_shield_pivot.position = SHIELD_RAISED if view.blocking else SHIELD_REST
	_shield_pivot.rotation.y = 0.0 if view.blocking else SHIELD_REST_YAW

	var attack_type := view.attack_type
	var attack := params.attack(attack_type) if attack_tick >= 0.0 else null
	var pose := _sword_pose(attack, attack_type, attack_tick)
	_sword_pivot.rotation = Vector3(pose.x, pose.y, 0.0)

	_hitbox_debug.visible = show_hitboxes and attack != null
	if _hitbox_debug.visible:
		var box := _hitbox_debug.mesh as BoxMesh
		box.size = Vector3(attack.hitbox_width, attack.hitbox_height, attack.hitbox_range)
		_hitbox_debug.position = Vector3(0.0, attack.hitbox_height / 2.0, -attack.hitbox_range / 2.0)
		var active := (attack_tick >= attack.windup_ticks
				and attack_tick < attack.windup_ticks + attack.active_ticks)
		_hitbox_material.albedo_color = Color(1.0, 0.2, 0.2, 0.45 if active else 0.1)

	if view.dead:
		_material.albedo_color = DEAD_COLOR
	elif Time.get_ticks_msec() < _hit_flash_until:
		_material.albedo_color = HIT_COLOR
	elif view.is_invulnerable(params):
		_material.albedo_color = INVULNERABLE_COLOR
	else:
		_material.albedo_color = _base_color


## Sword pivot rotation: rest → wind up → strike through → back to rest.
static func _sword_pose(attack: AttackParams, attack_type: int, tick: float) -> Vector2:
	if attack == null:
		return SWORD_IDLE
	var wound := LIGHT_WOUND if attack_type == PlayerState.ATTACK_LIGHT else HEAVY_WOUND
	var struck := LIGHT_STRUCK if attack_type == PlayerState.ATTACK_LIGHT else HEAVY_STRUCK
	var windup := float(attack.windup_ticks)
	var strike_end := windup + attack.active_ticks
	if tick < windup:
		return SWORD_IDLE.lerp(wound, tick / maxf(windup, 1.0))
	if tick < strike_end:
		return wound.lerp(struck, (tick - windup) / attack.active_ticks)
	return struck.lerp(SWORD_IDLE, (tick - strike_end) / maxf(attack.recovery_ticks, 1.0))
