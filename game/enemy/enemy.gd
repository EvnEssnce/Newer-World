class_name Enemy
extends CharacterBody3D
## An enemy. Server: runs its EnemyBrain every tick, moves, owns health and
## death, and emits attack_stepped while its swing is live (World resolves the
## hits). Clients: draw it interpolated between snapshots, like other players.
## Not predicted, so its state doesn't need to live in PlayerState-style arrays.

## Server only: emitted after each tick in which its swing's hitbox is live.
signal attack_stepped(enemy: Enemy)

## Must match the capsule in enemy.tscn. Used by player hit detection.
const BODY_RADIUS := 0.5
const BODY_HEIGHT := 2.2
const MAX_SNAPSHOTS := 30

# Placeholder visuals (cosmetic only; replaced by real models later).
const BASE_COLOR := Color(0.42, 0.3, 0.48)
## The windup telegraph: the body glows toward this color as the swing winds up.
const TELEGRAPH_COLOR := Color(1.0, 0.15, 0.05)
const HIT_COLOR := Color(1.0, 1.0, 1.0)
const DEAD_COLOR := Color(0.25, 0.25, 0.27)
const HIT_FLASH_MS := 150
const STAGGER_TILT := 0.4
## Club pitch at rest, raised at the end of the windup, and at the end of the strike.
const CLUB_IDLE := -0.6
const CLUB_WOUND := 1.9
const CLUB_STRUCK := -1.5

## Negative, so it never collides with a peer id. Also its node name.
var enemy_id := 0
## Which data/enemy_<kind>.cfg it uses.
var kind := "husk"
var params: EnemyParams
## Its camp: where it wanders, returns to and respawns.
var home := Vector3.ZERO
## Server-authoritative; clients copy it from snapshots.
var health := 0.0
var dead := false

# Server
var brain := EnemyBrain.new()
var respawn_at_tick := -1
## Players the current swing has already been resolved against (see Player).
var attack_results: Dictionary[int, bool] = {}
## A knockback, pull or launch in progress (start_force).
var force := ForcedMotion.new()
var _rng := RandomNumberGenerator.new()
var _gravity := 0.0

# Statuses (server; clients get a copy in snapshots for the label)
## Buffs and debuffs, indices into status_defs. Slow and root change its
## steering, stun staggers its brain, the rest change damage.
var statuses := StatusEffects.new()
var status_defs := StatusDefs.current()
## Damage over time (bleed) due from this tick's server_step, before its
## damage_taken multiplier. World applies it.
var status_damage := 0.0

# Client
var _snapshots: Array[Array] = []  # [server_time, pos, yaw, mode, attack_tick, dead]
var _status_text := ""
var _material: StandardMaterial3D
var _hitbox_material: StandardMaterial3D
var _hit_flash_until := 0

@onready var _model: Node3D = $Model
@onready var _body_pivot: Node3D = $Model/BodyPivot
@onready var _club_pivot: Node3D = $Model/BodyPivot/ClubPivot
@onready var _hitbox_debug: MeshInstance3D = $Model/HitboxDebug
@onready var _name_label: Label3D = $NameLabel


func _ready() -> void:
	params = EnemyParams.for_kind(kind)
	_gravity = PlayerParams.current().gravity
	if multiplayer.is_server():
		health = params.max_health
		brain.wander_point = home
		_rng.randomize()
		_name_label.visible = false
		return
	_material = StandardMaterial3D.new()
	_material.albedo_color = BASE_COLOR
	($Model/BodyPivot/Body as MeshInstance3D).material_override = _material
	_hitbox_material = StandardMaterial3D.new()
	_hitbox_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hitbox_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hitbox_debug.material_override = _hitbox_material
	_update_label()


# --- Server ---

## targets maps the peer id of every living player to their position.
func server_step(targets: Dictionary, delta: float) -> void:
	if dead:
		return
	status_damage = statuses.tick(status_defs)
	var desired := brain.step(global_position, home, targets, params, delta, _rng)
	if brain.attack_tick == 0:
		attack_results.clear()
	desired = _apply_status_movement(desired)
	velocity.x = desired.x
	velocity.z = desired.y
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	_apply_force_step()
	move_and_slide()
	if brain.arrived_home:
		health = params.max_health
	if brain.is_attack_active(params):
		attack_stepped.emit(self)


## Applies a player's hit. Returns true if it killed the enemy.
func take_hit(damage: float, stagger_ticks: int, attacker_id: int) -> bool:
	health = maxf(0.0, health - damage)
	if health <= 0.0:
		dead = true
		velocity = Vector3.ZERO
		statuses.clear()
		force.stop()
		return true
	if attacker_id > 0:
		brain.aggro(attacker_id)
	brain.stagger(roundi(stagger_ticks * params.stagger_multiplier))
	return false


## Server: applies a status (index into status_defs) from source. A stun
## staggers the brain for its duration (the same STAGGERED state as a hit
## stagger). Returns false if nothing was applied.
func apply_status(index: int, stacks: int, duration_ticks: int, source: int) -> bool:
	if dead or not statuses.apply(status_defs, index, stacks, duration_ticks, source):
		return false
	if status_defs.get_def(index).stuns:
		brain.stagger(statuses.ticks_left(index))
	return true


## Slows scale its steering; a root stops it (it can still turn and swing).
func _apply_status_movement(desired: Vector2) -> Vector2:
	if not statuses.can_move(status_defs):
		return Vector2.ZERO
	return desired * statuses.move_multiplier(status_defs)


func respawn() -> void:
	dead = false
	statuses.clear()
	health = params.max_health
	global_position = home
	velocity = Vector3.ZERO
	force.stop()
	brain = EnemyBrain.new()
	brain.wander_point = home
	respawn_at_tick = -1


