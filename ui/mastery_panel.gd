class_name MasteryPanel
extends Control
## Weapon mastery panel, toggled with K (client only, built in code). Shows one
## weapon's tree at a time: two branch columns of tiers, each node a button
## (click to allocate, click again to refund it and whatever needed it). Active
## nodes that are allocated get Q / E / R buttons to slot their ability.
##
## Every change sends the weapon's whole allocation and slots to the server
## (BuildService.request_mastery), which validates it; the panel redraws from
## the server's reply, so it always shows the real build.

const PANEL_SIZE := Vector2(900, 500)
const ALLOCATED_COLOR := Color(0.55, 1.0, 0.6)
const ERROR_COLOR := Color(1.0, 0.5, 0.45)
const HINT_COLOR := Color(0.75, 0.75, 0.8)
const TIER_NAMES := ["Tier 1", "Tier 2", "Tier 3", "Capstone"]

var _builds: BuildService
## The weapon whose tree is shown.
var _weapon_id := ""
var _content: VBoxContainer


func setup(builds: BuildService) -> void:
	_builds = builds
	_builds.build_changed.connect(_refresh)


func _ready() -> void:
	visible = false
	add_to_group(&"modal_ui")  # Player won't capture the mouse while it's open
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallows clicks so they don't reach the game (which captures the mouse).
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -PANEL_SIZE.x / 2.0
	panel.offset_right = PANEL_SIZE.x / 2.0
	panel.offset_top = -PANEL_SIZE.y / 2.0
	panel.offset_bottom = PANEL_SIZE.y / 2.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.95)
	style.border_color = Color(0.85, 0.7, 0.35, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)


func toggle() -> void:
	visible = not visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # back to the game


## Esc closes the panel like K (before Player's Esc handling frees the mouse).
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if _content == null or not visible:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var build := _builds.local_build if _builds else null
	if build == null:
		_content.add_child(_label("Waiting for the server...", HINT_COLOR))
		return
	if not build.trees.has(_weapon_id):
		_weapon_id = build.weapons[0] if not build.weapons.is_empty() else ""
	var tree: MasteryTree = build.trees.get(_weapon_id)
	if tree == null:
		_content.add_child(_label("No mastery tree.", HINT_COLOR))
		return
	var nodes := build.get_allocated(_weapon_id)
	var slots := build.get_slots(_weapon_id)

	_content.add_child(_header(build, tree, nodes))
	_content.add_child(_slot_row(tree, nodes, slots))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	for b in tree.branches.size():
		columns.add_child(_branch_column(tree, b, nodes, slots))
	_content.add_child(columns)
	if not _builds.last_message.is_empty():
		_content.add_child(_label(_builds.last_message, ERROR_COLOR, true))
	_content.add_child(_label(
			"Click a node to learn it, click it again to unlearn it. Respecs are free. K closes.",
			HINT_COLOR, true))


func _header(build: CharacterBuild, tree: MasteryTree, nodes: PackedStringArray) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var title := _label("%s mastery" % build.class_def.display_name, Color.WHITE)
	title.add_theme_font_size_override("font_size", 20)
	row.add_child(title)
	for weapon_id in build.class_def.weapons:
		if not build.trees.has(weapon_id):
			continue
		var tab := Button.new()
		var weapon := PlayerParams.current().weapon(weapon_id)
		tab.text = weapon.display_name
		tab.toggle_mode = true
		tab.button_pressed = weapon_id == _weapon_id
		tab.pressed.connect(_select_weapon.bind(weapon_id))
		row.add_child(tab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_label("Points: %d / %d" % [tree.spent(nodes), tree.points], Color.WHITE))
	var reset := Button.new()
	reset.text = "Unlearn all"
	reset.pressed.connect(_send.bind(PackedStringArray(), PackedStringArray(["", "", ""])))
	row.add_child(reset)
	var defaults := Button.new()
	defaults.text = "Default"
	defaults.pressed.connect(_send.bind(tree.default_nodes, tree.default_slots))
	row.add_child(defaults)
	return row


func _slot_row(tree: MasteryTree, nodes: PackedStringArray, slots: PackedStringArray) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label("Ability slots:", Color.WHITE))
	for slot in slots.size():
		var button := Button.new()
		var ability := slots[slot]
		button.text = "%s: %s" % [Hud.SLOT_KEYS[slot], _ability_name(ability) if ability else "(empty)"]
		button.tooltip_text = "Click to empty this slot."
		button.disabled = ability.is_empty()
		var cleared := slots.duplicate()
		cleared[slot] = ""
		button.pressed.connect(_send.bind(nodes, cleared))
		row.add_child(button)
	return row


