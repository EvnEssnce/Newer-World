class_name GatheringSystem
extends Node
## Gathering nodes over the network. World adds one at World/Gathering on the
## server and on every client (RPCs are matched by node path). The nodes come
## from the Marker3D children of World/GatherNodes (metadata/kind = a
## [node_<kind>] of data/gathering.cfg), so every machine builds the same list
## (a node's id = its index) and only availability travels.
##
## Server: owns each node's charges and respawn timer (GatherNode). F next to a
## node (LootSystem's interact key: loot in reach is picked up first,
## GatherNode.interact_choice) sends _request_gather(node id); the server checks
## it (alive, in range of its own position, node available, bag room, not busy:
## PlayerState.start_gather refuses mid-attack/ability/swap/roll/gear change or
## staggered) and starts the walk-only lock (equip_left, a server event, so
## prediction stays exact). Leaving range, being hurt, staggered, moved or
## defeated cancels it (PlayerState.cancel_equip). When it runs out
## (Player.equip_finished) the resources go into the bag as stacks
## (LootSystem.give_resources), the node loses a charge, and `gathered` fires.
## Never in snapshots: reliable _receive_node_state on a change, and every
## node's state to a player as they join (_receive_all_nodes).
## Client: draws the nodes (GatherNodeVisual); LootSystem shows the prompt and
## the progress bar. A --bot gathers once per cycle while circling (bot_move).
##
## Tradeskill hooks (server; set by whoever builds tradeskills):
##   signal gathered(peer_id, skill_id, node_kind, amount) after each gather.
##   time_multiplier_hook: Callable(peer_id: int, skill_id: String) -> float,
##     multiplies the node's gather time (unset = 1.0).
##   yield_bonus_hook: Callable(peer_id: int, skill_id: String) -> int, extra
##     resources per gather (unset = 0).

## Server, after every successful gather (amount = what went into the bag).
signal gathered(peer_id: int, skill_id: String, node_kind: String, amount: int)

## Bot: looks for a node this close when its circling phase starts (m)...
const BOT_SEARCH := 6.0
## ...gives up on gathering this cycle if it hasn't started by this phase (s)...
const BOT_START_BY := 6.8
## ...and asks from within this fraction of the node's range.
const BOT_REACH := 0.6
## Bot: stands still this long after asking, until the lock shows up (ms).
const BOT_WAIT_MS := 500

## World/Players and World/Loot. Set by World before adding this node.
var players: Node3D
var loot: LootSystem
## World/GatherNodes (the level's markers). Set by World.
var markers: Node
## See the header.
var time_multiplier_hook: Callable
var yield_bonus_hook: Callable

var nodes: Array[GatherNode] = []
var _is_client := false
## Kind id -> reach (m), for GatherNode.pick.
var _reach_of := {}
# Server
var _tick := 0
var _rng := RandomNumberGenerator.new()
var _verbose := false
## Peer -> [node id, health when last checked].
var _active: Dictionary[int, Array] = {}
var _started := 0
var _gathers := 0
var _resources := 0
var _cancelled := 0
var _refused := 0
var _depleted := 0
var _respawned := 0
# Client
var _visuals: Array[GatherNodeVisual] = []
var _requests := 0
var _updates_seen := 0
var _bot := false
var _bot_cycle := -1
var _bot_node := -1
var _bot_done := false
var _bot_asked_msec := -1


func _ready() -> void:
	_build_nodes()
	if multiplayer.is_server():
		_rng.randomize()
		_verbose = LaunchArgs.has_flag("verbose")
		Net.peer_left.connect(func(peer: int) -> void: _active.erase(peer))
	else:
		_is_client = true
		_bot = LaunchArgs.has_flag("bot")
		for node in nodes:
			var visual := GatherNodeVisual.new()
			add_child(visual)
			visual.global_position = node.position
			visual.rotation.y = fposmod(node.position.x * 1.7 + node.position.z * 0.9, TAU)
			visual.setup(GatherNodeParams.get_kind(node.kind).visual)
			_visuals.append(visual)


func _build_nodes() -> void:
	var db := ItemDatabase.current()
	for p in GatherNodeParams.all_kinds():
		_reach_of[p.id] = p.reach
		for problem in p.validate(db):
			push_error("Gathering data: " + problem)
	if markers == null:
		return
	for marker in markers.get_children():
		if not marker is Marker3D:
			continue
		var kind := str(marker.get_meta("kind", ""))
		var params := GatherNodeParams.get_kind(kind)
		if params == null:
			push_error("Gathering: marker %s has unknown kind '%s'" % [marker.name, kind])
			continue
		nodes.append(GatherNode.new(nodes.size(), kind, (marker as Marker3D).global_position, params.charges))


