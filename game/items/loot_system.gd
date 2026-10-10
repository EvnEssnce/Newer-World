class_name LootSystem
extends Node
## Loot drops, pickup, inventories and equipped gear over the network. World adds one at
## World/Loot on the server and on every client (RPCs are matched by node path).
## Not part of the predicted sim: nothing here touches PlayerState or the inputs.
##
## Server: owns every player's Inventory and the GroundLoot. When an enemy dies,
## each player who damaged it (Enemy.damaged_by) gets their own roll of its loot
## table (personal loot), dropped where it died; only that player is told about
## it. F sends a pickup request with nothing in it: the server picks up the
## sender's own drops within pickup_range of its own position for them, nearest
## first, until the inventory is full. Drops expire after `lifetime`.
## Equipping: the client asks to equip a bag item into an equip slot (or take
## one off); the server checks it (Equipment.check), starts the equip time
## (PlayerState.start_equip, a server event, so walking only) and applies the
## change on the step it ends (Player.equip_finished): a weapon item also sets
## that loadout slot's weapon type (BuildService.apply_weapons). The totals go
## to Player.gear / bonus_max_health, which World's combat numbers read.
## Inventories and gear are lost on disconnect (persistence is milestone 5).
## Client: draws its own drops (LootDropVisual), shows the pickup prompt, a feed
## of what it picked up and the equip bar (LootHud), and the inventory on I
## (InventoryPanel). A --bot picks up whatever of its own lands within reach and
## puts on armor and Wing Enhancements that beat what it wears.

## Bot: milliseconds between pickup requests while one of its drops is in reach.
const BOT_PICKUP_INTERVAL_MS := 500
## Bot: asks only within this fraction of pickup_range, so a drop right at the
## edge (where its position and the server's can disagree) isn't asked for.
const BOT_PICKUP_REACH := 0.8

## Bot: equips only in these parts of its 8 s cycle (World.bot_phase): the
## first second of its fight turn (it's often still walking up; a Juggernaut's
## long recoveries can fill a shorter window), and as the circling starts, so
## the 1 s equip time is over before its swap retry (7.2 s), dodges and 7.6 s
## respec.
const BOT_EQUIP_PHASES: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(6.0, 6.2)]

## World/Players. Set by World before adding this node.
var players: Node3D
## World/Builds (weapon items change the loadout). Set by World.
var builds: BuildService

var _is_client := false
var _db: ItemDatabase
var _pickup_range := 2.5
# Server
var _tick := 0
var _lifetime_ticks := 0
var _scatter := 1.0
var _slots := 0
var _ground := GroundLoot.new()
var _inventories: Dictionary[int, Inventory] = {}
var _equipment: Dictionary[int, Equipment] = {}
## Peer -> the gear change it's waiting on: ["equip", item uid, equip slot] or
## ["unequip", 0, equip slot].
var _pending: Dictionary[int, Array] = {}
var _equips := 0
var _unequips := 0
var _rng := RandomNumberGenerator.new()
var _verbose := false
var _kills_rolled := 0
var _drops := 0
var _items_dropped := 0
var _pickups := 0
var _items_picked := 0
var _expired := 0
var _full_refusals := 0
var _discards := 0
## Rarity id -> items dropped of it.
var _dropped_by_rarity: Dictionary[String, int] = {}
# Client
## The local player's inventory, as the server last sent it.
var inventory: Array[Item] = []
var capacity := 0
## The local player's equipped gear, as the server last sent it.
var equipment := Equipment.new()
var _equip_text := ""
var _equip_ticks := 1
var _bot_next_equip_msec := 0
var _bot_last_phase := 0.0
## Drop id -> [position: Vector3, items: Array[Item], visual: LootDropVisual].
var _seen: Dictionary[int, Array] = {}
var _drops_seen := 0
var _picked_seen := 0
var _hud: LootHud
var _panel: InventoryPanel
var _bot := false
var _bot_next_pickup_msec := 0


func _ready() -> void:
	_db = ItemDatabase.current()
	_pickup_range = Tuning.get_value("loot", "drops", "pickup_range")
	if multiplayer.is_server():
		_lifetime_ticks = roundi(Tuning.get_value("loot", "drops", "lifetime")
				* Engine.physics_ticks_per_second)
		_slots = Tuning.get_value("loot", "inventory", "slots")
		_scatter = Tuning.get_value("loot", "drops", "scatter")
		_rng.randomize()
		_verbose = LaunchArgs.has_flag("verbose")
		Net.peer_left.connect(_on_peer_left)
	else:
		_is_client = true
		_bot = LaunchArgs.has_flag("bot")
		_hud = LootHud.new()
		add_child(_hud)
		_panel = InventoryPanel.new()
		_hud.add_child(_panel)
		_panel.setup(self, _db)
		# For checking the panel from --screenshot-dir frames.
		if LaunchArgs.has_flag("inventory-panel"):
			_panel.toggle()


