class_name DamageMeter
extends RefCounted
## Damage dealt in one fight and its damage per second (the training dummy's
## readout). A fight starts with the first hit and ends after idle_time seconds
## without one; the next hit starts a new fight. While a fight runs, its length
## is measured up to now (a pause between hits lowers the DPS); once it ends,
## it's frozen at the last hit. Pure logic, unit tested (tests/test_damage_meter.gd).
## Times are in seconds, from any clock that only goes forward.

## A DPS over a shorter fight would be divided by this instead (one hit isn't
## "infinite DPS").
const MIN_DURATION := 1.0

## Seconds without a hit before the fight ends.
var idle_time := 0.0
var total := 0.0
var hits := 0
var _first_time := -1.0
var _last_time := -1.0


func _init(idle_seconds: float = 0.0) -> void:
	idle_time = idle_seconds


## A hit for `damage` at `now`. Starts a new fight if the last one ended.
func add(damage: float, now: float) -> void:
	if not is_active(now):
		total = 0.0
		hits = 0
		_first_time = now
	total += damage
	hits += 1
	_last_time = now


## Whether a fight is running (a hit within the last idle_time seconds).
func is_active(now: float) -> bool:
	return hits > 0 and now - _last_time <= idle_time


## Whether there's anything to show (a fight running or the last one's result).
func has_fight() -> bool:
	return hits > 0


## Seconds from the first hit to now (fight running) or to the last hit (ended).
func duration(now: float) -> float:
	if hits == 0:
		return 0.0
	return (now if is_active(now) else _last_time) - _first_time


func dps(now: float) -> float:
	if hits == 0:
		return 0.0
	return total / maxf(duration(now), MIN_DURATION)
