extends TestCase
## Aimed beams (AttackParams.aimed_beam: the Gauntlet heavy, Searing Ray,
## Mending Beam...): their hit is a line from the beam origin toward the
## crosshair's aim point, pitch included, like a projectile's flight; their
## facing heads for the crosshair's line at the full range. Params built by hand.

const BODY_RADIUS := 0.4
const BODY_HEIGHT := 1.8

var params: AimRay.Params


func before_each() -> void:
	params = AimRay.Params.new()
	params.pivot_height = 2.0
	params.shoulder_offset = 0.7
	params.distance = 5.5
	params.max_distance = 100.0
	params.min_ahead = 1.0
	params.melee_reach_fraction = 0.75
	params.melee_min_reach = 1.5
	params.beam_height = 1.4
	params.beam_forward = 0.5


func _beam(attack_range: float = 8.0, width: float = 1.5) -> AttackParams:
	var a := AttackParams.new()
	a.shape = AttackParams.SHAPE_BOX
	a.hitbox_range = attack_range
	a.hitbox_width = width
	a.hitbox_height = 2.0
	a.beam_color = Color.RED
	a.aimed_beam = true
	return a


func _assert_vec(actual: Vector3, expected: Vector3, message: String = "") -> void:
	assert_true(actual.distance_to(expected) < 0.0001,
			"%s: got %s, expected %s" % [message, actual, expected])


## The beam's [origin, direction] for a player at `feet` with this aim and
## facing, aimed at `aim_point` (World._beam_of without the ray cast).
func _line(feet: Vector3, facing: float, aim_yaw: float, aim_pitch: float,
		aim_point: Vector3) -> PackedVector3Array:
	var origin := AimRay.beam_origin(feet, facing, params)
	var ray := AimRay.create(feet, aim_yaw, aim_pitch, params)
	return PackedVector3Array([origin, AimRay.beam_direction(origin, aim_point, ray, params)])


# --- The hit test ---

func test_level_beam_hits_along_its_range_only() -> void:
	var origin := Vector3(0.0, 1.4, -0.5)
	var forward := Vector3.FORWARD
	assert_true(MeleeHitbox.beam_hits(origin, forward, 8.0, 0.75, Vector3(0.0, 0.0, -6.0),
			BODY_RADIUS, BODY_HEIGHT), "a target 6 m ahead")
	assert_true(MeleeHitbox.beam_hits(origin, forward, 8.0, 0.75, Vector3(1.0, 0.0, -6.0),
			BODY_RADIUS, BODY_HEIGHT), "1 m to the side: within radius + body radius")
	assert_false(MeleeHitbox.beam_hits(origin, forward, 8.0, 0.75, Vector3(1.3, 0.0, -6.0),
			BODY_RADIUS, BODY_HEIGHT), "1.3 m to the side: outside")
	assert_false(MeleeHitbox.beam_hits(origin, forward, 8.0, 0.75, Vector3(0.0, 0.0, -9.8),
			BODY_RADIUS, BODY_HEIGHT), "past the end of the beam")
	assert_false(MeleeHitbox.beam_hits(origin, forward, 8.0, 0.75, Vector3(0.0, 0.0, 3.0),
			BODY_RADIUS, BODY_HEIGHT), "behind the user")


func test_pitch_reaches_up_and_down() -> void:
	var feet := Vector3.ZERO
	# A target on a ledge 4 m up and 7 m ahead: a level beam passes under it.
	var high := Vector3(0.0, 4.0, -7.0)
	var origin := AimRay.beam_origin(feet, 0.0, params)
	assert_false(MeleeHitbox.beam_hits(origin, Vector3.FORWARD, 8.0, 0.75, high,
			BODY_RADIUS, BODY_HEIGHT), "level: under the ledge")
	var up := (high + Vector3.UP * 0.9 - origin).normalized()
	assert_true(MeleeHitbox.beam_hits(origin, up, 8.0, 0.75, high, BODY_RADIUS, BODY_HEIGHT),
			"aimed up at it: hits")
	# And one 3 m below (down a slope): the old level box ignored it.
	var low := Vector3(0.0, -3.0, -6.0)
	var a := _beam()
	assert_false(MeleeHitbox.hits(feet, 0.0, a, low, BODY_RADIUS, BODY_HEIGHT),
			"the level box can't reach below the feet")
	var down := (low + Vector3.UP * 0.9 - origin).normalized()
	assert_true(MeleeHitbox.beam_hits(origin, down, 8.0, 0.75, low, BODY_RADIUS, BODY_HEIGHT),
			"aimed down at it: hits")
	assert_false(MeleeHitbox.beam_hits(origin, up, 8.0, 0.75, low, BODY_RADIUS, BODY_HEIGHT),
			"aimed up: misses it")


