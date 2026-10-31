@tool
class_name MapDecor
extends StaticBody3D
## Blockout trees and rocks scattered over a map's Terrain (DecorScatter):
## low-poly shapes drawn with MultiMeshes, trunks and rocks colliding (layer
## 1: players, enemies and projectiles stop at them; the enemies' navmesh
## goes around them). Placeholders until the CC0 packs replace them.
## Built on every machine when the map loads; kept off roads, flats (town,
## camps, spawn points), the map's markers and its props (metadata/clearance,
## meters, default 5).

@export var terrain_path := NodePath("../Terrain")
@export var seed_value := 11
@export var tree_count := 520
@export var rock_count := 160
## Meters kept clear around each enemy spawn, gathering node, station and
## player spawn marker of the map.
@export var marker_clearance := 4.0
## Forests: noise above this (lower = more forest), and wood nodes pull
## forests around them.
@export var forest_threshold := 0.12
@export_tool_button("Rebuild") var _rebuild_button := rebuild

## What was placed (Vector4: x, ground y, z, scale), for tests and tools.
var trees: Array[Vector4] = []
var rocks: Array[Vector4] = []
var _built: Array[Node] = []


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for node in _built:
		if is_instance_valid(node):
			node.queue_free()
	_built.clear()
	var terrain := get_node_or_null(terrain_path) as Terrain
	if terrain == null:
		return
	var shape := terrain.shape()
	var scatter := DecorScatter.new()
	scatter.threshold = forest_threshold
	var map := get_parent()
	for group_name in ["EnemySpawns", "GatherNodes", "Stations", "PlayerSpawns"]:
		var group := map.get_node_or_null(group_name)
		if group == null:
			continue
		for marker: Node in group.get_children():
			if marker is Node3D:
				var p: Vector3 = (marker as Node3D).position
				var clearance := marker_clearance
				if group_name == "EnemySpawns" or group_name == "PlayerSpawns":
					clearance *= 2.0
				scatter.keep_out.append(Vector3(p.x, p.z, clearance))
				if group_name == "GatherNodes" and String(marker.get_meta("kind", "")) == "wood":
					scatter.boost_points.append(Vector2(p.x, p.z))
	var props := map.get_node_or_null(GameMap.PROPS)
	if props:
		for prop: Node in props.get_children():
			if prop is Node3D:
				var p: Vector3 = (prop as Node3D).position
				scatter.keep_out.append(Vector3(p.x, p.z, float(prop.get_meta("clearance", 5.0))))
	trees = scatter.scatter(shape, seed_value, tree_count, 0.8, 1.4)
	scatter.spacing = 2.5
	scatter.min_normal_y = 0.6
	rocks = scatter.scatter(shape, seed_value + 1, rock_count, 0.5, 1.6, false)
	_build_trees()
	_build_rocks()


func _add(node: Node) -> void:
	add_child(node)
	_built.append(node)


func _build_trees() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.32
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 0
	var low := CylinderMesh.new()
	low.top_radius = 0.0
	low.bottom_radius = 2.0
	low.height = 3.2
	low.radial_segments = 7
	low.rings = 0
	var high := CylinderMesh.new()
	high.top_radius = 0.0
	high.bottom_radius = 1.4
	high.height = 2.6
	high.radial_segments = 7
	high.rings = 0
	var trunks := _multimesh("Trunks", trunk, Color(0.4, 0.29, 0.2))
	var lows := _multimesh("FoliageLow", low, Color(0.2, 0.38, 0.2))
	var highs := _multimesh("FoliageHigh", high, Color(0.24, 0.43, 0.22))
	for mm in [trunks, lows, highs]:
		mm.multimesh.instance_count = trees.size()
	for i in trees.size():
		var t := trees[i]
		var s := t.w
		var base := Vector3(t.x, t.y - 0.4, t.z)
		var turn := Basis(Vector3.UP, fposmod(t.x * 1.7 + t.z * 0.9, TAU)).scaled(Vector3.ONE * s)
		var tint := 0.85 + 0.3 * fposmod(t.x * 0.37 + t.z * 0.61, 1.0)
		trunks.multimesh.set_instance_transform(i, Transform3D(turn, base + Vector3.UP * 1.5 * s))
		lows.multimesh.set_instance_transform(i, Transform3D(turn, base + Vector3.UP * 3.6 * s))
		highs.multimesh.set_instance_transform(i, Transform3D(turn, base + Vector3.UP * 5.2 * s))
		lows.multimesh.set_instance_color(i, Color(tint, tint, tint))
		highs.multimesh.set_instance_color(i, Color(tint, tint, tint))
		trunks.multimesh.set_instance_color(i, Color.WHITE)
		var collision := CollisionShape3D.new()
		collision.shape = hex_prism(0.35 * s, 4.0 * s)
		collision.position = Vector3(t.x, t.y + 1.6 * s, t.z)
		_add(collision)


func _build_rocks() -> void:
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 1.4
	rock.radial_segments = 6
	rock.rings = 3
	var rocks_mm := _multimesh("Rocks", rock, Color(0.5, 0.49, 0.47))
	rocks_mm.multimesh.instance_count = rocks.size()
	for i in rocks.size():
		var r := rocks[i]
		var s := r.w
		var turn := Basis(Vector3.UP, fposmod(r.x * 2.3 + r.z * 1.1, TAU)).scaled(Vector3(s * 1.2, s, s))
		rocks_mm.multimesh.set_instance_transform(i, Transform3D(turn, Vector3(r.x, r.y + 0.1 * s, r.z)))
		var tint := 0.8 + 0.35 * fposmod(r.x * 0.53 + r.z * 0.29, 1.0)
		rocks_mm.multimesh.set_instance_color(i, Color(tint, tint, tint))
		var collision := CollisionShape3D.new()
		collision.shape = hex_prism(1.0 * s, 1.6 * s)
		collision.position = Vector3(r.x, r.y + 0.1 * s, r.z)
		_add(collision)


## A six-sided upright prism (a cheap stand-in for a cylinder: the enemies'
## navmesh parses a CylinderShape3D into hundreds of triangles). No trig, so
## every platform builds the same one.
static func hex_prism(radius: float, height: float) -> ConvexPolygonShape3D:
	const SIN60 := 0.8660254037844386
	var corners := [Vector2(1.0, 0.0), Vector2(0.5, SIN60), Vector2(-0.5, SIN60),
			Vector2(-1.0, 0.0), Vector2(-0.5, -SIN60), Vector2(0.5, -SIN60)]
	var points := PackedVector3Array()
	for y: float in [-height / 2.0, height / 2.0]:
		for c: Vector2 in corners:
			points.append(Vector3(c.x * radius, y, c.y * radius))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


func _multimesh(node_name: String, mesh: PrimitiveMesh, color: Color) -> MultiMeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	mesh.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	_add(node)
	return node
