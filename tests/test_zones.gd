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
		assert_true(p.affects in [ZoneParams.AFFECTS_HOSTILE, ZoneParams.AFFECTS_ALLY],
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
