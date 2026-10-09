extends TestCase
## ThreatTable rules: adding, the switch ratio, forced targets (taunts),
## taunt threat, dropping players, decay and tie-breaks.

const RATIO := 1.1

var table: ThreatTable


func before_each() -> void:
	table = ThreatTable.new()


func test_ignores_non_players() -> void:
	assert_false(table.add(-3, 50.0), "enemy ids aren't players")
	assert_false(table.add(0, 50.0), "0 = unknown source")
	assert_true(table.is_empty())


func test_adds_up() -> void:
	table.add(1, 10.0)
	table.add(1, 5.0)
	assert_almost(table.get_threat(1), 15.0)
	assert_almost(table.get_threat(2), 0.0, 0.001, "not in the table")


func test_picks_the_top_with_no_current_target() -> void:
	table.add(1, 10.0)
	table.add(2, 30.0)
	assert_eq(table.pick_target(0, RATIO), 2)


func test_ties_go_to_whoever_came_first() -> void:
	table.add(2, 10.0)
	table.add(1, 10.0)
	assert_eq(table.pick_target(0, RATIO), 2)


func test_keeps_the_target_until_beaten_by_the_ratio() -> void:
	table.add(1, 100.0)
	table.add(2, 110.0)
	assert_eq(table.pick_target(1, RATIO), 1, "exactly 1.1x isn't enough")
	table.add(2, 0.5)
	assert_eq(table.pick_target(1, RATIO), 2, "more than 1.1x takes it")


func test_a_dropped_target_hands_over_to_the_next() -> void:
	table.add(1, 100.0)
	table.add(2, 20.0)
	table.remove(1)
	assert_eq(table.pick_target(1, RATIO), 2)
	table.remove(2)
	assert_eq(table.pick_target(2, RATIO), 0, "empty table: nobody")


func test_keep_only_drops_players_who_are_gone() -> void:
	table.add(1, 10.0)
	table.add(2, 10.0)
	table.add(3, 10.0)
	table.keep_only({1: Vector3.ZERO, 3: Vector3.ZERO})
	assert_true(table.has(1))
	assert_false(table.has(2))
	assert_true(table.has(3))


func test_forced_target_wins_while_in_the_table() -> void:
	table.add(1, 500.0)
	table.add(2, 1.0)
	assert_eq(table.pick_target(1, RATIO, 2), 2)
	assert_eq(table.pick_target(1, RATIO, 9), 1, "a taunter not in the table is ignored")


func test_taunt_lifts_threat_above_the_top() -> void:
	table.add(1, 200.0)
	table.add(2, 10.0)
	table.taunt(2, RATIO)
	assert_almost(table.get_threat(2), 220.0)
	assert_eq(table.pick_target(2, RATIO), 2, "aggro sticks once the taunt ends")
	table.add(1, 20.0)
	assert_eq(table.pick_target(2, RATIO), 2, "220 vs 220: the old target needs 10% more")
	table.add(1, 23.0)
	assert_eq(table.pick_target(2, RATIO), 1)


func test_taunt_never_lowers_threat() -> void:
	table.add(1, 300.0)
	table.taunt(1, RATIO)
	assert_almost(table.get_threat(1), 330.0, 0.001, "already the top: 1.1x its own")
	table.taunt(2, RATIO)
	assert_almost(table.get_threat(2), 363.0)


func test_taunt_on_an_empty_table_adds_the_taunter() -> void:
	assert_true(table.taunt(4, RATIO))
	assert_eq(table.pick_target(0, RATIO), 4)
	assert_false(table.taunt(-1, RATIO), "only players taunt")


func test_decay_scales_everyone() -> void:
	table.add(1, 100.0)
	table.add(2, 50.0)
	table.decay(0.5)
	assert_almost(table.get_threat(1), 50.0)
	assert_almost(table.get_threat(2), 25.0)
	table.decay(1.0)
	assert_almost(table.get_threat(1), 50.0, 0.001, "1 = no decay")
