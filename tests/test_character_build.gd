extends TestCase
## ClassDef weapon restrictions and CharacterBuild: defaults, validated
## mastery/slot changes, and what goes into PlayerState. Built by hand.

var class_def: ClassDef
var trees: Dictionary
var params: PlayerParams


func before_each() -> void:
	class_def = ClassDef.new()
	class_def.id = "fighter"
	class_def.display_name = "Fighter"
	class_def.weapons = PackedStringArray(["sword", "axes"])
	class_def.default_loadout = PackedStringArray(["sword", "axes"])

	var sword_tree := _tree(["spin", "charge"])
	sword_tree.default_nodes = PackedStringArray(["spin_node", "charge_node"])
	sword_tree.default_slots = PackedStringArray(["spin", "charge", ""])
	var axes_tree := _tree(["frenzy", "leap"])
	axes_tree.default_nodes = PackedStringArray(["frenzy_node"])
	axes_tree.default_slots = PackedStringArray(["", "frenzy", ""])
	trees = {"sword": sword_tree, "axes": axes_tree}

	params = PlayerParams.new()
	params.weapons = {"sword": _weapon("sword", ["counter", "spin", "charge"]),
			"axes": _weapon("axes", ["frenzy", "leap"]),
			"bow": _weapon("bow", ["volley"])}
	params.weapons["sword"].abilities[0].internal = true


## A one-branch tree with an active tier-1 node per ability ("<ability>_node").
func _tree(abilities: Array) -> MasteryTree:
	var t := MasteryTree.new()
	t.branches = PackedStringArray(["main", "other"])
	t.tier_requirements = PackedInt32Array([0, 2])
	t.points = 10
	for ability: String in abilities:
		t.add_node(ability + "_node", "main", 1, MasteryTree.KIND_ACTIVE, 1, ability)
	return t


func _weapon(id: String, abilities: Array) -> WeaponParams:
	var w := WeaponParams.new()
	w.id = id
	for ability_id: String in abilities:
		var a := AbilityParams.new()
		a.id = ability_id
		w.abilities.append(a)
	return w


func _build() -> CharacterBuild:
	return CharacterBuild.create(class_def, trees)


func test_class_allows_only_its_weapons() -> void:
	assert_true(class_def.allows_weapon("sword"))
	assert_false(class_def.allows_weapon("bow"))


func test_loadout_must_be_two_different_class_weapons() -> void:
	assert_eq(class_def.validate_loadout(PackedStringArray(["axes", "sword"])), "")
	assert_true(class_def.validate_loadout(PackedStringArray(["sword", "bow"])) != "", "other class")
	assert_true(class_def.validate_loadout(PackedStringArray(["sword", "sword"])) != "", "twice")
	assert_true(class_def.validate_loadout(PackedStringArray(["sword"])) != "", "one")
	assert_true(class_def.validate_loadout(PackedStringArray(["sword", "axes", "axes"])) != "", "three")


func test_build_rejects_other_class_weapons() -> void:
	var build := _build()
	assert_true(build.set_weapons(PackedStringArray(["bow", "axes"])) != "")
	assert_eq(build.weapons, PackedStringArray(["sword", "axes"]), "unchanged")
	assert_true(build.set_mastery("bow", PackedStringArray(), PackedStringArray(["", "", ""])) != "")


func test_default_build() -> void:
	var build := _build()
	assert_eq(build.weapons, class_def.default_loadout)
	assert_eq(build.get_allocated("sword"), PackedStringArray(["spin_node", "charge_node"]))
	assert_eq(build.get_slots("axes"), PackedStringArray(["", "frenzy", ""]))


func test_invalid_default_slots_are_emptied() -> void:
	trees["axes"].default_slots = PackedStringArray(["leap", "", ""])  # leap not learned
	assert_eq(_build().get_slots("axes"), PackedStringArray(["", "", ""]))


func test_slotting_requires_the_unlock() -> void:
	var build := _build()
	var error := build.set_mastery("axes", PackedStringArray(["frenzy_node"]),
			PackedStringArray(["leap", "", ""]))
	assert_true(error != "")
	assert_eq(build.get_slots("axes"), PackedStringArray(["", "frenzy", ""]), "unchanged")


