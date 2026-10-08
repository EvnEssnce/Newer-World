class_name ProjectileSystem
extends Node3D
## Projectiles over the network (the PROJ tag). World adds one at
## World/Projectiles on the server and on every client (RPCs are matched by node
## path). Projectiles are server state, never in snapshots (they'd blow the
## packet size): the server sends reliable events instead and clients fly a copy
## with the same math (Projectile).
##
## Server: Player.projectile_released (the firing attack reached its
## projectile_tick, in the predicted timeline) → server_fire throws them from
## the thrower's server position and facing. server_step flies every one once
## per tick, after the players and enemies: walls by a ray against layer 1,
## targets by sweeping the step's segment against player and enemy capsules
## (Projectile.sweep_capsule), nearest first. Hits go through World's melee
## rules (World.resolve_strike / strike_enemy): allies are ignored and it flies
## on, i-frames evade (it flies on, and can still hit them later on that leg), a
## guard or a Riposte facing where it came from blocks or parries it (stopping
## it if stopped_by_guard), statuses and force on HIT_DAMAGED, Ember as usual.
## Each target is hit once per projectile (once per leg for a boomerang).
## Events to clients: _receive_spawn(id, kind, owner, origin, velocity, tick) and
## _receive_event(id, type, age, position): TURN (a returning one turned back,
## from its timer, a wall or its pierce) or END_* (where it stopped).
##
## Clients: one copy per projectile. Other players' (and unmatched) ones run on
## the render clock, like remote players: age = render tick - spawn tick, so
## they leave the thrower's drawn hand (drawn interpolation_delay in the past)
## and events are applied at the age they happened. The local player's own
## throws appear at once from its prediction (client_fire, a cosmetic copy on
## its own clock); the server's spawn then confirms the oldest unconfirmed copy
## of that kind, whose later events apply as soon as they arrive. A returning
## copy steers toward where this client draws the thrower: hits are server-only,
## so a small difference in the return path is harmless.

const EVENT_TURN := 0  # otherwise an event's type is a Projectile.END_* reason
## Ticks an unconfirmed cosmetic copy waits for the server's spawn.
const UNCONFIRMED_TICKS := 30
## Meters back along a projectile's path that a guard, parry or knockback
## treats as where it came from.
const SOURCE_BACKOFF := 2.0

## World/Players and World/Enemies, and World itself. Set by World before
## adding this node.
var world: World
var players: Node3D
var enemies: Node3D

# Server
var _next_id := 1
var _active: Array[Projectile] = []
var _fired := 0
var _hits_players := 0
var _hits_enemies := 0
var _ally_hits := 0
var _ally_ignored := 0
var _ended := {}  # Projectile.END_* -> count
# Client
var _flying: Array[Flying] = []
var _by_id: Dictionary[int, Flying] = {}
var _spawns_seen := 0
var _cosmetic_fired := 0


## A client's copy of one projectile.
class Flying:
	var flight: Projectile
	var visual: ProjectileVisual
	## Server tick it was thrown (render-clock copies).
	var spawn_tick := 0
	## The local player's own throw: one step per physics tick from its release.
	var local_clock := false
	## The server's spawn arrived (has an id).
	var confirmed := true
	## [age, type, position], applied once the copy has flown that far.
	var events: Array[Array] = []
	var end_age := -1
	var end_position := Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		_client_step(delta)


# --- Server ---

## Server: `player`'s current attack just reached its release tick: throws its
## projectiles from its server position and facing.
func server_fire(player: Player) -> void:
	var attack := player.state.current_attack(player.params)
	var p := ProjectileParams.get_kind(attack.projectile) if attack else null
	if p == null:
		return
	var scale := (player.damage_multiplier(attack)
			* player.state.statuses.damage_dealt_multiplier(player.params.statuses))
	var yaw := player.state.yaw
	var from := Projectile.release_point(p, player.global_position, yaw)
	for i in attack.projectile_count:
		var proj := Projectile.new(p, from, Projectile.launch_velocity_for(p, yaw,
				spread_offset(i, attack.projectile_count, attack.projectile_spread)))
		proj.id = _next_id
		_next_id += 1
		proj.owner_id = player.peer_id
		proj.attack = attack
		proj.damage_scale = scale
		_active.append(proj)
		_fired += 1
		for peer_id in world._connected_player_ids():
			_receive_spawn.rpc_id(peer_id, proj.id, p.id, proj.owner_id, from, proj.velocity,
					world.server_tick())
		if world.is_verbose():
			print("[server] peer %d throws %s #%d" % [player.peer_id, p.id, proj.id])


