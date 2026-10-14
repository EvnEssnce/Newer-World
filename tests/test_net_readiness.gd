extends TestCase
## Internet readiness (Step G item 19): PositionHistory (lag compensation's
## record of where bodies stood), CorrectionSmoothing (the local player's drawn
## offset after a correction) and the server's tuning reaching clients
## (Tuning.pack / apply_packed).

const TUNING_SCRIPT := preload("res://core/tuning.gd")


# --- PositionHistory ---

func _walked(ticks: int) -> PositionHistory:
	# 0.1 m per tick along x, ticks 1..ticks.
	var history := PositionHistory.new(30, 1.5)
	for tick in range(1, ticks + 1):
		history.record(tick, Vector3(tick * 0.1, 0.0, 0.0))
	return history


func test_history_returns_the_position_at_a_tick() -> void:
	var history := _walked(10)
	var current := Vector3(1.05, 0.0, 0.0)
	assert_eq(history.at(4, current), Vector3(0.4, 0.0, 0.0))
	assert_eq(history.at(10, current), Vector3(1.0, 0.0, 0.0), "the newest record")


func test_history_newer_than_its_records_is_the_current_position() -> void:
	var history := _walked(10)
	var current := Vector3(1.05, 0.0, 0.0)
	assert_eq(history.at(11, current), current)
	assert_eq(PositionHistory.new().at(3, current), current, "nothing recorded yet")


func test_history_older_than_its_records_is_the_oldest() -> void:
	var history := PositionHistory.new(5, 1.5)
	for tick in range(1, 11):
		history.record(tick, Vector3(tick * 0.1, 0.0, 0.0))
	assert_eq(history.size(), 5, "keeps only capacity ticks")
	assert_eq(history.at(2, Vector3.ZERO), Vector3(0.6, 0.0, 0.0), "tick 6 is the oldest kept")


func test_history_gap_uses_the_older_record() -> void:
	var history := PositionHistory.new(30, 1.5)
	history.record(10, Vector3(1.0, 0.0, 0.0))
	history.record(13, Vector3(1.3, 0.0, 0.0))
	assert_eq(history.at(12, Vector3(1.4, 0.0, 0.0)), Vector3(1.0, 0.0, 0.0))


func test_history_ignores_repeated_or_older_ticks() -> void:
	var history := _walked(5)
	history.record(5, Vector3(9.0, 0.0, 0.0))
	history.record(3, Vector3(9.0, 0.0, 0.0))
	assert_eq(history.size(), 5)
	assert_eq(history.at(5, Vector3.ZERO), Vector3(0.5, 0.0, 0.0))


func test_history_never_reaches_back_past_a_teleport() -> void:
	var history := _walked(5)
	# A Blink at tick 6: 7 m in one tick, then walking on.
	history.record(6, Vector3(7.5, 0.0, 0.0))
	history.record(7, Vector3(7.6, 0.0, 0.0))
	var current := Vector3(7.7, 0.0, 0.0)
	assert_eq(history.at(3, current), Vector3(7.5, 0.0, 0.0), "the first position after it")
	assert_eq(history.at(6, current), Vector3(7.5, 0.0, 0.0))
	assert_eq(history.at(7, current), Vector3(7.6, 0.0, 0.0))


func test_history_teleport_this_tick_keeps_the_current_position() -> void:
	var history := _walked(5)
	# Respawned this tick (not recorded yet): every view of it is the spawn point.
	var spawn := Vector3(-3.0, 0.0, 0.0)
	assert_eq(history.at(5, spawn), spawn)
	assert_eq(history.at(2, spawn), spawn)


# --- CorrectionSmoothing ---

func test_smoothing_keeps_drawing_where_the_body_was() -> void:
	var smoothing := CorrectionSmoothing.new(0.1, 1.0)
	# Reconciliation moved the body 0.3 m forward: draw it 0.3 m back at first.
	smoothing.add_jump(Vector3(0.3, 0.0, 0.0))
	assert_eq(smoothing.offset, Vector3(-0.3, 0.0, 0.0))


func test_smoothing_blends_out_over_its_time() -> void:
	var smoothing := CorrectionSmoothing.new(0.1, 1.0)
	smoothing.add_jump(Vector3(0.5, 0.0, 0.0))
	var halfway := smoothing.step(0.03).length()
	assert_true(halfway < 0.5 and halfway > 0.1, "partly blended after 0.03 s (%.3f)" % halfway)
	var after := halfway
	for i in 4:
		after = smoothing.step(0.0175).length()
	assert_true(after <= 0.5 * 0.06, "about 95%% gone after 0.1 s (%.3f left)" % after)
	for i in 30:
		smoothing.step(0.0167)
	assert_eq(smoothing.offset, Vector3.ZERO, "settles to exactly zero")


