class_name Player
extends CharacterBody3D
## A player character. The same scene plays three roles:
##
## - Server: simulates one movement step per input received from its client.
## - Local client player: predicts movement from the keyboard immediately, then
##   corrects itself when a server snapshot arrives (reconciliation).
## - Remote client player: drawn slightly in the past, interpolating between
##   server snapshots.
##
## Inputs are [seq: int, move: Vector2, jump: bool]. "move" is a world-space XZ
## direction with length <= 1, already rotated by the client's camera.

const MAX_PENDING_INPUTS := 120
const MAX_SNAPSHOTS := 30
## Meters the server may differ from our prediction before we rewind and replay.
const RECONCILE_TOLERANCE := 0.01
const LOCAL_COLOR := Color(0.25, 0.55, 0.95)
const REMOTE_COLOR := Color(0.95, 0.55, 0.2)

var peer_id := 0
var is_local := false
## Facing direction. Visual only: it rotates the model, never the collision.
var yaw := 0.0

# Server
var last_processed_seq := 0
var _input_queue: Array[Array] = []
var _last_queued_seq := 0

# Local client
var corrections := 0
var _next_seq := 1
var _pending_inputs: Array[Array] = []
var _predicted_positions: Dictionary[int, Vector3] = {}  # seq -> position after that input
var _latest_ack: Array = []  # [pos, vel, seq] from the newest snapshot, applied next tick
var _last_ack_seq := 0
var _camera_pivot: Node3D
var _spring_arm: SpringArm3D

# Remote client
var _snapshots: Array[Array] = []  # [server_time, pos, yaw]
var distance_seen := 0.0

@onready var _model: Node3D = $Model
@onready var _body_mesh: MeshInstance3D = $Model/Body
@onready var _name_label: Label3D = $NameLabel


func _ready() -> void:
	if multiplayer.is_server():
		_name_label.visible = false
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = LOCAL_COLOR if is_local else REMOTE_COLOR
	_body_mesh.material_override = material
	_name_label.text = "You" if is_local else "Player %d" % (peer_id % 10000)
	if is_local:
		_setup_camera()


func _apply_input(move: Vector2, jump: bool, delta: float) -> void:
	PlayerMovement.step(self, move, jump, delta)
	if move.length_squared() > 0.01:
		var turn_speed := deg_to_rad(Tuning.get_value("movement", "player", "turn_speed"))
		yaw = rotate_toward(yaw, PlayerMovement.yaw_for_direction(move), turn_speed * delta)
	_model.rotation.y = yaw


# --- Server ---

func server_queue_inputs(inputs: Array, max_buffer: int) -> void:
	for input: Variant in inputs:
		if not (input is Array and input.size() == 3 and input[0] is int
				and input[1] is Vector2 and input[2] is bool):
			continue
		var seq: int = input[0]
		var move: Vector2 = input[1]
		if seq <= _last_queued_seq or not move.is_finite():
			continue
		_input_queue.append([seq, move.limit_length(1.0), input[2]])
		_last_queued_seq = seq
	while _input_queue.size() > max_buffer:
		_input_queue.pop_front()


## Runs at most max_per_tick queued inputs. With no input queued the player
## doesn't move, so server and client always simulate the same number of steps.
func server_process_inputs(max_per_tick: int, delta: float) -> void:
	for i in mini(max_per_tick, _input_queue.size()):
		var input: Array = _input_queue.pop_front()
		_apply_input(input[1], input[2], delta)
		last_processed_seq = input[0]


func get_state() -> Array:
	return [peer_id, global_position, velocity, yaw, last_processed_seq]


# --- Local client ---

## Reads input, predicts one step and returns the inputs to send to the server.
func client_predict(move_input: Vector2, jump: bool, delta: float, redundancy: int) -> Array:
	_reconcile(delta)
	# Turn the camera-relative stick into a world-space direction.
	var world := Vector3(move_input.x, 0.0, move_input.y).rotated(Vector3.UP, get_camera_yaw())
	var move := Vector2(world.x, world.z).limit_length(1.0)
	var input := [_next_seq, move, jump]
	_next_seq += 1
	_pending_inputs.append(input)
	if _pending_inputs.size() > MAX_PENDING_INPUTS:
		_predicted_positions.erase(_pending_inputs.pop_front()[0])
	_apply_input(move, jump, delta)
	_predicted_positions[input[0]] = global_position
	return _pending_inputs.slice(-redundancy)


func client_receive_ack(pos: Vector3, vel: Vector3, ack_seq: int) -> void:
	if ack_seq < _last_ack_seq:
		return
	_last_ack_seq = ack_seq
	_latest_ack = [pos, vel, ack_seq]


## If the server disagrees with where we predicted we'd be after its last
## processed input, rewinds to the server's state and replays every input it
## hasn't processed yet.
func _reconcile(delta: float) -> void:
	if _latest_ack.is_empty():
		return
	var server_pos: Vector3 = _latest_ack[0]
	var server_vel: Vector3 = _latest_ack[1]
	var ack_seq: int = _latest_ack[2]
	_latest_ack = []
	var predicted: Variant = _predicted_positions.get(ack_seq)
	while not _pending_inputs.is_empty() and _pending_inputs[0][0] <= ack_seq:
		_predicted_positions.erase(_pending_inputs.pop_front()[0])
	if predicted != null and server_pos.distance_to(predicted) < RECONCILE_TOLERANCE:
		return

	if ack_seq > 0:  # seq 0 is just the initial sync to the spawn point
		corrections += 1
	global_position = server_pos
	velocity = server_vel
	for input in _pending_inputs:
		PlayerMovement.step(self, input[1], input[2], delta)
		_predicted_positions[input[0]] = global_position


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

func push_snapshot(server_time: float, pos: Vector3, snapshot_yaw: float) -> void:
	if _snapshots.is_empty():
		global_position = pos
	_snapshots.append([server_time, pos, snapshot_yaw])
	if _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


func interpolate(render_time: float) -> void:
	if _snapshots.is_empty():
		return
	while _snapshots.size() >= 2 and _snapshots[1][0] <= render_time:
		_snapshots.pop_front()
	var from: Array = _snapshots[0]
	var new_pos: Vector3 = from[1]
	var new_yaw: float = from[2]
	if _snapshots.size() >= 2 and render_time > from[0]:
		var to: Array = _snapshots[1]
		var weight: float = (render_time - from[0]) / (to[0] - from[0])
		new_pos = from[1].lerp(to[1], weight)
		new_yaw = lerp_angle(from[2], to[2], weight)
	distance_seen += global_position.distance_to(new_pos)
	global_position = new_pos
	yaw = new_yaw
	_model.rotation.y = yaw
