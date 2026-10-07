class_name World
extends Node3D
## The shared game world, at /root/Main/World on the server and every client.
##
## Server: spawns a player when a client says it's ready, simulates players from
## their inputs every physics tick, resolves melee hits and sends snapshots of
## every player.
## Client: sends its inputs every tick, predicts its own player, draws other
## players interpolated between snapshots, and shows hits the server reports.

## Results sent with each hit event.
const HIT_DAMAGED := 0
const HIT_EVADED := 1
const HIT_DEFEATED := 2

const PLAYER_SCENE := preload("res://game/player/player.tscn")
const HUD_SCENE := preload("res://ui/hud.tscn")
## Inputs per packet the server accepts; anything larger is dropped as malformed.
const MAX_INPUTS_PER_PACKET := 8
const SPAWN_RADIUS := 3.0
## Bot fight phase: walk to this distance from the target before swinging.
const BOT_ATTACK_DISTANCE := 1.6

# Server
var _tick := 0
var _snapshot_interval := 3
var _max_input_buffer := 8
var _max_inputs_per_tick := 2
var _hits := 0

# Client
var _hud: Hud
var _local_player: Player
var _render_time := -1.0
var _interpolation_delay := 0.1
var _input_redundancy := 3
var _snapshots_received := 0
## The click that captures the mouse mustn't also attack: wait for a release first.
var _attack_blocked := true
var _hits_landed := 0
var _hits_taken := 0
var _bot := false
var _bot_last_phase := 0.0
var _verbose := false
var _log_timer := 0.0
var _last_screenshot_slot := -1

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
		Player.show_hitboxes = LaunchArgs.has_flag("hitboxes")
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
	_maybe_save_screenshot()
	if _verbose:
		_log_timer += delta
		if _log_timer >= 2.0:
			_log_timer = 0.0
			print(_describe_players())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_hitboxes"):
		Player.show_hitboxes = not Player.show_hitboxes


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
		states.append(player.get_snapshot())
	for peer_id in _connected_player_ids():
		_receive_snapshot.rpc_id(peer_id, _tick, states)


## Peers with a player in the world. A peer can be mid-disconnect for a moment
## before peer_left fires, so check the connection too.
func _connected_player_ids() -> Array[int]:
	var connected := multiplayer.get_peers()
	var ids: Array[int] = []
	for player: Player in _players.get_children():
		if player.peer_id in connected:
			ids.append(player.peer_id)
	return ids


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
	player.attack_stepped.connect(_on_attack_stepped)
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


## Server: the attacker's hitbox is live this step. Each target can be hit once
## per attack; a target in i-frames evades but can still be hit later in the
## same active window if its i-frames run out first.
func _on_attack_stepped(attacker: Player) -> void:
	var attack := attacker.state.current_attack(attacker.params)
	for target: Player in _players.get_children():
		if target == attacker or attacker.attack_results.get(target.peer_id, false):
			continue
		if not MeleeHitbox.hits(attacker.global_position, attacker.state.yaw, attack,
				target.global_position, Player.BODY_RADIUS, Player.BODY_HEIGHT):
			continue
		if target.state.is_invulnerable(target.params):
			if not attacker.attack_results.has(target.peer_id):
				attacker.attack_results[target.peer_id] = false
				_send_hit(attacker, target, 0.0, HIT_EVADED)
			continue
		attacker.attack_results[target.peer_id] = true
		target.health -= attack.damage
		var result := HIT_DAMAGED
		if target.health <= 0.0:
			result = HIT_DEFEATED
			# Placeholder until death and respawn exist: refill and keep fighting.
			target.health = target.params.max_health
		_hits += 1
		_send_hit(attacker, target, attack.damage, result)


func _send_hit(attacker: Player, target: Player, damage: float, result: int) -> void:
	if _verbose:
		print("[server] %d -> %d: %s %d" % [attacker.peer_id, target.peer_id,
				["hit", "evaded", "defeated"][result], damage])
	for peer_id in _connected_player_ids():
		_receive_hit.rpc_id(peer_id, attacker.peer_id, target.peer_id, damage, result)


# --- Client ---

func _client_tick(delta: float) -> void:
	var move := Vector2.ZERO
	var buttons := 0
	var aim_yaw := _local_player.get_camera_yaw()
	if _bot:
		var bot := _bot_input()
		move = bot[0]
		buttons = bot[1]
		aim_yaw = bot[2]
	else:
		move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		if Input.is_action_pressed(&"jump"):
			buttons |= PlayerState.BUTTON_JUMP
		if Input.is_action_just_pressed(&"dodge"):
			buttons |= PlayerState.BUTTON_DODGE
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		var attack_pressed := Input.is_action_pressed(&"attack")
		if not captured or not attack_pressed:
			_attack_blocked = not captured
		if captured and attack_pressed and not _attack_blocked:
			buttons |= PlayerState.BUTTON_ATTACK
	var inputs := _local_player.client_predict(move, buttons, aim_yaw, delta, _input_redundancy)
	_submit_inputs.rpc_id(1, inputs)