func test_smoothing_adds_up_corrections() -> void:
	var smoothing := CorrectionSmoothing.new(0.1, 1.0)
	smoothing.add_jump(Vector3(0.2, 0.0, 0.0))
	smoothing.add_jump(Vector3(0.0, 0.0, 0.1))
	assert_eq(smoothing.offset, Vector3(-0.2, 0.0, -0.1))


func test_smoothing_snaps_long_jumps() -> void:
	var smoothing := CorrectionSmoothing.new(0.1, 1.0)
	smoothing.add_jump(Vector3(0.6, 0.0, 0.0))
	smoothing.add_jump(Vector3(0.6, 0.0, 0.0))  # 1.2 m in all: snap
	assert_eq(smoothing.offset, Vector3.ZERO)
	smoothing.add_jump(Vector3(0.0, 0.0, 20.0))  # a respawn
	assert_eq(smoothing.offset, Vector3.ZERO)


func test_smoothing_off_snaps() -> void:
	var smoothing := CorrectionSmoothing.new(0.0, 1.0)
	smoothing.add_jump(Vector3(0.3, 0.0, 0.0))
	assert_eq(smoothing.step(0.016), Vector3.ZERO)


# --- The server's tuning ---

func test_tuning_pack_round_trips_every_value_exactly() -> void:
	var server: Node = TUNING_SCRIPT.new()
	var client: Node = TUNING_SCRIPT.new()
	# The server's edits and overrides (types kept) reach the client.
	server._files["movement"].set_value("player", "move_speed", 6.123456789012345)
	server._files["network"].set_value("client", "input_redundancy", 7)
	server._files["network"].set_value("client", "default_address", "10.0.0.9")
	var before: int = client.version
	assert_true(client.apply_packed(server.pack()))
	assert_eq(client.version, before + 1, "version moves so caches rebuild")
	var speed: Variant = client.get_value("movement", "player", "move_speed")
	assert_true(speed is float and speed == 6.123456789012345, "float bits kept (%s)" % speed)
	var redundancy: Variant = client.get_value("network", "client", "input_redundancy")
	assert_true(redundancy is int and redundancy == 7, "ints stay ints")
	assert_eq(client.get_value("network", "client", "default_address"), "10.0.0.9")
	server.free()
	client.free()


func test_tuning_pack_keeps_files_sections_and_order() -> void:
	var server: Node = TUNING_SCRIPT.new()
	var client: Node = TUNING_SCRIPT.new()
	server._files["zz_server_only"] = ConfigFile.new()
	server._files["zz_server_only"].set_value("b", "x", 1)
	server._files["zz_server_only"].set_value("a", "y", [1, 2.5, "z"])
	assert_true(client.apply_packed(server.pack()))
	assert_eq(client.get_sections("zz_server_only"), PackedStringArray(["b", "a"]),
			"section order (items, loot tables) kept")
	assert_eq(client.get_value("zz_server_only", "a", "y"), [1, 2.5, "z"])
	assert_eq(client.get_sections("items"), server.get_sections("items"))
	assert_eq(client.files_with_prefix("weapon_"), server.files_with_prefix("weapon_"))
	server.free()
	client.free()


func test_tuning_rejects_bad_bytes_and_keeps_its_own() -> void:
	var client: Node = TUNING_SCRIPT.new()
	var before: int = client.version
	var speed: Variant = client.get_value("movement", "player", "move_speed")
	# (Truncated bytes would make the engine log a decode error; values that
	# aren't a pack are what a mismatched build could send.)
	assert_false(client.apply_packed(var_to_bytes(42)))
	assert_false(client.apply_packed(PackedByteArray()))
	assert_false(client.apply_packed(var_to_bytes({"movement": "not sections"})))
	assert_eq(client.version, before)
	assert_eq(client.get_value("movement", "player", "move_speed"), speed)
	client.free()


func test_caches_rebuild_when_the_tuning_version_moves() -> void:
	var first := PlayerParams.current()
	assert_true(PlayerParams.current() == first, "cached while nothing changes")
	Tuning.version += 1
	var second := PlayerParams.current()
	assert_false(second == first, "rebuilt after the server's tuning")
	assert_eq(second.max_health, first.max_health, "from the same values")
