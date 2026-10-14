class_name TradeskillsPanel
extends Control
## The Tradeskills panel (P, client only, built in code): every tradeskill's
## name, level and an XP bar, grouped Gathering / Refining / Crafting, and what
## a gathering skill's level does (faster gathering, bonus yield). Shows what the
## server last sent (TradeskillSystem.local). A modal_ui panel like I and K:
## opening it closes them, and closing it recaptures the mouse only if no other
## panel is open.

const PANEL_WIDTH := 560.0
const NAME_WIDTH := 150.0
const LEVEL_WIDTH := 70.0
const BAR_HEIGHT := 20.0
const HINT_COLOR := Color(0.75, 0.75, 0.8)
const DETAIL_COLOR := Color(0.7, 0.8, 0.7)
const SECTION_COLOR := Color(0.55, 0.75, 0.9)
## The feed line on a level-up (TradeskillSystem).
const LEVEL_UP_COLOR := Color(0.95, 0.85, 0.45)
## XP bar fill per category.
const BAR_COLORS := {
	"gathering": Color(0.42, 0.72, 0.38),
	"refining": Color(0.85, 0.55, 0.25),
	"crafting": Color(0.4, 0.6, 0.9),
}

var _system: TradeskillSystem
## Skill id -> [level Label, ProgressBar, XP Label, detail Label or null].
var _rows: Dictionary[String, Array] = {}


func setup(system: TradeskillSystem) -> void:
	_system = system


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
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.95)
	style.border_color = Color(0.55, 0.75, 0.9, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override(&"panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	panel.add_child(column)
	column.add_child(_label("Tradeskills", 20, Color.WHITE))
	var defs := _system.defs
	for category in TradeskillDefs.CATEGORIES:
		var ids := defs.ids_in(category)
		if ids.is_empty():
			continue
		var header := _label(TradeskillDefs.CATEGORY_NAMES[category], 15, SECTION_COLOR)
		header.custom_minimum_size.y = 26
		header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		column.add_child(header)
		for id in ids:
			column.add_child(_skill_row(id, defs.skills[id]))
	var hint := _label("Gathering levels up as you gather: each level gathers a little faster and more often yields a bonus unit. Refining and crafting level from their recipes. P or Esc closes.",
			12, HINT_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = PANEL_WIDTH - 28.0
	column.add_child(hint)
	refresh()


func _skill_row(id: String, skill: TradeskillDefs.SkillDef) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	box.add_child(row)
	var name_label := _label(skill.display_name, 14, Color.WHITE)
	name_label.custom_minimum_size.x = NAME_WIDTH
	row.add_child(name_label)
	var level_label := _label("", 14, Color.WHITE)
	level_label.custom_minimum_size.x = LEVEL_WIDTH
	row.add_child(level_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size.y = BAR_HEIGHT
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.15, 0.16, 0.19)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override(&"background", back)
	var fill := StyleBoxFlat.new()
	fill.bg_color = BAR_COLORS.get(skill.category, Color.GRAY)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override(&"fill", fill)
	row.add_child(bar)
	var xp_label := _label("", 12, Color.WHITE)
	xp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xp_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	bar.add_child(xp_label)
	var detail: Label = null
	if skill.is_gathering():
		detail = _label("", 12, DETAIL_COLOR)
		detail.custom_minimum_size.x = NAME_WIDTH
		box.add_child(detail)
	_rows[id] = [level_label, bar, xp_label, detail]
	return box


func toggle() -> void:
	visible = not visible
	if visible:
		InventoryPanel.hide_other_modals(self)  # one mouse panel at a time
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		refresh()
	elif not InventoryPanel.other_modal_open(self):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # back to the game


## Esc closes the panel like P (before Player's Esc handling frees the mouse).
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	if _system == null or _system.local == null or not visible:
		return
	var skills := _system.local
	var defs := _system.defs
	for id: String in _rows:
		var row := _rows[id]
		var lv := skills.level(id)
		(row[0] as Label).text = "Lv %d" % lv
		(row[1] as ProgressBar).value = skills.progress(id)
		(row[2] as Label).text = "Max level" if skills.is_capped(id) \
				else "%s / %s XP" % [_thousands(skills.xp(id)), _thousands(skills.xp_needed(id))]
		var detail: Label = row[3]
		if detail:
			var faster := (1.0 - skills.gather_time_multiplier(id)) * 100.0
			var chance := defs.bonus_chance(lv) * 100.0
			detail.text = "No bonus yet" if lv <= Tradeskills.START_LEVEL else \
					"Gathers %.1f%% faster, %.1f%% chance of +%d" % [faster, chance, defs.bonus_units]


## 12345 -> "12,345".
static func _thousands(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
