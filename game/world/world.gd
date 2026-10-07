class_name World
extends Node3D
## The shared game world, at /root/Main/World on the server and every client.
##
## Server: spawns a player when a client says it's ready, simulates players from
## their inputs every physics tick and sends snapshots of every player.
## Client: sends its inputs every tick, predicts its own player, and draws other
## players interpolated between snapshots.

const PLAYER_SCENE := preload("res://game/player/player.tscn")
const HUD_SCENE := preload("res://ui/hud.tscn")
## Inputs per packet the server accepts; anything larger is dropped as malformed.
const MAX_INPUTS_PER_PACKET := 8
const SPAWN_RADIUS := 3.0

# Server
var _tick := 0
var _snapshot_interval := 3
var _max_input_buffer := 8
var _max_inputs_per_tick := 2

# Client
var _hud: Hud
var _local_player: Player
var _render_time := -1.0
var _interpolation_delay := 0.1
var _input_redundancy := 3
var _snapshots_received := 0
var _bot := false
var _verbose := false
var _log_timer := 0.0

@onready var _players: Node3D = $Players


func _ready() -> void:
	_verbose = LaunchArgs.has_flag("verbose")
	if multiplayer.is_server():
		var snapshot_rate: int = Tuning.get_value("network", "server", "snapshot_rate")
		_snapshot_interval = maxi(1, roundi(Engine.physics_ticks_per_second / float(snapshot_rate)))
		_max_input_buffer = Tuning.get_value("network", "server", "max_input_buffer")
		_max_inputs_per_tick = Tuning.get_value("network", "server", "max_inputs_per_tick")
		Net.peer_left.connect(_on_peer_left)
	else:
		_interpolation_delay = Tuning.get_value("network", "client", "interpolation_delay")
		_input_redundancy = Tuning.get_value("network", "client", "input_redundancy")
		_bot = LaunchArgs.has_flag("bot")
		_hud = HUD_SCENE.instantiate()
		add_child(_hud)
		_client_ready.rpc_id(1)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_tick(delta)
	elif _local_player:
		_client_tick(delta)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		return
	if _render_time >= 0.0:
		_render_time += delta
		for player: Player in _players.get_children():
			if not player.is_local:
				player.interpolate(_render_time)
	_update_hud()
	if _verbose:
		_log_timer += delta
		if _log_timer >= 2.0:
			_log_timer = 0.0
			print(_describe_players())


# --- Server ---

func _server_tick(delta: float) -> void:
	_tick += 1
	for player: Player in _players.get_children():
		player.server_process_inputs(_max_inputs_per_tick, delta)
	if _tick % _snapshot_interval == 0:
		_broadcast_snapshot()


func _broadcast_snapshot() -> void:
	var states: Array = []
	for player: Player in _players.get_children():
		states.append(player.get_state())
	var connected := multiplayer.get_peers()
	for player: Player in _players.get_children():
		# A peer can be mid-disconnect for a moment before peer_left fires.
		if player.peer_id in connected:
			_receive_snapshot.rpc_id(player.peer_id, _tick, states)


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if _players.has_node(str(peer_id)):
		return
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.peer_id = peer_id
	var angle := _players.get_child_count() * TAU / 8.0
	player.position = Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS + Vector3.UP * 0.1
	_players.add_child(player)
	print("[server] peer %d joined (%d players)" % [peer_id, _players.get_child_count()])


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_inputs(inputs: Array) -> void:
	if not multiplayer.is_server() or inputs.size() > MAX_INPUTS_PER_PACKET:
		return
	var player := _players.get_node_or_null(str(multiplayer.get_remote_sender_id())) as Player
	if player:
		player.server_queue_inputs(inputs, _max_input_buffer)


func _on_peer_left(peer_id: int) -> void:
	var player := _players.get_node_or_null(str(peer_id))
	if player:
		_players.remove_child(player)
		player.queue_free()
	print("[server] peer %d left (%d players)" % [peer_id, _players.get_child_count()])


# --- Client ---

func _client_tick(delta: float) -> void:
	var move := Vector2.ZERO
	var jump := false
	if _bot:
		# Walk in circles and hop now and then, for testing without a second person.
		var t := Time.get_ticks_msec() / 1000.0 + float(multiplayer.get_unique_id() % 100)
		move = Vector2(cos(t * 0.8), sin(t * 0.8))
		jump = fmod(t, 3.0) < 0.05
	else:
		move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		jump = Input.is_action_pressed(&"jump")
	var inputs := _local_player.client_predict(move, jump, delta, _input_redundancy)
	_submit_inputs.rpc_id(1, inputs)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_snapshot(tick: int, states: Array) -> void:
	_snapshots_received += 1
	var server_time := tick / float(Engine.physics_ticks_per_second)
	_sync_render_clock(server_time)
	var my_id := multiplayer.get_unique_id()
	var seen := {}
	for state: Array in states:
		var peer_id: int = state[0]
		seen[peer_id] = true
		var player := _players.get_node_or_null(str(peer_id)) as Player
		if player == null:
			player = _spawn_client_player(peer_id, peer_id == my_id, state[1])
		if player.is_local:
			player.client_receive_ack(state[1], state[2], state[4])
		else:
			player.push_snapshot(server_time, state[1], state[3])
	for player: Player in _players.get_children():
		if not seen.has(player.peer_id):
			print("[client] peer %d left" % player.peer_id)
			_players.remove_child(player)
			player.queue_free()


func _spawn_client_player(peer_id: int, local: bool, pos: Vector3) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.peer_id = peer_id
	player.is_local = local
	player.position = pos
	_players.add_child(player)
	if local:
		_local_player = player
	else:
		print("[client %d] sees peer %d" % [multiplayer.get_unique_id(), peer_id])
	return player


## Remote players are drawn at (latest server time - interpolation delay). The
## clock runs on local time and is nudged toward the server's to absorb jitter.
func _sync_render_clock(server_time: float) -> void:
	var target := server_time - _interpolation_delay
	if _render_time < 0.0 or absf(_render_time - target) > 0.25:
		_render_time = target
	else:
		_render_time = lerpf(_render_time, target, 0.05)


func _update_hud() -> void:
	if _hud == null:
		return
	var lines := PackedStringArray([
		"Peer %d   Players: %d   Ping: %d ms" % [
				multiplayer.get_unique_id(), _players.get_child_count(), Net.get_ping_ms()],
		"Snapshots: %d   Prediction corrections: %d" % [
				_snapshots_received, _local_player.corrections if _local_player else 0],
	])
	if _bot:
		lines.append("BOT MODE")
	_hud.set_info("\n".join(lines))


func _describe_players() -> String:
	var parts := PackedStringArray()
	for player: Player in _players.get_children():
		var p := player.global_position
		parts.append("%s%d@(%.1f, %.1f)" % ["*" if player.is_local else "", player.peer_id, p.x, p.z])
	return "[client %d] %s" % [multiplayer.get_unique_id(), "  ".join(parts)]


## Printed when the process exits via --quit-after; used by tools/smoke_test.ps1.
func print_summary() -> void:
	if multiplayer.is_server():
		print("SUMMARY server players=%d ticks=%d" % [_players.get_child_count(), _tick])
		return
	if _local_player:
		print("SUMMARY client=%d snapshots=%d corrections=%d" % [
				multiplayer.get_unique_id(), _snapshots_received, _local_player.corrections])
	for player: Player in _players.get_children():
		if not player.is_local:
			print("SUMMARY client=%d remote=%d moved=%.1f" % [
					multiplayer.get_unique_id(), player.peer_id, player.distance_seen])
