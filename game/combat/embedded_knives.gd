class_name EmbeddedKnives
extends RefCounted
## Knives stuck in targets (Throwing Knives' light and heavy throws that hit,
## AttackParams.embeds), waiting for Recall. Server only, pure logic
## (tests/test_embedded_knives.gd); ProjectileSystem owns one and mirrors each
## target's count into its embedded_knife status (what players see).
##
## Rules: each knife remembers its thrower, its target (a peer id or an enemy id,
## never 0) and the server tick it falls out. A thrower has at most `max_per_thrower`
## across all targets: a new one past that pushes out its oldest. take() rips
## out all of a thrower's knives (Recall); drop_target() removes every knife in
## a target (it died, was cleansed or left). A thrower who leaves keeps its
## knives in targets until they fall out. ProjectileSystem builds one per
## status from that status's max_stacks (the cap) and duration.

## Most knives one thrower can have embedded at once, across targets.
var max_per_thrower := 8
## Ticks a knife stays in its target.
var duration_ticks := 600
## Thrower id -> Array of [target id, tick it falls out], oldest first.
var _by_thrower: Dictionary[int, Array] = {}


func _init(max_knives := 8, ticks := 600) -> void:
	max_per_thrower = max_knives
	duration_ticks = ticks


## Embeds one of thrower's knives in target at server tick `now`. Returns the
## target id of a knife pushed out to stay within the cap (it may be target
## itself), or 0.
func add(thrower: int, target: int, now: int) -> int:
	var knives: Array = _by_thrower.get(thrower, [])
	knives.append([target, now + duration_ticks])
	_by_thrower[thrower] = knives
	if knives.size() > max_per_thrower:
		return knives.pop_front()[0]
	return 0


## Removes the knives that fell out by server tick `now`. Returns the targets
## that lost one (each once).
func expire(now: int) -> Array[int]:
	var changed: Array[int] = []
	for thrower in _by_thrower.keys():
		var kept := []
		for knife: Array in _by_thrower[thrower]:
			if knife[1] > now:
				kept.append(knife)
			elif not knife[0] in changed:
				changed.append(knife[0])
		_set_knives(thrower, kept)
	return changed


## Rips out all of thrower's knives (Recall): target id -> how many were in it.
func take(thrower: int) -> Dictionary[int, int]:
	var result: Dictionary[int, int] = {}
	for knife: Array in _by_thrower.get(thrower, []):
		result[knife[0]] = result.get(knife[0], 0) + 1
	_by_thrower.erase(thrower)
	return result


## Removes every knife in target (any thrower). Returns how many there were.
func drop_target(target: int) -> int:
	var dropped := 0
	for thrower in _by_thrower.keys():
		var kept := []
		for knife: Array in _by_thrower[thrower]:
			if knife[0] == target:
				dropped += 1
			else:
				kept.append(knife)
		_set_knives(thrower, kept)
	return dropped


## Knives in target, from every thrower.
func count_in(target: int) -> int:
	var count := 0
	for knives: Array in _by_thrower.values():
		for knife: Array in knives:
			if knife[0] == target:
				count += 1
	return count


## Knives thrower has embedded, across targets.
func count_of(thrower: int) -> int:
	return _by_thrower.get(thrower, []).size()


## The last tick a knife in target falls out (0 if none).
func last_expiry(target: int) -> int:
	var last := 0
	for knives: Array in _by_thrower.values():
		for knife: Array in knives:
			if knife[0] == target:
				last = maxi(last, knife[1])
	return last


## Every target with a knife in it.
func targets() -> Array[int]:
	var result: Array[int] = []
	for knives: Array in _by_thrower.values():
		for knife: Array in knives:
			if not knife[0] in result:
				result.append(knife[0])
	return result


func _set_knives(thrower: int, knives: Array) -> void:
	if knives.is_empty():
		_by_thrower.erase(thrower)
	else:
		_by_thrower[thrower] = knives
