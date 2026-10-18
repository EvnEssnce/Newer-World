class_name KeybindsPanel
extends PanelContainer
## The key list on the left side of the HUD (client, built in code; F1 shows or
## hides it). Keys are read from InputActions, so a rebinding shows here. Later
## this list moves to a keybinds options page where keys can be changed.

const TITLE_COLOR := Color(0.85, 0.75, 0.5)
const KEY_COLOR := Color(1.0, 0.92, 0.7)
const TEXT_COLOR := Color(0.85, 0.85, 0.88)
## Pixels from the screen's left and bottom edges (clear of the XP bar).
const MARGIN := Vector2(12, 16)

## [what it does, keys]: a key entry is an action name (its first key),
## anything else is shown as written.
const ENTRIES: Array[Array] = [
	["Move", [&"move_forward", &"move_left", &"move_back", &"move_right"]],
	["Jump", [&"jump"]],
	["Dodge", [&"dodge"]],
	["Light attack (hold: heavy)", ["LMB"]],
	["Block", ["RMB"]],
	["Abilities", [&"ability_1", &"ability_2", &"ability_3"]],
	["Wing abilities", [&"wing_1", &"wing_2"]],
	["Swap weapon", [&"swap_weapon"]],
	["Interact", [&"pickup"]],
	["Inventory", [&"toggle_inventory"]],
	["Mastery trees", [&"toggle_mastery"]],
	["Tradeskills", [&"toggle_tradeskills"]],
	["Party invite / join / decline", [&"party_invite", &"party_accept", &"party_decline"]],
	["Party leave / kick", [&"party_leave", &"party_kick"]],
	["Hitboxes", [&"toggle_hitboxes"]],
	["Free the mouse", ["Esc"]],
	["Hide this list", [&"toggle_keybinds"]],
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.6)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	add_theme_stylebox_override(&"panel", style)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = MARGIN.x
	offset_bottom = -MARGIN.y

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label("Keybinds", TITLE_COLOR, 14))
	box.add_child(grid)
	add_child(box)
	for entry in ENTRIES:
		var key := _label(keys_text(entry[1]), KEY_COLOR, 13)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(key)
		grid.add_child(_label(entry[0], TEXT_COLOR, 13))


## "Q / E / R", "WASD" (four single-letter keys run together), "LMB".
static func keys_text(keys: Array) -> String:
	var names := PackedStringArray()
	for key: Variant in keys:
		names.append(key_name(key) if key is StringName else str(key))
	var single := names.size() == 4
	for name in names:
		single = single and name.length() == 1
	return "".join(names) if single else " / ".join(names)


## An action's first key ("?" if it has none).
static func key_name(action: StringName) -> String:
	var keys: Array = InputActions.KEY_BINDINGS.get(action, [])
	return OS.get_keycode_string(keys[0]) if not keys.is_empty() else "?"


static func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 3)
	return label
