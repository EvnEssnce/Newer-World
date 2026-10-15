extends TestCase
## Persistence and CharacterSave: the bag/build/item round trips a save needs,
## saved builds going through the mastery rules, JSON columns, and the SQLite
## module against a temporary database (schema, migrations, accounts,
## characters, surviving a close and reopen). Objects are built by hand.

const DB_DIR := "user://test_persistence/"

var class_def: ClassDef
var trees: Dictionary
var skill_defs: TradeskillDefs
var item_db: ItemDatabase
var _paths: PackedStringArray = []


func before_each() -> void:
	class_def = ClassDef.new()
	class_def.id = "fighter"
	class_def.display_name = "Fighter"
	class_def.weapons = PackedStringArray(["sword", "axes", "spear"])
	class_def.default_loadout = PackedStringArray(["sword", "axes"])
	var sword_tree := _tree(["spin", "charge"])
	sword_tree.default_nodes = PackedStringArray(["spin_node"])
	sword_tree.default_slots = PackedStringArray(["spin", "", ""])
	var axes_tree := _tree(["frenzy", "leap"])
	axes_tree.default_nodes = PackedStringArray(["frenzy_node"])
	axes_tree.default_slots = PackedStringArray(["", "frenzy", ""])
	trees = {"sword": sword_tree, "axes": axes_tree, "spear": _tree(["thrust"])}

	skill_defs = TradeskillDefs.new()
	skill_defs.level_cap = 10
	skill_defs.xp_base = 100.0
	skill_defs.xp_exponent = 1.5
	skill_defs.add_skill("mining", "Mining", "gathering")
	skill_defs.add_skill("smelting", "Smelting", "refining")

	item_db = ItemDatabase.new()
	for id in ["sword", "cap", "ore"]:
		var def := ItemDatabase.ItemDef.new()
		def.id = id
		item_db.items[id] = def


func _tree(abilities: Array) -> MasteryTree:
	var t := MasteryTree.new()
	t.branches = PackedStringArray(["main", "other"])
	t.tier_requirements = PackedInt32Array([0, 2])
	t.points = 10
	for ability: String in abilities:
		t.add_node(ability + "_node", "main", 1, MasteryTree.KIND_ACTIVE, 1, ability)
	return t


func _gear(id: String, gear_score: int, primary: float) -> Item:
	var item := Item.new()
	item.item_id = id
	item.rarity = "rare"
	item.gear_score = gear_score
	item.primary_value = primary
	item.affixes = {"sear": 3.137, "vigor": 41.0}
	item.crafted = true
	return item


## A character with a changed build, a bag of gear and resource stacks, an
## equipped item and some tradeskill XP.
func _sample_save(char_name: String = "Ash") -> CharacterSave:
	var build := CharacterBuild.create(class_def, trees)
	assert_eq(build.set_weapons(PackedStringArray(["spear", "sword"])), "")
	assert_eq(build.set_mastery("sword", PackedStringArray(["spin_node", "charge_node"]),
			PackedStringArray(["charge", "spin", ""])), "")
	var bag := Inventory.new(10)
	bag.add(_gear("sword", 123, 128.71234567891234))
	bag.add_stack("ore", 130, 100)
	var gear := Equipment.new()
	gear.items["head"] = _gear("cap", 111, 17.5)
	var skills := Tradeskills.new(skill_defs)
	skills.add_xp("mining", 250)
	return CharacterSave.capture(char_name, build, bag, gear, skills)


func _open() -> Persistence:
	DirAccess.make_dir_recursive_absolute(DB_DIR)
	var path := DB_DIR + "test_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_paths.append(path)
	var p := Persistence.new()
	assert_true(p.open(path), "open: " + p.last_error)
	return p


func _reopen(p: Persistence) -> Persistence:
	p.close()
	var again := Persistence.new()
	assert_true(again.open(_paths[-1]), "reopen: " + again.last_error)
	return again


func _cleanup(p: Persistence) -> void:
	p.close()
	for path in _paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_paths.clear()


# --- Round trips without a database ---

func test_inventory_dict_round_trip_keeps_uids_counts_and_next_uid() -> void:
	var bag := Inventory.new(10)
	bag.add(_gear("sword", 123, 128.5))
	bag.add_stack("ore", 130, 100)
	var copy := Inventory.from_dict(bag.to_dict(), 10)
	assert_eq(copy.items.size(), 3)
	assert_eq(copy.to_array(), bag.to_array())
	assert_eq(copy.count_of("ore"), 130)
	copy.add(_gear("sword", 100, 100.0))
	assert_eq(copy.items[-1].uid, 4, "the next uid carries on")


