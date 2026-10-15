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
## player walks out of range or is defeated. While a craft runs the panel shows
## its progress (CraftProgress: recipe, bar, time left, "3 / 5"), from the
## predicted lock (PlayerState.equip_left) once it shows up, the client's clock
## since _receive_craft_started before that.
## **A craft needs the panel open**: closing it any way (Esc, F, its X, walking
## out of range, opening another panel) while a craft runs or is asked for
## sends _request_cancel_craft() (the client may only cancel its own action).
##
## Server: re-checks everything (alive, not busy, in range of its own position,
## the recipe belongs to that station's kind, then CraftingRules.check:
## level, materials, bag room) and starts the walk-only lock
## (PlayerState.start_gather: equip_left, a server event). A batch is one lock
## of craft_time x quantity. Leaving range, being hurt, staggered, moved,
## defeated, any movement input (CraftProgress.is_moving: you stand at the
## station) or the owner's cancel request cancels it (nothing taken). When it
## runs out (Player.equip_finished)
## CraftingRules.apply takes the inputs and adds the output in one go (or
## nothing, if the bag changed meanwhile; gear recipes roll each piece with
## this node's server RNG, gear_made= on the SUMMARY line), the owner gets the bag and a feed
## line (LootSystem.bag_changed), and the tradeskill its XP
## (TradeskillSystem.on_crafted, with the "+30 Smelting XP" line).
## Server -> owner, reliable: _receive_craft_started(recipe, quantity, ticks)
## and _receive_craft_ended(result: RESULT_*) after every request.
## A --bot that has the materials for a recipe walks to the Forge on purpose
## as its circling starts (bot_trip: it skips fighting until it's done), opens
## the panel, crafts as many as it can and closes the panel.

## How a craft request ended (_receive_craft_ended).
enum { RESULT_FINISHED, RESULT_CANCELLED, RESULT_REFUSED, RESULT_FAILED }

## Bot: starts a trip to a station in this part of its 8 s cycle (s; the
## circling phase, also right after a gather in it)...
const BOT_TRIP_START := Vector2(6.0, 8.0)
## ...not until this many cycles after a trip that crafted (one a smoke run:
## fights and Husks need the rest), or after one that didn't...
const BOT_TRIP_EVERY := 4
const BOT_TRIP_RETRY := 1
## ...and gives up on a trip after this long (s; stuck on a crate, say).
const BOT_TRIP_TIMEOUT := 16.0
## Bot: asks from within this fraction of the station's range...
const BOT_REACH := 0.7
## ...after standing still this long (ms), so the server's queued inputs from
## the walk there are done and don't count as moving away.
const BOT_SETTLE_MS := 300
## Bot: asks again after this long without an answer (ms), at most BOT_TRIES times a trip.
const BOT_WAIT_MS := 1500
const BOT_TRIES := 3
## Client: seconds between refreshes of the open panel (have/need counts).
const PANEL_REFRESH := 0.25
## Client: a request unanswered this long (ms) no longer holds the Craft buttons.
const PENDING_MS := 3000
## The feed line when moving cancels a craft.
const MOVED_TEXT := "Crafting cancelled: you moved."

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
## Gear pieces crafted (gear recipes; also counted in _items_made).
var _gear_made := 0
## Crafts cancelled by the owner's request (closing the panel), and by moving.
var _cancel_requests := 0
var _moved_cancels := 0
## Rolls crafted gear (seeded at startup, like loot).
var _rng := RandomNumberGenerator.new()
# Client
var _visuals: Array[StationVisual] = []
var _panel: CraftingPanel
var _panel_station := -1
var _panel_timer := 0.0
## The panel was open last frame (closing it cancels a craft).
var _panel_was_open := false
## --crafting-panel (screenshot checks): open at the nearest station once the
## local player exists, and keep it open wherever the bot walks.
var _panel_flag := false
var _requests := 0
var _panel_opens := 0
var _cancels_sent := 0
var _crafts_seen := 0
## The local craft under way (from _receive_craft_started), or null...
var _current: CraftProgress
## ...when its start message came (ms), and whether the predicted lock showed up.
var _current_msec := 0
var _current_locked := false
## A request was sent and not answered yet (since _pending_msec).
var _pending := false
var _pending_msec := 0
## The last _receive_craft_ended result (-1 = none since the last request).
var _last_result := -1
var _bot := false
## Bot: a trip to a station is under way (bot_trip).
var _bot_trip := false
var _bot_trip_msec := 0
var _bot_trip_cycle := -100
## Bot: the first cycle a new trip may start in.
var _bot_next_trip_cycle := -100
var _bot_station := -1
var _bot_recipe := ""
var _bot_tries := 0
var _bot_asked_msec := -1
## Bot: when it last stopped next to the station (ms; -1 = walking).
var _bot_still_msec := -1
var _bot_trips := 0


func _ready() -> void:
	defs = RecipeDefs.current()
	_db = ItemDatabase.current()
	for problem in defs.validate(_db, TradeskillDefs.current()):
		push_error("Crafting data: " + problem)
	_build_stations()
	if multiplayer.is_server():
		_verbose = LaunchArgs.has_flag("verbose")
		_rng.randomize()
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
		if reason == MOVED_TEXT:
			_moved_cancels += 1
			if _verbose:
				print("[server] crafting: %d moved (move %s, buttons %d)" % [peer, player.last_move, player.last_buttons])
		_cancel(player, reason)


# --- Server ---

## Server: stops `player`'s craft (nothing taken) and tells the owner why.
func _cancel(player: Player, reason: String) -> void:
	var peer := player.peer_id
	_active.erase(peer)
	_cancelled += 1
	player.state.cancel_equip()
	loot.notify(peer, reason)
	_receive_craft_ended.rpc_id(peer, RESULT_CANCELLED)
	if _verbose:
		print("[server] crafting: %d interrupted (%s)" % [peer, reason])


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
			_receive_craft_started.rpc_id(peer, recipe_id, quantity, ticks)
			if _verbose:
				print("[server] crafting: %d started %d x %s at station %d" % [peer, quantity, recipe_id, station_id])
		else:
			error = "Finish what you're doing first."
	if not error.is_empty():
		_refused += 1
		loot.notify(peer, error)
		_receive_craft_ended.rpc_id(peer, RESULT_REFUSED)
		if _verbose:
			print("[server] crafting: %d refused %d x %s (%s)" % [peer, quantity, recipe_id, error])


## Client -> server: the owner closed the station's panel, which cancels its
## craft under way (if any; the client can only stop its own action).
@rpc("any_peer", "call_remote", "reliable")
func _request_cancel_craft() -> void:
	if _is_client:
		return
	var peer := multiplayer.get_remote_sender_id()
	var player := players.get_node_or_null(str(peer)) as Player
	if player == null or not _active.has(peer):
		return
	_cancel_requests += 1
	_cancel(player, "Crafting cancelled.")


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
	if CraftProgress.is_moving(player.last_move, player.last_buttons):
		return MOVED_TEXT
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
		_receive_craft_ended.rpc_id(peer, RESULT_FAILED)
		return
	var made_items: Array[Item] = []
	var error := CraftingRules.apply(recipe, quantity, bag, tradeskills.level(peer, recipe.tradeskill),
			_db, defs.max_batch, tradeskills.defs, _rng, made_items)
	if not error.is_empty():
		_failed += 1
		loot.notify(peer, error)
		_receive_craft_ended.rpc_id(peer, RESULT_FAILED)
		return
	_receive_craft_ended.rpc_id(peer, RESULT_FINISHED)
	var made := CraftingRules.made(recipe, quantity)
	_crafts += 1
	_items_made += made
	if recipe.output_kind == RecipeDefs.OUTPUT_GEAR:
		_gear_made += made
	var gained := []
	for item in made_items:
		gained.append(item.to_dict())
	loot.bag_changed(peer, gained)
	tradeskills.on_crafted(peer, recipe.tradeskill, recipe.xp * quantity)
	if _verbose:
		print("[server] crafting: %d made %d %s" % [peer, made, recipe.output])


## The busy bar's label: "Smelting Rustvein Ingot x5".
func _batch_text(recipe: RecipeDefs.Recipe, quantity: int) -> String:
	var text := "%s %s" % [tradeskills.defs.display_name(recipe.tradeskill), recipe.display_name(_db)]
	return text + (" x%d" % quantity if quantity > 1 else "")


func print_summary() -> void:
	print("SUMMARY crafting crafts=%d items_made=%d started=%d cancelled=%d refused=%d failed=%d stations=%d recipes=%d gear_made=%d cancel_requests=%d moved_cancels=%d" % [
			_crafts, _items_made, _started, _cancelled, _refused, _failed, stations.size(), defs.recipes.size(), _gear_made,
			_cancel_requests, _moved_cancels])


# --- Client ---

