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
## Server only: emitted on the sim step an ability starts (not a parry counter).
signal ability_started(player: Player)
## Server only: emitted on the sim step a weapon swap starts.
signal weapon_swapped(player: Player)

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
## Nameplate colour of party members (others' are white).
const PARTY_NAME_COLOR := Color(0.45, 0.9, 1.0)
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
## Sword held out to the side for Whirlwind Edge, and across the body for Riposte.
const SWORD_SPIN := Vector2(0.0, -PI / 2.0)
const SWORD_PARRY := Vector2(0.3, 0.9)
## Axe pivot pitch at rest, raised, and at the end of a chop.
const AXE_IDLE := -0.9
const AXE_WOUND := 1.6
const AXE_STRUCK := -1.1
## Weapon pitch at the start of a swap (lowered), raised back to idle over the swap.
const WEAPON_LOWERED := -1.7
## Body color during a parry window.
const PARRY_COLOR := Color(0.55, 0.85, 1.0)
## Whirlwind Edge: radians the body winds back before spinning one full turn.
const SPIN_WINDBACK := 0.6
## Rising Cut: sword low at the side, then swept up high.
const RISING_WOUND := Vector2(-1.5, 0.4)
const RISING_STRUCK := Vector2(1.7, 0.0)
## Spear pivot pose: x = pitch (up), y = sweep (left), z = meters pulled back
## (negative = thrust forward).
const SPEAR_REST := Vector3(0.0, 0.0, 0.0)
const SPEAR_IDLE := Vector3(0.25, 0.0, 0.0)
const SPEAR_LIGHT_WOUND := Vector3(0.1, 0.0, 0.35)
const SPEAR_LIGHT_STRUCK := Vector3(0.0, 0.0, 0.0)  # z from the attack's range
const SPEAR_HEAVY_WOUND := Vector3(0.2, 0.0, 0.6)
const SPEAR_HEAVY_STRUCK := Vector3(-0.05, 0.0, 0.0)  # z from the attack's range
## Meters from the spear pivot to its tip (Head in player.tscn: z -1.86, 0.36
## long). A thrust pushes the pivot forward so the tip reaches the hitbox's range.
const SPEAR_TIP_DISTANCE := 2.04
## Low Sweep: low, swept from the right across to the left.
const SPEAR_SWEEP_WOUND := Vector3(-0.45, -1.3, 0.0)
const SPEAR_SWEEP_STRUCK := Vector3(-0.45, 1.3, 0.0)
## Vault: the tip planted on the ground in front.
const SPEAR_PLANTED := Vector3(-0.9, 0.0, -0.2)

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
## Light and heavy attacks started.
var attacks := 0
var abilities_used := 0
var swaps := 0

# Server
var last_processed_seq := 0
## The character's class, weapons and mastery (server only; see BuildService).
var build: CharacterBuild
## Targets the current hit window has already been resolved against:
## true = hit (can't be hit again), false = evaded so far (can still be hit).
## Cleared when a new attack or a new hit window (e.g. each Frenzy chop) starts.
var attack_results: Dictionary[int, bool] = {}
## [attack_serial, window] that attack_results belongs to.
var _results_key := Vector2i(-1, -1)
## On-hit statuses (Bloodlust's bleed) already taken for the current hit window:
## one charge per swing, given to every target that swing hits.
var _window_on_hit: Array[Vector2i] = []
var _window_on_hit_taken := false
## Server tick at which a dead player respawns.
var respawn_at_tick := -1
## Damage over time (bleed) from this tick's sim steps, not yet applied to
## health. World applies it after processing inputs.
var status_damage_pending := 0.0
var _input_queue: Array[Array] = []
var _last_queued_seq := 0

# Local client
var corrections := 0
var _last_equipped := 0
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
var _status_text := ""
var _hitbox_material: StandardMaterial3D
var _box_mesh: BoxMesh
var _radial_mesh: CylinderMesh

@onready var _model: Node3D = $Model
@onready var _roll_pivot: Node3D = $Model/RollPivot
@onready var _sword_pivot: Node3D = $Model/RollPivot/SwordPivot
@onready var _shield_pivot: Node3D = $Model/RollPivot/ShieldPivot
@onready var _axe_right_pivot: Node3D = $Model/RollPivot/AxeRightPivot
@onready var _axe_left_pivot: Node3D = $Model/RollPivot/AxeLeftPivot
@onready var _spear_pivot: Node3D = $Model/RollPivot/SpearPivot
@onready var _spear_rest_position: Vector3 = _spear_pivot.position
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
	_box_mesh = _hitbox_debug.mesh as BoxMesh
	_radial_mesh = CylinderMesh.new()
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
	var server := multiplayer.is_server()
	if state.attack_tick == 0:
		if state.is_using_ability():
			abilities_used += 1
			if server:
				ability_started.emit(self)
		else:
			attacks += 1
	if server and state.swap_tick == 0:
		swaps += 1
		weapon_swapped.emit(self)
	if server:
		status_damage_pending += state.status_damage
	var window := state.attack_window(params)
	if server and window >= 0:
		var key := Vector2i(state.attack_serial, window)
		if key != _results_key:
			_results_key = key
			attack_results.clear()
			_window_on_hit = []
			_window_on_hit_taken = false
		attack_stepped.emit(self)


