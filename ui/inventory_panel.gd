class_name InventoryPanel
extends Control
## The inventory (I, client only, built in code). Top: your equipped gear, a
## compact card per equip slot with a Take off button (hover for its stats and
## affixes), your average gear score and what your gear adds up to (armor and
## its damage reduction, bonuses). Below: the bag as a grid of compact cards
## (an ItemIcon symbol, with an anvil badge and "Crafted" for crafted gear;
## rarity colour, kind, gear score, how it compares with what you wear,
## affixes included, Equip and Discard buttons, or which class it's for);
## hover a card for every stat. Filters (item type, class) and a sort only
## change what this panel shows, never the server's bag. Shows what the server
## last sent (LootSystem.inventory / equipment), so it always shows the real
## gear; the server checks every request.

## Largest the window gets. A smaller viewport gets the viewport minus
## SCREEN_MARGIN on each side, and the panel scrolls only then.
const MAX_PANEL_SIZE := Vector2(1560, 840)
const MIN_PANEL_SIZE := Vector2(360, 260)
const SCREEN_MARGIN := 20.0
## Narrowest a bag card gets; the bag uses as many columns as fit, up to MAX_COLUMNS.
const CARD_MIN_WIDTH := 360.0
const MAX_COLUMNS := 4
const EQUIPPED_COLUMNS := 3
const GAP := 6
## Item symbols (ItemIcon), px: a bag card's two lines, an equipped card's one.
const BAG_ICON_SIZE := 34.0
const EQUIPPED_ICON_SIZE := 26.0
## Panel border + content margin, each side.
const PANEL_PADDING := 14.0
const HINT_COLOR := Color(0.75, 0.75, 0.8)
const STAT_COLOR := Color(0.88, 0.88, 0.9)
const BETTER_COLOR := Color(0.5, 0.95, 0.55)
const WORSE_COLOR := Color(1.0, 0.5, 0.45)
const SECTION_COLOR := Color(0.55, 0.75, 0.9)

enum Sort { NEWEST, TYPE, GEAR_SCORE, RARITY }
const SORT_NAMES := ["Newest", "Type", "Gear score", "Rarity"]

var _loot: LootSystem
var _db: ItemDatabase
var _panel: PanelContainer
var _title: Label
var _equipped: GridContainer
var _totals: Label
var _bag_header: Label
var _bag: GridContainer
var _type_picker: OptionButton
var _class_picker: OptionButton
## Item slot (ItemDatabase.SLOTS) shown, "" = every type.
var _type_filter := ""
## Class id whose items are shown (armor + its weapons and Wing Enhancements), "" = all.
var _class_filter := ""
var _sort: int = Sort.NEWEST
## Class id -> its weapon ids, and -> its display name (every class with a data file).
var _class_weapons := {}
var _class_names := {}


func setup(loot: LootSystem, db: ItemDatabase) -> void:
	_loot = loot
	_db = db


