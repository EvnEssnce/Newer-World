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
## Inputs are [seq: int, move: Vector2, buttons: int, aim_yaw: float,
## aim_pitch: float]. "move" is a world-space XZ direction with length <= 1,
## already rotated by the client's camera; "buttons" holds PlayerState.BUTTON_*
## bits; "aim_yaw" and "aim_pitch" are the camera's yaw and pitch (up = positive).

## Server only: emitted after each sim step in which an attack's hitbox is live.
signal attack_stepped(player: Player)
## Server only: emitted on the sim step an ability starts (not a parry counter).
signal ability_started(player: Player)
## Server only: emitted on the sim step a weapon swap starts.
signal weapon_swapped(player: Player)
## Server only: the step that finished putting on or taking off gear
## (PlayerState.equip_left reached 0); LootSystem applies the change.
signal equip_finished(player: Player)
## Server, and the local client's own prediction (not replays): emitted on the
## sim step an attack releases its projectiles (AttackParams.projectile_tick).
## The server throws the real ones; the local client shows a cosmetic copy.
signal projectile_released(player: Player)
## Server: a roll started this step (the Ranger's Parting Shot capstone).
signal dodged(player: Player)

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
## Sword pivot pose (x = pitch, y = sweep, z = meters pulled back, negative =
## thrust forward) at rest and at each swing's extremes.
const SWORD_IDLE := Vector3(-0.7, 0.0, 0.0)
const LIGHT_WOUND := Vector3(0.0, -1.4, 0.0)
const LIGHT_STRUCK := Vector3(0.0, 1.4, 0.0)
const HEAVY_WOUND := Vector3(1.7, 0.0, 0.0)
const HEAVY_STRUCK := Vector3(-1.3, 0.0, 0.0)
## Sword held out to the side for Whirlwind Edge, and across the body for Riposte.
const SWORD_SPIN := Vector3(0.0, -PI / 2.0, 0.0)
const SWORD_PARRY := Vector3(0.3, 0.9, 0.0)
## Opening Strike: pointed forward and drawn back, then thrust out. Diving
## Strike: the same, angled down at what it lands on.
const SWORD_THRUST_WOUND := Vector3(0.05, 0.0, 0.35)
const SWORD_THRUST_STRUCK := Vector3(0.0, 0.0, -0.6)
const SWORD_DIVE_WOUND := Vector3(0.1, 0.0, 0.35)
const SWORD_DIVE_STRUCK := Vector3(-0.6, 0.0, -0.5)
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
const RISING_WOUND := Vector3(-1.5, 0.4, 0.0)
const RISING_STRUCK := Vector3(1.7, 0.0, 0.0)
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
## Phoenix placeholder look: wing color, the Rebirth's fire, and the body's
## glow as it rises. Wings show during Wing abilities and Rebirth.
const WING_COLOR := Color(1.0, 0.5, 0.12, 0.85)
const REBIRTH_FIRE_COLOR := Color(1.0, 0.45, 0.08, 0.55)
const REBIRTH_GLOW_COLOR := Color(1.0, 0.6, 0.2)
## Meters the Rebirth's fire column reaches at its peak.
const REBIRTH_FIRE_HEIGHT := 2.6
## Wing angle (radians, up from horizontal) folded and fully spread.
const WING_FOLDED := -0.9
const WING_SPREAD := 0.5

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
## Max health from gear (Hearth); in snapshots, so clients draw the right bar.
var bonus_max_health := 0.0
## Server: what this player's equipped gear adds up to (LootSystem sets it).
var gear := Equipment.Stats.new()
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
## Hold the Line (World._hold_the_line): target ids inside the poke's reach
## last tick, and per target the server tick it can be poked again.
var line_inside: Dictionary[int, bool] = {}
var line_ready_at: Dictionary[int, int] = {}
## Damage over time (bleed) from this tick's sim steps, not yet applied to
## health. World applies it after processing inputs.
var status_damage_pending := 0.0
## Healing over time (Pyre Heart) from this tick's sim steps, not yet applied.
var status_heal_pending := 0.0
## Server: War Hammer heavies counted for the Earthshaker capstone.
var heavy_counter := HeavyCounter.new()
## Server: counts this player's knife throws (light and heavy) for the Throwing
## Knives' Flurry capstone ("knife_flurry").
var throw_counter := HeavyCounter.new()
## Server: server_tick of this player's last light or heavy projectile release
## (the Crossbow's Siege capstone, "loaded_chamber"); -1 = none yet.
var last_release_tick := -1
## Server: the player whose knockback is moving this one and who has the
## Tempest Wings capstone (a wall hit stuns), or 0.
var wall_stun_source := 0
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
## Placeholder phoenix visuals, built in code (client): two wing pivots and
## the Rebirth's fire column.
var _wing_pivots: Array[Node3D] = []
var _rebirth_fire: MeshInstance3D
var _rebirth_mesh: CylinderMesh
## Placeholder War Hammer, built in code (client; _build_hammer_model).
var _hammer_pivot: Node3D

