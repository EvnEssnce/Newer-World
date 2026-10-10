class_name Equipment
extends RefCounted
## One player's equipped gear (server-owned; the client gets a copy): an item
## (or nothing) per equip slot, the rules for what fits where, and the stat
## totals the server's combat numbers use. Pure logic, unit tested
## (tests/test_equipment.gd).
##
## weapon_1 / weapon_2 follow the character's two loadout weapon slots: a weapon
## item sits in the slot whose loadout weapon is its type. An empty weapon slot
## is the class's plain weapon at the base gear score (the weapon file's numbers).

const SLOTS: PackedStringArray = ["weapon_1", "weapon_2", "head", "chest", "legs", "wings"]
const SLOT_NAMES := {"weapon_1": "Weapon 1", "weapon_2": "Weapon 2", "head": "Head",
		"chest": "Chest", "legs": "Legs", "wings": "Wing Enhancement"}


## What gear adds up to. Server: Player.gear; the inventory panel shows it.
class Stats:
	var armor := 0.0
	## Weapon type -> its item's weapon power as a multiplier (1 = the file's damage).
	var weapon_power: Dictionary[String, float] = {}
	## Weapon type -> its item's gear score.
	var weapon_gear_score: Dictionary[String, int] = {}
	## The Wing Enhancement's wing power as a multiplier, and its gear score
	## (0 = none: callers use the base gear score).
	var wing_power := 1.0
	var wing_gear_score := 0
	## Affix stat (e.g. "crit_chance") -> total.
	var bonuses: Dictionary[String, float] = {}
	var average_gear_score := 0.0

	func bonus(stat: String) -> float:
		return bonuses.get(stat, 0.0)

	## Damage multiplier for attacks with this weapon type (1 without an item).
	func weapon_power_for(weapon_type: String) -> float:
		return weapon_power.get(weapon_type, 1.0)

	## The gear score a hit with this weapon type counts as against armor.
	func weapon_gear_score_for(weapon_type: String, base: int) -> int:
		return weapon_gear_score.get(weapon_type, base)


## Equip slot -> Item. Missing = empty.
var items: Dictionary[String, Item] = {}


## The item slot (ItemDatabase.SLOTS) an equip slot takes.
static func item_slot_for(equip_slot: String) -> String:
	return "weapon" if equip_slot.begins_with("weapon_") else equip_slot


## Loadout index of a weapon equip slot (weapon_1 -> 0), or -1.
static func weapon_index(equip_slot: String) -> int:
	return SLOTS.find(equip_slot) if equip_slot.begins_with("weapon_") else -1


## Why `item` can't be equipped in `equip_slot` by a character of class
## `class_id` whose class uses `class_weapons`; "" if it can.
static func check(item: Item, equip_slot: String, db: ItemDatabase, class_id: String,
		class_weapons: PackedStringArray) -> String:
	if equip_slot not in SLOTS:
		return "There's no %s slot." % equip_slot
	var def: ItemDatabase.ItemDef = db.items.get(item.item_id)
	if def == null:
		return "Unknown item."
	if def.slot != item_slot_for(equip_slot):
		return "%s doesn't go in the %s slot." % [def.name, SLOT_NAMES[equip_slot]]
	if not def.weapon_type.is_empty() and def.weapon_type not in class_weapons:
		return "Your class can't use %s." % def.name
	if not def.class_id.is_empty() and def.class_id != class_id:
		return "%s is for the %s class." % [def.name, def.class_id.capitalize()]
	return ""


## The equip slot a weapon item of `weapon_type` goes in when asked for
## `requested`: the slot whose loadout weapon already is that type (two slots
## can't hold the same weapon), else the one asked for.
static func weapon_target(weapon_type: String, requested: String, loadout: PackedStringArray) -> String:
	var index := loadout.find(weapon_type)
	return SLOTS[index] if index >= 0 and index < 2 else requested


func get_item(equip_slot: String) -> Item:
	return items.get(equip_slot)


## Puts the item in the slot and returns what was there (or null).
func equip(equip_slot: String, item: Item) -> Item:
	var previous: Item = items.get(equip_slot)
	items[equip_slot] = item
	return previous


## Empties the slot and returns what was there (or null).
func unequip(equip_slot: String) -> Item:
	var previous: Item = items.get(equip_slot)
	items.erase(equip_slot)
	return previous


## After the loadout's weapons changed (K panel, or an equip): moves each
## weapon item to the slot now holding its type. Returns the ones whose type
## isn't equipped any more, taken out (they go back to the bag).
func sync_weapons(loadout: PackedStringArray, db: ItemDatabase) -> Array[Item]:
	var weapon_items: Array[Item] = []
	for equip_slot in ["weapon_1", "weapon_2"]:
		if items.has(equip_slot):
			weapon_items.append(items[equip_slot])
			items.erase(equip_slot)
	var removed: Array[Item] = []
	for item in weapon_items:
		var def: ItemDatabase.ItemDef = db.items.get(item.item_id)
		var index := loadout.find(def.weapon_type) if def else -1
		if index < 0 or index >= 2 or items.has(SLOTS[index]):
			removed.append(item)
		else:
			items[SLOTS[index]] = item
	return removed


## What the equipped items add up to. In the average gear score an empty
## weapon slot counts as the plain weapon's base gear score, other empty slots
## as 0.
func stats(db: ItemDatabase, weights: Dictionary) -> Stats:
	var result := Stats.new()
	var weighted := 0.0
	var total_weight := 0.0
	for equip_slot in SLOTS:
		var weight: float = weights.get(equip_slot, 0.0)
		total_weight += weight
		var item: Item = items.get(equip_slot)
		if item == null:
			if equip_slot.begins_with("weapon_"):
				weighted += weight * db.gear.base
			continue
		weighted += weight * item.gear_score
		var def: ItemDatabase.ItemDef = db.items.get(item.item_id)
		if def:
			match def.primary_stat:
				"armor":
					result.armor += item.primary_value
				"weapon_power":
					result.weapon_power[def.weapon_type] = item.primary_value / 100.0
					result.weapon_gear_score[def.weapon_type] = item.gear_score
				"wing_power":
					result.wing_power = item.primary_value / 100.0
					result.wing_gear_score = item.gear_score
		for affix_id in item.affixes:
			var affix: ItemDatabase.AffixDef = db.affixes.get(affix_id)
			var stat := affix.stat if affix else affix_id
			result.bonuses[stat] = result.bonus(stat) + item.affixes[affix_id]
	if total_weight > 0.0:
		result.average_gear_score = weighted / total_weight
	return result


## Equip slot -> Item.to_dict(), for the network.
func to_dict() -> Dictionary:
	var data := {}
	for equip_slot in items:
		data[equip_slot] = items[equip_slot].to_dict()
	return data


static func from_dict(data: Dictionary) -> Equipment:
	var equipment := Equipment.new()
	for equip_slot: String in data:
		if equip_slot in SLOTS:
			equipment.items[equip_slot] = Item.from_dict(data[equip_slot])
	return equipment
