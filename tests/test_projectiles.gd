extends TestCase
## Projectile flight, swept hit tests, pierce, the boomerang's two legs and
## hit-once bookkeeping. Params built by hand (60 ticks per second).

const TPS := 60.0
const DT := 1.0 / TPS
const RADIUS := 0.4
const HEIGHT := 1.8

var p: ProjectileParams


func before_each() -> void:
	p = ProjectileParams.new()
	p.id = "test"
	p.speed = 30.0
	p.gravity = 0.0
	p.lifetime_ticks = 60
	p.hit_radius = 0.2
	p.pierce = 0
	p.stopped_by_guard = true


func _boomerang() -> void:
	p.speed = 20.0
	p.returns = true
	p.return_after_ticks = 30
	p.return_speed = 20.0
	p.catch_radius = 0.8
	p.lifetime_ticks = 180
	p.pierce = 5
	p.stopped_by_guard = false


# --- Flight ---

func test_flies_straight_at_its_speed() -> void:
	var proj := Projectile.new(p, Vector3.ZERO, Projectile.launch_velocity_for(p, 0.0))
	for i in 30:
		proj.step(DT, Vector3.ZERO)
	assert_almost(proj.position.z, -15.0, 0.0001, "yaw 0 flies along -Z, 30 m/s for 0.5 s")
	assert_almost(proj.position.x, 0.0)
	assert_almost(proj.position.y, 0.0)
	assert_eq(proj.age, 30)
	assert_almost(proj.prev_position.z, -14.5, 0.0001, "the last step's segment starts 0.5 m back")


func test_launch_follows_yaw_and_pitch() -> void:
	p.pitch = deg_to_rad(30.0)
	var v := Projectile.launch_velocity_for(p, PI / 2.0)
	assert_almost(v.length(), 30.0, 0.0001)
	assert_almost(v.x, -30.0 * cos(deg_to_rad(30.0)), 0.0001, "yaw 90 degrees faces -X")
	assert_almost(v.y, 15.0, 0.0001)
	assert_almost(v.z, 0.0, 0.0001)


func test_gravity_bends_it_down() -> void:
	p.gravity = 10.0
	var proj := Projectile.new(p, Vector3(0.0, 2.0, 0.0), Projectile.launch_velocity_for(p, 0.0))
	for i in 60:
		proj.step(DT, Vector3.ZERO)
	assert_true(proj.position.y < 2.0 - 4.5, "fell about g t^2 / 2 = 5 m in 1 s")
	assert_true(proj.position.y > 2.0 - 5.5)
	assert_almost(proj.velocity.y, -10.0, 0.0001)
	assert_almost(proj.position.z, -30.0, 0.0001, "horizontal speed unchanged")


func test_lifetime_ends_it() -> void:
	p.lifetime_ticks = 10
	var proj := Projectile.new(p, Vector3.ZERO, Projectile.launch_velocity_for(p, 0.0))
	for i in 9:
		proj.step(DT, Vector3.ZERO)
	assert_eq(proj.ended, Projectile.END_NONE)
	proj.step(DT, Vector3.ZERO)
	assert_eq(proj.ended, Projectile.END_EXPIRED)
	var at := proj.position
	proj.step(DT, Vector3.ZERO)
	assert_eq(proj.position, at, "an ended projectile doesn't move")


func test_release_point_is_in_front_and_up() -> void:
	p.release_height = 1.3
	p.release_forward = 0.5
	var at := Projectile.release_point(p, Vector3(1.0, 0.0, 1.0), 0.0)
	assert_almost(at.x, 1.0)
	assert_almost(at.y, 1.3)
	assert_almost(at.z, 0.5)


func test_spread_fans_evenly() -> void:
	assert_almost(ProjectileSystem.spread_offset(0, 1, 1.0), 0.0)
	assert_almost(ProjectileSystem.spread_offset(0, 3, 1.0), -0.5)
	assert_almost(ProjectileSystem.spread_offset(1, 3, 1.0), 0.0)
	assert_almost(ProjectileSystem.spread_offset(2, 3, 1.0), 0.5)


# --- Swept hit tests ---