@onready var _model: Node3D = $Model
@onready var _roll_pivot: Node3D = $Model/RollPivot
@onready var _sword_pivot: Node3D = $Model/RollPivot/SwordPivot
@onready var _shield_pivot: Node3D = $Model/RollPivot/ShieldPivot
@onready var _axe_right_pivot: Node3D = $Model/RollPivot/AxeRightPivot
@onready var _axe_left_pivot: Node3D = $Model/RollPivot/AxeLeftPivot
@onready var _spear_pivot: Node3D = $Model/RollPivot/SpearPivot
@onready var _spear_rest_position: Vector3 = _spear_pivot.position
@onready var _sword_rest_position: Vector3 = _sword_pivot.position
var _axe_thrown := false
@onready var _hitbox_debug: MeshInstance3D = $Model/HitboxDebug
@onready var _name_label: Label3D = $NameLabel


func _ready() -> void:
	state.stamina = params.max_stamina
	state.ember = params.ember_resting
	health = max_health()
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
	_build_phoenix_visuals()
	_build_halberd_greataxe()
	_build_hammer_model()
	_build_assassin_models()
	_build_ranger_models()
	_update_label()
	if is_local:
		_setup_camera()


func _process(_delta: float) -> void:
	if is_local:
		_show(state, state.yaw, state.dodge_progress(params), state.attack_tick)


func _simulate(move: Vector2, buttons: int, aim_yaw: float, aim_pitch: float, delta: float) -> void:
	var was_on_floor := is_on_floor()
	var was_equipping := state.is_equipping()
	PlayerMovement.step(self, state, move, buttons, aim_yaw, params, delta, aim_pitch)
	if state.dodge_tick == 0:
		dodges += 1
		if multiplayer.is_server():
			dodged.emit(self)
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
	var current := state.current_attack(params)
	if current and current.releases_projectile_at(state.attack_tick):
		projectile_released.emit(self)
	if server and state.swap_tick == 0:
		swaps += 1
		weapon_swapped.emit(self)
	if server and was_equipping and not state.is_equipping() and not state.dead:
		equip_finished.emit(self)
	if server:
		status_damage_pending += state.status_damage
		status_heal_pending += state.status_heal
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
		if not (input is Array and input.size() == 5 and input[0] is int
				and input[1] is Vector2 and input[2] is int and input[3] is float
				and input[4] is float):
			continue
		var seq: int = input[0]
		var move: Vector2 = input[1]
		var aim_yaw: float = input[3]
		var aim_pitch: float = input[4]
		if (seq <= _last_queued_seq or not move.is_finite() or not is_finite(aim_yaw)
				or not is_finite(aim_pitch)):
			continue
		if verbose and seq != _last_queued_seq + 1 and _last_queued_seq > 0:
			print("[server] peer %d inputs %d-%d never arrived" % [peer_id, _last_queued_seq + 1, seq - 1])
		_input_queue.append([seq, move.limit_length(1.0), input[2] & PlayerState.ALL_BUTTONS,
				aim_yaw, clampf(aim_pitch, -PI / 2.0, PI / 2.0)])
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
		_simulate(input[1], input[2], input[3], input[4], delta)
		last_processed_seq = input[0]


func get_snapshot() -> Array:
	# Health and max health in one Vector2: the same size as a float health alone
	# (snapshots are near the MTU).
	return [peer_id, global_position, velocity, last_processed_seq, state.to_array(),
			Vector2(health, max_health())]


## Base max health plus gear's.
func max_health() -> float:
	return params.max_health + bonus_max_health


## Server: the damage modifier from this player's mastery passives and
## upgrades and gear (the weapon's weapon power, or the Wing Enhancement's wing
## power for a Wing ability, times Blaze) for one of its attacks (or abilities).
func damage_multiplier(attack: AttackParams) -> float:
	if build == null or attack == null:
		return 1.0
	var kind := _attack_kind(attack)
	# A Wing ability only gets the Wing tree's modifiers.
	var weapon_id := "" if state.is_using_wing() else state.weapon_id()
	var power := gear.wing_power if state.is_using_wing() else gear.weapon_power_for(weapon_id)
	return (build.damage_multiplier(weapon_id, kind[0], kind[1], health / max_health())
			* power * (1.0 + gear.bonus("damage_pct")))


## Server: the gear score this player's hits count as against armor: the
## weapon that's out (the Wing Enhancement's during a Wing ability), or the
## base gear score without an item.
func attack_gear_score(base: int) -> int:
	if state.is_using_wing():
		return gear.wing_gear_score if gear.wing_gear_score > 0 else base
	return gear.weapon_gear_score_for(state.weapon_id(), base)


## "light", "heavy" or "ability": what kind of attack this is for this
## player's weapon out (as the mastery trees name them).
func attack_kind(attack: AttackParams) -> String:
	return _attack_kind(attack)[0]


## [attack kind ("light", "heavy" or "ability"), ability id] of one of this
## player's attacks, as the mastery trees name them.
func _attack_kind(attack: AttackParams) -> PackedStringArray:
	if attack is AbilityParams:
		return PackedStringArray(["ability", (attack as AbilityParams).id])
	var heavy := attack == state.weapon(params).heavy_attack
	return PackedStringArray(["heavy" if heavy else "light", ""])


## Server: the crit multiplier (Headsman, Predator: [crit] in data/combat.cfg)
## of the weapon tree that's out for this attack on a target that was (or
## wasn't) staggered before the hit, and is (or isn't) a backstab; 1 = no crit
## (and always during a Wing ability).
func crit_multiplier(attack: AttackParams, target_staggered: bool, backstab := false) -> float:
	if build == null or attack == null or state.is_using_wing():
		return 1.0
	var kind := _attack_kind(attack)
	return build.crit_multiplier(state.weapon_id(), kind[0], kind[1], target_staggered,
			params.crit_damage_multiplier, backstab)


