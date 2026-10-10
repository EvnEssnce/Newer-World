class_name ZoneSystem
extends Node3D
## Ground zones and summons over the network (the AREA and SUMMON tags). World
## adds one at World/Zones on the server and every client (RPCs are matched by
## node path). Zones are server state, never in snapshots and never in the
## predicted simulation: the server sends reliable events and clients only draw.
##
## Server: placed by an attack or ability reaching its zone_tick
## (Player.zone_placed: `zone` kind, `zone_distance` m ahead), by a projectile
## ending (`zone_on_impact`, where it stopped), or by a roll while a status
## with `roll_zone` is on (World._roll_zone). server_step ticks each one once
## per tick after players, enemies and projectiles: a pulse zone applies its
## effect (World.zone_effect: damage, healing, a status) to everything of its
## `affects` side standing in it; an armed trap fires on the first hostile in
## it, then re-arms or ends. Decoys stand in for their owner as enemies' target
## (World._enemy_targets). Walls get a collision box on WALL_LAYER, which only
## enemies collide with, and stop hostile projectiles (wall_hit).
## Events to clients: _receive_zone(id, kind, position, yaw, ticks_left),
## _receive_zone_moved(id, position), _receive_zone_triggered(id),
## _receive_zone_end(id).

## Physics layer value of summoned walls (layer 5): enemies mask it, players
## and the world don't.
const WALL_LAYER := 16
## Meters above a placement point the ground snap starts from.
const SNAP_FROM := 1.0

var world: World
var players: Node3D
var enemies: Node3D

# Server
var _next_id := 1
var _active: Array[Zone] = []
var _walls: Dictionary[int, StaticBody3D] = {}
var _spawned := 0
var _pulses := 0
var _affected := 0
var _trap_triggers := 0
var _decoys := 0
var _walls_placed := 0
var _projectiles_stopped := 0
var _grown := 0
# Client: id -> [Zone (its own countdown), ZoneVisual]
var _shown: Dictionary[int, Array] = {}


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		for id: int in _shown:
			var zone: Zone = _shown[id][0]
			zone.step()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		return
	var tps := float(Engine.physics_ticks_per_second)
	for id: int in _shown:
		var zone: Zone = _shown[id][0]
		(_shown[id][1] as ZoneVisual).update(maxf(0.0, zone.ticks_left / tps),
				zone.age >= zone.armed_at, delta)


# --- Server ---

## Server: places a zone of `kind` owned by `owner_id` on the ground below
## `at`, facing `yaw`. Returns it, or null for an unknown kind.
func server_spawn(kind: String, owner_id: int, at: Vector3, yaw: float) -> Zone:
	var p := ZoneParams.get_kind(kind)
	if p == null:
		push_error("ZoneSystem: unknown zone kind \"%s\"" % kind)
		return null
	var zone := Zone.new(p, _ground_below(at), yaw, owner_id, world.trap_rearms(owner_id, p))
	zone.id = _next_id
	_next_id += 1
	_active.append(zone)
	_spawned += 1
	if p.decoy:
		_decoys += 1
	if p.wall and p.solid:
		_add_wall_body(zone)
		_walls_placed += 1
	for peer_id in world._connected_player_ids():
		_receive_zone.rpc_id(peer_id, zone.id, kind, zone.position, yaw, zone.ticks_left)
	if world.is_verbose():
		print("[server] peer %d places %s #%d" % [owner_id, kind, zone.id])
	return zone


## Server: a player's attack or ability reached its zone_tick: places its
## `zone` zone_distance m ahead of the player, facing the same way.
func server_place_for_attack(player: Player, attack: AttackParams) -> void:
	var yaw := player.state.yaw
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw)) * attack.zone_distance
	server_spawn(attack.zone, player.peer_id, player.global_position + ahead, yaw)


## Server: every zone one tick (after players, enemies and projectiles).
func server_step() -> void:
	for zone: Zone in _active.duplicate():
		var pulse := zone.step()
		if pulse:
			_pulses += 1
			for target in _targets_in(zone):
				world.zone_effect(zone, target)
				_affected += 1
			_grow(zone)
		elif zone.is_armed():
			var first := _first_target_in(zone)
			if first:
				world.zone_effect(zone, first)
				_affected += 1
				_trap_triggers += 1
				zone.trigger()
				for peer_id in world._connected_player_ids():
					_receive_zone_triggered.rpc_id(peer_id, zone.id)
		if zone.ended:
			_end(zone)


## Server: the newest live decoy `peer_id` placed, or null.
func decoy_for(peer_id: int) -> Zone:
	for i in range(_active.size() - 1, -1, -1):
		var zone := _active[i]
		if zone.params.decoy and zone.owner_id == peer_id and not zone.ended:
			return zone
	return null


