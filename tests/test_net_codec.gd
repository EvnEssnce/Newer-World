extends TestCase
## NetCodec (snapshot encoding): every supported value comes back equal and with
## the same type, small values stay small, and PlayerState survives the trip
## exactly (reconciliation compares it). Also PlayerState.view_array, what other
## players get.


## Deep equality that also checks types (1 == 1.0 and [1] == [1.0] in GDScript).
func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if a is float and is_nan(a):
		return is_nan(b)
	return a == b


func _round_trip(value: Variant) -> Variant:
	return NetCodec.decode(NetCodec.encode(value))


func _assert_round_trip(value: Variant) -> void:
	var back: Variant = _round_trip(value)
	assert_true(_same(back, value), "%s (%s) came back as %s (%s)" % [
			value, type_string(typeof(value)), back, type_string(typeof(back))])


func test_scalars_round_trip() -> void:
	for value: Variant in [null, true, false, 0, 1, -1, 63, -64, 64, -65, 300, -300, 70000,
			-2147483648, 2147483647, 1 << 40, -(1 << 40), NetCodec.MAX_INT, -NetCodec.MAX_INT]:
		_assert_round_trip(value)


func test_floats_round_trip_exactly() -> void:
	for value: float in [0.0, 1.0, -1.0, 100.0, 150.0, 0.5, -0.25, 1.0 / 3.0, 87.33333333,
			0.1, 1e300, -1e-300, 123456789.125, 9007199254740992.0, INF, -INF]:
		_assert_round_trip(value)
	_assert_round_trip(NAN)


func test_negative_zero_keeps_its_sign() -> void:
	var back: float = _round_trip(-0.0)
	assert_eq(1.0 / back, -INF)
	var v2: Vector2 = _round_trip(Vector2(-0.0, 0.0))
	assert_eq(1.0 / v2.x, -INF)
	var v3: Vector3 = _round_trip(Vector3(0.0, -0.0, 0.0))
	assert_eq(1.0 / v3.y, -INF)


func test_strings_and_vectors_round_trip() -> void:
	for value: Variant in ["", "husk", "Ünïcödé ✓", Vector2.ZERO, Vector2(1.5, -2.25),
			Vector3.ZERO, Vector3(10.123, -0.5, 1e-7)]:
		_assert_round_trip(value)


func test_arrays_round_trip() -> void:
	for value: Variant in [[], [1, 2.0, "x", [true, [null]]], PackedInt32Array(),
			PackedInt32Array([5]), PackedInt32Array([0, 0, 0, 0]), PackedInt32Array([-1, -1]),
			PackedInt32Array([0, -5, 1000, -2147483648, 2147483647]),
			PackedStringArray(), PackedStringArray(["broadsword", "", "spear"])]:
		_assert_round_trip(value)


func test_small_values_are_small() -> void:
	assert_eq(NetCodec.encode(0).size(), 1)
	assert_eq(NetCodec.encode(-1).size(), 1)
	assert_eq(NetCodec.encode(true).size(), 1)
	assert_eq(NetCodec.encode(100.0).size(), 3)  # tag + 2-byte varint
	assert_eq(NetCodec.encode(0.5).size(), 5)  # exact as 32 bits
	assert_eq(NetCodec.encode(Vector3.ZERO).size(), 1)
	assert_eq(NetCodec.encode(Vector3(1, 2, 3)).size(), 13)
	# All the same: tag, count, value, whatever the count.
	var cooldowns := PackedInt32Array()
	cooldowns.resize(16)
	assert_eq(NetCodec.encode(cooldowns).size(), 3)


func test_header_then_encoded_entries_decode_as_one_array() -> void:
	var buffer := StreamPeerBuffer.new()
	NetCodec.write_array_header(buffer, 2)
	buffer.put_data(NetCodec.encode([1, "a"]))
	buffer.put_data(NetCodec.encode(2.5))
	assert_true(_same(NetCodec.decode(buffer.data_array), [[1, "a"], 2.5]))


func test_malformed_data_decodes_as_null() -> void:
	var bytes := NetCodec.encode([1, 2, 3])
	bytes.resize(bytes.size() - 1)
	assert_eq(NetCodec.decode(bytes), null, "truncated")
	assert_eq(NetCodec.decode(PackedByteArray([0x7F])), null, "unknown tag")
	var extra := NetCodec.encode(1)
	extra.append(0)
	assert_eq(NetCodec.decode(extra), null, "bytes left over")