## Server: the weapon tree's damage multiplier for this attack when it's a
## backstab (Backstab passives); 1 otherwise or during a Wing ability.
func backstab_multiplier(attack: AttackParams) -> float:
	if build == null or attack == null or state.is_using_wing():
		return 1.0
	var kind := _attack_kind(attack)
	return build.backstab_multiplier(state.weapon_id(), kind[0], kind[1])


## Server: the execute bonus (Finishing Thrust) of the weapon that's out, as
## (amount, threshold) for MasteryTree.execute_multiplier; zero during a Wing
## ability.
func execute_bonus() -> Vector2:
	if build == null or state.is_using_wing():
		return Vector2.ZERO
	return build.execute_bonus(state.weapon_id())


## Server: the mastery modifier on the stamina this player's blocked hits cost.
func block_stamina_multiplier() -> float:
	var gear_cut := maxf(0.0, 1.0 - gear.bonus("block_stamina_reduction"))
	return (build.block_stamina_multiplier(state.weapon_id()) if build else 1.0) * gear_cut


## Server: the Wing tree's modifier on damage this player takes.
func damage_taken_multiplier() -> float:
	return build.damage_taken_multiplier() if build else 1.0


# --- Local client ---

## Predicts one step from this tick's input and returns the inputs to send.
## move_input is camera-relative (x right, y back).
func client_predict(move_input: Vector2, buttons: int, aim_yaw: float, aim_pitch: float,
		delta: float, redundancy: int) -> Array:
	_reconcile(delta)
	var world := Vector3(move_input.x, 0.0, move_input.y).rotated(Vector3.UP, get_camera_yaw())
	var move := Vector2(world.x, world.z).limit_length(1.0)
	var input := [_next_seq, move, buttons, aim_yaw, aim_pitch]
	_next_seq += 1
	_pending_inputs.append(input)
	if _pending_inputs.size() > MAX_PENDING_INPUTS:
		_predictions.erase(_pending_inputs.pop_front()[0])
	_simulate(move, buttons, aim_yaw, aim_pitch, delta)
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
		PlayerMovement.step(self, state, input[1], input[2], input[3], params, delta, input[4])
		_predictions[input[0]] = [global_position, state.copy()]


func get_camera_yaw() -> float:
	return _camera_pivot.rotation.y if _camera_pivot else 0.0


## Radians, up = positive (the camera below the player looking up).
func get_camera_pitch() -> float:
	return _spring_arm.rotation.x if _spring_arm else 0.0


## Test bot screenshots: turn the camera to look where the bot aims.
func set_camera_yaw(yaw: float) -> void:
	if _camera_pivot:
		_camera_pivot.rotation.y = yaw


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


## True while one of this player's thrown axes is in flight: the right hand's
## axe is hidden (client, cosmetic). Set by ProjectileSystem every frame.
func set_axe_thrown(thrown: bool) -> void:
	_axe_thrown = thrown


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
	if ability_id in ["whirlwind_edge", "vortex", "talon_spin"]:
		spin = _spin_offset(ability, attack_tick)
	var lift := ability.leap_lift(attack_tick) if ability else 0.0
	_model.rotation.y = yaw + spin
	_model.position.y = lift
	if view.dead:
		# Face down on the ground; a Rebirth stands the body back up at the end.
		var rise := _rebirth_rise(view)
		_roll_pivot.rotation.x = -PI / 2.0 * (1.0 - rise)
		_roll_pivot.position.y = lerpf(BODY_RADIUS, BODY_HEIGHT / 2.0, rise)
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
	var polearm_or_greataxe := model in ["halberd", "greataxe"]
	var own_model := polearm_or_greataxe or model in ASSASSIN_MODELS or model in RANGER_MODELS
	_sword_pivot.visible = not axes and not spear and not own_model
	_shield_pivot.visible = not axes and not spear and not own_model
	_axe_right_pivot.visible = axes and not _axe_thrown
	_axe_left_pivot.visible = axes
	_spear_pivot.visible = spear
	var shield_up := view.blocking or ability_id in ["shield_charge", "riposte", "shield_wall"]
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
		_sword_pivot.position = _sword_rest_position + Vector3(0.0, 0.0, pose.z)
	_show_halberd_greataxe(model, view, attack, ability_id, attack_tick, lowered)
	_show_hammer(model == "war_hammer", attack, view.attack_type, ability_id, attack_tick, lowered)
	_show_assassin(model, attack, view.attack_type, ability_id, attack_tick, lowered)
	_show_ranger(model, attack, attack_tick, lowered)

	_show_hitbox(attack, attack_tick)
	_show_phoenix(view, attack, attack_tick)

	if view.dead:
		var progress := view.rebirth_progress(params)
		_material.albedo_color = (DEAD_COLOR.lerp(REBIRTH_GLOW_COLOR, progress) if progress >= 0.0
				else DEAD_COLOR)
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


