class_name GatherNodeVisual
extends Node3D
## Client look of a gathering node, built in code (low poly): "ore" a grey rock
## with glinting copper veins, "wood" a pine, "fiber" a thistle bush. Depleted:
## rubble, a stump, a dry tuft. Not collidable (players walk through it).

var _full: Node3D
var _empty: Node3D
var _glint: StandardMaterial3D
var _phase := 0.0


func setup(visual: String) -> void:
	_full = Node3D.new()
	_empty = Node3D.new()
	add_child(_full)
	add_child(_empty)
	_phase = randf() * TAU
	match visual:
		"ore":
			_build_ore()
		"wood":
			_build_wood()
		_:
			_build_fiber()
	set_available(true)


func set_available(available: bool) -> void:
	_full.visible = available
	_empty.visible = not available


func _process(delta: float) -> void:
	if _glint == null or not _full.visible:
		return
	_phase += delta
	# A slow shimmer with a short bright glint every couple of seconds.
	var glint := pow(maxf(0.0, sin(_phase * 1.7)), 12.0)
	_glint.emission_energy_multiplier = 0.6 + 0.3 * sin(_phase * 3.1) + 2.5 * glint


func _build_ore() -> void:
	var stone := _material(Color(0.44, 0.42, 0.40))
	var rock := _mesh(_sphere(0.75, 1.0, 6, 3), stone, Vector3(0.0, 0.32, 0.0))
	rock.scale = Vector3(1.25, 0.85, 1.0)
	rock.rotation.y = 0.4
	_full.add_child(rock)
	var side := _mesh(_sphere(0.45, 0.7, 5, 3), stone, Vector3(0.75, 0.18, 0.35))
	side.rotation = Vector3(0.3, 1.1, 0.2)
	_full.add_child(side)
	_glint = _material(Color(0.85, 0.45, 0.2))
	_glint.emission_enabled = true
	_glint.emission = Color(1.0, 0.55, 0.25)
	_glint.metallic = 0.8
	_glint.roughness = 0.3
	for i in 5:
		var angle := i * TAU / 5.0 + 0.3
		var vein_box := BoxMesh.new()
		vein_box.size = Vector3(0.09, 0.42, 0.07)
		var vein := _mesh(vein_box, _glint, Vector3(cos(angle) * 0.78, 0.38 + 0.12 * (i % 2), sin(angle) * 0.66))
		vein.rotation = Vector3(0.0, -angle, 0.5 + 0.35 * (i % 3))
		_full.add_child(vein)
	var rubble := _material(Color(0.36, 0.34, 0.33))
	for i in 4:
		var angle := i * TAU / 4.0
		var chunk := _mesh(_sphere(0.28, 0.32, 5, 2), rubble,
				Vector3(cos(angle) * 0.45, 0.1, sin(angle) * 0.4))
		chunk.rotation.y = angle
		_empty.add_child(chunk)


func _build_wood() -> void:
	var bark := _material(Color(0.42, 0.28, 0.16))
	var needles := _material(Color(0.17, 0.4, 0.22))
	_full.add_child(_mesh(_cylinder(0.17, 0.26, 2.4, 6), bark, Vector3(0.0, 1.2, 0.0)))
	_full.add_child(_mesh(_cylinder(0.0, 1.15, 1.7, 7), needles, Vector3(0.0, 2.3, 0.0)))
	var top := _mesh(_cylinder(0.0, 0.8, 1.4, 7), needles, Vector3(0.0, 3.15, 0.0))
	top.rotation.y = 0.45
	_full.add_child(top)
	_empty.add_child(_mesh(_cylinder(0.24, 0.29, 0.45, 6), bark, Vector3(0.0, 0.22, 0.0)))
	_empty.add_child(_mesh(_cylinder(0.22, 0.22, 0.02, 6), _material(Color(0.78, 0.66, 0.45)),
			Vector3(0.0, 0.455, 0.0)))


func _build_fiber() -> void:
	var leaves := _material(Color(0.32, 0.5, 0.22))
	var bloom := _material(Color(0.66, 0.42, 0.78))
	var stem := _material(Color(0.5, 0.58, 0.3))
	for i in 5:
		var angle := i * TAU / 5.0
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * (0.32 if i > 0 else 0.0)
		var lump := _mesh(_sphere(0.34, 0.5, 6, 3), leaves, offset + Vector3(0.0, 0.25, 0.0))
		lump.rotation.y = angle
		_full.add_child(lump)
		var tuft := _mesh(_cylinder(0.02, 0.03, 0.45, 4), stem, offset * 0.8 + Vector3(0.0, 0.6, 0.0))
		tuft.rotation = Vector3(0.25 * cos(angle), 0.0, 0.25 * sin(angle))
		_full.add_child(tuft)
		_full.add_child(_mesh(_sphere(0.09, 0.14, 5, 2), bloom, offset * 0.85 + Vector3(0.0, 0.85, 0.0)))
	_empty.add_child(_mesh(_sphere(0.3, 0.22, 5, 2), _material(Color(0.46, 0.38, 0.22)),
			Vector3(0.0, 0.08, 0.0)))


func _mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	return node


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


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
