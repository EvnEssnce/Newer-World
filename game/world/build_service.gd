class_name BuildService
extends Node
## Character builds: class, equipped weapons, mastery trees, slotted abilities.
## A child of World named "Builds" on the server and every client (RPCs are
## matched by node path).
##
## Server: creates each player's CharacterBuild when they join, validates their
## client's change requests (class weapon lists, mastery rules, not mid-attack),
## applies accepted ones to PlayerState (a server event, so the client's
## prediction doesn't count the correction) and sends the result back.
## Client: keeps a copy of its own build for the mastery panel and sends
## requests. The build that matters for the simulation (weapons, slots) also
## arrives in every snapshot inside PlayerState.

## Client: local_build or last_message changed.
signal build_changed

# Server
## World/Loot, for weapon items that follow the weapon slots. Set by World.
var loot: LootSystem
## Build changes applied / refused (for the smoke test summary).
var accepted := 0
var rejected := 0
## Class changes applied (_request_class).
var class_changes := 0

# Client
var local_build: CharacterBuild
## The server's reply to the last request: "" on success, else why it was refused.
var last_message := ""


func _players() -> Node:
	return get_parent().get_node("Players")


# --- Server ---

## Gives a joining player the default build of their class (or of the default
## class if theirs is unknown) and puts it into their state.
func setup_player(player: Player, class_id: String) -> void:
	var class_def := ClassDef.for_id(class_id)
	if class_def == null:
		print("[server] peer %d asked for unknown class \"%s\", using %s" % [
				player.peer_id, class_id, ClassDef.DEFAULT_CLASS])
		class_def = ClassDef.for_id(ClassDef.DEFAULT_CLASS)
	player.build = CharacterBuild.create_default(class_def)
	player.build.apply_to_state(player.state, player.params)


func send_build(player: Player, message: String = "") -> void:
	if player.peer_id in multiplayer.get_peers():
		_receive_build.rpc_id(player.peer_id, player.build.to_dict(), message)


## Client → server: replace one weapon's mastery allocation and ability slots
## (a free respec). slots holds ability ids for Q, E, R ("" = empty).
@rpc("any_peer", "call_remote", "reliable")
func _request_mastery(weapon_id: String, nodes: PackedStringArray, slots: PackedStringArray) -> void:
	var player := _sender_player()
	if player == null:
		return
	var error := _check_can_change(player)
	if error.is_empty():
		error = player.build.set_mastery(weapon_id, nodes, slots)
	_finish(player, error)


## Client → server: equip other weapons of the player's class (ids, one per
## weapon slot).
@rpc("any_peer", "call_remote", "reliable")
func _request_weapons(weapons: PackedStringArray) -> void:
	var player := _sender_player()
	if player == null:
		return
	var error := _check_can_change(player)
	if error.is_empty() and loot:
		error = loot.check_weapon_change(player, weapons)
	if error.is_empty():
		error = player.build.set_weapons(weapons)
	_finish(player, error)
	if error.is_empty() and loot:
		loot.weapons_changed(player)


## Server: equips these weapon types (one per slot) for a weapon item being
## equipped (LootSystem); the same checks as a request from the K panel.
## Returns "" or why not.
func apply_weapons(player: Player, weapons: PackedStringArray) -> String:
	var error := _check_can_change(player)
	if error.is_empty():
		error = player.build.set_weapons(weapons)
	if error.is_empty():
		player.build.apply_to_state(player.state, player.params)
		accepted += 1
		send_build(player)
	return error


## Client → server: replace the Wing tree allocation and the Wing slots (ability
## ids for Z and C, "" = empty; a free respec).
@rpc("any_peer", "call_remote", "reliable")
func _request_wings(nodes: PackedStringArray, slots: PackedStringArray) -> void:
	var player := _sender_player()
	if player == null:
		return
	var error := _check_can_change(player)
	if error.is_empty():
		error = player.build.set_wing_mastery(nodes, slots)
	_finish(player, error)