## Yaw offset of projectile i of count, fanned evenly over spread radians.
static func spread_offset(i: int, count: int, spread: float) -> float:
	if count <= 1:
		return 0.0
	return lerpf(-spread / 2.0, spread / 2.0, float(i) / (count - 1))


## Server: flies every projectile one tick and resolves what it hit.
func server_step(delta: float) -> void:
	for proj: Projectile in _active.duplicate():
		var was_returning := proj.returning
		proj.step(delta, _return_target(proj.owner_id, proj))
		_collide(proj)
		if proj.returning != was_returning:
			_send_event(proj, EVENT_TURN)
		if proj.ended != Projectile.END_NONE:
			_send_event(proj, proj.ended)
			_ended[proj.ended] = _ended.get(proj.ended, 0) + 1
			_active.erase(proj)


## Where a returning projectile steers: its thrower's hands, or where it was
## thrown from if the thrower is gone or dead.
func _return_target(owner_id: int, proj: Projectile) -> Vector3:
	var thrower := players.get_node_or_null(str(owner_id)) as Player
	if thrower == null:
		return proj.origin
	var dead := thrower.state.dead if (multiplayer.is_server() or thrower.is_local) else thrower.view_state.dead
	if dead:
		return proj.origin
	return thrower.global_position + Vector3.UP * proj.params.release_height