# --- Server ---

## Server: the attacker's on-hit statuses for a damaging hit in the current hit
## window. The window's first damaging hit uses up the charges (e.g. one
## Bloodlust stack); other targets the same swing hits get the same statuses
## without using more, so a swing through a group doesn't burn every charge.
func on_hit_statuses_for_window() -> Array[Vector2i]:
	if not _window_on_hit_taken:
		_window_on_hit_taken = true
		_window_on_hit = state.take_on_hit_statuses(params)
	return _window_on_hit

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


## Server: the damage modifier from this player's mastery passives and
## upgrades for one of its attacks (or abilities).
func damage_multiplier(attack: AttackParams) -> float:
	if build == null or attack == null:
		return 1.0
	var kind := "heavy" if attack == state.weapon(params).heavy_attack else "light"
	var ability_id := ""
	if attack is AbilityParams:
		kind = "ability"
		ability_id = (attack as AbilityParams).id
	return build.damage_multiplier(state.weapon_id(), kind, ability_id, health / params.max_health)


## Server: the mastery modifier on the stamina this player's blocked hits cost.
func block_stamina_multiplier() -> float:
	return build.block_stamina_multiplier(state.weapon_id()) if build else 1.0


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
	# Counted here rather than in _simulate: a swap that only happens in a
	# reconcile replay (the server let it through sooner) still counts.
	if state.equipped != _last_equipped:
		swaps += 1
	_last_equipped = state.equipped
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


func _modal_ui_open() -> bool:
	for node in get_tree().get_nodes_in_group(&"modal_ui"):
		if node is CanvasItem and node.visible:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		# Clicks recapture the mouse, but not wheel scrolls (a scroll that a
		# panel's list didn't use falls through to here) or while a panel is open.
		var wheel: bool = event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
		if not wheel and not _modal_ui_open():
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
		if (from_state.is_attacking() and to_state.attack_serial == from_state.attack_serial
				and to_state.attack_tick > from_state.attack_tick):
			attack_tick = lerpf(from_state.attack_tick, to_state.attack_tick, weight)
	distance_seen += global_position.distance_to(new_pos)
	global_position = new_pos
	view_state = from_state
	_set_status_text(from_state.statuses.summary(params.statuses))
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
	if not _status_text.is_empty():
		_name_label.text += "\n" + _status_text


## The status line under a remote player's health ("Bleed x3, Slow"; client).
func _set_status_text(text: String) -> void:
	if text == _status_text:
		return
	_status_text = text
	_update_label()


## Nameplate colour for players in your party (client, cosmetic). Set by
## PartySystem every frame.
func set_party_member(member: bool) -> void:
	_name_label.modulate = PARTY_NAME_COLOR if member else Color.WHITE


