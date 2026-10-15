class_name StationVisual
extends Node3D
## Client look of a crafting station, built in code (low poly). "forge": a stone
## hearth with a glowing ember bed under a hood and chimney, and an anvil on a
## stump beside it, lit by a flickering orange light. Not collidable (players
## walk through it, like gathering nodes).

var _embers: StandardMaterial3D
var _light: OmniLight3D
var _phase := 0.0


func setup(visual: String) -> void:
	_phase = randf() * TAU
	if visual != "forge":
		push_warning("StationVisual: unknown look '%s', drawing a forge" % visual)
	_build_forge()  # the only look so far


func _process(delta: float) -> void:
	if _embers == null:
		return
	_phase += delta
	# A slow breathing glow with a faster flicker on top.
	var flicker := 0.5 * sin(_phase * 1.3) + 0.3 * sin(_phase * 7.1) + 0.2 * sin(_phase * 13.7)
	_embers.emission_energy_multiplier = 2.2 + 0.6 * flicker
	_light.light_energy = 1.6 + 0.35 * flicker


func _build_forge() -> void:
	var stone := _material(Color(0.42, 0.40, 0.38))
	var dark_stone := _material(Color(0.28, 0.27, 0.27))
	var wood := _material(Color(0.42, 0.29, 0.18))
	var iron := _material(Color(0.22, 0.23, 0.25))
	iron.metallic = 0.7
	iron.roughness = 0.45
	_embers = _material(Color(0.9, 0.35, 0.08))
	_embers.emission_enabled = true
	_embers.emission = Color(1.0, 0.42, 0.1)
	var hearth_x := -0.6
	# Hearth: a stone block with a rim around the ember bed.
	add_child(_mesh(_box(Vector3(1.4, 0.85, 1.1)), stone, Vector3(hearth_x, 0.425, 0.0)))
	for side in [-1.0, 1.0]:
		add_child(_mesh(_box(Vector3(1.4, 0.14, 0.14)), dark_stone, Vector3(hearth_x, 0.92, side * 0.48)))
		add_child(_mesh(_box(Vector3(0.14, 0.14, 1.1)), dark_stone, Vector3(hearth_x + side * 0.63, 0.92, 0.0)))
	add_child(_mesh(_box(Vector3(1.1, 0.06, 0.82)), _embers, Vector3(hearth_x, 0.88, 0.0)))
	for i in 6:
		var coal := _mesh(_sphere(0.1, 0.12, 5, 2), _embers,
				Vector3(hearth_x - 0.4 + i * 0.16, 0.93, 0.18 * sin(i * 2.3)))
		coal.rotation.y = i * 1.1
		add_child(coal)
	# Back wall, a sloped hood over the fire and a chimney.
	add_child(_mesh(_box(Vector3(1.4, 1.05, 0.25)), stone, Vector3(hearth_x, 1.45, -0.43)))
	var hood := _mesh(_cylinder(0.32, 0.8, 0.75, 4), dark_stone, Vector3(hearth_x, 2.35, -0.1))
	hood.rotation.y = PI / 4.0
	add_child(hood)
	add_child(_mesh(_box(Vector3(0.45, 1.1, 0.45)), stone, Vector3(hearth_x, 3.25, -0.1)))
	# Anvil on a stump, to the right of the hearth.
	var anvil_at := Vector3(0.95, 0.0, 0.25)
	add_child(_mesh(_cylinder(0.28, 0.32, 0.5, 7), wood, anvil_at + Vector3(0.0, 0.25, 0.0)))
	add_child(_mesh(_box(Vector3(0.34, 0.12, 0.26)), iron, anvil_at + Vector3(0.0, 0.56, 0.0)))
	add_child(_mesh(_box(Vector3(0.18, 0.14, 0.16)), iron, anvil_at + Vector3(0.0, 0.69, 0.0)))
	add_child(_mesh(_box(Vector3(0.58, 0.14, 0.26)), iron, anvil_at + Vector3(-0.05, 0.83, 0.0)))
	var horn := _mesh(_cylinder(0.0, 0.11, 0.3, 6), iron, anvil_at + Vector3(0.39, 0.84, 0.0))
	horn.rotation.z = -PI / 2.0  # points away from the hearth
	add_child(horn)
	# A hammer resting on the anvil.
	var handle := _mesh(_cylinder(0.025, 0.025, 0.4, 5), wood, anvil_at + Vector3(-0.05, 0.93, 0.12))
	handle.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	add_child(handle)
	add_child(_mesh(_box(Vector3(0.1, 0.08, 0.16)), iron, anvil_at + Vector3(-0.05, 0.94, -0.08)))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.25)
	_light.omni_range = 4.5
	_light.position = Vector3(hearth_x, 1.3, 0.35)
	add_child(_light)


func _mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _sphere(radius: float, height: float, segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh
