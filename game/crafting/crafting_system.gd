class_name CraftingSystem
extends Node
## Crafting stations and recipes over the network. World adds one at
## World/Crafting on the server and on every client (RPCs are matched by node
## path). The stations come from the Marker3D children of World/Stations
## (metadata/kind = a [station_<kind>] of data/stations.cfg), so every machine
## builds the same list (a station's id = its index); stations have no state.
##
## Client: F next to a station (LootSystem's interact key: loot first, then a
## gathering node, then a station; GatherNode.interact_choice) opens the
## crafting panel (CraftingPanel) with that station's recipes. Craft sends
## _request_craft(station id, recipe id, quantity). The panel closes when the
## player walks out of range or is defeated.
##
## Server: re-checks everything (alive, not busy, in range of its own position,
## the recipe belongs to that station's kind, then CraftingRules.check:
## level, materials, bag room) and starts the walk-only lock
## (PlayerState.start_gather: equip_left, a server event). A batch is one lock
## of craft_time x quantity. Leaving range, being hurt, staggered, moved or
## defeated cancels it (nothing taken). When it runs out (Player.equip_finished)
## CraftingRules.apply takes the inputs and adds the output in one go (or
## nothing, if the bag changed meanwhile), the owner gets the bag and a feed
## line (LootSystem.bag_changed), and the tradeskill its XP
## (TradeskillSystem.on_crafted).
## A --bot refines once a cycle when it has the materials and a station is near
## (bot_move, before gathering).

## Bot: looks for a station this close during its circling phase (m)...
const BOT_SEARCH := 10.0
## ...gives up on crafting this cycle if it hasn't asked by this phase (s), so a
## short craft (0.15 s in the smoke test) ends before its respec (7.6 s; the
## swap has a retry and the 7.4 air dodge may be lost); later than gathering's,
## so a gather this cycle near a station can still be refined...
const BOT_START_BY := 7.3
## ...and asks from within this fraction of the station's range.
const BOT_REACH := 0.8
## Bot: stands still this long after asking, until the lock shows up (ms; it
## asks again if it doesn't: the server's copy can still be finishing a swing).
const BOT_WAIT_MS := 300
## Client: seconds between refreshes of the open panel (have/need counts).
const PANEL_REFRESH := 0.25

## World/Players, World/Loot and World/Tradeskills. Set by World before adding this node.
var players: Node3D
var loot: LootSystem
var tradeskills: TradeskillSystem
## World/Stations (the level's markers). Set by World.
var markers: Node

var defs: RecipeDefs
var stations: Array[CraftingStation] = []
## Each station's marker yaw (its look faces the marker's +Z).
var _yaws: Array[float] = []
var _db: ItemDatabase
var _is_client := false
## Kind id -> reach (m), for CraftingStation.pick.
var _reach_of := {}
# Server
var _verbose := false
## Peer -> [station id, recipe id, quantity, health when last checked].
var _active: Dictionary[int, Array] = {}
var _started := 0
var _crafts := 0
var _items_made := 0
var _cancelled := 0
var _refused := 0
var _failed := 0
# Client
var _visuals: Array[StationVisual] = []
var _panel: CraftingPanel
var _panel_station := -1
var _panel_timer := 0.0
## --crafting-panel (screenshot checks): open at the nearest station once the
## local player exists, and keep it open wherever the bot walks.
var _panel_flag := false
var _requests := 0
var _panel_opens := 0
var _bot := false
var _bot_cycle := -1
var _bot_station := -1
var _bot_recipe := ""
var _bot_done := false
var _bot_asked_msec := -1
## Bot: the lock showed up after its last request.
var _bot_crafting := false
## Bot (--verbose): said this cycle that there's nothing to craft.
var _bot_logged := false


