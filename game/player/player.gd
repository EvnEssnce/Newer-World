class_name Player
extends CharacterBody3D
## A player character. The same scene plays three roles:
##
## - Server: simulates one step per input received from its client.
## - Local client player: predicts from the keyboard immediately, then corrects
##   itself when a server snapshot disagrees (reconciliation).
## - Remote client player: drawn slightly in the past, interpolating between
##   server snapshots.
##
## Inputs are [seq: int, move: Vector2, buttons: int]. "move" is a world-space XZ
## direction with length <= 1, already rotated by the client's camera; "buttons"
## holds PlayerState.BUTTON_* bits.

const MAX_PENDING_INPUTS := 120
const MAX_SNAPSHOTS := 30
## Meters the server may differ from our prediction before we rewind and replay.
const RECONCILE_TOLERANCE := 0.01
const LOCAL_COLOR := Color(0.25, 0.55, 0.95)
const REMOTE_COLOR := Color(0.95, 0.55, 0.2)
## Body color while i-frames are active, so they're visible while tuning.
const INVULNERABLE_COLOR := Color(0.95, 0.95, 1.0)

var peer_id := 0
var is_local := false
var state := PlayerState.new()
var params := PlayerParams.current()
## Dodges started (counted once per real simulation step, not on replays).
var dodges := 0

# Server
var last_processed_seq := 0
var _input_queue: Array[Array] = []
var _last_queued_seq := 0

# Local client
var corrections := 0
var _next_seq := 1
var _pending_inputs: Array[Array] = []
var _predictions: Dictionary[int, Array] = {}  # seq -> [position, PlayerState] after that input
var _latest_ack: Array = []  # [pos, vel, seq, state array] from the newest snapshot
var _last_ack_seq := 0
var _camera_pivot: Node3D
var _spring_arm: SpringArm3D

# Remote client
var _snapshots: Array[Array] = []  # [server_time, pos, PlayerState]
var distance_seen := 0.0

var _material: StandardMaterial3D
var _base_color := REMOTE_COLOR

@onready var _model: Node3D = $Model
@onready var _roll_pivot: Node3D = $Model/RollPivot
@onready var _name_label: Label3D = $NameLabel


func _ready() -> void:
	state.stamina = params.max_stamina
	if multiplayer.is_server():
		_name_label.visible = false
		return
	_base_color = LOCAL_COLOR if is_local else REMOTE_COLOR
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	($Model/RollPivot/Body as MeshInstance3D).material_override = _material
	_name_label.text = "You" if is_local else "Player %d" % (peer_id % 10000)
	if is_local:
		_setup_camera()


func _process(_delta: float) -> void:
	if is_local:
		_show(state.yaw, state.dodge_progress(params), state.backstep,
				state.is_invulnerable(params))


func _simulate(move: Vector2, buttons: int, delta: float) -> void:
	PlayerMovement.step(self, state, move, buttons, params, delta)
	if state.dodge_tick == 0:
		dodges += 1


## Applies the facing, roll and i-frame look. Client only.
func _show(yaw: float, dodge_progress: float, is_backstep: bool, invulnerable: bool) -> void:
	_model.rotation.y = yaw
	# A full forward somersault over the roll (backward for a backstep).
	var roll := 0.0 if dodge_progress < 0.0 else TAU * dodge_progress
	_roll_pivot.rotation.x = roll if is_backstep else -roll
	_material.albedo_color = INVULNERABLE_COLOR if invulnerable else _base_color


# --- Server ---

func server_queue_inputs(inputs: Array, max_buffer: int) -> void:
	for input: Variant in inputs:
		if not (input is Array and input.size() == 3 and input[0] is int
				and input[1] is Vector2 and input[2] is int):
			continue
		var seq: int = input[0]
		var move: Vector2 = input[1]
		if seq <= _last_queued_seq or not move.is_finite():
			continue
		_input_queue.append([seq, move.limit_length(1.0), input[2] & PlayerState.ALL_BUTTONS])
		_last_queued_seq = seq
	while _input_queue.size() > max_buffer:
		_input_queue.pop_front()


## Runs at most max_per_tick queued inputs. With no input queued the player
## doesn't move, so server and client always simulate the same number of steps.
func server_process_inputs(max_per_tick: int, delta: float) -> void:
	for i in mini(max_per_tick, _input_queue.size()):
		var input: Array = _input_queue.pop_front()
		_simulate(input[1], input[2], delta)
		last_processed_seq = input[0]


func get_snapshot() -> Array:
	return [peer_id, global_position, velocity, last_processed_seq, state.to_array()]


# --- Local client ---

## Predicts one step from this tick's input and returns the inputs to send.
## move_input is camera-relative (x right, y back).
func client_predict(move_input: Vector2, buttons: int, delta: float, redundancy: int) -> Array:
	_reconcile(delta)
	var world := Vector3(move_input.x, 0.0, move_input.y).rotated(Vector3.UP, get_camera_yaw())
	var move := Vector2(world.x, world.z).limit_length(1.0)
	var input := [_next_seq, move, buttons]
	_next_seq += 1
	_pending_inputs.append(input)
	if _pending_inputs.size() > MAX_PENDING_INPUTS:
		_predictions.erase(_pending_inputs.pop_front()[0])
	_simulate(move, buttons, delta)
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
	while not _pending_inputs.is_empty() and _pending_inputs[0][0] <= ack_seq:
		_predictions.erase(_pending_inputs.pop_front()[0])
	if (predicted != null and server_pos.distance_to(predicted[0]) < RECONCILE_TOLERANCE
			and server_state.matches(predicted[1])):
		return

	if ack_seq > 0:  # seq 0 is just the initial sync to the spawn point
		corrections += 1
	global_position = server_pos
	velocity = server_vel
	state = server_state
	for input in _pending_inputs:
		PlayerMovement.step(self, state, input[1], input[2], params, delta)
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
	var progress := from_state.dodge_progress(params)
	if _snapshots.size() >= 2 and render_time > from[0]:
		var to: Array = _snapshots[1]
		var to_state: PlayerState = to[2]
		var weight: float = (render_time - from[0]) / (to[0] - from[0])
		new_pos = from[1].lerp(to[1], weight)
		yaw = lerp_angle(from_state.yaw, to_state.yaw, weight)
		if from_state.is_dodging() and to_state.dodge_tick > from_state.dodge_tick:
			progress = lerpf(progress, to_state.dodge_progress(params), weight)
	distance_seen += global_position.distance_to(new_pos)
	global_position = new_pos
	_show(yaw, progress, from_state.backstep, from_state.is_invulnerable(params))
