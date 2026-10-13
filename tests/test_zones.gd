extends TestCase
## Ground zones and summons (Zone): pulses, traps and re-arming, the area
## test, walls blocking a segment, and (last test) every [zone_<id>] in data/.

func _params(trigger: String) -> ZoneParams:
	var p := ZoneParams.new()
	p.id = "test"
	p.radius = 2.0
	p.height = 1.5
	p.duration_ticks = 100
	p.trigger = trigger
	p.interval_ticks = 30
	return p


func test_pulses_every_interval_then_ends() -> void:
	var z := Zone.new(_params(ZoneParams.TRIGGER_PULSE), Vector3.ZERO, 0.0, 7)
	var pulses: Array[int] = []
	for i in 100:
		if z.step():
			pulses.append(z.age)
	assert_eq(pulses, [1, 31, 61, 91] as Array[int])
	assert_true(z.ended)
	assert_false(z.step(), "nothing after the end")


func test_first_pulse_delay() -> void:
	var p := _params(ZoneParams.TRIGGER_PULSE)
	p.first_pulse_ticks = 10
	var z := Zone.new(p, Vector3.ZERO, 0.0, 7)
	var first := -1
	for i in 40:
		if z.step() and first < 0:
			first = z.age
	assert_eq(first, 11)


func test_trap_arms_triggers_and_rearms() -> void:
	var p := _params(ZoneParams.TRIGGER_TRAP)
	p.arm_ticks = 20
	var z := Zone.new(p, Vector3.ZERO, 0.0, 7, 1)
	for i in 19:
		z.step()
	assert_false(z.is_armed(), "still arming")
	z.step()
	assert_true(z.is_armed())
	z.trigger()
	assert_false(z.ended, "one re-arm left")
	assert_false(z.is_armed(), "re-arming")
	for i in 20:
		z.step()
	assert_true(z.is_armed())
	z.trigger()
	assert_true(z.ended, "no re-arms left")


func test_area_is_a_circle_with_a_height_band() -> void:
	var z := Zone.new(_params(ZoneParams.TRIGGER_PULSE), Vector3(1, 0, 1), 0.0, 7)
	assert_true(z.contains(Vector3(2.5, 0, 1)))
	assert_false(z.contains(Vector3(3.5, 0, 1)), "outside the radius")
	assert_false(z.contains(Vector3(1, 2.0, 1)), "above the band")


func test_wall_box_and_segment() -> void:
	var p := _params(ZoneParams.TRIGGER_NONE)
	p.wall = true
	p.solid = true
	p.wall_width = 4.0
	p.wall_depth = 0.5
	p.height = 2.5
	# Facing yaw 0 (toward -Z): the wall runs along X.
	var z := Zone.new(p, Vector3.ZERO, 0.0, 7)
	assert_true(z.contains(Vector3(1.5, 0, 0.1)))
	assert_false(z.contains(Vector3(2.5, 0, 0)), "past its end")
	var t := z.blocks_segment(Vector3(0, 1, -5), Vector3(0, 1, 5), 0.0)
	assert_almost(t, 0.475, 0.001, "meets the near face at z = -0.25")
	assert_almost(z.blocks_segment(Vector3(3, 1, -5), Vector3(3, 1, 5), 0.0), -1.0, 0.001,
			"passes beside it")
	assert_almost(z.blocks_segment(Vector3(0, 3, -5), Vector3(0, 3, 5), 0.0), -1.0, 0.001,
			"flies over it")
	# Turned 90 degrees, the same segment runs along it (inside: blocked at once).
	var turned := Zone.new(p, Vector3.ZERO, PI / 2.0, 7)
	assert_almost(turned.blocks_segment(Vector3(0, 1, -5), Vector3(0, 1, 5), 0.0), 0.3, 0.001)


func test_every_zone_in_data_loads() -> void:
	for section in Tuning.get_sections("zones"):
		if not section.begins_with("zone_"):
			continue
		var p := ZoneParams.get_kind(section.trim_prefix("zone_"))
		assert_true(p != null, section)
		assert_true(p.trigger in [ZoneParams.TRIGGER_PULSE, ZoneParams.TRIGGER_TRAP,
				ZoneParams.TRIGGER_NONE], section + " trigger")
		assert_true(p.affects in [ZoneParams.AFFECTS_HOSTILE, ZoneParams.AFFECTS_ALLY,
				ZoneParams.AFFECTS_BOTH],
				section + " affects")
		if not p.applies_status.is_empty():
			assert_true(StatusDefs.current().index_of(p.applies_status) >= 0,
					section + " status " + p.applies_status)
		if p.wall:
			assert_true(p.wall_width > 0.0 and p.wall_depth > 0.0, section + " wall size")
		assert_false(p.solid and not p.wall, section + ": solid needs wall")


func test_scale_grows_the_area() -> void:
	var z := Zone.new(_params(ZoneParams.TRIGGER_PULSE), Vector3.ZERO, 0.0, 7)
	assert_false(z.contains(Vector3(3.0, 0, 0)))
	z.scale = 1.6
	assert_true(z.contains(Vector3(3.0, 0, 0)), "2 m x 1.6")


