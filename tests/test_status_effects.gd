extends TestCase
## StatusEffects rules: applying, stacking, refreshing, ticking down, removal
## and cleanse, damage multipliers, bleed math, on-hit statuses (Bloodlust's
## "next N hits") and the network round trip. Fixed defs, not the data file
## (except the last test, which validates the real file).

var defs: StatusDefs
var effects: StatusEffects
var bleed: int
var slow: int
var root: int
var stun: int
var exposed: int
var empowered: int
var warded: int
var bloodlust: int


func before_each() -> void:
	defs = StatusDefs.new()
	var d := _def("bleed", StatusDef.CATEGORY_DEBUFF, 300, 5)
	d.tick_interval_ticks = 30
	d.damage_per_interval = 5.0  # 10 per second per stack
	bleed = defs.add(d)
	d = _def("slow", StatusDef.CATEGORY_DEBUFF, 180, 1)
	d.move_multiplier = 0.6
	d.affects = StatusDef.AFFECTS_SIM
	slow = defs.add(d)
	d = _def("root", StatusDef.CATEGORY_DEBUFF, 90, 1)
	d.stops_movement = true
	d.affects = StatusDef.AFFECTS_SIM
	root = defs.add(d)
	d = _def("stun", StatusDef.CATEGORY_DEBUFF, 60, 1)
	d.stuns = true
	d.affects = StatusDef.AFFECTS_SIM
	stun = defs.add(d)
	d = _def("exposed", StatusDef.CATEGORY_DEBUFF, 360, 2)
	d.damage_taken = 0.25
	exposed = defs.add(d)
	d = _def("empowered", StatusDef.CATEGORY_BUFF, 360, 3)
	d.damage_dealt = 0.2
	empowered = defs.add(d)
	d = _def("warded", StatusDef.CATEGORY_BUFF, 240, 1)
	d.damage_taken = -0.4
	warded = defs.add(d)
	d = _def("bloodlust", StatusDef.CATEGORY_BUFF, 480, 4)
	d.on_hit_status = "bleed"
	d.on_hit_stacks = 1
	d.consume_on_hit = true
	bloodlust = defs.add(d)
	effects = StatusEffects.new()


func _def(id: String, category: String, duration: int, max_stacks: int) -> StatusDef:
	var d := StatusDef.new()
	d.id = id
	d.display_name = id.capitalize()
	d.category = category
	d.duration_ticks = duration
	d.max_stacks = max_stacks
	return d


func _ticks(count: int) -> float:
	var damage := 0.0
	for i in count:
		damage += effects.tick(defs)
	return damage


# --- Apply, stack, refresh, expire ---

func test_apply_adds_a_status_with_its_duration() -> void:
	assert_true(effects.apply(defs, slow))
	assert_true(effects.has(slow))
	assert_eq(effects.stacks(slow), 1)
	assert_eq(effects.ticks_left(slow), 180)


func test_apply_rejects_unknown_status_and_zero_stacks() -> void:
	assert_false(effects.apply(defs, 99))
	assert_false(effects.apply(defs, -1))
	assert_false(effects.apply(defs, slow, 0))
	assert_true(effects.is_empty())


func test_stacks_add_up_to_the_cap() -> void:
	effects.apply(defs, bleed, 2)
	effects.apply(defs, bleed, 2)
	assert_eq(effects.stacks(bleed), 4)
	effects.apply(defs, bleed, 3)
	assert_eq(effects.stacks(bleed), 5, "capped at max_stacks")
	assert_eq(effects.entries.size(), 1, "one entry per status")


func test_reapplying_refreshes_to_full_duration() -> void:
	effects.apply(defs, slow)
	_ticks(100)
	assert_eq(effects.ticks_left(slow), 80)
	effects.apply(defs, slow)
	assert_eq(effects.ticks_left(slow), 180)


