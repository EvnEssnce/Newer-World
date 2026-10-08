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


func request_wings(nodes: PackedStringArray, slots: PackedStringArray) -> void:
	_request_wings.rpc_id(1, nodes, slots)


## Test bot: a free respec of the Wing tree to its default allocation, with the
## Wing slots for a bot cycle (bot_wing_slots_for_cycle), so the smoke test
## exercises the server's Wing validation and the bot gets to use every Wing
## ability. Nothing is sent if that's already the build.
func bot_respec_wings(cycle: int) -> void:
	if local_build == null or local_build.wing_tree == null:
		return
	var tree := local_build.wing_tree
	var nodes := tree.default_nodes.duplicate()
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
	else:
		var learned := _bot_learn_new_actives(tree, nodes, slots)
		nodes = learned[0]
		slots = learned[1]
	var unlocked := tree.unlocked_abilities(nodes)
	for i in slots.size():
		if not (slots[i] in unlocked):
			slots[i] = ""
	request_mastery(weapon_id, nodes, slots)


## Test bot: slots each of its class's weapons' unlocked status abilities (those
## with applies_status or self_status) first, then its projectile abilities,
## then its other slotted ones, so the bot applies statuses and throws
## projectiles. Keeps the allocation.
func bot_slot_status_abilities(params: PlayerParams) -> void:
	if local_build == null:
		return
	for weapon_id: String in local_build.trees:
		var tree: MasteryTree = local_build.trees.get(weapon_id)
		var nodes := local_build.get_allocated(weapon_id)
		var unlocked := tree.unlocked_abilities(nodes)
		var slots := PackedStringArray()
		for ability in params.weapon(weapon_id).abilities:
			if (ability.id in unlocked and not ability.internal
					and not (ability.applies_status.is_empty() and ability.self_status.is_empty())):
				slots.append(ability.id)
		for ability in params.weapon(weapon_id).abilities:
			if ability.id in unlocked and not ability.projectile.is_empty() and not ability.id in slots:
				slots.append(ability.id)
		for ability_id in local_build.get_slots(weapon_id):
			if not ability_id.is_empty() and not ability_id in slots:
				slots.append(ability_id)
		slots = slots.slice(0, PlayerState.ABILITY_SLOTS)
		while slots.size() < PlayerState.ABILITY_SLOTS:
			slots.append("")
		request_mastery(weapon_id, nodes, slots)
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
