extends EnemyLook
## The Cragmaw: a hulking grey-brown stone brute, broad and scaled up, with
## boulder plates on its shoulders and back and two heavy stone forearms. In the
## windup it leans back and raises both fists over its head (the fists heat up
## red with the body's telegraph); the strike slams them down to the ground in
## front as it leans in; the recovery holds them there, then lifts them back.
## Cosmetic only: hits use the normal capsule and the [attack] cone.

## How much bigger than the normal capsule it's drawn.
const SCALE := 1.3
## Arm pitch (radians, 0 = hanging straight down, positive = forward/up) at rest,
## raised over its head at the end of the windup, and slammed at the end of the strike.
const ARM_IDLE := 0.15
const ARM_WOUND := 2.9
const ARM_STRUCK := 0.75
## Body lean (radians, positive = forward) at the end of the windup and of the strike.
const LEAN_WOUND := -0.15
const LEAN_STRUCK := 0.35
## Fraction of the recovery the fists stay on the ground before lifting.
const RECOVERY_HOLD := 0.35

const STONE := Color(0.46, 0.41, 0.35)
const STONE_DARK := Color(0.32, 0.29, 0.26)
const STONE_LIGHT := Color(0.56, 0.52, 0.46)
const FIST_HOT := Color(0.85, 0.25, 0.12)

var _arms: Array[Node3D] = []
var _fist_materials: Array[StandardMaterial3D] = []


func build() -> void:
	model.scale = Vector3.ONE * SCALE
	eyes.scale = Vector3(1.3, 0.7, 1.0)

	# Shoulder boulders, tipped at odd angles.
	add_box(body_pivot, Vector3(0.62, 0.48, 0.66), Vector3(-0.6, 0.72, 0.05), STONE_DARK,
			Vector3(0.3, 0.4, -0.35))
	add_box(body_pivot, Vector3(0.58, 0.52, 0.6), Vector3(0.62, 0.7, 0.08), STONE_DARK,
			Vector3(-0.2, -0.5, 0.3))
	add_box(body_pivot, Vector3(0.34, 0.3, 0.36), Vector3(-0.72, 0.98, 0.15), STONE_LIGHT,
			Vector3(0.7, 0.2, 0.5))
	# Back plates, a ridge of slabs down its spine.
	add_box(body_pivot, Vector3(0.7, 0.5, 0.32), Vector3(0.0, 0.62, 0.42), STONE_LIGHT,
			Vector3(-0.45, 0.15, 0.1))
	add_box(body_pivot, Vector3(0.62, 0.46, 0.3), Vector3(0.05, 0.15, 0.46), STONE_DARK,
			Vector3(-0.25, -0.3, -0.15))
	add_box(body_pivot, Vector3(0.5, 0.4, 0.28), Vector3(-0.08, -0.32, 0.42), STONE_LIGHT,
			Vector3(0.2, 0.35, 0.2))
	# A heavy brow over the eyes and a jutting jaw.
	add_box(body_pivot, Vector3(0.7, 0.16, 0.3), Vector3(0.0, 0.8, -0.36), STONE_DARK,
			Vector3(0.25, 0.0, 0.0))
	add_box(body_pivot, Vector3(0.6, 0.22, 0.34), Vector3(0.0, 0.36, -0.38), STONE_DARK,
			Vector3(-0.15, 0.0, 0.0))
	# Stubby legs.
	for side: float in [-1.0, 1.0]:
		add_box(body_pivot, Vector3(0.36, 0.5, 0.42), Vector3(0.24 * side, -0.9, 0.0),
				STONE_DARK, Vector3(0.0, 0.2 * side, 0.0))

	for side: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.78 * side, 0.55, -0.05)
		body_pivot.add_child(arm)
		add_box(arm, Vector3(0.36, 0.5, 0.36), Vector3(0.0, -0.22, 0.0), STONE_DARK)
		add_box(arm, Vector3(0.44, 0.75, 0.44), Vector3(0.0, -0.78, 0.0), STONE,
				Vector3(0.08, 0.3 * side, 0.0))
		var fist := add_box(arm, Vector3(0.58, 0.5, 0.58), Vector3(0.0, -1.38, 0.0),
				STONE_LIGHT, Vector3(0.15, 0.4 * side, 0.1))
		_fist_materials.append((fist.mesh as BoxMesh).material as StandardMaterial3D)
		_arms.append(arm)
	_pose_parts(ARM_IDLE, 0.0, 0.0)


func base_color() -> Color:
	return STONE


func label_height() -> float:
	return 3.6


func pose(attack_tick: float) -> void:
	var arm := ARM_IDLE
	var lean := 0.0
	var heat := 0.0
	var strike := strike_fraction(attack_tick)
	var recovery := recovery_fraction(attack_tick)
	if strike >= 0.0:
		var t := strike * strike  # accelerates into the ground
		arm = lerpf(ARM_WOUND, ARM_STRUCK, t)
		lean = lerpf(LEAN_WOUND, LEAN_STRUCK, t)
		heat = 1.0 - strike
	elif recovery >= 0.0:
		var t := clampf((recovery - RECOVERY_HOLD) / (1.0 - RECOVERY_HOLD), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		arm = lerpf(ARM_STRUCK, ARM_IDLE, t)
		lean = lerpf(LEAN_STRUCK, 0.0, t)
	elif attack_tick >= 0.0:
		var w := windup_fraction(attack_tick)
		var t := 1.0 - pow(1.0 - w, 2.0)  # heaves up fast, then hangs at the top
		arm = lerpf(ARM_IDLE, ARM_WOUND, t)
		lean = lerpf(0.0, LEAN_WOUND, t)
		heat = w
	_pose_parts(arm, lean, heat)


## Both arms at pitch `arm`, the body leaning forward by `lean` (added to the
## stagger tilt Enemy set this frame), fists glowing by `heat` (0..1).
func _pose_parts(arm: float, lean: float, heat: float) -> void:
	body_pivot.rotation.x -= lean
	for a: Node3D in _arms:
		a.rotation.x = arm
	var color := STONE_LIGHT.lerp(FIST_HOT, heat)
	for m: StandardMaterial3D in _fist_materials:
		m.albedo_color = color
		m.emission_enabled = heat > 0.0
		m.emission = FIST_HOT
		m.emission_energy_multiplier = heat * 1.5
