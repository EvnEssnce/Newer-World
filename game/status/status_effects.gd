class_name StatusEffects
extends RefCounted
## The statuses one player or enemy has right now: which ones, stacks, ticks
## left. Pure logic (tests/test_status_effects.gd); every query takes the
## StatusDefs the indices refer to.
##
## Rules:
## - apply() adds stacks up to the status's max_stacks and resets the time left
##   to the full duration (or the longer of the two, so it never shortens).
## - tick() counts every status down by one tick, removes the expired ones and
##   returns the damage over time (bleed) due this tick.
## - Effects combine: walking speed uses the strongest slow; damage_taken and
##   damage_dealt add up over all statuses (per stack) and then multiply.
##
## Players keep one in PlayerState (synced, ticked in PlayerState.step);
## enemies keep one on the server.

## One status on its owner.
class Entry:
	extends RefCounted
	## Index into StatusDefs.
	var status := 0
	var stacks := 1
	var ticks_left := 0
	## Ticks since it was first applied (damage over time ticks on multiples of
	## the interval; a refresh doesn't restart it).
	var elapsed := 0
	## Server only, not synced: who applied it (peer id, enemy id, 0 = unknown),
	## for damage-over-time hit events.
	var source := 0

	func duplicate_entry() -> Entry:
		var e := Entry.new()
		e.status = status
		e.stacks = stacks
		e.ticks_left = ticks_left
		e.elapsed = elapsed
		e.source = source
		return e


## Values per entry in to_packed().
const PACKED_FIELDS := 4

var entries: Array[Entry] = []
## Set by tick(): the source of the last status that dealt damage this tick.
var last_damage_source := 0


## Adds `stacks` of a status (capped at max_stacks) and resets its time to
## duration_ticks (-1 = the status's own duration). Returns false if the index
## isn't a status.
func apply(defs: StatusDefs, index: int, stacks: int = 1, duration_ticks: int = -1,
		source: int = 0) -> bool:
	var def := defs.get_def(index)
	if def == null or stacks <= 0:
		return false
	var duration := duration_ticks if duration_ticks > 0 else def.duration_ticks
	var e := find(index)
	if e == null:
		e = Entry.new()
		e.status = index
		e.stacks = 0
		entries.append(e)
	e.stacks = mini(def.max_stacks, e.stacks + stacks)
	e.ticks_left = maxi(e.ticks_left, duration)
	e.source = source
	return true


## Advances one tick. Returns the damage over time due this tick (before the
## owner's damage_taken multiplier); last_damage_source says who caused it.
func tick(defs: StatusDefs) -> float:
	var damage := 0.0
	for e in entries:
		e.elapsed += 1
		e.ticks_left -= 1
		var def := defs.get_def(e.status)
		if def and def.deals_damage_over_time() and e.elapsed % def.tick_interval_ticks == 0:
			damage += def.damage_per_interval * e.stacks
			last_damage_source = e.source
	_remove_where(func(e: Entry) -> bool: return e.ticks_left <= 0)
	return damage


func find(index: int) -> Entry:
	for e in entries:
		if e.status == index:
			return e
	return null


func has(index: int) -> bool:
	return find(index) != null


func stacks(index: int) -> int:
	var e := find(index)
	return e.stacks if e else 0


func ticks_left(index: int) -> int:
	var e := find(index)
	return e.ticks_left if e else 0


func is_empty() -> bool:
	return entries.is_empty()


# --- Effects ---

## Walking speed multiplier: the strongest slow (1.0 = none).
func move_multiplier(defs: StatusDefs) -> float:
	var result := 1.0
	for e in entries:
		var def := defs.get_def(e.status)
		if def:
			result = minf(result, def.move_multiplier)
	return result


## False while rooted (or anything else that stops movement).
func can_move(defs: StatusDefs) -> bool:
	return not _any(defs, func(def: StatusDef) -> bool: return def.stops_movement)


