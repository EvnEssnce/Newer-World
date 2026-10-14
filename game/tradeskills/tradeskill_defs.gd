class_name TradeskillDefs
extends RefCounted
## Every tradeskill and the shared rules (data/tradeskills.cfg): the level cap,
## the XP curve, XP per gather and what a gathering skill's level does (gather
## time, bonus yield). Pure data + math; tests build one by hand (add_skill).

const CATEGORIES: PackedStringArray = ["gathering", "refining", "crafting"]
const CATEGORY_NAMES := {"gathering": "Gathering", "refining": "Refining", "crafting": "Crafting"}


## One skill ([skill_<id>]).
class SkillDef:
	extends RefCounted
	var id := ""
	var display_name := ""
	## "gathering", "refining" or "crafting".
	var category := "gathering"
	## Gathering skills: XP per gather, and per unit gathered.
	var xp_per_gather := 0
	var xp_per_unit := 0
	## Node kind -> XP multiplier (missing = 1.0).
	var node_xp := {}

	func is_gathering() -> bool:
		return category == "gathering"


static var _current: TradeskillDefs
static var _current_version := -1

var level_cap := 100
## XP to next level = round(xp_base * level ^ xp_exponent).
var xp_base := 100.0
var xp_exponent := 1.5
var time_reduction_per_level := 0.004
var time_floor := 0.6
var bonus_chance_per_level := 0.005
var bonus_chance_max := 0.5
var bonus_units := 1
## Skill ids in panel order.
var order: PackedStringArray = []
var skills: Dictionary[String, SkillDef] = {}


## The game's tradeskills, loaded once (again when Tuning.version moves).
static func current() -> TradeskillDefs:
	if _current == null or _current_version != Tuning.version:
		_current_version = Tuning.version
		_current = from_tuning()
	return _current


static func from_tuning() -> TradeskillDefs:
	var defs := TradeskillDefs.new()
	defs.level_cap = Tuning.get_value("tradeskills", "tradeskills", "level_cap")
	defs.xp_base = Tuning.get_value("tradeskills", "xp_curve", "base")
	defs.xp_exponent = Tuning.get_value("tradeskills", "xp_curve", "exponent")
	defs.time_reduction_per_level = Tuning.get_value("tradeskills", "gathering", "time_reduction_per_level")
	defs.time_floor = Tuning.get_value("tradeskills", "gathering", "time_floor")
	defs.bonus_chance_per_level = Tuning.get_value("tradeskills", "gathering", "bonus_chance_per_level")
	defs.bonus_chance_max = Tuning.get_value("tradeskills", "gathering", "bonus_chance_max")
	defs.bonus_units = Tuning.get_value("tradeskills", "gathering", "bonus_units")
	for id: String in Tuning.get_value("tradeskills", "tradeskills", "order"):
		if defs.has_skill(id):
			push_error("tradeskills.cfg: %s is in order twice" % id)
			continue
		var section := "skill_" + id
		var skill := defs.add_skill(id, Tuning.get_value("tradeskills", section, "name"),
				Tuning.get_value("tradeskills", section, "category"))
		skill.xp_per_gather = Tuning.get_optional("tradeskills", section, "xp_per_gather", 0)
		skill.xp_per_unit = Tuning.get_optional("tradeskills", section, "xp_per_unit", 0)
		skill.node_xp = Tuning.get_optional("tradeskills", section, "node_xp", {})
	for problem in defs.validate():
		push_error("tradeskills.cfg: " + problem)
	return defs


## Adds a skill at the end of the order (data loading and tests).
func add_skill(id: String, display_name: String, category: String) -> SkillDef:
	var skill := SkillDef.new()
	skill.id = id
	skill.display_name = display_name
	skill.category = category
	skills[id] = skill
	order.append(id)
	return skill


func has_skill(id: String) -> bool:
	return skills.has(id)


func is_gathering(id: String) -> bool:
	return skills.has(id) and skills[id].is_gathering()


func display_name(id: String) -> String:
	return skills[id].display_name if skills.has(id) else id


## Skill ids of one category, in panel order.
func ids_in(category: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for id in order:
		if skills[id].category == category:
			ids.append(id)
	return ids


## XP needed to go from `level` to the next (0 at the cap).
func xp_to_next(level: int) -> int:
	if level >= level_cap:
		return 0
	return maxi(1, roundi(xp_base * pow(maxf(1.0, level), xp_exponent)))


## XP a gather of `units` from a `node_kind` node gives a gathering skill (0 for
## other skills or nothing gathered).
func gather_xp(id: String, node_kind: String, units: int) -> int:
	if not is_gathering(id) or units <= 0:
		return 0
	var skill := skills[id]
	var multiplier: float = float(skill.node_xp.get(node_kind, 1.0))
	return maxi(0, roundi((skill.xp_per_gather + skill.xp_per_unit * units) * multiplier))


## Fraction of a node's gather time at this gathering level.
func time_multiplier(level: int) -> float:
	return maxf(time_floor, 1.0 - time_reduction_per_level * (level - 1))


## Chance (0..1) of bonus units on a gather at this gathering level.
func bonus_chance(level: int) -> float:
	return clampf(bonus_chance_per_level * (level - 1), 0.0, minf(1.0, bonus_chance_max))


## Problems with the data, or none (a unit test runs it on the real file).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if level_cap < 2:
		problems.append("level_cap must be at least 2")
	if xp_base <= 0.0 or xp_exponent < 0.0:
		problems.append("xp_curve base must be > 0 and exponent >= 0")
	if time_floor <= 0.0 or time_floor > 1.0:
		problems.append("gathering time_floor must be in (0, 1]")
	if bonus_units < 0:
		problems.append("gathering bonus_units must be >= 0")
	if order.is_empty():
		problems.append("no skills in [tradeskills] order")
	for id in order:
		var skill := skills[id]
		if not skill.category in CATEGORIES:
			problems.append("skill %s: unknown category '%s'" % [id, skill.category])
		if skill.display_name.is_empty():
			problems.append("skill %s has no name" % id)
		if skill.is_gathering() and skill.xp_per_gather + skill.xp_per_unit <= 0:
			problems.append("gathering skill %s gives no XP" % id)
		for kind: Variant in skill.node_xp:
			if not kind is String or not (skill.node_xp[kind] is float or skill.node_xp[kind] is int) \
					or float(skill.node_xp[kind]) < 0.0:
				problems.append("skill %s: node_xp needs node kind -> multiplier >= 0" % id)
	return problems
