class_name ZoneVisual
extends Node3D
## How a zone or summon looks on clients (cosmetic only; ZoneSystem places and
## removes it). Built in code from its ZoneParams: "disc" a glowing ground
## circle, "cloud" a few smoke puffs, "rain" a circle with arrows falling into
## it, "trap" a small wire between two stakes (dim until armed), "decoy" a
## burning copy of a player's body, "wall" three tall shields across the
## facing, "firewall" one glowing box (Flame Wall), "orb" a floating ball over
## a faint circle (Life Spore), "strip" a burning strip on the ground (Fire
## Trail: a glowing box `size` long with flames along it), "meteor" (Meteor
## Fall: a warning circle that fills from the middle and reaches its edge as the
## first pulse lands, with a meteor falling into it over its last
## METEOR_FALL_SECONDS, then a flash and a shock ring at impact; timed from when
## the client got it, like its countdown). A decoy shows its seconds left over
## its head. Everything fades out over its last FADE_SECONDS. setup_marker
## builds the faint landing preview of an aimed zone instead
## (ZoneSystem._update_marker).

const FADE_SECONDS := 0.5
const RAIN_STREAKS := 8
## Meters the falling arrows drop from.
const RAIN_HEIGHT := 6.0
## Strip: meters between flames along it.
const FLAME_SPACING := 0.55
## Meteor: seconds the meteor takes to fall (ending at the first pulse), where it
## falls from (meters, relative to the circle's center), seconds the flash and
## the shock ring last after impact, and seconds the warning circle takes to
## fade after it.
const METEOR_FALL_SECONDS := 0.45
const METEOR_FROM := Vector3(-3.5, 15.0, 4.5)
const METEOR_FLASH_SECONDS := 0.3
const METEOR_SHOCK_SECONDS := 0.5
const METEOR_WARNING_LINGER := 0.25
## Decoy: meters above its feet the countdown floats.
const COUNTDOWN_HEIGHT := Player.BODY_HEIGHT + 0.45

var _params: ZoneParams
var _materials: Array[StandardMaterial3D] = []
var _streaks: Array[Node3D] = []
var _flames: Array[Node3D] = []
var _time := 0.0
# Meteor parts (each with its own material, set in _update_meteor).
var _meteor_area: MeshInstance3D
var _meteor_edge: MeshInstance3D
var _meteor_fill: MeshInstance3D
var _meteor_fill_rim: MeshInstance3D
var _meteor: Node3D
var _meteor_flash: MeshInstance3D
var _meteor_shock: MeshInstance3D
# Decoy: its seconds left.
var _countdown: Label3D


