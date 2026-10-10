extends TestCase
## EnemyBrain: aggro, chase, swing, cooldown, stagger, leash, wander, and a
## stationary enemy (the training dummy).
## Fixed params, not data/enemy_husk.cfg. The camp is at the origin.

const DELTA := 1.0 / 60.0
const HOME := Vector3.ZERO

var params: EnemyParams
var brain: EnemyBrain
var rng: RandomNumberGenerator


func before_each() -> void:
	params = EnemyParams.new()
	params.move_speed = 3.0
	params.wander_speed = 1.0
	params.return_speed = 6.0
	params.turn_speed = TAU * 30.0  # half a turn per tick: faces any target within a tick
	params.stagger_multiplier = 1.0
	params.aggro_range = 8.0
	params.leash_range = 20.0
	params.attack_range = 2.0
	params.attack_cooldown_ticks = 30
	params.wander_radius = 4.0
	params.wander_pause_ticks = 0
	params.threat_per_damage = 1.0
	params.threat_proximity = 10.0
	params.threat_switch_ratio = 1.1
	params.threat_decay_factor = 1.0
	var attack := AttackParams.new()
	attack.windup_ticks = 6
	attack.active_ticks = 2
	attack.recovery_ticks = 4
	params.attack = attack
	brain = EnemyBrain.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 1


func _step(pos: Vector3, targets: Dictionary) -> Vector2:
	return brain.step(pos, HOME, targets, params, DELTA, rng)


func test_ignores_players_outside_aggro_range() -> void:
	_step(HOME, {1: Vector3(9, 0, 0)})
	assert_eq(brain.mode, EnemyBrain.Mode.IDLE)


func test_chases_a_player_in_aggro_range() -> void:
	var velocity := _step(HOME, {1: Vector3(5, 0, 0)})
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE)
	assert_eq(brain.target_id, 1)
	assert_true(velocity.is_equal_approx(Vector2(3, 0)), "runs at the target at move_speed")


func test_picks_the_nearest_player() -> void:
	_step(HOME, {1: Vector3(6, 0, 0), 2: Vector3(0, 0, 3)})
	assert_eq(brain.target_id, 2)


func test_swings_when_in_range_and_stands_still() -> void:
	var velocity := _step(HOME, {1: Vector3(1.5, 0, 0)})
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK)
	assert_eq(brain.attack_tick, 0)
	assert_eq(velocity, Vector2.ZERO)


func test_hitbox_live_only_after_windup_then_cooldown() -> void:
	var targets := {1: Vector3(1.5, 0, 0)}
	_step(HOME, targets)
	var active := []
	for i in params.attack.total_ticks():
		if brain.is_attack_active(params):
			active.append(brain.attack_tick)
		_step(HOME, targets)
	assert_eq(active, [6, 7])
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE, "swing over")
	for i in params.attack_cooldown_ticks - 1:
		_step(HOME, targets)
	assert_false(brain.is_attacking(), "still cooling down")
	_step(HOME, targets)
	assert_true(brain.is_attacking(), "swings again after the cooldown")


func test_tracks_target_during_windup_but_not_after() -> void:
	_step(HOME, {1: Vector3(0, 0, -1.5)})  # straight ahead (-Z): yaw 0
	_step(HOME, {1: Vector3(1.5, 0, 0)})  # moved to the right during the windup
	assert_almost(brain.yaw, PlayerState.yaw_for_direction(Vector2.RIGHT), 0.001)
	for i in params.attack.windup_ticks:
		_step(HOME, {1: Vector3(1.5, 0, 0)})
	var committed := brain.yaw
	_step(HOME, {1: Vector3(-1.5, 0, 0)})
	assert_almost(brain.yaw, committed, 0.001, "committed once the swing comes down")


func test_stagger_interrupts_the_swing() -> void:
	var targets := {1: Vector3(1.5, 0, 0)}
	_step(HOME, targets)
	brain.stagger(10)
	assert_false(brain.is_attacking())
	assert_eq(brain.mode, EnemyBrain.Mode.STAGGERED)
	for i in 9:
		_step(HOME, targets)
	assert_eq(brain.mode, EnemyBrain.Mode.STAGGERED)
	_step(HOME, targets)
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE)


func test_gives_up_past_the_leash_and_heals_at_home() -> void:
	_step(HOME, {1: Vector3(5, 0, 0)})
	var velocity := _step(Vector3(21, 0, 0), {1: Vector3(25, 0, 0)})
	assert_eq(brain.mode, EnemyBrain.Mode.RETURN)
	assert_true(velocity.is_equal_approx(Vector2(-6, 0)), "walks home at return_speed")
	_step(Vector3(0.2, 0, 0), {})
	assert_eq(brain.mode, EnemyBrain.Mode.IDLE)
	assert_true(brain.arrived_home)


