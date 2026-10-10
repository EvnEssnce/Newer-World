extends TestCase
## DamageMeter: the training dummy's damage/DPS readout. Fights end after
## idle_time seconds without a hit.

var meter: DamageMeter


func before_each() -> void:
	meter = DamageMeter.new(4.0)


func test_empty_meter_shows_nothing() -> void:
	assert_false(meter.has_fight())
	assert_eq(meter.dps(10.0), 0.0)
	assert_eq(meter.duration(10.0), 0.0)


func test_adds_up_the_damage_of_a_fight() -> void:
	meter.add(100.0, 10.0)
	meter.add(150.0, 11.0)
	meter.add(50.0, 12.5)
	assert_almost(meter.total, 300.0)
	assert_eq(meter.hits, 3)


func test_dps_is_damage_over_time_since_the_first_hit() -> void:
	meter.add(100.0, 10.0)
	meter.add(100.0, 12.0)
	assert_almost(meter.dps(12.0), 100.0, 0.001, "200 over 2 s")
	assert_almost(meter.dps(14.0), 50.0, 0.001, "a pause mid-fight lowers it")


func test_one_hit_is_divided_by_the_minimum_duration() -> void:
	meter.add(250.0, 10.0)
	assert_almost(meter.dps(10.0), 250.0 / DamageMeter.MIN_DURATION)


func test_fight_ends_after_idle_time_and_freezes_at_the_last_hit() -> void:
	meter.add(100.0, 10.0)
	meter.add(300.0, 12.0)
	assert_true(meter.is_active(16.0), "exactly idle_time later is still the fight")
	assert_false(meter.is_active(16.5))
	assert_true(meter.has_fight(), "the last fight's result stays shown")
	assert_almost(meter.duration(30.0), 2.0)
	assert_almost(meter.dps(30.0), 200.0)


func test_a_hit_after_the_fight_ended_starts_a_new_one() -> void:
	meter.add(100.0, 10.0)
	meter.add(500.0, 20.0)
	assert_almost(meter.total, 500.0)
	assert_eq(meter.hits, 1)
	assert_almost(meter.duration(21.0), 1.0)
