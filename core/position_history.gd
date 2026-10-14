class_name PositionHistory
extends RefCounted
## Where one body (a player or an enemy) stood at each recent server tick, for
## lag compensation: an attacker's client draws everyone else in the past (the
## interpolation delay plus the trip to it), so the server tests its melee and
## beam hits against where the targets were on the tick that client was drawing
## (World._lag_position). Pure logic, unit tested.
##
## A jump of more than break_distance between two ticks (a respawn, a Blink, a
## Shadow Swap) is a break: lookups never reach back past it, so nobody is hit
## where they stood before a teleport.

## Ticks kept (older ones are dropped).
var capacity := 30
## Meters between two ticks that count as a teleport, not movement.
var break_distance := 1.5

var _ticks := PackedInt32Array()
var _positions := PackedVector3Array()


func _init(keep_ticks: int = 30, teleport_distance: float = 1.5) -> void:
	capacity = maxi(1, keep_ticks)
	break_distance = teleport_distance


## The body's position at the end of server tick `tick` (ticks only go up).
func record(tick: int, position: Vector3) -> void:
	if not _ticks.is_empty() and tick <= _ticks[-1]:
		return
	_ticks.append(tick)
	_positions.append(position)
	while _ticks.size() > capacity:
		_ticks.remove_at(0)
		_positions.remove_at(0)


## Where the body stood at the end of `tick`; `current` is where it is now (later
## than anything recorded). Newer than the newest record → current; between two
## records → the older one; older than the oldest → the oldest; never across a
## break (then the position just after the break).
func at(tick: int, current: Vector3) -> Vector3:
	if _ticks.is_empty() or tick > _ticks[-1]:
		return current
	var newer := current
	for i in range(_ticks.size() - 1, -1, -1):
		if _positions[i].distance_to(newer) > break_distance:
			return newer
		if _ticks[i] <= tick:
			return _positions[i]
		newer = _positions[i]
	return newer


func size() -> int:
	return _ticks.size()