func test_returns_home_when_target_is_gone() -> void:
	_step(HOME, {1: Vector3(5, 0, 0)})
	_step(Vector3(3, 0, 0), {})
	assert_eq(brain.mode, EnemyBrain.Mode.RETURN)


func test_being_hit_while_idle_aggros_the_attacker() -> void:
	brain.add_threat(7, 50.0, params)
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE)
	assert_eq(brain.target_id, 7)


func test_damage_threat_takes_the_target_past_the_switch_ratio() -> void:
	var targets := {1: Vector3(3, 0, 0), 2: Vector3(0, 0, 5)}
	_step(HOME, targets)
	assert_eq(brain.target_id, 1, "nearest first")
	brain.add_threat(2, 10.0, params)  # 20 vs 10 proximity: more than 1.1x
	_step(HOME, targets)
	assert_eq(brain.target_id, 2)
	brain.add_threat(1, 11.0, params)  # 21 vs 20: not enough
	_step(HOME, targets)
	assert_eq(brain.target_id, 2, "doesn't flicker on close values")
	assert_eq(brain.target_switches, 1)


func test_target_dies_next_one_with_threat_is_chased() -> void:
	brain.add_threat(1, 50.0, params)
	brain.add_threat(2, 5.0, params)
	_step(HOME, {1: Vector3(5, 0, 0), 2: Vector3(30, 0, 0)})
	assert_eq(brain.target_id, 1)
	_step(HOME, {2: Vector3(30, 0, 0)})  # 1 died: out of the targets
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE)
	assert_eq(brain.target_id, 2, "still has threat on 2, even out of aggro range")


func test_taunt_forces_the_target_then_sticks() -> void:
	var targets := {1: Vector3(5, 0, 0), 2: Vector3(0, 0, 6)}
	brain.add_threat(1, 300.0, params)
	_step(HOME, targets)
	assert_true(brain.taunt(2, params))
	brain.forced_target = 2
	_step(HOME, targets)
	assert_eq(brain.target_id, 2)
	brain.add_threat(1, 500.0, params)
	_step(HOME, targets)
	assert_eq(brain.target_id, 2, "forced while the taunt lasts")
	brain.forced_target = 0
	_step(HOME, targets)
	assert_eq(brain.target_id, 1, "threat decides again once it ends")


func test_taunt_threat_keeps_aggro_after_it_ends() -> void:
	var targets := {1: Vector3(5, 0, 0), 2: Vector3(0, 0, 6)}
	brain.add_threat(1, 300.0, params)
	_step(HOME, targets)
	brain.taunt(2, params)
	brain.forced_target = 2
	_step(HOME, targets)
	brain.forced_target = 0
	_step(HOME, targets)
	assert_eq(brain.target_id, 2)


func test_taunt_wakes_an_idle_enemy() -> void:
	assert_true(brain.taunt(4, params))
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE)
	assert_eq(brain.target_id, 4)


func test_leashing_wipes_threat_and_ignores_new_threat_until_home() -> void:
	brain.add_threat(1, 100.0, params)
	_step(Vector3(21, 0, 0), {1: Vector3(25, 0, 0)})
	assert_eq(brain.mode, EnemyBrain.Mode.RETURN)
	assert_true(brain.threat.is_empty())
	brain.add_threat(1, 100.0, params)
	assert_false(brain.taunt(1, params))
	assert_true(brain.threat.is_empty(), "walking home ignores threat")
	_step(Vector3(0.2, 0, 0), {})
	assert_eq(brain.mode, EnemyBrain.Mode.IDLE)


func test_wanders_near_its_camp() -> void:
	var pos := HOME
	brain.wander_point = HOME
	var farthest := 0.0
	for i in 1200:
		var velocity := _step(pos, {})
		pos += Vector3(velocity.x, 0, velocity.y) * DELTA
		farthest = maxf(farthest, pos.length())
	assert_true(farthest > 0.5, "it actually moves")
	assert_true(farthest <= params.wander_radius + 0.1, "stays within wander_radius")


func test_stationary_never_moves_turns_or_swings() -> void:
	params.stationary = true
	brain.add_threat(1, 100.0, params)
	for i in 120:
		var velocity := _step(HOME, {1: Vector3(1, 0, 1)})
		assert_true(velocity.is_zero_approx(), "never walks")
	assert_eq(brain.mode, EnemyBrain.Mode.IDLE)
	assert_eq(brain.attack_tick, -1, "never swings at a player in range")
	assert_eq(brain.yaw, 0.0, "never turns")
	assert_eq(brain.target_id, 0)
	assert_false(brain.threat.has(1), "keeps no threat")


func test_stationary_is_still_staggered() -> void:
	params.stationary = true
	brain.stagger(3)
	_step(HOME, {})
	_step(HOME, {})
	assert_eq(brain.mode, EnemyBrain.Mode.STAGGERED)
	_step(HOME, {})
	assert_eq(brain.mode, EnemyBrain.Mode.IDLE)