func test_respec_replaces_allocation_and_slots() -> void:
	var build := _build()
	var error := build.set_mastery("axes", PackedStringArray(["leap_node", "frenzy_node"]),
			PackedStringArray(["leap", "", "frenzy"]))
	assert_eq(error, "")
	assert_eq(build.get_allocated("axes"), PackedStringArray(["leap_node", "frenzy_node"]))
	assert_eq(build.get_slots("axes"), PackedStringArray(["leap", "", "frenzy"]))
	assert_eq(build.set_mastery("axes", PackedStringArray(), PackedStringArray(["", "", ""])), "",
			"unlearning everything is a valid respec")


func test_invalid_tree_is_rejected() -> void:
	var build := _build()
	trees["axes"].points = 1
	var error := build.set_mastery("axes", PackedStringArray(["leap_node", "frenzy_node"]),
			PackedStringArray(["", "", ""]))
	assert_true(error != "")


func test_state_slots_are_pool_indices() -> void:
	var build := _build()
	# sword pool: counter(0), spin(1), charge(2); axes pool: frenzy(0), leap(1).
	assert_eq(build.state_slots(params), PackedInt32Array([1, 2, -1, -1, 0, -1]))


func test_internal_abilities_never_reach_a_slot() -> void:
	var build := _build()
	build.slots["sword"] = PackedStringArray(["counter", "", ""])
	assert_eq(build.state_slots(params)[0], -1)


func test_apply_to_state() -> void:
	var build := _build()
	var state := PlayerState.new()
	var events := state.server_events
	build.apply_to_state(state, params)
	assert_eq(state.weapons, PackedStringArray(["sword", "axes"]))
	assert_eq(state.ability_slots, PackedInt32Array([1, 2, -1, -1, 0, -1]))
	assert_eq(state.server_events, events + 1, "a server event for prediction")


func test_swapping_weapon_order_follows_through_to_state() -> void:
	var build := _build()
	var state := PlayerState.new()
	build.apply_to_state(state, params)
	assert_eq(build.set_weapons(PackedStringArray(["axes", "sword"])), "")
	build.apply_to_state(state, params)
	assert_eq(state.weapons, PackedStringArray(["axes", "sword"]))
	assert_eq(state.ability_slots, PackedInt32Array([-1, 0, -1, 1, 2, -1]))


# --- Choosing two of three class weapons (K panel) ---

func _three_weapon_class() -> void:
	class_def.weapons = PackedStringArray(["sword", "spear", "axes"])
	var spear_tree := _tree(["lunge"])
	spear_tree.default_nodes = PackedStringArray(["lunge_node"])
	spear_tree.default_slots = PackedStringArray(["lunge", "", ""])
	trees["spear"] = spear_tree
	params.weapons["spear"] = _weapon("spear", ["lunge"])


func test_any_two_distinct_class_weapons_can_be_equipped() -> void:
	_three_weapon_class()
	for pair: Array in [["sword", "spear"], ["spear", "axes"], ["axes", "sword"], ["spear", "sword"]]:
		assert_eq(class_def.validate_loadout(PackedStringArray(pair)), "", str(pair))
	assert_true(class_def.validate_loadout(PackedStringArray(["spear", "spear"])) != "", "twice")
	assert_true(class_def.validate_loadout(PackedStringArray(["spear", "bow"])) != "", "other class")


func test_equipping_the_third_weapon_reaches_state() -> void:
	_three_weapon_class()
	var build := _build()
	var state := PlayerState.new()
	build.apply_to_state(state, params)
	assert_eq(build.set_weapons(PackedStringArray(["sword", "spear"])), "")
	build.apply_to_state(state, params)
	assert_eq(state.weapons, PackedStringArray(["sword", "spear"]))
	assert_eq(state.ability_slots, PackedInt32Array([1, 2, -1, 0, -1, -1]), "spear's Lunge on Q")


func test_loadout_with_replaces_or_swaps() -> void:
	var current := PackedStringArray(["sword", "axes"])
	assert_eq(CharacterBuild.loadout_with(current, 1, "spear"), PackedStringArray(["sword", "spear"]))
	assert_eq(CharacterBuild.loadout_with(current, 0, "spear"), PackedStringArray(["spear", "axes"]))
	assert_eq(CharacterBuild.loadout_with(current, 0, "axes"), PackedStringArray(["axes", "sword"]),
			"picking the other slot's weapon swaps them")
	assert_eq(CharacterBuild.loadout_with(current, 0, "sword"), current, "no change")
	assert_eq(current, PackedStringArray(["sword", "axes"]), "input untouched")


