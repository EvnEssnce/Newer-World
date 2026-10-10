extends TestCase
## Paladin rules: Consecrating's hit heals, Guardian Link's damage share, the
## Rebirth discount and extra Rebirths (Phoenix Blessing), a zone that touches
## both sides, and (last tests) the Paladin's data.

var defs: StatusDefs
var consecrating: int
var link: int


func before_each() -> void:
	defs = StatusDefs.new()
	var d := StatusDef.new()
	d.id = "consecrating"
	d.category = StatusDef.CATEGORY_BUFF
	d.duration_ticks = 360
	d.hit_heal = 15.0
	d.hit_heal_radius = 6.0
	consecrating = defs.add(d)
	d = StatusDef.new()
	d.id = "guardian_link"
	d.category = StatusDef.CATEGORY_BUFF
	d.duration_ticks = 480
	d.damage_share = 0.3
	link = defs.add(d)


func test_consecrating_heal_and_radius() -> void:
	var s := StatusEffects.new()
	assert_eq(s.hit_heal(defs), Vector2.ZERO)
	s.apply(defs, consecrating)
	assert_eq(s.hit_heal(defs), Vector2(15.0, 6.0))


func test_guardian_link_share_and_source() -> void:
	var s := StatusEffects.new()
	assert_eq(s.damage_share(defs)[0], -1)
	s.apply(defs, link, 1, -1, 42)
	var share := s.damage_share(defs)
	assert_eq(share[0], link)
	assert_almost(share[1], 0.3)
	assert_eq(s.source_of(link), 42, "the guardian")


func _rebirth_params() -> PlayerParams:
	var p := PlayerParams.new()
	p.statuses = defs
	p.rebirth_threshold = 50.0
	p.rebirth_cost = 50.0
	p.rebirth_cooldown_ticks = 1000
	p.rebirth_ticks = 60
	return p


func test_rebirth_discount_lets_a_short_player_rise() -> void:
	var p := _rebirth_params()
	var state := PlayerState.new()
	state.ember = 42.0
	state.kill()
	assert_false(state.can_rebirth(p), "8 Ember short")
	assert_true(state.can_rebirth(p, 10.0), "a Purifier nearby lets off 10")
	assert_true(state.start_rebirth(p, 10.0))
	assert_almost(state.ember, 0.0, 0.001, "the cost is still spent (what there is)")


func test_blessing_charge_comes_and_goes() -> void:
	var p := _rebirth_params()
	var state := PlayerState.new()
	state.rebirth_cooldown = 500
	state.ember = 80.0
	state.grant_rebirth_charge()
	var events := state.server_events
	state.remove_rebirth_charge()
	assert_eq(state.rebirth_charges, 0)
	assert_eq(state.server_events, events + 1)
	state.remove_rebirth_charge()
	assert_eq(state.server_events, events + 1, "none left: no event")
	assert_false(state.can_rebirth(p), "on cooldown, no charge")


func test_both_sides_zone() -> void:
	assert_eq(ZoneParams.get_kind("sanctified_ground").affects, ZoneParams.AFFECTS_BOTH)
	var wings := ZoneParams.get_kind("sheltering_wings")
	assert_true(wings.solid and not wings.blocks_enemies, "stops projectiles, not people")


# --- Data ---

func test_paladin_wing_tree_default_build_is_valid() -> void:
	var t := MasteryTree.for_wings("paladin")
	assert_true(t != null, "data/mastery_wings_paladin.cfg")
	assert_eq(t.validate(t.default_nodes), "", "default nodes")
	assert_eq(t.validate_slots(t.default_nodes, t.default_slots), "", "default slots")
	var wings := PlayerParams.current().wing_set("paladin")
	for id in t.node_order:
		var n := t.get_node(id)
		if n.kind == MasteryTree.KIND_ACTIVE:
			assert_true(wings.ability_index(n.ability) >= 0, "%s's ability %s" % [id, n.ability])


func test_devotion_capstone_has_a_count() -> void:
	var t := MasteryTree.for_weapon("dual_shortstaffs")
	assert_eq(t.get_node("radiant_rhythm").count, 4)