func test_segment_through_a_capsule_hits() -> void:
	var s := Projectile.sweep_capsule(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, -4.0), 0.2,
			Vector3(0.0, 0.0, -2.0), RADIUS, HEIGHT)
	assert_almost(s, 0.5, 0.0001, "closest at the capsule's axis, halfway")


func test_segment_beside_a_capsule_misses() -> void:
	var a := Vector3(0.0, 1.0, 0.0)
	var b := Vector3(0.0, 1.0, -4.0)
	assert_true(Projectile.sweep_capsule(a, b, 0.2, Vector3(0.55, 0.0, -2.0), RADIUS, HEIGHT) >= 0.0,
			"within radius + hit radius (0.6 m)")
	assert_true(Projectile.sweep_capsule(a, b, 0.2, Vector3(0.65, 0.0, -2.0), RADIUS, HEIGHT) < 0.0)


func test_segment_over_a_capsule_misses() -> void:
	var s := Projectile.sweep_capsule(Vector3(0.0, 2.5, 0.0), Vector3(0.0, 2.5, -4.0), 0.2,
			Vector3(0.0, 0.0, -2.0), RADIUS, HEIGHT)
	assert_true(s < 0.0, "passes 0.7 m over a 1.8 m head (reach 0.6 m)")


func test_segment_short_of_a_capsule_misses() -> void:
	var s := Projectile.sweep_capsule(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, -1.0), 0.2,
			Vector3(0.0, 0.0, -2.0), RADIUS, HEIGHT)
	assert_true(s < 0.0, "ends 1 m short; the body's edge is 1.6 m away")


func test_fast_projectile_does_not_tunnel_through_thin_target() -> void:
	# 300 m/s = 5 m per tick, through a 0.1 m wide target: neither end of the
	# step is near it, but the swept segment is.
	p.speed = 300.0
	p.hit_radius = 0.05
	var proj := Projectile.new(p, Vector3(0.0, 1.0, 0.0), Projectile.launch_velocity_for(p, 0.0))
	var feet := Vector3(0.0, 0.0, -7.5)
	var hit_at := -1
	for i in 3:
		proj.step(DT, Vector3.ZERO)
		if Projectile.sweep_capsule(proj.prev_position, proj.position, p.hit_radius, feet, 0.05, HEIGHT) >= 0.0:
			hit_at = proj.age
			break
	assert_eq(hit_at, 2, "the step from 5 m to 10 m crosses the target at 7.5 m")
	assert_true(proj.prev_position.distance_to(feet + Vector3.UP) > 2.0, "start far from it")
	assert_true(proj.position.distance_to(feet + Vector3.UP) > 2.0, "end far from it")


func test_closest_on_segments_crossing() -> void:
	var st := Projectile.closest_on_segments(Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, -1.0, 1.0), Vector3(0.0, 1.0, 1.0))
	assert_almost(st.x, 0.5)
	assert_almost(st.y, 0.5)


# --- Hits, pierce, guards ---

func test_each_target_is_hit_once() -> void:
	p.pierce = 3
	var proj := Projectile.new(p, Vector3.ZERO, Vector3.FORWARD)
	assert_true(proj.can_hit(7))
	assert_true(proj.register_hit(7, false))
	assert_false(proj.can_hit(7), "already hit")
	assert_true(proj.can_hit(-2), "others still can be (enemy ids too)")


func test_an_evade_can_still_be_hit_later() -> void:
	var proj := Projectile.new(p, Vector3.ZERO, Vector3.FORWARD)
	proj.register_evade(7)
	assert_true(proj.can_hit(7))
	proj.register_hit(7, false)
	proj.register_evade(7)
	assert_false(proj.can_hit(7), "an evade after a hit doesn't reopen it")


func test_pierce_zero_stops_at_the_first_target() -> void:
	var proj := Projectile.new(p, Vector3.ZERO, Vector3.FORWARD)
	assert_false(proj.register_hit(1, false))
	assert_eq(proj.ended, Projectile.END_HIT)


func test_pierce_passes_through_that_many() -> void:
	p.pierce = 2
	var proj := Projectile.new(p, Vector3.ZERO, Vector3.FORWARD)
	assert_true(proj.register_hit(1, false))
	assert_true(proj.register_hit(2, false))
	assert_eq(proj.ended, Projectile.END_NONE)
	assert_false(proj.register_hit(3, false), "the third stops it")
	assert_eq(proj.ended, Projectile.END_HIT)


