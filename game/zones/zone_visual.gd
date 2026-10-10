class_name ZoneVisual
extends Node3D
## How a zone or summon looks on clients (cosmetic only; ZoneSystem places and
## removes it). Built in code from its ZoneParams: "disc" a glowing ground
## circle, "cloud" a few smoke puffs, "rain" a circle with arrows falling into
## it, "trap" a small wire between two stakes (dim until armed), "decoy" a
## burning copy of a player's body, "wall" three tall shields across the
## facing. Everything fades out over its last FADE_SECONDS.

const FADE_SECONDS := 0.5
const RAIN_STREAKS := 8
## Meters the falling arrows drop from.
const RAIN_HEIGHT := 6.0

var _params: ZoneParams
var _materials: Array[StandardMaterial3D] = []
var _streaks: Array[Node3D] = []
var _time := 0.0


func setup(p: ZoneParams, yaw: float) -> void:
	_params = p
	rotation.y = yaw
	match p.visual:
		"cloud":
			for i in 5:
				var angle := TAU * i / 5.0
				var r := p.radius * 0.5
				_sphere(Vector3(cos(angle) * r, 0.9, sin(angle) * r), p.radius * 0.55, 0.55)
			_sphere(Vector3(0.0, 1.3, 0.0), p.radius * 0.6, 0.5)
		"trap":
			_box(Vector3(p.radius * 1.6, 0.03, 0.03), Vector3(0.0, 0.25, 0.0), 0.9)
			_box(Vector3(0.06, 0.5, 0.06), Vector3(p.radius * 0.8, 0.25, 0.0), 0.9)
			_box(Vector3(0.06, 0.5, 0.06), Vector3(-p.radius * 0.8, 0.25, 0.0), 0.9)
			_disc(p.radius, 0.12)
		"decoy":
			var mesh := CapsuleMesh.new()
			mesh.radius = Player.BODY_RADIUS
			mesh.height = Player.BODY_HEIGHT
			_add(mesh, Vector3(0.0, Player.BODY_HEIGHT / 2.0, 0.0), 0.55, true)
		"wall":
			var shield_width := p.wall_width / 3.0
			for i in 3:
				_box(Vector3(shield_width * 0.92, p.height, p.wall_depth),
						Vector3((i - 1) * shield_width, p.height / 2.0, 0.0), 0.85)
		"rain":
			_disc(p.radius, 0.25)
			for i in RAIN_STREAKS:
				var streak := Node3D.new()
				add_child(streak)
				var mesh := BoxMesh.new()
				mesh.size = Vector3(0.03, 0.8, 0.03)
				var instance := MeshInstance3D.new()
				instance.mesh = mesh
				instance.material_override = _material(0.9, false)
				streak.add_child(instance)
				_streaks.append(streak)
		_:
			_disc(p.radius, 0.3)


## seconds_left of its life (fades out at the end); armed: a trap that can
## trigger (bright) or not yet (dim).
func update(seconds_left: float, armed: bool, delta: float) -> void:
	_time += delta
	var fade := clampf(seconds_left / FADE_SECONDS, 0.0, 1.0)
	var pulse := 0.85 + 0.15 * sin(_time * 4.0)
	if _params.visual == "trap" and not armed:
		pulse = 0.35
	for m in _materials:
		m.albedo_color.a = m.get_meta("alpha") * fade * pulse
	for i in _streaks.size():
		# Arrows fall at staggered times to random-looking spots inside the circle.
		var phase := fmod(_time * 1.6 + i * 0.37, 1.0)
		var angle := i * 2.4
		var r := _params.radius * (0.25 + 0.7 * fmod(i * 0.61, 1.0))
		_streaks[i].position = Vector3(cos(angle) * r, RAIN_HEIGHT * (1.0 - phase), sin(angle) * r)


func _disc(radius: float, alpha: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
	_add(mesh, Vector3(0.0, 0.03, 0.0), alpha, true)


func _sphere(at: Vector3, radius: float, alpha: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.6
	_add(mesh, at, alpha, false)


func _box(size: Vector3, at: Vector3, alpha: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add(mesh, at, alpha, false)


func _add(mesh: Mesh, at: Vector3, alpha: float, glow: bool) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(alpha, glow)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _material(alpha: float, glow: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(_params.color, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = (BaseMaterial3D.SHADING_MODE_UNSHADED if glow
			else BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	m.set_meta("alpha", alpha)
	_materials.append(m)
	return m
