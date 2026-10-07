class_name Item
extends RefCounted
## One rolled item: which item it is, plus everything rolled when it dropped.
## Plain data (to_dict / from_dict) so it can go over the network and, later,
## into saves. Definitions live in ItemDatabase; LootRoller makes these.

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
		"item": item_id,
		"rarity": rarity,
		"gs": gear_score,
		"primary": primary_value,
		"affixes": affixes.duplicate(),
	}


static func from_dict(data: Dictionary) -> Item:
	var item := Item.new()
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