func _ready() -> void:
	defs = RecipeDefs.current()
	_db = ItemDatabase.current()
	for problem in defs.validate(_db, TradeskillDefs.current()):
		push_error("Crafting data: " + problem)
	_build_stations()
	if multiplayer.is_server():
		_verbose = LaunchArgs.has_flag("verbose")
		Net.peer_left.connect(func(peer: int) -> void: _active.erase(peer))
		return
	_is_client = true
	_bot = LaunchArgs.has_flag("bot")
	_panel_flag = LaunchArgs.has_flag("crafting-panel")
	for station in stations:
		var visual := StationVisual.new()
		add_child(visual)
		visual.global_position = station.position
		visual.rotation.y = _yaws[station.id]
		visual.setup(defs.get_station(station.kind).visual)
		_visuals.append(visual)
	var layer := CanvasLayer.new()
	layer.layer = 2  # with the other panels, above the HUD
	add_child(layer)
	_panel = CraftingPanel.new()
	_panel.setup(self)
	layer.add_child(_panel)


func _build_stations() -> void:
	for station: RecipeDefs.StationDef in defs.stations.values():
		_reach_of[station.id] = station.reach
	if markers == null:
		return
	for marker in markers.get_children():
		if not marker is Marker3D:
			continue
		var kind := str(marker.get_meta("kind", ""))
		if defs.get_station(kind) == null:
			push_error("Crafting: marker %s has unknown station kind '%s'" % [marker.name, kind])
			continue
		stations.append(CraftingStation.new(stations.size(), kind, (marker as Marker3D).global_position))
		_yaws.append((marker as Marker3D).global_rotation.y)


func _physics_process(_delta: float) -> void:
	if _is_client:
		return
	for peer: int in _active.keys():
		var player := players.get_node_or_null(str(peer)) as Player
		if player == null:
			_active.erase(peer)
			continue
		var reason := _interruption(player, _active[peer])
		if reason.is_empty():
			_active[peer][3] = player.health
			continue
		_active.erase(peer)
		_cancelled += 1
		player.state.cancel_equip()
		loot.notify(peer, reason)
		if _verbose:
			print("[server] crafting: %d interrupted (%s)" % [peer, reason])


# --- Server ---

@rpc("any_peer", "call_remote", "reliable")
func _request_craft(station_id: int, recipe_id: String, quantity: int) -> void:
	if _is_client:
		return
	var peer := multiplayer.get_remote_sender_id()
	var player := players.get_node_or_null(str(peer)) as Player
	if player == null:
		return
	var error := _craft_error(player, station_id, recipe_id, quantity)
	if error.is_empty():
		var recipe := defs.get_recipe(recipe_id)
		var ticks := recipe.ticks_for(quantity)
		if player.state.start_gather(ticks):
			_active[peer] = [station_id, recipe_id, quantity, player.health]
			_started += 1
			loot.show_busy_bar(peer, _batch_text(recipe, quantity), ticks)
			if _verbose:
				print("[server] crafting: %d started %d x %s at station %d" % [peer, quantity, recipe_id, station_id])
		else:
			error = "Finish what you're doing first."
	if not error.is_empty():
		_refused += 1
		loot.notify(peer, error)
		if _verbose:
			print("[server] crafting: %d refused %d x %s (%s)" % [peer, quantity, recipe_id, error])


## Why `player` can't start crafting now; "" if it can (the sim's own rules,
## PlayerState.start_gather, come after).
func _craft_error(player: Player, station_id: int, recipe_id: String, quantity: int) -> String:
	if station_id < 0 or station_id >= stations.size():
		return "There's no station there."
	var station := stations[station_id]
	var kind := defs.get_station(station.kind)
	var recipe := defs.get_recipe(recipe_id)
	if recipe == null or recipe.station != station.kind:
		return "The %s can't make that." % kind.name
	if player.state.dead:
		return "You can't craft while defeated."
	if _active.has(player.peer_id) or player.state.is_equipping():
		return "Finish what you're doing first."
	if not station.in_reach(player.global_position, kind.reach + defs.range_tolerance):
		return "Too far from the %s." % kind.name
	var bag := loot.bag_of(player.peer_id)
	if bag == null:
		return "No inventory yet."
	return CraftingRules.check(recipe, quantity, bag, tradeskills.level(player.peer_id, recipe.tradeskill),
			_db, defs.max_batch, tradeskills.defs)