func _branch_column(tree: MasteryTree, branch_index: int, nodes: PackedStringArray,
		slots: PackedStringArray) -> Control:
	var branch := tree.branches[branch_index]
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label("%s  (%d points)" % [tree.branch_names[branch_index],
			tree.spent_in_branch(nodes, branch)], Color(0.95, 0.8, 0.45))
	title.add_theme_font_size_override("font_size", 17)
	column.add_child(title)
	for tier in range(1, tree.tier_count() + 1):
		var open := tree.is_tier_open(nodes, branch, tier)
		var tier_name: String = TIER_NAMES[mini(tier - 1, TIER_NAMES.size() - 1)]
		var caption := tier_name if open else "%s (needs %d points in lower tiers)" % [
				tier_name, tree.tier_requirements[tier - 1]]
		column.add_child(_label(caption, HINT_COLOR if open else ERROR_COLOR.darkened(0.2)))
		var row := HFlowContainer.new()
		for id in tree.node_order:
			var n := tree.get_node(id)
			if n.branch == branch and n.tier == tier:
				row.add_child(_node_card(tree, n, nodes, slots))
		column.add_child(row)
	return column


func _node_card(tree: MasteryTree, n: MasteryTree.MasteryNode, nodes: PackedStringArray,
		slots: PackedStringArray) -> Control:
	var card := VBoxContainer.new()
	var button := Button.new()
	var learned := n.id in nodes
	button.text = "%s\n%s, %d pt" % [n.display_name, n.kind, n.cost]
	button.tooltip_text = n.description
	button.custom_minimum_size = Vector2(140, 0)
	if learned:
		button.modulate = ALLOCATED_COLOR
		button.pressed.connect(_send_unlearn.bind(n.id))
	else:
		button.disabled = not tree.can_add(nodes, n.id)
		button.pressed.connect(_send_learn.bind(n.id))
	card.add_child(button)
	if learned and n.kind == MasteryTree.KIND_ACTIVE:
		var slot_row := HBoxContainer.new()
		for slot in PlayerState.ABILITY_SLOTS:
			var slot_button := Button.new()
			slot_button.text = Hud.SLOT_KEYS[slot]
			slot_button.toggle_mode = true
			slot_button.button_pressed = slots[slot] == n.ability
			slot_button.tooltip_text = "Put %s in slot %s" % [n.display_name, Hud.SLOT_KEYS[slot]]
			slot_button.pressed.connect(_send_slot.bind(n.ability, slot))
			slot_row.add_child(slot_button)
		card.add_child(slot_row)
	return card


func _select_weapon(weapon_id: String) -> void:
	_weapon_id = weapon_id
	_builds.last_message = ""
	_refresh()


func _send_learn(id: String) -> void:
	var build := _builds.local_build
	var nodes := build.get_allocated(_weapon_id).duplicate()
	nodes.append(id)
	_send(nodes, build.get_slots(_weapon_id))


## Unlearns a node and whatever needed it; empties slots that lose their ability.
func _send_unlearn(id: String) -> void:
	var build := _builds.local_build
	var tree: MasteryTree = build.trees[_weapon_id]
	_send(tree.remove(build.get_allocated(_weapon_id), id), build.get_slots(_weapon_id))


## Slots an ability (taking it out of any other slot it was in).
func _send_slot(ability: String, slot: int) -> void:
	var build := _builds.local_build
	var slots := build.get_slots(_weapon_id).duplicate()
	for i in slots.size():
		if slots[i] == ability:
			slots[i] = ""
	slots[slot] = ability
	_send(build.get_allocated(_weapon_id), slots)


func _send(nodes: PackedStringArray, slots: PackedStringArray) -> void:
	var tree: MasteryTree = _builds.local_build.trees[_weapon_id]
	var unlocked := tree.unlocked_abilities(nodes)
	var kept := slots.duplicate()
	for i in kept.size():
		if not (kept[i] in unlocked):
			kept[i] = ""
	_builds.request_mastery(_weapon_id, nodes, kept)


func _ability_name(ability_id: String) -> String:
	var weapon := PlayerParams.current().weapon(_weapon_id)
	var index := weapon.ability_index(ability_id)
	return weapon.abilities[index].display_name if index >= 0 else ability_id


## wrap: only for labels that get a full row (in a VBox); in an HBox a wrapping
## label would shrink to nothing.
static func _label(text: String, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
