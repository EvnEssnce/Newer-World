extends TestCase
## The Cinder Seer's role in EnemyBrain: a caster that starts its cast from
## long range, stands still while casting, backs away from players who come
## too close between casts, waits in its band, and closes in when out of range.
## Hand-built params shaped like data/enemy_seer.cfg (not read from it).

const DELTA := 1.0 / 60.0
const HOME := Vector3.ZERO
const ATTACK_RANGE := 13.0
const KEEP_DISTANCE := 7.0

var params: EnemyParams
var brain: EnemyBrain
var rng: RandomNumberGenerator


func before_each() -> void:
	params = EnemyParams.new()
	params.move_speed = 3.2
	params.wander_speed = 1.2
	params.return_speed = 6.0
	params.turn_speed = TAU * 30.0  # faces any target within a tick
	params.stagger_multiplier = 1.0
	params.aggro_range = 10.0
	params.leash_range = 20.0
	params.attack_range = ATTACK_RANGE
	params.attack_cooldown_ticks = 132
	params.wander_radius = 3.0
	params.wander_pause_ticks = 0
	params.keep_distance = KEEP_DISTANCE
	params.retreat_speed = 3.0
	params.threat_per_damage = 1.0
	params.threat_proximity = 10.0
	params.threat_switch_ratio = 1.1
	params.threat_decay_factor = 1.0
	params.attack = _cast()
	brain = EnemyBrain.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 1


## A cast like the Seer's: no hitbox, one orb at the end of the windup.
func _cast() -> AttackParams:
	var attack := AttackParams.new()
	attack.windup_ticks = 48
	attack.active_ticks = 6
	attack.recovery_ticks = 30
	attack.move_multiplier = 0.0
	attack.shape = AttackParams.SHAPE_NONE
	attack.projectile = "cinder_orb"
	attack.projectile_tick = 48
	return attack


func _step(pos: Vector3, targets: Dictionary) -> Vector2:
	return brain.step(pos, HOME, targets, params, DELTA, rng)


## Hit from far away (beyond aggro_range): it now fights player 1.
func _pull() -> void:
	brain.add_threat(1, 50.0, params)


## Runs one whole cast from the start; returns the largest speed it asked for.
func _finish_cast(target: Dictionary) -> float:
	var fastest := 0.0
	for i in params.attack.total_ticks():
		fastest = maxf(fastest, _step(HOME, target).length())
	return fastest


func test_casts_from_long_range_instead_of_walking_in() -> void:
	_pull()
	var velocity := _step(HOME, {1: Vector3(12.5, 0, 0)})
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK, "12.5 m is in its 13 m attack_range: casts")
	assert_true(velocity.is_zero_approx(), "doesn't step toward the target to cast")
	assert_almost(brain.yaw, PlayerState.yaw_for_direction(Vector2(1, 0)), 0.001, "faces it")


func test_stands_still_through_the_cast() -> void:
	_pull()
	var target := {1: Vector3(10.0, 0, 0)}
	_step(HOME, target)
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK)
	assert_almost(_finish_cast(target), 0.0, 0.0001, "never moves while casting")
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE, "cast over")
	assert_true(brain.cooldown_ticks > 0, "cooldown running")


func test_close_target_during_the_cast_doesnt_pull_it_in() -> void:
	_pull()
	_step(HOME, {1: Vector3(12.0, 0, 0)})
	# The target rushes in mid-cast: the Seer finishes the cast where it stands.
	assert_almost(_finish_cast({1: Vector3(2.0, 0, 0)}), 0.0, 0.0001,
			"no step forward or back during the cast")


func test_backs_away_between_casts_when_too_close() -> void:
	_pull()
	var near := {1: Vector3(4.0, 0, 0)}
	_step(HOME, near)
	_finish_cast(near)
	var velocity := _step(HOME, near)
	assert_true(velocity.is_equal_approx(Vector2(-3, 0)), "backs away at retreat_speed")
	assert_almost(brain.yaw, PlayerState.yaw_for_direction(Vector2(1, 0)), 0.001,
			"still faces the target")


func test_waits_in_its_band_during_cooldown() -> void:
	_pull()
	var mid := {1: Vector3(10.0, 0, 0)}
	_step(HOME, mid)
	_finish_cast(mid)
	assert_true(brain.cooldown_ticks > 0)
	for i in 20:
		assert_true(_step(HOME, mid).is_zero_approx(),
				"between keep_distance and attack_range: holds still")
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE)


func test_casts_again_once_cooldown_ends() -> void:
	_pull()
	var mid := {1: Vector3(10.0, 0, 0)}
	_step(HOME, mid)
	_finish_cast(mid)
	for i in params.attack_cooldown_ticks:
		_step(HOME, mid)
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK, "next cast from the same spot")


func test_walks_closer_when_beyond_attack_range() -> void:
	_pull()
	var velocity := _step(HOME, {1: Vector3(16.0, 0, 0)})
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE, "out of range: no cast")
	assert_true(velocity.x > 0.0, "walks toward the target")
	assert_almost(velocity.length(), params.move_speed, 0.001, "at move_speed")


func test_walks_closer_during_cooldown_when_beyond_attack_range() -> void:
	_pull()
	var mid := {1: Vector3(10.0, 0, 0)}
	_step(HOME, mid)
	_finish_cast(mid)
	assert_true(brain.cooldown_ticks > 0)
	assert_true(_step(HOME, {1: Vector3(15.0, 0, 0)}).x > 0.0, "keeps the target in range")


func test_notices_players_at_aggro_range_only() -> void:
	_step(HOME, {1: Vector3(11.0, 0, 0)})
	assert_eq(brain.mode, EnemyBrain.Mode.IDLE, "11 m is past its 10 m aggro_range")
	_step(HOME, {1: Vector3(9.5, 0, 0)})
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK, "noticed within reach of a cast: casts at once")


func test_releases_its_orb_on_the_configured_tick_only() -> void:
	var attack := _cast()
	for tick in attack.total_ticks():
		assert_eq(attack.releases_projectile_at(tick), tick == 48, "tick %d" % tick)


func test_no_projectile_never_releases() -> void:
	var attack := _cast()
	attack.projectile = ""
	for tick in attack.total_ticks():
		assert_false(attack.releases_projectile_at(tick))
