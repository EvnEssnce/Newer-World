extends EnemyLook
## The Cinder Seer: a hooded caster in a long six-sided robe, holding an ember
## orb in front of it. The orb swells and brightens through the windup, snaps
## forward and vanishes at the throw (the real orb is the projectile), then
## rekindles in its hands during the recovery. No club. Cosmetic only.

const ROBE_HEIGHT := 1.6
## The held orb's spot (body_pivot space) at rest, drawn in at the end of the
## windup, and where it flies to as it leaves.
const ORB_REST := Vector3(0.0, 0.28, -0.55)
const ORB_WOUND := Vector3(0.0, 0.42, -0.42)
const ORB_THROWN := Vector3(0.0, 0.32, -1.4)
const ORB_RADIUS := 0.13
## Orb scale at rest and at the end of the windup.
const ORB_SCALE_REST := 1.0
const ORB_SCALE_WOUND := 2.2
## Orb glow at rest and at the end of the windup.
const GLOW_REST := 1.6
const GLOW_WOUND := 6.0
## Arm pitch (radians; 0 = hanging down, PI/2 = straight ahead) at rest, raised
## at the end of the windup, and thrust out at the throw.
const ARM_REST := 1.15
const ARM_WOUND := 1.45
const ARM_THROWN := 1.7

const HOOD_COLOR := Color(0.13, 0.12, 0.12)
const SLEEVE_COLOR := Color(0.2, 0.19, 0.19)
const ORB_COLOR := Color(1.0, 0.45, 0.1)

var _orb: MeshInstance3D
var _orb_material: StandardMaterial3D
var _arms: Array[Node3D] = []


func build() -> void:
	club_pivot.visible = false
	# The capsule becomes a narrow torso inside the robe; it keeps Enemy's
	# material (telegraph red, hit flash, dead grey), and so does the robe.
	body.scale = Vector3(0.5, 0.45, 0.5)
	body.position = Vector3(0.0, 0.55, 0.0)
	var body_material: Material = body.material_override

	var robe_mesh := CylinderMesh.new()
	robe_mesh.top_radius = 0.24
	robe_mesh.bottom_radius = 0.62
	robe_mesh.height = ROBE_HEIGHT
	robe_mesh.radial_segments = 6
	robe_mesh.rings = 1
	var robe := MeshInstance3D.new()
	robe.mesh = robe_mesh
	robe.material_override = body_material
	# Hem on the ground (body_pivot sits at half the 2.2 m body height).
	robe.position = Vector3(0.0, -1.1 + ROBE_HEIGHT / 2.0, 0.0)
	body_pivot.add_child(robe)

	# Hood: a six-sided cone over the head, a dark brim in front.
	var hood_mesh := CylinderMesh.new()
	hood_mesh.top_radius = 0.0
	hood_mesh.bottom_radius = 0.33
	hood_mesh.height = 0.7
	hood_mesh.radial_segments = 6
	hood_mesh.rings = 1
	hood_mesh.material = material(HOOD_COLOR)
	var hood := MeshInstance3D.new()
	hood.mesh = hood_mesh
	hood.position = Vector3(0.0, 0.88, 0.02)
	hood.rotation.x = -0.12
	body_pivot.add_child(hood)
	add_box(body_pivot, Vector3(0.42, 0.1, 0.16), Vector3(0.0, 0.92, -0.26), HOOD_COLOR,
			Vector3(-0.3, 0.0, 0.0))
	# Shoulder mantle.
	add_box(body_pivot, Vector3(0.7, 0.14, 0.42), Vector3(0.0, 0.5, 0.0), HOOD_COLOR)

	# The eyes glow from the hood's shadow, narrower than the Husk's.
	eyes.position = Vector3(0.0, 0.76, -0.25)
	eyes.scale = Vector3(0.45, 0.8, 0.8)

	# Sleeves from the shoulders, reaching forward to cup the orb.
	for side: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.3 * side, 0.45, -0.05)
		arm.rotation.x = ARM_REST
		body_pivot.add_child(arm)
		add_box(arm, Vector3(0.16, 0.6, 0.16), Vector3(0.0, -0.3, 0.0), SLEEVE_COLOR,
				Vector3(0.0, 0.0, -0.45 * side))
		_arms.append(arm)

	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = ORB_RADIUS
	orb_mesh.height = ORB_RADIUS * 2.0
	orb_mesh.radial_segments = 8
	orb_mesh.rings = 4
	_orb_material = material(ORB_COLOR, GLOW_REST)
	_orb_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_mesh.material = _orb_material
	_orb = MeshInstance3D.new()
	_orb.mesh = orb_mesh
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.position = ORB_REST
	body_pivot.add_child(_orb)


func base_color() -> Color:
	return Color(0.3, 0.29, 0.28)


func label_height() -> float:
	return 2.6


func pose(attack_tick: float) -> void:
	var pos := ORB_REST
	var size := ORB_SCALE_REST
	var glow := GLOW_REST
	var arm := ARM_REST
	var strike := strike_fraction(attack_tick)
	var recovery := recovery_fraction(attack_tick)
	if strike >= 0.0:
		# The throw: it snaps forward and goes out as the real orb leaves.
		pos = ORB_WOUND.lerp(ORB_THROWN, strike)
		size = lerpf(ORB_SCALE_WOUND, 0.0, strike)
		glow = GLOW_WOUND
		arm = lerpf(ARM_WOUND, ARM_THROWN, strike)
	elif recovery >= 0.0:
		# Rekindles in its hands.
		size = lerpf(0.2, ORB_SCALE_REST, recovery)
		glow = lerpf(GLOW_WOUND, GLOW_REST, recovery)
		arm = lerpf(ARM_THROWN, ARM_REST, recovery)
	elif attack_tick >= 0.0:
		var wound := windup_fraction(attack_tick)
		var eased := wound * wound
		pos = ORB_REST.lerp(ORB_WOUND, wound)
		size = lerpf(ORB_SCALE_REST, ORB_SCALE_WOUND, eased)
		glow = lerpf(GLOW_REST, GLOW_WOUND, eased)
		arm = lerpf(ARM_REST, ARM_WOUND, wound)
	else:
		# Idle: the ember breathes.
		var t := Time.get_ticks_msec() / 1000.0
		size *= 1.0 + 0.08 * sin(t * 3.0)
		pos.y += 0.03 * sin(t * 1.7)
	_orb.visible = size > 0.02
	_orb.position = pos
	_orb.scale = Vector3.ONE * maxf(size, 0.02)
	_orb_material.emission_energy_multiplier = glow
	for a in _arms:
		a.rotation.x = arm
