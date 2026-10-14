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


# --- Melee facing (the crosshair's line at an attack's reach) ---

## The horizontal unit direction a yaw faces.
func _flat_forward(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


func test_facing_points_at_the_crosshair_line_at_the_reach() -> void:
	params.shoulder_offset = 0.7
	params.melee_min_reach = 1.5
	var feet := Vector3(3.0, 1.0, -2.0)
	for aim_yaw: float in [0.0, 1.0, -2.5]:
		for pitch_deg: float in [-40.0, 0.0, 25.0]:
			var ray := AimRay.create(feet, aim_yaw, deg_to_rad(pitch_deg), params)
			var facing := AimRay.facing_at_reach(aim_yaw, 3.0, params)
			# The ray's point 3 m ahead of the feet along the aim yaw (horizontally).
			var fwd := _flat_forward(aim_yaw)
			var start := Vector2(ray.origin.x - feet.x, ray.origin.z - feet.z).dot(fwd)
			var along := Vector2(ray.direction.x, ray.direction.z).dot(fwd)
			var point := ray.point_at((3.0 - start) / along)
			var to := Vector2(point.x - feet.x, point.z - feet.z).normalized()
			assert_true(to.distance_to(_flat_forward(facing)) < 0.0001,
					"yaw %s pitch %s: faces the crosshair's line 3 m ahead" % [aim_yaw, pitch_deg])


func test_facing_turns_right_toward_the_shoulder() -> void:
	params.shoulder_offset = 0.7
	params.melee_min_reach = 1.5
	var facing := AimRay.facing_at_reach(0.0, 3.0, params)
	assert_almost(facing, -atan2(0.7, 3.0), 0.0001, "about 13 degrees right (negative yaw)")
	assert_true(AimRay.facing_at_reach(0.0, 6.0, params) > facing, "farther reach, smaller turn")


func test_facing_without_offset_or_reach_is_the_aim() -> void:
	assert_almost(AimRay.facing_at_reach(0.8, 3.0, params), 0.8, 0.0001, "no shoulder offset")
	params.shoulder_offset = 0.7
	assert_almost(AimRay.facing_at_reach(0.8, 0.0, params), 0.8, 0.0001, "no reach (all-round)")


func test_short_reach_is_clamped_to_the_minimum() -> void:
	params.shoulder_offset = 0.7
	params.melee_min_reach = 1.5
	assert_almost(AimRay.facing_at_reach(0.0, 0.4, params), -atan2(0.7, 1.5), 0.0001,
			"never turns more than at melee_min_reach")


func _box(attack_range: float, width: float) -> AttackParams:
	var a := AttackParams.new()
	a.shape = AttackParams.SHAPE_BOX
	a.hitbox_range = attack_range
	a.hitbox_width = width
	a.hitbox_height = 2.0
	return a


func test_attack_facing_hits_what_is_under_the_crosshair() -> void:
	params.shoulder_offset = 0.7
	params.melee_reach_fraction = 0.75
	params.melee_min_reach = 1.5
	var a := _box(3.0, 0.4)
	var aim_yaw := 0.6
	# A target standing on the crosshair's line 2.25 m ahead.
	var ray := AimRay.create(Vector3.ZERO, aim_yaw, 0.0, params)
	var target := ray.point_at(2.25)  # level aim: 2.25 m ahead, 0.7 m right
	target.y = 0.0
	assert_false(MeleeHitbox.hits(Vector3.ZERO, aim_yaw, a, target, 0.4, 1.8),
			"facing the aim yaw, the narrow box passes left of it")
	var facing := AimRay.attack_facing(aim_yaw, a, params)
	assert_true(MeleeHitbox.hits(Vector3.ZERO, facing, a, target, 0.4, 1.8),
			"facing the crosshair's line, it hits")


func test_attack_reach_by_shape() -> void:
	var box := _box(2.0, 1.0)
	assert_almost(box.aim_reach(0.75), 1.5, 0.0001, "a box: that fraction of its range")
	var radial := _box(3.0, 0.0)
	radial.shape = AttackParams.SHAPE_RADIAL
	assert_almost(radial.aim_reach(0.75), 0.0, 0.0001, "all round: faces the aim")
	radial.hitbox_arc = deg_to_rad(90.0)
	assert_almost(radial.aim_reach(0.75), 2.25, 0.0001, "a cone in front counts")
	var none := _box(0.0, 0.0)
	none.shape = AttackParams.SHAPE_NONE
	assert_almost(none.aim_reach(0.75), 0.0, 0.0001, "no hitbox (a throw): faces the aim")


func test_a_forward_dash_adds_its_distance() -> void:
	var a := AbilityParams.new()
	a.shape = AttackParams.SHAPE_RADIAL
	a.hitbox_range = 2.3
	a.dash_length = 6.0
	assert_almost(a.aim_reach(0.75), 6.0, 0.0001, "lands on the crosshair's line")
	a.dash_from_input = true
	assert_almost(a.aim_reach(0.75), 0.0, 0.0001, "an input dash goes its own way")
	a.dash_from_input = false
	a.dash_backward = true
	assert_almost(a.aim_reach(0.75), 0.0, 0.0001, "a backward dash doesn't count")


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
