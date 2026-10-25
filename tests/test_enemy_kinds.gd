extends TestCase
## Every enemy kind in data/ (like ItemDatabase.validate on the real files):
## its tuning loads and validates (loot table, projectile), and every marker
## under the world's EnemySpawns names a kind that has a file.


func test_every_enemy_file_validates() -> void:
	var db := ItemDatabase.current()
	var files := Tuning.files_with_prefix("enemy_")
	assert_true(files.size() >= 5, "husk, dummy and the camp kinds")
	for file in files:
		var params := EnemyParams.from_tuning(file)
		assert_eq(params.validate(db), PackedStringArray(), file)


func test_validate_finds_problems() -> void:
	var db := ItemDatabase.current()
	var params := EnemyParams.new()
	params.max_health = 100.0
	params.move_speed = 3.0
	params.return_speed = 5.0
	params.aggro_range = 5.0
	params.leash_range = 10.0
	params.attack = AttackParams.new()
	params.attack.windup_ticks = 10
	params.attack.active_ticks = 2
	params.attack.recovery_ticks = 5
	assert_eq(params.validate(db), PackedStringArray())
	params.loot_table = "no_such_table"
	params.attack.projectile = "no_such_projectile"
	params.aggro_range = 20.0
	params.keep_distance = 3.0
	assert_eq(params.validate(db).size(), 4)


func test_every_spawn_marker_has_a_kind_file() -> void:
	var world: Node = load("res://game/world/world.tscn").instantiate()
	var kinds := {}
	var camps := {}
	for marker: Node in world.get_node("EnemySpawns").get_children():
		var kind: String = marker.get_meta("kind", "husk")
		kinds[kind] = true
		assert_true(Tuning.has_file("enemy_" + kind), "data/enemy_%s.cfg" % kind)
		var camp: String = marker.get_meta("camp", "")
		if not camp.is_empty():
			camps[camp] = camps.get(camp, 0) + 1
	world.free()
	for kind in ["husk", "dummy", "thorn", "seer", "crag"]:
		assert_true(kinds.has(kind), "a %s is placed" % kind)
	assert_eq(camps.size(), 3, "three camps")