# --- Forced movement (server) ---

## Can't be pushed, pulled or launched. Nothing grants it yet (a hook for
## heavy enemies and bosses, like PlayerState.is_force_immune).
func is_force_immune() -> bool:
	return false


## Moves this enemy `displacement` meters (world XZ) over `ticks` steps of
## `delta` seconds, launching it at launch_speed m/s (0 = none). Its brain is
## staggered for as long, so steering and swings pause (a swing is interrupted).
## Refused (false) while dead or immune.
func start_force(displacement: Vector2, ticks: int, launch_speed: float, delta: float) -> bool:
	if dead or ticks <= 0 or is_force_immune():
		return false
	force.start(displacement, ticks, launch_speed, delta)
	brain.stagger(ticks)
	return true


## Overrides this step's horizontal velocity (and the vertical one on a
## launch's first step) while being moved.
func _apply_force_step() -> void:
	if not force.is_active():
		return
	var push := force.step_velocity()
	velocity.x = push.x
	velocity.z = push.y
	var launch := force.take_launch()
	if launch > 0.0:
		velocity.y = launch


func get_snapshot() -> Array:
	return [enemy_id, kind, global_position, brain.yaw, brain.mode, brain.attack_tick, health, dead,
			statuses.to_packed()]


# --- Client ---

func push_snapshot(server_time: float, pos: Vector3, yaw: float, mode: int, attack_tick: int,
		is_dead: bool) -> void:
	if _snapshots.is_empty():
		global_position = pos
	_snapshots.append([server_time, pos, yaw, mode, attack_tick, is_dead])
	if _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


func interpolate(render_time: float) -> void:
	if _snapshots.is_empty():
		return
	while _snapshots.size() >= 2 and _snapshots[1][0] <= render_time:
		_snapshots.pop_front()
	var from: Array = _snapshots[0]
	var pos: Vector3 = from[1]
	var yaw: float = from[2]
	var attack_tick := float(from[4])
	if _snapshots.size() >= 2 and render_time > from[0]:
		var to: Array = _snapshots[1]
		var weight: float = (render_time - from[0]) / (to[0] - from[0])
		pos = from[1].lerp(to[1], weight)
		yaw = lerp_angle(from[2], to[2], weight)
		if from[4] >= 0 and to[4] > from[4]:
			attack_tick = lerpf(from[4], to[4], weight)
	global_position = pos
	dead = from[5]
	_show(yaw, from[3] == EnemyBrain.Mode.STAGGERED, attack_tick)


func set_health(value: float) -> void:
	if value == health:
		return
	health = value
	_update_label()


func show_hit(damage: float, result: int) -> void:
	HitFeedback.spawn_label(self, 2.8, damage, result)
	if HitFeedback.flashes(result):
		_hit_flash_until = Time.get_ticks_msec() + HIT_FLASH_MS


## Client: the statuses from the latest snapshot (StatusEffects.to_packed()),
## shown as a line under its health.
func set_statuses(data: PackedInt32Array) -> void:
	var text := StatusEffects.from_packed(data).summary(status_defs)
	if text == _status_text:
		return
	_status_text = text
	_update_label()


func _update_label() -> void:
	var status := "Defeated" if health <= 0.0 else str(ceili(health))
	_name_label.text = "%s\n%s" % [kind.capitalize(), status]
	if not _status_text.is_empty():
		_name_label.text += "\n" + _status_text


## attack_tick is fractional for smooth swings; -1 when not swinging.
func _show(yaw: float, staggered: bool, attack_tick: float) -> void:
	_model.rotation.y = yaw
	if dead:
		_body_pivot.rotation.x = -PI / 2.0
		_body_pivot.position.y = BODY_RADIUS
	else:
		_body_pivot.position.y = BODY_HEIGHT / 2.0
		_body_pivot.rotation.x = STAGGER_TILT if staggered else 0.0

	var attack := params.attack
	var windup := float(attack.windup_ticks)
	var strike_end := windup + attack.active_ticks
	var club := CLUB_IDLE
	var telegraph := 0.0
	if attack_tick >= 0.0 and not dead:
		if attack_tick < windup:
			telegraph = attack_tick / maxf(windup, 1.0)
			club = lerpf(CLUB_IDLE, CLUB_WOUND, telegraph)
		elif attack_tick < strike_end:
			club = lerpf(CLUB_WOUND, CLUB_STRUCK, (attack_tick - windup) / attack.active_ticks)
		else:
			club = lerpf(CLUB_STRUCK, CLUB_IDLE,
					(attack_tick - strike_end) / maxf(attack.recovery_ticks, 1.0))
	_club_pivot.rotation.x = club

	_hitbox_debug.visible = Player.show_hitboxes and attack_tick >= 0.0 and not dead
	if _hitbox_debug.visible:
		(_hitbox_debug.mesh as BoxMesh).size = Vector3(
				attack.hitbox_width, attack.hitbox_height, attack.hitbox_range)
		_hitbox_debug.position = Vector3(0.0, attack.hitbox_height / 2.0, -attack.hitbox_range / 2.0)
		var active := attack_tick >= windup and attack_tick < strike_end
		_hitbox_material.albedo_color = Color(1.0, 0.2, 0.2, 0.45 if active else 0.1)

	if dead:
		_material.albedo_color = DEAD_COLOR
	elif Time.get_ticks_msec() < _hit_flash_until:
		_material.albedo_color = HIT_COLOR
	else:
		_material.albedo_color = BASE_COLOR.lerp(TELEGRAPH_COLOR, telegraph)
