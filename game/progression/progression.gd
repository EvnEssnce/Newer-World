class_name Progression
extends RefCounted
## One character's progression (ProgressionDefs): a character level and, per
## weapon type, a mastery level, each with the XP into it. Everything starts at
## level 1 with 0 XP. Pure logic, unit tested (tests/test_progression.gd); the
## server owns the real one (World/Progression) and saves it with the character
## (CharacterSave.progression).
##
## The levels decide tree points (wing_points, weapon_points), which limit the
## Wing and weapon trees (CharacterBuild.set_point_limits). XP comes from
## World/Progression (kills, gathering).

const START_LEVEL := 1

var defs: ProgressionDefs
var _level := START_LEVEL
## XP into the current character level (always below its xp_to_next).
var _xp := 0
## Weapon id -> [mastery level, XP into it] (missing = level 1, 0 XP).
var _mastery: Dictionary[String, Vector2i] = {}


func _init(progression_defs: ProgressionDefs) -> void:
	defs = progression_defs


# --- Character level ---

func level() -> int:
	return _level


## XP into the current character level.
func xp() -> int:
	return _xp


## XP the current character level needs to reach the next (0 at the cap).
func xp_needed() -> int:
	return defs.character.xp_to_next(_level)


## Adds character XP; returns the levels gained (several if it's enough). XP past
## the cap is dropped; xp <= 0 changes nothing.
func add_xp(amount: int) -> int:
	var after := _gain(defs.character, Vector2i(_level, _xp), amount)
	var gained := after.x - _level
	_level = after.x
	_xp = after.y
	return gained


## Wing tree points this character level gives.
func wing_points() -> int:
	return defs.wing_points(_level)


# --- Weapon mastery ---

func mastery_level(weapon_id: String) -> int:
	return _track(weapon_id).x


## XP into the weapon's current mastery level.
func mastery_xp(weapon_id: String) -> int:
	return _track(weapon_id).y


## XP the weapon's current mastery level needs to reach the next (0 at the cap).
func mastery_xp_needed(weapon_id: String) -> int:
	return defs.mastery.xp_to_next(mastery_level(weapon_id))


## Adds mastery XP to one weapon type; returns the levels gained. An empty
## weapon id or xp <= 0 changes nothing.
func add_mastery_xp(weapon_id: String, amount: int) -> int:
	if weapon_id.is_empty():
		return 0
	var before := _track(weapon_id)
	var after := _gain(defs.mastery, before, amount)
	if after != before:
		_mastery[weapon_id] = after
	return after.x - before.x


## That weapon's mastery tree points at its mastery level.
func weapon_points(weapon_id: String) -> int:
	return defs.mastery_points(mastery_level(weapon_id))


func _track(weapon_id: String) -> Vector2i:
	return _mastery.get(weapon_id, Vector2i(START_LEVEL, 0))


## Weapon ids with any mastery level or XP, sorted.
func mastered_weapons() -> PackedStringArray:
	var ids := PackedStringArray(_mastery.keys())
	ids.sort()
	return ids


# --- Saving ---

## {"level": L, "xp": X, "mastery": {weapon id: [L, X]}} (saves, and later
## the owner's copy). Only weapons with progress are listed.
func to_dict() -> Dictionary:
	var mastery := {}
	for id in mastered_weapons():
		mastery[id] = [_mastery[id].x, _mastery[id].y]
	return {"level": _level, "xp": _xp, "mastery": mastery}


## The reverse of to_dict. Malformed parts are skipped; levels are clamped to
## 1..cap and XP to below the level's need, so stale saves or tuning changes
## (a lower cap, a steeper curve) can't break it. Unknown weapon ids are kept
## (harmless; a weapon renamed in data/ just starts over).
static func from_dict(data: Dictionary, progression_defs: ProgressionDefs) -> Progression:
	var result := Progression.new(progression_defs)
	if _is_number(data.get("level")):
		var start := _clamped(progression_defs.character, int(data["level"]),
				int(data["xp"]) if _is_number(data.get("xp")) else 0)
		result._level = start.x
		result._xp = start.y
	var mastery: Variant = data.get("mastery", {})
	if mastery is Dictionary:
		for id: Variant in mastery:
			var entry: Variant = mastery[id]
			if not (id is String and not id.is_empty() and entry is Array and entry.size() == 2
					and _is_number(entry[0]) and _is_number(entry[1])):
				continue
			var track := _clamped(progression_defs.mastery, int(entry[0]), int(entry[1]))
			if track != Vector2i(START_LEVEL, 0):
				result._mastery[id] = track
	return result


## Mastery XP for one kill: `xp` split over the weapons in `by_weapon` (weapon id
## -> damage dealt with it; "" = no weapon, a Wing ability) by their share of
## all the damage, rounded; weapons whose share rounds to 0 are left out.
static func mastery_split(by_weapon: Dictionary, xp: int) -> Dictionary[String, int]:
	var result: Dictionary[String, int] = {}
	var total := 0.0
	for id: String in by_weapon:
		total += maxf(0.0, by_weapon[id])
	if xp <= 0 or total <= 0.0:
		return result
	for id: String in by_weapon:
		var share := roundi(xp * maxf(0.0, by_weapon[id]) / total)
		if not id.is_empty() and share > 0:
			result[id] = share
	return result


## [level, xp] after adding `amount` on `curve`.
static func _gain(curve: ProgressionDefs.LevelCurve, track: Vector2i, amount: int) -> Vector2i:
	if amount <= 0 or track.x >= curve.level_cap:
		return track
	var lv := track.x
	var have := track.y + amount
	while lv < curve.level_cap and have >= curve.xp_to_next(lv):
		have -= curve.xp_to_next(lv)
		lv += 1
	return Vector2i(lv, 0 if lv >= curve.level_cap else have)


static func _clamped(curve: ProgressionDefs.LevelCurve, lv: int, have: int) -> Vector2i:
	lv = clampi(lv, START_LEVEL, curve.level_cap)
	var needed := curve.xp_to_next(lv)
	return Vector2i(lv, 0 if needed <= 0 else clampi(have, 0, needed - 1))


# Numbers may come back as floats (JSON), so both are accepted.
static func _is_number(value: Variant) -> bool:
	return value is int or value is float
