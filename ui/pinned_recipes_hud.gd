class_name PinnedRecipesHud
extends PanelContainer
## The pinned recipes on the HUD (client only, built in code), on the right
## below the gear box: each pinned recipe's name and its materials as have/need
## for one craft (green when you have enough, red when short), so you can see
## what's left to gather. Pins come from the Forge panel's Pin buttons
## (CraftingSystem.pins); hidden while the Forge panel is open (its Pinned tab
## shows them) and when nothing is pinned.

const WIDTH := 270.0
const MARGIN := 16.0
## Below the gear box (EquipmentSummary) in the top right.
const TOP := 300.0
const REFRESH := 0.5
const TITLE_COLOR := Color(1.0, 0.85, 0.35)
const NAME_COLOR := Color.WHITE
const HAVE_COLOR := Color(0.75, 0.92, 0.7)
const SHORT_COLOR := Color(1.0, 0.5, 0.45)

var _system: CraftingSystem
var _column: VBoxContainer
## One entry per pinned recipe: [recipe, [input Label...] in recipe.inputs order].
var _entries: Array[Array] = []
var _timer := 0.0


func setup(system: CraftingSystem) -> void:
	_system = system


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_right = -MARGIN
	offset_left = -MARGIN - WIDTH
	offset_top = TOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	add_theme_stylebox_override(&"panel", style)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override(&"separation", 2)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	rebuild()


## Rebuilds the list from the pins (CraftingSystem.toggle_pin calls it).
func rebuild() -> void:
	if _column == null:
		return
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	_entries.clear()
	_column.add_child(_label("Pinned recipes", 13, TITLE_COLOR))
	var db := ItemDatabase.current()
	for id in _system.pins.ids:
		var recipe := _system.defs.get_recipe(id)
		if recipe == null:
			continue
		var title := _label(recipe.display_name(db), 14, NAME_COLOR)
		title.clip_text = true
		_column.add_child(title)
		var inputs: Array[Label] = []
		for item_id in recipe.inputs:
			var line := _label("", 12, HAVE_COLOR)
			line.set_meta(&"item", item_id)
			_column.add_child(line)
			inputs.append(line)
		_entries.append([recipe, inputs])
	_timer = 0.0
	_update()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		_update()


func _update() -> void:
	visible = not _entries.is_empty() and not _system.panel_open()
	if not visible:
		return
	var db := ItemDatabase.current()
	var bag := _system.local_bag()
	for entry in _entries:
		var recipe: RecipeDefs.Recipe = entry[0]
		for line: Label in entry[1]:
			var item_id: String = line.get_meta(&"item")
			var need: int = recipe.inputs[item_id]
			var have := bag.count_of(item_id)
			var def: ItemDatabase.ItemDef = db.items.get(item_id)
			line.text = "   %s  %d/%d" % [def.name if def else item_id, have, need]
			line.add_theme_color_override(&"font_color", HAVE_COLOR if have >= need else SHORT_COLOR)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