## Server: moves a zone (Shadow Swap moves a decoy) and tells every client.
func server_move(zone: Zone, to: Vector3) -> void:
	zone.position = to
	for peer_id in world._connected_player_ids():
		_receive_zone_moved.rpc_id(peer_id, zone.id, to)


## Server: the fraction (0..1) along a -> b where a projectile of `radius`
## thrown by owner_id first meets a wall that isn't its own side's, or -1.
func wall_hit(a: Vector3, b: Vector3, radius: float, owner_id: int) -> float:
	var best := -1.0
	for zone in _active:
		if not zone.params.solid or world.are_allies(zone.owner_id, owner_id):
			continue
		var t := zone.blocks_segment(a, b, radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


## Server: a projectile stopped at a wall (counted for the summary).
func note_projectile_stopped() -> void:
	_projectiles_stopped += 1


func print_summary() -> void:
	print("SUMMARY zones spawned=%d pulses=%d affected=%d trap_triggers=%d decoys=%d walls=%d projectiles_stopped=%d grown=%d" % [
			_spawned, _pulses, _affected, _trap_triggers, _decoys, _walls_placed,
			_projectiles_stopped, _grown])


func _end(zone: Zone) -> void:
	_active.erase(zone)
	if _walls.has(zone.id):
		_walls[zone.id].queue_free()
		_walls.erase(zone.id)
	if zone.params.decoy:
		world.on_decoy_ended(zone)
	for peer_id in world._connected_player_ids():
		_receive_zone_end.rpc_id(peer_id, zone.id)


## Living players of the zone's `affects` side and (hostile zones) living
## enemies standing in it.
func _targets_in(zone: Zone) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var hostile := zone.params.affects == ZoneParams.AFFECTS_HOSTILE
	for player: Player in players.get_children():
		if player.state.dead or not zone.contains(player.global_position):
			continue
		if world.are_allies(zone.owner_id, player.peer_id) != hostile:
			result.append(player)
	if hostile:
		for enemy: Enemy in enemies.get_children():
			if not enemy.dead and zone.contains(enemy.global_position):
				result.append(enemy)
	return result


## A trap's target: the first of its `affects` side standing in it (enemies
## first for a hostile one), or null.
func _first_target_in(zone: Zone) -> Node3D:
	var targets := _targets_in(zone)
	for target in targets:
		if target is Enemy:
			return target
	return targets[0] if not targets.is_empty() else null


## Conflagration: a pulse zone whose owner has "zone_grow" for its status grows
## (World.zone_growth: [per pulse, at most]); clients are told its new scale.
func _grow(zone: Zone) -> void:
	var growth := world.zone_growth(zone)
	if growth.x <= 0.0 or zone.scale >= growth.y:
		return
	zone.scale = minf(growth.y, zone.scale + growth.x)
	_grown += 1
	for peer_id in world._connected_player_ids():
		_receive_zone_scaled.rpc_id(peer_id, zone.id, zone.scale)


func _add_wall_body(zone: Zone) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(zone.params.wall_width, zone.params.height, zone.params.wall_depth)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = zone.position + Vector3.UP * zone.params.height / 2.0
	body.rotation.y = zone.yaw
	_walls[zone.id] = body


## The ground straight below `from` (or `from` if there's none within 50 m).
func _ground_below(from: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * SNAP_FROM,
			from + Vector3.DOWN * 50.0, 1)
	var hit := space.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else from


# --- Client ---

@rpc("authority", "call_remote", "reliable")
func _receive_zone(id: int, kind: String, position_: Vector3, yaw: float, ticks_left: int) -> void:
	var p := ZoneParams.get_kind(kind)
	if p == null or _shown.has(id):
		return
	var zone := Zone.new(p, position_, yaw, 0)
	zone.ticks_left = ticks_left
	var visual := ZoneVisual.new()
	visual.setup(p, yaw)
	add_child(visual)
	visual.global_position = position_
	_shown[id] = [zone, visual]


@rpc("authority", "call_remote", "reliable")
func _receive_zone_moved(id: int, to: Vector3) -> void:
	if _shown.has(id):
		(_shown[id][0] as Zone).position = to
		(_shown[id][1] as ZoneVisual).global_position = to


@rpc("authority", "call_remote", "reliable")
func _receive_zone_scaled(id: int, new_scale: float) -> void:
	if _shown.has(id):
		(_shown[id][0] as Zone).scale = new_scale
		(_shown[id][1] as ZoneVisual).scale = Vector3(new_scale, 1.0, new_scale)


@rpc("authority", "call_remote", "reliable")
func _receive_zone_triggered(id: int) -> void:
	if _shown.has(id):
		var zone: Zone = _shown[id][0]
		zone.armed_at = zone.age + maxi(1, zone.params.arm_ticks)


@rpc("authority", "call_remote", "reliable")
func _receive_zone_end(id: int) -> void:
	if _shown.has(id):
		(_shown[id][1] as Node).queue_free()
		_shown.erase(id)