## Client → server: become another class (a test tool, data/testing.cfg
## [class_change] enabled). Out of combat and between actions only
## (PlayerState.class_change_error); a clean start: the class's default build,
## full health, the state reset of PlayerState.reset_for_class_change, and gear
## the class can't wear back in the bag (LootSystem.class_changed).
@rpc("any_peer", "call_remote", "reliable")
func _request_class(class_id: String) -> void:
	var player := _sender_player()
	if player == null:
		return
	var class_def := ClassDef.for_id(class_id)
	var error := ""
	if not class_change_enabled():
		error = "Changing class is switched off."
	elif player.build == null:
		error = "No build yet."
	elif class_def == null:
		error = "There's no class \"%s\"." % class_id
	elif class_def == player.build.class_def:
		error = "You're already a %s." % class_def.display_name
	else:
		error = player.state.class_change_error()
	if error.is_empty() and loot:
		error = loot.check_class_change(player, class_def)
	if not error.is_empty():
		rejected += 1
		print("[server] peer %d class change refused: %s" % [player.peer_id, error])
		send_build(player, error)
		return
	var old_class := player.build.class_def.id
	player.state.reset_for_class_change(player.params)
	player.reset_class_state()
	player.build = CharacterBuild.create_default(class_def)
	player.build.apply_to_state(player.state, player.params)
	if loot:
		loot.class_changed(player)
	player.health = player.max_health()
	accepted += 1
	class_changes += 1
	print("[server] peer %d changed class: %s -> %s" % [player.peer_id, old_class, class_def.id])
	send_build(player)


## data/testing.cfg [class_change] enabled: the server allows _request_class,
## and the K panel shows the Class picker.
static func class_change_enabled() -> bool:
	return Tuning.get_optional("testing", "class_change", "enabled", false)


func _check_can_change(player: Player) -> String:
	if player.build == null:
		return "No build yet."
	if not player.state.can_change_loadout():
		return "Can't change your build mid-attack, mid-ability, mid-swap or while changing gear."
	return ""


func _finish(player: Player, error: String) -> void:
	if error.is_empty():
		player.build.apply_to_state(player.state, player.params)
		accepted += 1
	else:
		rejected += 1
		print("[server] peer %d build change refused: %s" % [player.peer_id, error])
	send_build(player, error)


func _sender_player() -> Player:
	if not multiplayer.is_server():
		return null
	return _players().get_node_or_null(str(multiplayer.get_remote_sender_id())) as Player


# --- Client ---

@rpc("authority", "call_remote", "reliable")
func _receive_build(data: Dictionary, message: String) -> void:
	var build := CharacterBuild.from_dict(data)
	if build:
		local_build = build
	last_message = message
	build_changed.emit()


func request_mastery(weapon_id: String, nodes: PackedStringArray, slots: PackedStringArray) -> void:
	_request_mastery.rpc_id(1, weapon_id, nodes, slots)


func request_weapons(weapons: PackedStringArray) -> void:
	_request_weapons.rpc_id(1, weapons)


func request_wings(nodes: PackedStringArray, slots: PackedStringArray) -> void:
	_request_wings.rpc_id(1, nodes, slots)


func request_class(class_id: String) -> void:
	_request_class.rpc_id(1, class_id)


## Test bot: a free respec of the Wing tree to its default allocation plus the
## built capstones that fit (the first in file order on even cycles, the last
## on odd ones, so each gets its turn), with the Wing slots for a bot cycle
## (bot_wing_slots_for_cycle), so the smoke test exercises the server's Wing
## validation and the bot gets to use every Wing ability. Nothing is sent if
## that's already the build.
func bot_respec_wings(cycle: int) -> void:
	if local_build == null or local_build.wing_tree == null:
		return
	var tree := local_build.wing_tree
	var nodes := _bot_learn_capstones(tree, tree.default_nodes.duplicate(), cycle % 2 == 1)
	var slots := bot_wing_slots_for_cycle(cycle)
	var unlocked := tree.unlocked_abilities(nodes)
	for i in slots.size():
		if not (slots[i] in unlocked):
			slots[i] = ""
	if nodes == local_build.wing_nodes and slots == local_build.wing_slots:
		return
	request_wings(nodes, slots)