func _ready() -> void:
	visible = false
	add_to_group(&"modal_ui")  # Player won't capture the mouse while it's open
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # clicks don't reach the game
	for class_id in ClassDef.all_ids():
		var class_def := ClassDef.for_id(class_id)
		if class_def:
			_class_weapons[class_id] = class_def.weapons
			_class_names[class_id] = class_def.display_name
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.95)
	style.border_color = Color(0.55, 0.75, 0.9, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(PANEL_PADDING - 2.0)
	_panel.add_theme_stylebox_override(&"panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	_panel.add_child(column)
	column.add_child(_header_row())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 5)
	scroll.add_child(list)
	list.add_child(_label("Equipped", 15, SECTION_COLOR))
	_equipped = _grid(EQUIPPED_COLUMNS)
	list.add_child(_equipped)
	_totals = _label("", 13, STAT_COLOR)
	_totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_totals)
	_bag_header = _label("Bag", 15, SECTION_COLOR)
	list.add_child(_bag_header)
	_bag = _grid(MAX_COLUMNS)
	list.add_child(_bag)
	var hint := _label("Hover an item for all its stats. Personal loot: only you see your drops; walk up and press F. Changing gear takes a moment (you can walk, not fight). I or Esc closes.",
			12, HINT_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	resized.connect(_fit)
	_fit()


## Title, then the bag filters and sort (built once; they keep their choice).
func _header_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	_title = _label("", 20, Color.WHITE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	row.add_child(_title)
	row.add_child(_label("Show", 13, HINT_COLOR))
	_type_picker = _picker("Show only one kind of item.")
	_type_picker.add_item("All types")
	_type_picker.set_item_metadata(0, "")
	for slot in ItemDatabase.ITEM_SLOTS:
		_type_picker.add_item(_slot_plural(slot))
		_type_picker.set_item_metadata(_type_picker.item_count - 1, slot)
	_type_picker.item_selected.connect(func(index: int) -> void:
		_type_filter = _type_picker.get_item_metadata(index)
		refresh())
	row.add_child(_type_picker)
	_class_picker = _picker("Show only what one class can use: its weapons and Wing Enhancements, and armor (any class wears it).")
	_class_picker.add_item("All classes")
	_class_picker.set_item_metadata(0, "")
	for class_id: String in _class_names:
		_class_picker.add_item(_class_names[class_id])
		_class_picker.set_item_metadata(_class_picker.item_count - 1, class_id)
	_class_picker.item_selected.connect(func(index: int) -> void:
		_class_filter = _class_picker.get_item_metadata(index)
		refresh())
	row.add_child(_class_picker)
	row.add_child(_label("Sort", 13, HINT_COLOR))
	var sort_picker := _picker("Order of the bag (equal items: newest first).")
	for sort_name: String in SORT_NAMES:
		sort_picker.add_item(sort_name)
	sort_picker.item_selected.connect(func(index: int) -> void:
		_sort = index
		refresh())
	row.add_child(sort_picker)
	return row


## Sizes the window to the viewport (up to MAX_PANEL_SIZE) and the grids to the window.
func _fit() -> void:
	if _panel == null:
		return
	var room := size - Vector2.ONE * SCREEN_MARGIN * 2.0
	var panel_size := room.min(MAX_PANEL_SIZE).max(MIN_PANEL_SIZE)
	_panel.offset_left = -panel_size.x / 2.0
	_panel.offset_right = panel_size.x / 2.0
	_panel.offset_top = -panel_size.y / 2.0
	_panel.offset_bottom = panel_size.y / 2.0
	var inner := panel_size.x - PANEL_PADDING * 2.0
	var columns := clampi(floori((inner + GAP) / (CARD_MIN_WIDTH + GAP)), 1, MAX_COLUMNS)
	_bag.columns = columns
	_equipped.columns = mini(EQUIPPED_COLUMNS, columns)


func toggle() -> void:
	visible = not visible
	if visible:
		hide_other_modals(self)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		refresh()
	elif not other_modal_open(self):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # back to the game


## True while a mouse panel (modal_ui group) other than `panel` is visible.
static func other_modal_open(panel: Node) -> bool:
	for node in panel.get_tree().get_nodes_in_group(&"modal_ui"):
		if node != panel and node is CanvasItem and (node as CanvasItem).visible:
			return true
	return false


## Closes every other mouse panel (I and K never show together). The mouse
## stays free, since `panel` is opening.
static func hide_other_modals(panel: Node) -> void:
	for node in panel.get_tree().get_nodes_in_group(&"modal_ui"):
		if node != panel and node is CanvasItem:
			(node as CanvasItem).visible = false


## Esc closes the panel like I (before Player's Esc handling frees the mouse).
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	if _bag == null or not visible:
		return
	for grid in [_equipped, _bag]:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	var curve := GearScore.current()
	var stats := _loot.equipment.stats(_db, curve.average_weights)
	_title.text = "Inventory   %d / %d        Gear score %d" % [
			_loot.inventory.size(), _loot.capacity, roundi(stats.average_gear_score)]
	var local_class := _loot.local_class()
	for i in _class_picker.item_count:
		var class_id: String = _class_picker.get_item_metadata(i)
		if not class_id.is_empty():
			_class_picker.set_item_text(i, _class_names[class_id] + (
					" (you)" if local_class and local_class.id == class_id else ""))

	for equip_slot in Equipment.SLOTS:
		_equipped.add_child(_equipped_card(equip_slot))
	_totals.text = _totals_text(stats, curve)

	var items := _loot.inventory
	var shown := bag_view(items, _db, _type_filter, _class_filter, _class_weapons, _sort)
	_bag_header.text = "Bag" if shown.size() == items.size() else "Bag   (showing %d of %d)" % [
			shown.size(), items.size()]
	if items.is_empty():
		_bag.add_child(_label("Nothing yet. Defeat enemies to find gear.", 14, HINT_COLOR))
	elif shown.is_empty():
		_bag.add_child(_label("Nothing matches the filters.", 14, HINT_COLOR))
	for item in shown:
		_bag.add_child(_item_card(item))


## The bag as the panel shows it: the items that match the filters, in `sort`
## order (Sort; ties and NEWEST: newest first, i.e. last in `items`).
## `slot` "" = any type; `class_id` "" = any class, else armor plus that
## class's weapons and Wing Enhancements (`class_weapons`: class id -> weapon ids).
static func bag_view(items: Array[Item], db: ItemDatabase, slot: String, class_id: String,
		class_weapons: Dictionary, sort: int) -> Array[Item]:
	var entries: Array = []  # [item, its index in items]
	for i in items.size():
		var def: ItemDatabase.ItemDef = db.items.get(items[i].item_id)
		if not slot.is_empty() and (def == null or def.slot != slot):
			continue
		if not class_id.is_empty() and not fits_class(def, class_id,
				class_weapons.get(class_id, PackedStringArray())):
			continue
		entries.append([items[i], i])
	entries.sort_custom(func(a: Array, b: Array) -> bool:
		var order := _order(a[0], b[0], db, sort)
		return order < 0 if order != 0 else a[1] > b[1])
	var shown: Array[Item] = []
	for entry in entries:
		shown.append(entry[0])
	return shown


## Whether a class (using `class_weapons`) can use the item: armor fits any
## class; weapons and Wing Enhancements are class-locked.
static func fits_class(def: ItemDatabase.ItemDef, class_id: String,
		class_weapons: PackedStringArray) -> bool:
	if def == null:
		return false
	if not def.weapon_type.is_empty():
		return def.weapon_type in class_weapons
	if not def.class_id.is_empty():
		return def.class_id == class_id
	return true


## Negative if a goes before b, positive if after, 0 if equal for this sort.
static func _order(a: Item, b: Item, db: ItemDatabase, sort: int) -> int:
	match sort:
		Sort.TYPE:
			var def_a: ItemDatabase.ItemDef = db.items.get(a.item_id)
			var def_b: ItemDatabase.ItemDef = db.items.get(b.item_id)
			var slot_a := ItemDatabase.ITEM_SLOTS.find(def_a.slot) if def_a else 99
			var slot_b := ItemDatabase.ITEM_SLOTS.find(def_b.slot) if def_b else 99
			if slot_a != slot_b:
				return slot_a - slot_b
			var kind_a := (def_a.weapon_type + def_a.class_id) if def_a else ""
			var kind_b := (def_b.weapon_type + def_b.class_id) if def_b else ""
			if kind_a != kind_b:
				return -1 if kind_a < kind_b else 1
			return b.gear_score - a.gear_score
		Sort.GEAR_SCORE:
			return b.gear_score - a.gear_score
		Sort.RARITY:
			var rank := db.rarity_order.find(b.rarity) - db.rarity_order.find(a.rarity)
			return rank if rank != 0 else b.gear_score - a.gear_score
	return 0


## "Armor 84: 20% less damage from gear score 120 hits.  +42 max health ..."
func _totals_text(stats: Equipment.Stats, curve: GearScore) -> String:
	var parts := PackedStringArray()
	parts.append("Armor %d: %d%% less damage from gear score %d hits" % [roundi(stats.armor),
			roundi(curve.mitigation(stats.armor, curve.ui_attacker_gear_score) * 100.0),
			curve.ui_attacker_gear_score])
	for stat: String in stats.bonuses:
		parts.append(Item.display_stat(stat, stats.bonuses[stat]))
	return ".   ".join(parts)


## One line: slot, item name, gear score, Take off. Hover: its stats and affixes.
func _equipped_card(equip_slot: String) -> Control:
	var item := _loot.equipment.get_item(equip_slot)
	var card := _card(item.rarity_color(_db) if item else Color(0.3, 0.3, 0.35))
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)
	card.add_child(line)
	line.add_child(ItemIcon.for_item(item, _db, EQUIPPED_ICON_SIZE,
			"sword" if equip_slot.begins_with("weapon") else equip_slot))
	var slot_name: String = "Wings" if equip_slot == "wings" else Equipment.SLOT_NAMES[equip_slot]
	var slot_label := _label(slot_name, 12, HINT_COLOR)
	slot_label.custom_minimum_size.x = 62
	line.add_child(slot_label)
	var text := _label("", 14, STAT_COLOR)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	line.add_child(text)
	if item == null:
		text.text = _empty_slot_text(equip_slot)
		text.add_theme_color_override(&"font_color", HINT_COLOR)
		card.tooltip_text = "%s: %s" % [Equipment.SLOT_NAMES[equip_slot], text.text]
		return card
	text.text = item.display_name(_db)
	text.add_theme_color_override(&"font_color", item.rarity_color(_db))
	if item.crafted:
		line.add_child(_label("Crafted", 12, ItemIcon.CRAFTED_COLOR))
	line.add_child(_label("GS %d" % item.gear_score, 12, HINT_COLOR))
	var take_off := _button("Take off")
	take_off.pressed.connect(_loot.request_unequip.bind(equip_slot))
	line.add_child(take_off)
	card.tooltip_text = "\n".join(_item_tooltip(item))
	return card


## An empty weapon slot is the class's plain weapon at the base gear score.
func _empty_slot_text(equip_slot: String) -> String:
	var index := Equipment.weapon_index(equip_slot)
	var weapons := _loadout()
	if index >= 0 and index < weapons.size():
		return "Plain %s (GS %d)" % [_weapon_name(weapons[index]), GearScore.current().base]
	return "Empty"


## Two lines: name, kind and gear score; then how it compares with what it
## would replace (or which class it's for). Hover: every stat, and the
## comparison stat by stat.
func _item_card(item: Item) -> Control:
	var def: ItemDatabase.ItemDef = _db.items.get(item.item_id)
	var color := item.rarity_color(_db)
	var card := _card(color)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)
	card.add_child(line)
	line.add_child(ItemIcon.for_item(item, _db, BAG_ICON_SIZE))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 0)
	line.add_child(text)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 8)
	text.add_child(top)
	var name_label := _label(item.display_name(_db), 14, color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	top.add_child(name_label)
	var resource := def != null and def.is_resource()
	top.add_child(_label("Resource · ×%d" % item.count if resource
			else "%s · GS %d" % [_kind_short(def), item.gear_score], 12, HINT_COLOR))
	# Second line: "Crafted" (crafted gear), then the comparison or why not.
	var detail := HBoxContainer.new()
	detail.add_theme_constant_override(&"separation", 6)
	text.add_child(detail)
	if item.crafted:
		detail.add_child(_label("Crafted", 12, ItemIcon.CRAFTED_COLOR))

	var tooltip := _item_tooltip(item)
	var buttons := HBoxContainer.new()
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons.add_theme_constant_override(&"separation", 4)
	line.add_child(buttons)
	var refusal := "" if resource else _refusal(item, def)
	if resource:
		detail.add_child(_label("Crafting material (stacks to %d)" % def.max_stack, 12, HINT_COLOR))
	elif def and refusal.is_empty():
		var compare := _comparison(item, def)
		if compare.is_empty():
			detail.add_child(_label(_replaces_text(), 12, HINT_COLOR))
		else:
			detail.add_child(_rich(compare[0]))
			tooltip.append("")
			tooltip.append_array(compare[1])
		buttons.add_child(_equip_button(item, def))
	else:
		var refused := _label(refusal, 12, WORSE_COLOR)
		refused.clip_text = true
		refused.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_child(refused)
		tooltip.append("")
		tooltip.append(refusal)

	var discard := _button("Discard")
	discard.tooltip_text = "Throw it away (click twice)."
	# Two clicks: the first arms it, so one stray click can't throw away a Legendary.
	discard.pressed.connect(func() -> void:
		if discard.text == "Discard":
			discard.text = "Sure?"
		else:
			_loot.request_discard(item.uid))
	buttons.add_child(discard)
	card.tooltip_text = "\n".join(tooltip)
	return card


## Name, kind and gear score, then each stat line (primary, then affixes).
func _item_tooltip(item: Item) -> PackedStringArray:
	var def: ItemDatabase.ItemDef = _db.items.get(item.item_id)
	if def and def.is_resource():
		return PackedStringArray([item.display_name(_db), "Resource   ×%d" % item.count])
	var lines := PackedStringArray([item.display_name(_db),
			"%s   Gear score %d" % [item.kind_text(_db), item.gear_score]])
	lines.append_array(item.stat_lines(_db))
	return lines


## Why your class can't equip it, naming the class it's for; "" if it can.
func _refusal(item: Item, def: ItemDatabase.ItemDef) -> String:
	if def == null:
		return "Unknown item."
	var class_def := _loot.local_class()
	if class_def == null:
		return ""
	var first_slot := "weapon_1" if def.slot == "weapon" else def.slot
	var refusal := Equipment.check(item, first_slot, _db, class_def.id, class_def.weapons)
	if refusal.is_empty():
		return ""
	var owners := PackedStringArray()
	for class_id: String in _class_names:
		if fits_class(def, class_id, _class_weapons[class_id]):
			owners.append(_class_names[class_id])
	if owners.is_empty():
		return refusal
	return "For the %s class." % " or ".join(owners)


## The Equip button; a weapon type that isn't in the loadout gets a menu of
## which weapon it replaces.
func _equip_button(item: Item, def: ItemDatabase.ItemDef) -> Control:
	var targets := _equip_targets(def)
	if targets.size() == 1:
		var equip := _button("Equip")
		equip.tooltip_text = "Equip in %s." % Equipment.SLOT_NAMES[targets[0][1]]
		equip.pressed.connect(_loot.request_equip.bind(item.uid, targets[0][1]))
		return equip
	var menu := MenuButton.new()
	menu.text = "Equip..."
	menu.flat = false
	menu.focus_mode = Control.FOCUS_NONE
	menu.add_theme_font_size_override(&"font_size", 12)
	menu.tooltip_text = "Not in your loadout: pick the weapon it replaces."
	var popup := menu.get_popup()
	for i in targets.size():
		popup.add_item(targets[i][0], i)
	popup.id_pressed.connect(func(id: int) -> void:
		_loot.request_equip(item.uid, targets[id][1]))
	return menu


## [menu text, equip slot] per way to equip it. A weapon whose type is in
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
		targets.append(["Replace %s" % _weapon_name(weapons[i]), Equipment.SLOTS[i]])
	return targets


func _replaces_text() -> String:
	var weapons := _loadout()
	var names := PackedStringArray()
	for i in mini(weapons.size(), 2):
		names.append(_weapon_name(weapons[i]))
	return "Not in your loadout: replaces your %s" % " or ".join(names)


## [one-line BBCode summary, tooltip lines]: every stat that changes
## (primary stat and affixes) vs. what it would replace. An empty weapon or
## Wing slot compares with the base (100) power. [] for a weapon type that
## isn't in the loadout (its menu says what it replaces).
func _comparison(item: Item, def: ItemDatabase.ItemDef) -> Array:
	var equip_slot := def.slot
	if def.slot == "weapon":
		var index := _loadout().find(def.weapon_type)
		if index < 0 or index >= 2:
			return []
		equip_slot = Equipment.SLOTS[index]
	var worn := _loot.equipment.get_item(equip_slot)
	var old_stats := worn.stat_totals(_db) if worn else {def.primary_stat:
			def.primary_base if def.slot in ["weapon", "wings"] else 0.0}
	var changes := Item.stat_changes(item.stat_totals(_db), old_stats)
	var against := "equipped"
	var against_long := "Compared with your %s (GS %d):" % [worn.display_name(_db),
			worn.gear_score] if worn else "Compared with an empty slot:"
	if worn == null:
		against = "empty slot"
		if def.slot == "weapon":
			against = "plain %s" % _weapon_name(def.weapon_type)
			against_long = "Compared with your plain %s:" % _weapon_name(def.weapon_type)
	var gains := false
	var losses := false
	var lines := PackedStringArray([against_long])
	for stat: String in changes:
		lines.append(Item.display_change(stat, changes[stat]))
		gains = gains or changes[stat] > 0.0
		losses = losses or changes[stat] < 0.0
	if not gains and not losses:
		lines.append("Same stats.")
	# The card only shows which way it goes (a trade-off shows both arrows); the
	# tooltip has every stat.
	var arrows := ""
	if gains:
		arrows += "[color=#%s]▲[/color]" % BETTER_COLOR.to_html(false)
	if losses:
		arrows += "[color=#%s]▼[/color]" % WORSE_COLOR.to_html(false)
	if arrows.is_empty():
		arrows = "="
	return ["%s [color=#%s]vs. %s[/color]" % [arrows, HINT_COLOR.to_html(false), against],
			lines]


## "Chest", "Spear", "Wing Enh." (short, for the card's first line).
func _kind_short(def: ItemDatabase.ItemDef) -> String:
	if def == null:
		return "?"
	if not def.weapon_type.is_empty():
		return _weapon_name(def.weapon_type)
	return "Wing Enh." if def.slot == "wings" else def.slot.capitalize()


static func _slot_plural(slot: String) -> String:
	match slot:
		"weapon":
			return "Weapons"
		"wings":
			return "Wing Enhancements"
		"resource":
			return "Resources"
	return slot.capitalize()


func _weapon_name(weapon_type: String) -> String:
	return Tuning.get_optional("weapon_" + weapon_type, "weapon", "name", weapon_type.capitalize())


func _loadout() -> PackedStringArray:
	var local := _loot.local_player()
	return local.state.weapons if local else PackedStringArray()


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", GAP)
	grid.add_theme_constant_override(&"v_separation", GAP - 2)
	return grid


## A card with a rarity-coloured left edge. Its tooltip covers the whole card
## (labels and boxes inside pass the hover up to it).
func _card(color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.x = CARD_MIN_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.16, 0.95)
	style.border_color = color
	style.border_width_left = 4
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	card.add_theme_stylebox_override(&"panel", style)
	return card


func _rich(bbcode: String) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.text = bbcode
	# One line, clipped (not fit_content, which would widen the card to the text).
	rich.scroll_active = false
	rich.autowrap_mode = TextServer.AUTOWRAP_OFF
	rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rich.custom_minimum_size = Vector2(1, 18)
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the card shows the tooltip
	rich.add_theme_font_size_override(&"normal_font_size", 12)
	rich.add_theme_color_override(&"default_color", STAT_COLOR)
	return rich


func _picker(tooltip: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	picker.tooltip_text = tooltip
	picker.add_theme_font_size_override(&"font_size", 13)
	return picker


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
	button.add_theme_font_size_override(&"font_size", 12)
	return button
