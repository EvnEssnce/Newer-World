extends TestCase
## Mage rules: silence in the sim, healing taken/dealt modifiers (Withered,
## Phoenix Aura), Ward's absorb status, the Ascendant cooldown refund as a
## server event, the class's Ember gain, ramping channels, and (last tests) the
## Mage's data.

var defs: StatusDefs
var silenced: int
var withered: int
var aura: int
var ward: int


func before_each() -> void:
	defs = StatusDefs.new()
	var d := StatusDef.new()
	d.id = "silenced"
	d.affects = StatusDef.AFFECTS_SIM
	d.duration_ticks = 180
	d.silences = true
	silenced = defs.add(d)
	d = StatusDef.new()
	d.id = "withered"
	d.duration_ticks = 300
	d.healing_taken = -0.5
	withered = defs.add(d)
	d = StatusDef.new()
	d.id = "phoenix_aura"
	d.category = StatusDef.CATEGORY_BUFF
	d.duration_ticks = 360
	d.healing_dealt = 0.2
	aura = defs.add(d)
	d = StatusDef.new()
	d.id = "ward"
	d.category = StatusDef.CATEGORY_BUFF
	d.duration_ticks = 480
	d.absorbs = true
	ward = defs.add(d)


func test_silence_is_crowd_control_and_sim() -> void:
	assert_true(defs.get_def(silenced).is_crowd_control())
	assert_eq(defs.validate(), "")
	defs.get_def(silenced).affects = StatusDef.AFFECTS_DAMAGE
	assert_true(defs.validate().contains("sim"))


func test_silence_stops_abilities_in_the_sim() -> void:
	# Built on the real tuning: a Fighter's weapons.
	var p := PlayerParams.current()
	var state := PlayerState.new()
	state.stamina = p.max_stamina
	state.set_loadout(PackedStringArray(["broadsword", "spear"]), PackedInt32Array([0, 1, 2, 0, 1, 2]))
	var silence := p.statuses.index_of("silenced")
	state.statuses.apply(p.statuses, silence)
	state.step(Vector2.ZERO, PlayerState.BUTTON_ABILITY_1, 0.0, true, p, 1.0 / 60.0)
	assert_false(state.is_using_ability(), "silenced: no ability")
	state.statuses.remove(silence)
	state.step(Vector2.ZERO, PlayerState.BUTTON_ABILITY_1, 0.0, true, p, 1.0 / 60.0)
	assert_true(state.is_using_ability(), "the buffered press starts once it's gone")


func test_healing_taken_and_dealt() -> void:
	var s := StatusEffects.new()
	assert_almost(s.healing_multiplier(defs, false), 1.0)
	s.apply(defs, withered)
	s.apply(defs, aura)
	assert_almost(s.healing_multiplier(defs, false), 0.5, 0.001, "taken: Withered")
	assert_almost(s.healing_multiplier(defs, true), 1.2, 0.001, "dealt: Phoenix Aura")


func test_ward_is_the_absorb_status() -> void:
	var s := StatusEffects.new()
	assert_eq(s.absorb_status(defs), -1)
	s.apply(defs, ward)
	assert_eq(s.absorb_status(defs), ward)


func test_cooldown_refund_is_a_server_event() -> void:
	var state := PlayerState.new()
	var events := state.server_events
	state.reduce_ability_cooldowns(0.5)
	assert_eq(state.server_events, events, "nothing on cooldown: no event")
	state.cooldowns[2] = 300
	state.reduce_ability_cooldowns(0.5)
	assert_eq(state.cooldowns[2], 150)
	assert_eq(state.server_events, events + 1)


func test_window_index_for_a_ramping_channel() -> void:
	var a := AttackParams.new()
	a.windup_ticks = 12
	a.active_ticks = 7
	a.windows = 6
	a.window_interval_ticks = 15
	a.window_ramp = 0.3
	assert_eq(a.window_at(12), 0)
	assert_eq(a.window_at(12 + 15 * 5), 5)
	assert_almost(1.0 + a.window_ramp * a.window_at(12 + 15 * 5), 2.5, 0.001, "the last pulse")


# --- Data ---

func test_mage_class_gains_more_ember() -> void:
	assert_almost(ClassDef.for_id("mage").ember_gain, 2.0)
	assert_almost(ClassDef.for_id("fighter").ember_gain, 1.0)


func test_mage_wing_tree_default_build_is_valid() -> void:
	var t := MasteryTree.for_wings("mage")
	assert_true(t != null, "data/mastery_wings_mage.cfg")
	assert_eq(t.validate(t.default_nodes), "", "default nodes")
	assert_eq(t.validate_slots(t.default_nodes, t.default_slots), "", "default slots")
	var wings := PlayerParams.current().wing_set("mage")
	for id in t.node_order:
		var n := t.get_node(id)
		if n.kind == MasteryTree.KIND_ACTIVE:
			assert_true(wings.ability_index(n.ability) >= 0, "%s's ability %s" % [id, n.ability])


func test_mage_abilities_cost_ember() -> void:
	var staff := PlayerParams.current().weapon("great_staff")
	for ability in staff.abilities:
		assert_true(ability.ember_cost > 0.0, ability.id)
