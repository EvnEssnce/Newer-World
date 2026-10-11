extends TestCase
## Changing class in-game (a test tool, BuildService._request_class): when
## PlayerState allows it, the clean start reset_for_class_change gives, and
## which gear has to come off (Equipment.slots_off_for_class). Built by hand.

var params: PlayerParams
var state: PlayerState


func before_each() -> void:
	params = PlayerParams.new()
	params.max_stamina = 100.0
	params.ember_resting = 50.0
	var defs := StatusDefs.new()
	var bleed := StatusDef.new()
	bleed.id = "bleed"
	bleed.category = StatusDef.CATEGORY_DEBUFF
	bleed.duration_ticks = 120
	bleed.max_stacks = 3
	defs.add(bleed)
	params.statuses = defs
	state = PlayerState.new()
	state.stamina = params.max_stamina


# --- When ---

func test_allowed_when_idle() -> void:
	assert_eq(state.class_change_error(), "")


func test_refused_while_defeated() -> void:
	state.kill()
	assert_true(state.class_change_error().contains("defeated"))


func test_refused_in_combat() -> void:
	state.combat_ticks = 90
	assert_true(state.class_change_error().contains("combat"))
	state.combat_ticks = 0
	assert_eq(state.class_change_error(), "")


func test_refused_mid_action() -> void:
	state.attack_tick = 3
	assert_false(state.class_change_error().is_empty(), "mid-attack")
	state.attack_tick = -1
	state.swap_tick = 2
	assert_false(state.class_change_error().is_empty(), "mid-swap")
	state.swap_tick = -1
	state.equip_left = 10
	assert_false(state.class_change_error().is_empty(), "changing gear")
	state.equip_left = 0
	state.dodge_tick = 4
	assert_false(state.class_change_error().is_empty(), "rolling")
	state.dodge_tick = -1
	state.stagger_ticks = 6
	assert_false(state.class_change_error().is_empty(), "staggered")


# --- The clean start ---

func test_reset_is_a_clean_start() -> void:
	state.stamina = 12.0
	state.stamina_regen_wait = 30
	state.statuses.apply(params.statuses, 0, 2)
	state.ember = 88.0
	state.cooldowns[2] = 400
	state.wing_cooldowns[1] = 900
	state.dodge_cooldown = 20
	state.rebirth_cooldown = 18000
	state.rebirth_charges = 1
	state.spare_charges = 3
	state.equipped = 1
	state.blocking = true
	state.queued_attack = PlayerState.ATTACK_ABILITY
	state.queued_ability_slot = 2
	state.attack_speed_carry = 0.5
	var events := state.server_events
	state.reset_for_class_change(params)
	assert_eq(state.stamina, 100.0)
	assert_eq(state.stamina_regen_wait, 0)
	assert_true(state.statuses.is_empty())
	assert_eq(state.ember, 50.0)
	assert_eq(state.cooldowns.count(0), state.cooldowns.size())
	assert_eq(state.wing_cooldowns.count(0), state.wing_cooldowns.size())
	assert_eq(state.dodge_cooldown, 0)
	assert_eq(state.rebirth_cooldown, 0)
	assert_eq(state.rebirth_charges, 0)
	assert_eq(state.spare_charges, 0)
	assert_eq(state.equipped, 0)
	assert_false(state.blocking)
	assert_eq(state.queued_attack, PlayerState.ATTACK_NONE)
	assert_eq(state.queued_ability_slot, -1)
	assert_eq(state.attack_speed_carry, 0.0)
	assert_eq(state.server_events, events + 1, "a server event, so prediction takes it")


func test_new_loadout_after_reset_has_no_cooldowns() -> void:
	state.set_loadout(PackedStringArray(["sword", "axes"]), PackedInt32Array([0, 1, 2, 0, 1, 2]))
	state.cooldowns[0] = 300
	state.reset_for_class_change(params)
	state.set_loadout(PackedStringArray(["hammer", "halberd"]), PackedInt32Array([0, -1, -1, 1, -1, -1]))
	assert_eq(state.weapons, PackedStringArray(["hammer", "halberd"]))
	assert_eq(state.cooldowns.count(0), state.cooldowns.size())
	assert_eq(state.equipped, 0)


# --- Gear ---

func _gear_db() -> ItemDatabase:
	var db := ItemDatabase.new()
	db.gear = GearScore.new()
	for row in [["sword", "weapon", "broadsword", ""], ["maul", "weapon", "war_hammer", ""],
			["cap", "head", "", ""], ["plumes", "wings", "", "fighter"]]:
		var def := ItemDatabase.ItemDef.new()
		def.id = row[0]
		def.name = row[0].capitalize()
		def.slot = row[1]
		def.weapon_type = row[2]
		def.class_id = row[3]
		db.items[def.id] = def
	return db


func _item(id: String) -> Item:
	var item := Item.new()
	item.item_id = id
	item.rarity = "common"
	item.gear_score = 100
	return item


func test_other_class_gear_comes_off() -> void:
	var db := _gear_db()
	var worn := Equipment.new()
	worn.equip("weapon_1", _item("sword"))
	worn.equip("head", _item("cap"))
	worn.equip("wings", _item("plumes"))
	var juggernaut := PackedStringArray(["halberd", "greataxe", "war_hammer"])
	assert_eq(worn.slots_off_for_class(db, "juggernaut", juggernaut),
			PackedStringArray(["weapon_1", "wings"]), "the Fighter's sword and Wing Enhancement")
	var fighter := PackedStringArray(["broadsword", "spear", "dual_axes"])
	assert_eq(worn.slots_off_for_class(db, "fighter", fighter), PackedStringArray(),
			"its own class keeps everything")


func test_armor_stays_on() -> void:
	var db := _gear_db()
	var worn := Equipment.new()
	worn.equip("head", _item("cap"))
	assert_eq(worn.slots_off_for_class(db, "mage", PackedStringArray(["great_staff"])),
			PackedStringArray())
