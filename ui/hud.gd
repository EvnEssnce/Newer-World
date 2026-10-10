class_name Hud
extends CanvasLayer
## In-game overlay: health, stamina and Ember bars (Ember with a Rebirth marker
## and line), ability bar, Wing slots, current weapon, connection stats and
## controls. The ability bar, Wing slots and Ember bar are built in code.

const SLOT_KEYS := ["Q", "E", "R"]
const WING_KEYS := ["Z", "C"]
## Wing slots' border, and the Ember bar's fill and Rebirth marker.
const WING_BORDER := Color(1.0, 0.5, 0.15, 0.95)
const EMBER_FILL := Color(1.0, 0.5, 0.12)
const EMBER_MARKER := Color(1.0, 1.0, 1.0, 0.95)
const UNAFFORDABLE_COLOR := Color(0.9, 0.35, 0.3)
const SLOT_SIZE := Vector2(116, 58)
const SLOT_COLOR := Color(0.08, 0.09, 0.12, 0.8)
const SLOT_BORDER := Color(0.85, 0.7, 0.35, 0.9)
const EMPTY_BORDER := Color(0.4, 0.4, 0.45, 0.6)
const COOLDOWN_COLOR := Color(0.0, 0.0, 0.0, 0.6)
## Status chips: bottom edge colour.
const BUFF_BORDER := Color(0.4, 0.85, 0.45)
const DEBUFF_BORDER := Color(0.9, 0.3, 0.3)

@onready var _info: Label = %Info
@onready var _health: ProgressBar = %Health
@onready var _stamina: ProgressBar = %Stamina
@onready var _banner: Label = %Banner

var _weapon_label: Label
var _slot_panels: Array[Panel] = []
var _slot_names: Array[Label] = []
var _slot_overlays: Array[ColorRect] = []
var _slot_timers: Array[Label] = []
var _status_row: HBoxContainer
# Wings and Ember (built in code)
var _wing_panels: Array[Panel] = []
var _wing_names: Array[Label] = []
var _wing_overlays: Array[ColorRect] = []
var _wing_timers: Array[Label] = []
var _wing_costs: Array[Label] = []
var _ember_bar: ProgressBar
var _ember_marker: ColorRect
var _ember_label: Label
## Blind statuses (Dazzled): a white haze over the whole screen.
var _blind_overlay: ColorRect


func _ready() -> void:
	_build_ability_bar()
	_build_wing_bar()
	_build_ember_bar()
	_build_status_row()
	_blind_overlay = ColorRect.new()
	_blind_overlay.color = Color(1.0, 0.97, 0.9, 0.0)
	_blind_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blind_overlay)
	move_child(_blind_overlay, 0)


func set_info(text: String) -> void:
	_info.text = text


func set_health(value: float, max_value: float) -> void:
	_health.max_value = max_value
	_health.value = value


## Big centered message (e.g. the respawn countdown); empty hides it.
func set_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = not text.is_empty()


func set_stamina(value: float, max_value: float) -> void:
	_stamina.max_value = max_value
	_stamina.value = value


## The weapon that's out, the other one (X swaps to it; "" if none), and
## whether a swap is in progress.
func set_weapons(current: String, other: String, swapping: bool) -> void:
	if swapping:
		_weapon_label.text = "Drawing %s..." % current
	elif other.is_empty():
		_weapon_label.text = current
	else:
		_weapon_label.text = "%s      [X] %s" % [current, other]


## One ability slot: name ("" = empty), cooldown left as a fraction (0 = ready)
## and in seconds.
func set_ability(slot: int, ability_name: String, cooldown_fraction: float,
		seconds_left: float) -> void:
	_slot_names[slot].text = ability_name if not ability_name.is_empty() else "(empty)"
	_slot_names[slot].modulate.a = 1.0 if not ability_name.is_empty() else 0.45
	var style := _slot_panels[slot].get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = SLOT_BORDER if not ability_name.is_empty() and cooldown_fraction <= 0.0 else EMPTY_BORDER
	var overlay := _slot_overlays[slot]
	overlay.visible = cooldown_fraction > 0.0
	overlay.anchor_top = 1.0 - clampf(cooldown_fraction, 0.0, 1.0)
	_slot_timers[slot].visible = cooldown_fraction > 0.0
	_slot_timers[slot].text = "%.1f" % seconds_left if seconds_left < 10.0 else str(ceili(seconds_left))