func test_inventory_from_dict_keeps_everything_and_never_reuses_a_uid() -> void:
	var saved := {"items": [_gear("sword", 100, 100.0).to_dict(), _gear("sword", 100, 100.0).to_dict()],
			"next_uid": 1}
	saved["items"][0]["uid"] = 7
	saved["items"][1]["uid"] = 9
	var bag := Inventory.from_dict(saved, 1)
	assert_eq(bag.items.size(), 2, "kept past a smaller capacity")
	assert_true(bag.is_full())
	bag.capacity = 5
	bag.add(_gear("sword", 100, 100.0))
	assert_eq(bag.items[-1].uid, 10, "above every saved uid")


func test_saved_build_is_restored() -> void:
	var save := _sample_save()
	var build := CharacterBuild.create(class_def, trees)
	assert_eq(save.restore_build(build), PackedStringArray())
	assert_eq(build.weapons, PackedStringArray(["spear", "sword"]))
	assert_eq(build.get_allocated("sword"), PackedStringArray(["spin_node", "charge_node"]))
	assert_eq(build.get_slots("sword"), PackedStringArray(["charge", "spin", ""]))
	assert_eq(build.get_allocated("axes"), PackedStringArray(["frenzy_node"]), "unchanged tree")


func test_saved_build_parts_the_rules_refuse_keep_the_default() -> void:
	var build := CharacterBuild.create(class_def, trees)
	var problems := build.apply_saved({
		"weapons": ["sword", "bow"],
		"allocated": {"sword": ["gone_node"], "axes": ["leap_node"], "bow": []},
		"slots": {"sword": ["spin", "", ""], "axes": ["leap", "", ""]},
	})
	assert_eq(problems.size(), 3, "weapons, sword tree, unknown bow tree: %s" % [problems])
	assert_eq(build.weapons, class_def.default_loadout)
	assert_eq(build.get_allocated("sword"), PackedStringArray(["spin_node"]), "default kept")
	assert_eq(build.get_allocated("axes"), PackedStringArray(["leap_node"]), "valid part applied")
	assert_eq(build.get_slots("axes"), PackedStringArray(["leap", "", ""]))


func test_json_columns_round_trip_exactly() -> void:
	var value := {"gs": 123, "primary": 128.71234567891234, "list": [1, 2.5, "x"], "whole": 120.0,
			"nested": {"count": 100}}
	var back: Dictionary = Persistence.decode(Persistence.encode(value))
	assert_eq(back["gs"], 123)
	assert_eq(typeof(back["gs"]), TYPE_INT, "ints come back as ints")
	assert_eq(back["primary"], 128.71234567891234, "full precision")
	assert_eq(back["list"], [1, 2.5, "x"])
	assert_eq(back["nested"]["count"], 100)
	assert_eq(Persistence.decode("not json"), null)


func test_capture_and_rebuild_through_json() -> void:
	var save := _sample_save()
	var bag := Inventory.from_dict(Persistence.decode(Persistence.encode(save.inventory)), 10)
	assert_eq(bag.to_array(), save.make_inventory(10).to_array())
	var sword := bag.items[0]
	assert_eq(sword.item_id, "sword")
	assert_eq(sword.gear_score, 123)
	assert_eq(sword.primary_value, 128.71234567891234)
	assert_almost(sword.affixes["sear"], 3.137, 0.0)
	assert_almost(sword.affixes["vigor"], 41.0, 0.0)
	assert_true(sword.crafted)
	var gear := Equipment.from_dict(Persistence.decode(Persistence.encode(save.equipment)))
	assert_eq(gear.items["head"].item_id, "cap")
	var skills := Tradeskills.from_dict(Persistence.decode(Persistence.encode(save.tradeskills)),
			skill_defs)
	assert_eq(skills.level("mining"), save.make_tradeskills(skill_defs).level("mining"))
	assert_eq(skills.level("mining"), 2)
	assert_eq(skills.xp("mining"), 150)


func test_unknown_items_are_dropped() -> void:
	var save := _sample_save()
	save.inventory["items"][0]["item"] = "old_sword"
	save.equipment["head"]["item"] = "old_cap"
	var dropped := save.drop_unknown_items(item_db)
	assert_eq(dropped, PackedStringArray(["old_sword", "old_cap"]))
	assert_eq(save.make_inventory(10).count_of("ore"), 130, "ore stacks kept")
	assert_eq(save.make_inventory(10).items.size(), 2)
	assert_false(save.equipment.has("head"))


# --- The database ---

