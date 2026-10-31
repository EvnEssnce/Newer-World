extends TestCase
## Maps (game/maps/): the terrain's heights and surface (TerrainShape), the
## scattered decor (DecorScatter), spawn points, gates, and every map's markers.

const MAPS: Array[String] = ["test_map", "ashvale"]


func _shape() -> TerrainShape:
	var s := TerrainShape.new()
	s.size = 120.0
	s.cell = 4.0
	s.noise_seed = 3
	s.noise_amplitude = 4.0
	s.edge_start = 45.0
	s.edge_height = 20.0
	s.hills.append([Vector2(-20, 20), 15.0, 6.0])
	s.flats.append([Vector2(10, -10), 8.0, 6.0, NAN, "stone"])
	s.flats.append([Vector2(-30, -30), 6.0, 6.0, 3.0, "dirt"])
	s.roads.append([PackedVector2Array([Vector2(-50, 0), Vector2(50, 0)]), 4.0])
	s.build()
	return s


func test_vertex_heights_are_whole_quanta() -> void:
	var s := _shape()
	for iz in range(0, s.cells() + 1, 7):
		for ix in range(0, s.cells() + 1, 5):
			var h := s.vertex_height(ix, iz)
			assert_eq(h, TerrainShape.quantize(h))


func test_the_surface_passes_through_every_vertex_and_is_linear_between() -> void:
	var s := _shape()
	for p: Vector2i in [Vector2i(3, 4), Vector2i(10, 12), Vector2i(29, 1)]:
		var xz := s.vertex_xz(p.x, p.y)
		assert_almost(s.surface_height(xz.x, xz.y), s.vertex_height(p.x, p.y))
		# Halfway along the cell's diagonal: the average of its two ends.
		var mid := xz + Vector2(s.cell, s.cell) / 2.0
		assert_almost(s.surface_height(mid.x, mid.y),
				(s.vertex_height(p.x, p.y) + s.vertex_height(p.x + 1, p.y + 1)) / 2.0)


func test_faces_cover_the_grid_facing_up() -> void:
	var s := _shape()
	var faces := s.faces()
	assert_eq(faces.size(), s.cells() * s.cells() * 6)
	for i in range(0, faces.size(), 3 * 97):
		assert_true(Plane(faces[i], faces[i + 1], faces[i + 2]).normal.y > 0.0, "triangle %d faces up" % (i / 3))


func test_flats_are_level() -> void:
	var s := _shape()
	var level := s.flat_height(0)
	for offset: Vector2 in [Vector2.ZERO, Vector2(5, 0), Vector2(-3, 4), Vector2(0, -5.5)]:
		var p := Vector2(10, -10) + offset
		assert_eq(s.surface_height(p.x, p.y), level, "flat at %s" % p)
	assert_eq(s.flat_height(1), 3.0, "a fixed height")
	assert_eq(s.surface_height(-30, -30), 3.0)


func test_an_earlier_flat_wins_an_overlap() -> void:
	var s := TerrainShape.new()
	s.size = 80.0
	s.flats.append([Vector2(0, 0), 10.0, 4.0, 2.0, "stone"])
	s.flats.append([Vector2(8, 0), 10.0, 4.0, 5.0, "grass"])
	s.build()
	assert_eq(s.surface_height(4, 0), 2.0)
	assert_eq(s.flat_at(4, 0), 0)
	assert_eq(s.surface_height(16, 0), 5.0)


func test_edge_mountains_rise() -> void:
	var s := _shape()
	assert_true(s.surface_height(58, 30) > s.surface_height(30, 30) + 8.0)


func test_the_same_fields_build_the_same_ground() -> void:
	assert_eq(_shape().faces(), _shape().faces())


func test_road_distance() -> void:
	var s := _shape()
	assert_almost(s.road_distance(0, 0), -2.0)
	assert_almost(s.road_distance(0, 7), 5.0)
	assert_eq(TerrainShape.new().road_distance(0, 0), INF)


func test_decor_is_seeded_and_keeps_clear() -> void:
	var s := _shape()
	var scatter := DecorScatter.new()
	scatter.threshold = -1.0  # everywhere is forest
	scatter.keep_out.append(Vector3(20, 20, 6))
	var trees := scatter.scatter(s, 5, 60, 0.8, 1.2)
	assert_eq(trees, scatter.scatter(s, 5, 60, 0.8, 1.2), "same seed, same trees")
	assert_true(trees.size() > 20, "most fit")
	for t in trees:
		var p := Vector2(t.x, t.z)
		assert_true((p - Vector2(20, 20)).length() >= 6.0, "keep-out circle")
		assert_true((p - Vector2(10, -10)).length() >= 8.0 + 3.0, "off the flat and half its blend")
		assert_true(s.road_distance(t.x, t.z) >= scatter.road_margin, "off the road")
		assert_eq(t.y, s.surface_height(t.x, t.z), "on the ground")
		for other in trees:
			if other != t:
				assert_true((p - Vector2(other.x, other.z)).length() >= scatter.spacing * minf(t.w, other.w))


