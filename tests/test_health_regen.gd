extends TestCase
## HealthRegen: out-of-combat regeneration, built by hand (delay 10 ticks,
## combat_time 6 ticks, 1% of max health per tick).

var regen: HealthRegen


func before_each() -> void:
	regen = HealthRegen.new()
	regen.delay_ticks = 10
	regen.fraction_per_tick = 0.01


func _steps(count: int, combat_ticks: int, health: float, multiplier := 1.0) -> float:
	var healed := 0.0
	for i in count:
		healed += regen.step(combat_ticks, 6, false, health, 1000.0, multiplier)
	return healed


func test_waits_the_delay_after_combat() -> void:
	_steps(1, 1, 500.0)  # last combat tick: 5 ticks since the damage
	assert_almost(_steps(4, 0, 500.0), 0.0, 0.001, "still waiting (6..9)")
	assert_almost(_steps(1, 0, 500.0), 10.0, 0.001, "10 ticks after: 1% of 1000")


func test_nothing_while_in_combat() -> void:
	assert_almost(_steps(20, 6, 500.0), 0.0)


func test_combat_restarts_the_wait() -> void:
	_steps(20, 0, 500.0)
	_steps(1, 6, 500.0)  # hit again
	assert_almost(_steps(1, 0, 500.0), 0.0, 0.001, "waiting again")


func test_capped_at_max_health_and_off_when_full() -> void:
	_steps(10, 0, 1000.0)
	assert_almost(regen.step(0, 6, false, 995.0, 1000.0, 1.0), 5.0)
	assert_almost(regen.step(0, 6, false, 1000.0, 1000.0, 1.0), 0.0)


func test_modifiers_scale_it() -> void:
	_steps(10, 0, 500.0)
	assert_almost(regen.step(0, 6, false, 500.0, 1000.0, 1.5), 15.0)
	assert_almost(regen.step(0, 6, false, 500.0, 1000.0, 0.0), 0.0)


func test_dead_resets_the_wait() -> void:
	_steps(10, 0, 500.0)
	assert_almost(regen.step(0, 6, true, 0.0, 1000.0, 1.0), 0.0)
	assert_almost(regen.step(0, 6, false, 300.0, 1000.0, 1.0), 0.0, 0.001, "waits again after rising")
