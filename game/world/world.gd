class_name World
extends Node3D
## The shared game world, at /root/Main/World on the server and every client.
##
## Server: spawns a player when a client says it's ready, simulates players from
## their inputs every physics tick, runs enemies (one per marker under
## EnemySpawns), resolves melee hits and sends snapshots of everyone.
## Client: sends its inputs every tick, predicts its own player, draws other
## players and enemies interpolated between snapshots, and shows hits the server
## reports.
## Builds (class, weapons, mastery) live in the BuildService child "Builds".

## Results sent with each hit event.
const HIT_DAMAGED := 0
const HIT_EVADED := 1
const HIT_DEFEATED := 2
const HIT_BLOCKED := 3
const HIT_GUARD_BROKEN := 4
## Negated by the target's parry (Riposte), which answers with a counter.
const HIT_PARRIED := 5
const HIT_NAMES := ["hit", "evaded", "defeated", "blocked", "guard broken", "parried"]

const PLAYER_SCENE := preload("res://game/player/player.tscn")
const ENEMY_SCENE := preload("res://game/enemy/enemy.tscn")
const HUD_SCENE := preload("res://ui/hud.tscn")
## Inputs per packet the server accepts; anything larger is dropped as malformed.
const MAX_INPUTS_PER_PACKET := 8
const SPAWN_RADIUS := 3.0
## Bot fight phase: walk to this distance from the target before swinging.
const BOT_ATTACK_DISTANCE := 1.6
## The bot fights enemies within this many meters rather than other players.
const BOT_ENEMY_RANGE := 15.0

# Server
var _tick := 0
var _snapshot_interval := 3
var _max_input_buffer := 8
var _max_inputs_per_tick := 2
var _hits := 0
var _deaths := 0
var _respawns := 0
var _blocks := 0
var _guard_breaks := 0
## Enemy swings that connected with a player (including blocked ones).
var _enemy_hits := 0
## Player hits on enemies.
var _enemy_damaged := 0
var _enemy_kills := 0
var _ability_uses := 0
## Ability hits that connected with a player or enemy (including blocked/parried).
var _ability_hits := 0
var _parries := 0
var _swaps := 0

# Client
var _hud: Hud
var _local_player: Player
var _render_time := -1.0
var _interpolation_delay := 0.1
var _input_redundancy := 3
var _snapshots_received := 0
## Remote players that left: peer id -> meters seen moving (for the summary,
## since the other bot can quit a moment before this one prints it).
var _departed_seen := {}
## The click that captures the mouse mustn't also attack: after capturing, the
## attack button has to be released once before it counts.
var _attack_blocked := true
var _hits_landed := 0
var _hits_taken := 0
## Local time (msec) when the local player respawns, or -1 when alive.
var _respawn_at_msec := -1
var _bot := false
var _bot_last_phase := 0.0
var _bot_swaps_before := 0
var _verbose := false
var _log_timer := 0.0
var _last_screenshot_slot := -1
var _mastery_panel: MasteryPanel

@onready var _players: Node3D = $Players
@onready var _enemies: Node3D = $Enemies
var _builds: BuildService


func _ready() -> void:
	_verbose = LaunchArgs.has_flag("verbose")
	_builds = BuildService.new()
	_builds.name = "Builds"
	add_child(_builds)
	if multiplayer.is_server():
		var snapshot_rate: int = Tuning.get_value("network", "server", "snapshot_rate")
		_snapshot_interval = maxi(1, roundi(Engine.physics_ticks_per_second / float(snapshot_rate)))
		_max_input_buffer = Tuning.get_value("network", "server", "max_input_buffer")
		_max_inputs_per_tick = Tuning.get_value("network", "server", "max_inputs_per_tick")
		Net.peer_left.connect(_on_peer_left)
		_spawn_enemies()
	else:
		_interpolation_delay = Tuning.get_value("network", "client", "interpolation_delay")
		_input_redundancy = Tuning.get_value("network", "client", "input_redundancy")
		_bot = LaunchArgs.has_flag("bot")
		Player.show_hitboxes = LaunchArgs.has_flag("hitboxes")
		_hud = HUD_SCENE.instantiate()
		add_child(_hud)
		_mastery_panel = MasteryPanel.new()
		_hud.add_child(_mastery_panel)
		_mastery_panel.setup(_builds)
		if LaunchArgs.has_flag("mastery-panel"):
			_mastery_panel.toggle()  # for checking the panel from --screenshot-dir frames
		_client_ready.rpc_id(1, LaunchArgs.get_value("class", ClassDef.DEFAULT_CLASS))


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
		for enemy: Enemy in _enemies.get_children():
			enemy.interpolate(_render_time)
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
	elif event.is_action_pressed(&"toggle_mastery") and _mastery_panel:
		_mastery_panel.toggle()


