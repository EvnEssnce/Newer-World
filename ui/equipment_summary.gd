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


## One equip slot's symbol, drawn in code (ItemIcon.draw_glyph): the equipped
## item's icon (crossed swords or a bow for a weapon), else the slot's.
class SlotIcon extends Control:
	var equip_slot := ""
	var color := EMPTY_COLOR
	var equipped := false
	var icon := ""

	func _init(slot: String) -> void:
		equip_slot = slot
		icon = "sword" if slot.begins_with("weapon") else slot
		custom_minimum_size = ICON_SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_item(item_color: Color, is_equipped: bool, item_icon: String) -> void:
		color = item_color
		equipped = is_equipped
		icon = item_icon
		queue_redraw()

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		var back := Color(color, 0.22) if equipped else Color(0.05, 0.05, 0.07, 0.6)
		draw_rect(box, back)
		draw_rect(box.grow(-0.5), Color(color, 0.95 if equipped else 0.6), false, 1.0)
		var glyph := color.lightened(0.25) if equipped else Color(EMPTY_COLOR, 0.8)
		# Shapes are laid out on a 24 x 24 grid, scaled to the icon.
		draw_set_transform(Vector2(1, 1), 0.0, (size - Vector2(2, 2)) / 24.0)
		ItemIcon.draw_glyph(self, icon, glyph, back)
		if equip_slot.begins_with("weapon"):
			draw_string(ThemeDB.fallback_font, Vector2(17, 23),
					"1" if equip_slot == "weapon_1" else "2",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE if equipped else glyph)
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
		var def: ItemDatabase.ItemDef = _db.items.get(item.item_id) if item else null
		var empty_icon := "sword" if icon.equip_slot.begins_with("weapon") else icon.equip_slot
		icon.set_item(item.rarity_color(_db) if item else EMPTY_COLOR, item != null,
				def.icon_id() if def else empty_icon)
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