## Applies facing, roll, stagger/death pose, weapon model and swing, hitbox and
## color. Client only, placeholder animation. view supplies the discrete state
## (attack type, ability, weapon, dead, staggered, i-frames, parry); yaw,
## dodge_progress and attack_tick may be interpolated, and attack_tick is -1
## when not attacking.
func _show(view: PlayerState, yaw: float, dodge_progress: float, attack_tick: float) -> void:
	var attack := view.attack_params(params) if attack_tick >= 0.0 else null
	var ability := attack as AbilityParams
	var ability_id := ability.id if ability else ""

	var spin := 0.0
	if ability_id == "whirlwind_edge":
		spin = _spin_offset(ability, attack_tick)
	var lift := 0.0
	if ability and ability.leap_height > 0.0 and ability.dash_speed > 0.0:
		var p := inverse_lerp(float(ability.dash_start_tick), float(ability.dash_end_tick), attack_tick)
		if p >= 0.0 and p <= 1.0:
			lift = 4.0 * ability.leap_height * p * (1.0 - p)
	_model.rotation.y = yaw + spin
	_model.position.y = lift
	if view.dead:
		_roll_pivot.rotation.x = -PI / 2.0  # face down on the ground
		_roll_pivot.position.y = BODY_RADIUS
	else:
		_roll_pivot.position.y = BODY_HEIGHT / 2.0
		if dodge_progress >= 0.0:
			_roll_pivot.rotation.x = -TAU * dodge_progress  # a full forward somersault
		elif view.is_staggered() or view.is_forced():
			_roll_pivot.rotation.x = STAGGER_TILT
		else:
			_roll_pivot.rotation.x = 0.0

	var model := view.weapon(params).model
	var axes := model == "dual_axes"
	var spear := model == "spear"
	_sword_pivot.visible = not axes and not spear
	_shield_pivot.visible = not axes and not spear
	_axe_right_pivot.visible = axes
	_axe_left_pivot.visible = axes
	_spear_pivot.visible = spear
	var shield_up := view.blocking or ability_id in ["shield_charge", "riposte"]
	_shield_pivot.position = SHIELD_RAISED if shield_up else SHIELD_REST
	_shield_pivot.rotation.y = 0.0 if shield_up else SHIELD_REST_YAW
	# A swap starts with the (new) weapon lowered and raises it.
	var lowered := 1.0 - view.swap_tick / float(params.swap_ticks) if view.is_swapping() else 0.0
	if axes:
		var pitches := _axe_pitches(attack, view.attack_type, ability_id, attack_tick)
		_axe_right_pivot.rotation.x = lerpf(pitches.x, WEAPON_LOWERED, lowered)
		_axe_left_pivot.rotation.x = lerpf(pitches.y, WEAPON_LOWERED, lowered)
	elif spear:
		var spear_pose := _spear_pose(attack, view.attack_type, ability_id, attack_tick)
		_spear_pivot.rotation = Vector3(lerpf(spear_pose.x, WEAPON_LOWERED, lowered), spear_pose.y, 0.0)
		_spear_pivot.position = _spear_rest_position + Vector3(0.0, 0.0, spear_pose.z)
	else:
		var pose := _sword_pose(attack, view.attack_type, ability_id, attack_tick)
		_sword_pivot.rotation = Vector3(lerpf(pose.x, WEAPON_LOWERED, lowered), pose.y, 0.0)

	_show_hitbox(attack, attack_tick)

	if view.dead:
		_material.albedo_color = DEAD_COLOR
	elif Time.get_ticks_msec() < _hit_flash_until:
		_material.albedo_color = HIT_COLOR
	elif view.is_invulnerable(params):
		_material.albedo_color = INVULNERABLE_COLOR
	elif view.is_parrying(params):
		_material.albedo_color = PARRY_COLOR
	else:
		_material.albedo_color = _base_color


func _show_hitbox(attack: AttackParams, attack_tick: float) -> void:
	_hitbox_debug.visible = (show_hitboxes and attack != null
			and attack.shape != AttackParams.SHAPE_NONE)
	if not _hitbox_debug.visible:
		return
	if attack.shape == AttackParams.SHAPE_RADIAL:
		_hitbox_debug.mesh = _radial_mesh
		_radial_mesh.top_radius = attack.hitbox_range
		_radial_mesh.bottom_radius = attack.hitbox_range
		_radial_mesh.height = attack.hitbox_height
		_hitbox_debug.position = Vector3(0.0, attack.hitbox_height / 2.0, 0.0)
	else:
		_hitbox_debug.mesh = _box_mesh
		_box_mesh.size = Vector3(attack.hitbox_width, attack.hitbox_height, attack.hitbox_range)
		_hitbox_debug.position = Vector3(0.0, attack.hitbox_height / 2.0, -attack.hitbox_range / 2.0)
	var active := attack.window_at(floori(attack_tick)) >= 0
	_hitbox_material.albedo_color = Color(1.0, 0.2, 0.2, 0.45 if active else 0.1)


## Whirlwind Edge: winds back during the windup, one full turn over the active
## phase.
static func _spin_offset(ability: AbilityParams, tick: float) -> float:
	var windup := float(ability.windup_ticks)
	if tick < windup:
		return SPIN_WINDBACK * tick / maxf(windup, 1.0)
	var spin_ticks := float(ability.recovery_start_tick() - ability.windup_ticks)
	return SPIN_WINDBACK - (SPIN_WINDBACK + TAU) * minf(1.0, (tick - windup) / maxf(spin_ticks, 1.0))


## Rest → wound (over the windup) → struck (over the hit windows) → rest (over
## the recovery).
static func _phase_pose(attack: AttackParams, tick: float, rest: Vector2, wound: Vector2,
		struck: Vector2) -> Vector2:
	var windup := float(attack.windup_ticks)
	var strike_end := float(attack.recovery_start_tick())
	if tick < windup:
		return rest.lerp(wound, tick / maxf(windup, 1.0))
	if tick < strike_end:
		return wound.lerp(struck, (tick - windup) / maxf(strike_end - windup, 1.0))
	return struck.lerp(rest, (tick - strike_end) / maxf(attack.recovery_ticks, 1.0))