func _physics_process(_delta: float) -> void:
	if _is_client:
		return
	_tick += 1
	for node in nodes:
		if node.step(_tick, GatherNodeParams.get_kind(node.kind)):
			_respawned += 1
			_broadcast_state(node)
	for peer: int in _active.keys():
		var player := players.get_node_or_null(str(peer)) as Player
		if player == null:
			_active.erase(peer)
			continue
		var reason := _interruption(player, _active[peer])
		if reason.is_empty():
			_active[peer][1] = player.health
			continue
		_active.erase(peer)
		_cancelled += 1
		player.state.cancel_equip()
		loot.notify(peer, reason)
		if _verbose:
			print("[server] gathering: %d interrupted (%s)" % [peer, reason])


# --- Server ---

## A player joined: every node's availability (1 = can be gathered).
func add_player(peer: int) -> void:
	var states := PackedByteArray()
	for node in nodes:
		states.append(1 if node.is_available() else 0)
	_receive_all_nodes.rpc_id(peer, states)


@rpc("any_peer", "call_remote", "reliable")
func _request_gather(node_id: int) -> void:
	if _is_client:
		return
	var peer := multiplayer.get_remote_sender_id()
	var player := players.get_node_or_null(str(peer)) as Player
	if player == null:
		return
	var error := _gather_error(player, node_id)
	if error.is_empty():
		var node := nodes[node_id]
		var params := GatherNodeParams.get_kind(node.kind)
		var ticks := params.ticks_for(_time_multiplier(peer, params.tradeskill))
		if player.state.start_gather(ticks):
			_active[peer] = [node_id, player.health]
			_started += 1
			loot.show_busy_bar(peer, "Gathering %s" % params.name, ticks)
		else:
			error = "Finish what you're doing first."
	if not error.is_empty():
		_refused += 1
		loot.notify(peer, error)
		if _verbose:
			print("[server] gathering: %d refused node %d (%s)" % [peer, node_id, error])


## Why `player` can't start gathering node `node_id` now; "" if it can (the
## sim's own rules, PlayerState.start_gather, come after).
func _gather_error(player: Player, node_id: int) -> String:
	if node_id < 0 or node_id >= nodes.size():
		return "There's nothing to gather there."
	if player.state.dead:
		return "You can't gather while defeated."
	if _active.has(player.peer_id) or player.state.is_equipping():
		return "Finish what you're doing first."
	var node := nodes[node_id]
	var params := GatherNodeParams.get_kind(node.kind)
	if not node.is_available():
		return "The %s is used up." % params.name
	if not node.in_reach(player.global_position, params.reach + GatherNodeParams.range_tolerance()):
		return "Too far from the %s." % params.name
	if loot.resource_room(player.peer_id, params.resource) <= 0:
		return "Your inventory is full."
	return ""


## "" while the gather can go on, else why it stopped.
func _interruption(player: Player, active: Array) -> String:
	var node := nodes[active[0]]
	var params := GatherNodeParams.get_kind(node.kind)
	if player.state.dead or not player.state.is_equipping() or not player.state.can_act():
		return "Gathering interrupted."
	if player.health < active[1]:
		return "Gathering interrupted: you were hit."
	if not node.is_available():
		return "The %s is used up." % params.name
	if not node.in_reach(player.global_position, params.reach + GatherNodeParams.range_tolerance()):
		return "You moved away from the %s." % params.name
	return ""


## Server (Player.equip_finished): the gather time ran out. The resources go in
## the bag, the node loses a charge (depleted at 0), and `gathered` fires.
func finish_gather(player: Player) -> void:
	var peer := player.peer_id
	if not _active.has(peer):
		return
	var node := nodes[_active[peer][0]]
	_active.erase(peer)
	var params := GatherNodeParams.get_kind(node.kind)
	if not node.is_available():
		loot.notify(peer, "The %s is used up." % params.name)
		return
	var amount := params.roll_yield(_rng, _yield_bonus(peer, params.tradeskill))
	var added := loot.give_resources(peer, params.resource, amount)
	if added <= 0:
		return  # bag full: the node keeps its charge
	node.take(_tick, params)
	if not node.is_available():
		_depleted += 1
		_broadcast_state(node)
	_gathers += 1
	_resources += added
	if _verbose:
		print("[server] gathering: %d gathered %d %s from node %d (%d left)" % [
				peer, added, params.resource, node.id, node.charges_left])
	gathered.emit(peer, params.tradeskill, node.kind, added)


