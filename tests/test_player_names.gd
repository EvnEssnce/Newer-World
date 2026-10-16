extends TestCase
## PlayerNames: the peer id → character name table behind nameplates and
## party frames, and its "Player N" fallback.

var names: PlayerNames


func before_each() -> void:
	names = PlayerNames.new()


func test_unknown_peer_falls_back_to_player_number() -> void:
	assert_eq(names.name_of(123456), "Player 3456")
	assert_eq(PlayerNames.fallback(7), "Player 7")
	assert_false(names.has(7))


func test_put_names_a_peer_and_reports_changes() -> void:
	assert_true(names.put(5, "Aldric"))
	assert_eq(names.name_of(5), "Aldric")
	assert_false(names.put(5, "Aldric"), "same name again is no change")
	assert_true(names.put(5, "Brenna"))
	assert_eq(names.name_of(5), "Brenna")


func test_put_ignores_empty_names_and_server_ids() -> void:
	assert_false(names.put(5, ""))
	assert_false(names.put(0, "Server"))
	assert_false(names.put(-2, "Husk"))
	assert_eq(names.name_of(5), "Player 5")


func test_forget_goes_back_to_the_fallback() -> void:
	names.put(5, "Aldric")
	assert_true(names.forget(5))
	assert_false(names.forget(5))
	assert_eq(names.name_of(5), "Player 5")


func test_to_dict_and_put_all_round_trip() -> void:
	names.put(5, "Aldric")
	names.put(9, "Brenna")
	var other := PlayerNames.new()
	other.put(9, "Brenna")
	var changed := other.put_all(names.to_dict())
	assert_eq(changed, [5] as Array[int], "only the new name changed")
	assert_eq(other.name_of(5), "Aldric")
	assert_eq(other.name_of(9), "Brenna")
	assert_eq(other.peers().size(), 2)


func test_put_all_skips_entries_of_the_wrong_type() -> void:
	var changed := names.put_all({"5": "Aldric", 6: 42, 7: "Cora"})
	assert_eq(changed, [7] as Array[int])
	assert_false(names.has(6))
