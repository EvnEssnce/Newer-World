@tool
class_name Terrain
extends StaticBody3D
## A map's ground (layer 1, like every wall): a TerrainShape turned into a
## flat-shaded low-poly mesh and a matching collision shape, plus invisible
## walls around the edge. Built in code on every machine when the map loads
## (and in the editor: the Rebuild button after moving a marker).
##
## Shaped by marker children:
## - Hills/<Marker3D>: a hill (or a hollow) centred on the marker;
##   position.y = its height (m), metadata/radius (m).
## - Flats/<Marker3D>: a level area; metadata/radius (m), metadata/blend (m
##   of slope around it, default 8), metadata/ground ("grass", "dirt" or
##   "stone"). Its height is the ground's own at its centre, or position.y with
##   metadata/fixed_height = true. Spawn points, camps and the town sit on one;
##   an earlier flat wins where two overlap (its colour, and it's levelled last).
## - Roads/<Node3D>/<Marker3D>...: a road through its markers in order
##   (colour only); metadata/width on the road node (m, default 4).
##
## Markers under the map's EnemySpawns, GatherNodes, Stations and PlayerSpawns
## are snapped onto this ground when the map loads (GameMap).

## Meters along each side (the map is centred on the origin).
@export var size := 400.0
## Meters per grid cell (bigger = coarser, more low-poly facets).
@export var cell := 4.0
@export var noise_seed := 1
## Meters: roughly how far the rolling noise goes up and down.
@export var noise_amplitude := 4.0
## Meters between noise hills (roughly).
@export var noise_wavelength := 90.0
## Meters from the centre where the edge mountains start, and their height.
@export var edge_start := 165.0
@export var edge_height := 40.0
## Meters: height of the invisible walls on the map's edge (0 = none).
@export var boundary_wall_height := 80.0
@export_tool_button("Rebuild") var _rebuild_button := rebuild

var _shape: TerrainShape
var _built: Array[Node] = []


func _ready() -> void:
	rebuild()


## The ground's maths (built on first use).
func shape() -> TerrainShape:
	if _shape == null:
		_shape = make_shape()
	return _shape


## The ground height at a point (map x/z: the map sits at the origin).
func surface_height(x: float, z: float) -> float:
	return shape().surface_height(x, z) + position.y


## A fresh TerrainShape from the exports and marker children.
func make_shape() -> TerrainShape:
	var s := TerrainShape.new()
	s.size = size
	s.cell = cell
	s.noise_seed = noise_seed
	s.noise_amplitude = noise_amplitude
	s.noise_wavelength = noise_wavelength
	s.edge_start = edge_start
	s.edge_height = edge_height
	for marker in _markers("Hills"):
		s.hills.append([Vector2(marker.position.x, marker.position.z),
				float(marker.get_meta("radius", 20.0)), marker.position.y])
	for marker in _markers("Flats"):
		s.flats.append([Vector2(marker.position.x, marker.position.z),
				float(marker.get_meta("radius", 10.0)), float(marker.get_meta("blend", 8.0)),
				TerrainShape.quantize(marker.position.y) if marker.get_meta("fixed_height", false) else NAN,
				String(marker.get_meta("ground", "grass"))])
	var roads := get_node_or_null("Roads")
	if roads:
		for road: Node in roads.get_children():
			var points := PackedVector2Array()
			for marker: Node in road.get_children():
				if marker is Node3D:
					var p: Vector3 = (road as Node3D).position + (marker as Node3D).position \
							if road is Node3D else (marker as Node3D).position
					points.append(Vector2(p.x, p.z))
			if points.size() >= 2:
				s.roads.append([points, float(road.get_meta("width", 4.0))])
	s.build()
	return s


func _markers(group: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var node := get_node_or_null(group)
	if node:
		for child: Node in node.get_children():
			if child is Node3D:
				out.append(child)
	return out


## Builds (again) the mesh, the collision and the edge walls.
func rebuild() -> void:
	for node in _built:
		if is_instance_valid(node):
			node.queue_free()
	_built.clear()
	_shape = make_shape()
	var faces := _shape.faces()
	var collision := CollisionShape3D.new()
	collision.name = "GroundCollision"
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	collision.shape = concave
	_add(collision)
	var mesh := MeshInstance3D.new()
	mesh.name = "GroundMesh"
	mesh.mesh = _mesh(faces)
	_add(mesh)
	if boundary_wall_height > 0.0:
		var half := size / 2.0
		for side: Vector3 in [Vector3(half + 0.5, 0, 0), Vector3(-half - 0.5, 0, 0),
				Vector3(0, 0, half + 0.5), Vector3(0, 0, -half - 0.5)]:
			var wall := CollisionShape3D.new()
			wall.name = "EdgeWall"
			var box := BoxShape3D.new()
			box.size = Vector3(1.0, boundary_wall_height, size + 2.0) if side.x != 0.0 \
					else Vector3(size + 2.0, boundary_wall_height, 1.0)
			wall.shape = box
			wall.position = side + Vector3.UP * boundary_wall_height / 2.0
			_add(wall)


func _add(node: Node) -> void:
	add_child(node)
	_built.append(node)


func _mesh(faces: PackedVector3Array) -> ArrayMesh:
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	normals.resize(faces.size())
	colors.resize(faces.size())
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var normal := Plane(a, b, c).normal
		var color := _shape.triangle_color((a + b + c) / 3.0, normal)
		for k in 3:
			normals[i + k] = normal
			colors[i + k] = color
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	mesh.surface_set_material(0, material)
	return mesh