func test_decor_forests_follow_the_noise() -> void:
	var scatter := DecorScatter.new()
	scatter.threshold = 2.0  # nowhere is forest...
	assert_eq(scatter.scatter(_shape(), 5, 40, 1.0, 1.0).size(), 0)
	assert_true(scatter.scatter(_shape(), 5, 40, 1.0, 1.0, false).size() > 0, "...unless density is even")


func test_nearest_spawn_point() -> void:
	var points := PackedVector3Array([Vector3(0, 2, 100), Vector3(-100, 0, 0), Vector3(30, 1, -80)])
	assert_eq(GameMap.nearest_point(points, Vector3(-60, 0, 10)), Vector3(-100, 0, 0))
	assert_eq(GameMap.nearest_point(points, Vector3(20, 50, -40)), Vector3(30, 1, -80), "horizontal distance")
	assert_eq(GameMap.nearest_point(PackedVector3Array(), Vector3(1, 2, 3)), Vector3(1, 2, 3))


func test_palisade_gates() -> void:
	var palisade := Palisade.new()
	palisade.radius = 30.0
	palisade.gate_width = 8.0
	palisade.gates = PackedFloat32Array([0.0, 270.0])
	assert_true(palisade.in_gate(5.0))
	assert_true(palisade.in_gate(355.0), "wraps around")
	assert_true(palisade.in_gate(268.0))
	assert_false(palisade.in_gate(90.0))
	assert_false(palisade.in_gate(20.0))
	palisade.free()


func test_hex_prisms_are_the_same_everywhere() -> void:
	var shape := MapDecor.hex_prism(0.5, 2.0)
	assert_eq(shape.points.size(), 12)
	assert_almost(shape.points[0].x, 0.5)
	assert_almost(shape.points[11].y, 1.0)


func test_the_configured_map_exists() -> void:
	assert_true(ResourceLoader.exists(GameMap.path_for(GameMap.current_id())), GameMap.current_id())


func test_every_map_has_valid_markers() -> void:
	for id in MAPS:
		var map := GameMap.instantiate_map(id)
		assert_true(map != null, id)
		if map == null:
			continue
		for marker in map.markers("EnemySpawns"):
			assert_true(Tuning.has_file("enemy_" + String(marker.get_meta("kind", "husk"))), "%s %s" % [id, marker.name])
		assert_true(map.markers("GatherNodes").size() > 0, id)
		for marker in map.markers("GatherNodes"):
			assert_true("node_" + String(marker.get_meta("kind", "")) in Tuning.get_sections("gathering"),
					"%s %s" % [id, marker.name])
		assert_true(map.markers("Stations").size() > 0, id)
		for marker in map.markers("Stations"):
			assert_true("station_" + String(marker.get_meta("kind", "")) in Tuning.get_sections("stations"),
					"%s %s" % [id, marker.name])
		assert_true(map.markers("PlayerSpawns").size() > 0, id)
		map.free()


func test_the_zone_has_every_camp_kind_and_level_spawn_points() -> void:
	var map := GameMap.instantiate_map("ashvale")
	var kinds := {}
	for marker in map.markers("EnemySpawns"):
		kinds[String(marker.get_meta("kind", "husk"))] = true
		if marker.has_meta("gear_score"):
			assert_true(int(marker.get_meta("gear_score")) >= 100, marker.name)
	for kind in ["husk", "dummy", "thorn", "seer", "crag"]:
		assert_true(kinds.has(kind), "a %s is placed" % kind)
	var terrain := map.get_node("Terrain") as Terrain
	assert_eq(terrain.size, 400.0)
	for marker in map.markers("PlayerSpawns"):
		var p := marker.position
		var h := terrain.surface_height(p.x, p.z)
		for offset: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-0.7, -0.7), Vector2(0.7, -0.7)]:
			var q := Vector2(p.x, p.z) + offset * GameMap.SPAWN_CLEARANCE
			assert_eq(terrain.surface_height(q.x, q.y), h, "%s: level ground around it" % marker.name)
	map.free()