func _process(delta: float) -> void:
	if not _is_client or _panel == null:
		return
	var local := loot.local_player() if loot else null
	if _panel_flag and _panel_station < 0 and local and not stations.is_empty():
		open_panel(_nearest_station(local.global_position))
	if _panel.visible and not _panel_flag and _should_close(local):
		close_panel()
	if not _panel.visible:
		if _panel_was_open:
			_panel_closed()
		if not _panel_flag:  # closed by Esc (with the flag: stays closed)
			_panel_station = -1
		return
	_panel_was_open = true
	_panel.show_progress(_progress_view(local))
	_panel_timer -= delta
	if _panel_timer <= 0.0:
		_panel_timer = PANEL_REFRESH
		_panel.refresh()


## Client: the panel was closed (any way: Esc, F, its X, out of range, another
## panel, defeat). A craft needs it open, so one under way or asked for is
## cancelled.
func _panel_closed() -> void:
	_panel_was_open = false
	if CraftProgress.cancel_on_close(_current != null, _pending):
		_cancels_sent += 1
		_request_cancel_craft.rpc_id(1)
		if LaunchArgs.has_flag("verbose"):
			print("[client] crafting: panel closed, cancel sent")


## Client: what the panel's progress box shows now: [recipe name, fraction,
## status text], or [] when nothing is being crafted.
func _progress_view(local: Player) -> Array:
	if _current == null:
		return []
	var tps := Engine.physics_ticks_per_second
	var left: int
	if local and local.state.is_equipping():
		_current_locked = true
		left = local.state.equip_left  # predicted: smooth, and the server's count
	elif _current_locked:
		left = 0  # the lock ran out; the end message is on its way
	else:
		var elapsed := roundi((Time.get_ticks_msec() - _current_msec) / 1000.0 * tps)
		left = _current.ticks_left_after(elapsed)
	var recipe := defs.get_recipe(_current.recipe_id)
	var title := recipe.display_name(_db) if recipe else _current.recipe_id
	if _current.quantity > 1:
		title += "  x%d" % _current.quantity
	return [title, _current.fraction(left), _current.status_text(left, tps)]


@rpc("authority", "call_remote", "reliable")
func _receive_craft_started(recipe_id: String, quantity: int, ticks: int) -> void:
	var recipe := defs.get_recipe(recipe_id)
	_current = CraftProgress.new(recipe_id, quantity, ticks, recipe.craft_ticks if recipe else ticks)
	_current_msec = Time.get_ticks_msec()
	_current_locked = false
	_pending = false


@rpc("authority", "call_remote", "reliable")
func _receive_craft_ended(result: int) -> void:
	_current = null
	_pending = false
	_last_result = result
	if result == RESULT_FINISHED:
		_crafts_seen += 1
	if _panel and _panel.visible:
		_panel.show_progress([])
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
	if _panel_station < 0 or crafting():
		return
	_requests += 1
	_pending = true
	_pending_msec = Time.get_ticks_msec()
	_last_result = -1
	_request_craft.rpc_id(1, _panel_station, recipe_id, quantity)


## Client: a craft of ours is under way or asked for (the panel's Craft
## buttons wait). An unanswered request stops counting after PENDING_MS.
func crafting() -> bool:
	if _pending and Time.get_ticks_msec() - _pending_msec > PENDING_MS:
		_pending = false
	return _current != null or _pending


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