## Sword pivot pose (see SWORD_IDLE): thrusts for Opening Strike and Diving
## Strike.
static func _sword_pose(attack: AttackParams, attack_type: int, ability_id: String,
		tick: float) -> Vector3:
	if attack == null:
		return SWORD_IDLE
	match ability_id:
		"whirlwind_edge":
			return _phase_pose3(attack, tick, SWORD_IDLE, SWORD_SPIN, SWORD_SPIN)
		"shield_charge":
			return SWORD_IDLE
		"riposte", "shield_wall":
			return _phase_pose3(attack, tick, SWORD_IDLE, SWORD_PARRY, SWORD_PARRY)
		"rising_cut":
			return _phase_pose3(attack, tick, SWORD_IDLE, RISING_WOUND, RISING_STRUCK)
		"opening_strike":
			return _phase_pose3(attack, tick, SWORD_IDLE, SWORD_THRUST_WOUND, SWORD_THRUST_STRUCK)
		"diving_strike":
			return _phase_pose3(attack, tick, SWORD_IDLE, SWORD_DIVE_WOUND, SWORD_DIVE_STRUCK)
	if attack_type == PlayerState.ATTACK_HEAVY:
		return _phase_pose3(attack, tick, SWORD_IDLE, HEAVY_WOUND, HEAVY_STRUCK)
	return _phase_pose3(attack, tick, SWORD_IDLE, LIGHT_WOUND, LIGHT_STRUCK)


## Spear pivot pose (see SPEAR_IDLE): thrusts for light, heavy, Lunge and
## Skewer, repeated thrusts for Perforate, a low sweep for Low Sweep, planted
## for Vault.
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
	if ability_id == "perforate":
		return _repeated_thrust_pose(attack, tick, SPEAR_LIGHT_STRUCK + thrust)
	if attack_type == PlayerState.ATTACK_LIGHT:
		return _phase_pose3(attack, tick, SPEAR_IDLE, SPEAR_LIGHT_WOUND, SPEAR_LIGHT_STRUCK + thrust)
	return _phase_pose3(attack, tick, SPEAR_IDLE, SPEAR_HEAVY_WOUND, SPEAR_HEAVY_STRUCK + thrust)


## Perforate: a light thrust in each hit window, drawing back between them.
static func _repeated_thrust_pose(attack: AttackParams, tick: float, struck: Vector3) -> Vector3:
	var since := tick - attack.windup_ticks
	if since < 0.0 or tick >= attack.recovery_start_tick():
		return _phase_pose3(attack, tick, SPEAR_IDLE, SPEAR_LIGHT_WOUND, struck)
	var interval := float(attack.window_interval_ticks)
	var into := since - floorf(since / interval) * interval
	if into <= attack.active_ticks:
		return SPEAR_LIGHT_WOUND.lerp(struck, into / maxf(attack.active_ticks, 1.0))
	return struck.lerp(SPEAR_LIGHT_WOUND,
			(into - attack.active_ticks) / maxf(interval - attack.active_ticks, 1.0))


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


## Axe pivot pitches (x = right axe, y = left axe). Light, Hamstring and
## Boomerang Axe (it throws the right one): the right axe chops;
## heavy and Crashing Leap: both; Frenzy: they take turns.
static func _axe_pitches(attack: AttackParams, attack_type: int, ability_id: String,
		tick: float) -> Vector2:
	if attack == null:
		return Vector2(AXE_IDLE, AXE_IDLE)
	var rest := Vector2(AXE_IDLE, 0.0)
	var chop := _phase_pose(attack, tick, rest, Vector2(AXE_WOUND, 0.0), Vector2(AXE_STRUCK, 0.0)).x
	if ability_id == "frenzy":
		return _frenzy_pitches(attack, tick, chop)
	if ability_id in ["bloodlust", "rampage", "venom_coat"]:
		# Both axes raised high, then lowered.
		var raised := _phase_pose(attack, tick, rest, Vector2(AXE_WOUND, 0.0), Vector2(AXE_WOUND, 0.0)).x
		return Vector2(raised, raised)
	if attack_type == PlayerState.ATTACK_LIGHT or ability_id in ["hamstring", "boomerang_axe"]:
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


# --- Assassin: Dual Talons and Throwing Knives models (placeholder, client) ---
# Built in code: a claw (three blades) on each fist, or a knife in each hand.
# They swing like the Dual Axes (_axe_pitches: pitch on a pivot at each hand).

const ASSASSIN_MODELS := ["dual_talons", "throwing_knives"]
const TALON_RIGHT_PIVOT := Vector3(0.42, 0.2, -0.15)
const TALON_LEFT_PIVOT := Vector3(-0.42, 0.2, -0.15)

var _talon_right: Node3D
var _talon_left: Node3D
var _knife_right: Node3D
var _knife_left: Node3D


func _build_assassin_models() -> void:
	var claw := _flat_material(Color(0.85, 0.45, 0.18), 0.6, 0.35)
	var wrap := _flat_material(Color(0.22, 0.18, 0.16), 0.0, 0.9)
	var steel := _flat_material(Color(0.75, 0.77, 0.8), 0.7, 0.3)
	for side in [1.0, -1.0]:
		var parts: Array = [[Vector3(0.14, 0.12, 0.14), Vector3.ZERO, wrap]]
		for i in 3:
			parts.append([Vector3(0.025, 0.03, 0.42), Vector3((i - 1) * 0.045, 0.0, -0.27), claw])
		var talon := _weapon_pivot(TALON_RIGHT_PIVOT if side > 0.0 else TALON_LEFT_PIVOT, parts)
		var knife := _weapon_pivot(TALON_RIGHT_PIVOT if side > 0.0 else TALON_LEFT_PIVOT, [
			[Vector3(0.04, 0.04, 0.12), Vector3(0.0, 0.0, -0.02), wrap],
			[Vector3(0.015, 0.06, 0.24), Vector3(0.0, 0.0, -0.2), steel],
		])
		if side > 0.0:
			_talon_right = talon
			_knife_right = knife
		else:
			_talon_left = talon
			_knife_left = knife