## `size`: a wall's (width, depth) for this placement; zero = the kind's.
func setup(p: ZoneParams, yaw: float, size := Vector2.ZERO) -> void:
	_params = p
	rotation.y = yaw
	var width := size.x if size != Vector2.ZERO else p.wall_width
	var depth := size.y if size != Vector2.ZERO else p.wall_depth
	match p.visual:
		"strip":
			_box(Vector3(width, 0.04, maxf(depth, 0.1)), Vector3(0.0, 0.03, 0.0), 0.5, true)
			var count := maxi(2, ceili(depth / FLAME_SPACING))
			for i in count:
				var along := (i + 0.5) / count - 0.5
				var across := (0.25 if i % 2 == 0 else -0.25) * width
				var flame := Node3D.new()
				flame.position = Vector3(across, 0.0, along * depth)
				add_child(flame)
				var mesh := SphereMesh.new()
				mesh.radius = 0.22
				mesh.height = 0.8
				var instance := MeshInstance3D.new()
				instance.mesh = mesh
				instance.position = Vector3(0.0, 0.4, 0.0)
				instance.material_override = _material(0.55, true)
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				flame.add_child(instance)
				_flames.append(flame)
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
		"orb":
			_sphere(Vector3(0.0, 0.6, 0.0), 0.3, 0.8)
			_disc(p.radius, 0.15)
		"firewall":
			_box(Vector3(width, p.height, depth), Vector3(0.0, p.height / 2.0, 0.0), 0.45)
		"decoy":
			var mesh := CapsuleMesh.new()
			mesh.radius = Player.BODY_RADIUS
			mesh.height = Player.BODY_HEIGHT
			_add(mesh, Vector3(0.0, Player.BODY_HEIGHT / 2.0, 0.0), 0.55, true)
			_countdown = Label3D.new()
			_countdown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_countdown.no_depth_test = true
			_countdown.font_size = 64
			_countdown.outline_size = 14
			_countdown.modulate = p.color.lightened(0.6)
			_countdown.outline_modulate = p.color.darkened(0.75)
			_countdown.position = Vector3(0.0, COUNTDOWN_HEIGHT, 0.0)
			add_child(_countdown)
		"meteor":
			_build_meteor(p)
		"wall":
			var shield_width := width / 3.0
			for i in 3:
				_box(Vector3(shield_width * 0.92, p.height, depth),
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


## The landing preview of an aimed zone of kind `p`: a thin ring of its radius
## (a faint flat box for a wall), unshaded, never faded (no update calls).
func setup_marker(p: ZoneParams) -> void:
	_params = p
	if p.wall:
		_box(Vector3(p.wall_width, 0.03, maxf(p.wall_depth, 0.1)), Vector3(0.0, 0.04, 0.0), 0.22, true)
		return
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(0.0, p.radius - 0.1)
	ring.outer_radius = p.radius
	ring.rings = 48
	ring.ring_segments = 6
	_add(ring, Vector3(0.0, 0.05, 0.0), 0.6, true)
	_disc(p.radius, 0.08)


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
	for i in _flames.size():
		# Flames flicker out of step with each other.
		var flicker := 0.75 + 0.35 * sin(_time * 9.0 + i * 1.7)
		_flames[i].scale = Vector3(1.0, flicker, 1.0)
	if _countdown:
		_countdown.text = "%.1f" % seconds_left
		_countdown.modulate.a = fade
		_countdown.outline_modulate.a = fade
	if _meteor:
		_update_meteor(fade)


func _build_meteor(p: ZoneParams) -> void:
	var r := p.radius
	_meteor_area = _part(_cylinder(r, 0.04), Vector3(0.0, 0.03, 0.0), p.color)
	_meteor_edge = _part(_torus(r - 0.14, r), Vector3(0.0, 0.05, 0.0), p.color.lightened(0.3))
	# The fill and its rim are 1 m across and scaled to the fill's radius.
	_meteor_fill = _part(_cylinder(1.0, 0.05), Vector3(0.0, 0.04, 0.0), p.color)
	_meteor_fill_rim = _part(_torus(0.93, 1.0), Vector3(0.0, 0.06, 0.0), Color(1.0, 0.9, 0.6))
	# The meteor: a bright ball with a tail back toward where it falls from.
	_meteor = Node3D.new()
	add_child(_meteor)
	_meteor.basis = Basis.looking_at(-METEOR_FROM.normalized(), Vector3.UP)
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	_part(ball, Vector3.ZERO, Color(1.0, 0.9, 0.55), _meteor)
	var tail := CylinderMesh.new()
	tail.top_radius = 0.05
	tail.bottom_radius = 0.45
	tail.height = 3.5
	var tail_part := _part(tail, Vector3(0.0, 0.0, 1.75), p.color.lightened(0.2), _meteor)
	tail_part.rotation.x = PI / 2.0  # its top (thin end) points back (+Z)
	var flash := SphereMesh.new()
	flash.radius = 1.0
	flash.height = 1.2
	_meteor_flash = _part(flash, Vector3(0.0, 0.3, 0.0), Color(1.0, 0.95, 0.75))
	_meteor_shock = _part(_torus(0.8, 1.0), Vector3(0.0, 0.12, 0.0), p.color.lightened(0.5))


## Meteor: the warning fills toward the impact (the first pulse, timed from
## when this client got the zone), throbbing faster as it nears; the meteor
## falls over the last METEOR_FALL_SECONDS; at impact a flash and a shock ring
## burst out and the warning fades.
func _update_meteor(fade: float) -> void:
	var r := _params.radius
	var impact := _params.first_pulse_ticks / float(Engine.physics_ticks_per_second)
	var progress := clampf(_time / maxf(impact, 0.01), 0.0, 1.0)
	var since := _time - impact  # seconds since impact (negative before)
	var warning := 1.0 if since < 0.0 else clampf(1.0 - since / METEOR_WARNING_LINGER, 0.0, 1.0)
	var throb := 0.7 + 0.3 * sin(_time * (8.0 + 22.0 * progress))
	_set_alpha(_meteor_area, (0.15 + 0.1 * progress) * warning * fade)
	_set_alpha(_meteor_edge, 0.9 * throb * warning * fade)
	var fill_radius := maxf(progress * r, 0.01)
	_meteor_fill.scale = Vector3(fill_radius, 1.0, fill_radius)
	_meteor_fill_rim.scale = Vector3(fill_radius, 1.0, fill_radius)
	_set_alpha(_meteor_fill, (0.2 + 0.35 * progress) * warning * fade)
	_set_alpha(_meteor_fill_rim, 0.85 * warning * fade)
	# Falling: from METEOR_FROM to the center, landing at the impact.
	var fall := 1.0 - (impact - _time) / METEOR_FALL_SECONDS
	var falling := fall >= 0.0 and since < 0.0
	_meteor.position = METEOR_FROM * (1.0 - clampf(fall, 0.0, 1.0))
	for part in _meteor.get_children():
		_set_alpha(part as MeshInstance3D, (1.0 if falling else 0.0) * fade)
	# Impact: the flash swells and fades, the shock ring races out past the edge.
	var flash := clampf(since / METEOR_FLASH_SECONDS, 0.0, 1.0) if since >= 0.0 else 1.0
	_meteor_flash.scale = Vector3.ONE * lerpf(0.3, r * 0.8, 1.0 - pow(1.0 - flash, 2.0))
	_set_alpha(_meteor_flash, 0.9 * (1.0 - flash) * fade)
	var shock := clampf(since / METEOR_SHOCK_SECONDS, 0.0, 1.0) if since >= 0.0 else 1.0
	var shock_radius := r * lerpf(0.3, 1.5, 1.0 - pow(1.0 - shock, 2.0))
	_meteor_shock.scale = Vector3(shock_radius, 1.0 + 2.0 * (1.0 - shock), shock_radius)
	_set_alpha(_meteor_shock, 0.95 * (1.0 - shock) * fade)


## A glowing (unshaded) part with its own material, alpha set by the caller.
func _part(mesh: Mesh, at: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, 0.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = m
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(instance)
	return instance


static func _set_alpha(instance: MeshInstance3D, alpha: float) -> void:
	(instance.material_override as StandardMaterial3D).albedo_color.a = alpha


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh


static func _torus(inner: float, outer: float) -> TorusMesh:
	var ring := TorusMesh.new()
	ring.inner_radius = inner
	ring.outer_radius = outer
	ring.rings = 48
	ring.ring_segments = 6
	return ring


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


func _box(size: Vector3, at: Vector3, alpha: float, glow := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add(mesh, at, alpha, glow)


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
