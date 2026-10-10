class_name InventoryPanel
extends Control
## The inventory (I, client only, built in code). Top: your equipped gear, one
## row per equip slot with a Take off button, your average gear score and what
## your gear adds up to (armor and its damage reduction, bonuses). Below: every
## item you carry, newest first, with its rarity colour, kind, gear score and
## stats, how it compares with what you wear, Equip and Discard buttons, and why
## not when your class can't use it. Shows what the server last sent
## (LootSystem.inventory / equipment), so it always shows the real gear; the
## server checks every request.

const PANEL_SIZE := Vector2(760, 620)
const HINT_COLOR := Color(0.75, 0.75, 0.8)
const STAT_COLOR := Color(0.88, 0.88, 0.9)
const BETTER_COLOR := Color(0.5, 0.95, 0.55)
const WORSE_COLOR := Color(1.0, 0.5, 0.45)
const SECTION_COLOR := Color(0.55, 0.75, 0.9)

var _loot: LootSystem
var _db: ItemDatabase
var _title: Label
var _list: VBoxContainer


func setup(loot: LootSystem, db: ItemDatabase) -> void:
	_loot = loot
	_db = db


func _ready() -> void:
	visible = false
	add_to_group(&"modal_ui")  # Player won't capture the mouse while it's open
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # clicks don't reach the game
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -PANEL_SIZE.x / 2.0
	panel.offset_right = PANEL_SIZE.x / 2.0
	panel.offset_top = -PANEL_SIZE.y / 2.0
	panel.offset_bottom = PANEL_SIZE.y / 2.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.95)
	style.border_color = Color(0.55, 0.75, 0.9, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override(&"panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	panel.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 20)
	column.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_list)
	var hint := _label("Personal loot: what enemies drop for you only you can see; walk up to it and press F. Changing gear takes a moment: you can walk, not fight. I or Esc closes.",
			13, HINT_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)


func toggle() -> void:
	visible = not visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		refresh()
	elif not _other_modal_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # back to the game


## Another mouse panel (the K panel) is still open: leave the mouse free.
func _other_modal_open() -> bool:
	for node in get_tree().get_nodes_in_group(&"modal_ui"):
		if node != self and node is CanvasItem and (node as CanvasItem).visible:
			return true
	return false


## Esc closes the panel like I (before Player's Esc handling frees the mouse).
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	if _list == null or not visible:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var curve := GearScore.current()
	var stats := _loot.equipment.stats(_db, curve.average_weights)
	_title.text = "Inventory   %d / %d          Gear score %d" % [
			_loot.inventory.size(), _loot.capacity, roundi(stats.average_gear_score)]

	_list.add_child(_label("Equipped", 16, SECTION_COLOR))
	for equip_slot in Equipment.SLOTS:
		_list.add_child(_equipped_row(equip_slot))
	var totals := _label(_totals_text(stats, curve), 14, STAT_COLOR)
	totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(totals)

	_list.add_child(_label("Bag", 16, SECTION_COLOR))
	var items := _loot.inventory
	if items.is_empty():
		_list.add_child(_label("Nothing yet. Defeat enemies to find gear.", 14, HINT_COLOR))
		return
	for i in range(items.size() - 1, -1, -1):
		_list.add_child(_item_row(items[i]))


## "Armor 84: 20% less damage from gear score 120 hits.  +42 max health ..."
func _totals_text(stats: Equipment.Stats, curve: GearScore) -> String:
	var parts := PackedStringArray()
	parts.append("Armor %d: %d%% less damage from gear score %d hits" % [roundi(stats.armor),
			roundi(curve.mitigation(stats.armor, curve.ui_attacker_gear_score) * 100.0),
			curve.ui_attacker_gear_score])
	for stat: String in stats.bonuses:
		parts.append(Item.display_stat(stat, stats.bonuses[stat]))
	return ".   ".join(parts)


func _equipped_row(equip_slot: String) -> Control:
	var item := _loot.equipment.get_item(equip_slot)
	var row := _row_panel(item.rarity_color(_db) if item else Color(0.3, 0.3, 0.35))
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 12)
	row.add_child(line)
	var slot_label := _label(Equipment.SLOT_NAMES[equip_slot], 14, HINT_COLOR)
	slot_label.custom_minimum_size.x = 140
	line.add_child(slot_label)
	var text := _label("", 15, STAT_COLOR)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	if item == null:
		text.text = _empty_slot_text(equip_slot)
		text.add_theme_color_override(&"font_color", HINT_COLOR)
		return row
	text.text = "%s   GS %d   %s" % [item.display_name(_db), item.gear_score,
			item.stat_lines(_db)[0]]
	text.add_theme_color_override(&"font_color", item.rarity_color(_db))
	var take_off := _button("Take off")
	take_off.pressed.connect(_loot.request_unequip.bind(equip_slot))
	line.add_child(take_off)
	return row


