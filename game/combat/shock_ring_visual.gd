class_name ShockRingVisual
extends MeshInstance3D
## Client look of a ShockRing (the Earthshaker aftershock): a glowing band on
## the ground, bright at its outer edge, with a low ridge fading upward,
## growing from the center at the ring's speed and fading out near the end.
## Cosmetic only; the server decides the hits.

const SEGMENTS := 48
const RIDGE_HEIGHT := 0.35
## Fraction of the way out where it starts fading.
const FADE_FROM := 0.6

var _speed := 0.0
var _max_radius := 0.0
var _band := 0.0
var _color := Color.WHITE
## Seconds since the ring started (negative = not started yet: a remote
## player's ring waits for the render clock).
var _age := 0.0
var _mesh := ImmediateMesh.new()


## position: the ring's center on the ground. delay: seconds before it starts.
func setup(at: Vector3, speed: float, max_radius: float, band: float, color: Color,
		delay: float) -> void:
	position = at + Vector3.UP * 0.03
	_speed = speed
	_max_radius = max_radius
	_band = band
	_color = color
	_age = -maxf(0.0, delay)
	mesh = _mesh
	material_override = _material(color)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _process(delta: float) -> void:
	_age += delta
	if _age < 0.0:
		return
	var radius := minf(_max_radius, _age * _speed)
	if _speed <= 0.0 or radius >= _max_radius:
		queue_free()
		return
	var t := radius / _max_radius
	var alpha := 1.0 if t < FADE_FROM else 1.0 - (t - FADE_FROM) / (1.0 - FADE_FROM)
	_rebuild(radius, alpha)
	visible = true


func _rebuild(radius: float, alpha: float) -> void:
	_mesh.clear_surfaces()
	var inner := maxf(0.0, radius - _band)
	var bright := Color(_color.lightened(0.35), alpha)
	var edge := Color(_color, alpha)
	var faint := Color(_color, 0.0)
	var up := Vector3(0.0, RIDGE_HEIGHT, 0.0)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		var a := TAU * i / SEGMENTS
		var b := TAU * (i + 1) / SEGMENTS
		var da := Vector3(sin(a), 0.0, cos(a))
		var db := Vector3(sin(b), 0.0, cos(b))
		var outer_a := da * radius
		var outer_b := db * radius
		# The band on the ground, bright at the outer edge.
		_triangle(outer_a, outer_b, db * inner, bright, bright, faint)
		_triangle(outer_a, db * inner, da * inner, bright, faint, faint)
		# The ridge, rising from the edge and fading upward.
		_triangle(outer_a, outer_b, outer_b + up, edge, edge, faint)
		_triangle(outer_a, outer_b + up, outer_a + up, edge, faint, faint)
	_mesh.surface_end()


func _triangle(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	for v: Array in [[a, ca], [b, cb], [c, cc]]:
		_mesh.surface_set_color(v[1])
		_mesh.surface_set_normal(Vector3.UP)
		_mesh.surface_add_vertex(v[0])


## Same settings as ProjectileVisual's wave (so the same compiled shader).
static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.6
	return m
