@tool
class_name Palisade
extends StaticBody3D
## A placeholder ring of log posts around a town, with gaps for gates: box
## colliders (layer 1) along a circle, posts drawn with a MultiMesh. Its origin
## is the ring's centre on the ground (under the map's Props node, GameMap sets
## it on the ground). The colliders' corners use cos/sin rounded to 1/4096, so
## every platform builds the same walls (prediction).

## Meters from the centre to the wall.
@export var radius := 36.0
@export var height := 3.2
## Degrees around the ring where gates are: 0 = east (+X), 90 = south (+Z),
## 180 = west, 270 = north.
@export var gates := PackedFloat32Array([0.0, 180.0, 270.0])
## Meters of opening per gate.
@export var gate_width := 8.0
## Meters per wall segment (one collider each).
@export var segment := 3.0
@export_tool_button("Rebuild") var _rebuild_button := rebuild

var _built: Array[Node] = []


func _ready() -> void:
	rebuild()


static func _q(v: float) -> float:
	return roundf(v * 4096.0) / 4096.0


## Whether a point at `degrees` around the ring falls in a gate.
func in_gate(degrees: float) -> bool:
	var half := rad_to_deg(gate_width / 2.0 / maxf(radius, 0.1))
	for gate in gates:
		var d := absf(fposmod(degrees - gate + 180.0, 360.0) - 180.0)
		if d < half:
			return true
	return false


func rebuild() -> void:
	for node in _built:
		if is_instance_valid(node):
			node.queue_free()
	_built.clear()
	var count := maxi(8, roundi(TAU * radius / segment))
	var corners := PackedVector3Array()
	for i in count + 1:
		var a := TAU * i / count
		corners.append(Vector3(_q(cos(a)) * radius, 0.0, _q(sin(a)) * radius))
	var posts := PackedVector3Array()
	for i in count:
		var mid_degrees := 360.0 * (i + 0.5) / count
		if in_gate(mid_degrees):
			continue
		var a := corners[i]
		var b := corners[i + 1]
		var along := b - a
		var length := along.length()
		var x_axis := along / length
		var z_axis := x_axis.cross(Vector3.UP)
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(length, height, 0.6)
		collision.shape = box
		collision.transform = Transform3D(Basis(x_axis, Vector3.UP, z_axis), (a + b) / 2.0 + Vector3.UP * height / 2.0)
		_add(collision)
		var steps := maxi(1, roundi(length / 0.5))
		for k in steps:
			posts.append(a + along * (k + 0.5) / steps)
	var post := CylinderMesh.new()
	post.top_radius = 0.22
	post.bottom_radius = 0.26
	post.height = 1.0
	post.radial_segments = 5
	post.rings = 0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.33, 0.22)
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	post.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = post
	mm.instance_count = posts.size()
	for i in posts.size():
		var h := height + 0.4 * fposmod(i * 0.618, 1.0)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.0, h + 0.5, 1.0)),
				posts[i] + Vector3.UP * (h - 0.5) / 2.0))
		var tint := 0.85 + 0.25 * fposmod(i * 0.381, 1.0)
		mm.set_instance_color(i, Color(tint, tint, tint))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	_add(node)


func _add(node: Node) -> void:
	add_child(node)
	_built.append(node)
