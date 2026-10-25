class_name EnemyLook
extends RefCounted
## How an enemy kind looks (client only): placeholder low-poly parts built in
## code on the enemy's model, and how they move during a swing. One script per
## kind, game/enemy/looks/<kind>_look.gd (extends EnemyLook), picked by the
## enemy's kind; a kind without one looks like a Husk. Cosmetic only: hits use
## Enemy.BODY_RADIUS / BODY_HEIGHT and the [attack] hitbox whatever the look.
##
## Enemy owns the shared parts and effects: `body` (the capsule; Enemy colors
## its material: base_color(), lerping to the red telegraph during the windup,
## white on a hit, grey when dead), `body_pivot` (tilts when staggered, lies
## down when dead), `model` (turns with the enemy's yaw), the eyes and the club
## from enemy.tscn (hidden unless the look shows them), the name label.

## Turns with its yaw. Scale it for a bigger or smaller kind.
var model: Node3D
## Child of model at half the body height: tilts when staggered, lies down when dead.
var body_pivot: Node3D
## The capsule (radius 0.5, height 2.2, centered on body_pivot).
var body: MeshInstance3D
## The Husk's club (body_pivot/ClubPivot/Club): hidden unless the look shows it.
var club_pivot: Node3D
## The glowing eyes (body_pivot/Eyes), shown by default.
var eyes: MeshInstance3D
var params: EnemyParams


## The look for an enemy kind: looks/<kind>_look.gd, else the Husk's.
static func for_kind(kind: String) -> EnemyLook:
	var path := "res://game/enemy/looks/%s_look.gd" % kind
	if not ResourceLoader.exists(path):
		path = "res://game/enemy/looks/husk_look.gd"
	var script: GDScript = load(path)
	return script.new()


## Adds the kind's parts (meshes under model / body_pivot). Called once, when
## the enemy enters the client's tree; the fields above are set by then.
func build() -> void:
	pass


## The body's color when it isn't telegraphing, flashing or dead.
func base_color() -> Color:
	return Color(0.42, 0.3, 0.48)


## Height of the name label over its feet (m).
func label_height() -> float:
	return 2.7


## Poses the parts. attack_tick: ticks since its swing started (fractional, for
## smooth swings), -1 when not swinging; never called while dead.
func pose(_attack_tick: float) -> void:
	pass


# --- Helpers for pose() ---

## 0..1 through the windup (0 when not winding up).
func windup_fraction(attack_tick: float) -> float:
	var windup := float(params.attack.windup_ticks)
	if attack_tick < 0.0 or attack_tick >= windup:
		return 0.0
	return attack_tick / maxf(windup, 1.0)


## 0..1 through the hit window (the strike), -1 outside it.
func strike_fraction(attack_tick: float) -> float:
	var a := params.attack
	var start := float(a.windup_ticks)
	if attack_tick < start or attack_tick >= start + a.active_ticks:
		return -1.0
	return (attack_tick - start) / maxf(a.active_ticks, 1.0)


## 0..1 through the recovery, -1 outside it.
func recovery_fraction(attack_tick: float) -> float:
	var a := params.attack
	var start := float(a.windup_ticks + a.active_ticks)
	if attack_tick < start:
		return -1.0
	return clampf((attack_tick - start) / maxf(a.recovery_ticks, 1.0), 0.0, 1.0)


## A flat-shaded material for placeholder parts.
static func material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


## A box part added under parent at position, rotated by rotation (radians).
static func add_box(parent: Node3D, size: Vector3, position: Vector3, color: Color,
		rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material(color)
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	parent.add_child(part)
	return part
