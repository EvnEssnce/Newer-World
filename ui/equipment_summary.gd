class_name EquipmentSummary
extends PanelContainer
## Small HUD box in the top-right corner (client, built in code): the average
## gear score, one symbol per equip slot (Weapon 1, Weapon 2, Head, Chest, Legs,
## Wing Enhancement; tinted with the item's rarity colour when something is
## equipped, dim when empty) and what the gear adds up to
## (Equipment.Stats.summary_lines). Shows LootSystem.equipment, the copy the
## server last sent, and redraws when a new copy arrives.

const MARGIN := 12.0
const ICON_SIZE := Vector2(26, 26)
const TITLE_COLOR := Color(0.55, 0.75, 0.9)
const STAT_COLOR := Color(0.88, 0.88, 0.9)
const HINT_COLOR := Color(0.65, 0.65, 0.7)
const EMPTY_COLOR := Color(0.4, 0.4, 0.45)

var _loot: LootSystem
var _db: ItemDatabase
## The Equipment shown; LootSystem replaces the object on every update.
var _shown: Equipment
var _title: Label
var _icons: Array[SlotIcon] = []
var _stats: Label


## One equip slot's symbol, drawn in code.
class SlotIcon extends Control:
	var equip_slot := ""
	var color := EMPTY_COLOR
	var equipped := false

	func _init(slot: String) -> void:
		equip_slot = slot
		custom_minimum_size = ICON_SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_item_color(item_color: Color, is_equipped: bool) -> void:
		color = item_color
		equipped = is_equipped
		queue_redraw()

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		var back := Color(color, 0.22) if equipped else Color(0.05, 0.05, 0.07, 0.6)
		draw_rect(box, back)
		draw_rect(box.grow(-0.5), Color(color, 0.95 if equipped else 0.6), false, 1.0)
		var glyph := color.lightened(0.25) if equipped else Color(EMPTY_COLOR, 0.8)
		# Shapes are laid out on a 24 x 24 grid, scaled to the icon.
		draw_set_transform(Vector2(1, 1), 0.0, (size - Vector2(2, 2)) / 24.0)
		match equip_slot:
			"weapon_1", "weapon_2":
				draw_line(Vector2(5, 19), Vector2(17, 7), glyph, 2.5)  # blade
				draw_colored_polygon(PackedVector2Array([Vector2(16, 5), Vector2(19, 5),
						Vector2(19, 8), Vector2(17, 7)]), glyph)  # tip
				draw_line(Vector2(4, 14), Vector2(10, 20), glyph, 2.0)  # guard
				draw_string(ThemeDB.fallback_font, Vector2(15, 22),
						"1" if equip_slot == "weapon_1" else "2",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 9, glyph)
			"head":
				var dome := PackedVector2Array()
				for i in 9:
					dome.append(Vector2(12, 14) + Vector2.from_angle(PI + PI * i / 8.0) * 8.0)
				draw_colored_polygon(dome, glyph)
				draw_rect(Rect2(3, 14, 18, 3), glyph)  # brim
				draw_rect(Rect2(11, 7, 2, 7), back.darkened(0.5))  # nose guard gap
			"chest":
				draw_colored_polygon(PackedVector2Array([Vector2(8, 4), Vector2(10, 4),
						Vector2(12, 7), Vector2(14, 4), Vector2(16, 4), Vector2(21, 8),
						Vector2(18, 12), Vector2(17, 11), Vector2(17, 20), Vector2(7, 20),
						Vector2(7, 11), Vector2(6, 12), Vector2(3, 8)]), glyph)
			"legs":
				draw_rect(Rect2(6, 4, 12, 4), glyph)  # belt
				draw_colored_polygon(PackedVector2Array([Vector2(6, 9), Vector2(11.5, 9),
						Vector2(10.5, 21), Vector2(6, 21)]), glyph)
				draw_colored_polygon(PackedVector2Array([Vector2(12.5, 9), Vector2(18, 9),
						Vector2(18, 21), Vector2(13.5, 21)]), glyph)
			"wings":
				draw_colored_polygon(PackedVector2Array([Vector2(11, 9), Vector2(5, 4),
						Vector2(2, 8), Vector2(3, 14), Vector2(6, 18), Vector2(11, 14)]), glyph)
				draw_colored_polygon(PackedVector2Array([Vector2(13, 9), Vector2(19, 4),
						Vector2(22, 8), Vector2(21, 14), Vector2(18, 18), Vector2(13, 14)]), glyph)
				draw_circle(Vector2(12, 11), 1.6, glyph)
		draw_set_transform(Vector2.ZERO)


func setup(loot: LootSystem) -> void:
	_loot = loot
	_db = ItemDatabase.current()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.7)
	style.border_color = Color(TITLE_COLOR, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(7)
	add_theme_stylebox_override(&"panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_title = _label(13, TITLE_COLOR)
	column.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	for equip_slot in Equipment.SLOTS:
		var icon := SlotIcon.new(equip_slot)
		_icons.append(icon)
		row.add_child(icon)
	_stats = _label(12, STAT_COLOR)
	column.add_child(_stats)
	visible = false  # until setup


func _process(_delta: float) -> void:
	if _loot == null:
		return
	visible = true
	if _loot.equipment != _shown:
		_shown = _loot.equipment
		_refresh()
	# Hug the top-right corner at the content's size (grows and shrinks leftward).
	var min_size := get_combined_minimum_size()
	offset_right = -MARGIN
	offset_left = -MARGIN - min_size.x
	offset_top = MARGIN
	offset_bottom = MARGIN + min_size.y


func _refresh() -> void:
	var stats := _shown.stats(_db, GearScore.current().average_weights)
	_title.text = "Gear score %d" % roundi(stats.average_gear_score)
	for icon in _icons:
		var item := _shown.get_item(icon.equip_slot)
		icon.set_item_color(item.rarity_color(_db) if item else EMPTY_COLOR, item != null)
	var lines := stats.summary_lines()
	if lines.is_empty():
		_stats.text = "No gear bonuses"
		_stats.add_theme_color_override(&"font_color", HINT_COLOR)
	else:
		_stats.text = "\n".join(lines)
		_stats.add_theme_color_override(&"font_color", STAT_COLOR)


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_constant_override(&"outline_size", 3)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
