class_name PartyHud
extends CanvasLayer
## Party overlay (client): a panel on the left with a frame per other party
## member (name, leader tag, health bar), key hints and short party notices,
## plus the invite prompt at the top centre. Built in code; PartySystem fills it
## every frame.

const FRAME_WIDTH := 220.0
const PANEL_TOP := 150.0
## Matches Player.PARTY_NAME_COLOR, so frames and nameplates read as one group.
const ACCENT_COLOR := Color(0.45, 0.9, 1.0)
const LEADER_COLOR := Color(1.0, 0.82, 0.35)
const HEALTH_COLOR := Color(0.35, 0.8, 0.45)
const DOWN_COLOR := Color(0.45, 0.45, 0.48)
## How long each notice line stays, and how many show at once.
const NOTICE_MS := 4000
const MAX_NOTICES := 4

var _panel: PanelContainer
var _title: Label
var _rows: VBoxContainer
var _hint: Label
var _prompt_panel: PanelContainer
var _prompt: Label
var _notices: Label
var _notice_lines: Array[Array] = []  # [text, expires_msec]


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(12.0, PANEL_TOP)
	_panel.custom_minimum_size.x = FRAME_WIDTH
	_panel.add_theme_stylebox_override(&"panel", _panel_style(ACCENT_COLOR))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false  # until the first set_party
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	_panel.add_child(box)
	_title = _label(15, ACCENT_COLOR)
	box.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 6)
	box.add_child(_rows)
	_hint = _label(12, Color(0.8, 0.8, 0.8))
	box.add_child(_hint)
	_notices = _label(13, Color(1.0, 0.95, 0.8))
	_notices.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notices.custom_minimum_size.x = FRAME_WIDTH - 20.0
	_notices.visible = false
	box.add_child(_notices)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.add_theme_stylebox_override(&"panel", _panel_style(LEADER_COLOR))
	_prompt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.offset_top = 120.0  # below the debug info lines
	_prompt_panel.visible = false
	add_child(_prompt_panel)
	_prompt = _label(18, Color.WHITE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	while not _notice_lines.is_empty() and _notice_lines[0][1] <= now:
		_notice_lines.pop_front()
	var lines := PackedStringArray()
	for line in _notice_lines:
		lines.append(line[0])
	_notices.text = "\n".join(lines)
	_notices.visible = not lines.is_empty()


## frames: one {name, health, max_health, leader} per other party member.
func set_party(title: String, frames: Array[Dictionary], hint: String) -> void:
	_panel.visible = true
	_title.text = title
	_hint.text = hint
	while _rows.get_child_count() < frames.size():
		_rows.add_child(_make_row())
	while _rows.get_child_count() > frames.size():
		var row := _rows.get_child(_rows.get_child_count() - 1)
		_rows.remove_child(row)
		row.queue_free()
	for i in frames.size():
		var frame := frames[i]
		var row := _rows.get_child(i)
		var down: bool = frame["health"] <= 0.0
		(row.get_node("Top/Name") as Label).text = frame["name"] + ("  (down)" if down else "")
		(row.get_node("Top/Leader") as Label).visible = frame["leader"]
		var bar := row.get_node("Health") as ProgressBar
		bar.max_value = frame["max_health"]
		bar.value = frame["health"]
		var fill := bar.get_theme_stylebox(&"fill") as StyleBoxFlat
		fill.bg_color = DOWN_COLOR if down else HEALTH_COLOR


## The invite prompt; empty hides it.
func set_invite(text: String) -> void:
	_prompt.text = text
	_prompt_panel.visible = not text.is_empty()


func show_notice(text: String) -> void:
	_notice_lines.append([text, Time.get_ticks_msec() + NOTICE_MS])
	while _notice_lines.size() > MAX_NOTICES:
		_notice_lines.pop_front()


func _make_row() -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	var top := HBoxContainer.new()
	top.name = "Top"
	row.add_child(top)
	var name_label := _label(14, Color.WHITE)
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var leader := _label(12, LEADER_COLOR)
	leader.name = "Leader"
	leader.text = "LEADER"
	top.add_child(leader)
	var bar := ProgressBar.new()
	bar.name = "Health"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(FRAME_WIDTH - 20.0, 10.0)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = HEALTH_COLOR
	bar.add_theme_stylebox_override(&"background", background)
	bar.add_theme_stylebox_override(&"fill", fill)
	row.add_child(bar)
	return row


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Dark translucent panel with a coloured strip down its left edge.
func _panel_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.08, 0.6)
	style.border_color = accent
	style.border_width_left = 3
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	return style
