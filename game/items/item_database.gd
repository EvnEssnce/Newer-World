class_name ItemDatabase
extends RefCounted
## Every rarity, item, affix and loot table definition, from data/loot.cfg,
## data/items.cfg and data/affixes.cfg. The game uses current(); tests build
## their own and fill the dictionaries by hand.

## Item slots ("wings" = a Wing Enhancement). Equipment maps them to equip slots.
const SLOTS: PackedStringArray = ["weapon", "head", "chest", "legs", "wings"]
## Stackable crafting materials (gathered): never equipped, no stats.
const RESOURCE_SLOT := "resource"
## Every item slot: the gear SLOTS, then resources.
const ITEM_SLOTS: PackedStringArray = ["weapon", "head", "chest", "legs", "wings", "resource"]
const PRIMARY_STATS: PackedStringArray = ["weapon_power", "wing_power", "armor"]
## Inventory icon ids (items.cfg `icon`; ItemIcon draws each): melee weapons
## (crossed swords), ranged weapons (a bow), the armor slots, Wing
## Enhancements, then materials.
const ICONS: PackedStringArray = ["melee", "ranged", "head", "chest", "legs", "wings",
		"ore", "ingot", "log", "plank", "fiber", "cloth"]
const TABLE_PREFIX := "table_"


class RarityDef:
	var id := ""
	var name := ""
	## Affixes an item of this rarity rolls.
	var affix_count := 0
	var color := Color.WHITE


class ItemDef:
	var id := ""
	var name := ""
	## One of SLOTS.
	var slot := ""
	## Weapons only: the weapon type (data/weapon_<type>.cfg), which is class-locked.
	var weapon_type := ""
	## Wing Enhancements only: the one class that equips it.
	var class_id := ""
	## One of PRIMARY_STATS.
	var primary_stat := ""
	## Its value at the base gear score (GearScore.factor scales it).
	var primary_base := 0.0
	## How many fit in one bag slot: 1 for gear, more for resources.
	var max_stack := 1
	## items.cfg `icon` (one of ICONS), "" = from the slot (icon_id()).
	var icon := ""
	## Weapons only: the weapon file's [weapon] ranged (it throws or shoots),
	## which picks the bow icon.
	var ranged := false

	func is_resource() -> bool:
		return slot == ItemDatabase.RESOURCE_SLOT

	## The inventory icon (one of ICONS): `icon` when set, else "ranged" or
	## "melee" for a weapon, the slot for armor and Wing Enhancements, ""
	## for a resource without one (validate() reports it).
	func icon_id() -> String:
		if not icon.is_empty():
			return icon
		if slot == "weapon":
			return "ranged" if ranged else "melee"
		return "" if is_resource() else slot


class AffixDef:
	var id := ""
	var name := ""
	## The combat number it changes, e.g. "crit_chance".
	var stat := ""
	var min_per_100_gs := 0.0
	var max_per_100_gs := 0.0
	var slots: PackedStringArray = []
	## Lowest rarity id that can roll it ("" = every rarity).
	var min_rarity := ""


class LootTable:
	var id := ""
	## Chance (0-1) that a kill drops anything, per eligible player.
	var drop_chance := 0.0
	var rolls := 0
	var gear_score_min := 0
	var gear_score_max := 0
	## Item id -> relative weight.
	var item_weights: Dictionary = {}
	## Rarity id -> relative weight.
	var rarity_weights: Dictionary = {}


## Rarity ids, worst first.
var rarity_order: PackedStringArray = []
var rarities: Dictionary[String, RarityDef] = {}
var items: Dictionary[String, ItemDef] = {}
var affixes: Dictionary[String, AffixDef] = {}
var tables: Dictionary[String, LootTable] = {}
## The gear score curve items' main stats follow.
var gear := GearScore.new()

static var _current: ItemDatabase
static var _current_version := -1


## The game's definitions, loaded once (again when Tuning.version moves: the
## server's tuning). Edits need a server restart.
static func current() -> ItemDatabase:
	if _current == null or _current_version != Tuning.version:
		_current_version = Tuning.version
		_current = from_tuning()
		for problem in _current.validate():
			push_error("Item data: " + problem)
	return _current


