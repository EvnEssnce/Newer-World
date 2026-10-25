extends TestCase
## The Thornling's role (data/enemy_thorn.cfg) through EnemyBrain: a lunging
## bite (it keeps closing during the swing), backing off between bites, coming
## back in for the next one; and its look. Hand-built params shaped like the
## Thornling's, not read from data/. The camp is at the origin.

const DELTA := 1.0 / 60.0
const HOME := Vector3.ZERO

var params: EnemyParams
var brain: EnemyBrain
var rng: RandomNumberGenerator


func before_each() -> void:
	params = EnemyParams.new()
	params.move_speed = 5.5
	params.wander_speed = 2.0
	params.return_speed = 7.0
	params.turn_speed = TAU * 30.0  # faces any target within a tick
	params.stagger_multiplier = 1.2
	params.aggro_range = 9.0
	params.leash_range = 22.0
	params.attack_range = 2.4
	params.attack_cooldown_ticks = 84  # 1.4 s
	params.wander_radius = 3.0
	params.keep_distance = 4.0
	params.retreat_speed = 4.0
	params.threat_per_damage = 1.0
	params.threat_proximity = 10.0
	params.threat_switch_ratio = 1.1
	params.threat_decay_factor = 1.0
	var attack := AttackParams.new()
	attack.windup_ticks = 21  # 0.35 s
	attack.active_ticks = 9
	attack.recovery_ticks = 21
	attack.move_multiplier = 0.8
	attack.hitbox_range = 1.6
	params.attack = attack
	brain = EnemyBrain.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 1


func _step(pos: Vector3, targets: Dictionary) -> Vector2:
	return brain.step(pos, HOME, targets, params, DELTA, rng)


func test_bites_from_attack_range_and_lunges_in() -> void:
	var target := {1: Vector3(2.2, 0, 0)}
	assert_true(_step(HOME, target).is_zero_approx(), "the bite starts this tick")
	assert_eq(brain.mode, EnemyBrain.Mode.ATTACK)
	var velocity := _step(HOME, target)
	assert_true(velocity.is_equal_approx(Vector2(5.5 * 0.8, 0)),
			"keeps closing during the bite at move_speed x move_multiplier")


func test_lunge_stops_on_top_of_the_target() -> void:
	_step(HOME, {1: Vector3(2.2, 0, 0)})
	assert_true(_step(HOME, {1: Vector3(0.3, 0, 0)}).is_zero_approx(), "doesn't run through it")


func test_backs_off_after_a_bite_then_circles_back_in() -> void:
	var target := {1: Vector3(1.5, 0, 0)}
	_step(HOME, target)
	for i in params.attack.total_ticks():
		_step(HOME, target)
	assert_eq(brain.mode, EnemyBrain.Mode.CHASE)
	var velocity := _step(HOME, target)
	assert_true(velocity.is_equal_approx(Vector2(-4, 0)), "backs away at retreat_speed")
	velocity = _step(HOME, {1: Vector3(4.5, 0, 0)})
	assert_true(velocity.is_equal_approx(Vector2(5.5, 0)), "past keep_distance: runs back in")
	assert_false(brain.is_attacking(), "no bite while its cooldown runs")


func test_hit_and_run_cycle() -> void:
	# A target standing still at the origin; the Thornling starts 6 m away and
	# moves with the velocities it asks for.
	var target_pos := Vector3.ZERO
	var targets := {1: target_pos}
	var pos := Vector3(6, 0, 0)
	var bites := 0
	var was_attacking := false
	var nearest_between := INF
	var farthest_between := 0.0
	for i in 60 * 6:
		var velocity := _step(pos, targets)
		pos += Vector3(velocity.x, 0, velocity.y) * DELTA
		if brain.is_attacking() and not was_attacking:
			bites += 1
			assert_true(pos.distance_to(target_pos) <= params.attack_range + 0.1,
					"starts each bite within attack_range")
		was_attacking = brain.is_attacking()
		if bites >= 1 and not brain.is_attacking() and brain.cooldown_ticks > 10:
			var distance := pos.distance_to(target_pos)
			nearest_between = minf(nearest_between, distance)
			farthest_between = maxf(farthest_between, distance)
	assert_true(bites >= 3, "bites again each time its cooldown ends (%d bites)" % bites)
	assert_true(farthest_between >= params.keep_distance - 0.2,
			"backs off to about keep_distance between bites")
	assert_true(farthest_between <= params.keep_distance + 0.5, "but stays close")


func test_look_is_its_own() -> void:
	var look := EnemyLook.for_kind("thorn")
	var husk := EnemyLook.for_kind("husk")
	assert_true(look.base_color() != husk.base_color(), "not the Husk's look")
	assert_true(look.label_height() < husk.label_height(), "a smaller kind")


func test_look_builds_and_poses() -> void:
	var look := EnemyLook.for_kind("thorn")
	var model := Node3D.new()
	var pivot := Node3D.new()
	model.add_child(pivot)
	var body := MeshInstance3D.new()
	pivot.add_child(body)
	var club := Node3D.new()
	pivot.add_child(club)
	var eyes := MeshInstance3D.new()
	pivot.add_child(eyes)
	look.model = model
	look.body_pivot = pivot
	look.body = body
	look.club_pivot = club
	look.eyes = eyes
	look.params = params
	look.build()
	assert_true(model.scale.x < 1.0, "smaller than a Husk")
	assert_false(club.visible, "no club")
	assert_true(pivot.get_child_count() > 10, "adds its parts")
	var jaw: Node3D = look.get("_jaw")
	look.pose(-1.0)
	var rest := jaw.rotation.x
	look.pose(params.attack.windup_ticks - 1.0)
	assert_true(jaw.rotation.x > rest, "the jaw gapes during the windup")
	look.pose(params.attack.windup_ticks + params.attack.active_ticks - 1.0)
	assert_true(jaw.rotation.x < rest, "and snaps shut in the bite")
	model.free()