func _physics_process(_delta: float) -> void:
	if _is_client:
		return
	_tick += 1
	# A change whose equip time ended without finishing (defeated meanwhile).
	for peer: int in _pending.keys():
		var player := players.get_node_or_null(str(peer)) as Player
		if player == null or not player.state.is_equipping():
			_pending.erase(peer)
			if player:
				_receive_notice.rpc_id(peer, "Gear change interrupted.")
	for drop in _ground.expire(_tick):
		_expired += 1
		if _has_player(drop.owner):
			_receive_drop_removed.rpc_id(drop.owner, drop.id)


func _process(_delta: float) -> void:
	if not _is_client:
		return
	var local := local_player()
	var in_reach: Array[int] = []
	if local:
		in_reach = _drops_in_reach(local, _pickup_range)
	if _bot and local and not local.state.dead and Time.get_ticks_msec() >= _bot_next_pickup_msec \
			and not _drops_in_reach(local, _pickup_range * BOT_PICKUP_REACH).is_empty():
		_bot_next_pickup_msec = Time.get_ticks_msec() + BOT_PICKUP_INTERVAL_MS
		_request_pickup.rpc_id(1)
	var prompt := ""
	if not in_reach.is_empty() and not local.state.dead:
		var items: Array[Item] = []
		for id: int in in_reach:
			items.append_array(_seen[id][1])
		var best := Item.best_of(items, _db)
		prompt = "[F] Pick up %s" % best.display_name(_db)
		if items.size() > 1:
			prompt += "  (+%d more)" % (items.size() - 1)
		_hud.set_prompt(prompt, best.rarity_color(_db))
	else:
		_hud.set_prompt("", Color.WHITE)
	if local and local.state.is_equipping():
		_hud.set_equip_progress(_equip_text if not _equip_text.is_empty() else "Changing gear",
				1.0 - local.state.equip_left / float(_equip_ticks))
	else:
		_hud.set_equip_progress("", 0.0)
	if _bot and local:
		_bot_equip(local)


# --- Server ---

## A player joined: give them an empty inventory and no gear, and send them.
func add_player(peer: int) -> void:
	_inventories[peer] = Inventory.new(_slots)
	_equipment[peer] = Equipment.new()
	_send_inventory(peer)


## An enemy died: everyone who damaged it and is still here gets their own
## roll of its loot table, dropped on the ground `scatter` m from where it died.
func on_enemy_killed(enemy: Enemy) -> void:
	var table: ItemDatabase.LootTable = _db.tables.get(enemy.params.loot_table)
	if table == null:
		return
	var contributors: Array[int] = []
	for peer: int in enemy.damaged_by:
		if _inventories.has(peer) and _has_player(peer):
			contributors.append(peer)
	if contributors.is_empty():
		return
	_kills_rolled += 1
	var loot := LootRoller.roll_kill(table, _db, contributors, _rng)
	for peer: int in loot:
		var items: Array[Item] = []
		items.assign(loot[peer])
		var angle := _rng.randf() * TAU
		var position := _ground_below(enemy.global_position
				+ Vector3(cos(angle), 0.0, sin(angle)) * _scatter)
		var drop := _ground.add(peer, position, items, _tick, _lifetime_ticks)
		_drops += 1
		_items_dropped += items.size()
		for item in items:
			_dropped_by_rarity[item.rarity] = _dropped_by_rarity.get(item.rarity, 0) + 1
		if _verbose:
			var described := PackedStringArray()
			for item in items:
				described.append(item.describe(_db))
			print("[server] loot: enemy %d dropped for %d: %s" % [enemy.enemy_id, peer,
					", ".join(described)])
		_send_drop(drop)


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup() -> void:
	var peer := _sender()
	if peer == 0:
		return
	var player := players.get_node(str(peer)) as Player
	if player.state.dead:
		_receive_notice.rpc_id(peer, "You can't pick things up while defeated.")
		return
	var drops := _ground.in_reach(peer, player.global_position, _pickup_range)
	if drops.is_empty():
		_receive_notice.rpc_id(peer, "Nothing of yours to pick up here.")
		return
	var bag := _inventories[peer]
	var picked: Array = []
	for drop in drops:
		var moved := _ground.take_into(drop, bag)
		for item in moved:
			picked.append(item.to_dict())
		if _ground.drops.has(drop.id):
			_send_drop(drop)  # what's left of it
		else:
			_receive_drop_removed.rpc_id(peer, drop.id)
	if not picked.is_empty():
		_pickups += 1
		_items_picked += picked.size()
		_send_inventory(peer)
		_receive_picked.rpc_id(peer, picked)
	if bag.is_full() and _ground.in_reach(peer, player.global_position, _pickup_range).size() > 0:
		_full_refusals += 1
		_receive_notice.rpc_id(peer, "Inventory full (%d/%d). Discard something (I) to make room." % [
				bag.items.size(), bag.capacity])