## "" while the craft can go on, else why it stopped.
func _interruption(player: Player, active: Array) -> String:
	var station := stations[active[0]]
	var kind := defs.get_station(station.kind)
	if player.state.dead or not player.state.is_equipping() or not player.state.can_act():
		return "Crafting interrupted."
	if player.health < active[3]:
		return "Crafting interrupted: you were hit."
	if not station.in_reach(player.global_position, kind.reach + defs.range_tolerance):
		return "You moved away from the %s." % kind.name
	return ""


## Server (Player.equip_finished): the craft time ran out. Takes the inputs and
## gives the output (all or nothing), then XP and the feed line.
func finish_craft(player: Player) -> void:
	var peer := player.peer_id
	if not _active.has(peer):
		return
	var active: Array = _active[peer]
	_active.erase(peer)
	var recipe := defs.get_recipe(active[1])
	var quantity: int = active[2]
	var bag := loot.bag_of(peer)
	if recipe == null or bag == null:
		return
	var error := CraftingRules.apply(recipe, quantity, bag, tradeskills.level(peer, recipe.tradeskill),
			_db, defs.max_batch, tradeskills.defs)
	if not error.is_empty():
		_failed += 1
		loot.notify(peer, error)
		return
	var made := CraftingRules.made(recipe, quantity)
	_crafts += 1
	_items_made += made
	loot.bag_changed(peer, [Item.resource(recipe.output, made).to_dict()])
	tradeskills.on_crafted(peer, recipe.tradeskill, recipe.xp * quantity)
	if _verbose:
		print("[server] crafting: %d made %d %s" % [peer, made, recipe.output])


## The busy bar's label: "Smelting Rustvein Ingot x5".
func _batch_text(recipe: RecipeDefs.Recipe, quantity: int) -> String:
	var text := "%s %s" % [tradeskills.defs.display_name(recipe.tradeskill), recipe.display_name(_db)]
	return text + (" x%d" % quantity if quantity > 1 else "")


func print_summary() -> void:
	print("SUMMARY crafting crafts=%d items_made=%d started=%d cancelled=%d refused=%d failed=%d stations=%d recipes=%d" % [
			_crafts, _items_made, _started, _cancelled, _refused, _failed, stations.size(), defs.recipes.size()])


# --- Client ---

func _process(delta: float) -> void:
	if not _is_client or _panel == null:
		return
	var local := loot.local_player() if loot else null
	if _panel_flag and _panel_station < 0 and local and not stations.is_empty():
		open_panel(_nearest_station(local.global_position))
	if not _panel.visible:
		if not _panel_flag:  # closed by Esc (with the flag: stays closed)
			_panel_station = -1
		return
	if not _panel_flag and _should_close(local):
		close_panel()
		return
	_panel_timer -= delta
	if _panel_timer <= 0.0:
		_panel_timer = PANEL_REFRESH
		_panel.refresh()


func _should_close(local: Player) -> bool:
	if local == null or local.state.dead or _panel_station < 0:
		return true
	var station := stations[_panel_station]
	return not station.in_reach(local.global_position,
			defs.get_station(station.kind).reach + defs.range_tolerance)


## Client: the station F would open for `local` (in reach, nearest the
## crosshair), or -1.
func target_station(local: Player) -> int:
	if local == null or local.state.dead:
		return -1
	var ray := local.aim_ray()
	return CraftingStation.pick(stations, _reach_of, local.global_position, ray.origin, ray.direction)


## Client: "[F] Use Forge" for the station F would open, or "".
func prompt_text(local: Player) -> String:
	var station_id := target_station(local)
	if station_id < 0:
		return ""
	var kind := defs.get_station(stations[station_id].kind)
	return "[F] %s %s" % [kind.action, kind.name]


func panel_open() -> bool:
	return _panel != null and _panel.visible


## Client: opens the crafting panel on a station's recipes.
func open_panel(station_id: int) -> void:
	if station_id < 0 or station_id >= stations.size():
		return
	_panel_station = station_id
	_panel_opens += 1
	_panel_timer = PANEL_REFRESH
	var kind := defs.get_station(stations[station_id].kind)
	_panel.open(kind, defs.recipes_for(kind.id))


func close_panel() -> void:
	if _panel and _panel.visible:
		_panel.close()
	_panel_station = -1


