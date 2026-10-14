class_name ProjectileVisual
extends Node3D
## How a projectile looks on clients (cosmetic only; ProjectileSystem moves
## it). "feather": a flat, tapered vane on a quill, pointing along its velocity
## (the game's projectile signature), with a short fading streak behind it.
## "axe": a hand axe spinning flat. "wave": a crescent rolling along the
## ground (Shockwave). Colored per kind (data/projectiles.cfg).
## Every kind also glows (its `glow` key scales it; 0 = off) so it reads in
## flight against the bright ground and at 15-30 m: a camera-facing halo (a
## white-hot core in its color, never smaller on screen than HALO_MIN_ANGLE)
## and a fading trail behind it that grows from the release point (a wave:
## only the trail, flat on the ground).
## Meshes and materials are built in code once per kind; prewarm_looks() gives
## ProjectileSystem invisible copies to draw at load (shader warm-up).

## Fraction of the length the vane is wide (each side of the quill).
const VANE_WIDTH := 0.16
## The vane halves tilt up this much (radians), so it reads from the side too.
const VANE_DIHEDRAL := 0.3
## Seconds of flight the streak behind a feather covers.
const STREAK_SECONDS := 0.025
## Vane outline: [fraction of the length from the tip, fraction of VANE_WIDTH].
const VANE_PROFILE := [[0.06, 0.0], [0.16, 0.75], [0.32, 1.0], [0.55, 0.85], [0.78, 0.6],
		[0.88, 0.45], [0.84, 0.0]]

## Wave: degrees the crescent spans, meters deep its ground band is, and
## meters tall its ridge is.
const WAVE_ARC_DEGREES := 120.0
const WAVE_BAND := 0.45
const WAVE_RIDGE_HEIGHT := 0.45

## Glow, all scaled by the kind's `glow`. The halo is HALO_BASE +
## HALO_PER_LENGTH x length meters across, but never under HALO_MIN_ANGLE
## radians seen from the camera (about 25 px at 1080p), so far throws still show.
const HALO_BASE := 0.3
const HALO_PER_LENGTH := 0.35
const HALO_MIN_ANGLE := 0.028
## Seconds of flight the trail covers once it has flown that far.
const TRAIL_SECONDS := 0.07
## Trail width at its head, a fraction of the halo's size (a wave: of its length).
const TRAIL_WIDTH := 0.4
const WAVE_TRAIL_WIDTH := 0.8
## The body's emission energy: base + per unit of glow.
const BODY_EMISSION := 0.6
const BODY_EMISSION_PER_GLOW := 0.8

static var _meshes: Dictionary[String, Mesh] = {}
static var _halo_materials: Dictionary[String, StandardMaterial3D] = {}
static var _trail_meshes: Dictionary[String, Mesh] = {}
static var _trail_material: StandardMaterial3D
static var _quad: QuadMesh

var _params: ProjectileParams
var _spin := 0.0
var _body: MeshInstance3D
var _halo: MeshInstance3D
var _trail: MeshInstance3D
var _halo_size := 0.0
var _trail_length := 0.0
## Meters flown since it was first shown (the trail never reaches further back).
var _travelled := 0.0
var _shown := false


func setup(p: ProjectileParams) -> void:
	_params = p
	_body = MeshInstance3D.new()
	_body.mesh = _mesh_for(p)
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)
	if p.glow <= 0.0:
		return
	var wave := p.visual == ProjectileParams.VISUAL_WAVE
	_halo_size = (HALO_BASE + HALO_PER_LENGTH * p.length) * p.glow
	_trail_length = p.speed * TRAIL_SECONDS * p.glow
	if not wave:
		_halo = MeshInstance3D.new()
		_halo.mesh = _quad_mesh()
		_halo.material_override = _halo_material(p)
		_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_halo.scale = Vector3.ONE * _halo_size
		add_child(_halo)
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh(p)
	_trail.material_override = _trail_mat()
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# From just behind the body (a wave: on the ground, from the crescent's ends).
	_trail.position = (Vector3(0.0, -p.release_height + 0.03, 0.0) if wave
			else Vector3(0.0, 0.0, p.length * 0.25))
	_trail.scale = Vector3(1.0, 1.0, 0.01)
	add_child(_trail)


## Places it at `pos`, facing along `velocity` (a feather) or spinning flat (an axe).
func show_at(pos: Vector3, velocity: Vector3) -> void:
	if _shown:
		_travelled += pos.distance_to(position)
	_shown = true
	position = pos
	var dir := velocity.normalized() if not velocity.is_zero_approx() else Vector3.FORWARD
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK
	basis = Basis.looking_at(dir, up)
	if _params.spin != 0.0:
		_spin = fmod(_spin + _params.spin * get_process_delta_time(), TAU)
		_body.rotation = Vector3(0.0, _spin, 0.0)
	_show_glow(pos)


## Sizes the halo (at least HALO_MIN_ANGLE seen from the camera) and the trail
## (as long as it has flown, up to TRAIL_SECONDS of flight).
func _show_glow(pos: Vector3) -> void:
	if _trail == null:
		return
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(pos) if camera else 0.0
	var size := maxf(_halo_size, distance * HALO_MIN_ANGLE * _params.glow)
	var width := _params.length * WAVE_TRAIL_WIDTH * _params.glow
	if _halo:
		_halo.scale = Vector3.ONE * size
		width = size * TRAIL_WIDTH
	_trail.scale = Vector3(width, width, clampf(_travelled, 0.01, maxf(_trail_length, 0.01)))


