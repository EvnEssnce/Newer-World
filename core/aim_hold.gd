class_name AimHold
extends RefCounted
## Hold to aim (client input only): the key of an ability whose zone lands at
## the crosshair (ZoneSystem.is_aimed: Meteor Fall, Arrow Rain, Binding Embers...)
## doesn't cast on press. While it's held the landing marker follows the
## crosshair (ZoneSystem._update_marker, World.held_aimed_attack), and the
## press bit goes out on the tick the key is released. A cancel (right click,
## or the mouse freed: Esc, a panel) drops the hold without casting. Every
## other key still sends its bit on the press. The sim and the server never
## know: they get one press, like any ability. Bots send presses directly.
## Pure logic, unit tested (tests/test_aim_hold.gd).

## The PlayerState.BUTTON_* bit of the key being held to aim; 0 = none.
var held_bit := 0


## One tick. `pressed` / `released`: ability and Wing bits whose keys were
## just pressed / released; `aimed`: bits whose slot holds an aimed-zone
## ability; `cancel`: drop the hold. Returns the bits to send this tick.
## A new aimed press replaces a hold already going (that one is dropped).
func step(pressed: int, released: int, aimed: int, cancel: bool) -> int:
	if cancel:
		held_bit = 0
	var send := pressed & ~aimed
	var hold := pressed & aimed
	if hold != 0:
		held_bit = hold & -hold  # the lowest one, if several at once
	if held_bit != 0 and (released & held_bit) != 0:
		send |= held_bit
		held_bit = 0
	return send


func is_holding() -> bool:
	return held_bit != 0
