class_name LootHud
extends CanvasLayer
## Loot overlay (client, built in code; LootSystem fills it): the "[F] Pick up"
## prompt just below the middle of the screen, and a feed on the right of what you picked up
## (in rarity colours) and loot notices (inventory full, ...).

const NOTICE_COLOR := Color(1.0, 0.95, 0.8)
## How long each feed line stays, and how many show at once.
const FEED_MS := 5000
const MAX_FEED_LINES := 6
## Pixels below the middle of the screen (clear of the HUD's bars and lines).
const PROMPT_BELOW_CENTER := 90.0

var _prompt_panel: PanelContainer
var _prompt: Label
var _feed: VBoxContainer
var _feed_lines: Array[Array] = []  # [Label, expires_msec]


func _ready() -> void:
	layer = 2  # above the HUD, so the inventory panel covers the ability bar
	_prompt_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.8)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_prompt_panel.add_theme_stylebox_override(&"panel", style)
	_prompt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = Control.GROW_DIRECTION_END
	_prompt_panel.offset_top = PROMPT_BELOW_CENTER
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.visible = false
	add_child(_prompt_panel)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override(&"font_size", 18)
	_prompt.add_theme_constant_override(&"outline_size", 4)
	_prompt.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_prompt_panel.add_child(_prompt)

	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.offset_right = -16.0
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	while not _feed_lines.is_empty() and _feed_lines[0][1] <= now:
		(_feed_lines.pop_front()[0] as Node).queue_free()


## Empty text hides it.
func set_prompt(text: String, color: Color) -> void:
	_prompt_panel.visible = not text.is_empty()
	if _prompt.text != text:
		_prompt.text = text
	_prompt.add_theme_color_override(&"font_color", color)


func add_feed_line(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override(&"font_size", 16)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_constant_override(&"outline_size", 4)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_feed.add_child(label)
	_feed_lines.append([label, Time.get_ticks_msec() + FEED_MS])
	while _feed_lines.size() > MAX_FEED_LINES:
		(_feed_lines.pop_front()[0] as Node).queue_free()
