class_name GameMap
extends Node3D
## The level a server runs: game/maps/<id>.tscn, chosen by data/world.cfg
## [map] id (the server's choice reaches clients with the tuning, so both load
## the same one). World adds it as World/Map, at the origin, before anything
## reads its markers.
##
## A map scene holds the ground and walls (static bodies on layer 1, which
## players, enemies, projectiles, aiming and the enemies' navmesh all use),
## its light and sky, and these marker groups (Marker3D children):
## - EnemySpawns: one enemy each (metadata/kind, camp, gear_score; see
##   World._spawn_enemies). Ids count them from -1: add new ones last.
## - GatherNodes: gathering nodes (metadata/kind). Ids are their indices.
## - Stations: crafting stations (metadata/kind).
## - PlayerSpawns: where players appear: a new arrival at the first one, a
##   respawn at the one nearest where they fell. Each needs level ground at
##   least SPAWN_CLEARANCE m around it (players appear in a ring there): on a
##   Terrain, a flat of radius SPAWN_CLEARANCE + 1.5 cells or more.
## - Props: buildings, walls, braziers (BlockoutBuilding, Palisade...).
## With a Terrain child, every marker in those groups and every direct child
## of Props is put on the ground when the map loads (their y in the scene
## doesn't matter; a prop with metadata/keep_y = true keeps its own).

const DIR := "res://game/maps/"
const MARKER_GROUPS: Array[String] = ["EnemySpawns", "GatherNodes", "Stations", "PlayerSpawns"]
const PROPS := "Props"
## Meters of level ground a player spawn point needs around it.
const SPAWN_CLEARANCE := 4.0

## The map's Terrain, or null (a map built from boxes, like the test map).
var terrain: Terrain


## The scene path of map `id`.
static func path_for(id: String) -> String:
	return DIR + id + ".tscn"


## The map data/world.cfg names (with --tune overrides; on a client, the server's).
static func current_id() -> String:
	return String(Tuning.get_value("world", "map", "id"))


## A new instance of map `id`, or null (logged) if there's no such map.
static func instantiate_map(id: String) -> GameMap:
	var path := path_for(id)
	if not ResourceLoader.exists(path):
		push_error("No map '%s' (%s): check data/world.cfg [map] id" % [id, path])
		return null
	return (load(path) as PackedScene).instantiate() as GameMap


## Of `points`, the one nearest `position` (horizontally); `position` itself
## if there are none.
static func nearest_point(points: PackedVector3Array, position: Vector3) -> Vector3:
	var best := position
	var best_distance := INF
	for point in points:
		var d := Vector2(point.x - position.x, point.z - position.z).length_squared()
		if d < best_distance:
			best_distance = d
			best = point
	return best


func _ready() -> void:
	terrain = get_node_or_null("Terrain") as Terrain
	snap_markers()


## Puts every marker of MARKER_GROUPS and every prop on the ground (with a
## Terrain).
func snap_markers() -> void:
	if terrain == null:
		return
	for group_name in MARKER_GROUPS:
		for marker in markers(group_name):
			marker.position.y = terrain.surface_height(marker.position.x, marker.position.z)
	var props := get_node_or_null(PROPS)
	if props:
		for prop: Node in props.get_children():
			if prop is Node3D and not prop.get_meta("keep_y", false):
				var p: Vector3 = (prop as Node3D).position
				(prop as Node3D).position.y = terrain.surface_height(p.x, p.z)


## The ground height at (x, z): the terrain's, else 0 (a flat box map).
func ground_height(x: float, z: float) -> float:
	return terrain.surface_height(x, z) if terrain else 0.0


## The Marker3D children of group `group_name` (empty if the map has none).
func markers(group_name: String) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var node := get_node_or_null(group_name)
	if node:
		for child: Node in node.get_children():
			if child is Marker3D:
				out.append(child)
	return out


## The group node (EnemySpawns, GatherNodes, Stations), or null.
func group_node(group_name: String) -> Node:
	return get_node_or_null(group_name)


## Where players appear (PlayerSpawns markers); the origin if there are none.
func player_spawns() -> PackedVector3Array:
	var out := PackedVector3Array()
	for marker in markers("PlayerSpawns"):
		out.append(marker.position)
	if out.is_empty():
		out.append(Vector3.ZERO)
	return out