## Bot (World._bot_input, every tick unless a gather is under way): a trip to
## a station. Starts in BOT_TRIP_START of a cycle (at most every BOT_TRIP_EVERY
## cycles) when the bag holds the materials for a recipe at any station (the
## nearest such one; refining before gear): walks there (however far), stands
## still BOT_SETTLE_MS, opens the panel, crafts as many as it can (Max, so a
## batch runs), keeps still until the server says it ended, closes the panel.
## Returns the move to use while on the trip (World then presses nothing), or null.
func bot_trip(local: Player, phase: float, cycle: int) -> Variant:
	var now := Time.get_ticks_msec()
	if not _bot_trip:
		if (local.state.dead or local.state.is_equipping() or crafting()
				or phase < BOT_TRIP_START.x or phase >= BOT_TRIP_START.y
				or cycle < _bot_next_trip_cycle):
			return null
		_bot_pick(local)
		if _bot_station < 0:
			return null
		_bot_trip = true
		_bot_trip_msec = now
		_bot_trip_cycle = cycle
		_bot_next_trip_cycle = cycle + BOT_TRIP_RETRY
		_bot_tries = 0
		_bot_asked_msec = -1
		_bot_still_msec = -1
		_bot_trips += 1
		if LaunchArgs.has_flag("verbose"):
			print("[client] crafting: walking to station %d (%.1f m) for %s (frame %d)" % [_bot_station,
					local.global_position.distance_to(stations[_bot_station].position), _bot_recipe, now / 250])
	if _current != null:
		_bot_trip_msec = now  # (the timeout is for getting there and getting an answer)
		return Vector2.ZERO  # crafting: stand still, panel open
	if now - _bot_trip_msec > BOT_TRIP_TIMEOUT * 1000.0:
		_end_bot_trip("timed out")
		return null
	if local.state.dead:
		# Keeps the trip: it walks on from where it rises (a Rebirth) or respawns
		# (the spawn circle, nearer the Forge than the camp).
		_bot_asked_msec = -1
		_bot_still_msec = -1
		return null
	if _bot_asked_msec >= 0:
		if _last_result == RESULT_FINISHED:
			_bot_next_trip_cycle = _bot_trip_cycle + BOT_TRIP_EVERY
			_end_bot_trip("crafted")
			return null
		if _current != null:
			return Vector2.ZERO  # crafting: stand still, panel open
		if _last_result < 0 and now - _bot_asked_msec < BOT_WAIT_MS:
			return Vector2.ZERO  # waiting for the answer
		# Refused (still finishing a swing), cancelled or unanswered: ask again.
		_bot_asked_msec = -1
		_bot_still_msec = -1
		_pending = false
		if _bot_tries >= BOT_TRIES:
			_end_bot_trip("no craft after %d tries" % _bot_tries)
			return null
	var station := stations[_bot_station]
	var to := station.position - local.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() > _reach_of[station.kind] * BOT_REACH:
		_bot_still_msec = -1
		return flat.normalized()
	if _bot_still_msec < 0:
		_bot_still_msec = now
	if (now - _bot_still_msec < BOT_SETTLE_MS or not local.state.can_change_loadout()
			or local.state.is_dodging() or not local.state.can_act()):
		return Vector2.ZERO  # settle; finish a swing, roll or gear change first
	var quantity := _bot_quantity(local)
	if quantity <= 0:
		_end_bot_trip("nothing left to craft")
		return null
	if not _panel.visible or _panel_station != _bot_station:
		open_panel(_bot_station)
	_bot_tries += 1
	_bot_asked_msec = now
	request_craft(_bot_recipe, quantity)
	if LaunchArgs.has_flag("verbose"):
		print("[client] crafts %d x %s at station %d (frame %d)" % [quantity, _bot_recipe, _bot_station, now / 250])
	return Vector2.ZERO


## Bot: how many of its recipe it can make now (Max, re-picked if the bag changed).
func _bot_quantity(local: Player) -> int:
	var recipe := defs.get_recipe(_bot_recipe)
	var bag := local_bag()
	var quantity := CraftingRules.max_quantity(recipe, bag, local_level(recipe.tradeskill), _db,
			defs.max_batch) if recipe else 0
	if quantity > 0:
		return quantity
	var station := _bot_station
	_bot_pick(local)
	if _bot_station != station:  # only recipes at this station
		_bot_station = station
		return 0
	recipe = defs.get_recipe(_bot_recipe)
	return CraftingRules.max_quantity(recipe, bag, local_level(recipe.tradeskill), _db, defs.max_batch)


func _end_bot_trip(why: String) -> void:
	_bot_trip = false
	_bot_asked_msec = -1
	if not _panel_flag:
		close_panel()  # nothing under way by now, unless it gave up mid-craft (cancelled)
	if LaunchArgs.has_flag("verbose"):
		print("[client] crafting: trip ended (%s) (frame %d)" % [why, Time.get_ticks_msec() / 250])
	_bot_station = -1


## The nearest station with a recipe the bot can make one of, refining
## (item recipes) before gear.
func _bot_pick(local: Player) -> void:
	_bot_station = -1
	var bag := local_bag()
	var best := INF
	for gear in [false, true]:
		for station in stations:
			var distance := Vector2(station.position.x - local.global_position.x,
					station.position.z - local.global_position.z).length()
			if distance >= best:
				continue
			for recipe in defs.recipes_for(station.kind):
				if (recipe.output_kind == RecipeDefs.OUTPUT_GEAR) != gear:
					continue
				if CraftingRules.check(recipe, 1, bag, local_level(recipe.tradeskill), _db, defs.max_batch).is_empty():
					best = distance
					_bot_station = station.id
					_bot_recipe = recipe.id
					break
		if _bot_station >= 0:
			return


func print_client_summary() -> void:
	print("SUMMARY client=%d crafting requests=%d panel_opens=%d trips=%d crafts_seen=%d cancels_sent=%d" % [
			multiplayer.get_unique_id(), _requests, _panel_opens, _bot_trips, _crafts_seen, _cancels_sent])