## One Wing slot (0 = Z, 1 = C): name ("" = empty), cooldown left as a fraction
## and in seconds, Ember cost, and whether there's enough Ember for it.
func set_wing(slot: int, ability_name: String, cooldown_fraction: float, seconds_left: float,
		cost: float, affordable: bool) -> void:
	_wing_names[slot].text = ability_name if not ability_name.is_empty() else "(empty)"
	_wing_names[slot].modulate.a = 1.0 if not ability_name.is_empty() else 0.45
	var ready := not ability_name.is_empty() and cooldown_fraction <= 0.0 and affordable
	var style := _wing_panels[slot].get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = WING_BORDER if ready else EMPTY_BORDER
	_wing_overlays[slot].visible = cooldown_fraction > 0.0
	_wing_overlays[slot].anchor_top = 1.0 - clampf(cooldown_fraction, 0.0, 1.0)
	_wing_timers[slot].visible = cooldown_fraction > 0.0
	_wing_timers[slot].text = "%.1f" % seconds_left if seconds_left < 10.0 else str(ceili(seconds_left))
	_wing_costs[slot].visible = not ability_name.is_empty()
	_wing_costs[slot].text = "%d" % roundi(cost)
	_wing_costs[slot].add_theme_color_override("font_color",
			EMBER_FILL if affordable else UNAFFORDABLE_COLOR)


## The Ember bar: value out of cap, with a marker at the Rebirth threshold, and
## the Rebirth line (e.g. "Rebirth ready", "Rebirth in 4:32"). rebirth_ready
## brightens the marker.
func set_ember(value: float, cap: float, threshold: float, rebirth_text: String,
		rebirth_ready: bool) -> void:
	_ember_bar.max_value = maxf(cap, 1.0)
	_ember_bar.value = value
	_ember_marker.anchor_left = clampf(threshold / maxf(cap, 1.0), 0.0, 1.0)
	_ember_marker.anchor_right = _ember_marker.anchor_left
	_ember_marker.color = EMBER_MARKER if rebirth_ready else Color(EMBER_MARKER, 0.4)
	_ember_label.text = "Ember %d   %s" % [floori(value), rebirth_text]


## How blind the local player is (0..1, StatusEffects.blind_amount): the haze's
## opacity. Drawn under the HUD's own widgets, so bars stay readable.
func set_blind(amount: float) -> void:
	_blind_overlay.color.a = clampf(amount, 0.0, 1.0)
	_blind_overlay.visible = amount > 0.0


## The local player's statuses, one chip each: [name, stacks, seconds left,
## is_debuff] per entry. Buffs have a green edge, debuffs red.
func set_statuses(entries: Array) -> void:
	while _status_row.get_child_count() < entries.size():
		_status_row.add_child(_build_status_chip())
	for i in _status_row.get_child_count():
		var chip := _status_row.get_child(i) as PanelContainer
		chip.visible = i < entries.size()
		if not chip.visible:
			continue
		var entry: Array = entries[i]
		var text: String = entry[0]
		if entry[1] > 1:
			text += " x%d" % entry[1]
		text += "  %.1fs" % entry[2]
		(chip.get_child(0) as Label).text = text
		var style := chip.get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = DEBUFF_BORDER if entry[3] else BUFF_BORDER


func _build_status_row() -> void:
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 6)
	_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status_row.offset_left = -400.0
	_status_row.offset_right = 400.0
	_status_row.offset_top = _weapon_label.offset_top - 30.0
	_status_row.offset_bottom = _weapon_label.offset_top - 4.0
	_status_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_row)


func _build_status_chip() -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = SLOT_COLOR
	style.set_border_width_all(0)
	style.border_width_bottom = 3
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	chip.add_child(label)
	return chip


## Three slots centered above the health bar, with the weapon line above them.
func _build_ability_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var width := SLOT_SIZE.x * 3 + 16
	bar.offset_left = -width / 2.0
	bar.offset_right = width / 2.0
	bar.offset_top = -96.0 - SLOT_SIZE.y
	bar.offset_bottom = -96.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(bar)
	for slot in SLOT_KEYS.size():
		bar.add_child(_build_slot(slot))

	_weapon_label = Label.new()
	_weapon_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_weapon_label.offset_left = -300.0
	_weapon_label.offset_right = 300.0
	_weapon_label.offset_top = bar.offset_top - 28.0
	_weapon_label.offset_bottom = bar.offset_top - 4.0
	_weapon_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_weapon_label.add_theme_constant_override("outline_size", 4)
	add_child(_weapon_label)


