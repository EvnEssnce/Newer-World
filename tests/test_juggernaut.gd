extends TestCase
## Juggernaut rules that don't need a scene: the Earthshaker heavy counter, the
## Tempest Wings wall test and knockback bonus, a second target status
## (Challenger's Roar), cone hitboxes (Seismic Slam) and Anchor's stacking
## damage reduction. Params are built by hand, not read from data/.


# --- Earthshaker: every 3rd heavy ---

func test_every_third_heavy_triggers() -> void:
	var counter := HeavyCounter.new()
	var fired: Array[bool] = []
	for serial in [10, 11, 12, 13, 14, 15]:
		fired.append(counter.register(serial, 3))
	assert_eq(fired, [false, false, true, false, false, true] as Array[bool])


func test_a_heavy_counts_once_however_long_its_hitbox_is_live() -> void:
	var counter := HeavyCounter.new()
	for i in 5:
		counter.register(7, 3)
	assert_eq(counter.count, 1, "the same attack_serial is one heavy")
	assert_false(counter.register(8, 3))
	assert_true(counter.register(9, 3), "third distinct heavy")
	assert_false(counter.register(9, 3), "not again on its next live tick")


func test_heavy_counter_never_triggers_without_a_period() -> void:
	var counter := HeavyCounter.new()
	for serial in 6:
		assert_false(counter.register(serial, 0))


# --- Tempest Wings: knocked into a wall ---

func test_pushed_head_on_into_a_wall() -> void:
	# Pushed toward +X into a wall whose normal faces -X.
	assert_true(ForcedMotion.pushed_into_wall(Vector2(5.0, 0.0), Vector3(-1.0, 0.0, 0.0)))
	# 45 degrees off still counts.
	assert_true(ForcedMotion.pushed_into_wall(Vector2(5.0, 5.0), Vector3(-1.0, 0.0, 0.0)))


func test_glancing_walls_floors_and_slow_pushes_dont_count() -> void:
	assert_false(ForcedMotion.pushed_into_wall(Vector2(5.0, 0.0), Vector3(0.0, 0.0, 1.0)),
			"sliding along a wall")
	assert_false(ForcedMotion.pushed_into_wall(Vector2(5.0, 0.0), Vector3(1.0, 0.0, 0.0)),
			"a wall behind, facing the way it's pushed")
	assert_false(ForcedMotion.pushed_into_wall(Vector2(5.0, 0.0), Vector3(-0.3, 0.95, 0.0)),
			"a slope / the floor")
	assert_false(ForcedMotion.pushed_into_wall(Vector2(0.2, 0.0), Vector3(-1.0, 0.0, 0.0)),
			"barely moving any more")


func test_knockback_bonus_pushes_farther_up_to_the_cap() -> void:
	var moved := ForceParams.scaled(Vector2(3.5, 0.0), 0.2, 6.0)
	assert_almost(moved.x, 4.2)
	moved = ForceParams.scaled(Vector2(0.0, -4.0), 0.8, 6.0)
	assert_almost(moved.length(), 6.0, 0.001, "capped at the max distance")
	assert_almost(moved.y, -6.0, 0.001, "same direction")
	assert_eq(ForceParams.scaled(Vector2(2.0, 1.0), 0.0, 6.0), Vector2(2.0, 1.0), "no bonus")
	assert_eq(ForceParams.scaled(Vector2.ZERO, 0.4, 6.0), Vector2.ZERO, "a pure launch stays put")


# --- Challenger's Roar: two statuses on one hit ---

func test_second_target_status() -> void:
	var roar := AttackParams.new()
	roar.applies_status = "taunted"
	roar.applies_status_2 = "slow"
	roar.status_stacks_2 = 2
	roar.status_duration_2_ticks = 180
	assert_eq(roar.target_statuses(), [["taunted", 1, -1], ["slow", 2, 180]] as Array[Array])
	roar.applies_status = ""
	assert_eq(roar.target_statuses(), [["slow", 2, 180]] as Array[Array], "the second alone")
	assert_true(AttackParams.new().target_statuses().is_empty())


func test_copy_keeps_every_field() -> void:
	var heavy := AttackParams.new()
	heavy.damage = 240.0
	heavy.applies_status_2 = "slow"
	heavy.hitbox_arc = 1.0
	var breaking := heavy.copy()
	breaking.breaks_block = true
	assert_almost(breaking.damage, 240.0)
	assert_eq(breaking.applies_status_2, "slow")
	assert_almost(breaking.hitbox_arc, 1.0)
	assert_false(heavy.breaks_block, "the original is unchanged")


# --- Seismic Slam: a cone ---

func test_cone_hits_only_in_front() -> void:
	var slam := AttackParams.new()
	slam.shape = AttackParams.SHAPE_RADIAL
	slam.hitbox_range = 4.0
	slam.hitbox_height = 2.0
	slam.hitbox_arc = deg_to_rad(90.0)
	var at := Vector3.ZERO
	# Yaw 0 faces -Z.
	assert_true(MeleeHitbox.hits(at, 0.0, slam, Vector3(0.0, 0.0, -3.0), 0.4, 1.8), "ahead")
	assert_true(MeleeHitbox.hits(at, 0.0, slam, Vector3(1.5, 0.0, -2.0), 0.4, 1.8), "inside 45 degrees")
	assert_false(MeleeHitbox.hits(at, 0.0, slam, Vector3(2.5, 0.0, -1.0), 0.4, 1.8), "off to the side")
	assert_false(MeleeHitbox.hits(at, 0.0, slam, Vector3(0.0, 0.0, 2.0), 0.4, 1.8), "behind")
	assert_false(MeleeHitbox.hits(at, 0.0, slam, Vector3(0.0, 0.0, -5.0), 0.4, 1.8), "out of range")
	slam.hitbox_arc = 0.0
	assert_true(MeleeHitbox.hits(at, 0.0, slam, Vector3(0.0, 0.0, 2.0), 0.4, 1.8),
			"no arc: all the way round")


func test_impact_copy_drops_the_cone() -> void:
	var slam := AttackParams.new()
	slam.shape = AttackParams.SHAPE_RADIAL
	slam.hitbox_arc = 1.5
	assert_almost(slam.radial_copy(2.5).hitbox_arc, 0.0)


# --- Anchor: Defiant stacks per taunted enemy ---

func test_defiant_stacks_reduce_damage_taken_up_to_its_cap() -> void:
	var defs := StatusDefs.new()
	var defiant := StatusDef.new()
	defiant.id = "defiant"
	defiant.category = StatusDef.CATEGORY_BUFF
	defiant.duration_ticks = 360
	defiant.max_stacks = 5
	defiant.damage_taken = -0.06
	var index := defs.add(defiant)
	var effects := StatusEffects.new()
	for taunted in 3:
		effects.apply(defs, index, 1)
	assert_almost(effects.damage_taken_multiplier(defs), 0.82, 0.0001, "3 enemies taunted")
	for taunted in 4:
		effects.apply(defs, index, 1)
	assert_eq(effects.stacks(index), 5)
	assert_almost(effects.damage_taken_multiplier(defs), 0.7, 0.0001, "capped at 5 stacks")
