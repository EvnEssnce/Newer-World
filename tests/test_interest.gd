extends TestCase
## Interest: who sees what (radius, hysteresis, always-visible ids, off).

var interest: Interest


func before_each() -> void:
	interest = Interest.new(20.0, 25.0)


func test_only_entities_within_the_enter_radius() -> void:
	var seen := interest.update(1, Vector3.ZERO, {2: Vector3(10, 0, 0), 3: Vector3(30, 0, 0), -1: Vector3(0, 0, -19)})
	assert_eq(seen, [2, -1] as Array[int])


func test_distance_is_horizontal() -> void:
	var seen := interest.update(1, Vector3.ZERO, {2: Vector3(10, 50, 0)})
	assert_eq(seen, [2] as Array[int], "height doesn't count")


func test_stays_in_view_until_past_the_exit_radius() -> void:
	interest.update(1, Vector3.ZERO, {2: Vector3(19, 0, 0)})
	assert_eq(interest.update(1, Vector3.ZERO, {2: Vector3(24, 0, 0)}), [2] as Array[int], "inside the margin")
	assert_eq(interest.update(1, Vector3.ZERO, {2: Vector3(26, 0, 0)}), [] as Array[int], "past it: gone")
	assert_eq(interest.update(1, Vector3.ZERO, {2: Vector3(24, 0, 0)}), [] as Array[int],
			"must come back within the enter radius")
	assert_eq(interest.update(1, Vector3.ZERO, {2: Vector3(20, 0, 0)}), [2] as Array[int])


func test_always_visible_ids() -> void:
	var seen := interest.update(1, Vector3.ZERO, {1: Vector3.ZERO, 5: Vector3(500, 0, 0)}, [1, 5])
	assert_eq(seen, [1, 5] as Array[int], "itself and its party, however far")


func test_each_viewer_has_its_own_view() -> void:
	interest.update(1, Vector3.ZERO, {3: Vector3(19, 0, 0)})
	assert_true(interest.sees(1, 3))
	assert_false(interest.sees(2, 3))
	assert_eq(interest.update(2, Vector3.ZERO, {3: Vector3(24, 0, 0)}), [] as Array[int],
			"viewer 2 never had it in view: the enter radius applies")
	interest.forget(1)
	assert_false(interest.sees(1, 3))


func test_zero_radius_means_off() -> void:
	interest = Interest.new(0.0, 0.0)
	assert_eq(interest.update(1, Vector3.ZERO, {2: Vector3(9999, 0, 0)}), [2] as Array[int])