## Bot input for testing without a second person. Repeats every 6 s:
## 0–3.5 s: walk to the nearest player. When in reach (until 2.8 s), tap light
## attacks every 0.4 s, except hold a heavy from 2.0 to 2.5.
## 3.5–6 s: walk in circles; jump at 3.5, air dodge at 3.65, ground dodge at 5.0.
## Fighting comes first because players spawn close together.
## Returns [move, buttons, aim_yaw].
func _bot_input() -> Array:
	var t := Time.get_ticks_msec() / 1000.0
	var phase := fmod(t, 6.0)
	var crossed := func(at: float) -> bool: return _bot_last_phase < at and phase >= at
	var move := Vector2.ZERO
	var buttons := 0
	var aim_yaw := 0.0
	if phase >= 3.5:
		var circle_t := t + float(multiplayer.get_unique_id() % 100)
		move = Vector2(cos(circle_t * 0.8), sin(circle_t * 0.8))
		if phase < 3.55:
			buttons |= PlayerState.BUTTON_JUMP
		if crossed.call(3.65) or crossed.call(5.0):
			buttons |= PlayerState.BUTTON_DODGE
	else:
		var target := _nearest_remote_player()
		var in_reach := false
		if target:
			var to := target.global_position - _local_player.global_position
			var flat := Vector2(to.x, to.z)
			aim_yaw = PlayerState.yaw_for_direction(flat)
			in_reach = flat.length() <= BOT_ATTACK_DISTANCE + 0.4
			if flat.length() > BOT_ATTACK_DISTANCE:
				move = flat.normalized()
		# Stop swinging by 2.8 s so the last attack is over before the 3.5 s jump.
		if in_reach and phase < 2.8:
			if phase >= 2.0 and phase < 2.5:
				buttons |= PlayerState.BUTTON_ATTACK
			elif fmod(phase, 0.4) < fmod(_bot_last_phase, 0.4):
				buttons |= PlayerState.BUTTON_ATTACK
	_bot_last_phase = phase
	return [move, buttons, aim_yaw]


func _nearest_remote_player() -> Player:
	var nearest: Player
	var best := INF
	for player: Player in _players.get_children():
		if player.is_local:
			continue
		var distance := player.global_position.distance_to(_local_player.global_position)
		if distance < best:
			best = distance
			nearest = player
	return nearest


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
			player.client_receive_ack(state[1], state[2], state[3], state[4])
		else:
			player.push_snapshot(server_time, state[1], state[4])
		player.set_health(state[5])
	for player: Player in _players.get_children():
		if not seen.has(player.peer_id):
			print("[client] peer %d left" % player.peer_id)
			_players.remove_child(player)
			player.queue_free()


@rpc("authority", "call_remote", "reliable")
func _receive_hit(attacker_id: int, target_id: int, damage: float, result: int) -> void:
	var my_id := multiplayer.get_unique_id()
	if result != HIT_EVADED:
		if attacker_id == my_id:
			_hits_landed += 1
		if target_id == my_id:
			_hits_taken += 1
	var target := _players.get_node_or_null(str(target_id)) as Player
	if target:
		target.show_hit(damage, result)


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
		"Hits landed: %d   Hits taken: %d   F3: hitboxes %s" % [
				_hits_landed, _hits_taken, "on" if Player.show_hitboxes else "off"],
	])
	if _bot:
		lines.append("BOT MODE")
	_hud.set_info("\n".join(lines))
	if _local_player:
		_hud.set_health(_local_player.health, _local_player.params.max_health)
		_hud.set_stamina(_local_player.state.stamina, _local_player.params.max_stamina)


## Debug: with --screenshot-dir=PATH, saves this game window's image every 0.25 s
## (game pixels only, not the desktop), for checking visuals without a person.
func _maybe_save_screenshot() -> void:
	var dir := LaunchArgs.get_value("screenshot-dir")
	if dir.is_empty() or _local_player == null:
		return
	var slot := Time.get_ticks_msec() / 250
	if slot == _last_screenshot_slot:
		return
	_last_screenshot_slot = slot
	var image := get_viewport().get_texture().get_image()
	image.save_png(dir.path_join("frame_%04d.png" % slot))


func _describe_players() -> String:
	var parts := PackedStringArray()
	for player: Player in _players.get_children():
		var p := player.global_position
		parts.append("%s%d@(%.1f, %.1f)" % ["*" if player.is_local else "", player.peer_id, p.x, p.z])
	return "[client %d] %s" % [multiplayer.get_unique_id(), "  ".join(parts)]


## Printed when the process exits via --quit-after; used by tools/smoke_test.ps1.
func print_summary() -> void:
	if multiplayer.is_server():
		print("SUMMARY server players=%d ticks=%d hits=%d" % [
				_players.get_child_count(), _tick, _hits])
		return
	if _local_player:
		print("SUMMARY client=%d snapshots=%d corrections=%d dodges=%d air_dodges=%d attacks=%d hits_landed=%d" % [
				multiplayer.get_unique_id(), _snapshots_received, _local_player.corrections,
				_local_player.dodges, _local_player.air_dodges, _local_player.attacks, _hits_landed])
	for player: Player in _players.get_children():
		if not player.is_local:
			print("SUMMARY client=%d remote=%d moved=%.1f" % [
					multiplayer.get_unique_id(), player.peer_id, player.distance_seen])