## Sword pivot rotation (x = pitch, y = sweep).
static func _sword_pose(attack: AttackParams, attack_type: int, ability_id: String,
		tick: float) -> Vector2:
	if attack == null:
		return SWORD_IDLE
	match ability_id:
		"whirlwind_edge":
			return _phase_pose(attack, tick, SWORD_IDLE, SWORD_SPIN, SWORD_SPIN)
		"shield_charge":
			return SWORD_IDLE
		"riposte":
			return _phase_pose(attack, tick, SWORD_IDLE, SWORD_PARRY, SWORD_PARRY)
		"rising_cut":
			return _phase_pose(attack, tick, SWORD_IDLE, RISING_WOUND, RISING_STRUCK)
	if attack_type == PlayerState.ATTACK_HEAVY or ability_id == "opening_strike":
		return _phase_pose(attack, tick, SWORD_IDLE, HEAVY_WOUND, HEAVY_STRUCK)
	return _phase_pose(attack, tick, SWORD_IDLE, LIGHT_WOUND, LIGHT_STRUCK)


## Spear pivot pose (see SPEAR_IDLE): thrusts for light, heavy and Lunge, a low
## sweep for Low Sweep, planted for Vault.
static func _spear_pose(attack: AttackParams, attack_type: int, ability_id: String,
		tick: float) -> Vector3:
	if attack == null:
		return SPEAR_IDLE
	match ability_id:
		"low_sweep":
			return _phase_pose3(attack, tick, SPEAR_IDLE, SPEAR_SWEEP_WOUND, SPEAR_SWEEP_STRUCK)
		"vault":
			return _phase_pose3(attack, tick, SPEAR_IDLE, SPEAR_PLANTED, SPEAR_PLANTED)
	# Thrusts: the tip goes as far as the hitbox reaches, so a longer range is a
	# longer thrust.
	var thrust := Vector3(0.0, 0.0, -maxf(0.0, attack.hitbox_range - SPEAR_TIP_DISTANCE))
	if attack_type == PlayerState.ATTACK_LIGHT:
		return _phase_pose3(attack, tick, SPEAR_IDLE, SPEAR_LIGHT_WOUND, SPEAR_LIGHT_STRUCK + thrust)
	return _phase_pose3(attack, tick, SPEAR_IDLE, SPEAR_HEAVY_WOUND, SPEAR_HEAVY_STRUCK + thrust)


## _phase_pose for a Vector3 pose.
static func _phase_pose3(attack: AttackParams, tick: float, rest: Vector3, wound: Vector3,
		struck: Vector3) -> Vector3:
	var windup := float(attack.windup_ticks)
	var strike_end := float(attack.recovery_start_tick())
	if tick < windup:
		return rest.lerp(wound, tick / maxf(windup, 1.0))
	if tick < strike_end:
		return wound.lerp(struck, (tick - windup) / maxf(strike_end - windup, 1.0))
	return struck.lerp(rest, (tick - strike_end) / maxf(attack.recovery_ticks, 1.0))


## Axe pivot pitches (x = right axe, y = left axe). Light: the right axe chops;
## heavy and Crashing Leap: both; Frenzy: they take turns.
static func _axe_pitches(attack: AttackParams, attack_type: int, ability_id: String,
		tick: float) -> Vector2:
	if attack == null:
		return Vector2(AXE_IDLE, AXE_IDLE)
	var rest := Vector2(AXE_IDLE, 0.0)
	var chop := _phase_pose(attack, tick, rest, Vector2(AXE_WOUND, 0.0), Vector2(AXE_STRUCK, 0.0)).x
	if ability_id == "frenzy":
		return _frenzy_pitches(attack, tick, chop)
	if ability_id == "bloodlust":
		# Both axes raised high, then lowered.
		var raised := _phase_pose(attack, tick, rest, Vector2(AXE_WOUND, 0.0), Vector2(AXE_WOUND, 0.0)).x
		return Vector2(raised, raised)
	if attack_type == PlayerState.ATTACK_LIGHT or ability_id == "hamstring":
		return Vector2(chop, AXE_IDLE)
	return Vector2(chop, chop)


## Frenzy: each hit window is one axe chopping (right, left, right, left)
## while the other is held up ready.
static func _frenzy_pitches(attack: AttackParams, tick: float, chop: float) -> Vector2:
	var since := tick - attack.windup_ticks
	if since < 0.0 or tick >= attack.recovery_start_tick():
		return Vector2(chop, chop)
	var interval := float(attack.window_interval_ticks)
	var index := floori(since / interval)
	var into := since - index * interval
	var pitch := lerpf(AXE_WOUND, AXE_STRUCK, minf(1.0, into / attack.active_ticks))
	if into > attack.active_ticks:
		pitch = lerpf(AXE_STRUCK, AXE_WOUND,
				(into - attack.active_ticks) / maxf(interval - attack.active_ticks, 1.0))
	return Vector2(pitch, AXE_WOUND) if index % 2 == 0 else Vector2(AXE_WOUND, pitch)