## False while stunned. (Players and enemies also stagger for a stun's whole
## duration, so their own stagger checks cover it too.)
func can_act(defs: StatusDefs) -> bool:
	return not _any(defs, func(def: StatusDef) -> bool: return def.stuns)


## Multiplier on damage the owner takes: 1 + the sum of damage_taken x stacks.
func damage_taken_multiplier(defs: StatusDefs) -> float:
	var bonus := 0.0
	for e in entries:
		var def := defs.get_def(e.status)
		if def:
			bonus += def.damage_taken * e.stacks
	return maxf(0.0, 1.0 + bonus)


## Multiplier on damage the owner deals: 1 + the sum of damage_dealt x stacks.
func damage_dealt_multiplier(defs: StatusDefs) -> float:
	var bonus := 0.0
	for e in entries:
		var def := defs.get_def(e.status)
		if def:
			bonus += def.damage_dealt * e.stacks
	return maxf(0.0, 1.0 + bonus)


## The owner landed a damaging hit: returns the statuses it applies to the
## target ([status index, stacks] each, e.g. Bloodlust's bleed) and uses up a
## stack of every status that's consumed on hit.
func take_on_hit_statuses(defs: StatusDefs) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for e in entries:
		var def := defs.get_def(e.status)
		if def == null or def.on_hit_status.is_empty():
			continue
		var index := defs.index_of(def.on_hit_status)
		if index < 0:
			continue
		result.append(Vector2i(index, def.on_hit_stacks))
		if def.consume_on_hit:
			e.stacks -= 1
	_remove_where(func(e: Entry) -> bool: return e.stacks <= 0)
	return result


# --- Removal ---

## Removes one status. Returns true if it was there.
func remove(index: int) -> bool:
	var before := entries.size()
	_remove_where(func(e: Entry) -> bool: return e.status == index)
	return entries.size() != before


## A cleanse: removes every debuff. Returns how many were removed.
func remove_debuffs(defs: StatusDefs) -> int:
	var before := entries.size()
	_remove_where(func(e: Entry) -> bool:
		var def := defs.get_def(e.status)
		return def == null or def.is_debuff())
	return before - entries.size()


func clear() -> void:
	entries.clear()


# --- Display ---

## "Bleed x3, Slow": names (with stacks above 1) for labels over heads.
func summary(defs: StatusDefs) -> String:
	var parts := PackedStringArray()
	for e in entries:
		var def := defs.get_def(e.status)
		if def:
			parts.append(def.display_name if e.stacks <= 1 else "%s x%d" % [def.display_name, e.stacks])
	return ", ".join(parts)


# --- Network ---

## [status, stacks, ticks_left, elapsed] per entry. Sources aren't included
## (server only).
func to_packed() -> PackedInt32Array:
	var data := PackedInt32Array()
	for e in entries:
		data.append_array([e.status, e.stacks, e.ticks_left, e.elapsed])
	return data


static func from_packed(data: PackedInt32Array) -> StatusEffects:
	var s := StatusEffects.new()
	for i in range(0, data.size() - PACKED_FIELDS + 1, PACKED_FIELDS):
		var e := Entry.new()
		e.status = data[i]
		e.stacks = data[i + 1]
		e.ticks_left = data[i + 2]
		e.elapsed = data[i + 3]
		s.entries.append(e)
	return s


func copy() -> StatusEffects:
	var s := StatusEffects.new()
	for e in entries:
		s.entries.append(e.duplicate_entry())
	s.last_damage_source = last_damage_source
	return s


func _any(defs: StatusDefs, test: Callable) -> bool:
	for e in entries:
		var def := defs.get_def(e.status)
		if def and test.call(def):
			return true
	return false


func _remove_where(test: Callable) -> void:
	for i in range(entries.size() - 1, -1, -1):
		if test.call(entries[i]):
			entries.remove_at(i)
