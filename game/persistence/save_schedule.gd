class_name SaveSchedule
extends RefCounted
## When the server saves characters (World/Saves, SaveService). Pure timing
## rules, unit tested (tests/test_save_schedule.gd); times are seconds on any
## clock that only goes forward.
##
## - A change to something a save holds (build, bag, gear, tradeskills) marks
##   the character changed; it's saved `after_change` s after its FIRST unsaved
##   change, so a burst of changes (a batch of pickups, a respec) is one write,
##   and nothing waits longer than that. 0 = on the next check.
## - Every `interval` s everyone online is saved together (one transaction),
##   changed or not, which also clears every mark. 0 or less = never.
## - Leaving and shutting down save at once (the caller does it, then forget()).

## Seconds between saves of everyone online (<= 0: off).
var interval := 60.0
## Seconds from a character's first unsaved change to its save.
var after_change := 3.0

var _next_periodic := 0.0
## Character key (the peer id) -> when its first unsaved change happened.
var _changed_since: Dictionary[int, float] = {}


func _init(interval_s: float = 60.0, after_change_s: float = 3.0, now: float = 0.0) -> void:
	interval = interval_s
	after_change = maxf(0.0, after_change_s)
	_next_periodic = now + interval


## Something `peer`'s save holds changed at `now`. A later change before the
## save doesn't push it back.
func mark_changed(peer: int, now: float) -> void:
	if not _changed_since.has(peer):
		_changed_since[peer] = now


func is_changed(peer: int) -> bool:
	return _changed_since.has(peer)


## Whether the periodic save of everyone is due.
func periodic_due(now: float) -> bool:
	return interval > 0.0 and now >= _next_periodic


## The changed characters whose save is due at `now`, lowest id first.
func changes_due(now: float) -> Array[int]:
	var due: Array[int] = []
	for peer: int in _changed_since:
		if now - _changed_since[peer] >= after_change:
			due.append(peer)
	due.sort()
	return due


## These characters were saved: their marks are cleared.
func saved(peers: Array[int]) -> void:
	for peer in peers:
		_changed_since.erase(peer)


## Everyone online was saved at `now` (the periodic save): every mark is
## cleared and the next periodic save is `interval` from now (a late one
## doesn't make the next one early).
func saved_everyone(now: float) -> void:
	_changed_since.clear()
	_next_periodic = now + interval


## `peer` left (saved by the caller): no mark kept for it.
func forget(peer: int) -> void:
	_changed_since.erase(peer)
