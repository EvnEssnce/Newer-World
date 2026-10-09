class_name InventoryPanel
extends Control
## The inventory (I, client only, built in code): every item you carry, newest
## first, with its rarity colour, kind, gear score and stats, and a Discard
## button. Shows LootSystem.inventory, which the server sends after every
## change, so it always shows the real bag. Equipping comes later (milestone 2).

const PANEL_SIZE := Vector2(620, 520)
const HINT_COLOR := Color(0.75, 0.75, 0.8)
const STAT_COLOR := Color(0.88, 0.88, 0.9)

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
	var hint := Label.new()
	hint.text = "Personal loot: what enemies drop for you only you can see. Walk up to it and press F. I or Esc closes."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override(&"font_color", HINT_COLOR)
	hint.add_theme_font_size_override(&"font_size", 13)
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
	var items := _loot.inventory
	_title.text = "Inventory   %d / %d" % [items.size(), _loot.capacity]
	if items.is_empty():
		var empty := Label.new()
		empty.text = "Nothing yet. Defeat enemies to find gear."
		empty.add_theme_color_override(&"font_color", HINT_COLOR)
		_list.add_child(empty)
		return
	for i in range(items.size() - 1, -1, -1):
		_list.add_child(_item_row(items[i]))


func _item_row(item: Item) -> Control:
	var color := item.rarity_color(_db)
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.16, 0.95)
	style.border_color = color
	style.border_width_left = 4
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	row.add_theme_stylebox_override(&"panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 12)
	row.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 2)
	line.add_child(text)
	var name_label := Label.new()
	name_label.text = item.display_name(_db)
	name_label.add_theme_font_size_override(&"font_size", 17)
	name_label.add_theme_color_override(&"font_color", color)
	text.add_child(name_label)
	var kind := Label.new()
	kind.text = "%s   Gear score %d" % [item.kind_text(_db), item.gear_score]
	kind.add_theme_font_size_override(&"font_size", 13)
	kind.add_theme_color_override(&"font_color", HINT_COLOR)
	text.add_child(kind)
	var stats := Label.new()
	stats.text = "\n".join(item.stat_lines(_db))
	stats.add_theme_font_size_override(&"font_size", 14)
	stats.add_theme_color_override(&"font_color", STAT_COLOR)
	text.add_child(stats)

	var discard := Button.new()
	discard.text = "Discard"
	discard.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	discard.focus_mode = Control.FOCUS_NONE
	# Two clicks: the first arms it, so one stray click can't throw away a Legendary.
	discard.pressed.connect(func() -> void:
		if discard.text == "Discard":
			discard.text = "Sure?"
		else:
			_loot.request_discard(item.uid))
	line.add_child(discard)
	return row
