class_name ItemDatabase
extends RefCounted
## Every rarity, item, affix and loot table definition, from data/loot.cfg,
## data/items.cfg and data/affixes.cfg. The game uses current(); tests build
## their own and fill the dictionaries by hand.

const SLOTS: PackedStringArray = ["weapon", "head", "chest", "hands", "legs", "feet"]
const PRIMARY_STATS: PackedStringArray = ["weapon_power", "armor"]
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
	## One of PRIMARY_STATS.
	var primary_stat := ""
	var primary_per_gear_score := 0.0


class AffixDef:
	var id := ""
	var name := ""
	## The combat number it changes, e.g. "crit_chance".
	var stat := ""
	var min_per_100_gs := 0.0
	var max_per_100_gs := 0.0
	var slots: PackedStringArray = []


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

static var _current: ItemDatabase


## The game's definitions, loaded once. Edits need a server restart.
static func current() -> ItemDatabase:
	if _current == null:
		_current = from_tuning()
		for problem in _current.validate():
			push_error("Item data: " + problem)
	return _current


static func from_tuning() -> ItemDatabase:
	var db := ItemDatabase.new()
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
		item.primary_stat = Tuning.get_value("items", id, "primary_stat")
		item.primary_per_gear_score = Tuning.get_value("items", id, "primary_per_gear_score")
		db.items[id] = item

	for id in Tuning.get_sections("affixes"):
		var affix := AffixDef.new()
		affix.id = id
		affix.name = Tuning.get_value("affixes", id, "name")
		affix.stat = Tuning.get_value("affixes", id, "stat")
		affix.min_per_100_gs = Tuning.get_value("affixes", id, "min_per_100_gs")
		affix.max_per_100_gs = Tuning.get_value("affixes", id, "max_per_100_gs")
		affix.slots = PackedStringArray(Tuning.get_value("affixes", id, "slots"))
		db.affixes[id] = affix
	return db


## Affixes an item in this slot can roll, in data file order.
func affixes_for_slot(slot: String) -> Array[AffixDef]:
	var pool: Array[AffixDef] = []
	for affix: AffixDef in affixes.values():
		if slot in affix.slots:
			pool.append(affix)
	return pool


## Problems with the definitions, e.g. a loot table naming an item that doesn't
## exist. Empty when everything is consistent.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	for id in rarity_order:
		if not rarities.has(id):
			problems.append("rarity '%s' is in the order list but has no section" % id)
	for item: ItemDef in items.values():
		if item.slot not in SLOTS:
			problems.append("item '%s' has unknown slot '%s'" % [item.id, item.slot])
		if item.primary_stat not in PRIMARY_STATS:
			problems.append("item '%s' has unknown primary_stat '%s'" % [item.id, item.primary_stat])
		var is_weapon := item.slot == "weapon"
		var has_weapon_type := not item.weapon_type.is_empty()
		if is_weapon != has_weapon_type:
			problems.append("item '%s': weapons need a weapon type, other slots mustn't have one" % item.id)
	for affix: AffixDef in affixes.values():
		if affix.min_per_100_gs > affix.max_per_100_gs:
			problems.append("affix '%s' has min above max" % affix.id)
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
		for rarity_id: String in table.rarity_weights:
			if not rarities.has(rarity_id):
				problems.append("loot table '%s' names unknown rarity '%s'" % [table.id, rarity_id])
	return problems