# --- Server ---

func _server_tick(delta: float) -> void:
	_tick += 1
	for player: Player in _players.get_children():
		if player.state.dead and _tick >= player.respawn_at_tick:
			_respawn(player)
		player.server_process_inputs(_max_inputs_per_tick, delta)
	var targets := {}
	for player: Player in _players.get_children():
		if not player.state.dead:
			targets[player.peer_id] = player.global_position
	for enemy: Enemy in _enemies.get_children():
		if enemy.dead:
			if _tick >= enemy.respawn_at_tick:
				enemy.respawn()
				if _verbose:
					print("[server] enemy %d respawned" % enemy.enemy_id)
		else:
			enemy.server_step(targets, delta)
	if _tick % _snapshot_interval == 0:
		_broadcast_snapshot()


func _broadcast_snapshot() -> void:
	var states: Array = []
	for player: Player in _players.get_children():
		states.append(player.get_snapshot())
	var enemy_states: Array = []
	for enemy: Enemy in _enemies.get_children():
		enemy_states.append(enemy.get_snapshot())
	for peer_id in _connected_player_ids():
		_receive_snapshot.rpc_id(peer_id, _tick, states, enemy_states)


## Peers with a player in the world. A peer can be mid-disconnect for a moment
## before peer_left fires, so check the connection too.
func _connected_player_ids() -> Array[int]:
	var connected := multiplayer.get_peers()
	var ids: Array[int] = []
	for player: Player in _players.get_children():
		if player.peer_id in connected:
			ids.append(player.peer_id)
	return ids


## class_id: the character's class (--class=, see ClassDef).
@rpc("any_peer", "call_remote", "reliable")
func _client_ready(class_id: String) -> void:
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
	player.ability_started.connect(_on_ability_started)
	player.weapon_swapped.connect(func(_p: Player) -> void: _swaps += 1)
	_builds.setup_player(player, class_id)
	_players.add_child(player)
	_builds.send_build(player)
	print("[server] peer %d joined as %s (%d players)" % [
			peer_id, player.build.class_def.id, _players.get_child_count()])


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


## Server: a player's hitbox (attack or ability) is live this step. It can hit
## other players and enemies, each at most once per hit window, and at most
## attack.max_targets in total (then the attack skips to its recovery, e.g.
## Shield Charge stops at the first target).
func _on_attack_stepped(attacker: Player) -> void:
	var attack := attacker.state.current_attack(attacker.params)
	var damage_scale := attacker.damage_multiplier(attack)
	var connected := 0
	for target: Player in _players.get_children():
		if target == attacker or _target_limit_reached(attacker, attack):
			continue
		var result := _strike_player(attacker.peer_id, attacker.global_position,
				attacker.state.yaw, attack, attacker.attack_results, target, damage_scale)
		if result >= 0 and result != HIT_EVADED:
			connected += 1
	for enemy: Enemy in _enemies.get_children():
		if enemy.dead or attacker.attack_results.has(enemy.enemy_id):
			continue
		if _target_limit_reached(attacker, attack):
			break
		if not MeleeHitbox.hits(attacker.global_position, attacker.state.yaw, attack,
				enemy.global_position, Enemy.BODY_RADIUS, Enemy.BODY_HEIGHT):
			continue
		attacker.attack_results[enemy.enemy_id] = true
		var damage := attack.damage * damage_scale
		var killed := enemy.take_hit(damage, attack.stagger_ticks, attacker.peer_id)
		_enemy_damaged += 1
		connected += 1
		if killed:
			enemy.respawn_at_tick = _tick + enemy.params.respawn_ticks
			_enemy_kills += 1
		_send_hit(attacker.peer_id, enemy.enemy_id, damage,
				HIT_DEFEATED if killed else HIT_DAMAGED)
	if connected > 0:
		_on_player_attack_connected(attacker, attack, connected)


