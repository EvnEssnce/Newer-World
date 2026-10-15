class_name CharacterSave
extends RefCounted
## Everything a character keeps between sessions, as plain data: who it is
## (name, class, account) and the to_dict() of its build, inventory, equipment
## and tradeskills. Persistence stores and loads these; the server captures one
## from a player's live objects and rebuilds the objects from one. No database
## here, so it's unit tested on its own (tests/test_persistence.gd).
##
## Rebuilding goes through the same rules as play: CharacterBuild.apply_saved
## (refused parts keep the class default), Inventory.from_dict (capacity from
## data/), Tradeskills.from_dict (levels clamped to the cap), and
## drop_unknown_items for items whose definition left data/items.cfg.

## Database row id (0 = not stored yet) and the owning account's.
var id := 0
var account_id := 0
var name := ""
var class_id := ""
## CharacterBuild.to_dict(): weapons, allocations, slots, Wing tree and slots.
var build: Dictionary = {}
## Inventory.to_dict(): items (with uids and stack counts) and the next uid.
var inventory: Dictionary = {}
## Equipment.to_dict(): equip slot -> Item.to_dict().
var equipment: Dictionary = {}
## Tradeskills.to_dict(): skill id -> [level, xp].
var tradeskills: Dictionary = {}


## A save of a character's live objects (null ones are saved empty).
static func capture(char_name: String, char_build: CharacterBuild, bag: Inventory,
		gear: Equipment, skills: Tradeskills) -> CharacterSave:
	var save := CharacterSave.new()
	save.name = char_name
	if char_build:
		save.class_id = char_build.class_def.id
		save.build = char_build.to_dict()
	if bag:
		save.inventory = bag.to_dict()
	if gear:
		save.equipment = gear.to_dict()
	if skills:
		save.tradeskills = skills.to_dict()
	return save


## Puts the saved build on `fresh` (normally CharacterBuild.create_default of
## this class). Returns why any refused part was dropped.
func restore_build(fresh: CharacterBuild) -> PackedStringArray:
	return fresh.apply_saved(build)


func make_inventory(slots: int) -> Inventory:
	return Inventory.from_dict(inventory, slots)


func make_equipment() -> Equipment:
	return Equipment.from_dict(equipment)


func make_tradeskills(defs: TradeskillDefs) -> Tradeskills:
	return Tradeskills.from_dict(tradeskills, defs)


## A short hash of the four save parts as they'd be stored (whole floats read
## back as ints, as Persistence.decode does), so a save and the same character
## captured again after loading match exactly. The server logs it on every
## save and load; the smoke test's restart check compares the two.
func fingerprint() -> String:
	var parts := [build, inventory, equipment, tradeskills]
	return Persistence.encode(Persistence.decode(Persistence.encode(parts))).md5_text().substr(0, 12)


## For the server's log: "bag=12 equipped=3 skill_levels=9 skill_xp=140" (bag
## = slots used; skill totals over every tradeskill).
func summary_text() -> String:
	var levels := 0
	var xp := 0
	for entry: Variant in tradeskills.values():
		if entry is Array and entry.size() == 2:
			levels += int(entry[0])
			xp += int(entry[1])
	return "bag=%d equipped=%d skill_levels=%d skill_xp=%d" % [
			inventory.get("items", []).size(), equipment.size(), levels, xp]


## Removes bag and equipped items whose item id isn't in `db` any more (a
## definition renamed or removed from data/items.cfg). Returns their ids, for
## the server's log.
func drop_unknown_items(db: ItemDatabase) -> PackedStringArray:
	var dropped := PackedStringArray()
	var kept := []
	for entry: Variant in inventory.get("items", []):
		var item_id: String = entry.get("item", "") if entry is Dictionary else ""
		if db.items.has(item_id):
			kept.append(entry)
		else:
			dropped.append(item_id)
	if inventory.has("items"):
		inventory["items"] = kept
	for equip_slot: Variant in equipment.keys():
		var entry: Variant = equipment[equip_slot]
		var item_id: String = entry.get("item", "") if entry is Dictionary else ""
		if not db.items.has(item_id):
			dropped.append(item_id)
			equipment.erase(equip_slot)
	return dropped
