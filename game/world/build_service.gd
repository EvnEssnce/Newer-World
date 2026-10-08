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
## Build changes applied / refused (for the smoke test summary).
var accepted := 0
var rejected := 0

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
	if error.is_empty():
		error = player.build.set_weapons(weapons)
	_finish(player, error)


func _check_can_change(player: Player) -> String:
	if player.build == null:
		return "No build yet."
	if not player.state.can_change_loadout():
		return "Can't change your build mid-attack, mid-ability or mid-swap."
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


## Test bot: a free respec of the weapon it has out. Alternates between its
## tree's default allocation and that plus one more passive node (or, if none
## fits, minus the last passive), so the smoke test exercises the server's
## validation and the loadout server event. Abilities stay unlocked.
func bot_respec(weapon_id: String, cycle: int) -> void:
	if local_build == null or not local_build.trees.has(weapon_id):
		return
	var tree: MasteryTree = local_build.trees[weapon_id]
	var nodes := tree.default_nodes.duplicate()
	if cycle % 2 == 0:
		var added := false
		for id in tree.node_order:
			if (tree.get_node(id).kind == MasteryTree.KIND_PASSIVE and not id in nodes
					and tree.can_add(nodes, id)):
				nodes.append(id)
				added = true
				break
		if not added:
			for i in range(nodes.size() - 1, -1, -1):
				if tree.get_node(nodes[i]).kind == MasteryTree.KIND_PASSIVE:
					nodes = tree.remove(nodes, nodes[i])
					break
	var slots := local_build.get_slots(weapon_id).duplicate()
	var unlocked := tree.unlocked_abilities(nodes)
	for i in slots.size():
		if not (slots[i] in unlocked):
			slots[i] = ""
	request_mastery(weapon_id, nodes, slots)


## Test bot: slots each equipped weapon's unlocked status abilities (those with
## applies_status or self_status) first, then its other slotted ones, so the
## bot applies statuses. Keeps the allocation.
func bot_slot_status_abilities(params: PlayerParams) -> void:
	if local_build == null:
		return
	for weapon_id in local_build.weapons:
		var tree: MasteryTree = local_build.trees.get(weapon_id)
		if tree == null:
			continue
		var nodes := local_build.get_allocated(weapon_id)
		var unlocked := tree.unlocked_abilities(nodes)
		var slots := PackedStringArray()
		for ability in params.weapon(weapon_id).abilities:
			if (ability.id in unlocked and not ability.internal
					and not (ability.applies_status.is_empty() and ability.self_status.is_empty())):
				slots.append(ability.id)
		for ability_id in local_build.get_slots(weapon_id):
			if not ability_id.is_empty() and not ability_id in slots:
				slots.append(ability_id)
		slots = slots.slice(0, PlayerState.ABILITY_SLOTS)
		while slots.size() < PlayerState.ABILITY_SLOTS:
			slots.append("")
		request_mastery(weapon_id, nodes, slots)
