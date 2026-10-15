extends TestCase
## CraftProgress: the crafting panel's progress (fraction, piece of a batch,
## time left, text), the rules that cancel a craft (moving at the station,
## closing the panel), and the XP feed line.


func test_fraction_fills_over_the_whole_batch() -> void:
	var progress := CraftProgress.new("ingot", 5, 600, 120)
	assert_almost(progress.fraction(600), 0.0)
	assert_almost(progress.fraction(300), 0.5)
	assert_almost(progress.fraction(0), 1.0)
	assert_almost(progress.fraction(900), 0.0, 0.001, "clamped below")
	assert_almost(progress.fraction(-5), 1.0, 0.001, "clamped above")


func test_piece_is_the_one_the_elapsed_time_reached() -> void:
	var progress := CraftProgress.new("ingot", 5, 600, 120)
	assert_eq(progress.piece(600), 1, "just started")
	assert_eq(progress.piece(481), 1, "119 ticks in")
	assert_eq(progress.piece(480), 2, "120 ticks in: the second")
	assert_eq(progress.piece(1), 5)
	assert_eq(progress.piece(0), 5, "never past the batch")


func test_status_text_shows_the_count_only_for_a_batch() -> void:
	var batch := CraftProgress.new("ingot", 5, 600, 120)
	assert_eq(batch.status_text(300, 60), "3 / 5   5.0 s left")
	var one := CraftProgress.new("ingot", 1, 120, 120)
	assert_eq(one.status_text(30, 60), "0.5 s left")


func test_seconds_left_never_negative() -> void:
	var progress := CraftProgress.new("ingot", 1, 120, 120)
	assert_almost(progress.seconds_left(90, 60), 1.5)
	assert_almost(progress.seconds_left(-3, 60), 0.0)


func test_ticks_left_from_the_clients_clock() -> void:
	var progress := CraftProgress.new("ingot", 2, 240, 120)
	assert_eq(progress.ticks_left_after(0), 240)
	assert_eq(progress.ticks_left_after(100), 140)
	assert_eq(progress.ticks_left_after(500), 0)


func test_bad_numbers_are_made_safe() -> void:
	var progress := CraftProgress.new("ingot", 0, 0, 0)
	assert_eq(progress.quantity, 1)
	assert_eq(progress.piece(0), 1)
	assert_almost(progress.fraction(0), 1.0)


func test_moving_cancels_but_standing_still_does_not() -> void:
	assert_false(CraftProgress.is_moving(Vector2.ZERO, 0), "standing still")
	assert_false(CraftProgress.is_moving(Vector2(0.05, 0.0), 0), "inside the dead zone")
	assert_true(CraftProgress.is_moving(Vector2(0.0, 1.0), 0), "walking")
	assert_true(CraftProgress.is_moving(Vector2.ZERO, PlayerState.BUTTON_JUMP), "jumping")
	assert_true(CraftProgress.is_moving(Vector2.ZERO, PlayerState.BUTTON_DODGE), "dodging")
	assert_false(CraftProgress.is_moving(Vector2.ZERO, PlayerState.BUTTON_BLOCK), "other buttons don't count")


func test_closing_the_panel_cancels_a_craft_under_way_or_asked_for() -> void:
	assert_true(CraftProgress.cancel_on_close(true, false), "crafting")
	assert_true(CraftProgress.cancel_on_close(false, true), "asked, not answered yet")
	assert_false(CraftProgress.cancel_on_close(false, false), "nothing going on")


func test_xp_feed_line() -> void:
	assert_eq(TradeskillSystem.xp_line("Mining", 25), "+25 Mining XP")


func test_pieces_done_counts_whole_pieces_only() -> void:
	# A batch of 5, 120 ticks each (600 in all).
	assert_eq(CraftProgress.pieces_done(600, 600, 120, 5), 0, "just started")
	assert_eq(CraftProgress.pieces_done(600, 481, 120, 5), 0, "first piece not done yet")
	assert_eq(CraftProgress.pieces_done(600, 480, 120, 5), 1, "first piece done")
	assert_eq(CraftProgress.pieces_done(600, 250, 120, 5), 2, "two done, third under way")
	assert_eq(CraftProgress.pieces_done(600, 0, 120, 5), 5, "all done")
	assert_eq(CraftProgress.pieces_done(600, -10, 120, 5), 5, "never more than the batch")
	assert_eq(CraftProgress.pieces_done(600, 700, 120, 5), 0, "never negative")


func test_move_closes_the_panel_only_once_armed() -> void:
	assert_false(CraftProgress.move_closes(false, true), "still walking up as F opened it")
	assert_true(CraftProgress.move_closes(true, true), "moving after standing still")
	assert_false(CraftProgress.move_closes(true, false), "standing still")