func _on_ability_started(player: Player) -> void:
	_ability_uses += 1
	if _verbose:
		print("[server] peer %d uses %s" % [player.peer_id,
				player.state.current_ability(player.params).id])


## Server: a player's attack or ability connected with `count` targets this step.
func _on_player_attack_connected(attacker: Player, attack: AttackParams, count: int) -> void:
	if attacker.state.is_using_ability():
		_ability_hits += count
	if _target_limit_reached(attacker, attack):
		attacker.state.end_active_window(attacker.params)


## True once an attack with max_targets has connected with that many targets.
func _target_limit_reached(attacker: Player, attack: AttackParams) -> bool:
	if attack.max_targets <= 0:
		return false
	var connected := 0
	for hit: bool in attacker.attack_results.values():
		if hit:
			connected += 1
	return connected >= attack.max_targets


## Server: an enemy's swing is live this tick.
func _on_enemy_attack_stepped(enemy: Enemy) -> void:
	for target: Player in _players.get_children():
		var result := _strike_player(enemy.enemy_id, enemy.global_position, enemy.brain.yaw,
				enemy.params.attack, enemy.attack_results, target)
		if result >= 0 and result != HIT_EVADED:
			_enemy_hits += 1


## Server: resolves one attack against one player, at most once per hit window
## (`results`, keyed by target id). A player in i-frames evades but can still be
## hit later in the same active window if their i-frames run out first. A
## parrying player (Riposte) facing the attacker negates it and counters. A
## blocking player facing the attacker takes stamina damage instead.
## damage_scale: the attacker's damage modifiers. Returns the HIT_* result, or
## -1 if the attack didn't connect (or already did).
func _strike_player(attacker_id: int, attacker_pos: Vector3, attacker_yaw: float,
		attack: AttackParams, results: Dictionary[int, bool], target: Player,
		damage_scale: float = 1.0) -> int:
	if target.state.dead or results.get(target.peer_id, false):
		return -1
	if not MeleeHitbox.hits(attacker_pos, attacker_yaw, attack, target.global_position,
			Player.BODY_RADIUS, Player.BODY_HEIGHT):
		return -1
	if target.state.is_invulnerable(target.params):
		if results.has(target.peer_id):
			return -1
		results[target.peer_id] = false
		_send_hit(attacker_id, target.peer_id, 0.0, HIT_EVADED)
		return HIT_EVADED
	results[target.peer_id] = true
	if _try_parry(attacker_id, attacker_pos, target):
		return HIT_PARRIED
	var damage := attack.damage * damage_scale
	var result := HIT_DAMAGED
	if target.state.blocking and MeleeHitbox.is_in_front(target.global_position,
			target.state.yaw, attacker_pos, target.params.block_arc):
		var broke := target.state.take_blocked_hit(attack, target.params,
				target.block_stamina_multiplier())
		damage *= target.params.block_damage_taken
		result = HIT_GUARD_BROKEN if broke else HIT_BLOCKED
		if broke:
			_guard_breaks += 1
		else:
			_blocks += 1
	target.health = maxf(0.0, target.health - damage)
	if target.health <= 0.0:
		result = HIT_DEFEATED
		target.state.kill()
		target.respawn_at_tick = _tick + target.params.respawn_ticks
		_deaths += 1
	elif result == HIT_DAMAGED:
		target.state.apply_stagger(attack.stagger_ticks)
	_hits += 1
	_send_hit(attacker_id, target.peer_id, damage, result)
	return result