func _time_multiplier(peer: int, skill: String) -> float:
	return float(time_multiplier_hook.call(peer, skill)) if time_multiplier_hook.is_valid() else 1.0


func _yield_bonus(peer: int, skill: String) -> int:
	return int(yield_bonus_hook.call(peer, skill)) if yield_bonus_hook.is_valid() else 0


func _broadcast_state(node: GatherNode) -> void:
	var peers := multiplayer.get_peers()
	for player: Player in players.get_children():
		if player.peer_id in peers:
			_receive_node_state.rpc_id(player.peer_id, node.id, node.is_available())


func print_summary() -> void:
	print("SUMMARY gathering gathers=%d resources=%d started=%d cancelled=%d refused=%d depleted=%d respawned=%d nodes=%d" % [
			_gathers, _resources, _started, _cancelled, _refused, _depleted, _respawned, nodes.size()])


# --- Client ---

@rpc("authority", "call_remote", "reliable")
func _receive_all_nodes(states: PackedByteArray) -> void:
	for i in mini(states.size(), nodes.size()):
		_set_available(i, states[i] != 0)


@rpc("authority", "call_remote", "reliable")
func _receive_node_state(node_id: int, available: bool) -> void:
	if node_id >= 0 and node_id < nodes.size():
		_updates_seen += 1
		_set_available(node_id, available)


func _set_available(node_id: int, available: bool) -> void:
	nodes[node_id].charges_left = 1 if available else 0
	if node_id < _visuals.size():
		_visuals[node_id].set_available(available)


## Client: the node F would gather for `local` (in reach, nearest the
## crosshair), or -1.
func target_node(local: Player) -> int:
	if local == null or local.state.dead:
		return -1
	var ray := local.aim_ray()
	return GatherNode.pick(nodes, _reach_of, local.global_position, ray.origin, ray.direction)


## Client: "[F] Mine Rustvein Deposit" for the node F would gather, or "".
func prompt_text(local: Player) -> String:
	var node_id := target_node(local)
	if node_id < 0:
		return ""
	var params := GatherNodeParams.get_kind(nodes[node_id].kind)
	return "[F] %s %s" % [params.action, params.name]


func request_gather(node_id: int) -> void:
	_requests += 1
	_request_gather.rpc_id(1, node_id)


## Bot (World._bot_input, circling phase): once a cycle, walks to an available
## node within BOT_SEARCH m and gathers it, standing still while it does.
## Returns the move to use, or null to circle as usual.
func bot_move(local: Player, phase: float, cycle: int) -> Variant:
	if cycle != _bot_cycle:
		_bot_cycle = cycle
		_bot_node = -1
		_bot_done = false
		_bot_asked_msec = -1
	if _bot_asked_msec >= 0:
		if local.state.is_equipping() or Time.get_ticks_msec() - _bot_asked_msec < BOT_WAIT_MS:
			return Vector2.ZERO
		return null
	if _bot_done or local.state.dead or phase >= BOT_START_BY:
		return null
	if _bot_node < 0 or not nodes[_bot_node].is_available():
		_bot_node = _nearest_available(local.global_position, BOT_SEARCH)
		if _bot_node < 0:
			_bot_done = true
			return null
	var node := nodes[_bot_node]
	var to := node.position - local.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() > _reach_of[node.kind] * BOT_REACH:
		return flat.normalized()
	if not local.state.can_change_loadout() or local.state.is_dodging() or not local.state.can_act():
		return Vector2.ZERO  # finish the swing (or gear change) first
	_bot_asked_msec = Time.get_ticks_msec()
	request_gather(node.id)
	if LaunchArgs.has_flag("verbose"):
		# The --screenshot-dir frame number, to find the gather in the frames.
		print("[client] gathers node %d (frame %d)" % [node.id, _bot_asked_msec / 250])
	return Vector2.ZERO


func _nearest_available(from: Vector3, within: float) -> int:
	var best := -1
	var best_distance := within
	for node in nodes:
		var distance := Vector2(node.position.x - from.x, node.position.z - from.z).length()
		if node.is_available() and distance <= best_distance:
			best_distance = distance
			best = node.id
	return best


func print_client_summary() -> void:
	var resources := 0
	for item in loot.inventory:
		var def: ItemDatabase.ItemDef = ItemDatabase.current().items.get(item.item_id)
		if def and def.is_resource():
			resources += item.count
	print("SUMMARY client=%d gathering requests=%d node_updates=%d resources_in_bag=%d" % [
			multiplayer.get_unique_id(), _requests, _updates_seen, resources])
