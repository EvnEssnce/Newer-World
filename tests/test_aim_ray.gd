extends TestCase
## AimRay (the crosshair's line, rebuilt by the server from position + aim) and
## projectiles launched along it. Params built by hand.

const TPS := 60.0
const DT := 1.0 / TPS

var params: AimRay.Params


func before_each() -> void:
	params = AimRay.Params.new()
	params.pivot_height = 1.6
	params.shoulder_offset = 0.0
	params.distance = 4.5
	params.max_distance = 100.0
	params.min_ahead = 1.0


func _assert_vec(actual: Vector3, expected: Vector3, message: String = "") -> void:
	assert_true(actual.distance_to(expected) < 0.0001, "%s: got %s, expected %s" % [message, actual, expected])


func _arrow() -> ProjectileParams:
	var p := ProjectileParams.new()
	p.id = "arrow"
	p.speed = 40.0
	p.gravity = 3.0
	p.pitch = deg_to_rad(2.0)
	p.lifetime_ticks = 45
	p.hit_radius = 0.2
	p.release_height = 1.4
	p.release_forward = 0.4
	return p


# --- The ray ---

func test_level_aim_looks_forward_from_the_pivot() -> void:
	var ray := AimRay.create(Vector3(2.0, 0.0, 3.0), 0.0, 0.0, params)
	_assert_vec(ray.origin, Vector3(2.0, 1.6, 3.0), "the orbit point is pivot_height above the feet")
	_assert_vec(ray.direction, Vector3(0.0, 0.0, -1.0), "yaw 0 looks along -Z")
	_assert_vec(ray.camera, Vector3(2.0, 1.6, 7.5), "the camera is distance behind")
	_assert_vec(ray.point_at(10.0), Vector3(2.0, 1.6, -7.0), "10 m along the aim")


func test_yaw_turns_the_aim() -> void:
	var ray := AimRay.create(Vector3.ZERO, PI / 2.0, 0.0, params)
	_assert_vec(ray.direction, Vector3(-1.0, 0.0, 0.0), "yaw 90 degrees looks along -X")


func test_shoulder_offset_is_to_the_right_of_the_yaw() -> void:
	params.shoulder_offset = 0.7
	var ray := AimRay.create(Vector3.ZERO, 0.0, 0.0, params)
	_assert_vec(ray.origin, Vector3(0.7, 1.6, 0.0), "facing -Z, right is +X")
	ray = AimRay.create(Vector3.ZERO, PI / 2.0, 0.0, params)
	_assert_vec(ray.origin, Vector3(0.0, 1.6, -0.7), "facing -X, right is -Z")
	_assert_vec(ray.camera, Vector3(4.5, 1.6, -0.7), "the camera stays behind the shoulder")


func test_looking_up_puts_the_camera_below() -> void:
	var ray := AimRay.create(Vector3.ZERO, 0.0, deg_to_rad(30.0), params)
	assert_almost(ray.direction.y, 0.5, 0.0001, "pitch up = positive")
	assert_almost(ray.direction.z, -cos(deg_to_rad(30.0)), 0.0001)
	assert_almost(ray.direction.length(), 1.0, 0.0001)
	assert_almost(ray.camera.y, 1.6 - 4.5 * 0.5, 0.0001, "the camera sits below, looking up")


func test_looking_down_reaches_the_ground_ahead() -> void:
	var ray := AimRay.create(Vector3.ZERO, 0.0, deg_to_rad(-30.0), params)
	var ground := ray.point_at(1.6 / sin(deg_to_rad(30.0)))
	assert_almost(ground.y, 0.0, 0.0001, "the line meets flat ground")
	assert_almost(ground.z, -1.6 / tan(deg_to_rad(30.0)), 0.0001, "about 2.8 m ahead")
	assert_true(ray.camera.y > ray.origin.y, "the camera sits above, looking down")


# --- Launch direction ---

func test_launch_heads_at_the_aim_point() -> void:
	var from := Vector3(0.0, 1.4, -0.4)
	var point := Vector3(3.0, 0.0, -10.0)
	var dir := AimRay.launch_direction(from, point, Vector3(0.0, 0.0, -1.0), 1.0)
	_assert_vec(dir, (point - from).normalized(), "straight from the hand at the point")


func test_launch_too_close_follows_the_aim_ray() -> void:
	var aim := AimRay.look_direction(0.0, deg_to_rad(-10.0))
	var from := Vector3(0.0, 1.4, -0.4)
	var dir := AimRay.launch_direction(from, from + Vector3(0.0, 0.0, -0.5), aim, 1.0)
	_assert_vec(dir, aim, "under min_ahead: along the aim")
	dir = AimRay.launch_direction(from, from + Vector3(0.0, 0.0, 2.0), aim, 1.0)
	_assert_vec(dir, aim, "behind the hand: along the aim")


