extends TestCase
## SaveSchedule: when the server saves characters (a change saved a fixed time
## after the first unsaved one, a periodic save of everyone), and the save
## fingerprint the restart check compares.


func test_a_change_is_saved_after_the_delay_from_the_first_change() -> void:
	var schedule := SaveSchedule.new(60.0, 3.0, 0.0)
	schedule.mark_changed(5, 10.0)
	schedule.mark_changed(5, 12.0)  # a later change doesn't push it back
	assert_true(schedule.is_changed(5))
	assert_eq(schedule.changes_due(12.9), [] as Array[int])
	assert_eq(schedule.changes_due(13.0), [5] as Array[int])


func test_due_changes_come_lowest_id_first_and_clear_when_saved() -> void:
	var schedule := SaveSchedule.new(60.0, 2.0, 0.0)
	schedule.mark_changed(9, 1.0)
	schedule.mark_changed(4, 1.5)
	schedule.mark_changed(7, 5.0)
	assert_eq(schedule.changes_due(4.0), [4, 9] as Array[int], "7 isn't due yet")
	schedule.saved([4, 9] as Array[int])
	assert_false(schedule.is_changed(4))
	assert_true(schedule.is_changed(7))
	assert_eq(schedule.changes_due(4.0), [] as Array[int])
	schedule.mark_changed(4, 6.0)
	assert_eq(schedule.changes_due(8.0), [4, 7] as Array[int], "a new change starts a new delay")


func test_zero_delay_saves_on_the_next_check() -> void:
	var schedule := SaveSchedule.new(60.0, 0.0, 0.0)
	schedule.mark_changed(3, 2.0)
	assert_eq(schedule.changes_due(2.0), [3] as Array[int])


func test_periodic_save_every_interval_clears_every_mark() -> void:
	var schedule := SaveSchedule.new(30.0, 5.0, 100.0)
	assert_false(schedule.periodic_due(129.9))
	assert_true(schedule.periodic_due(130.0))
	schedule.mark_changed(2, 128.0)
	schedule.saved_everyone(131.0)
	assert_false(schedule.is_changed(2), "the periodic save covered it")
	assert_false(schedule.periodic_due(160.0), "the next is an interval after the late one")
	assert_true(schedule.periodic_due(161.0))


func test_periodic_save_off_with_no_interval() -> void:
	var schedule := SaveSchedule.new(0.0, 3.0, 0.0)
	assert_false(schedule.periodic_due(1.0e9))


func test_forget_drops_a_mark() -> void:
	var schedule := SaveSchedule.new(60.0, 1.0, 0.0)
	schedule.mark_changed(8, 0.0)
	schedule.forget(8)
	assert_false(schedule.is_changed(8))
	assert_eq(schedule.changes_due(10.0), [] as Array[int])


func test_fingerprint_matches_after_a_json_round_trip() -> void:
	var save := CharacterSave.new()
	save.build = {"class": "fighter", "weapons": ["sword", "axes"]}
	save.inventory = {"items": [{"item": "sword", "uid": 1, "gs": 120, "primary": 120.0,
			"affixes": {"sear": 3.137}}], "next_uid": 2}
	save.equipment = {"head": {"item": "cap", "uid": 0, "primary": 17.5}}
	save.tradeskills = {"mining": [2, 150]}
	var loaded := CharacterSave.new()
	loaded.build = Persistence.decode(Persistence.encode(save.build))
	loaded.inventory = Persistence.decode(Persistence.encode(save.inventory))
	loaded.equipment = Persistence.decode(Persistence.encode(save.equipment))
	loaded.tradeskills = Persistence.decode(Persistence.encode(save.tradeskills))
	assert_eq(loaded.fingerprint(), save.fingerprint(), "120.0 and 120 count as the same")
	loaded.tradeskills["mining"] = [2, 151]
	assert_true(loaded.fingerprint() != save.fingerprint(), "any change shows")


func test_summary_text_counts_bag_gear_and_skills() -> void:
	var save := CharacterSave.new()
	save.inventory = {"items": [{}, {}, {}]}
	save.equipment = {"head": {}}
	save.tradeskills = {"mining": [2, 150], "smelting": [1, 30]}
	assert_eq(save.summary_text(), "bag=3 equipped=1 skill_levels=3 skill_xp=180")
