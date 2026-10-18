extends TestCase
## Class bonus stats from levels past a full Wing tree (ClassDef.level_bonus,
## the sim's parts in PlayerState) and the real Wing trees, which fill exactly
## at character level 20. Built by hand except the real-data test.


func _class(stat: String, per_point: float) -> ClassDef:
	var c := ClassDef.new()
	c.level_bonus_stat = stat
	c.level_bonus_per_point = per_point
	return c


func test_bonus_amounts_and_text() -> void:
	var fighter := _class("damage", 0.01)
	assert_true(absf(fighter.level_bonus(3) - 0.03) < 1e-9)
	assert_eq(fighter.level_bonus(-2), 0.0, "never negative")
	assert_eq(fighter.level_bonus_text(3), "+3% damage")
	assert_eq(_class("max_health", 20.0).level_bonus_text(3), "+60 max health")
	assert_eq(_class("move_speed", 0.01).level_bonus_text(10), "+10% movement speed")
	assert_eq(_class("dodge_cost", 0.02).level_bonus_text(10), "-20% dodge stamina")
	assert_eq(_class("ember_cost", 0.02).level_bonus_text(1), "-2% Ember cost")
	assert_eq(_class("healing", 0.02).level_bonus_text(5), "+10% healing")
	assert_eq(_class("", 0.5).level_bonus(4), 0.0, "no stat, no bonus")
	assert_eq(fighter.level_bonus_text(0), "")


func test_sim_bonuses_cut_roll_and_ability_costs() -> void:
	var params := PlayerParams.new()
	params.statuses = StatusDefs.new()
	params.dodge_stamina_cost = 20.0
	var state := PlayerState.new()
	var ability := AbilityParams.new()
	ability.ember_cost = 25.0
	assert_eq(state.dodge_cost(params), 20.0)
	assert_eq(state.ember_cost_of(ability), 25.0)
	var events := state.server_events
	state.set_level_bonus(100, 200, 200)
	assert_eq(state.server_events, events + 1, "a server event")
	assert_true(absf(state.dodge_cost(params) - 16.0) < 1e-6)
	assert_true(absf(state.ember_cost_of(ability) - 20.0) < 1e-6)
	assert_true(absf(state.bonus_move_multiplier() - 1.1) < 1e-6)
	state.ember = 21.0
	assert_true(state.can_afford(ability), "21 Ember pays a 20 cost")
	state.set_level_bonus(100, 200, 200)
	assert_eq(state.server_events, events + 1, "no change, no event")


func test_sim_bonuses_are_synced_to_the_owner_only() -> void:
	var state := PlayerState.new()
	state.set_level_bonus(50, 0, 140)
	var copy := PlayerState.from_array(state.to_array())
	assert_eq(copy.bonus_move_pm, 50)
	assert_eq(copy.bonus_ember_cut_pm, 140)
	assert_true(copy.matches(state))
	var view := PlayerState.from_array(state.view_array())
	assert_eq(view.bonus_move_pm, 0, "others don't need it")


## The real data: every Wing tree costs exactly its budget, which the
## character level reaches at 20 and not before; levels 21-30 are 10 bonus
## points; every class has a level bonus stat.
func test_real_wing_trees_fill_at_level_twenty() -> void:
	var defs := ProgressionDefs.from_tuning()
	for class_id in ClassDef.all_ids():
		var tree := MasteryTree.for_wings(class_id)
		var cost := tree.spent(tree.node_order)
		assert_eq(cost, tree.points, "%s: the whole tree fits the budget" % class_id)
		assert_eq(defs.wing_points(20), tree.points, "%s: full at 20" % class_id)
		assert_true(defs.wing_points(19) < tree.points, "%s: not before" % class_id)
		assert_eq(defs.wing_points(defs.character.level_cap) - tree.points, 10,
				"%s: 10 bonus points by level 30" % class_id)
		assert_true(ClassDef.for_id(class_id).level_bonus_stat in ClassDef.LEVEL_BONUS_STATS,
				"%s has a level bonus" % class_id)
