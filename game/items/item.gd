class_name Item
extends RefCounted
## One rolled item: which item it is, plus everything rolled when it dropped.
## Plain data (to_dict / from_dict) so it can go over the network and, later,
## into saves. Definitions live in ItemDatabase; LootRoller makes these.

## Its id in the owner's Inventory (requests name items by it); 0 until it's
## added to one.
var uid := 0
## Item definition id (a section of data/items.cfg).
var item_id := ""
## Rarity id (a section of data/loot.cfg).
var rarity := ""
var gear_score := 0
## Value of the definition's primary_stat (weapon_power or armor) at this gear score.
var primary_value := 0.0
## Affix id (a section of data/affixes.cfg) -> rolled value.
var affixes: Dictionary[String, float] = {}


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"item": item_id,
		"rarity": rarity,
		"gs": gear_score,
		"primary": primary_value,
		"affixes": affixes.duplicate(),
	}


static func from_dict(data: Dictionary) -> Item:
	var item := Item.new()
	item.uid = data.get("uid", 0)
	item.item_id = data.get("item", "")
	item.rarity = data.get("rarity", "")
	item.gear_score = data.get("gs", 0)
	item.primary_value = data.get("primary", 0.0)
	var rolled: Dictionary = data.get("affixes", {})
	for affix_id: String in rolled:
		item.affixes[affix_id] = rolled[affix_id]
	return item


## One line for logs and the loot simulator, e.g.
## "Rare Iron Broadsword  GS 123  weapon_power 123  Sear crit_chance +3.1%".
func describe(db: ItemDatabase) -> String:
	var def: ItemDatabase.ItemDef = db.items.get(item_id)
	var rarity_def: ItemDatabase.RarityDef = db.rarities.get(rarity)
	var parts := PackedStringArray()
	parts.append("%s %s" % [rarity_def.name if rarity_def else rarity, def.name if def else item_id])
	parts.append("GS %d" % gear_score)
	if def:
		parts.append("%s %.1f" % [def.primary_stat, primary_value])
	for affix_id in affixes:
		var affix: ItemDatabase.AffixDef = db.affixes.get(affix_id)
		parts.append("%s %s" % [affix.name if affix else affix_id,
				format_stat(affix.stat if affix else affix_id, affixes[affix_id])])
	return "  ".join(parts)


## "crit_chance +3.1%" for fractional percent stats, "max_health +42" otherwise.
static func format_stat(stat: String, value: float) -> String:
	if stat.ends_with("_pct") or stat.ends_with("_chance") or stat.ends_with("_reduction"):
		return "%s +%.1f%%" % [stat, value * 100.0]
	return "%s +%d" % [stat, roundi(value)]


## How each stat reads in the UI: [label, is a fraction shown as %, sign].
## A sign of -1 shows the bonus as a reduction (block_stamina_reduction).
const STAT_TEXT := {
	"weapon_power": ["weapon power", false, 0],
	"wing_power": ["wing power", false, 0],
	"armor": ["armor", false, 0],
	"damage_pct": ["damage", true, 1],
	"crit_chance": ["crit chance", true, 1],
	"max_health": ["max health", false, 1],
	"max_stamina": ["max stamina", false, 1],
	"stamina_regen_pct": ["stamina regen", true, 1],
	"block_stamina_reduction": ["stamina cost of blocked hits", true, -1],
	"healing_pct": ["healing received", true, 1],
	"ember_gain_pct": ["Ember gained", true, 1],
}


## The rarest of the items (latest in the rarity order), the first of equals.
static func best_of(items: Array[Item], db: ItemDatabase) -> Item:
	var best: Item = items[0]
	for item in items:
		if db.rarity_order.find(item.rarity) > db.rarity_order.find(best.rarity):
			best = item
	return best


## "Iron Broadsword", or the id if the definition is missing.
func display_name(db: ItemDatabase) -> String:
	var def: ItemDatabase.ItemDef = db.items.get(item_id)
	return def.name if def else item_id


func rarity_color(db: ItemDatabase) -> Color:
	var rarity_def: ItemDatabase.RarityDef = db.rarities.get(rarity)
	return rarity_def.color if rarity_def else Color.WHITE


## "Rare  Head", "Common  Weapon (Broadsword)" or "Epic  Wing Enhancement".
func kind_text(db: ItemDatabase) -> String:
	var rarity_def: ItemDatabase.RarityDef = db.rarities.get(rarity)
	var def: ItemDatabase.ItemDef = db.items.get(item_id)
	var slot: String = "?" if def == null else (
			"Wing Enhancement" if def.slot == "wings" else def.slot.capitalize())
	if def and not def.weapon_type.is_empty():
		var file := "weapon_" + def.weapon_type
		var weapon_name: String = Tuning.get_optional(file, "weapon", "name", def.weapon_type.capitalize())
		slot += " (%s)" % weapon_name
	return "%s  %s" % [rarity_def.name if rarity_def else rarity, slot]


## One line per stat: the primary stat first ("Armor 18"), then each bonus
## stat with its affix name ("Sear: +3.1% crit chance").
func stat_lines(db: ItemDatabase) -> PackedStringArray:
	var lines := PackedStringArray()
	var def: ItemDatabase.ItemDef = db.items.get(item_id)
	if def:
		var label := _stat_label(def.primary_stat)
		lines.append("%s%s %d" % [label.left(1).to_upper(), label.substr(1), roundi(primary_value)])
	for affix_id in affixes:
		var affix: ItemDatabase.AffixDef = db.affixes.get(affix_id)
		var stat := affix.stat if affix else affix_id
		lines.append("%s: %s" % [affix.name if affix else affix_id, display_stat(stat, affixes[affix_id])])
	return lines


## "+3.1% crit chance", "+42 max health", "-6.0% stamina cost of blocked hits".
static func display_stat(stat: String, value: float) -> String:
	if not STAT_TEXT.has(stat):
		return format_stat(stat, value)
	var text: Array = STAT_TEXT[stat]
	var sign_text := "-" if text[2] < 0 else "+"
	if text[1]:
		return "%s%.1f%% %s" % [sign_text, value * 100.0, text[0]]
	return "%s%d %s" % [sign_text, roundi(value), text[0]]


static func _stat_label(stat: String) -> String:
	return STAT_TEXT[stat][0] if STAT_TEXT.has(stat) else stat