func test_shorter_reapply_never_shortens() -> void:
	effects.apply(defs, slow, 1, 500)
	effects.apply(defs, slow, 1, 50)
	assert_eq(effects.ticks_left(slow), 500)


func test_duration_override() -> void:
	effects.apply(defs, slow, 1, 45)
	assert_eq(effects.ticks_left(slow), 45)


func test_expires_after_its_duration() -> void:
	effects.apply(defs, root)
	_ticks(89)
	assert_true(effects.has(root))
	_ticks(1)
	assert_false(effects.has(root))
	assert_true(effects.is_empty())


# --- Removal and cleanse ---

func test_remove_one_status() -> void:
	effects.apply(defs, slow)
	effects.apply(defs, bleed)
	assert_true(effects.remove(slow))
	assert_false(effects.has(slow))
	assert_true(effects.has(bleed))
	assert_false(effects.remove(slow), "already gone")


func test_cleanse_removes_debuffs_and_keeps_buffs() -> void:
	effects.apply(defs, slow)
	effects.apply(defs, bleed, 3)
	effects.apply(defs, empowered)
	effects.apply(defs, warded)
	assert_eq(effects.remove_debuffs(defs), 2)
	assert_false(effects.has(slow))
	assert_false(effects.has(bleed))
	assert_true(effects.has(empowered))
	assert_true(effects.has(warded))


# --- Sim queries ---

func test_no_statuses_means_no_effect() -> void:
	assert_eq(effects.move_multiplier(defs), 1.0)
	assert_true(effects.can_move(defs))
	assert_true(effects.can_act(defs))
	assert_eq(effects.damage_taken_multiplier(defs), 1.0)
	assert_eq(effects.damage_dealt_multiplier(defs), 1.0)


func test_slow_root_and_stun_queries() -> void:
	effects.apply(defs, slow)
	assert_almost(effects.move_multiplier(defs), 0.6)
	assert_true(effects.can_move(defs))
	effects.apply(defs, root)
	assert_false(effects.can_move(defs))
	assert_true(effects.can_act(defs), "rooted can still act")
	effects.apply(defs, stun)
	assert_false(effects.can_act(defs))


func test_strongest_slow_counts() -> void:
	var stronger := _def("cripple", StatusDef.CATEGORY_DEBUFF, 60, 1)
	stronger.move_multiplier = 0.3
	stronger.affects = StatusDef.AFFECTS_SIM
	var cripple := defs.add(stronger)
	effects.apply(defs, slow)
	effects.apply(defs, cripple)
	assert_almost(effects.move_multiplier(defs), 0.3)


# --- Damage multipliers ---

func test_exposed_scales_damage_taken_per_stack() -> void:
	effects.apply(defs, exposed)
	assert_almost(effects.damage_taken_multiplier(defs), 1.25)
	effects.apply(defs, exposed)
	assert_almost(effects.damage_taken_multiplier(defs), 1.5)


func test_damage_taken_modifiers_add_up() -> void:
	effects.apply(defs, exposed)  # +25%
	effects.apply(defs, warded)   # -40%
	assert_almost(effects.damage_taken_multiplier(defs), 0.85)


func test_damage_taken_never_goes_negative() -> void:
	var big := _def("immune", StatusDef.CATEGORY_BUFF, 60, 1)
	big.damage_taken = -2.0
	effects.apply(defs, defs.add(big))
	assert_eq(effects.damage_taken_multiplier(defs), 0.0)


func test_damage_dealt_per_stack() -> void:
	effects.apply(defs, empowered, 2)
	assert_almost(effects.damage_dealt_multiplier(defs), 1.4)
	assert_almost(effects.damage_taken_multiplier(defs), 1.0, 0.001, "doesn't change damage taken")


# --- Bleed ---

func test_bleed_ticks_every_interval_per_stack() -> void:
	effects.apply(defs, bleed, 3)
	assert_almost(_ticks(29), 0.0, 0.001, "nothing before the first interval")
	assert_almost(effects.tick(defs), 15.0, 0.001, "5 per stack per interval")


