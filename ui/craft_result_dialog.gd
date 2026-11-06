class_name CraftResultDialog
extends Control
## The result of a gear craft (client only, built in code), over the Forge
## panel: the piece's icon, name in its rarity's color, kind, gear score and
## every stat line, then OK (keep it) or Discard (click twice; throws it away
## through LootSystem.request_discard like the bag's Discard). A batch shows its
## pieces one after another ("2 of 5"); the last OK goes back to the panel. Esc
## = OK. It's already in the bag before this shows: closing the Forge
## keeps whatever is still queued.

const CARD_WIDTH := 420.0
const ICON_SIZE := 64.0
const HINT_COLOR := Color(0.75, 0.75, 0.8)
const STAT_COLOR := Color(0.85, 0.88, 0.95)
const DISCARD_COLOR := Color(1.0, 0.5, 0.45)

var _loot: LootSystem
## Items (Item) still to show, the first one on screen.
var _queue: Array[Item] = []
var _shown_total := 0
var _card: PanelContainer
var _style: StyleBoxFlat
var _icon_slot: Control
var _name: Label
var _kind: Label
var _count: Label
var _stats: VBoxContainer
var _ok: Button
var _discard: Button


func setup(loot: LootSystem) -> void:
	_loot = loot


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # the panel underneath waits
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.custom_minimum_size.x = CARD_WIDTH
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.08, 0.08, 0.1, 0.97)
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(6)
	_style.set_content_margin_all(16)
	_card.add_theme_stylebox_override(&"panel", _style)
	center.add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	_card.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := _label("Crafted", 18, ItemIcon.CRAFTED_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_count = _label("", 13, HINT_COLOR)
	top.add_child(_count)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 12)
	column.add_child(line)
	_icon_slot = Control.new()
	_icon_slot.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	line.add_child(_icon_slot)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(names)
	_name = _label("", 18, Color.WHITE)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_name)
	_kind = _label("", 13, HINT_COLOR)
	names.add_child(_kind)
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override(&"separation", 2)
	column.add_child(_stats)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override(&"separation", 8)
	column.add_child(buttons)
	_discard = Button.new()
	_discard.focus_mode = Control.FOCUS_NONE
	_discard.custom_minimum_size = Vector2(96, 34)
	_discard.tooltip_text = "Throw it away (click twice)."
	_discard.pressed.connect(_on_discard)
	buttons.add_child(_discard)
	_ok = Button.new()
	_ok.text = "OK"
	_ok.focus_mode = Control.FOCUS_NONE
	_ok.custom_minimum_size = Vector2(96, 34)
	_ok.tooltip_text = "Keep it (it's in your bag)."
	_ok.pressed.connect(_next)
	buttons.add_child(_ok)


## Queues freshly crafted gear (Item dicts, with their bag uids).
func add_items(items: Array) -> void:
	for data in items:
		var item := Item.from_dict(data)
		var def: ItemDatabase.ItemDef = ItemDatabase.current().items.get(item.item_id) if item else null
		if def and not def.is_resource():
			_queue.append(item)
			_shown_total += 1
	if not _queue.is_empty() and not visible:
		_show_first()


func showing() -> bool:
	return visible


func _show_first() -> void:
	if _queue.is_empty():
		visible = false
		_shown_total = 0
		return
	var db := ItemDatabase.current()
	var item := _queue[0]
	var color := item.rarity_color(db)
	_style.border_color = color
	for child in _icon_slot.get_children():
		child.queue_free()
	var icon := ItemIcon.for_item(item, db, ICON_SIZE)
	_icon_slot.add_child(icon)
	_name.text = item.display_name(db)
	_name.add_theme_color_override(&"font_color", color)
	_kind.text = "%s   Gear score %d" % [item.kind_text(db), item.gear_score]
	var done := _shown_total - _queue.size() + 1
	_count.text = "%d of %d" % [done, _shown_total] if _shown_total > 1 else ""
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	for stat in item.stat_lines(db):
		_stats.add_child(_label(stat, 14, STAT_COLOR))
	_discard.text = "Discard"
	_discard.add_theme_color_override(&"font_color", Color.WHITE)
	visible = true


func _next() -> void:
	if not _queue.is_empty():
		_queue.pop_front()
	_show_first()


func _on_discard() -> void:
	if _discard.text == "Discard":
		# Two clicks: the first arms it, so one stray click can't throw away an Epic.
		_discard.text = "Sure?"
		_discard.add_theme_color_override(&"font_color", DISCARD_COLOR)
		return
	if _loot and not _queue.is_empty():
		_loot.request_discard(_queue[0].uid)
	_next()


## Esc = OK (before the Forge panel's Esc closes it).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_next()
		get_viewport().set_input_as_handled()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Forgets what's queued (the Forge panel closed: the pieces stay in the bag).
func clear() -> void:
	_queue.clear()
	_shown_total = 0
	visible = false
