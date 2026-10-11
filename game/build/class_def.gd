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

static var _cache: Dictionary[String, ClassDef] = {}


## The class with this id, loaded once; null if there's no data file for it.
static func for_id(class_id: String) -> ClassDef:
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
	return c


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