## A state in the middle of things, with fractional floats and non-default
## arrays everywhere, survives the trip exactly.
func _busy_state() -> PlayerState:
	var s := PlayerState.new()
	s.stamina = 87.33333333
	s.stamina_regen_wait = 12
	s.dodge_tick = 4
	s.dodge_dir = Vector2(0.6, -0.8)
	s.yaw = -2.123456789
	s.attack_type = PlayerState.ATTACK_ABILITY
	s.attack_tick = 130
	s.attack_hold = PlayerState.HOLD_SPENT
	s.attack_speed_carry = 0.25
	s.attack_serial = 4000
	s.server_events = 77
	s.blocking = true
	s.on_floor = true
	s.weapons = PackedStringArray(["broadsword", "spear"])
	s.equipped = 1
	s.ability_slots = PackedInt32Array([0, 1, 2, 3, -1, 5])
	s.cooldowns[3] = 600
	s.ability = 2
	s.ability_dir = Vector2(0.3, 0.4)
	s.force.velocity = Vector2(-7.5, 1.0 / 3.0)
	s.force.ticks = 9
	s.force.launch = 4.2
	s.ember = 63.7
	s.wing_set = "fighter"
	s.wing_slots = PackedInt32Array([0, 3])
	s.wing_cooldowns[1] = 900
	s.combat_ticks = 300
	s.rebirth_cooldown = 18000
	s.equip_left = 45
	s.free_move_mask = 2
	s.charge_mask = 3
	s.spare_charges = 1
	return s


func test_player_state_survives_exactly() -> void:
	var s := _busy_state()
	var data := s.to_array()
	var back: Array = _round_trip(data)
	assert_true(_same(back, data))
	assert_true(PlayerState.from_array(back).matches(s))


func test_encoded_state_is_much_smaller_than_godots() -> void:
	var data := _busy_state().to_array()
	var ours := NetCodec.encode(data).size()
	var godots := var_to_bytes(data).size()
	assert_true(ours * 2 < godots, "%d bytes vs Godot's %d" % [ours, godots])


func test_view_keeps_what_drawing_needs() -> void:
	var s := _busy_state()
	s.dead = true
	s.rebirth_left = 40
	s.stagger_ticks = 5
	s.swap_tick = 3
	var view := PlayerState.from_array(_round_trip(s.view_array()))
	assert_eq(view.yaw, s.yaw)
	assert_eq(view.dodge_tick, s.dodge_tick)
	assert_eq(view.dodge_dir, s.dodge_dir)
	assert_eq(view.attack_type, s.attack_type)
	assert_eq(view.attack_tick, s.attack_tick)
	assert_eq(view.attack_serial, s.attack_serial)
	assert_eq(view.ability, s.ability)
	assert_eq(view.ability_dir, s.ability_dir)
	assert_eq(view.blocking, s.blocking)
	assert_eq(view.weapons, s.weapons)
	assert_eq(view.equipped, s.equipped)
	assert_eq(view.wing_set, s.wing_set)
	assert_eq(view.dead, true)
	assert_eq(view.rebirth_left, 40)
	assert_eq(view.stagger_ticks, 5)
	assert_eq(view.swap_tick, 3)
	assert_eq(view.force.ticks, s.force.ticks)
	assert_true(view.is_forced())


func test_view_hides_the_owners_numbers() -> void:
	var view := PlayerState.from_array(_busy_state().view_array())
	assert_eq(view.stamina, 0.0)
	assert_eq(view.ember, 0.0)
	assert_eq(view.server_events, 0)
	assert_eq(view.cooldowns.count(0), view.cooldowns.size())
	assert_eq(view.ability_slots.count(-1), view.ability_slots.size())
	assert_eq(view.wing_slots.count(-1), view.wing_slots.size())
	assert_eq(view.wing_cooldowns.count(0), view.wing_cooldowns.size())
	assert_eq(view.rebirth_cooldown, 0)
	assert_eq(view.combat_ticks, 0)
	assert_eq(view.force.velocity, Vector2.ZERO)
	assert_eq(view.equip_left, 0)
	assert_eq(view.free_move_mask, 0)
	assert_eq(view.charge_mask, 0)
	assert_eq(view.spare_charges, 0)
	# Arrays keep their sizes, so code indexing them still works.
	assert_eq(view.cooldowns.size(), PlayerState.WEAPON_SLOTS * WeaponParams.MAX_ABILITIES)


func test_view_is_smaller_than_the_full_state() -> void:
	var s := _busy_state()
	var full := NetCodec.encode(s.to_array()).size()
	var view := NetCodec.encode(s.view_array()).size()
	assert_true(view < full, "view %d bytes, full %d" % [view, full])
