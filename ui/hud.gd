class_name Hud
extends CanvasLayer
## In-game overlay: health and stamina bars, ability bar, current weapon,
## connection stats and controls. The ability bar is built in code.

const SLOT_KEYS := ["Q", "E", "R"]
const SLOT_SIZE := Vector2(116, 58)
const SLOT_COLOR := Color(0.08, 0.09, 0.12, 0.8)
const SLOT_BORDER := Color(0.85, 0.7, 0.35, 0.9)
const EMPTY_BORDER := Color(0.4, 0.4, 0.45, 0.6)
const COOLDOWN_COLOR := Color(0.0, 0.0, 0.0, 0.6)

@onready var _info: Label = %Info
@onready var _health: ProgressBar = %Health
@onready var _stamina: ProgressBar = %Stamina
@onready var _banner: Label = %Banner

var _weapon_label: Label
var _slot_panels: Array[Panel] = []
var _slot_names: Array[Label] = []
var _slot_overlays: Array[ColorRect] = []
var _slot_timers: Array[Label] = []


func _ready() -> void:
	_build_ability_bar()


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
	key.text = SLOT_KEYS[slot]
	key.position = Vector2(6, 1)
	key.add_theme_color_override("font_color", SLOT_BORDER)
	key.add_theme_font_size_override("font_size", 13)
	panel.add_child(key)

	_slot_panels.append(panel)
	_slot_names.append(ability_name)
	_slot_overlays.append(overlay)
	_slot_timers.append(timer)
	return panel