## Client: asks the server to craft at the open panel's station.
func request_craft(recipe_id: String, quantity: int) -> void:
	if _panel_station < 0:
		return
	_requests += 1
	_request_craft.rpc_id(1, _panel_station, recipe_id, quantity)


## Client: the local bag as an Inventory (CraftingRules reads it; never changed).
func local_bag() -> Inventory:
	var bag := Inventory.new(loot.capacity)
	bag.items = loot.inventory
	return bag


## Client: the local player's level in a skill (1 before the server sends any).
func local_level(skill: String) -> int:
	return tradeskills.local.level(skill) if tradeskills and tradeskills.local else Tradeskills.START_LEVEL


func _nearest_station(from: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for station in stations:
		var distance := Vector2(station.position.x - from.x, station.position.z - from.z).length()
		if distance < best_distance:
			best_distance = distance
			best = station.id
	return best


## Bot (World._bot_input, circling phase, before gathering unless a gather is
## under way): once a cycle, when it has the materials for a recipe at a station
## within BOT_SEARCH, walks there and crafts one, standing still meanwhile.
## Returns the move to use, or null.
func bot_move(local: Player, phase: float, cycle: int) -> Variant:
	if cycle != _bot_cycle:
		_bot_cycle = cycle
		_bot_station = -1
		_bot_done = false
		_bot_asked_msec = -1
		_bot_crafting = false
		_bot_logged = false
	if _bot_asked_msec >= 0:
		if local.state.is_equipping():
			_bot_crafting = true
			return Vector2.ZERO
		if Time.get_ticks_msec() - _bot_asked_msec < BOT_WAIT_MS:
			return Vector2.ZERO
		if _bot_crafting:
			_bot_done = true  # crafted (or interrupted): once a cycle
		# Else refused (the server's copy was still mid-swing): ask again.
		_bot_asked_msec = -1
		_bot_station = -1
		_bot_crafting = false
	if _bot_done or local.state.dead or phase >= BOT_START_BY or local.state.is_equipping():
		return null  # (equipping: a gather or gear change of its own)
	if _bot_station < 0:
		# Looked for every tick until BOT_START_BY: a gather this cycle can
		# bring the materials.
		_bot_pick(local)
		if _bot_station < 0:
			if not _bot_logged and LaunchArgs.has_flag("verbose"):
				_bot_logged = true
				var nearest := _nearest_station(local.global_position)
				print("[client] crafting: nothing to craft within %.0f m (nearest station %.1f m)" % [
						BOT_SEARCH, local.global_position.distance_to(stations[nearest].position) if nearest >= 0 else -1.0])
			return null
	var station := stations[_bot_station]
	var to := station.position - local.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() > _reach_of[station.kind] * BOT_REACH:
		return flat.normalized()
	if not local.state.can_change_loadout() or local.state.is_dodging() or not local.state.can_act():
		return Vector2.ZERO  # finish the swing (or gear change) first
	_bot_asked_msec = Time.get_ticks_msec()
	_requests += 1
	_request_craft.rpc_id(1, _bot_station, _bot_recipe, 1)
	if LaunchArgs.has_flag("verbose"):
		print("[client] crafts %s at station %d (frame %d)" % [_bot_recipe, _bot_station, _bot_asked_msec / 250])
	return Vector2.ZERO


## The nearest station within BOT_SEARCH with a recipe the bot can make one of.
func _bot_pick(local: Player) -> void:
	var bag := local_bag()
	var best_distance := BOT_SEARCH
	for station in stations:
		var distance := Vector2(station.position.x - local.global_position.x,
				station.position.z - local.global_position.z).length()
		if distance > best_distance:
			continue
		for recipe in defs.recipes_for(station.kind):
			if CraftingRules.check(recipe, 1, bag, local_level(recipe.tradeskill), _db, defs.max_batch).is_empty():
				best_distance = distance
				_bot_station = station.id
				_bot_recipe = recipe.id
				break


func print_client_summary() -> void:
	print("SUMMARY client=%d crafting requests=%d panel_opens=%d" % [
			multiplayer.get_unique_id(), _requests, _panel_opens])