## Shows the Talons or Knives (hidden for other models), swung like the axes.
func _show_assassin(model: String, attack: AttackParams, attack_type: int, ability_id: String,
		attack_tick: float, lowered: float) -> void:
	var talons := model == "dual_talons"
	var knives := model == "throwing_knives"
	_talon_right.visible = talons
	_talon_left.visible = talons
	_knife_right.visible = knives
	_knife_left.visible = knives
	if not talons and not knives:
		return
	var pitches := _axe_pitches(attack, attack_type, ability_id, attack_tick)
	var right := _talon_right if talons else _knife_right
	var left := _talon_left if talons else _knife_left
	right.rotation.x = lerpf(pitches.x, WEAPON_LOWERED, lowered)
	left.rotation.x = lerpf(pitches.y, WEAPON_LOWERED, lowered)


# --- Ranger: Longbow, Crossbow and Firebolts models (placeholder, client) ---
# Built in code. The bow and crossbow are carried pointing down and raised
# level while attacking; the Firebolts' ember wraps glow on both hands and
# swing like the axes.

const RANGER_MODELS := ["longbow", "crossbow", "firebolts"]
const BOW_PIVOT := Vector3(-0.4, 0.3, -0.25)
const CROSSBOW_PIVOT := Vector3(0.3, 0.3, -0.2)
## Pitch while carried; level (0) while shooting.
const RANGED_CARRY_PITCH := -0.9

var _bow: Node3D
var _crossbow: Node3D
var _wrap_right: Node3D
var _wrap_left: Node3D


func _build_ranger_models() -> void:
	var wood := _flat_material(Color(0.5, 0.33, 0.18), 0.0, 0.8)
	var string := _flat_material(Color(0.9, 0.88, 0.8), 0.0, 0.9)
	var steel := _flat_material(Color(0.62, 0.65, 0.7), 0.7, 0.35)
	var ember := _flat_material(Color(1.0, 0.45, 0.1), 0.0, 0.6)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.4, 0.05)
	# Longbow: a tall limb bent forward in three pieces, and its string.
	_bow = _weapon_pivot(BOW_PIVOT, [
		[Vector3(0.05, 0.6, 0.05), Vector3(0.0, 0.0, -0.12), wood],
		[Vector3(0.05, 0.5, 0.05), Vector3(0.0, 0.5, -0.02), wood],
		[Vector3(0.05, 0.5, 0.05), Vector3(0.0, -0.5, -0.02), wood],
		[Vector3(0.012, 1.45, 0.012), Vector3(0.0, 0.0, 0.08), string],
	])
	# Crossbow: a stock with a bow across its front.
	_crossbow = _weapon_pivot(CROSSBOW_PIVOT, [
		[Vector3(0.08, 0.08, 0.7), Vector3(0.0, 0.0, -0.25), wood],
		[Vector3(0.7, 0.05, 0.06), Vector3(0.0, 0.03, -0.55), steel],
		[Vector3(0.04, 0.12, 0.08), Vector3(0.0, -0.08, -0.05), steel],
	])
	_wrap_right = _weapon_pivot(TALON_RIGHT_PIVOT, [
		[Vector3(0.14, 0.12, 0.16), Vector3.ZERO, ember],
		[Vector3(0.05, 0.05, 0.2), Vector3(0.0, 0.0, -0.15), ember],
	])
	_wrap_left = _weapon_pivot(TALON_LEFT_PIVOT, [
		[Vector3(0.14, 0.12, 0.16), Vector3.ZERO, ember],
		[Vector3(0.05, 0.05, 0.2), Vector3(0.0, 0.0, -0.15), ember],
	])


## Shows the Longbow, Crossbow or Firebolts (hidden for other models).
func _show_ranger(model: String, attack: AttackParams, attack_tick: float, lowered: float) -> void:
	_bow.visible = model == "longbow"
	_crossbow.visible = model == "crossbow"
	_wrap_right.visible = model == "firebolts"
	_wrap_left.visible = model == "firebolts"
	var aiming := 0.0 if attack != null and attack_tick >= 0.0 else RANGED_CARRY_PITCH
	_bow.rotation.x = lerpf(aiming, WEAPON_LOWERED, lowered)
	_crossbow.rotation.x = lerpf(aiming, WEAPON_LOWERED, lowered)
	if model == "firebolts":
		var pitches := _axe_pitches(attack, PlayerState.ATTACK_LIGHT, "", attack_tick)
		_wrap_right.rotation.x = lerpf(pitches.x, WEAPON_LOWERED, lowered)
		_wrap_left.rotation.x = lerpf(pitches.y, WEAPON_LOWERED, lowered)


# --- Juggernaut: Halberd and Greataxe models (placeholder, client) ---
# Built in code. Poses are Vector3(pitch up, sweep left, meters pulled back;
# negative = thrust forward), like the spear's, on a pivot at the right hand.