func test_a_box_that_isnt_solid_blocks_nothing() -> void:
	var p := _params(ZoneParams.TRIGGER_PULSE)
	p.wall = true
	p.wall_width = 4.0
	p.wall_depth = 1.0
	var z := Zone.new(p, Vector3.ZERO, 0.0, 7)
	assert_true(z.contains(Vector3(1.5, 0, 0.2)), "still a box-shaped area")
	assert_almost(z.blocks_segment(Vector3(0, 1, -5), Vector3(0, 1, 5), 0.0), -1.0)


## Flame Wall's size (data/zones.cfg [zone_flame_wall]), built by hand.
func _flame_wall() -> ZoneParams:
	var p := _params(ZoneParams.TRIGGER_PULSE)
	p.radius = 3.0
	p.height = 2.0
	p.duration_ticks = 300
	p.interval_ticks = 30
	p.wall = true
	p.wall_width = 6.0
	p.wall_depth = 1.2
	return p


## Regression (session 41 playtest: "enemies standing in the Flame Wall when it
## appears aren't burned"): the thin box was tested at the target's feet only,
## so a Husk whose body stood visibly in the fire (center up to its radius
## outside the 1.2 m depth, or past the ends) was never touched.
func test_wall_area_counts_bodies_that_overlap_it() -> void:
	# Placed 5 m ahead of a player at the origin facing -Z: the box spans
	# x -3..3, z -5.6..-4.4.
	var z := Zone.new(_flame_wall(), Vector3(0, 0, -5), 0.0, 7)
	assert_true(z.step(), "pulses on its first tick")
	var husk := 0.5  # Enemy.BODY_RADIUS
	var body_in_fire := Vector3(0.0, 0.0, -5.9)  # body spans z -6.4..-5.4
	assert_false(z.contains(body_in_fire), "the feet alone are outside")
	assert_true(z.contains(body_in_fire, husk), "the body overlaps the fire")
	assert_true(z.contains(Vector3(3.3, 0.0, -5.0), husk), "overlapping an end")
	assert_false(z.contains(Vector3(0.0, 0.0, -6.2), husk), "a clear gap")
	assert_false(z.contains(Vector3(3.6, 0.0, -5.0), husk), "past an end")
	# Turned (facing -X, so the wall runs along Z): same rule in its frame.
	var turned := Zone.new(_flame_wall(), Vector3(-5, 0, 0), PI / 2.0, 7)
	assert_true(turned.contains(Vector3(-5.9, 0.0, 0.0), husk))
	assert_true(turned.contains(Vector3(-5.0, 0.0, 3.3), husk))
	assert_false(turned.contains(Vector3(-5.0, 0.0, 3.6), husk))
	# A disc is a ground marking: the feet decide, whatever the body.
	var disc := Zone.new(_params(ZoneParams.TRIGGER_PULSE), Vector3.ZERO, 0.0, 7)
	assert_false(disc.contains(Vector3(2.3, 0, 0), husk))


## A Husk walking straight through a Flame Wall at its chase speed (3.5 m/s)
## is burned at least once, whatever the pulse timing when it reaches it.
func test_walking_through_a_wall_is_always_burned() -> void:
	var step := 3.5 / 60.0
	for phase in 30:
		var z := Zone.new(_flame_wall(), Vector3(0, 0, -5), 0.0, 7)
		for i in phase:
			z.step()
		var at := Vector3(0.0, 0.0, -9.0)
		var burned := false
		while at.z < -1.0:
			if z.step() and z.contains(at, 0.5):
				burned = true
			at.z += step
		assert_true(burned, "pulse phase %d" % phase)


# --- Aimed placement (Zone.aimed_target) ---

## The camera tuning of data/camera.cfg, built by hand.
func _aim_params() -> AimRay.Params:
	var a := AimRay.Params.new()
	a.pivot_height = 1.6
	a.shoulder_offset = 0.7
	a.distance = 4.5
	a.max_distance = 100.0
	return a


## Where `ray` meets flat ground (y = 0).
func _ground_hit(ray: AimRay) -> Vector3:
	return ray.point_at(-ray.origin.y / ray.direction.y)


func test_an_aimed_zone_lands_at_the_crosshair_within_range() -> void:
	var ray := AimRay.create(Vector3.ZERO, 0.0, deg_to_rad(-20.0), _aim_params())
	var aim := _ground_hit(ray)  # about 4.4 m ahead, 0.7 m right
	var at := Zone.aimed_target(Vector3.ZERO, ray, aim, true, 0.0, 10.0)
	assert_true(at.distance_to(aim) < Zone.AIM_BACKOFF + 0.001, "at the aim point")
	assert_almost(at.x, 0.7, 0.05, "on the crosshair's line")


func test_an_aimed_zone_past_its_range_is_clamped_on_the_crosshair_line() -> void:
	var ray := AimRay.create(Vector3.ZERO, 0.0, deg_to_rad(-20.0), _aim_params())
	var at := Zone.aimed_target(Vector3.ZERO, ray, _ground_hit(ray), true, 0.0, 3.0)
	assert_almost(Vector2(at.x, at.z).length(), 3.0, 0.001, "max range, horizontally")
	assert_almost(at.x, 0.7, 0.001, "still under the crosshair")
	assert_true(at.z < 0.0, "ahead")
	assert_almost(at.y, 0.0, 0.001, "at the feet's height")