@rpc("any_peer", "call_remote", "reliable")
func _request_discard(uid: int) -> void:
	var peer := _sender()
	if peer == 0:
		return
	var item := _inventories[peer].remove(uid)
	if item == null:
		return
	_discards += 1
	_send_inventory(peer)
	_receive_notice.rpc_id(peer, "Discarded %s." % item.display_name(_db))


# --- Server: equipping ---

@rpc("any_peer", "call_remote", "reliable")
func _request_equip(uid: int, equip_slot: String) -> void:
	var peer := _sender()
	if peer == 0:
		return
	var player := players.get_node(str(peer)) as Player
	var item := _inventories[peer].get_item(uid)
	if item == null:
		return
	var error := _equip_error(player, item, equip_slot)
	if error.is_empty():
		var def: ItemDatabase.ItemDef = _db.items[item.item_id]
		if not def.weapon_type.is_empty():
			equip_slot = Equipment.weapon_target(def.weapon_type, equip_slot, player.state.weapons)
		error = _start_change(player, ["equip", uid, equip_slot], "Equipping " + item.display_name(_db))
	if not error.is_empty():
		_receive_notice.rpc_id(peer, error)


@rpc("any_peer", "call_remote", "reliable")
func _request_unequip(equip_slot: String) -> void:
	var peer := _sender()
	if peer == 0:
		return
	var player := players.get_node(str(peer)) as Player
	var item := _equipment[peer].get_item(equip_slot)
	if item == null:
		return
	var error := "Your inventory is full." if _inventories[peer].is_full() else ""
	if error.is_empty():
		error = _start_change(player, ["unequip", 0, equip_slot], "Taking off " + item.display_name(_db))
	if not error.is_empty():
		_receive_notice.rpc_id(peer, error)


func _equip_error(player: Player, item: Item, equip_slot: String) -> String:
	if player.build == null:
		return "No build yet."
	var class_def := player.build.class_def
	return Equipment.check(item, equip_slot, _db, class_def.id, class_def.weapons)


## Starts the equip time for a change; "" or why it can't start.
func _start_change(player: Player, change: Array, text: String) -> String:
	if _pending.has(player.peer_id) or player.state.is_equipping():
		return "You're already changing gear."
	if player.state.dead:
		return "You can't change gear while defeated."
	var ticks := GearScore.current().equip_ticks
	if not player.state.start_equip(ticks):
		return "Finish what you're doing first."
	_pending[player.peer_id] = change
	_receive_equip_started.rpc_id(player.peer_id, text, ticks)
	return ""


## Server (Player.equip_finished): the equip time is over; makes the change.
func finish_equip(player: Player) -> void:
	var peer := player.peer_id
	if not _pending.has(peer):
		return
	var change: Array = _pending[peer]
	_pending.erase(peer)
	var bag := _inventories[peer]
	var worn := _equipment[peer]
	var equip_slot: String = change[2]
	if change[0] == "unequip":
		var item := worn.unequip(equip_slot)
		if item == null:
			return
		if not bag.add(item):
			worn.equip(equip_slot, item)
			_receive_notice.rpc_id(peer, "Your inventory is full.")
			return
		_unequips += 1
		_receive_notice.rpc_id(peer, "Took off %s." % item.display_name(_db))
	else:
		var item := bag.get_item(change[1])
		if item == null:
			return
		var error := _equip_error(player, item, equip_slot)
		var index := Equipment.weapon_index(equip_slot)
		var def: ItemDatabase.ItemDef = _db.items[item.item_id]
		if error.is_empty() and index >= 0 and player.state.weapons[index] != def.weapon_type:
			var loadout := player.state.weapons.duplicate()
			loadout[index] = def.weapon_type
			error = builds.apply_weapons(player, loadout)
		if not error.is_empty():
			_receive_notice.rpc_id(peer, error)
			return
		bag.remove(item.uid)
		var previous := worn.equip(equip_slot, item)
		var back: Array[Item] = worn.sync_weapons(player.state.weapons, _db)
		if previous:
			back.push_front(previous)
		for returned in back:
			if not bag.add(returned):  # can't happen: equipping freed a slot
				push_warning("Loot: no room for %s, lost" % returned.describe(_db))
		_equips += 1
		_receive_notice.rpc_id(peer, "Equipped %s." % item.display_name(_db))
		if _verbose:
			print("[server] loot: %d equipped %s in %s" % [peer, item.describe(_db), equip_slot])
	_apply_gear(player)
	_send_inventory(peer)