func _build_slot(slot: int) -> Panel:
	var parts := _make_slot(SLOT_KEYS[slot], SLOT_BORDER)
	_slot_panels.append(parts[0])
	_slot_names.append(parts[1])
	_slot_overlays.append(parts[2])
	_slot_timers.append(parts[3])
	return parts[0]


## Two Wing slots (Z, C) to the right of the ability bar, each with its Ember
## cost in the top-right corner.
func _build_wing_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var left := (SLOT_SIZE.x * 3 + 16) / 2.0 + 28.0
	bar.offset_left = left
	bar.offset_right = left + SLOT_SIZE.x * 2 + 8
	bar.offset_top = -96.0 - SLOT_SIZE.y
	bar.offset_bottom = -96.0
	add_child(bar)
	for slot in WING_KEYS.size():
		var parts := _make_slot(WING_KEYS[slot], WING_BORDER)
		var panel: Panel = parts[0]
		var cost := Label.new()
		cost.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		cost.offset_left = -40.0
		cost.offset_right = -6.0
		cost.offset_top = 1.0
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost.add_theme_font_size_override("font_size", 13)
		cost.add_theme_color_override("font_outline_color", Color.BLACK)
		cost.add_theme_constant_override("outline_size", 3)
		panel.add_child(cost)
		bar.add_child(panel)
		_wing_panels.append(panel)
		_wing_names.append(parts[1])
		_wing_overlays.append(parts[2])
		_wing_timers.append(parts[3])
		_wing_costs.append(cost)


## The Ember bar under the stamina bar, with a marker at the Rebirth threshold
## and a label (Ember, Rebirth state) to its right.
func _build_ember_bar() -> void:
	_ember_bar = ProgressBar.new()
	_ember_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ember_bar.offset_left = -150.0
	_ember_bar.offset_right = 150.0
	_ember_bar.offset_top = -47.0
	_ember_bar.offset_bottom = -39.0
	_ember_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ember_bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	background.set_corner_radius_all(3)
	_ember_bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = EMBER_FILL
	fill.set_corner_radius_all(3)
	_ember_bar.add_theme_stylebox_override("fill", fill)
	add_child(_ember_bar)
	_ember_marker = ColorRect.new()
	_ember_marker.color = EMBER_MARKER
	_ember_marker.anchor_top = 0.0
	_ember_marker.anchor_bottom = 1.0
	_ember_marker.offset_left = -1.0
	_ember_marker.offset_right = 1.0
	_ember_marker.offset_top = -3.0
	_ember_marker.offset_bottom = 3.0
	_ember_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ember_bar.add_child(_ember_marker)
	_ember_label = Label.new()
	_ember_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ember_label.offset_left = 158.0
	_ember_label.offset_right = 520.0
	_ember_label.offset_top = -52.0
	_ember_label.offset_bottom = -34.0
	_ember_label.add_theme_font_size_override("font_size", 13)
	_ember_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))
	_ember_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_ember_label.add_theme_constant_override("outline_size", 4)
	_ember_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_ember_label)


## One slot panel: [panel, name label, cooldown overlay, timer label].
func _make_slot(key_text: String, key_color: Color) -> Array:
	var panel := Panel.new()
	panel.custom_minimum_size = SLOT_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = SLOT_COLOR
	style.border_color = EMPTY_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var ability_name := Label.new()
	ability_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ability_name.offset_top = 14.0
	ability_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ability_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ability_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ability_name.add_theme_font_size_override("font_size", 13)
	panel.add_child(ability_name)

	var overlay := ColorRect.new()
	overlay.color = COOLDOWN_COLOR
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	panel.add_child(overlay)

	var timer := Label.new()
	timer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer.add_theme_font_size_override("font_size", 22)
	timer.add_theme_color_override("font_outline_color", Color.BLACK)
	timer.add_theme_constant_override("outline_size", 5)
	timer.visible = false
	panel.add_child(timer)

	var key := Label.new()
	key.text = key_text
	key.position = Vector2(6, 1)
	key.add_theme_color_override("font_color", key_color)
	key.add_theme_font_size_override("font_size", 13)
	panel.add_child(key)
	return [panel, ability_name, overlay, timer]
