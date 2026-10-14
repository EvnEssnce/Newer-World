extends TestCase
## AimHold: hold an aimed-zone ability's key to aim, release to cast.

const Q := PlayerState.BUTTON_ABILITY_1
const E := PlayerState.BUTTON_ABILITY_2
const Z := PlayerState.BUTTON_WING_1

var hold: AimHold


func before_each() -> void:
	hold = AimHold.new()


func test_other_abilities_cast_on_press() -> void:
	assert_eq(hold.step(E, 0, Q, false), E, "E isn't aimed: sent at once")
	assert_false(hold.is_holding())
	assert_eq(hold.step(0, E, Q, false), 0, "its release sends nothing")


func test_aimed_ability_casts_on_release() -> void:
	assert_eq(hold.step(Q, 0, Q, false), 0, "pressed: nothing sent yet")
	assert_true(hold.is_holding(), "aiming")
	assert_eq(hold.held_bit, Q)
	assert_eq(hold.step(0, 0, Q, false), 0, "held: still aiming")
	assert_eq(hold.step(0, Q, Q, false), Q, "released: the press goes out")
	assert_false(hold.is_holding())


func test_cancel_drops_the_hold() -> void:
	hold.step(Z, 0, Z, false)
	assert_eq(hold.step(0, 0, Z, true), 0, "right click: nothing sent")
	assert_false(hold.is_holding())
	assert_eq(hold.step(0, Z, Z, false), 0, "the later release casts nothing")


func test_tap_within_one_tick_still_casts() -> void:
	assert_eq(hold.step(Q, Q, Q, false), Q, "pressed and released the same tick")
	assert_false(hold.is_holding())


func test_a_new_aimed_press_replaces_the_hold() -> void:
	hold.step(Q, 0, Q | Z, false)
	assert_eq(hold.step(Z, 0, Q | Z, false), 0, "now aiming Z")
	assert_eq(hold.held_bit, Z)
	assert_eq(hold.step(0, Q, Q | Z, false), 0, "Q's release: dropped")
	assert_eq(hold.step(0, Z, Q | Z, false), Z, "Z's release casts Z")


func test_other_keys_while_aiming_keep_the_hold() -> void:
	hold.step(Q, 0, Q, false)
	assert_eq(hold.step(E, 0, Q, false), E, "E goes out at once")
	assert_true(hold.is_holding(), "still aiming Q")
	assert_eq(hold.step(0, Q, Q, false), Q)
