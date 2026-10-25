extends EnemyLook
## The Thornling: a small, low four-legged brute (the shared capsule laid flat
## as its body), a ring of thorn spikes on its back, a snout with glowing eyes
## and a jaw that gapes during the windup and snaps shut in the bite. The body
## stretches forward a little in the bite (the lunge). Placeholder parts;
## cosmetic only.

const BODY_COLOR := Color(0.24, 0.32, 0.17)
const THORN_COLOR := Color(0.36, 0.25, 0.13)
const TIP_COLOR := Color(0.78, 0.72, 0.5)
const MOUTH_COLOR := Color(0.45, 0.12, 0.1)
const TOOTH_COLOR := Color(0.9, 0.86, 0.7)

## The whole model's scale: about 70% of a Husk.
const MODEL_SCALE := 0.7
## Where the body's middle sits under body_pivot (pivot units: before MODEL_SCALE),
## so the low body is near the ground.
const BODY_DROP := -0.55
## Jaw pitch (radians) at rest, wide open at the end of the windup, shut in the bite.
const JAW_REST := 0.15
const JAW_OPEN := 0.95
const JAW_SHUT := -0.05
## Extra forward stretch of the body at the height of the bite (fraction).
const LUNGE_STRETCH := 0.12

var _jaw: Node3D
var _front: Node3D


func build() -> void:
	model.scale = Vector3.ONE * MODEL_SCALE
	club_pivot.visible = false
	# The capsule (axis along Y) laid along -Z: a long, low body.
	body.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	body.scale = Vector3(0.9, 0.7, 0.75)
	body.position = Vector3(0.0, BODY_DROP, 0.0)

	# Legs: four stubby boxes reaching the ground (pivot y -1.1 = the feet).
	for x in [-0.32, 0.32]:
		for z in [-0.45, 0.45]:
			add_box(body_pivot, Vector3(0.18, 0.55, 0.2), Vector3(x, -0.86, z), BODY_COLOR.darkened(0.25))

	# The front: head, snout and jaw, moved forward a little in the lunge.
	_front = Node3D.new()
	_front.position = Vector3(0.0, BODY_DROP, -0.8)
	body_pivot.add_child(_front)
	add_box(_front, Vector3(0.6, 0.42, 0.45), Vector3(0.0, 0.08, -0.05), BODY_COLOR.darkened(0.1))
	add_box(_front, Vector3(0.44, 0.2, 0.32), Vector3(0.0, 0.12, -0.38), BODY_COLOR.darkened(0.15))
	for x in [-0.15, 0.15]:  # upper fangs
		add_box(_front, Vector3(0.06, 0.12, 0.06), Vector3(x, -0.02, -0.5), TOOTH_COLOR)
	_jaw = Node3D.new()
	_jaw.position = Vector3(0.0, -0.06, -0.2)
	_front.add_child(_jaw)
	add_box(_jaw, Vector3(0.42, 0.1, 0.36), Vector3(0.0, -0.05, -0.18), MOUTH_COLOR)
	for x in [-0.12, 0.12]:  # lower fangs
		add_box(_jaw, Vector3(0.05, 0.1, 0.05), Vector3(x, 0.04, -0.32), TOOTH_COLOR)
	eyes.position = _front.position + Vector3(0.0, 0.22, -0.29)
	eyes.scale = Vector3(0.9, 0.9, 1.0)

	# Thorns: a row along the spine leaning back and a ring around the back, leaning outward.
	for i in 5:
		var z := lerpf(-0.45, 0.55, i / 4.0)
		_add_thorn(Vector3(0.0, BODY_DROP + 0.34, z), Vector3(0.35, 0.0, 0.0), 0.42 - 0.04 * absf(i - 1.5))
	for i in 8:
		var angle := TAU * i / 8.0
		var side := Vector3(sin(angle) * 0.36, 0.0, cos(angle) * 0.42)
		# Rotating about X tips the top toward +Z, about Z toward -X: outward.
		var lean := Vector3(cos(angle) * 0.75, 0.0, -sin(angle) * 0.75)
		_add_thorn(Vector3(side.x, BODY_DROP + 0.22, side.z), lean, 0.3)
	# A short spiked tail.
	add_box(body_pivot, Vector3(0.12, 0.12, 0.45), Vector3(0.0, BODY_DROP + 0.05, 0.95),
			BODY_COLOR.darkened(0.2), Vector3(0.35, 0.0, 0.0))
	_add_thorn(Vector3(0.0, BODY_DROP + 0.15, 1.15), Vector3(1.1, 0.0, 0.0), 0.25)


func base_color() -> Color:
	return BODY_COLOR


func label_height() -> float:
	return 1.4


func pose(attack_tick: float) -> void:
	var jaw := JAW_REST
	var lunge := 0.0
	var strike := strike_fraction(attack_tick)
	var recovery := recovery_fraction(attack_tick)
	if strike >= 0.0:
		jaw = lerpf(JAW_OPEN, JAW_SHUT, minf(strike * 2.0, 1.0))
		lunge = 1.0
	elif recovery >= 0.0:
		jaw = lerpf(JAW_SHUT, JAW_REST, recovery)
		lunge = 1.0 - recovery
	elif attack_tick >= 0.0:
		var w := windup_fraction(attack_tick)
		jaw = lerpf(JAW_REST, JAW_OPEN, w)
		lunge = -0.4 * w  # crouches back before it springs
	_jaw.rotation.x = jaw
	_front.position.z = -0.8 - 0.25 * lunge
	body.scale.y = 0.7 * (1.0 + LUNGE_STRETCH * lunge)


## A thorn: a tall thin four-sided spike (a prism) with a pale tip, at position
## under body_pivot, tilted by rotation (radians).
func _add_thorn(position: Vector3, rotation: Vector3, length: float) -> void:
	var pivot := Node3D.new()
	pivot.position = position
	pivot.rotation = rotation
	body_pivot.add_child(pivot)
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.12, length, 0.12)
	mesh.material = material(THORN_COLOR)
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = Vector3(0.0, length / 2.0, 0.0)
	pivot.add_child(part)
	var tip := PrismMesh.new()
	tip.size = Vector3(0.05, length * 0.3, 0.05)
	tip.material = material(TIP_COLOR)
	var tip_part := MeshInstance3D.new()
	tip_part.mesh = tip
	tip_part.position = Vector3(0.0, length * 0.85, 0.0)
	pivot.add_child(tip_part)