## Server: if the target is in a parry window (Riposte) and the attacker is in
## front of it, the hit is negated and the target starts its counter strike,
## turned toward the attacker. Returns true if parried.
func _try_parry(attacker_id: int, attacker_pos: Vector3, target: Player) -> bool:
	if not target.state.is_parrying(target.params):
		return false
	var parry := target.state.current_ability(target.params)
	if not MeleeHitbox.is_in_front(target.global_position, target.state.yaw, attacker_pos,
			parry.parry_arc):
		return false
	var to_attacker := Vector2(attacker_pos.x - target.global_position.x,
			attacker_pos.z - target.global_position.z)
	var face := target.state.yaw
	if not to_attacker.is_zero_approx():
		face = PlayerState.yaw_for_direction(to_attacker)
	target.state.start_counter(target.params, face)
	_parries += 1
	_send_hit(attacker_id, target.peer_id, 0.0, HIT_PARRIED)
	return true


func _spawn_enemies() -> void:
	var next_id := -1
	for marker: Marker3D in $EnemySpawns.get_children():
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		enemy.enemy_id = next_id
		enemy.name = str(next_id)
		enemy.kind = marker.get_meta("kind", "husk")
		enemy.home = marker.position
		enemy.position = marker.position
		enemy.attack_stepped.connect(_on_enemy_attack_stepped)
		_enemies.add_child(enemy)
		next_id -= 1


## Server: brings a dead player back at a random spawn point with full health.
## The point must be exactly on the ground: the body's on-floor flag isn't synced,
## so a mid-air teleport makes the client's prediction disagree for a tick.
func _respawn(player: Player) -> void:
	var angle := randf() * TAU
	player.global_position = Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS
	player.velocity = Vector3.ZERO
	player.health = player.params.max_health
	player.state.revive(player.params)
	player.respawn_at_tick = -1
	_respawns += 1
	print("[server] peer %d respawned" % player.peer_id)


## Ids are peer ids for players and negative ids for enemies.
func _send_hit(attacker_id: int, target_id: int, damage: float, result: int) -> void:
	if _verbose:
		print("[server] %d -> %d: %s %d" % [attacker_id, target_id, HIT_NAMES[result], damage])
	for peer_id in _connected_player_ids():
		_receive_hit.rpc_id(peer_id, attacker_id, target_id, damage, result)


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
		buttons |= _ability_and_swap_buttons()
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		var attack_held := Input.is_action_pressed(&"attack")
		if not captured or not attack_held:
			_attack_blocked = not captured
		if captured and attack_held and not _attack_blocked:
			buttons |= PlayerState.BUTTON_ATTACK
		if captured and Input.is_action_pressed(&"block"):
			buttons |= PlayerState.BUTTON_BLOCK
	var inputs := _local_player.client_predict(move, buttons, aim_yaw, delta, _input_redundancy)
	_submit_inputs.rpc_id(1, inputs)


## Keys for this tick: Q / E / R (abilities) and X (weapon swap), sent only on
## the tick they're pressed.
func _ability_and_swap_buttons() -> int:
	var buttons := 0
	if Input.is_action_just_pressed(&"swap_weapon"):
		buttons |= PlayerState.BUTTON_SWAP
	for slot in PlayerState.ABILITY_SLOTS:
		if Input.is_action_just_pressed(StringName("ability_%d" % (slot + 1))):
			buttons |= PlayerState.BUTTON_ABILITY_1 << slot
	return buttons