func test_launch_velocity_follows_the_aim_pitch() -> void:
	var p := _arrow()
	p.pitch = 0.0
	var aimed := AimRay.look_direction(0.3, deg_to_rad(-25.0))
	var v := Projectile.launch_velocity_along(p, aimed, 0.0, 0.0)
	_assert_vec(v, aimed * 40.0, "speed along the aim, pitch included")
	p.pitch = deg_to_rad(2.0)
	v = Projectile.launch_velocity_along(p, aimed, 0.0, 0.0)
	assert_almost(asin(v.normalized().y), deg_to_rad(-23.0), 0.0001, "the kind's pitch adds on top")


func test_ground_wave_ignores_the_aim_pitch() -> void:
	var p := _arrow()
	p.pitch = 0.0
	p.aim_pitch = false
	var aimed := AimRay.look_direction(PI / 2.0, deg_to_rad(-40.0))
	var v := Projectile.launch_velocity_along(p, aimed, 0.0, 0.0)
	_assert_vec(v, Vector3(-40.0, 0.0, 0.0), "level, along the aim's heading")


func test_spread_fans_around_the_aimed_direction() -> void:
	var p := _arrow()
	p.pitch = 0.0
	var aimed := AimRay.look_direction(0.0, deg_to_rad(20.0))
	var left := Projectile.launch_velocity_along(p, aimed, deg_to_rad(10.0), 0.0)
	var right := Projectile.launch_velocity_along(p, aimed, deg_to_rad(-10.0), 0.0)
	assert_almost(left.y, aimed.y * 40.0, 0.0001, "same elevation")
	assert_almost(right.y, aimed.y * 40.0, 0.0001)
	assert_almost(left.x, -right.x, 0.0001, "mirrored around the aim's heading")
	assert_true(left.x < 0.0, "a positive offset turns left (toward -X facing -Z)")


func test_straight_down_keeps_the_fallback_heading() -> void:
	var p := _arrow()
	p.pitch = 0.0
	var v := Projectile.launch_velocity_along(p, Vector3.DOWN, 0.0, PI / 2.0)
	assert_true(v.y < -39.0, "nearly straight down")
	assert_true(v.x < 0.0 and absf(v.z) < 0.0001, "the tiny horizontal part follows the fallback yaw")


# --- Shooting down from a hover (Updraft) ---

func test_arrow_from_a_hover_hits_a_target_below() -> void:
	params.shoulder_offset = 0.7
	var feet := Vector3(0.0, 3.5, 0.0)  # hovering 3.5 m up
	var yaw := 0.0
	var target_feet := Vector3(0.7, 0.0, -9.0)
	# Aim the crosshair at the target's chest (what the cast would hit).
	var probe := AimRay.create(feet, yaw, 0.0, params)
	var chest := target_feet + Vector3.UP * 1.0
	var to := chest - probe.origin
	var pitch := atan2(to.y, -to.z)
	var ray := AimRay.create(feet, yaw, pitch, params)
	assert_true(pitch < deg_to_rad(-15.0), "looking down at it")
	var aim_point := ray.point_at(to.length())
	assert_true(aim_point.distance_to(chest) < 0.01, "the crosshair is on the chest")
	var p := _arrow()
	var from := Projectile.release_point(p, feet, yaw)
	var dir := AimRay.launch_direction(from, aim_point, ray.direction, params.min_ahead)
	var proj := Projectile.new(p, from, Projectile.launch_velocity_along(p, dir, 0.0, yaw))
	var hit := false
	for i in p.lifetime_ticks:
		proj.step(DT, Vector3.ZERO)
		if Projectile.sweep_capsule(proj.prev_position, proj.position, p.hit_radius, target_feet,
				0.4, 1.8) >= 0.0:
			hit = true
			break
	assert_true(hit, "the arrow flies down into the target")
	var flat := Projectile.new(p, from, Projectile.launch_velocity_for(p, yaw))
	var flat_hit := false
	for i in p.lifetime_ticks:
		flat.step(DT, Vector3.ZERO)
		if Projectile.sweep_capsule(flat.prev_position, flat.position, p.hit_radius, target_feet,
				0.4, 1.8) >= 0.0:
			flat_hit = true
	assert_false(flat_hit, "a level throw (the old behaviour) sails over it")
