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
## Fastest attack speed any statuses give (PlayerState skips at most one tick
## per tick).
const MAX_ATTACK_SPEED := 2.0
## A blind fades out over this last fraction of its duration.
const BLIND_FADE := 0.3

var entries: Array[Entry] = []
## Set by tick(): the source of the last status that dealt damage this tick.
var last_damage_source := 0
## Set by tick(): healing over time (Pyre Heart) due this tick, and the source
## of the last status that healed.
var heal_due := 0.0
var last_heal_source := 0


## Adds `stacks` of a status (capped at max_stacks) and resets its time to
## duration_ticks (-1 = the status's own duration). Returns false if the index
## isn't a status or the owner is immune to it (refuses).
func apply(defs: StatusDefs, index: int, stacks: int = 1, duration_ticks: int = -1,
		source: int = 0) -> bool:
	var def := defs.get_def(index)
	if def == null or stacks <= 0 or refuses(defs, index):
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
## Healing over time due this tick goes in heal_due (last_heal_source).
func tick(defs: StatusDefs) -> float:
	var damage := 0.0
	heal_due = 0.0
	for e in entries:
		e.elapsed += 1
		e.ticks_left -= 1
		var def := defs.get_def(e.status)
		if def == null or def.tick_interval_ticks <= 0 or e.elapsed % def.tick_interval_ticks != 0:
			continue
		if def.deals_damage_over_time():
			damage += def.damage_per_interval * e.stacks
			last_damage_source = e.source
		if def.heals_over_time():
			heal_due += def.heal_per_interval * e.stacks
			last_heal_source = e.source
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


## Immune to knockback, pull and launch (Braced, Steadfast, Unbowed).
func force_immune(defs: StatusDefs) -> bool:
	return _any(defs, func(def: StatusDef) -> bool: return def.force_immune)


## Immune to stagger: hits, guard breaks and stuns (Steadfast, Unbowed).
func stagger_immune(defs: StatusDefs) -> bool:
	return _any(defs, func(def: StatusDef) -> bool: return def.stagger_immune)


## Immune to crowd-control debuffs: slow, root, stun, taunt (Unbowed).
func cc_immune(defs: StatusDefs) -> bool:
	return _any(defs, func(def: StatusDef) -> bool: return def.cc_immune)


## True if the owner's statuses refuse this status being applied: a stun while
## stagger or CC immune, any crowd-control debuff while CC immune.
func refuses(defs: StatusDefs, index: int) -> bool:
	var def := defs.get_def(index)
	if def == null:
		return false
	if def.stuns and stagger_immune(defs):
		return true
	return def.is_crowd_control() and cc_immune(defs)


## The source (peer id) of a taunt (forces_target) on the owner, 0 = none.
func forced_target(defs: StatusDefs) -> int:
	for e in entries:
		var def := defs.get_def(e.status)
		if def and def.forces_target and e.source > 0:
			return e.source
	return 0


## Multiplier on damage the owner takes: 1 + the sum of damage_taken x stacks.
func damage_taken_multiplier(defs: StatusDefs) -> float:
	var bonus := 0.0
	for e in entries:
		var def := defs.get_def(e.status)
		if def:
			bonus += def.damage_taken * e.stacks
	return maxf(0.0, 1.0 + bonus)


## Who applied a status (Entry.source, server only), 0 if it isn't there.
func source_of(index: int) -> int:
	var e := find(index)
	return e.source if e else 0


## Brace: ticks an attacker whose melee hit just landed on the owner is
## staggered (the longest charge_stagger among its statuses), if the hit counts
## as a charge for that status: the attacker was dashing, or the status started
## less than its charge_window ago. 0 = no stagger.
func charge_stagger_ticks(defs: StatusDefs, attacker_dashing: bool) -> int:
	var result := 0
	for e in entries:
		var def := defs.get_def(e.status)
		if (def and def.charge_stagger_ticks > 0
				and (attacker_dashing or e.elapsed < def.charge_window_ticks)):
			result = maxi(result, def.charge_stagger_ticks)
	return result


## Iron Hide: the largest crowd_radius among the owner's statuses (meters), 0
## without one (then nothing needs counting).
func crowd_radius(defs: StatusDefs) -> float:
	var result := 0.0
	for e in entries:
		var def := defs.get_def(e.status)
		if def and def.crowd_damage_taken != 0.0:
			result = maxf(result, def.crowd_radius)
	return result


## Iron Hide: multiplier on damage the owner takes with `nearby` hostiles
## around it: 1 + the sum of crowd_damage_taken x stacks x min(nearby,
## crowd_max) over its statuses (each counting only hostiles within its own
## radius is left to the caller: one radius, crowd_radius()). At least 0.
func crowd_damage_taken_multiplier(defs: StatusDefs, nearby: int) -> float:
	var bonus := 0.0
	for e in entries:
		var def := defs.get_def(e.status)
		if def and def.crowd_damage_taken != 0.0:
			bonus += def.crowd_damage_taken * e.stacks * mini(maxi(nearby, 0), def.crowd_max)
	return maxf(0.0, 1.0 + bonus)


## Multiplier on damage the owner deals: 1 + the sum of damage_dealt x stacks.
## How many times faster light and heavy attacks play (Rampage): the fastest
## status whose stamina condition holds (stamina_fraction = stamina / max),
## each stack adding its attack_speed - 1 (Talon Storm), at most
## MAX_ATTACK_SPEED. 1 = normal.
func attack_speed(defs: StatusDefs, stamina_fraction: float) -> float:
	var result := 1.0
	for e in entries:
		var def := defs.get_def(e.status)
		if def and stamina_fraction >= def.attack_speed_min_stamina:
			result = maxf(result, 1.0 + (def.attack_speed - 1.0) * e.stacks)
	return minf(result, MAX_ATTACK_SPEED)


## How blind the owner is (0..1): the strongest blind status, fading linearly
## over the last BLIND_FADE of its duration. A player's screen haze; an enemy's
## chance to miss a swing.
func blind_amount(defs: StatusDefs) -> float:
	var result := 0.0
	for e in entries:
		var def := defs.get_def(e.status)
		if def and def.blind > 0.0:
			var fade := maxf(1.0, def.duration_ticks * BLIND_FADE)
			result = maxf(result, def.blind * minf(1.0, e.ticks_left / fade))
	return result


## The index of a mark (marked_bonus > 0: Marked) that source_id applied, or -1.
func mark_from(defs: StatusDefs, source_id: int) -> int:
	for e in entries:
		var def := defs.get_def(e.status)
		if def and def.marked_bonus > 0.0 and e.source == source_id:
			return e.status
	return -1


## The index of a status that makes the owner's next hit crit (Primed), or -1.
func next_hit_crit_status(defs: StatusDefs) -> int:
	for e in entries:
		var def := defs.get_def(e.status)
		if def and def.next_hit_crits:
			return e.status
	return -1


## Shield Wall's cover box behind the owner while it blocks: (depth, width) in
## meters, the largest of its statuses'; zero without one.
func cover_box(defs: StatusDefs) -> Vector2:
	var result := Vector2.ZERO
	for e in entries:
		var def := defs.get_def(e.status)
		if def and def.cover_depth > 0.0 and def.cover_width > 0.0:
			result = Vector2(maxf(result.x, def.cover_depth), maxf(result.y, def.cover_width))
	return result


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
