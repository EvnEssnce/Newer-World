class_name CraftingPanel
extends Control
## The crafting panel (client only, built in code): F at a station opens it on
## that station's recipes (CraftingSystem.open_panel), grouped by tradeskill.
## Each recipe shows its output, its inputs as have/need (red when short), the
## level it needs (the row is dimmed and the line red when yours is too low), a
## quantity picker (1, 5, Max) and a Craft button. The numbers come from the
## bag and tradeskills the server last sent; the server checks again.
## Gear recipes add a line with what a craft can roll at your current level:
## the gear score range and each rarity's chance, in its color. The list
## scrolls when it's taller than the screen allows.
## A modal_ui panel like I, K and P: opening it closes them (and they close it),
## Esc, F or its X closes it, and CraftingSystem closes it when you walk out of
## range. Closing it cancels a craft under way (CraftingSystem._panel_closed).
## While one runs, a box under the title shows it (show_progress): the recipe,
## a bar filling over the whole batch, "3 / 5" and the time left; the Craft
## buttons wait for it.

const PANEL_WIDTH := 700.0
## Most of the viewport's height the recipe list takes before it scrolls.
const LIST_HEIGHT_FRACTION := 0.68
const QUANTITY_CHOICES: PackedStringArray = ["1", "5", "Max"]
const HINT_COLOR := Color(0.75, 0.75, 0.8)
const DETAIL_COLOR := Color(0.7, 0.72, 0.78)
const SECTION_COLOR := Color(0.95, 0.65, 0.35)
const HAVE_COLOR := Color(0.75, 0.92, 0.7)
const SHORT_COLOR := Color(1.0, 0.45, 0.4)
const OUTPUT_COLOR := Color.WHITE
const LOCKED_ALPHA := 0.55
const PROGRESS_FILL := Color(0.95, 0.6, 0.3)

var _system: CraftingSystem
var _title: Label
## The current craft's box: its name, bar and "3 / 5   1.4 s left".
var _progress_box: PanelContainer
var _progress_name: Label
var _progress_bar: ProgressBar
var _progress_status: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
## Recipe id -> {recipe, root, name, inputs (HBoxContainer), odds (gear: HBoxContainer of the gear\n## score label, then one label per rarity in rarity order; else null), status, quantity, craft, mode}.
var _rows: Dictionary[String, Dictionary] = {}