## Bot input for testing without a second person. Repeats every 8 s:
## 0–4 s: fight. The target is the nearest living enemy within BOT_ENEMY_RANGE,
## or else the nearest other player. The fight has two 2 s turns; the bot with
## the lower peer id (compared with the nearest other player) attacks in the
## first, the other in the second. On its turn a bot holds for a heavy, then taps
## two lights; off its turn it holds block.
## 4–6 s: abilities, same target. Both bots hold block and each presses two
## different ability slots, 1 s apart: the first bot at 4.0 and 5.0, the other
## at 4.5 and 5.5.
## 6–8 s: walk in circles; swap weapons at 6.95 (after any ability; again at
## 7.2 if that press didn't swap), jump at
## 7.25, air dodge at 7.4, ground dodge at 7.95, and a free respec at 7.6
## (BuildService.bot_respec).
## Fighting comes first because players spawn close together.
## Returns [move, buttons, aim_yaw].
func _bot_input() -> Array:
	var t := Time.get_ticks_msec() / 1000.0
	var phase := fmod(t, 8.0)
	var cycle := floori(t / 8.0)
	var crossed := func(at: float) -> bool: return _bot_last_phase < at and phase >= at
	var move := Vector2.ZERO
	var buttons := 0
	var aim_yaw := 0.0
	if phase >= 6.0:
		var circle_t := t + float(multiplayer.get_unique_id() % 100)
		move = Vector2(cos(circle_t * 0.8), sin(circle_t * 0.8))
		if crossed.call(6.95):
			buttons |= PlayerState.BUTTON_SWAP
			_bot_swaps_before = _local_player.swaps
		elif crossed.call(7.2) and _local_player.swaps == _bot_swaps_before:
			buttons |= PlayerState.BUTTON_SWAP  # the first press didn't swap (e.g. staggered)
		if phase >= 7.25 and phase < 7.3:
			buttons |= PlayerState.BUTTON_JUMP
		if crossed.call(7.4) or crossed.call(7.95):
			buttons |= PlayerState.BUTTON_DODGE
		if crossed.call(7.6):
			_builds.bot_respec(_local_player.state.weapon_id(), cycle)
	else:
		var other_player := _nearest_remote_player()
		var target: Node3D = _nearest_enemy(BOT_ENEMY_RANGE)
		if target == null:
			target = other_player
		if target:
			var to := target.global_position - _local_player.global_position
			var flat := Vector2(to.x, to.z)
			aim_yaw = PlayerState.yaw_for_direction(flat)
			if flat.length() > BOT_ATTACK_DISTANCE:
				move = flat.normalized()
			var first_turn := other_player == null or multiplayer.get_unique_id() < other_player.peer_id
			var turn_start := 0.0 if first_turn else 2.0
			var turn_time := phase - turn_start
			if phase >= 4.0:
				# Abilities: guard up between them (an ability drops it, holding block
				# brings it back), alternating with the other bot every 0.5 s.
				buttons |= PlayerState.BUTTON_BLOCK
				var offset := 0.0 if first_turn else 0.5
				if crossed.call(4.0 + offset):
					buttons |= _bot_ability_button(cycle * 2)
				elif crossed.call(5.0 + offset):
					buttons |= _bot_ability_button(cycle * 2 + 1)
			elif turn_time < 0.0 or turn_time >= 2.0:
				# Guard up for the whole off turn: other players are drawn ~0.1 s in
				# the past, too late to react to a light attack's windup.
				buttons |= PlayerState.BUTTON_BLOCK
			elif turn_time < 0.3:
				buttons |= PlayerState.BUTTON_ATTACK  # held 0.3 s: heavy
			elif crossed.call(turn_start + 1.35) or crossed.call(turn_start + 1.75):
				buttons |= PlayerState.BUTTON_ATTACK  # one tick: light on release
	_bot_last_phase = phase
	return [move, buttons, aim_yaw]


## One of the equipped weapon's filled ability slots, rotating with `turn`
## (offset by peer id so two bots differ).
func _bot_ability_button(turn: int) -> int:
	var filled: Array[int] = []
	for slot in PlayerState.ABILITY_SLOTS:
		if _local_player.state.slot_ability(slot) >= 0:
			filled.append(slot)
	if filled.is_empty():
		return 0
	var slot := filled[(turn + multiplayer.get_unique_id()) % filled.size()]
	return PlayerState.BUTTON_ABILITY_1 << slot


func _nearest_enemy(max_distance: float) -> Enemy:
	var nearest: Enemy
	var best := max_distance
	for enemy: Enemy in _enemies.get_children():
		var distance := enemy.global_position.distance_to(_local_player.global_position)
		if not enemy.dead and distance < best:
			best = distance
			nearest = enemy
	return nearest


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
func _receive_snapshot(tick: int, states: Array, enemy_states: Array) -> void:
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
			_departed_seen[player.peer_id] = player.distance_seen
			_players.remove_child(player)
			player.queue_free()
	_receive_enemy_states(server_time, enemy_states)