## Client: invisible copies (alpha 0) of every projectile look, one per visual
## type, for ProjectileSystem to draw for a few frames at load, so the GPU
## compiles their shaders then instead of on the first throw.
static func prewarm_looks() -> Node3D:
	var root := Node3D.new()
	var seen := {}
	for p in ProjectileParams.all_kinds():
		if seen.has(p.visual):
			continue
		seen[p.visual] = true
		var look := ProjectileVisual.new()
		look.setup(p)
		look._make_invisible()
		root.add_child(look)
	return root


func _make_invisible() -> void:
	for child in get_children():
		var instance := child as MeshInstance3D
		var m := (instance.material_override if instance.material_override
				else instance.mesh.surface_get_material(0)) as StandardMaterial3D
		var copy := m.duplicate() as StandardMaterial3D
		copy.albedo_color.a = 0.0
		instance.material_override = copy


static func _mesh_for(p: ProjectileParams) -> Mesh:
	if not _meshes.has(p.id):
		match p.visual:
			ProjectileParams.VISUAL_AXE:
				_meshes[p.id] = _build_axe(p)
			ProjectileParams.VISUAL_WAVE:
				_meshes[p.id] = _build_wave(p)
			_:
				_meshes[p.id] = _build_feather(p)
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
	mesh.surface_set_material(0, _material(p.color, p.glow))
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
	mesh.surface_set_material(0, _material(p.color, p.glow))
	return mesh


## A shockwave: a crescent `length` meters across, bulging forward (-Z), lying
## on the ground (release_height below the projectile's center) with a low,
## fading ridge rising from its front edge.
static func _build_wave(p: ProjectileParams) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arc := deg_to_rad(WAVE_ARC_DEGREES) / 2.0
	var radius := p.length / 2.0 / sin(arc)
	var center_z := radius * cos(arc)  # the ends of the arc sit at z = 0
	var ground := -p.release_height + 0.02
	var bright := p.color.lightened(0.35)
	var faint := Color(p.color, 0.0)
	var segments := 12
	for i in segments:
		var a := lerpf(-arc, arc, float(i) / segments)
		var b := lerpf(-arc, arc, float(i + 1) / segments)
		var outer_a := Vector3(radius * sin(a), ground, center_z - radius * cos(a))
		var outer_b := Vector3(radius * sin(b), ground, center_z - radius * cos(b))
		var inner := radius - WAVE_BAND
		var inner_a := Vector3(inner * sin(a), ground, center_z - inner * cos(a))
		var inner_b := Vector3(inner * sin(b), ground, center_z - inner * cos(b))
		# The band on the ground, bright at the front edge.
		_triangle(st, outer_a, outer_b, inner_b, bright, bright, faint)
		_triangle(st, outer_a, inner_b, inner_a, bright, faint, faint)
		# The ridge, rising from the front edge and fading upward.
		var up := Vector3(0.0, WAVE_RIDGE_HEIGHT, 0.0)
		_triangle(st, outer_a, outer_b, outer_b + up, p.color, p.color, faint)
		_triangle(st, outer_a, outer_b + up, outer_a + up, p.color, faint, faint)
	var mesh := st.commit()
	mesh.surface_set_material(0, _material(p.color, p.glow))
	return mesh


static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color,
		cc: Color) -> void:
	for v: Array in [[a, ca], [b, cb], [c, cc]]:
		st.set_color(v[1])
		st.set_normal(Vector3.UP)
		st.add_vertex(v[0])


static func _material(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = BODY_EMISSION + BODY_EMISSION_PER_GLOW * glow
	return m


static func _quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## A camera-facing disc: white at the center, the kind's color around it,
## fading out at the edge. Unshaded so the light doesn't dim it; drawn before
## the body (render_priority) so the body shows on top of it.
static func _halo_material(p: ProjectileParams) -> StandardMaterial3D:
	if not _halo_materials.has(p.id):
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.55, 1.0])
		gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0),
				Color(p.color.lightened(0.3), 1.0), Color(p.color, 0.7), Color(p.color, 0.0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = texture
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = -1
		_halo_materials[p.id] = m
	return _halo_materials[p.id]


## The trail: a strip 1 m long along +Z (behind), 1 m wide at its head and
## tapering, bright at the head and fading to clear; two crossed strips (one
## flat on the ground for a wave) so it shows from any side. Scaled per frame.
static func _trail_mesh(p: ProjectileParams) -> Mesh:
	if not _trail_meshes.has(p.id):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var head := Color(p.color.lightened(0.4), 0.85)
		var tail := Color(p.color, 0.0)
		var back := Vector3(0.0, 0.0, 1.0)
		var planes := [Vector3.RIGHT] if p.visual == ProjectileParams.VISUAL_WAVE else [Vector3.RIGHT, Vector3.UP]
		for across: Vector3 in planes:
			var wide := across * 0.5
			var narrow := across * 0.1
			_triangle(st, -wide, wide, narrow + back, head, head, tail)
			_triangle(st, -wide, narrow + back, -narrow + back, head, tail, tail)
		_trail_meshes[p.id] = st.commit()
	return _trail_meshes[p.id]


static func _trail_mat() -> StandardMaterial3D:
	if _trail_material == null:
		_trail_material = StandardMaterial3D.new()
		_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_material.vertex_color_use_as_albedo = true
		_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_trail_material.render_priority = -1
	return _trail_material