## Server: this step's segment against the world and every target, nearest
## first, until the projectile stops or turns back.
func _collide(proj: Projectile) -> void:
	var a := proj.prev_position
	var b := proj.position
	var leg_returning := proj.returning
	var limit := 1.0
	var wall_point := b
	if proj.params.walls and not proj.returning and not a.is_equal_approx(b):
		var query := PhysicsRayQueryParameters3D.create(a, b, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			wall_point = hit.position
			limit = a.distance_to(wall_point) / a.distance_to(b)
	var candidates: Array[Array] = []  # [fraction, Player or Enemy]
	var radius := proj.params.hit_radius
	for target: Player in players.get_children():
		if target.peer_id == proj.owner_id or target.state.dead or not proj.can_hit(target.peer_id):
			continue
		var s := Projectile.sweep_capsule(a, b, radius, target.global_position,
				Player.BODY_RADIUS, Player.BODY_HEIGHT)
		if s >= 0.0 and s <= limit:
			candidates.append([s, target])
	for enemy: Enemy in enemies.get_children():
		if enemy.dead or not proj.can_hit(enemy.enemy_id):
			continue
		var s := Projectile.sweep_capsule(a, b, radius, enemy.global_position,
				Enemy.BODY_RADIUS, Enemy.BODY_HEIGHT)
		if s >= 0.0 and s <= limit:
			candidates.append([s, enemy])
	candidates.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for candidate in candidates:
		var at := a.lerp(b, candidate[0])
		var keeps_going := true
		if candidate[1] is Player:
			keeps_going = _hit_player(proj, candidate[1], at)
		else:
			keeps_going = _hit_enemy(proj, candidate[1], at)
		if not keeps_going or proj.returning != leg_returning:
			proj.position = at
			return
	if limit < 1.0:
		proj.hit_wall(wall_point)


## Where the projectile came from (for guards, parries and knockback): a point
## back along its path from `at`, and the yaw it flies along.
func _source(proj: Projectile, at: Vector3) -> Array:
	var dir := proj.velocity.normalized()
	var flat := Vector2(dir.x, dir.z)
	var yaw := PlayerState.yaw_for_direction(flat) if not flat.is_zero_approx() else 0.0
	return [at - dir * SOURCE_BACKOFF, yaw]


## Server: resolves a hit on a player. Returns false if it stopped (or turned).
func _hit_player(proj: Projectile, target: Player, at: Vector3) -> bool:
	var source := _source(proj, at)
	var allied := world.are_allies(proj.owner_id, target.peer_id)
	var result := world.resolve_strike(proj.owner_id, source[0], source[1], proj.attack,
			proj.results, target, proj.damage_scale)
	if allied:
		if result >= 0:
			_ally_hits += 1
		else:
			_ally_ignored += 1
	if result < 0:
		return true  # an ally: flies on
	world.note_projectile_hit(proj.attack is AbilityParams, true)
	if result == World.HIT_EVADED:
		return true
	_hits_players += 1
	if result == World.HIT_DAMAGED:
		world._give_hit_statuses(proj.owner_id, proj.attack, _on_hit_for(proj), target)
	return proj.register_hit(target.peer_id,
			result == World.HIT_BLOCKED or result == World.HIT_PARRIED)


## Server: resolves a hit on an enemy. Returns false if it stopped (or turned).
func _hit_enemy(proj: Projectile, enemy: Enemy, at: Vector3) -> bool:
	var source := _source(proj, at)
	_hits_enemies += 1
	world.note_projectile_hit(proj.attack is AbilityParams, false)
	var keeps_going := proj.register_hit(enemy.enemy_id, false)
	world.strike_enemy(proj.owner_id, source[0], source[1], proj.attack, enemy,
			proj.damage_scale, _on_hit_for.bind(proj))
	return keeps_going


## The thrower's on-hit statuses (Bloodlust's bleed) for a damaging hit: taken
## (using up a charge) on the projectile's first damaging hit, then shared.
func _on_hit_for(proj: Projectile) -> Array[Vector2i]:
	if not proj.on_hit_taken:
		proj.on_hit_taken = true
		var thrower := world._player_by_id(proj.owner_id)
		if thrower and not thrower.state.dead:
			proj.on_hit = thrower.state.take_on_hit_statuses(thrower.params)
	return proj.on_hit


func _send_event(proj: Projectile, type: int) -> void:
	if world.is_verbose() and type != EVENT_TURN:
		print("[server] projectile #%d ended (%d) at %s" % [proj.id, type, proj.position])
	for peer_id in world._connected_player_ids():
		_receive_event.rpc_id(peer_id, proj.id, type, proj.age, proj.position)


func print_summary() -> void:
	print("SUMMARY projectiles fired=%d hits=%d on_players=%d on_enemies=%d ally_hits=%d ally_ignored=%d stopped=%d walls=%d caught=%d expired=%d" % [
			_fired, _hits_players + _hits_enemies, _hits_players, _hits_enemies, _ally_hits,
			_ally_ignored, _ended.get(Projectile.END_HIT, 0), _ended.get(Projectile.END_WALL, 0),
			_ended.get(Projectile.END_CAUGHT, 0), _ended.get(Projectile.END_EXPIRED, 0)])


# --- Client ---

## Client: the local player's predicted attack released its projectiles: a
## cosmetic copy of each right away, until the server's spawn confirms it.
func client_fire(player: Player) -> void:
	var attack := player.state.current_attack(player.params)
	var p := ProjectileParams.get_kind(attack.projectile) if attack else null
	if p == null:
		return
	var yaw := player.state.yaw
	var from := Projectile.release_point(p, player.global_position, yaw)
	for i in attack.projectile_count:
		var f := _add_flying(p, from, Projectile.launch_velocity_for(p, yaw,
				spread_offset(i, attack.projectile_count, attack.projectile_spread)), player.peer_id)
		f.local_clock = true
		f.confirmed = false
		_cosmetic_fired += 1
	if world.is_verbose():
		# The --screenshot-dir frame number, to find the throw in the frames.
		print("[client] throws %s (frame %d)" % [p.id, Time.get_ticks_msec() / 250])


@rpc("authority", "call_remote", "reliable")
func _receive_spawn(id: int, kind: String, owner_id: int, origin: Vector3, velocity: Vector3,
		tick: int) -> void:
	_spawns_seen += 1
	var p := ProjectileParams.get_kind(kind)
	if p == null:
		return
	if owner_id == multiplayer.get_unique_id():
		for f in _flying:
			if not f.confirmed and f.flight.params == p:
				f.confirmed = true
				f.flight.id = id
				_by_id[id] = f
				return
	var f := _add_flying(p, origin, velocity, owner_id)
	f.flight.id = id
	f.spawn_tick = tick
	_by_id[id] = f


@rpc("authority", "call_remote", "reliable")
func _receive_event(id: int, type: int, age: int, position: Vector3) -> void:
	var f: Flying = _by_id.get(id)
	if f:
		f.events.append([age, type, position])


func _add_flying(p: ProjectileParams, from: Vector3, velocity: Vector3, owner_id: int) -> Flying:
	var f := Flying.new()
	f.flight = Projectile.new(p, from, velocity)
	f.flight.owner_id = owner_id
	f.visual = ProjectileVisual.new()
	f.visual.setup(p)
	f.visual.visible = false
	add_child(f.visual)
	_flying.append(f)
	return f


func _client_step(delta: float) -> void:
	var render_tick := world.render_tick()
	for f: Flying in _flying.duplicate():
		var target_age := f.flight.age + 1
		if not f.local_clock:
			if render_tick < 0.0:
				continue
			target_age = floori(render_tick) - f.spawn_tick
		_apply_events(f, delta)
		while f.flight.age < target_age and f.flight.ended == Projectile.END_NONE:
			if f.end_age >= 0 and f.flight.age >= f.end_age:
				break
			f.flight.step(delta, _return_target(f.flight.owner_id, f.flight))
			_apply_events(f, delta)
		var over := f.end_age >= 0 and f.flight.age >= f.end_age
		var unconfirmed_too_long := not f.confirmed and f.flight.age > UNCONFIRMED_TICKS
		if over or f.flight.ended != Projectile.END_NONE or unconfirmed_too_long:
			_remove(f)


## Applies the server's events the copy has reached. A late one (the local
## player's own copy runs ahead) rewinds to it and flies the difference again.
func _apply_events(f: Flying, delta: float) -> void:
	while not f.events.is_empty() and f.events[0][0] <= f.flight.age:
		var event: Array = f.events.pop_front()
		var age: int = event[0]
		if event[1] != EVENT_TURN:
			f.end_age = age
			f.end_position = event[2]
			continue
		var late := f.flight.age - age
		f.flight.age = age
		f.flight.position = event[2]
		f.flight.prev_position = event[2]
		if not f.flight.returning:
			f.flight.start_return()
		f.flight.ended = Projectile.END_NONE
		for i in late:
			f.flight.step(delta, _return_target(f.flight.owner_id, f.flight))


func _remove(f: Flying) -> void:
	_flying.erase(f)
	if _by_id.get(f.flight.id) == f:
		_by_id.erase(f.flight.id)
	f.visual.queue_free()


func _process(_delta: float) -> void:
	if multiplayer.is_server():
		return
	var render_tick := world.render_tick()
	for f in _flying:
		var flight := f.flight
		var fraction := Engine.get_physics_interpolation_fraction()
		if not f.local_clock:
			var exact := render_tick - f.spawn_tick
			if render_tick < 0.0 or exact < 0.0:
				f.visual.visible = false
				continue
			fraction = clampf(exact - (flight.age - 1), 0.0, 1.0)
		f.visual.visible = true
		f.visual.show_at(flight.prev_position.lerp(flight.position, fraction), flight.velocity)


func print_client_summary() -> void:
	print("SUMMARY client=%d projectiles_seen=%d cosmetic=%d" % [
			multiplayer.get_unique_id(), _spawns_seen, _cosmetic_fired])
