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


func _base_params() -> EnemyParams:
	var params := EnemyParams.new()
	params.gear_score = 100
	params.max_health = 1000.0
	params.move_speed = 3.0
	params.kill_xp = 100
	params.mastery_xp = 50
	params.attack = AttackParams.new()
	params.attack.damage = 100.0
	params.attack.block_stamina_damage = 20.0
	params.attack.windup_ticks = 30
	return params


func test_scaling_to_a_higher_gear_score() -> void:
	var base := _base_params()
	var scaled := base.scaled_by(150, 0.02, 0.01, 0.03)  # 10 steps of 5 GS
	assert_eq(scaled.gear_score, 150)
	assert_almost(scaled.max_health, 1000.0 * pow(1.02, 10))
	assert_almost(scaled.attack.damage, 100.0 * pow(1.01, 10))
	assert_almost(scaled.attack.block_stamina_damage, 20.0 * pow(1.01, 10))
	assert_eq(scaled.kill_xp, roundi(100 * pow(1.03, 10)))
	assert_eq(scaled.mastery_xp, roundi(50 * pow(1.03, 10)))
	assert_eq(scaled.move_speed, 3.0, "speeds don't scale")
	assert_eq(scaled.attack.windup_ticks, 30, "timings don't scale")
	assert_eq(base.max_health, 1000.0, "the kind's own params are untouched")
	assert_eq(base.attack.damage, 100.0)


func test_scaling_down_and_to_its_own_gear_score() -> void:
	var base := _base_params()
	assert_true(base.scaled_by(100, 0.02, 0.01, 0.03) == base, "its own GS: the same params")
	assert_true(base.scaled_by(50, 0.02, 0.01, 0.03).max_health < 1000.0, "weaker below")


func test_camp_markers_place_gear_scores() -> void:
	var world: Node = load("res://game/world/world.tscn").instantiate()
	for marker: Node in world.get_node("EnemySpawns").get_children():
		if marker.has_meta("gear_score"):
			assert_true(int(marker.get_meta("gear_score")) >= 100, marker.name)
	world.free()
