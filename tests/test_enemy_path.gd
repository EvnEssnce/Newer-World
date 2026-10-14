extends TestCase
## EnemyPath: following a path's corners, when it asks for a new one, and the
## brain walking around an obstacle with it (a scripted path, no navigation map).

const DELTA := 1.0 / 60.0
## The corner of the scripted way around a wall between the origin and GOAL.
const CORNER := Vector3(3, 0, -3)
const GOAL := Vector3(0, 0, -6)

var calls: Array = []
## What the scripted query returns (the start point is replaced by `from`).
var route: Array = [CORNER, GOAL]


func before_each() -> void:
	calls = []
	route = [CORNER, GOAL]


func _query(from: Vector3, to: Vector3) -> PackedVector3Array:
	calls.append([from, to])
	var result := PackedVector3Array([from])
	for point: Vector3 in route:
		result.append(point)
	return result


func _path() -> EnemyPath:
	return EnemyPath.new(_query, 30, 1.0, 0.3)


func test_heads_for_the_first_corner_not_the_goal() -> void:
	var path := _path()
	var to := path.steer(Vector3.ZERO, GOAL)
	assert_true(to.is_equal_approx(Vector2(3, -3)), "toward the corner: %s" % to)
	assert_false(path.is_direct(), "a corner is in the way")
	assert_eq(calls.size(), 1)


func test_passes_a_reached_corner_and_is_then_direct() -> void:
	var path := _path()
	path.steer(Vector3.ZERO, GOAL)
	var to := path.steer(Vector3(2.9, 0, -3), GOAL)
	assert_true(to.is_equal_approx(Vector2(-2.9, -3)), "on to the goal: %s" % to)
	assert_true(path.is_direct())


func test_no_path_goes_straight() -> void:
	var path := EnemyPath.new()
	var to := path.steer(Vector3.ZERO, GOAL)
	assert_true(to.is_equal_approx(Vector2(0, -6)))
	assert_true(path.is_direct())
	route = []
	var empty := _path()
	assert_true(empty.steer(Vector3.ZERO, GOAL).is_equal_approx(Vector2(0, -6)),
			"an empty result (navigation not ready) also goes straight")


func test_repaths_when_the_goal_moves_far_enough() -> void:
	var path := _path()
	path.steer(Vector3.ZERO, GOAL)
	path.steer(Vector3.ZERO, GOAL + Vector3(0.5, 0, 0))
	assert_eq(calls.size(), 1, "a small move keeps the path")
	path.steer(Vector3.ZERO, GOAL + Vector3(1.5, 0, 0))
	assert_eq(calls.size(), 2, "a bigger one asks again")


func test_repaths_on_its_timer() -> void:
	var path := EnemyPath.new(_query, 5, 1.0, 0.3)
	for i in 5:
		path.steer(Vector3.ZERO, GOAL)
	assert_eq(calls.size(), 1)
	path.steer(Vector3.ZERO, GOAL)
	assert_eq(calls.size(), 2, "every repath_ticks")


func test_repaths_when_the_map_changes() -> void:
	var path := _path()
	path.steer(Vector3.ZERO, GOAL)
	path.version = 7  # a wall went up: the map was rebaked
	path.steer(Vector3.ZERO, GOAL)
	assert_eq(calls.size(), 2)


func test_arrived_after_the_last_corner() -> void:
	var path := _path()
	path.steer(Vector3.ZERO, GOAL)
	assert_false(path.arrived())
	path.steer(CORNER, GOAL)
	path.steer(GOAL + Vector3(0.1, 0, 0), GOAL)
	assert_true(path.arrived())
	path.reset()
	assert_false(path.arrived())


# --- The brain with a path ---

func _brain_params() -> EnemyParams:
	var params := EnemyParams.new()
	params.move_speed = 3.0
	params.wander_speed = 1.0
	params.return_speed = 6.0
	params.turn_speed = TAU * 30.0
	params.aggro_range = 8.0
	params.leash_range = 20.0
	params.attack_range = 2.0
	params.attack_cooldown_ticks = 30
	params.wander_radius = 4.0
	params.threat_proximity = 10.0
	params.threat_switch_ratio = 1.1
	params.threat_decay_factor = 1.0
	var attack := AttackParams.new()
	attack.windup_ticks = 6
	attack.active_ticks = 2
	attack.recovery_ticks = 4
	params.attack = attack
	return params


func test_brain_chases_along_the_path() -> void:
	var params := _brain_params()
	var brain := EnemyBrain.new()
	brain.path = _path()
	var velocity := brain.step(Vector3.ZERO, Vector3.ZERO, {1: GOAL}, params, DELTA,
			RandomNumberGenerator.new())
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE)
	assert_true(velocity.is_equal_approx(Vector2(3, -3).normalized() * 3.0),
			"runs toward the corner at move_speed: %s" % velocity)


func test_brain_doesnt_swing_through_a_wall() -> void:
	# The target is in reach (1.5 m) but behind a wall: the path goes around.
	var params := _brain_params()
	var brain := EnemyBrain.new()
	route = [Vector3(2, 0, 0), Vector3(2, 0, -1.5), Vector3(0, 0, -1.5)]
	brain.path = _path()
	var velocity := brain.step(Vector3.ZERO, Vector3.ZERO, {1: Vector3(0, 0, -1.5)}, params,
			DELTA, RandomNumberGenerator.new())
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE, "no swing yet")
	assert_true(velocity.is_equal_approx(Vector2(3, 0)), "walks around: %s" % velocity)
	# Round the wall: in reach with nothing between, it swings.
	brain.step(Vector3(2, 0, 0), Vector3.ZERO, {1: Vector3(0, 0, -1.5)}, params, DELTA,
			RandomNumberGenerator.new())
	brain.step(Vector3(2, 0, -1.5), Vector3.ZERO, {1: Vector3(0, 0, -1.5)}, params, DELTA,
			RandomNumberGenerator.new())
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK)


func test_brain_returns_home_along_the_path() -> void:
	var params := _brain_params()
	var brain := EnemyBrain.new()
	brain.mode = EnemyBrain.Mode.RETURN
	route = [Vector3(3, 0, 3), Vector3.ZERO]
	brain.path = _path()
	var velocity := brain.step(Vector3(0, 0, 6), Vector3.ZERO, {}, params, DELTA,
			RandomNumberGenerator.new())
	assert_eq(brain.mode, EnemyBrain.Mode.RETURN)
	assert_true(velocity.is_equal_approx(Vector2(3, -3).normalized() * 6.0),
			"toward the first corner at return_speed: %s" % velocity)