func setup(system: CraftingSystem) -> void:
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
	style.bg_color = Color(0.08, 0.07, 0.07, 0.95)
	style.border_color = Color(0.95, 0.6, 0.3, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override(&"panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = _label("", 20, Color.WHITE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "Close (cancels a craft under way)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(32, 30)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(_build_progress_box())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var hint := _label("Stay at the station with this panel open while you craft. The materials are only taken when the bar fills; moving, getting hit or closing the panel cancels it and nothing is lost. F, Esc or X closes.",
			12, HINT_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = PANEL_WIDTH - 28.0
	column.add_child(hint)


func _build_progress_box() -> Control:
	_progress_box = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.13, 0.08, 0.95)
	style.border_color = Color(0.95, 0.6, 0.3, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_progress_box.add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	_progress_box.add_child(box)
	var line := HBoxContainer.new()
	box.add_child(line)
	var crafting := _label("Crafting", 13, SECTION_COLOR)
	crafting.custom_minimum_size.x = 80
	line.add_child(crafting)
	_progress_name = _label("", 15, OUTPUT_COLOR)
	_progress_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_progress_name)
	_progress_status = _label("", 14, Color.WHITE)
	line.add_child(_progress_status)
	_progress_bar = ProgressBar.new()
	_progress_bar.show_percentage = false
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.custom_minimum_size.y = 14
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = PROGRESS_FILL
	fill.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override(&"fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.04, 0.04, 0.9)
	back.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override(&"background", back)
	box.add_child(_progress_bar)
	_progress_box.visible = false
	return _progress_box


## The current craft (CraftingSystem._progress_view, every frame while open):
## [recipe name, fraction 0..1, "3 / 5   1.4 s left"], or [] to hide the box.
func show_progress(view: Array) -> void:
	if _progress_box == null:
		return
	var crafting := view.size() >= 3
	if crafting != _progress_box.visible:
		_progress_box.visible = crafting
		refresh()  # the Craft buttons wait while one runs
	if not crafting:
		return
	_progress_name.text = view[0]
	_progress_bar.value = view[1]
	_progress_status.text = view[2]


## Shows `station`'s recipes, grouped by tradeskill (in the Tradeskills panel's order).
func open(station: RecipeDefs.StationDef, recipes: Array[RecipeDefs.Recipe]) -> void:
	_title.text = station.name
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	var skills := _system.tradeskills.defs
	var skill_ids: Array[String] = []
	for id in skills.order:
		skill_ids.append(id)
	for recipe in recipes:
		if not recipe.tradeskill in skill_ids:
			skill_ids.append(recipe.tradeskill)
	for skill in skill_ids:
		var group := recipes.filter(func(r: RecipeDefs.Recipe) -> bool: return r.tradeskill == skill)
		if group.is_empty():
			continue
		var header := _label("", 15, SECTION_COLOR)
		header.set_meta(&"skill", skill)
		header.custom_minimum_size.y = 24
		header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_list.add_child(header)
		for recipe: RecipeDefs.Recipe in group:
			_list.add_child(_recipe_row(recipe))
	if recipes.is_empty():
		_list.add_child(_label("Nothing to make here yet.", 14, DETAIL_COLOR))
	if not visible:
		visible = true
		InventoryPanel.hide_other_modals(self)  # one mouse panel at a time
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_scroll.scroll_vertical = 0
	refresh()
	_fit_list.call_deferred()


## The list as tall as its rows, up to LIST_HEIGHT_FRACTION of the viewport (then it scrolls).
func _fit_list() -> void:
	var most := get_viewport_rect().size.y * LIST_HEIGHT_FRACTION
	_scroll.custom_minimum_size.y = minf(_list.get_combined_minimum_size().y, most)


func close() -> void:
	if not visible:
		return
	visible = false
	if not InventoryPanel.other_modal_open(self):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # back to the game


## Esc closes the panel (before Player's Esc handling frees the mouse).
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _recipe_row(recipe: RecipeDefs.Recipe) -> Control:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.12, 0.11, 0.9)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	frame.add_theme_stylebox_override(&"panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	frame.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 2)
	row.add_child(info)
	var name_label := _label("", 15, OUTPUT_COLOR)
	info.add_child(name_label)
	var inputs := HBoxContainer.new()
	inputs.add_theme_constant_override(&"separation", 14)
	info.add_child(inputs)
	for item_id in recipe.inputs:
		var input_label := _label("", 13, HAVE_COLOR)
		input_label.set_meta(&"item", item_id)
		inputs.add_child(input_label)
	var odds: HBoxContainer = null
	if recipe.output_kind == RecipeDefs.OUTPUT_GEAR:
		odds = HBoxContainer.new()
		odds.add_theme_constant_override(&"separation", 12)
		info.add_child(odds)
		odds.add_child(_label("", 13, OUTPUT_COLOR))  # the gear score range
		var db := ItemDatabase.current()
		for rarity in db.rarity_order:
			var rarity_label := _label("", 13, db.rarities[rarity].color)
			rarity_label.set_meta(&"rarity", rarity)
			odds.add_child(rarity_label)
	var status := _label("", 12, DETAIL_COLOR)
	info.add_child(status)
	var picker := HBoxContainer.new()
	picker.add_theme_constant_override(&"separation", 2)
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(picker)
	var group := ButtonGroup.new()
	for i in QUANTITY_CHOICES.size():
		var choice := Button.new()
		choice.text = QUANTITY_CHOICES[i]
		choice.toggle_mode = true
		choice.button_group = group
		choice.button_pressed = i == 0
		choice.focus_mode = Control.FOCUS_NONE  # Space/Enter stay the game's
		choice.custom_minimum_size = Vector2(44, 30)
		choice.pressed.connect(_set_mode.bind(recipe.id, i))
		picker.add_child(choice)
	var quantity := _label("", 14, Color.WHITE)
	quantity.custom_minimum_size.x = 44
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(quantity)
	var craft := Button.new()
	craft.text = "Craft"
	craft.focus_mode = Control.FOCUS_NONE
	craft.custom_minimum_size = Vector2(84, 34)
	craft.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	craft.pressed.connect(_craft.bind(recipe.id))
	row.add_child(craft)
	_rows[recipe.id] = {"recipe": recipe, "root": frame, "name": name_label, "inputs": inputs, "odds": odds,
			"status": status, "quantity": quantity, "craft": craft, "mode": 0}
	return frame


func _set_mode(recipe_id: String, mode: int) -> void:
	if _rows.has(recipe_id):
		_rows[recipe_id]["mode"] = mode
		refresh()


func _craft(recipe_id: String) -> void:
	var quantity := _quantity(_rows[recipe_id])
	if quantity > 0:
		_system.request_craft(recipe_id, quantity)
		refresh()


## The quantity a row's picker means now (Max = as many as you can, 0 if none).
func _quantity(row: Dictionary) -> int:
	var recipe: RecipeDefs.Recipe = row["recipe"]
	match int(row["mode"]):
		0:
			return 1
		1:
			return mini(5, _system.defs.max_batch)
	return CraftingRules.max_quantity(recipe, _system.local_bag(),
			_system.local_level(recipe.tradeskill), ItemDatabase.current(), _system.defs.max_batch)


## Updates every number from the local bag and tradeskills.
func refresh() -> void:
	if _system == null or not visible:
		return
	var db := ItemDatabase.current()
	var skills := _system.tradeskills.defs
	var bag := _system.local_bag()
	for child in _list.get_children():
		if child.has_meta(&"skill"):
			var skill: String = child.get_meta(&"skill")
			(child as Label).text = "%s   Lv %d" % [skills.display_name(skill), _system.local_level(skill)]
	for recipe_id: String in _rows:
		var row := _rows[recipe_id]
		var recipe: RecipeDefs.Recipe = row["recipe"]
		var level := _system.local_level(recipe.tradeskill)
		var locked := level < recipe.level
		var quantity := _quantity(row)
		var shown := maxi(1, quantity)
		(row["root"] as Control).modulate.a = LOCKED_ALPHA if locked else 1.0
		var made := CraftingRules.made(recipe, shown)
		(row["name"] as Label).text = "%s  x%d" % [recipe.display_name(db), made]
		for input_label: Label in (row["inputs"] as HBoxContainer).get_children():
			var item_id: String = input_label.get_meta(&"item")
			var need: int = recipe.inputs[item_id] * shown
			var have := bag.count_of(item_id)
			var def: ItemDatabase.ItemDef = db.items.get(item_id)
			input_label.text = "%s  %d/%d" % [def.name if def else item_id, have, need]
			input_label.add_theme_color_override(&"font_color", HAVE_COLOR if have >= need else SHORT_COLOR)
		if row["odds"] != null:
			_show_odds(row["odds"], skills, level, db)
		var error := CraftingRules.check(recipe, shown, bag, level, db, _system.defs.max_batch, skills)
		if quantity == 0 and error.is_empty():
			error = "Nothing to craft."
		var status: Label = row["status"]
		if locked:
			status.text = "Requires %s %d (you have %d)" % [skills.display_name(recipe.tradeskill), recipe.level, level]
			status.add_theme_color_override(&"font_color", SHORT_COLOR)
		elif not error.is_empty() and not error.begins_with("Not enough"):
			status.text = error  # the bag is full, mostly (short inputs are red above)
			status.add_theme_color_override(&"font_color", SHORT_COLOR)
		else:
			status.text = "Requires %s %d   %.1f s each   +%d XP each" % [
					skills.display_name(recipe.tradeskill), recipe.level,
					recipe.craft_ticks / float(Engine.physics_ticks_per_second), recipe.xp]
			status.add_theme_color_override(&"font_color", DETAIL_COLOR)
		(row["quantity"] as Label).text = "x%d" % quantity
		(row["craft"] as Button).disabled = quantity == 0 or not error.is_empty() or _system.crafting()


## A gear recipe's roll at `level`: "GS 100-110", then "Rare 14%" per rarity
## that can roll (others hidden).
func _show_odds(odds: HBoxContainer, skills: TradeskillDefs, level: int, db: ItemDatabase) -> void:
	var gs_range := skills.gear_score_range(level)
	(odds.get_child(0) as Label).text = "GS %d–%d" % [gs_range.x, gs_range.y]
	var chances := skills.gear_rarity_odds(level)
	for i in range(1, odds.get_child_count()):
		var label := odds.get_child(i) as Label
		var rarity: String = label.get_meta(&"rarity")
		var chance: float = chances.get(rarity, 0.0)
		label.visible = chance > 0.0
		var rarity_def: ItemDatabase.RarityDef = db.rarities.get(rarity)
		label.text = "%s %s%%" % [rarity_def.name if rarity_def else rarity, _percent(chance)]


## A chance as a short percent: "14", "2.7", "0.4".
static func _percent(chance: float) -> String:
	var percent := chance * 100.0
	if percent >= 10.0 or is_equal_approx(percent, roundf(percent)):
		return str(roundi(percent))
	return "%.1f" % percent


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
