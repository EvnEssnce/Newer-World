extends TestCase
## War Hammer feedback: the Earthshaker ring (ShockRing: growth, the swept
## band, hit once) and Hooked applied only with the Warden capstone
## (CharacterBuild.applies_mark). Built by hand.


func _ring() -> ShockRing:
	# 12 m/s to 6 m, a 1 m band, feet up to 0.8 m above the ground.
	return ShockRing.new(Vector3.ZERO, 12.0, 6.0, 1.0, 0.8)


# --- ShockRing ---

func test_ring_grows_at_its_speed_and_stops_at_max_radius() -> void:
	var ring := _ring()
	ring.step(0.25)
	assert_almost(ring.radius, 3.0)
	assert_false(ring.is_done())
	ring.step(0.25)
	assert_almost(ring.radius, 6.0)
	assert_true(ring.is_done())
	ring.step(0.25)
	assert_almost(ring.radius, 6.0, 0.001, "never past max_radius")


func test_band_touches_what_the_edge_passes_this_step() -> void:
	var ring := _ring()
	ring.step(0.25)  # 0 -> 3 m
	assert_true(ring.touches(Vector3(0.0, 0.0, 0.5), 0.4), "near the center, swept over")
	assert_true(ring.touches(Vector3(3.2, 0.0, 0.0), 0.4), "body reaches the edge")
	assert_false(ring.touches(Vector3(4.0, 0.0, 0.0), 0.4), "ahead of the edge")
	ring.step(0.25)  # 3 -> 6 m: band from 2 m (3 - thickness) to 6 m
	assert_true(ring.touches(Vector3(0.0, 0.0, 5.0), 0.4), "passed this step")
	assert_false(ring.touches(Vector3(1.0, 0.0, 0.0), 0.4), "left behind the band")


func test_fast_ring_cannot_skip_a_target_between_ticks() -> void:
	var ring := ShockRing.new(Vector3.ZERO, 120.0, 30.0, 0.1, 1.0)
	ring.step(1.0 / 60.0)  # 2 m
	ring.step(1.0 / 60.0)  # 2 -> 4 m in one step
	assert_true(ring.touches(Vector3(3.0, 0.0, 0.0), 0.1))


func test_jumping_over_the_ring_avoids_it() -> void:
	var ring := _ring()
	ring.step(0.25)
	assert_true(ring.touches(Vector3(1.0, 0.5, 0.0), 0.4), "a low hop is still hit")
	assert_false(ring.touches(Vector3(1.0, 1.2, 0.0), 0.4), "feet above ring_height")
	assert_false(ring.touches(Vector3(1.0, -3.0, 0.0), 0.4), "far below")


func test_each_target_is_hit_once() -> void:
	var ring := _ring()
	assert_true(ring.can_hit(7))
	assert_true(ring.register_hit(7))
	assert_false(ring.can_hit(7))
	assert_false(ring.register_hit(7), "second time")
	assert_true(ring.register_hit(-2), "another target (an enemy)")


func test_an_evade_does_not_use_up_the_hit() -> void:
	var ring := _ring()
	ring.results[7] = false  # World.resolve_strike's evade
	assert_true(ring.can_hit(7))


func test_outward_yaw_points_away_from_the_center() -> void:
	var ring := ShockRing.new(Vector3(10.0, 0.0, 10.0), 12.0, 6.0, 1.0, 0.8)
	var target := Vector3(10.0, 0.0, 14.0)
	var yaw := ring.outward_yaw(target)
	var expected := PlayerState.yaw_for_direction(Vector2(0.0, 4.0))
	assert_almost(yaw, expected)


# --- Hooked only with Caught on the Hook ---

func _halberd_build() -> CharacterBuild:
	var class_def := ClassDef.new()
	class_def.id = "juggernaut"
	class_def.weapons = PackedStringArray(["halberd", "hammer"])
	class_def.default_loadout = PackedStringArray(["halberd", "hammer"])
	var tree := MasteryTree.new()
	tree.branches = PackedStringArray(["warden"])
	tree.tier_requirements = PackedInt32Array([0])
	tree.points = 10
	tree.add_node("hook", "warden", 1, MasteryTree.KIND_ACTIVE, 1, "hooking_pull")
	var n := tree.add_node("caught", "warden", 1, MasteryTree.KIND_PASSIVE, 1)
	n.effect = "hook_stagger"
	n.applies_to = "hooked"
	n.amount = 0.8
	tree.default_nodes = PackedStringArray(["hook"])
	return CharacterBuild.create(class_def, {"halberd": tree})


func test_hooked_needs_the_capstone() -> void:
	var build := _halberd_build()
	assert_false(build.applies_mark("halberd", "hooked"), "not learned")
	build.allocated["halberd"] = PackedStringArray(["hook", "caught"])
	assert_true(build.applies_mark("halberd", "hooked"), "learned")


func test_other_statuses_and_weapons_are_unaffected() -> void:
	var build := _halberd_build()
	assert_true(build.applies_mark("halberd", "slow"), "not a mark")
	assert_true(build.applies_mark("halberd", ""), "no status")
	assert_true(build.applies_mark("hammer", "hooked"), "no tree for that weapon")
