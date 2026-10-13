extends TestCase
## Embedded knives (EmbeddedKnives, for Recall): per-thrower cap, expiry,
## ripping out, dropping a target; and the status that mirrors them
## (StatusEffects.set_stacks, PlayerState.set_status_stacks).

const THROWER := 1
const OTHER := 2
const HUSK := -1
const PLAYER := 5

var knives: EmbeddedKnives


func before_each() -> void:
	knives = EmbeddedKnives.new(3, 100)


func test_counts_per_target_and_thrower() -> void:
	knives.add(THROWER, HUSK, 0)
	knives.add(THROWER, HUSK, 0)
	knives.add(THROWER, PLAYER, 0)
	knives.add(OTHER, HUSK, 0)
	assert_eq(knives.count_in(HUSK), 3, "both throwers' knives")
	assert_eq(knives.count_in(PLAYER), 1)
	assert_eq(knives.count_of(THROWER), 3)
	assert_eq(knives.count_of(OTHER), 1)


func test_past_the_cap_the_throwers_oldest_falls_out() -> void:
	assert_eq(knives.add(THROWER, PLAYER, 0), 0)
	assert_eq(knives.add(THROWER, HUSK, 1), 0)
	assert_eq(knives.add(THROWER, HUSK, 2), 0)
	assert_eq(knives.add(THROWER, HUSK, 3), PLAYER, "the oldest (in the player) is pushed out")
	assert_eq(knives.count_in(PLAYER), 0)
	assert_eq(knives.count_in(HUSK), 3)
	assert_eq(knives.add(OTHER, HUSK, 4), 0, "the cap is per thrower")


func test_knives_fall_out_after_their_time() -> void:
	knives.add(THROWER, HUSK, 0)
	knives.add(THROWER, PLAYER, 50)
	assert_eq(knives.last_expiry(HUSK), 100)
	assert_eq(knives.expire(99), [] as Array[int])
	assert_eq(knives.expire(100), [HUSK] as Array[int])
	assert_eq(knives.count_in(HUSK), 0)
	assert_eq(knives.count_in(PLAYER), 1)
	assert_eq(knives.expire(150), [PLAYER] as Array[int])
	assert_eq(knives.targets(), [] as Array[int])


func test_recall_takes_every_knife_of_its_thrower_only() -> void:
	knives.add(THROWER, HUSK, 0)
	knives.add(THROWER, HUSK, 0)
	knives.add(THROWER, PLAYER, 0)
	knives.add(OTHER, HUSK, 0)
	var torn := knives.take(THROWER)
	assert_eq(torn[HUSK], 2)
	assert_eq(torn[PLAYER], 1)
	assert_eq(knives.count_of(THROWER), 0, "used up")
	assert_eq(knives.count_in(HUSK), 1, "the other thrower's stays")
	assert_true(knives.take(THROWER).is_empty(), "nothing left to recall")


func test_drop_target_removes_every_throwers_knives_in_it() -> void:
	knives.add(THROWER, HUSK, 0)
	knives.add(OTHER, HUSK, 0)
	knives.add(THROWER, PLAYER, 0)
	assert_eq(knives.drop_target(HUSK), 2)
	assert_eq(knives.count_in(HUSK), 0)
	assert_eq(knives.targets(), [PLAYER] as Array[int])


func test_set_stacks_mirrors_an_exact_count() -> void:
	var defs := _defs()
	var statuses := StatusEffects.new()
	assert_true(statuses.set_stacks(0, 11, 60, THROWER), "above max_stacks is allowed")
	assert_eq(statuses.stacks_of(0), 11)
	assert_eq(statuses.ticks_left(0), 60)
	assert_false(statuses.set_stacks(0, 11, 60), "no change")
	assert_true(statuses.set_stacks(0, 2, 30))
	assert_eq(statuses.stacks_of(0), 2)
	assert_true(statuses.set_stacks(0, 0, 30))
	assert_false(statuses.has(0), "0 removes it")
	statuses.set_stacks(0, 2, 30)
	assert_eq(statuses.remove_debuffs(defs), 1, "a cleanse removes it (a debuff)")


func test_player_status_change_is_a_server_event() -> void:
	var state := PlayerState.new()
	var events := state.server_events
	state.set_status_stacks(0, 2, 60, THROWER)
	assert_eq(state.server_events, events + 1)
	state.set_status_stacks(0, 2, 60, THROWER)
	assert_eq(state.server_events, events + 1, "unchanged: no event")
	state.kill()
	events = state.server_events
	state.set_status_stacks(0, 1, 60, THROWER)
	assert_false(state.statuses.has(0), "not on the dead")
	assert_eq(state.server_events, events)


func _defs() -> StatusDefs:
	var def := StatusDef.new()
	def.id = "embedded_knife"
	def.category = StatusDef.CATEGORY_DEBUFF
	def.max_stacks = 8
	def.duration_ticks = 600
	var defs := StatusDefs.new()
	defs.add(def)
	return defs
