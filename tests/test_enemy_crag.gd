extends TestCase
## The Cragmaw's role (data/enemy_crag.cfg): a slow-turning bruiser whose slam
## is a frontal cone, that barely staggers and plants its feet while swinging.
## Hand-built params in its spirit, not read from data/. The camp is at the origin.

const DELTA := 1.0 / 60.0
const HOME := Vector3.ZERO
const TARGET_RADIUS := 0.5
const TARGET_HEIGHT := 2.2

var params: EnemyParams
var brain: EnemyBrain
var rng: RandomNumberGenerator


func before_each() -> void:
	params = EnemyParams.new()
	params.move_speed = 2.6
	params.wander_speed = 1.0
	params.return_speed = 5.0
	params.turn_speed = deg_to_rad(150.0)
	params.stagger_multiplier = 0.25
	params.aggro_range = 7.0
	params.leash_range = 18.0
	params.attack_range = 2.6
	params.attack_cooldown_ticks = 108
	params.wander_radius = 3.0
	params.wander_pause_ticks = 0
	params.threat_per_damage = 1.0
	params.threat_proximity = 10.0
	params.threat_switch_ratio = 1.1
	params.threat_decay_factor = 1.0
	var attack := AttackParams.new()
	attack.windup_ticks = 72
	attack.active_ticks = 9
	attack.recovery_ticks = 60
	attack.shape = AttackParams.SHAPE_RADIAL
	attack.hitbox_range = 3.2
	attack.hitbox_height = 2.2
	attack.hitbox_arc = deg_to_rad(120.0)
	attack.move_multiplier = 0.0
	attack.breaks_block = true
	params.attack = attack
	brain = EnemyBrain.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 1


func _step(pos: Vector3, targets: Dictionary) -> Vector2:
	return brain.step(pos, HOME, targets, params, DELTA, rng)


func _slam_hits(yaw: float, target: Vector3) -> bool:
	return MeleeHitbox.hits(HOME, yaw, params.attack, target, TARGET_RADIUS, TARGET_HEIGHT)


func test_takes_over_a_second_to_face_a_target_behind_it() -> void:
	# Facing -Z (yaw 0); the player stands 5 m behind it, out of reach.
	var target := Vector3(0, 0, 5)
	var goal := PlayerState.yaw_for_direction(Vector2(target.x, target.z))
	var ticks := 0
	while absf(angle_difference(brain.yaw, goal)) > 0.01 and ticks < 600:
		_step(HOME, {1: target})
		ticks += 1
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE)
	# 180 degrees at 150 degrees/s = 1.2 s = 72 ticks.
	assert_true(ticks >= 70 and ticks <= 74, "turned around in %d ticks" % ticks)


func test_turns_no_faster_than_turn_speed_per_tick() -> void:
	_step(HOME, {1: Vector3(0, 0, 5)})
	assert_almost(absf(brain.yaw), params.turn_speed * DELTA, 0.0001)


func test_slam_hits_in_front_and_misses_behind_and_wide() -> void:
	assert_true(_slam_hits(0.0, Vector3(0, 0, -2)), "straight ahead")
	assert_true(_slam_hits(0.0, Vector3(0, 0, -3.5)), "at the edge: range + body radius")
	assert_false(_slam_hits(0.0, Vector3(0, 0, -3.9)), "beyond its reach")
	assert_true(_slam_hits(0.0, Vector3(1.5, 0, -2)), "inside the 120 degree cone")
	assert_false(_slam_hits(0.0, Vector3(2, 0, 0)), "beside it")
	assert_false(_slam_hits(0.0, Vector3(0, 0, 2)), "behind it")
	assert_false(_slam_hits(0.0, Vector3(-2, 0, 1)), "behind its flank")


func test_a_player_circling_it_during_the_windup_ends_up_outside_the_cone() -> void:
	# The player starts in front, 1.5 m away, and runs around it at 5.5 m/s.
	var radius := 1.5
	var angular := 5.5 / radius
	var angle := 0.0
	var target := Vector3(0, 0, -radius)
	_step(HOME, {1: target})
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK, "starts its slam")
	while brain.attack_tick < params.attack.windup_ticks:
		angle += angular * DELTA
		target = Vector3(sin(angle), 0, -cos(angle)) * radius
		_step(HOME, {1: target})
	assert_true(brain.is_attack_active(params), "the slam comes down")
	assert_false(_slam_hits(brain.yaw, target), "the circling player is out of the cone")


func test_a_player_standing_in_front_during_the_windup_is_hit() -> void:
	var target := Vector3(0.8, 0, -1.8)
	_step(HOME, {1: target})
	while brain.attack_tick < params.attack.windup_ticks:
		_step(HOME, {1: target})
	assert_true(brain.is_attack_active(params))
	assert_true(_slam_hits(brain.yaw, target))


func test_the_slam_is_committed_once_it_comes_down() -> void:
	var target := Vector3(0, 0, -2)
	_step(HOME, {1: target})
	while brain.attack_tick < params.attack.windup_ticks:
		_step(HOME, {1: target})
	var committed := brain.yaw
	var behind := Vector3(0, 0, 2)
	for i in params.attack.active_ticks + 10:
		_step(HOME, {1: behind})
	assert_almost(brain.yaw, committed, 0.0001, "no turning after the windup")


func test_plants_its_feet_through_the_whole_swing() -> void:
	var target := Vector3(0, 0, -2)
	var velocity := _step(HOME, {1: target})
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK)
	var moved := false
	# The player backs off to 4 m: it still doesn't follow until the swing ends.
	for i in params.attack.total_ticks() - 1:
		target.z = -4.0
		velocity = _step(HOME, {1: target})
		if velocity != Vector2.ZERO:
			moved = true
	assert_false(moved, "move_multiplier 0: no movement while slamming")
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK)


func test_a_heavy_staggers_it_only_a_quarter_as_long() -> void:
	var target := Vector3(0, 0, -2)
	_step(HOME, {1: target})
	_step(HOME, {1: target})
	assert_true(brain.is_attacking())
	# A 0.8 s stagger (48 ticks) scaled as Enemy.take_hit does.
	var ticks := roundi(48 * params.stagger_multiplier)
	assert_eq(ticks, 12)
	brain.stagger(ticks)
	assert_false(brain.is_attacking(), "the windup is interrupted")
	var staggered := 0
	while brain.mode == EnemyBrain.Mode.STAGGERED and staggered < 100:
		_step(HOME, {1: target})
		staggered += 1
	assert_eq(staggered, 12, "staggered for a quarter of the time")
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE)


func test_a_tiny_stagger_scaled_to_nothing_does_not_interrupt() -> void:
	var target := Vector3(0, 0, -2)
	_step(HOME, {1: target})
	_step(HOME, {1: target})
	var tick := brain.attack_tick
	brain.stagger(roundi(1 * params.stagger_multiplier))
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK)
	assert_eq(brain.attack_tick, tick, "the swing goes on")
