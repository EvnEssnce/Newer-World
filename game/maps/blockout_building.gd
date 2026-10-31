@tool
class_name BlockoutBuilding
extends StaticBody3D
## A placeholder building built from boxes: walls (collide, layer 1), an
## optional pitched roof and door, and an optional ember glow on top (spawn
## braziers). Its origin is the middle of its base; the front (door) faces -Z.
## Put it under the map's Props node to have it set on the ground when the map
## loads (GameMap). Replaced by CC0 models later.

@export var size := Vector3(6.0, 3.5, 5.0):
	set(value):
		size = value
		_queue_rebuild()
## Meters of roof above the walls (0 = no roof: a pillar, a wall, a plinth).
@export var roof_height := 2.0:
	set(value):
		roof_height = value
		_queue_rebuild()
@export var door := true:
	set(value):
		door = value
		_queue_rebuild()
## An ember glow on top (spawn braziers): cosmetic.
@export var glow := false:
	set(value):
		glow = value
		_queue_rebuild()
@export var wall_color := Color(0.62, 0.55, 0.45):
	set(value):
		wall_color = value
		_queue_rebuild()
@export var roof_color := Color(0.45, 0.25, 0.2):
	set(value):
		roof_color = value
		_queue_rebuild()

var _built: Array[Node] = []


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if is_inside_tree():
		rebuild()


func rebuild() -> void:
	for node in _built:
		if is_instance_valid(node):
			node.queue_free()
	_built.clear()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = Vector3.UP * size.y / 2.0
	_add(collision)
	_box(size, Vector3.UP * size.y / 2.0, wall_color)
	if roof_height > 0.0:
		var roof := PrismMesh.new()
		roof.size = Vector3(size.x + 0.6, roof_height, size.z + 0.6)
		_mesh(roof, Vector3.UP * (size.y + roof_height / 2.0), roof_color)
	if door:
		var door_size := Vector3(minf(1.2, size.x * 0.4), minf(2.2, size.y * 0.7), 0.1)
		_box(door_size, Vector3(0.0, door_size.y / 2.0, -size.z / 2.0 - 0.04), Color(0.25, 0.17, 0.12))
	if glow:
		var ember := BoxMesh.new()
		ember.size = Vector3(size.x * 0.5, 0.35, size.z * 0.5)
		var node := _mesh(ember, Vector3.UP * (size.y + 0.2), Color(1.0, 0.55, 0.15))
		var material := node.mesh.surface_get_material(0) as StandardMaterial3D
		material.emission_enabled = true
		material.emission = Color(1.0, 0.45, 0.1)
		material.emission_energy_multiplier = 2.5
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.3)
		light.omni_range = 7.0
		light.position = Vector3.UP * (size.y + 0.8)
		_add(light)


func _box(box_size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	return _mesh(mesh, at, color)


func _mesh(mesh: PrimitiveMesh, at: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	_add(node)
	return node


func _add(node: Node) -> void:
	add_child(node)
	_built.append(node)
