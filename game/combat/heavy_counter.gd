class_name HeavyCounter
extends RefCounted
## Counts a player's heavy attacks for the War Hammer's Earthshaker capstone
## ("every 3rd heavy attack sends out a shockwave"). Server only, never sim
## state. Each heavy is counted once, by its PlayerState.attack_serial, however
## many ticks its hitbox is live. Pure logic, unit tested
## (tests/test_juggernaut.gd).

## Heavies counted so far.
var count := 0
## attack_serial of the last heavy counted (-1 = none yet).
var last_serial := -1


## A heavy attack (serial) is live. Returns true if it's a new one and the
## every-th one (3rd, 6th, ...). every <= 0 never triggers.
func register(serial: int, every: int) -> bool:
	if serial == last_serial:
		return false
	last_serial = serial
	count += 1
	return every > 0 and count % every == 0


func reset() -> void:
	count = 0
	last_serial = -1