const HALBERD_PIVOT := Vector3(0.35, 0.05, 0.0)
const HALBERD_IDLE := Vector3(0.6, 0.0, 0.0)
## Light: the axe head swept right to left at reach.
const HALBERD_SWEEP_WOUND := Vector3(-0.15, -1.3, 0.0)
const HALBERD_SWEEP_STRUCK := Vector3(-0.15, 1.3, 0.0)
## Heavy and Cleaving Arc: raised high, chopped down.
const HALBERD_CHOP_WOUND := Vector3(1.7, 0.0, 0.25)
const HALBERD_CHOP_STRUCK := Vector3(-0.35, 0.0, -0.1)
## Wide Reap: a much wider sweep. Crowd Sweep: low.
const HALBERD_REAP_WOUND := Vector3(-0.25, -2.0, 0.0)
const HALBERD_REAP_STRUCK := Vector3(-0.25, 2.0, 0.0)
const HALBERD_LOW_WOUND := Vector3(-0.6, -1.4, 0.0)
const HALBERD_LOW_STRUCK := Vector3(-0.6, 1.4, 0.0)
## Hooking Pull: thrust out (the recovery draws it back in).
const HALBERD_HOOK_OUT := Vector3(0.05, 0.0, -1.2)
## Pole Vault and Brace: the butt planted on the ground ahead. Block: across.
const HALBERD_PLANTED := Vector3(-0.9, 0.0, -0.2)
const HALBERD_GUARD := Vector3(0.9, 0.9, 0.0)
const GREATAXE_PIVOT := Vector3(0.4, 0.2, -0.1)
const GREATAXE_IDLE := Vector3(1.0, 0.3, 0.0)
## Light: a diagonal cleave.
const GREATAXE_CLEAVE_WOUND := Vector3(0.9, -1.2, 0.0)
const GREATAXE_CLEAVE_STRUCK := Vector3(-0.5, 1.2, 0.0)
## Heavy, Charging Chop, Grounding Blow, Executioner's Swing: overhead chop.
const GREATAXE_CHOP_WOUND := Vector3(2.2, 0.0, 0.1)
const GREATAXE_CHOP_STRUCK := Vector3(-1.2, 0.0, 0.0)
## Vortex: held out to the side while the body spins. Iron Hide / block: across.
const GREATAXE_SPIN := Vector3(0.0, -PI / 2.0, 0.0)
const GREATAXE_GUARD := Vector3(0.5, 0.9, 0.0)
## Hurl: drawn back, thrown forward (it leaves the hands: set_axe_thrown).
const GREATAXE_THROW_WOUND := Vector3(2.3, 0.0, 0.2)
const GREATAXE_THROW_STRUCK := Vector3(0.3, 0.0, -0.3)

var _halberd_pivot: Node3D
var _greataxe_pivot: Node3D


func _build_halberd_greataxe() -> void:
	var wood := _flat_material(Color(0.42, 0.28, 0.16), 0.0, 0.85)
	var steel := _flat_material(Color(0.72, 0.74, 0.78), 0.7, 0.35)
	var dark := _flat_material(Color(0.3, 0.3, 0.34), 0.6, 0.5)
	# Halberd: a long shaft with an axe blade on top, a hook below and a spike.
	_halberd_pivot = _weapon_pivot(HALBERD_PIVOT, [
		[Vector3(0.06, 0.06, 2.8), Vector3(0.0, 0.0, -0.6), wood],
		[Vector3(0.04, 0.42, 0.34), Vector3(0.0, 0.22, -1.82), steel],
		[Vector3(0.03, 0.2, 0.08), Vector3(0.0, -0.13, -1.85), dark],
		[Vector3(0.08, 0.025, 0.36), Vector3(0.0, 0.0, -2.16), steel],
	])
	# Greataxe: a long handle with a big double-bit head.
	_greataxe_pivot = _weapon_pivot(GREATAXE_PIVOT, [
		[Vector3(0.07, 0.07, 1.5), Vector3(0.0, 0.0, -0.55), wood],
		[Vector3(0.05, 0.58, 0.42), Vector3(0.0, 0.3, -1.12), steel],
		[Vector3(0.05, 0.42, 0.32), Vector3(0.0, -0.24, -1.12), steel],
		[Vector3(0.1, 0.1, 0.14), Vector3(0.0, 0.0, -1.12), dark],
	])


func _flat_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


## A hidden weapon pivot under the body with box parts: [size, position, material].
func _weapon_pivot(at: Vector3, parts: Array) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	pivot.visible = false
	_roll_pivot.add_child(pivot)
	for part: Array in parts:
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = part[1]
		instance.material_override = part[2]
		pivot.add_child(instance)
	return pivot


## Shows the Halberd or Greataxe (hidden for other models) in its pose.
func _show_halberd_greataxe(model: String, view: PlayerState, attack: AttackParams,
		ability_id: String, attack_tick: float, lowered: float) -> void:
	_halberd_pivot.visible = model == "halberd"
	_greataxe_pivot.visible = model == "greataxe" and not _axe_thrown
	var pivot := _halberd_pivot if model == "halberd" else _greataxe_pivot
	if model != "halberd" and model != "greataxe":
		return
	var pose: Vector3
	if model == "halberd":
		pose = _halberd_pose(attack, view.attack_type, ability_id, attack_tick, view.blocking)
	else:
		pose = _greataxe_pose(attack, view.attack_type, ability_id, attack_tick, view.blocking)
	var rest := HALBERD_PIVOT if model == "halberd" else GREATAXE_PIVOT
	pivot.rotation = Vector3(lerpf(pose.x, WEAPON_LOWERED, lowered), pose.y, 0.0)
	pivot.position = rest + Vector3(0.0, 0.0, pose.z)