## Server: the K panel is about to change the weapon types: "" if every weapon
## item whose type leaves the loadout fits in the bag, else why not.
func check_weapon_change(player: Player, weapons: PackedStringArray) -> String:
	var worn: Equipment = _equipment.get(player.peer_id)
	if worn == null:
		return ""
	var leaving := 0
	for equip_slot in ["weapon_1", "weapon_2"]:
		var item := worn.get_item(equip_slot)
		if item and _db.items[item.item_id].weapon_type not in weapons:
			leaving += 1
	if leaving > _inventories[player.peer_id].free_slots():
		return "No room in your inventory for the weapon you'd take off."
	return ""


## Server: the weapon types changed (K panel): weapon items follow their type,
## or go back to the bag.
func weapons_changed(player: Player) -> void:
	var worn: Equipment = _equipment.get(player.peer_id)
	if worn == null:
		return
	var back := worn.sync_weapons(player.state.weapons, _db)
	for item in back:
		_inventories[player.peer_id].add(item)
	_apply_gear(player)
	_send_inventory(player.peer_id)


## Server: the gear totals the combat numbers use, and max health (current
## health never goes above it).
func _apply_gear(player: Player) -> void:
	var stats := _equipment[player.peer_id].stats(_db, GearScore.current().average_weights)
	player.gear = stats
	player.bonus_max_health = stats.bonus("max_health")
	player.health = minf(player.health, player.max_health())


## The peer that sent this request, if it has a player and an inventory; else 0.
func _sender() -> int:
	if _is_client:
		return 0
	var peer := multiplayer.get_remote_sender_id()
	return peer if _has_player(peer) and _inventories.has(peer) else 0


func _has_player(peer: int) -> bool:
	return players.has_node(str(peer)) and peer in multiplayer.get_peers()


func _send_drop(drop: GroundLoot.Drop) -> void:
	var items: Array = []
	for item in drop.items:
		items.append(item.to_dict())
	_receive_drop.rpc_id(drop.owner, drop.id, drop.position, items)


func _send_inventory(peer: int) -> void:
	var bag := _inventories[peer]
	_receive_inventory.rpc_id(peer, bag.to_array(), bag.capacity, _equipment[peer].to_dict())


## Where a drop lands: the ground straight below `from` (a launched enemy can
## die in the air), or `from` itself if there's no ground within 50 m.
func _ground_below(from: Vector3) -> Vector3:
	var space := players.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.5, from + Vector3.DOWN * 50.0, 1)
	var hit := space.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else from


func _on_peer_left(peer: int) -> void:
	_inventories.erase(peer)
	_equipment.erase(peer)
	_pending.erase(peer)
	_ground.remove_owner(peer)


func print_summary() -> void:
	var rarities := PackedStringArray()
	for id in _db.rarity_order:
		rarities.append("%s:%d" % [id, _dropped_by_rarity.get(id, 0)])
	print("SUMMARY loot kills_rolled=%d drops=%d items_dropped=%d pickups=%d items_picked=%d expired=%d full=%d discards=%d rarities=%s" % [
			_kills_rolled, _drops, _items_dropped, _pickups, _items_picked, _expired,
			_full_refusals, _discards, ",".join(rarities)])
	print("SUMMARY gear equips=%d unequips=%d" % [_equips, _unequips])


# --- Client ---

@rpc("authority", "call_remote", "reliable")
func _receive_drop(id: int, position: Vector3, item_data: Array) -> void:
	var items := Inventory.items_from_array(item_data)
	if _seen.has(id):
		var visual: LootDropVisual = _seen[id][2]
		visual.show_items(items, _db)
		_seen[id][1] = items
		return
	_drops_seen += 1
	var visual := LootDropVisual.new()
	add_child(visual)
	visual.global_position = position
	visual.show_items(items, _db)
	_seen[id] = [position, items, visual]