func test_bleed_total_over_its_duration() -> void:
	effects.apply(defs, bleed, 2)
	# 300 ticks / 30 = 10 intervals, the last on the tick it expires.
	assert_almost(_ticks(400), 10 * 2 * 5.0)
	assert_false(effects.has(bleed))


func test_refresh_keeps_the_bleed_rhythm() -> void:
	effects.apply(defs, bleed)
	_ticks(20)
	effects.apply(defs, bleed)  # refresh + stack; doesn't restart the 30-tick interval
	assert_almost(_ticks(10), 10.0, 0.001, "ticks at 30 with both stacks")


func test_bleed_source_is_reported() -> void:
	effects.apply(defs, bleed, 1, -1, 42)
	_ticks(30)
	assert_eq(effects.last_damage_source, 42)


func test_statuses_without_damage_deal_none() -> void:
	effects.apply(defs, slow)
	effects.apply(defs, exposed)
	assert_almost(_ticks(180), 0.0)


# --- On-hit statuses (Bloodlust) ---

func test_bloodlust_applies_bleed_for_the_next_n_hits() -> void:
	effects.apply(defs, bloodlust, 4)
	for hit in 4:
		var on_hit := effects.take_on_hit_statuses(defs)
		assert_eq(on_hit.size(), 1, "hit %d" % hit)
		assert_eq(on_hit[0], Vector2i(bleed, 1))
		assert_eq(effects.stacks(bloodlust), 3 - hit)
	assert_false(effects.has(bloodlust), "used up")
	assert_eq(effects.take_on_hit_statuses(defs).size(), 0, "the fifth hit applies nothing")


func test_on_hit_status_without_consume_lasts() -> void:
	var d := _def("venom", StatusDef.CATEGORY_BUFF, 60, 1)
	d.on_hit_status = "slow"
	d.on_hit_stacks = 1
	var venom := defs.add(d)
	effects.apply(defs, venom)
	for hit in 3:
		assert_eq(effects.take_on_hit_statuses(defs), [Vector2i(slow, 1)] as Array[Vector2i])
	assert_true(effects.has(venom))


func test_no_on_hit_statuses_by_default() -> void:
	effects.apply(defs, empowered)
	assert_eq(effects.take_on_hit_statuses(defs).size(), 0)
	assert_true(effects.has(empowered))


# --- Network and display ---

func test_packed_round_trip() -> void:
	effects.apply(defs, bleed, 3, -1, 7)
	effects.apply(defs, slow)
	_ticks(12)
	var copy := StatusEffects.from_packed(effects.to_packed())
	assert_eq(copy.to_packed(), effects.to_packed())
	assert_eq(copy.stacks(bleed), 3)
	assert_eq(copy.ticks_left(slow), 168)
	assert_eq(copy.find(bleed).source, 0, "sources are server-only")


func test_summary_lists_names_and_stacks() -> void:
	effects.apply(defs, bleed, 3)
	effects.apply(defs, slow)
	assert_eq(effects.summary(defs), "Bleed x3, Slow")


func test_real_status_file_is_valid() -> void:
	var real := StatusDefs.from_tuning()
	assert_eq(real.validate(), "")
	for id in ["bleed", "slow", "root", "stun", "exposed", "damage_up", "damage_reduction", "bloodlust"]:
		assert_true(real.index_of(id) >= 0, "has %s" % id)


func test_test_defs_are_valid() -> void:
	assert_eq(defs.validate(), "")


func test_validate_catches_a_sim_effect_marked_damage() -> void:
	var bad := _def("bad", StatusDef.CATEGORY_DEBUFF, 60, 1)
	bad.affects = StatusDef.AFFECTS_DAMAGE
	bad.stops_movement = true
	defs.add(bad)
	assert_true(defs.validate().contains("bad"))
