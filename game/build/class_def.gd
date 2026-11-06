class_name ClassDef
extends RefCounted
## A character class from data/class_<id>.cfg: which weapons it may equip, and
## the loadout a new character starts with. Weapon lists are strict: the server
## only lets a character equip its own class's weapons. Tests build their own.

const DEFAULT_CLASS := "fighter"

var id := ""
var display_name := ""
## Every weapon id this class can equip.
var weapons := PackedStringArray()
## Equipped weapon ids for a new character, one per weapon slot.
var default_loadout := PackedStringArray()
## Multiplies every Ember gain (the Mage spends Ember on weapon abilities, so it
## gains more). 1 = normal.
var ember_gain := 1.0
## Base max health before gear and the level bonus ([class] base_health); 0 =
## the shared data/combat.cfg [health] max.
var base_health := 0.0
## Gathering passive ([gathering]): a gathering tradeskill (mining, logging,
## harvesting: every node of that skill, whatever its resource) the class is
## better at, its name, the fraction of the gather time it takes (0.85 = 15%
## faster) and the bonus-unit chance it adds. "" = none.
var gather_skill := ""
var gather_passive_name := ""
var gather_time := 1.0
var gather_bonus_chance := 0.0
## Level bonus (levels past a full Wing tree, data/class_<id>.cfg [level_bonus]):
## the stat each point raises (one of LEVEL_BONUS_STATS) and by how much.
var level_bonus_stat := ""
var level_bonus_per_point := 0.0

## Level bonus stats: "max_health" (points of health), "damage" (fraction more
## damage dealt), "move_speed" (fraction faster walking), "dodge_cost" (fraction
## less stamina per roll), "ember_cost" (fraction less Ember per ability),
## "healing" (fraction more healing done).
const LEVEL_BONUS_STATS := ["max_health", "damage", "move_speed", "dodge_cost", "ember_cost", "healing"]

static var _cache: Dictionary[String, ClassDef] = {}
static var _cache_version := -1


## The class with this id, loaded once (again when Tuning.version moves); null
## if there's no data file for it.
static func for_id(class_id: String) -> ClassDef:
	if _cache_version != Tuning.version:
		_cache_version = Tuning.version
		_cache.clear()
	if not _cache.has(class_id):
		if not class_id.is_valid_identifier() or not Tuning.has_file("class_" + class_id):
			return null
		_cache[class_id] = from_tuning(class_id)
	return _cache[class_id]


## Every class with a data/class_<id>.cfg, sorted (the K panel's Class picker).
static func all_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for file in Tuning.files_with_prefix("class_"):
		ids.append(file.trim_prefix("class_"))
	return ids


static func from_tuning(class_id: String) -> ClassDef:
	var file := "class_" + class_id
	var c := ClassDef.new()
	c.id = class_id
	c.display_name = Tuning.get_value(file, "class", "name")
	c.weapons = PackedStringArray(Tuning.get_value(file, "class", "weapons"))
	c.default_loadout = PackedStringArray(Tuning.get_value(file, "class", "default_loadout"))
	c.ember_gain = Tuning.get_optional(file, "class", "ember_gain", 1.0)
	c.base_health = Tuning.get_optional(file, "class", "base_health", 0.0)
	c.gather_skill = Tuning.get_optional(file, "gathering", "skill", "")
	c.gather_passive_name = Tuning.get_optional(file, "gathering", "name", "")
	c.gather_time = clampf(Tuning.get_optional(file, "gathering", "time_multiplier", 1.0), 0.1, 1.0)
	c.gather_bonus_chance = clampf(Tuning.get_optional(file, "gathering", "bonus_chance", 0.0), 0.0, 1.0)
	c.level_bonus_stat = Tuning.get_optional(file, "level_bonus", "stat", "")
	c.level_bonus_per_point = Tuning.get_optional(file, "level_bonus", "per_point", 0.0)
	if not c.level_bonus_stat.is_empty() and not (c.level_bonus_stat in LEVEL_BONUS_STATS):
		push_error("class_%s.cfg: unknown [level_bonus] stat \"%s\"" % [class_id, c.level_bonus_stat])
	return c


## What `points` level bonus points add up to (level_bonus_per_point each).
func level_bonus(points: int) -> float:
	return maxi(0, points) * level_bonus_per_point if not level_bonus_stat.is_empty() else 0.0


## "+3% damage", "+60 max health", "-6% dodge stamina" for `points` points
## ("" for none): the K panel and the level-up feed line.
func level_bonus_text(points: int) -> String:
	var amount := level_bonus(points)
	if amount == 0.0:
		return ""
	var tenths := roundi(amount * 1000.0)  # one decimal of a percent
	var percent := ("%d%%" % (tenths / 10)) if tenths % 10 == 0 else ("%.1f%%" % (tenths / 10.0))
	match level_bonus_stat:
		"max_health":
			return "+%d max health" % roundi(amount)
		"damage":
			return "+%s damage" % percent
		"move_speed":
			return "+%s movement speed" % percent
		"dodge_cost":
			return "-%s dodge stamina" % percent
		"ember_cost":
			return "-%s Ember cost" % percent
		"healing":
			return "+%s healing" % percent
	return ""


## Fraction of the gather time for a node of this tradeskill (the passive's
## time_multiplier for its skill, else 1).
func gather_time_multiplier(skill: String) -> float:
	return gather_time if not gather_skill.is_empty() and skill == gather_skill else 1.0


## Bonus-unit chance the passive adds for this tradeskill (0 for any other).
func gather_extra_chance(skill: String) -> float:
	return gather_bonus_chance if not gather_skill.is_empty() and skill == gather_skill else 0.0


## "Prospector: Mining 15% faster, +10% bonus yield chance" ("" for none): the P panel.
func gather_passive_text(skill_name: String) -> String:
	if gather_skill.is_empty():
		return ""
	var parts := PackedStringArray()
	if gather_time < 1.0:
		parts.append("%s %d%% faster" % [skill_name, roundi((1.0 - gather_time) * 100.0)])
	if gather_bonus_chance > 0.0:
		parts.append("+%d%% bonus yield chance" % roundi(gather_bonus_chance * 100.0))
	if parts.is_empty():
		return ""
	var title := gather_passive_name if not gather_passive_name.is_empty() else display_name
	return "%s: %s" % [title, ", ".join(parts)]


func allows_weapon(weapon_id: String) -> bool:
	return weapon_id in weapons


## "" if loadout (weapon ids, one per weapon slot) is allowed, else why not.
func validate_loadout(loadout: PackedStringArray) -> String:
	if loadout.size() != PlayerState.WEAPON_SLOTS:
		return "Equip exactly %d weapons." % PlayerState.WEAPON_SLOTS
	if loadout[0] == loadout[1]:
		return "Can't equip the same weapon twice."
	for weapon_id in loadout:
		if not allows_weapon(weapon_id):
			return "A %s can't equip %s." % [display_name, weapon_id]
	return ""