## Test bot: the Wing slots (Z, C) for a cycle. Even cycles: the default slots
## (Fighter: Ember Mantle, Wingbeat Surge); odd cycles put the tree's other
## actives into Z in turn, last one first (Fighter: Diving Strike, then Pyre Heart).
func bot_wing_slots_for_cycle(cycle: int) -> PackedStringArray:
	var tree := local_build.wing_tree
	var slots := tree.default_slots.duplicate()
	if cycle % 2 == 0:
		return slots
	var others := PackedStringArray()
	for ability in tree.unlocked_abilities(tree.default_nodes):
		if not (ability in slots):
			others.append(ability)
	if others.is_empty():
		return slots
	@warning_ignore("integer_division")
	slots[0] = others[others.size() - 1 - (cycle / 2) % others.size()]
	return slots


## Test bot: a free respec of a weapon, starting from the tree's default allocation
## and the weapon's current slots (so the status abilities bot_slot_status_abilities
## put in stay in). Even cycles: minus the last passive node whose removal keeps every
## learned ability (a tier gate could otherwise take an ability with it); odd cycles:
## plus every new active the rules allow. So the smoke test exercises the server's
## validation and the loadout server event.
func bot_respec(weapon_id: String, cycle: int) -> void:
	if local_build == null or not local_build.trees.has(weapon_id):
		return
	var tree: MasteryTree = local_build.trees[weapon_id]
	var nodes := tree.default_nodes.duplicate()
	var slots := local_build.get_slots(weapon_id).duplicate()
	if cycle % 2 == 0:
		var abilities := tree.unlocked_abilities(nodes)
		for i in range(nodes.size() - 1, -1, -1):
			if tree.get_node(nodes[i]).kind != MasteryTree.KIND_PASSIVE:
				continue
			var fewer := tree.remove(nodes, nodes[i])
			if tree.unlocked_abilities(fewer) == abilities:
				nodes = fewer
				break
		nodes = _bot_learn_capstones(tree, nodes)
	else:
		var before := nodes.size()
		var learned := _bot_learn_new_actives(tree, nodes, slots)
		nodes = learned[0]
		slots = learned[1]
		if nodes.size() == before:
			# Every active is already learned (War Hammer): the capstones instead.
			nodes = _bot_learn_capstones(tree, nodes)
	var unlocked := tree.unlocked_abilities(nodes)
	for i in slots.size():
		if not (slots[i] in unlocked):
			slots[i] = ""
	request_mastery(weapon_id, nodes, slots)


## Test bot: slots each of its class's weapons' unlocked zone and status
## abilities first (zones and summons like Shield Wall and Tripwire, then
## self-buffs like Bloodlust and Rampage, then those with applies_status),
## keeping one slot for a projectile ability if the weapon has one, then its
## other slotted ones, so the bot places zones, applies statuses, buffs itself
## and throws projectiles. Keeps the allocation.
func bot_slot_status_abilities(params: PlayerParams) -> void:
	if local_build == null:
		return
	for weapon_id: String in local_build.trees:
		var tree: MasteryTree = local_build.trees.get(weapon_id)
		var nodes := local_build.get_allocated(weapon_id)
		var unlocked := tree.unlocked_abilities(nodes)
		var slots := PackedStringArray()
		var throws := PackedStringArray()
		for ability in params.weapon(weapon_id).abilities:
			if ability.id in unlocked and not ability.internal and not ability.projectile.is_empty():
				throws.append(ability.id)
		var status_room := PlayerState.ABILITY_SLOTS - mini(throws.size(), 1)
		# Summons and zones first (Shield Wall, Tripwire, Arrow Rain), so the smoke
		# test places them; then self-buffs, then status abilities.
		for key in ["zone", "self_status", "applies_status"]:
			for ability in params.weapon(weapon_id).abilities:
				if (ability.id in unlocked and not ability.internal and not ability.id in slots
						and not ability.id in throws and not str(ability.get(key)).is_empty()
						and slots.size() < status_room):
					slots.append(ability.id)
		for ability_id in throws:
			if not ability_id in slots:
				slots.append(ability_id)
		for ability_id in local_build.get_slots(weapon_id):
			if not ability_id.is_empty() and not ability_id in slots:
				slots.append(ability_id)
		slots = slots.slice(0, PlayerState.ABILITY_SLOTS)
		while slots.size() < PlayerState.ABILITY_SLOTS:
			slots.append("")
		request_mastery(weapon_id, nodes, slots)
