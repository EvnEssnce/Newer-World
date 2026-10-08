class_name ProjectileVisual
extends Node3D
## How a projectile looks on clients (cosmetic only; ProjectileSystem moves
## it). "feather": a flat, tapered vane on a quill, pointing along its velocity
## (the game's projectile signature), with a short fading streak behind it.
## "axe": a hand axe spinning flat. Colored per kind (data/projectiles.cfg).
## Meshes are built in code once per kind.

## Fraction of the length the vane is wide (each side of the quill).
const VANE_WIDTH := 0.16
## The vane halves tilt up this much (radians), so it reads from the side too.
const VANE_DIHEDRAL := 0.3
## Seconds of flight the streak behind a feather covers.
const STREAK_SECONDS := 0.025
## Vane outline: [fraction of the length from the tip, fraction of VANE_WIDTH].
const VANE_PROFILE := [[0.06, 0.0], [0.16, 0.75], [0.32, 1.0], [0.55, 0.85], [0.78, 0.6],
		[0.88, 0.45], [0.84, 0.0]]

static var _meshes: Dictionary[String, Mesh] = {}

var _params: ProjectileParams
var _spin := 0.0
var _body: MeshInstance3D


func setup(p: ProjectileParams) -> void:
	_params = p
	_body = MeshInstance3D.new()
	_body.mesh = _mesh_for(p)
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)


## Places it at `pos`, facing along `velocity` (a feather) or spinning flat (an axe).
func show_at(pos: Vector3, velocity: Vector3) -> void:
	position = pos
	var dir := velocity.normalized() if not velocity.is_zero_approx() else Vector3.FORWARD
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK
	basis = Basis.looking_at(dir, up)
	if _params.spin != 0.0:
		_spin = fmod(_spin + _params.spin * get_process_delta_time(), TAU)
		_body.rotation = Vector3(0.0, _spin, 0.0)


static func _mesh_for(p: ProjectileParams) -> Mesh:
	if not _meshes.has(p.id):
		_meshes[p.id] = _build_axe(p) if p.visual == ProjectileParams.VISUAL_AXE else _build_feather(p)
	return _meshes[p.id]


## Local space: forward is -Z, the tip at z = -length / 2.
static func _build_feather(p: ProjectileParams) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := p.length / 2.0
	var width := p.length * VANE_WIDTH
	var edge := p.color
	var root := p.color.lightened(0.5)
	# Vane: two halves either side of the quill, fanned from the quill line.
	for side: float in [-1.0, 1.0]:
		for i in VANE_PROFILE.size() - 1:
			var a: Array = VANE_PROFILE[i]
			var b: Array = VANE_PROFILE[i + 1]
			var za: float = -half + a[0] * p.length
			var zb: float = -half + b[0] * p.length
			var outer_a := _vane_point(side, a[1] * width, za)
			var outer_b := _vane_point(side, b[1] * width, zb)
			_triangle(st, Vector3(0.0, 0.0, za), outer_a, outer_b, root, edge, edge)
			_triangle(st, Vector3(0.0, 0.0, za), outer_b, Vector3(0.0, 0.0, zb), root, edge, root)
	# Quill: a thin flat strip from tip to base, brighter.
	var quill := width * 0.12
	var white := Color(1.0, 1.0, 1.0)
	_triangle(st, Vector3(0.0, 0.01, -half), Vector3(quill, 0.01, half), Vector3(-quill, 0.01, half),
			white, white, white)
	# Streak: a fading strip behind the base.
	var tail := half + p.speed * STREAK_SECONDS
	var clear := Color(p.color, 0.0)
	var faint := Color(p.color, 0.45)
	_triangle(st, Vector3(-width * 0.3, 0.0, half), Vector3(width * 0.3, 0.0, half), Vector3(0.0, 0.0, tail),
			faint, faint, clear)
	var mesh := st.commit()
	mesh.surface_set_material(0, _material(p.color))
	return mesh


static func _vane_point(side: float, out: float, z: float) -> Vector3:
	return Vector3(side * out * cos(VANE_DIHEDRAL), out * sin(VANE_DIHEDRAL), z)


## A hand axe lying flat: a handle along Z and a blade off one end.
static func _build_axe(p: ProjectileParams) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := p.length / 2.0
	var handle := Color(0.45, 0.3, 0.18)
	var w := p.length * 0.05
	_triangle(st, Vector3(-w, 0.0, -half), Vector3(w, 0.0, -half), Vector3(w, 0.0, half), handle, handle, handle)
	_triangle(st, Vector3(-w, 0.0, -half), Vector3(w, 0.0, half), Vector3(-w, 0.0, half), handle, handle, handle)
	# Blade: a curved wedge at the -Z end, sticking out to +X.
	var edge := p.color.lightened(0.4)
	var base := p.color
	var reach := p.length * 0.6
	var points := [Vector3(w, 0.0, -half), Vector3(reach * 0.7, 0.0, -half - p.length * 0.12),
			Vector3(reach, 0.0, -half + p.length * 0.12), Vector3(reach * 0.7, 0.0, -half + p.length * 0.32),
			Vector3(w, 0.0, -half + p.length * 0.22)]
	for i in range(1, points.size() - 1):
		_triangle(st, points[0], points[i], points[i + 1], base, edge, edge)
	var mesh := st.commit()
	mesh.surface_set_material(0, _material(p.color))
	return mesh


static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color,
		cc: Color) -> void:
	for v: Array in [[a, ca], [b, cb], [c, cc]]:
		st.set_color(v[1])
		st.set_normal(Vector3.UP)
		st.add_vertex(v[0])


static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.6
	return m