func test_open_creates_the_schema_once() -> void:
	var p := _open()
	assert_eq(p.schema_version(), Persistence.MIGRATIONS.size())
	assert_true(p.create_account("ember", "hash") > 0)
	p = _reopen(p)
	assert_eq(p.schema_version(), Persistence.MIGRATIONS.size(), "no migration runs twice")
	assert_false(p.find_account("ember").is_empty(), "data kept")
	_cleanup(p)


func test_a_newer_schema_is_refused() -> void:
	var p := _open()
	assert_true(p._run("PRAGMA user_version = 99;", []))
	p.close()
	var again := Persistence.new()
	assert_false(again.open(_paths[-1]))
	assert_true(again.last_error.contains("99"), again.last_error)
	assert_false(again.is_open())
	_cleanup(again)


func test_account_names_are_unique_ignoring_case() -> void:
	var p := _open()
	var id := p.create_account("Ember", "h1")
	assert_true(id > 0)
	assert_eq(p.create_account("ember", "h2"), 0)
	assert_true(p.last_error.contains("taken"), p.last_error)
	var found := p.find_account("EMBER")
	assert_eq(found.get("id"), id)
	assert_eq(found.get("name"), "Ember")
	assert_eq(found.get("password_hash"), "h1")
	assert_true(p.find_account("nobody").is_empty())
	_cleanup(p)


func test_character_round_trip() -> void:
	var p := _open()
	var account := p.create_account("ember", "hash")
	var save := _sample_save()
	var id := p.create_character(account, save)
	assert_true(id > 0, p.last_error)
	assert_eq(save.id, id)
	assert_eq(p.list_characters(account), [{"id": id, "name": "Ash", "class_id": "fighter"}])

	var loaded := p.load_character(id)
	assert_eq(loaded.name, "Ash")
	assert_eq(loaded.class_id, "fighter")
	assert_eq(loaded.account_id, account)
	assert_eq(loaded.make_inventory(10).to_array(), save.make_inventory(10).to_array())
	assert_eq(loaded.make_equipment().to_dict(), save.make_equipment().to_dict())
	assert_eq(loaded.make_tradeskills(skill_defs).to_dict(), save.tradeskills)
	var build := CharacterBuild.create(class_def, trees)
	assert_eq(loaded.restore_build(build), PackedStringArray())
	assert_eq(build.to_dict(), save.build)

	var bag := loaded.make_inventory(10)
	bag.remove_count("ore", 30)
	loaded.inventory = bag.to_dict()
	assert_true(p.save_character(loaded), p.last_error)
	assert_eq(p.load_character(id).make_inventory(10).count_of("ore"), 100)
	_cleanup(p)


func test_characters_survive_a_restart() -> void:
	var p := _open()
	var account := p.create_account("ember", "hash")
	var id := p.create_character(account, _sample_save())
	p = _reopen(p)
	var loaded := p.load_character(id)
	assert_true(loaded != null, p.last_error)
	if loaded:
		assert_eq(loaded.make_inventory(10).count_of("ore"), 130)
		assert_eq(loaded.make_tradeskills(skill_defs).level("mining"), 2)
	_cleanup(p)


func test_create_character_needs_an_account_and_a_free_name() -> void:
	var p := _open()
	assert_eq(p.create_character(42, _sample_save()), 0)
	assert_true(p.last_error.contains("account"), p.last_error)
	var account := p.create_account("ember", "hash")
	var other := p.create_account("cinder", "hash")
	assert_true(p.create_character(account, _sample_save("Ash")) > 0)
	assert_eq(p.create_character(other, _sample_save("ASH")), 0)
	assert_true(p.last_error.contains("taken"), p.last_error)
	assert_true(p.list_characters(other).is_empty())
	_cleanup(p)


func test_saving_everyone_is_all_or_nothing() -> void:
	var p := _open()
	var account := p.create_account("ember", "hash")
	var ash := _sample_save("Ash")
	p.create_character(account, ash)
	ash.tradeskills = {"mining": [5, 0]}
	var ghost := _sample_save("Ghost")
	ghost.id = 999
	var saves: Array[CharacterSave] = [ash, ghost]
	assert_false(p.save_characters(saves))
	assert_eq(p.load_character(ash.id).tradeskills["mining"][0], 2, "rolled back")
	saves = [ash]
	assert_true(p.save_characters(saves), p.last_error)
	assert_eq(p.load_character(ash.id).tradeskills["mining"][0], 5)
	_cleanup(p)


func test_delete_character() -> void:
	var p := _open()
	var account := p.create_account("ember", "hash")
	var id := p.create_character(account, _sample_save())
	assert_true(p.delete_character(id))
	assert_eq(p.load_character(id), null)
	assert_false(p.delete_character(id))
	assert_true(p.list_characters(account).is_empty())
	_cleanup(p)