static func _halberd_pose(attack: AttackParams, attack_type: int, ability_id: String,
		tick: float, blocking: bool) -> Vector3:
	if attack == null:
		return HALBERD_GUARD if blocking else HALBERD_IDLE
	match ability_id:
		"hooking_pull":
			return _phase_pose3(attack, tick, HALBERD_IDLE, HALBERD_IDLE, HALBERD_HOOK_OUT)
		"wide_reap":
			return _phase_pose3(attack, tick, HALBERD_IDLE, HALBERD_REAP_WOUND, HALBERD_REAP_STRUCK)
		"crowd_sweep":
			return _phase_pose3(attack, tick, HALBERD_IDLE, HALBERD_LOW_WOUND, HALBERD_LOW_STRUCK)
		"pole_vault", "brace":
			return _phase_pose3(attack, tick, HALBERD_IDLE, HALBERD_PLANTED, HALBERD_PLANTED)
		"cleaving_arc":
			return _phase_pose3(attack, tick, HALBERD_IDLE, HALBERD_CHOP_WOUND, HALBERD_CHOP_STRUCK)
	if attack_type == PlayerState.ATTACK_HEAVY:
		return _phase_pose3(attack, tick, HALBERD_IDLE, HALBERD_CHOP_WOUND, HALBERD_CHOP_STRUCK)
	return _phase_pose3(attack, tick, HALBERD_IDLE, HALBERD_SWEEP_WOUND, HALBERD_SWEEP_STRUCK)


static func _greataxe_pose(attack: AttackParams, attack_type: int, ability_id: String,
		tick: float, blocking: bool) -> Vector3:
	if attack == null:
		return GREATAXE_GUARD if blocking else GREATAXE_IDLE
	match ability_id:
		"vortex":
			return _phase_pose3(attack, tick, GREATAXE_IDLE, GREATAXE_SPIN, GREATAXE_SPIN)
		"iron_hide":
			return _phase_pose3(attack, tick, GREATAXE_IDLE, GREATAXE_GUARD, GREATAXE_GUARD)
		"hurl":
			return _phase_pose3(attack, tick, GREATAXE_IDLE, GREATAXE_THROW_WOUND, GREATAXE_THROW_STRUCK)
		"charging_chop", "grounding_blow", "executioners_swing":
			return _phase_pose3(attack, tick, GREATAXE_IDLE, GREATAXE_CHOP_WOUND, GREATAXE_CHOP_STRUCK)
	if attack_type == PlayerState.ATTACK_HEAVY:
		return _phase_pose3(attack, tick, GREATAXE_IDLE, GREATAXE_CHOP_WOUND, GREATAXE_CHOP_STRUCK)
	return _phase_pose3(attack, tick, GREATAXE_IDLE, GREATAXE_CLEAVE_WOUND, GREATAXE_CLEAVE_STRUCK)


# --- Phoenix visuals (Wing abilities, Rebirth; placeholder, client) ---

func _build_phoenix_visuals() -> void:
	var wing_material := StandardMaterial3D.new()
	wing_material.albedo_color = WING_COLOR
	wing_material.emission_enabled = true
	wing_material.emission = Color(WING_COLOR, 1.0)
	wing_material.emission_energy_multiplier = 1.5
	wing_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.15 * side, 0.45, 0.28)
		pivot.visible = false
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.95, 0.05, 0.45)
		mesh.mesh = box
		mesh.material_override = wing_material
		mesh.position = Vector3(0.5 * side, 0.0, 0.1)
		pivot.add_child(mesh)
		_roll_pivot.add_child(pivot)
		_wing_pivots.append(pivot)
	var fire_material := StandardMaterial3D.new()
	fire_material.albedo_color = REBIRTH_FIRE_COLOR
	fire_material.emission_enabled = true
	fire_material.emission = Color(REBIRTH_FIRE_COLOR, 1.0)
	fire_material.emission_energy_multiplier = 2.0
	fire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rebirth_mesh = CylinderMesh.new()
	_rebirth_mesh.top_radius = 0.1
	_rebirth_mesh.bottom_radius = 0.7
	_rebirth_fire = MeshInstance3D.new()
	_rebirth_fire.mesh = _rebirth_mesh
	_rebirth_fire.material_override = fire_material
	_rebirth_fire.visible = false
	add_child(_rebirth_fire)


## Wings spread during a Wing ability (out over the windup, folded back over the
## recovery) and while rebirthing; a fire column rises under a rebirthing body.
func _show_phoenix(view: PlayerState, attack: AttackParams, attack_tick: float) -> void:
	if _wing_pivots.is_empty():
		return
	var rebirth := view.rebirth_progress(params)
	var wing_angle := WING_FOLDED
	var wings_out := false
	if rebirth >= 0.0:
		wings_out = true
		wing_angle = lerpf(WING_FOLDED, WING_SPREAD, rebirth)
	elif attack != null and view.attack_type == PlayerState.ATTACK_WING:
		wings_out = true
		wing_angle = _phase_pose(attack, attack_tick, Vector2(WING_FOLDED, 0.0),
				Vector2(WING_SPREAD, 0.0), Vector2(WING_SPREAD, 0.0)).x
	for i in _wing_pivots.size():
		var side := -1.0 if i == 0 else 1.0
		_wing_pivots[i].visible = wings_out
		_wing_pivots[i].rotation = Vector3(0.0, -0.3 * side, wing_angle * side)
	_rebirth_fire.visible = rebirth >= 0.0
	if _rebirth_fire.visible:
		# Grows up to its full height by halfway, flickering a little.
		var height := REBIRTH_FIRE_HEIGHT * minf(1.0, rebirth * 2.0 + 0.1)
		height *= 1.0 + 0.08 * sin(Time.get_ticks_msec() / 70.0)
		_rebirth_mesh.height = height
		_rebirth_fire.position = Vector3(0.0, height / 2.0, 0.0)