## Test bot: `nodes` plus each built capstone (a last-tier passive whose effect
## isn't "none": the Spear's Hold the Line and Finishing Thrust) that fits, with
## the lower nodes of its branch (in file order) it needs, so the smoke test
## exercises them. A capstone that doesn't fit is left out. reverse: try the
## capstones last-first.
static func _bot_learn_capstones(tree: MasteryTree, nodes: PackedStringArray,
		reverse := false) -> PackedStringArray:
	var order := tree.node_order.duplicate()
	if reverse:
		order.reverse()
	for id in order:
		var cap := tree.get_node(id)
		if (cap.tier != tree.tier_count() or cap.kind == MasteryTree.KIND_ACTIVE
				or cap.effect == "none" or id in nodes):
			continue
		var trial := nodes.duplicate()
		for other_id in tree.node_order:
			if tree.can_add(trial, id):
				break
			var other := tree.get_node(other_id)
			if other.branch == cap.branch and other.tier < cap.tier and tree.can_add(trial, other_id):
				trial.append(other_id)
		if tree.can_add(trial, id):
			trial.append(id)
			nodes = trial
	return nodes


## Test bot: `nodes` plus every active node the rules allow that isn't learned
## yet, and `slots` with each new ability put in from Q onward, so the bot also
## uses abilities that aren't in a tree's default build (Rising Cut). Returns
## [nodes, slots].
static func _bot_learn_new_actives(tree: MasteryTree, nodes: PackedStringArray,
		slots: PackedStringArray) -> Array:
	var next_slot := 0
	for id in tree.node_order:
		var n := tree.get_node(id)
		if n.kind != MasteryTree.KIND_ACTIVE or id in nodes or not tree.can_add(nodes, id):
			continue
		nodes.append(id)
		if next_slot < slots.size() and not (n.ability in slots):
			slots[next_slot] = n.ability
			next_slot += 1
	return [nodes, slots]


## Test bot: its [focus, other] weapons for a bot cycle. The first cycle uses
## the class's default loadout (the fight the older smoke checks were tuned
## on); after that the focus weapon (out for the fight and abilities) changes
## every cycle, going through the class's weapons starting with the first one
## the default loadout lacks (Fighter: Spear, then Dual Axes, then Broadsword),
## so every weapon gets its turn within a 32 s smoke run. Empty without a build.
func bot_weapons_for_cycle(cycle: int) -> PackedStringArray:
	if local_build == null:
		return PackedStringArray()
	if cycle <= 0:
		return local_build.class_def.default_loadout.duplicate()
	var all := local_build.class_def.weapons
	var start := 0
	for i in all.size():
		if not (all[i] in local_build.class_def.default_loadout):
			start = i
			break
	var focus := start + cycle - 1
	return PackedStringArray([all[focus % all.size()], all[(focus + 1) % all.size()]])


## Test bot: asks for `weapons` ([focus, other]) with the focus weapon in weapon
## slot `equipped` (the one that's out), unless that's already the loadout.
## Returns true if a request was sent.
func bot_request_weapons(weapons: PackedStringArray, equipped: int) -> bool:
	if local_build == null or weapons.size() < PlayerState.WEAPON_SLOTS:
		return false
	var wanted := PackedStringArray(["", ""])
	wanted[equipped] = weapons[0]
	wanted[1 - equipped] = weapons[1]
	if wanted == local_build.weapons:
		return false
	request_weapons(wanted)
	return true