## An empty weapon slot is the class's plain weapon at the base gear score.
func _empty_slot_text(equip_slot: String) -> String:
	var index := Equipment.weapon_index(equip_slot)
	var weapons := _loadout()
	if index >= 0 and index < weapons.size():
		var weapon_name: String = Tuning.get_optional("weapon_" + weapons[index], "weapon", "name",
				weapons[index].capitalize())
		return "Plain %s (gear score %d)" % [weapon_name, GearScore.current().base]
	return "Empty"


func _item_row(item: Item) -> Control:
	var color := item.rarity_color(_db)
	var row := _row_panel(color)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 12)
	row.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 2)
	line.add_child(text)
	text.add_child(_label(item.display_name(_db), 17, color))
	text.add_child(_label("%s   Gear score %d" % [item.kind_text(_db), item.gear_score], 13,
			HINT_COLOR))
	text.add_child(_label("\n".join(item.stat_lines(_db)), 14, STAT_COLOR))

	var buttons := VBoxContainer.new()
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons.add_theme_constant_override(&"separation", 4)
	line.add_child(buttons)
	var def: ItemDatabase.ItemDef = _db.items.get(item.item_id)
	var class_def := _loot.local_class()
	var refusal := ""
	if def and class_def:
		var first_slot := "weapon_1" if def.slot == "weapon" else def.slot
		refusal = Equipment.check(item, first_slot, _db, class_def.id, class_def.weapons)
	if def and refusal.is_empty():
		var compare := _comparison(item, def)
		if compare:
			text.add_child(compare)
		for target in _equip_targets(def):
			var equip := _button(target[0])
			equip.pressed.connect(_loot.request_equip.bind(item.uid, target[1]))
			buttons.add_child(equip)
	elif not refusal.is_empty():
		text.add_child(_label(refusal, 13, WORSE_COLOR))

	var discard := _button("Discard")
	# Two clicks: the first arms it, so one stray click can't throw away a Legendary.
	discard.pressed.connect(func() -> void:
		if discard.text == "Discard":
			discard.text = "Sure?"
		else:
			_loot.request_discard(item.uid))
	buttons.add_child(discard)
	return row


## [button text, equip slot] per way to equip it. A weapon whose type is in
## the loadout replaces that slot's; another weapon type can go in either slot
## (replacing that weapon type).
func _equip_targets(def: ItemDatabase.ItemDef) -> Array:
	if def.slot != "weapon":
		return [["Equip", def.slot]]
	var weapons := _loadout()
	var index := weapons.find(def.weapon_type)
	if index >= 0 and index < 2:
		return [["Equip", Equipment.SLOTS[index]]]
	var targets := []
	for i in mini(weapons.size(), 2):
		var weapon_name: String = Tuning.get_optional("weapon_" + weapons[i], "weapon", "name",
				weapons[i])
		targets.append(["Replace %s" % weapon_name, Equipment.SLOTS[i]])
	return targets


## "+12 armor vs. equipped" in green (or red when worse). An empty weapon or
## Wing slot compares with the base (100) power; null for a weapon type that
## isn't in the loadout (its buttons say what it replaces).
func _comparison(item: Item, def: ItemDatabase.ItemDef) -> Label:
	var equip_slot := def.slot
	if def.slot == "weapon":
		var index := _loadout().find(def.weapon_type)
		if index < 0 or index >= 2:
			return null
		equip_slot = Equipment.SLOTS[index]
	var worn := _loot.equipment.get_item(equip_slot)
	var worn_value := worn.primary_value if worn else (
			def.primary_base if def.slot in ["weapon", "wings"] else 0.0)
	var diff := item.primary_value - worn_value
	var what: String = Item.STAT_TEXT[def.primary_stat][0] if Item.STAT_TEXT.has(def.primary_stat) else def.primary_stat
	var against := "equipped"
	if worn == null:
		against = "nothing equipped"
		if def.slot == "weapon":
			against = "your plain %s" % Tuning.get_optional("weapon_" + def.weapon_type, "weapon",
					"name", def.weapon_type)
	return _label("%+d %s vs. %s" % [roundi(diff), what, against], 13,
			BETTER_COLOR if diff >= 0.0 else WORSE_COLOR)


func _loadout() -> PackedStringArray:
	var local := _loot.local_player()
	return local.state.weapons if local else PackedStringArray()


func _row_panel(color: Color) -> PanelContainer:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.16, 0.95)
	style.border_color = color
	style.border_width_left = 4
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	row.add_theme_stylebox_override(&"panel", style)
	return row


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	return button