static func from_tuning() -> ItemDatabase:
	var db := ItemDatabase.new()
	db.gear = GearScore.current()
	db.rarity_order = PackedStringArray(Tuning.get_value("loot", "rarities", "order"))
	for id in db.rarity_order:
		var r := RarityDef.new()
		r.id = id
		r.name = Tuning.get_value("loot", id, "name")
		r.affix_count = Tuning.get_value("loot", id, "affixes")
		r.color = Tuning.get_value("loot", id, "color")
		db.rarities[id] = r

	for section in Tuning.get_sections("loot"):
		if not section.begins_with(TABLE_PREFIX):
			continue
		var t := LootTable.new()
		t.id = section.trim_prefix(TABLE_PREFIX)
		t.drop_chance = Tuning.get_value("loot", section, "drop_chance")
		t.rolls = Tuning.get_value("loot", section, "rolls")
		t.gear_score_min = Tuning.get_value("loot", section, "gear_score_min")
		t.gear_score_max = Tuning.get_value("loot", section, "gear_score_max")
		t.item_weights = Tuning.get_value("loot", section, "items")
		t.rarity_weights = Tuning.get_value("loot", section, "rarity_weights")
		db.tables[t.id] = t

	for id in Tuning.get_sections("items"):
		var item := ItemDef.new()
		item.id = id
		item.name = Tuning.get_value("items", id, "name")
		item.slot = Tuning.get_value("items", id, "slot")
		if Tuning.has_value("items", id, "weapon"):
			item.weapon_type = Tuning.get_value("items", id, "weapon")
		item.class_id = Tuning.get_optional("items", id, "class", "")
		item.primary_stat = Tuning.get_optional("items", id, "primary_stat", "")
		item.primary_base = Tuning.get_optional("items", id, "primary_base", 0.0)
		item.max_stack = Tuning.get_optional("items", id, "max_stack", 1)
		item.icon = Tuning.get_optional("items", id, "icon", "")
		if not item.weapon_type.is_empty():
			item.ranged = Tuning.get_optional("weapon_" + item.weapon_type, "weapon", "ranged", false)
		db.items[id] = item

	for id in Tuning.get_sections("affixes"):
		var affix := AffixDef.new()
		affix.id = id
		affix.name = Tuning.get_value("affixes", id, "name")
		affix.stat = Tuning.get_value("affixes", id, "stat")
		affix.min_per_100_gs = Tuning.get_value("affixes", id, "min_per_100_gs")
		affix.max_per_100_gs = Tuning.get_value("affixes", id, "max_per_100_gs")
		affix.slots = PackedStringArray(Tuning.get_value("affixes", id, "slots"))
		affix.min_rarity = Tuning.get_optional("affixes", id, "min_rarity", "")
		db.affixes[id] = affix
	return db


## Affixes an item in this slot can roll, in data file order. With a rarity,
## only those whose min_rarity it reaches.
func affixes_for_slot(slot: String, rarity := "") -> Array[AffixDef]:
	var pool: Array[AffixDef] = []
	for affix: AffixDef in affixes.values():
		if slot in affix.slots and (rarity.is_empty() or rarity_allows(rarity, affix)):
			pool.append(affix)
	return pool


## Whether an item of this rarity may roll the affix: no min_rarity, or the
## rarity is that one or later in rarity_order.
func rarity_allows(rarity: String, affix: AffixDef) -> bool:
	if affix.min_rarity.is_empty():
		return true
	return rarity_order.find(rarity) >= rarity_order.find(affix.min_rarity)


## Problems with the definitions, e.g. a loot table naming an item that doesn't
## exist. Empty when everything is consistent.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	for id in rarity_order:
		if not rarities.has(id):
			problems.append("rarity '%s' is in the order list but has no section" % id)
	for item: ItemDef in items.values():
		if item.slot not in ITEM_SLOTS:
			problems.append("item '%s' has unknown slot '%s'" % [item.id, item.slot])
		if not item.icon.is_empty() and item.icon not in ICONS:
			problems.append("item '%s' has unknown icon '%s'" % [item.id, item.icon])
		elif item.icon_id().is_empty():
			problems.append("resource '%s' needs an icon" % item.id)
		if item.is_resource():
			if item.max_stack < 1:
				problems.append("resource '%s' needs a max_stack of at least 1" % item.id)
			if not item.primary_stat.is_empty() or not item.weapon_type.is_empty() or not item.class_id.is_empty():
				problems.append("resource '%s' mustn't have a primary_stat, weapon or class" % item.id)
			continue
		if item.max_stack != 1:
			problems.append("item '%s': only resources stack (max_stack)" % item.id)
		if item.primary_stat not in PRIMARY_STATS:
			problems.append("item '%s' has unknown primary_stat '%s'" % [item.id, item.primary_stat])
		var is_weapon := item.slot == "weapon"
		var has_weapon_type := not item.weapon_type.is_empty()
		if is_weapon != has_weapon_type:
			problems.append("item '%s': weapons need a weapon type, other slots mustn't have one" % item.id)
		if (item.slot == "wings") != not item.class_id.is_empty():
			problems.append("item '%s': Wing Enhancements need a class, other slots mustn't have one" % item.id)
	for affix: AffixDef in affixes.values():
		if affix.min_per_100_gs > affix.max_per_100_gs:
			problems.append("affix '%s' has min above max" % affix.id)
		if not affix.min_rarity.is_empty() and affix.min_rarity not in rarity_order:
			problems.append("affix '%s' has unknown min_rarity '%s'" % [affix.id, affix.min_rarity])
		for slot in affix.slots:
			if slot not in SLOTS:
				problems.append("affix '%s' has unknown slot '%s'" % [affix.id, slot])
	for table: LootTable in tables.values():
		if table.drop_chance < 0.0 or table.drop_chance > 1.0:
			problems.append("loot table '%s' drop_chance must be 0-1" % table.id)
		if table.gear_score_min > table.gear_score_max:
			problems.append("loot table '%s' has gear_score_min above max" % table.id)
		for item_id: String in table.item_weights:
			if not items.has(item_id):
				problems.append("loot table '%s' names unknown item '%s'" % [table.id, item_id])
			elif items[item_id].is_resource():
				problems.append("loot table '%s' names resource '%s' (tables roll gear)" % [table.id, item_id])
		for rarity_id: String in table.rarity_weights:
			if not rarities.has(rarity_id):
				problems.append("loot table '%s' names unknown rarity '%s'" % [table.id, rarity_id])
	return problems
