class_name Tradeskills
extends RefCounted
## One character's tradeskills: a level and the XP into it per skill
## (TradeskillDefs). Every skill starts at level 1 with 0 XP. Pure logic, unit
## tested; the server owns the real one (World/Tradeskills), the client draws a
## copy made from what the server sends (to_dict / from_dict).

const START_LEVEL := 1

var defs: TradeskillDefs
## Skill id -> level (missing = START_LEVEL).
var _levels: Dictionary[String, int] = {}
## Skill id -> XP into the current level (always below xp_to_next).
var _xp: Dictionary[String, int] = {}


func _init(skill_defs: TradeskillDefs) -> void:
	defs = skill_defs


func level(skill: String) -> int:
	return _levels.get(skill, START_LEVEL)


## XP into the current level.
func xp(skill: String) -> int:
	return _xp.get(skill, 0)


## XP the current level needs to reach the next (0 at the cap).
func xp_needed(skill: String) -> int:
	return defs.xp_to_next(level(skill))


## How far through the current level, 0..1 (1 at the cap).
func progress(skill: String) -> float:
	var needed := xp_needed(skill)
	return 1.0 if needed <= 0 else clampf(float(xp(skill)) / needed, 0.0, 1.0)


func is_capped(skill: String) -> bool:
	return level(skill) >= defs.level_cap


## Adds XP to a skill; returns the levels gained (several if it's enough). XP
## past the cap is dropped. Unknown skills and xp <= 0 change nothing.
func add_xp(skill: String, amount: int) -> int:
	if not defs.has_skill(skill) or amount <= 0 or is_capped(skill):
		return 0
	var current := level(skill)
	var have := xp(skill) + amount
	var gained := 0
	while current < defs.level_cap and have >= defs.xp_to_next(current):
		have -= defs.xp_to_next(current)
		current += 1
		gained += 1
	if current >= defs.level_cap:
		have = 0
	_levels[skill] = current
	_xp[skill] = have
	return gained


## Fraction of a node's gather time for this skill (1.0 for non-gathering skills).
func gather_time_multiplier(skill: String) -> float:
	return defs.time_multiplier(level(skill)) if defs.is_gathering(skill) else 1.0


## Bonus units for one gather: defs.bonus_units with the level's bonus chance,
## else 0 (always 0 for non-gathering skills). Server only (its RNG).
func bonus_yield(skill: String, rng: RandomNumberGenerator) -> int:
	if not defs.is_gathering(skill):
		return 0
	var chance := defs.bonus_chance(level(skill))
	if chance <= 0.0:
		return 0
	return defs.bonus_units if rng.randf() < chance else 0


## {skill id: [level, xp]} for every known skill (network and, later, saves).
func to_dict() -> Dictionary:
	var data := {}
	for id in defs.order:
		data[id] = [level(id), xp(id)]
	return data


## The reverse of to_dict. Unknown skills and malformed entries are skipped;
## levels are clamped to 1..cap and XP to below the level's need, so stale
## saves or tuning changes can't break it.
static func from_dict(data: Dictionary, skill_defs: TradeskillDefs) -> Tradeskills:
	var skills := Tradeskills.new(skill_defs)
	for id: Variant in data:
		var entry: Variant = data[id]
		# Numbers may come back as floats (JSON), so both are accepted.
		if not (id is String and skill_defs.has_skill(id) and entry is Array and entry.size() == 2
				and _is_number(entry[0]) and _is_number(entry[1])):
			continue
		var lv := clampi(int(entry[0]), START_LEVEL, skill_defs.level_cap)
		skills._levels[id] = lv
		var needed := skill_defs.xp_to_next(lv)
		skills._xp[id] = 0 if needed <= 0 else clampi(int(entry[1]), 0, needed - 1)
	return skills


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
