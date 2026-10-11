class_name MasteryPanel
extends Control
## Weapon mastery panel, toggled with K (client only, built in code). Shows one
## weapon's tree at a time (or the class's Wing tree on the "Wings" tab): two
## branch columns of tiers, each node a button (click to allocate, click again
## to refund it and whatever needed it). Active nodes that are allocated get
## Q / E / R buttons (Z / C on the Wings tab) to slot their ability.
##
## Every change sends the weapon's whole allocation and slots to the server
## (BuildService.request_mastery), which validates it; the panel redraws from
## the server's reply, so it always shows the real build.

const PANEL_SIZE := Vector2(900, 500)
const ALLOCATED_COLOR := Color(0.55, 1.0, 0.6)
const ERROR_COLOR := Color(1.0, 0.5, 0.45)
const HINT_COLOR := Color(0.75, 0.75, 0.8)
const TIER_NAMES := ["Tier 1", "Tier 2", "Tier 3", "Capstone"]
## _weapon_id of the Wings tab (the class's Wing tree, slots Z / C).
const WINGS := "@wings"

var _builds: BuildService
## The weapon whose tree is shown, or WINGS.
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
	if not build.trees.has(_weapon_id) and not (_weapon_id == WINGS and build.wing_tree):
		_weapon_id = build.weapons[0] if not build.weapons.is_empty() else ""
	var tree := _current_tree()
	if tree == null:
		_content.add_child(_label("No mastery tree.", HINT_COLOR))
		return
	var nodes := _current_nodes()
	var slots := _current_slots()

	_content.add_child(_header(build, tree, nodes))
	if BuildService.class_change_enabled():
		_content.add_child(_class_row(build))
	_content.add_child(_weapon_row(build))
	_content.add_child(_slot_row(tree, nodes, slots))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	for b in tree.branches.size():
		columns.add_child(_branch_column(tree, b, nodes, slots))
	_content.add_child(columns)
	if not _builds.last_message.is_empty():
		_content.add_child(_label(_builds.last_message, ERROR_COLOR, true))
	var hint := "Click a node to learn it, click it again to unlearn it. Pick each slot's ability above, or with the %s buttons under a learned ability. Respecs are free. K or Esc closes." % " / ".join(_slot_keys())
	if _weapon_id == WINGS:
		hint = "Wing abilities cost Ember and stay on Z / C whichever weapon is out. Dying with 50 Ember or more brings you back (Rebirth). " + hint
	_content.add_child(_label(hint, HINT_COLOR, true))


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
	if build.wing_tree:
		var wings_tab := Button.new()
		wings_tab.text = "Wings"
		wings_tab.tooltip_text = "Wing abilities (Z / C): the same whichever weapon is out."
		wings_tab.toggle_mode = true
		wings_tab.button_pressed = _weapon_id == WINGS
		wings_tab.pressed.connect(_select_weapon.bind(WINGS))
		row.add_child(wings_tab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_label("Points: %d / %d" % [tree.spent(nodes), tree.points], Color.WHITE))
	var reset := Button.new()
	reset.text = "Unlearn all"
	var empty_slots := PackedStringArray()
	empty_slots.resize(tree.slot_count)
	reset.pressed.connect(_send.bind(PackedStringArray(), empty_slots))
	row.add_child(reset)
	var defaults := Button.new()
	defaults.text = "Default"
	defaults.pressed.connect(_send.bind(tree.default_nodes, tree.default_slots))
	row.add_child(defaults)
	return row


## Test tool (data/testing.cfg): every class; picking one asks the server to
## switch (BuildService.request_class). The panel redraws from the reply, so a
## refused switch (in combat, mid-action) snaps back and shows why.
func _class_row(build: CharacterBuild) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label("Class:", Color.WHITE))
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(150, 0)
	picker.tooltip_text = "Switch class (test tool). Out of combat only; starts you fresh with the class's default build."
	for class_id in ClassDef.all_ids():
		var class_def := ClassDef.for_id(class_id)
		if class_def == null:
			continue
		picker.add_item(class_def.display_name)
		picker.set_item_metadata(picker.item_count - 1, class_id)
		if class_def == build.class_def:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void:
		_builds.request_class(picker.get_item_metadata(index)))
	row.add_child(picker)
	var note := _label("Test tool: out of combat only. Resets health, Ember, cooldowns and your build to the class's defaults.", HINT_COLOR, true)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	return row


## The two equipped weapons, each picked from the class's weapon list. Picking
## the weapon already in the other slot swaps them. The server validates it
## (and refuses mid-attack, mid-ability or mid-swap).
func _weapon_row(build: CharacterBuild) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label("Equipped weapons:", Color.WHITE))
	for slot in build.weapons.size():
		row.add_child(_label("%d:" % (slot + 1), Color.WHITE))
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(150, 0)
		picker.tooltip_text = "Choose weapon %d (X swaps between the two)." % (slot + 1)
		for weapon_id in build.class_def.weapons:
			picker.add_item(PlayerParams.current().weapon(weapon_id).display_name)
			picker.set_item_metadata(picker.item_count - 1, weapon_id)
			if weapon_id == build.weapons[slot]:
				picker.select(picker.item_count - 1)
		picker.item_selected.connect(func(index: int) -> void:
			_builds.request_weapons(CharacterBuild.loadout_with(
					_builds.local_build.weapons, slot, picker.get_item_metadata(index))))
		row.add_child(picker)
	return row


