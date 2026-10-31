class_name EnemyNavigation
extends Node
## World/EnemyNav (server only): the walkable area enemies path on, a Godot
## navigation mesh on the world's navigation map.
##
## Baked once at startup (bake_static) from the map's static colliders on the
## world layer (ground, crates; players, enemies and summoned walls are on
## other layers). A summoned wall that blocks enemies (Shield Wall:
## ZoneSystem._add_wall_body) is added with add_wall and taken out with
## remove_wall: the mesh is baked again in the background (Recast on a worker
## thread, a few ms on the test map) from the cached static geometry plus every
## wall's footprint, then swapped in. `version` follows the map's iteration id,
## so every EnemyPath asks for a new path once the swapped map is live. Until
## the first map sync find_path returns nothing (enemies walk straight).
##
## Tuning in data/navigation.cfg [navmesh].

const FILE := "navigation"
## Below the wall's base, so its footprint reaches the ground surface.
const WALL_SINK := 0.3

## The navigation map's iteration id (changes when a new mesh is live).
var version := 0

# Counters (SUMMARY nav)
var bakes := 0
var path_queries := 0
var walls_added := 0
var last_bake_ms := 0.0
var max_bake_ms := 0.0

var _map := RID()
var _region := RID()
var _template: NavigationMesh
var _static_source: NavigationMeshSourceGeometryData3D
## zone id -> [outline: PackedVector3Array, base y, height]
var _walls: Dictionary[int, Array] = {}
var _wall_padding := 0.0
## The mesh baking in the background, or null.
var _baking: NavigationMesh = null
var _bake_started_usec := 0
## A wall changed while a bake ran: bake again when it's done.
var _dirty := false


## Bakes the walkable area from root's static colliders (synchronously, once).
func bake_static(root: Node3D) -> void:
	_map = root.get_world_3d().navigation_map
	_template = NavigationMesh.new()
	# Must match the map's cells or the map refuses the mesh.
	_template.cell_size = NavigationServer3D.map_get_cell_size(_map)
	_template.cell_height = NavigationServer3D.map_get_cell_height(_map)
	# Whole cells, as Recast uses them (it warns about anything else).
	var cell := _template.cell_size
	var cell_y := _template.cell_height
	_template.agent_radius = ceilf(Tuning.get_value(FILE, "navmesh", "agent_radius") / cell - 0.001) * cell
	_template.agent_height = ceilf(Tuning.get_value(FILE, "navmesh", "agent_height") / cell_y - 0.001) * cell_y
	_template.agent_max_climb = floorf(Tuning.get_value(FILE, "navmesh", "agent_max_climb") / cell_y + 0.001) * cell_y
	_template.agent_max_slope = Tuning.get_value(FILE, "navmesh", "agent_max_slope")
	_template.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_template.geometry_collision_mask = 1
	_wall_padding = Tuning.get_value(FILE, "navmesh", "wall_padding")
	_static_source = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_template, _static_source, root)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, _map)
	var start := Time.get_ticks_usec()
	var mesh := _new_mesh()
	NavigationServer3D.bake_from_source_geometry_data(mesh, _source_with_walls())
	_note_bake((Time.get_ticks_usec() - start) / 1000.0)
	NavigationServer3D.region_set_navigation_mesh(_region, mesh)
	if LaunchArgs.has_flag("verbose"):
		print("[server] navigation mesh baked: %d polygons, %.1f ms" % [
				mesh.get_polygon_count(), last_bake_ms])


## A wall that blocks enemies went up: a box of `size` (x = width, z = depth)
## standing on `base`, turned `yaw` around Y. Bakes the mesh again.
func add_wall(id: int, base: Vector3, yaw: float, size: Vector3) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var hx := size.x / 2.0 + _wall_padding
	var hz := size.z / 2.0 + _wall_padding
	var outline := PackedVector3Array()
	for corner: Vector2 in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
		outline.append(base + basis * Vector3(corner.x, 0.0, corner.y))
	_walls[id] = [outline, base.y - WALL_SINK, size.y + WALL_SINK]
	walls_added += 1
	_request_bake()


## The wall `id` came down: bakes the mesh again without it.
func remove_wall(id: int) -> void:
	if _walls.erase(id):
		_request_bake()


## Corners of a walkable path from `from` to `to` (or the nearest walkable
## point to it). Empty before the first bake is live: walk straight.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not _map.is_valid() or version == 0:
		return PackedVector3Array()
	path_queries += 1
	return NavigationServer3D.map_get_path(_map, from, to, true)


## A new EnemyPath on this navigation, with params' following tuning.
func new_path(params: EnemyParams) -> EnemyPath:
	return EnemyPath.new(find_path, params.repath_ticks, params.repath_distance,
			params.waypoint_reach)


func _physics_process(_delta: float) -> void:
	if not _map.is_valid():
		return
	version = NavigationServer3D.map_get_iteration_id(_map)
	if _baking != null and not NavigationServer3D.is_baking_navigation_mesh(_baking):
		_note_bake((Time.get_ticks_usec() - _bake_started_usec) / 1000.0)
		NavigationServer3D.region_set_navigation_mesh(_region, _baking)
		_baking = null
		if _dirty:
			_dirty = false
			_start_bake()


func _exit_tree() -> void:
	if _region.is_valid():
		NavigationServer3D.free_rid(_region)
		_region = RID()


func _request_bake() -> void:
	if _template == null:
		return
	if _baking != null:
		_dirty = true
	else:
		_start_bake()


func _start_bake() -> void:
	_baking = _new_mesh()
	_bake_started_usec = Time.get_ticks_usec()
	NavigationServer3D.bake_from_source_geometry_data_async(_baking, _source_with_walls())


func _new_mesh() -> NavigationMesh:
	return _template.duplicate() as NavigationMesh


## The static geometry plus every wall's footprint (cut out with the agent
## radius around it, like a crate).
func _source_with_walls() -> NavigationMeshSourceGeometryData3D:
	var source := NavigationMeshSourceGeometryData3D.new()
	# merge, not set_vertices/set_indices: set_indices refuses a mesh with more
	# indices than vertex floats (shared vertices: a big terrain).
	source.merge(_static_source)
	for wall: Array in _walls.values():
		source.add_projected_obstruction(wall[0], wall[1], wall[2], false)
	return source


func _note_bake(ms: float) -> void:
	bakes += 1
	last_bake_ms = ms
	max_bake_ms = maxf(max_bake_ms, ms)


func print_summary() -> void:
	print("SUMMARY nav bakes=%d max_bake_ms=%.1f walls=%d path_queries=%d version=%d" % [
			bakes, max_bake_ms, walls_added, path_queries, version])