@rpc("authority", "call_remote", "reliable")
func _receive_drop_removed(id: int) -> void:
	if _seen.has(id):
		(_seen[id][2] as Node).queue_free()
		_seen.erase(id)


@rpc("authority", "call_remote", "reliable")
func _receive_inventory(item_data: Array, slots: int, worn: Dictionary) -> void:
	inventory = Inventory.items_from_array(item_data)
	capacity = slots
	equipment = Equipment.from_dict(worn)
	if _panel:
		_panel.refresh()


@rpc("authority", "call_remote", "reliable")
func _receive_equip_started(text: String, ticks: int) -> void:
	_equip_text = text
	_equip_ticks = maxi(1, ticks)


@rpc("authority", "call_remote", "reliable")
func _receive_picked(item_data: Array) -> void:
	for item in Inventory.items_from_array(item_data):
		_picked_seen += 1
		_hud.add_feed_line("+ %s" % item.display_name(_db), item.rarity_color(_db))


@rpc("authority", "call_remote", "reliable")
func _receive_notice(text: String) -> void:
	if _hud:
		_hud.add_feed_line(text, LootHud.NOTICE_COLOR)


## Client: asks the server to throw away an inventory item.
func request_discard(uid: int) -> void:
	_request_discard.rpc_id(1, uid)


## Client: asks to equip an inventory item in an equip slot (Equipment.SLOTS).
func request_equip(uid: int, equip_slot: String) -> void:
	_request_equip.rpc_id(1, uid, equip_slot)


func request_unequip(equip_slot: String) -> void:
	_request_unequip.rpc_id(1, equip_slot)


## Client: the local character's class, or null before the server's build arrives.
func local_class() -> ClassDef:
	return builds.local_build.class_def if builds and builds.local_build else null


## Bot: puts on armor or a Wing Enhancement from the bag when its slot is empty
## or the item's main stat beats what's worn (never weapons: the bot picks its
## weapons per cycle in the K panel).
func _bot_equip(local: Player) -> void:
	var class_def := local_class()
	var phase := (get_parent() as World).bot_phase()
	var last := _bot_last_phase
	_bot_last_phase = phase
	# In a window, or just past its start (a slow frame can jump over it).
	var in_window := BOT_EQUIP_PHASES.any(func(w: Vector2) -> bool:
			return (phase >= w.x and phase < w.y) or (last < w.x and phase >= w.x))
	if class_def == null or local.state.dead or not local.state.can_change_loadout() \
			or not in_window or Time.get_ticks_msec() < _bot_next_equip_msec:
		return
	for item in inventory:
		var def: ItemDatabase.ItemDef = _db.items.get(item.item_id)
		if def == null or def.slot == "weapon":
			continue
		if not Equipment.check(item, def.slot, _db, class_def.id, class_def.weapons).is_empty():
			continue
		var worn := equipment.get_item(def.slot)
		if worn == null or item.primary_value > worn.primary_value:
			_bot_next_equip_msec = Time.get_ticks_msec() + 1000  # once per window
			request_equip(item.uid, def.slot)
			return


func _unhandled_input(event: InputEvent) -> void:
	if not _is_client or local_player() == null or event.is_echo():
		return
	if event.is_action_pressed(&"pickup"):
		_request_pickup.rpc_id(1)
	elif event.is_action_pressed(&"toggle_inventory"):
		_panel.toggle()


## Ids of our drops within `reach` of where we're drawn, nearest first (the
## server checks again with its own positions).
func _drops_in_reach(local: Player, reach: float) -> Array[int]:
	var ids: Array[int] = []
	var here := Vector2(local.global_position.x, local.global_position.z)
	for id: int in _seen:
		var pos: Vector3 = _seen[id][0]
		if here.distance_to(Vector2(pos.x, pos.z)) <= reach:
			ids.append(id)
	ids.sort_custom(func(a: int, b: int) -> bool:
			var pa: Vector3 = _seen[a][0]
			var pb: Vector3 = _seen[b][0]
			return here.distance_to(Vector2(pa.x, pa.z)) < here.distance_to(Vector2(pb.x, pb.z)))
	return ids


func local_player() -> Player:
	if players == null:
		return null
	for player: Player in players.get_children():
		if player.is_local:
			return player
	return null


func print_client_summary() -> void:
	print("SUMMARY client=%d loot drops_seen=%d picked=%d inventory=%d equipped=%d" % [
			multiplayer.get_unique_id(), _drops_seen, _picked_seen, inventory.size(),
			equipment.items.size()])