## Enemy snapshot entries: Enemy.get_snapshot().
func _receive_enemy_states(server_time: float, enemy_states: Array) -> void:
	var seen := {}
	for state: Array in enemy_states:
		var enemy_id: int = state[0]
		seen[enemy_id] = true
		var enemy := _enemies.get_node_or_null(str(enemy_id)) as Enemy
		if enemy == null:
			enemy = ENEMY_SCENE.instantiate()
			enemy.enemy_id = enemy_id
			enemy.name = str(enemy_id)
			enemy.kind = state[1]
			enemy.position = state[2]
			_enemies.add_child(enemy)
		enemy.push_snapshot(server_time, state[2], state[3], state[4], state[5], state[7])
		enemy.set_health(state[6])
	for enemy: Enemy in _enemies.get_children():
		if not seen.has(enemy.enemy_id):
			_enemies.remove_child(enemy)
			enemy.queue_free()


@rpc("authority", "call_remote", "reliable")
func _receive_hit(attacker_id: int, target_id: int, damage: float, result: int) -> void:
	var my_id := multiplayer.get_unique_id()
	if result in [HIT_DAMAGED, HIT_DEFEATED, HIT_GUARD_BROKEN]:
		if attacker_id == my_id:
			_hits_landed += 1
		if target_id == my_id:
			_hits_taken += 1
			if result == HIT_DEFEATED and _local_player:
				var respawn_seconds := _local_player.params.respawn_ticks / float(Engine.physics_ticks_per_second)
				_respawn_at_msec = Time.get_ticks_msec() + roundi(respawn_seconds * 1000.0)
	var container := _enemies if target_id < 0 else _players
	var target := container.get_node_or_null(str(target_id))
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
		var banner := ""
		if _local_player.state.dead:
			var seconds_left := maxi(0, ceili((_respawn_at_msec - Time.get_ticks_msec()) / 1000.0))
			banner = "Defeated\nRespawning in %d" % seconds_left
		_hud.set_banner(banner)
		_update_loadout_hud()


## The ability bar and weapon line, from the local player's predicted state.
func _update_loadout_hud() -> void:
	var state := _local_player.state
	var params := _local_player.params
	var weapon := state.weapon(params)
	var other := ""
	if state.weapons.size() >= PlayerState.WEAPON_SLOTS:
		other = params.weapon(state.weapons[1 - state.equipped]).display_name
	_hud.set_weapons(weapon.display_name, other, state.is_swapping())
	var tps := float(Engine.physics_ticks_per_second)
	for slot in PlayerState.ABILITY_SLOTS:
		var ability := weapon.ability(state.slot_ability(slot))
		if ability == null:
			_hud.set_ability(slot, "", 0.0, 0.0)
			continue
		var left := state.cooldown_left(state.slot_ability(slot))
		_hud.set_ability(slot, ability.display_name,
				left / float(maxi(1, ability.cooldown_ticks)), left / tps)


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
		print("SUMMARY server players=%d ticks=%d hits=%d deaths=%d respawns=%d blocks=%d guard_breaks=%d" % [
				_players.get_child_count(), _tick, _hits, _deaths, _respawns, _blocks, _guard_breaks])
		print("SUMMARY enemies count=%d enemy_hits=%d enemy_damaged=%d enemy_kills=%d" % [
				_enemies.get_child_count(), _enemy_hits, _enemy_damaged, _enemy_kills])
		print("SUMMARY abilities uses=%d ability_hits=%d parries=%d swaps=%d builds=%d builds_refused=%d" % [
				_ability_uses, _ability_hits, _parries, _swaps, _builds.accepted, _builds.rejected])
		return
	if _local_player:
		print("SUMMARY client=%d snapshots=%d corrections=%d dodges=%d air_dodges=%d attacks=%d hits_landed=%d abilities=%d swaps=%d" % [
				multiplayer.get_unique_id(), _snapshots_received, _local_player.corrections,
				_local_player.dodges, _local_player.air_dodges, _local_player.attacks, _hits_landed,
				_local_player.abilities_used, _local_player.swaps])
	var seen := _departed_seen.duplicate()
	for player: Player in _players.get_children():
		if not player.is_local:
			seen[player.peer_id] = player.distance_seen
	for peer_id: int in seen:
		print("SUMMARY client=%d remote=%d moved=%.1f" % [
				multiplayer.get_unique_id(), peer_id, seen[peer_id]])