func test_touches_uses_the_beam_only_for_aimed_beams() -> void:
	var a := _beam()
	var target := Vector3(0.0, 0.0, -6.0)
	var away := PackedVector3Array([Vector3(0.0, 1.4, -0.5), Vector3.RIGHT])
	assert_false(MeleeHitbox.touches(Vector3.ZERO, 0.0, a, away, target, BODY_RADIUS, BODY_HEIGHT),
			"the beam points away: no hit, whatever the facing box says")
	assert_true(MeleeHitbox.touches(Vector3.ZERO, 0.0, a, PackedVector3Array(), target,
			BODY_RADIUS, BODY_HEIGHT), "no beam line: the box")
	a.aimed_beam = false
	assert_true(MeleeHitbox.touches(Vector3.ZERO, 0.0, a, away, target, BODY_RADIUS, BODY_HEIGHT),
			"not aimed: the box along the facing")


func test_beam_and_projectile_share_their_line() -> void:
	# The Gauntlet's life bolt is released where the beam starts, and both head
	# from there at the same aim point.
	var bolt := ProjectileParams.new()
	bolt.release_height = params.beam_height
	bolt.release_forward = params.beam_forward
	var feet := Vector3(2.0, 0.5, -1.0)
	var facing := 0.4
	var ray := AimRay.create(feet, 0.5, deg_to_rad(8.0), params)
	var aim_point := ray.point_at(12.0)
	var release := Projectile.release_point(bolt, feet, facing)
	_assert_vec(AimRay.beam_origin(feet, facing, params), release, "same start")
	_assert_vec(AimRay.beam_direction(release, aim_point, ray, params),
			AimRay.launch_direction(release, aim_point, ray.direction, params.min_ahead),
			"same direction")


func test_beam_hits_what_is_under_the_crosshair_at_any_pitch() -> void:
	var a := _beam(10.0, 1.4)
	for pitch_deg: float in [-12.0, -4.0, 0.0, 8.0, 20.0]:
		var aim_yaw := 0.3
		var pitch := deg_to_rad(pitch_deg)
		var facing := AimRay.attack_facing(aim_yaw, a, params)
		var ray := AimRay.create(Vector3.ZERO, aim_yaw, pitch, params)
		# The crosshair rests on the middle of a body (0.9 m up) 7 m along the ray.
		var aim_point := ray.point_at(7.0)
		var target := aim_point - Vector3.UP * 0.9
		var line := _line(Vector3.ZERO, facing, aim_yaw, pitch, aim_point)
		assert_true(MeleeHitbox.touches(Vector3.ZERO, facing, a, line, target, BODY_RADIUS,
				BODY_HEIGHT), "pitch %s: hits the target under the crosshair" % pitch_deg)
		# A narrow beam still goes through the aim point itself.
		var to_point := aim_point - line[0]
		var off_line := to_point - line[1] * to_point.dot(line[1])
		assert_true(off_line.length() < 0.0001, "pitch %s: through the aim point" % pitch_deg)


func test_a_far_aim_point_keeps_the_crosshair_heading() -> void:
	# Nothing under the crosshair: the aim point is max_distance away, so the
	# beam runs almost parallel to the aim ray (as a throw would).
	var ray := AimRay.create(Vector3.ZERO, 0.0, deg_to_rad(10.0), params)
	var origin := AimRay.beam_origin(Vector3.ZERO, 0.0, params)
	var dir := AimRay.beam_direction(origin, ray.point_at(params.max_distance), ray, params)
	assert_true(dir.angle_to(ray.direction) < deg_to_rad(1.0), "within a degree of the aim")


func test_aim_point_too_close_follows_the_aim_ray() -> void:
	var ray := AimRay.create(Vector3.ZERO, 0.0, 0.0, params)
	var origin := AimRay.beam_origin(Vector3.ZERO, 0.0, params)
	_assert_vec(AimRay.beam_direction(origin, origin + Vector3(0.0, 0.0, -0.3), ray, params),
			ray.direction, "a wall in the user's face: along the aim")


# --- Facing ---

func test_beam_faces_the_crosshair_line_at_full_range() -> void:
	var a := _beam(8.0)
	assert_almost(a.aim_reach(0.75), 8.0, 0.0001, "the whole range, not 75%")
	assert_almost(AimRay.attack_facing(0.2, a, params),
			AimRay.facing_at_reach(0.2, 8.0, params), 0.0001, "toward the line at 8 m")
	a.aimed_beam = false
	assert_almost(a.aim_reach(0.75), 6.0, 0.0001, "unaimed: the melee rule")


func test_aim_yaw_for_facing_inverts_facing_at_reach() -> void:
	for reach: float in [0.0, 1.0, 8.0, 10.0]:
		var facing := AimRay.facing_at_reach(0.9, reach, params)
		assert_almost(AimRay.aim_yaw_for_facing(facing, reach, params), 0.9, 0.0001,
				"reach %s" % reach)


func test_radial_copy_is_not_a_beam() -> void:
	var a := _beam()
	assert_false(a.radial_copy(2.0).aimed_beam, "an impact circle tests as a circle")
	assert_true(a.copy().aimed_beam, "a plain copy keeps it")


# --- Remote players' beam pitch ---

func test_beam_pitch_travels_in_the_state_and_the_view() -> void:
	var state := PlayerState.new()
	state.beam_pitch = -8
	assert_eq(PlayerState.from_array(state.to_array()).beam_pitch, -8, "owner's snapshot")
	assert_eq(PlayerState.from_array(state.view_array()).beam_pitch, -8, "others draw it")