# --- Tree points from levels (build order 4.3) ---

func test_a_point_limit_lowers_the_budget() -> void:
	var tree: MasteryTree = trees["sword"]
	var both := PackedStringArray(["spin_node", "charge_node"])
	assert_eq(tree.budget(), 10)
	assert_eq(tree.budget(1), 1)
	assert_eq(tree.budget(50), 10, "never over the tree's own points")
	assert_eq(tree.validate(both), "")
	assert_eq(tree.validate(both, 1), "Not enough points (2 of 1).")
	assert_false(tree.can_add(PackedStringArray(["spin_node"]), "charge_node", 1))
	assert_true(tree.can_add(PackedStringArray(["spin_node"]), "charge_node", 2))


func test_fit_keeps_slotted_abilities_first() -> void:
	var tree: MasteryTree = trees["sword"]
	tree.add_node("edge", "main", 1, MasteryTree.KIND_PASSIVE, 1, "")
	var nodes := PackedStringArray(["edge", "spin_node", "charge_node"])
	var slots := PackedStringArray(["", "charge", ""])
	var fitted := tree.fit(nodes, slots, 1)
	assert_eq(fitted[0], PackedStringArray(["charge_node"]))
	assert_eq(fitted[1], slots)
	fitted = tree.fit(nodes, PackedStringArray(["spin", "", ""]), 0)
	assert_eq(fitted[0], PackedStringArray())
	assert_eq(fitted[1], PackedStringArray(["", "", ""]), "slots lose what's no longer learned")
	assert_eq(tree.fit(nodes, slots, 3)[0], nodes, "unchanged when it fits")


func test_point_limits_cut_trees_and_refuse_more() -> void:
	var build := _build()
	var cut := build.set_point_limits({"sword": 1} as Dictionary[String, int], -1)
	assert_eq(cut, PackedStringArray(["sword: 2 -> 1 points"]))
	assert_eq(build.get_allocated("sword"), PackedStringArray(["spin_node"]))
	assert_eq(build.get_slots("sword"), PackedStringArray(["spin", "", ""]))
	assert_eq(build.get_allocated("axes"), PackedStringArray(["frenzy_node"]), "no limit")
	assert_true(build.set_mastery("sword", PackedStringArray(["spin_node", "charge_node"]),
			PackedStringArray(["spin", "charge", ""])) != "", "over the limit")
	assert_eq(build.set_point_limits({"sword": 2} as Dictionary[String, int], -1), PackedStringArray(),
			"a higher limit cuts nothing")
	assert_eq(build.set_mastery("sword", PackedStringArray(["spin_node", "charge_node"]),
			PackedStringArray(["spin", "charge", ""])), "")
	assert_eq(build.point_limit("axes"), -1)


func test_limits_reach_the_client_but_not_saves() -> void:
	var build := CharacterBuild.create_default(ClassDef.for_id("fighter"))
	build.set_point_limits({"spear": 4} as Dictionary[String, int], 3)
	assert_false(build.to_dict().has("limits"))
	var copy := CharacterBuild.from_dict(build.to_dict(true))
	assert_eq(copy.point_limit("spear"), 4)
	assert_eq(copy.point_limit("broadsword"), -1)
	assert_eq(copy.wing_point_limit, 3)


## The real data: a new character (level 1 everywhere, the real start points)
## keeps at least one slotted ability on every weapon and in its Wing slots.
func test_every_class_starts_with_abilities_at_level_one() -> void:
	var defs := ProgressionDefs.from_tuning()
	var levels := Progression.new(defs)
	for class_id in ClassDef.all_ids():
		var build := CharacterBuild.create_default(ClassDef.for_id(class_id))
		var limits: Dictionary[String, int] = {}
		for weapon_id: String in build.trees:
			limits[weapon_id] = levels.weapon_points(weapon_id)
		build.set_point_limits(limits, levels.wing_points())
		for weapon_id: String in build.trees:
			assert_true(build.get_slots(weapon_id).count("") < PlayerState.ABILITY_SLOTS,
					"%s %s keeps an ability" % [class_id, weapon_id])
		if build.wing_tree:
			assert_true(build.wing_slots.count("") < PlayerState.WING_SLOTS,
					"%s Wings keep an ability" % class_id)