func _slot_row(tree: MasteryTree, nodes: PackedStringArray, slots: PackedStringArray) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label("Ability slots:", Color.WHITE))
	# Each slot picks from the learned abilities (or empty), so an emptied slot can
	# always be filled again.
	var unlocked := tree.unlocked_abilities(nodes)
	var keys := _slot_keys()
	for slot in slots.size():
		row.add_child(_label("%s:" % keys[slot], Color.WHITE))
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(150, 0)
		picker.tooltip_text = "Choose the ability on %s." % keys[slot]
		picker.add_item("(empty)")
		picker.set_item_metadata(0, "")
		for ability in unlocked:
			picker.add_item(_ability_name(ability))
			picker.set_item_metadata(picker.item_count - 1, ability)
			if ability == slots[slot]:
				picker.select(picker.item_count - 1)
		if slots[slot].is_empty():
			picker.select(0)
		picker.item_selected.connect(func(index: int) -> void:
			_send_slot(picker.get_item_metadata(index), slot))
		row.add_child(picker)
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
		var keys := _slot_keys()
		for slot in tree.slot_count:
			var slot_button := Button.new()
			slot_button.text = keys[slot]
			slot_button.toggle_mode = true
			slot_button.button_pressed = slots[slot] == n.ability
			slot_button.tooltip_text = "Put %s in slot %s" % [n.display_name, keys[slot]]
			slot_button.pressed.connect(_send_slot.bind(n.ability, slot))
			slot_row.add_child(slot_button)
		card.add_child(slot_row)
	return card


## Shows the Wings tab (once the build arrives).
func show_wings() -> void:
	_weapon_id = WINGS
	_refresh()


func _select_weapon(weapon_id: String) -> void:
	_weapon_id = weapon_id
	_builds.last_message = ""
	_refresh()


## Learns a node. A newly unlocked ability goes into the first empty slot.
func _send_learn(id: String) -> void:
	var nodes := _current_nodes().duplicate()
	nodes.append(id)
	var slots := _current_slots().duplicate()
	var n := _current_tree().get_node(id)
	if n.kind == MasteryTree.KIND_ACTIVE and not (n.ability in slots):
		var empty := slots.find("")
		if empty >= 0:
			slots[empty] = n.ability
	_send(nodes, slots)


## Unlearns a node and whatever needed it; empties slots that lose their ability.
func _send_unlearn(id: String) -> void:
	_send(_current_tree().remove(_current_nodes(), id), _current_slots())


## Slots an ability (taking it out of any other slot it was in), or empties the
## slot when ability is "".
func _send_slot(ability: String, slot: int) -> void:
	var slots := _current_slots().duplicate()
	for i in slots.size():
		if not ability.is_empty() and slots[i] == ability:
			slots[i] = ""
	slots[slot] = ability
	_send(_current_nodes(), slots)


## Sends the shown tree's whole allocation and slots (weapon or Wings).
func _send(nodes: PackedStringArray, slots: PackedStringArray) -> void:
	var unlocked := _current_tree().unlocked_abilities(nodes)
	var kept := slots.duplicate()
	for i in kept.size():
		if not (kept[i] in unlocked):
			kept[i] = ""
	if _weapon_id == WINGS:
		_builds.request_wings(nodes, kept)
	else:
		_builds.request_mastery(_weapon_id, nodes, kept)


func _ability_name(ability_id: String) -> String:
	var params := PlayerParams.current()
	if _weapon_id == WINGS:
		var pool := params.wing_set(_builds.local_build.wing_set_id())
		var wing := pool.ability(pool.ability_index(ability_id))
		return wing.display_name if wing else ability_id
	var weapon := params.weapon(_weapon_id)
	var index := weapon.ability_index(ability_id)
	return weapon.abilities[index].display_name if index >= 0 else ability_id


# --- The shown tree (a weapon's, or the Wings tab's) ---

func _current_tree() -> MasteryTree:
	var build := _builds.local_build
	return build.wing_tree if _weapon_id == WINGS else build.trees.get(_weapon_id)


func _current_nodes() -> PackedStringArray:
	var build := _builds.local_build
	return build.wing_nodes if _weapon_id == WINGS else build.get_allocated(_weapon_id)


func _current_slots() -> PackedStringArray:
	var build := _builds.local_build
	return build.wing_slots if _weapon_id == WINGS else build.get_slots(_weapon_id)


func _slot_keys() -> Array:
	return Hud.WING_KEYS if _weapon_id == WINGS else Hud.SLOT_KEYS


## wrap: only for labels that get a full row (in a VBox); in an HBox a wrapping
## label would shrink to nothing.
static func _label(text: String, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