func test_aiming_at_the_sky_places_it_at_max_range_along_the_heading() -> void:
	var feet := Vector3(5.0, 2.0, -3.0)
	for pitch_deg: float in [30.0, 90.0]:
		var yaw := PI / 2.0  # facing -X
		var ray := AimRay.create(feet, yaw, deg_to_rad(pitch_deg), _aim_params())
		var aim := ray.point_at(100.0)  # nothing hit
		var at := Zone.aimed_target(feet, ray, aim, false, yaw, 8.0)
		var flat := Vector2(at.x - feet.x, at.z - feet.z)
		assert_almost(flat.length(), 8.0, 0.001, "pitch %d: max range" % pitch_deg)
		assert_true(flat.x < -7.0, "pitch %d: ahead along the heading" % pitch_deg)
		assert_almost(at.y, feet.y, 0.001, "pitch %d: at the feet's height" % pitch_deg)


func test_a_hit_up_close_or_on_a_wall_counts_within_range() -> void:
	# Looking down at the ground right in front: lands there, not pushed out.
	var ray := AimRay.create(Vector3.ZERO, 0.0, deg_to_rad(-80.0), _aim_params())
	var aim := _ground_hit(ray)
	var at := Zone.aimed_target(Vector3.ZERO, ray, aim, true, 0.0, 10.0)
	assert_true(Vector2(at.x, at.z).length() < 1.0, "close to the feet")
	# A wall 4 m ahead hit at chest height: pulled back off its face.
	var level := AimRay.create(Vector3.ZERO, 0.0, 0.0, _aim_params())
	var on_wall := level.point_at(4.0)
	var off := Zone.aimed_target(Vector3.ZERO, level, on_wall, true, 0.0, 10.0)
	assert_true(off.z > on_wall.z, "on the near side of the wall")


# --- Fire Trail strips (Zone.strip_between, strip_size) ---

func _strip_params() -> ZoneParams:
	var p := _params(ZoneParams.TRIGGER_PULSE)
	p.wall = true
	p.strip = true
	p.wall_width = 1.6
	p.wall_depth = 1.0
	p.fast_roll_widen = 0.25
	return p


func test_a_strip_runs_from_the_roll_start_to_its_end() -> void:
	var straight := Zone.strip_between(Vector3.ZERO, Vector3(0.0, 0.0, -4.5))
	assert_true((straight[0] as Vector3).is_equal_approx(Vector3(0.0, 0.0, -2.25)), "center")
	assert_almost(straight[1], 0.0, 0.0001, "faces -Z")
	assert_almost(straight[2], 4.5, 0.0001, "length")
	var diagonal := Zone.strip_between(Vector3(1.0, 0.5, 1.0), Vector3(4.0, 0.2, 5.0))
	var yaw: float = diagonal[1]
	assert_true(Vector2(-sin(yaw), -cos(yaw)).is_equal_approx(Vector2(0.6, 0.8)), "along the roll")
	assert_almost(diagonal[2], 5.0, 0.0001, "horizontal length")
	assert_almost((diagonal[0] as Vector3).y, 0.5, 0.0001, "at the start's height")


func test_strip_size_follows_the_roll_length_and_speed() -> void:
	var p := _strip_params()
	assert_true(Zone.strip_size(p, 4.5, 1.0).is_equal_approx(Vector2(1.6, 4.5)), "a normal roll")
	assert_true(Zone.strip_size(p, 8.1, 1.8).is_equal_approx(Vector2(1.92, 8.1)),
			"Gust Roll: 1.8x longer and a bit wider")
	assert_true(Zone.strip_size(p, 0.2, 1.0).is_equal_approx(Vector2(1.6, 1.0)),
			"a roll stopped by a wall: the shortest strip")


func test_a_turned_strip_contains_what_lies_along_the_roll() -> void:
	var start := Vector3.ZERO
	var end := Vector3(4.0, 0.0, 3.0)  # 5 m along (0.8, 0.6)
	var strip := Zone.strip_between(start, end)
	var z := Zone.new(_strip_params(), strip[0], strip[1], 7)
	var size := Zone.strip_size(z.params, strip[2], 1.0)
	z.width = size.x
	z.depth = size.y
	assert_true(z.contains(Vector3(2.0, 0.0, 1.5)), "the middle of the roll")
	assert_true(z.contains(Vector3(0.4, 0.0, 0.3)), "near the start")
	assert_true(z.contains(Vector3(3.6, 0.0, 2.7)), "near the end")
	assert_false(z.contains(Vector3(4.8, 0.0, 3.6)), "1 m past the end")
	var side := Vector3(2.0 - 0.6, 0.0, 1.5 + 0.8)  # 1 m to the side of the middle
	assert_false(z.contains(side), "the feet 1 m to the side (half width 0.8)")
	assert_true(z.contains(side, 0.3), "a body overlapping its edge")