func test_a_guard_stops_it_even_with_pierce() -> void:
	p.pierce = 5
	var proj := Projectile.new(p, Vector3.ZERO, Vector3.FORWARD)
	assert_false(proj.register_hit(1, true))
	assert_eq(proj.ended, Projectile.END_HIT)


func test_a_guard_does_not_stop_it_when_not_stopped_by_guard() -> void:
	p.pierce = 5
	p.stopped_by_guard = false
	var proj := Projectile.new(p, Vector3.ZERO, Vector3.FORWARD)
	assert_true(proj.register_hit(1, true))
	assert_eq(proj.pierce_left, 4, "it still uses up pierce")


func test_wall_stops_it_where_it_hit() -> void:
	var proj := Projectile.new(p, Vector3.ZERO, Projectile.launch_velocity_for(p, 0.0))
	proj.step(DT, Vector3.ZERO)
	proj.hit_wall(Vector3(0.0, 0.0, -0.3))
	assert_eq(proj.ended, Projectile.END_WALL)
	assert_eq(proj.position, Vector3(0.0, 0.0, -0.3))


# --- Boomerang ---

func test_boomerang_turns_after_its_outbound_time() -> void:
	_boomerang()
	var proj := Projectile.new(p, Vector3.ZERO, Projectile.launch_velocity_for(p, 0.0))
	for i in 30:
		proj.step(DT, Vector3.ZERO)
	assert_false(proj.returning, "still on the way out after 30 steps")
	assert_almost(proj.position.z, -10.0, 0.0001)
	proj.step(DT, Vector3.ZERO)
	assert_true(proj.returning, "turns at the start of step 31")
	assert_almost(proj.position.z, -10.0 + 20.0 * DT, 0.0001, "and that step flies back")


func test_boomerang_is_caught_by_its_thrower() -> void:
	_boomerang()
	var proj := Projectile.new(p, Vector3.ZERO, Projectile.launch_velocity_for(p, 0.0))
	var thrower := Vector3(3.0, 0.0, 0.0)  # moved while it flew
	for i in 120:
		proj.step(DT, thrower)
		if proj.ended != Projectile.END_NONE:
			break
	assert_eq(proj.ended, Projectile.END_CAUGHT)
	assert_true(proj.position.distance_to(thrower) <= p.catch_radius)
	assert_true(proj.age < 30 + 40, "about 10.4 m back at 20 m/s")


func test_boomerang_hits_each_target_once_per_leg() -> void:
	_boomerang()
	var proj := Projectile.new(p, Vector3.ZERO, Projectile.launch_velocity_for(p, 0.0))
	assert_true(proj.register_hit(4, false), "way out")
	assert_false(proj.can_hit(4))
	for i in 31:
		proj.step(DT, Vector3.ZERO)
	assert_true(proj.returning)
	assert_true(proj.can_hit(4), "a new leg: can be hit again on the way back")
	assert_eq(proj.pierce_left, 5, "pierce starts again")
	proj.register_hit(4, false)
	assert_false(proj.can_hit(4), "but only once on the way back")


func test_boomerang_out_of_pierce_turns_back_early() -> void:
	_boomerang()
	p.pierce = 0
	var proj := Projectile.new(p, Vector3.ZERO, Projectile.launch_velocity_for(p, 0.0))
	proj.step(DT, Vector3.ZERO)
	assert_false(proj.register_hit(1, false), "the leg ends")
	assert_true(proj.returning, "turned back instead of stopping")
	assert_eq(proj.ended, Projectile.END_NONE)
	assert_false(proj.register_hit(2, false))
	assert_eq(proj.ended, Projectile.END_HIT, "on the way back it stops")


func test_boomerang_wall_turns_it_back() -> void:
	_boomerang()
	var proj := Projectile.new(p, Vector3.ZERO, Projectile.launch_velocity_for(p, 0.0))
	proj.step(DT, Vector3.ZERO)
	proj.hit_wall(Vector3(0.0, 0.0, -0.2))
	assert_true(proj.returning)
	assert_eq(proj.ended, Projectile.END_NONE)
	assert_eq(proj.position, Vector3(0.0, 0.0, -0.2))
