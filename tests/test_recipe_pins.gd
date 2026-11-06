extends TestCase
## RecipePins (pinned recipes) and the Forge panel's tabs (CraftingPanel.tab_of
## / tabs_for), built by hand.

const PATH := "user://test_recipe_pins.cfg"



func test_toggle_and_cap() -> void:
	var pins := RecipePins.new()
	assert_true(pins.toggle("a"))
	assert_true(pins.is_pinned("a"))
	assert_true(pins.toggle("a"), "unpinning works")
	assert_false(pins.is_pinned("a"))
	for i in RecipePins.MAX_PINS:
		assert_true(pins.toggle("r%d" % i))
	assert_false(pins.toggle("one_more"), "full")
	assert_false(pins.is_pinned("one_more"))


func test_save_load_and_unknown_recipes() -> void:
	var pins := RecipePins.new()
	pins.toggle("iron_spear")
	pins.toggle("gone")
	pins.save(PATH)
	var back := RecipePins.load_from(PATH)
	assert_eq(back.ids, PackedStringArray(["iron_spear", "gone"]))
	back.keep_only(["iron_spear", "pine_plank"])
	assert_eq(back.ids, PackedStringArray(["iron_spear"]))
	assert_eq(RecipePins.load_from("user://no_such_file.cfg").ids.size(), 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _recipe(id: String, skill: String) -> RecipeDefs.Recipe:
	var r := RecipeDefs.Recipe.new()
	r.id = id
	r.tradeskill = skill
	return r


func test_forge_tabs() -> void:
	var skills := TradeskillDefs.new()
	skills.add_skill("mining", "Mining", "gathering")
	skills.add_skill("smelting", "Smelting", "refining")
	skills.add_skill("spinning", "Spinning", "refining")
	skills.add_skill("weaponsmithing", "Weaponforging", "crafting")
	skills.add_skill("armoring", "Armorcraft", "crafting")
	var recipes: Array[RecipeDefs.Recipe] = [_recipe("cap", "armoring"),
			_recipe("ingot", "smelting"), _recipe("spear", "weaponsmithing"), _recipe("linen", "spinning")]
	assert_eq(CraftingPanel.tab_of(recipes[1], skills), CraftingPanel.TAB_REFINING)
	assert_eq(CraftingPanel.tab_of(recipes[0], skills), "armoring")
	assert_eq(CraftingPanel.tabs_for(recipes, skills, false),
			PackedStringArray(["refining", "weaponsmithing", "armoring"]))
	assert_eq(CraftingPanel.tabs_for(recipes, skills, true)[0], CraftingPanel.TAB_PINNED)
	assert_eq(CraftingPanel.tab_title("weaponsmithing", skills), "Weaponforging")
	assert_eq(CraftingPanel.tab_title(CraftingPanel.TAB_REFINING, skills), "Refining")