## 0 while lying dead; during the last 30% of a Rebirth, 0..1 as the body
## stands back up.
func _rebirth_rise(view: PlayerState) -> float:
	var progress := view.rebirth_progress(params)
	return clampf((progress - 0.7) / 0.3, 0.0, 1.0) if progress >= 0.0 else 0.0


# --- War Hammer model (Juggernaut; placeholder, client) ---

## Hammer pivot pose: x = pitch (up), y = sweep (left), z = meters pulled back.
const HAMMER_IDLE := Vector3(-0.5, 0.25, 0.0)
## Light: a diagonal swing from the right shoulder.
const HAMMER_LIGHT_WOUND := Vector3(1.0, -1.0, 0.0)
const HAMMER_LIGHT_STRUCK := Vector3(-0.8, 0.8, 0.0)
## Heavy and the slams: raised high overhead, then down onto the ground.
const HAMMER_SLAM_WOUND := Vector3(2.4, 0.0, 0.1)
const HAMMER_SLAM_STRUCK := Vector3(-1.25, 0.0, -0.1)
## Clout: a flat sideways blow.
const HAMMER_CLOUT_WOUND := Vector3(0.2, -1.6, 0.0)
const HAMMER_CLOUT_STRUCK := Vector3(0.0, 1.0, 0.0)
## Steadfast: the head planted on the ground in front.
const HAMMER_PLANTED := Vector3(-1.45, 0.0, 0.0)
const HAMMER_HANDLE_COLOR := Color(0.42, 0.28, 0.16)
const HAMMER_HEAD_COLOR := Color(0.45, 0.47, 0.52)
## Abilities drawn as an overhead slam.
const HAMMER_SLAMS := ["seismic_slam", "shatter", "upheaval", "shockwave", "meteor_drop"]


## A two-handed hammer: a long handle along -Z with a block head across its end.
func _build_hammer_model() -> void:
	_hammer_pivot = Node3D.new()
	_hammer_pivot.position = Vector3(0.4, 0.3, -0.1)
	_hammer_pivot.visible = false
	for part: Array in [[Vector3(0.07, 0.07, 1.25), Vector3(0.0, 0.0, -0.5), HAMMER_HANDLE_COLOR],
			[Vector3(0.28, 0.5, 0.3), Vector3(0.0, 0.0, -1.1), HAMMER_HEAD_COLOR]]:
		var box := BoxMesh.new()
		box.size = part[0]
		var material := StandardMaterial3D.new()
		material.albedo_color = part[2]
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.material_override = material
		mesh.position = part[1]
		_hammer_pivot.add_child(mesh)
	_roll_pivot.add_child(_hammer_pivot)


## Shows the hammer (and hides the Fighter weapons) while the War Hammer is out,
## posed for the current attack; lowered: 0..1 of a swap's lowered weapon.
func _show_hammer(shown: bool, attack: AttackParams, attack_type: int, ability_id: String,
		attack_tick: float, lowered: float) -> void:
	if _hammer_pivot == null:
		return
	_hammer_pivot.visible = shown
	if not shown:
		return
	for pivot in [_sword_pivot, _shield_pivot, _axe_right_pivot, _axe_left_pivot, _spear_pivot]:
		pivot.visible = false
	var pose := _hammer_pose(attack, attack_type, ability_id, attack_tick)
	_hammer_pivot.rotation = Vector3(lerpf(pose.x, WEAPON_LOWERED, lowered), pose.y, 0.0)
	_hammer_pivot.position = Vector3(0.4, 0.3, -0.1 + pose.z)


static func _hammer_pose(attack: AttackParams, attack_type: int, ability_id: String,
		tick: float) -> Vector3:
	if attack == null:
		return HAMMER_IDLE
	if ability_id in HAMMER_SLAMS or attack_type == PlayerState.ATTACK_HEAVY:
		return _phase_pose3(attack, tick, HAMMER_IDLE, HAMMER_SLAM_WOUND, HAMMER_SLAM_STRUCK)
	if ability_id == "clout":
		return _phase_pose3(attack, tick, HAMMER_IDLE, HAMMER_CLOUT_WOUND, HAMMER_CLOUT_STRUCK)
	if ability_id == "steadfast":
		return _phase_pose3(attack, tick, HAMMER_IDLE, HAMMER_PLANTED, HAMMER_PLANTED)
	if attack_type == PlayerState.ATTACK_LIGHT:
		return _phase_pose3(attack, tick, HAMMER_IDLE, HAMMER_LIGHT_WOUND, HAMMER_LIGHT_STRUCK)
	return HAMMER_IDLE  # other Wing abilities: held ready


