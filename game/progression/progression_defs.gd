class_name ProgressionDefs
extends RefCounted
## The progression rules (data/progression.cfg): the character level and weapon
## mastery level curves (cap, XP to the next level) and the tree points each
## level gives. Pure data + math; tests build one by hand.


## One level track: a cap and an XP curve.
class LevelCurve:
	extends RefCounted
	var level_cap := 20
	## XP to the next level = round(xp_base * level ^ xp_exponent).
	var xp_base := 100.0
	var xp_exponent := 1.5

	func _init(cap: int = 20, base: float = 100.0, exponent: float = 1.5) -> void:
		level_cap = cap
		xp_base = base
		xp_exponent = exponent

	## XP needed to go from `level` to the next (0 at the cap).
	func xp_to_next(level: int) -> int:
		if level >= level_cap:
			return 0
		return maxi(1, roundi(xp_base * pow(maxf(1.0, level), xp_exponent)))

	## Total XP from level 1 to `level` (for the tuning comments and tests).
	func xp_to_reach(level: int) -> int:
		var total := 0
		for lv in range(1, mini(level, level_cap)):
			total += xp_to_next(lv)
		return total


static var _current: ProgressionDefs
static var _current_version := -1

var character := LevelCurve.new()
var mastery := LevelCurve.new()
## Wing tree points at character level 1, and per level after the first.
var wing_start_points := 0
var wing_points_per_level := 1
## A weapon tree's points at mastery level 1, and per mastery level after the first.
var mastery_start_points := 0
var mastery_points_per_level := 1
## Character XP for each gather (any node kind).
var gather_xp := 0


## The game's rules, loaded once (again when Tuning.version moves).
static func current() -> ProgressionDefs:
	if _current == null or _current_version != Tuning.version:
		_current_version = Tuning.version
		_current = from_tuning()
	return _current


static func from_tuning() -> ProgressionDefs:
	var defs := ProgressionDefs.new()
	defs.character = LevelCurve.new(Tuning.get_value("progression", "character", "level_cap"),
			Tuning.get_value("progression", "character", "xp_base"),
			Tuning.get_value("progression", "character", "xp_exponent"))
	defs.mastery = LevelCurve.new(Tuning.get_value("progression", "weapon_mastery", "level_cap"),
			Tuning.get_value("progression", "weapon_mastery", "xp_base"),
			Tuning.get_value("progression", "weapon_mastery", "xp_exponent"))
	defs.wing_points_per_level = Tuning.get_value("progression", "character", "wing_points_per_level")
	defs.wing_start_points = Tuning.get_value("progression", "character", "wing_start_points")
	defs.mastery_points_per_level = Tuning.get_value("progression", "weapon_mastery", "points_per_level")
	defs.mastery_start_points = Tuning.get_value("progression", "weapon_mastery", "start_points")
	defs.gather_xp = Tuning.get_value("progression", "sources", "gather_xp")
	for problem in defs.validate():
		push_error("progression.cfg: " + problem)
	return defs


## Wing tree points at a character level.
func wing_points(character_level: int) -> int:
	return wing_start_points + maxi(0, character_level - 1) * wing_points_per_level


## A weapon tree's points at a mastery level.
func mastery_points(mastery_level: int) -> int:
	return mastery_start_points + maxi(0, mastery_level - 1) * mastery_points_per_level


## What's wrong with the rules ([] if nothing).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	for entry: Array in [["character", character], ["weapon_mastery", mastery]]:
		var curve: LevelCurve = entry[1]
		if curve.level_cap < 1:
			problems.append("[%s] level_cap must be at least 1" % entry[0])
		if curve.xp_base <= 0.0 or curve.xp_exponent < 0.0:
			problems.append("[%s] xp_base must be above 0 and xp_exponent at least 0" % entry[0])
	if mini(mini(wing_points_per_level, mastery_points_per_level), mini(wing_start_points, mastery_start_points)) < 0:
		problems.append("points can't be negative")
	if gather_xp < 0:
		problems.append("[sources] gather_xp can't be negative")
	return problems
