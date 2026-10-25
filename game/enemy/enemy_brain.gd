class_name EnemyBrain
extends RefCounted
## An enemy's decisions, one server tick at a time: wander around its camp,
## notice players, chase, swing, and walk home if pulled too far. Pure logic
## (positions in, desired velocity out), so it's unit tested
## (tests/test_enemy_brain.gd). Server only; death and health live in Enemy.
##
## Target choice is a ThreatTable: players gain threat by coming within
## aggro_range (threat_proximity, nearest first), damaging it and healing
## someone it fights (add_threat). While chasing it retargets every tick
## (ThreatTable.pick_target); a swing keeps its target. An empty table (the
## target died or left, nobody else has threat) sends it home, like leashing;
## walking home wipes the table and ignores new threat until it's back.
##
## A stationary enemy (params.stationary: the training dummy) never moves,
## turns or swings: it only goes through staggers.
##
## Walking (wander, chase, return) goes through `path` (EnemyPath) when set:
## the brain picks the goal, the path the way around crates and walls. A swing
## starts only when the path to the target is direct.
##
## Camps: an enemy that starts fighting (IDLE -> CHASE) sets `pulled`; World
## then alerts the rest of its camp (`alert`), so a camp fights together.
## keep_distance > 0 (hit-and-run kinds, casters): while its attack cooldown
## runs it backs away from a target nearer than that, facing it.

enum Mode { IDLE, CHASE, ATTACK, STAGGERED, RETURN }

var mode := Mode.IDLE
## Peer id of the player being chased or attacked; 0 for none.
var target_id := 0
## Ticks since the current swing started, or -1 when not swinging.
var attack_tick := -1
var cooldown_ticks := 0
var stagger_ticks := 0
## Facing around Y. 0 faces -Z.
var yaw := 0.0
var wander_point := Vector3.ZERO
var wander_wait := 0
## True only for the step in which it got back to its camp after leashing.
var arrived_home := false
## Who it wants to fight.
var threat := ThreatTable.new()
## Set by Enemy before each step: the taunting player (peer id) it must target
## while the taunt lasts, 0 = none.
var forced_target := 0
## Times it changed from one target to another (counted for the server summary).
var target_switches := 0
## Set when it starts fighting (IDLE -> CHASE): World alerts its camp and
## clears it (take_pulled).
var pulled := false
## Walks around obstacles (EnemyPath) when set; null = straight at the goal
## (tests, the training dummy, kinds with [navigation] enabled=false).
var path: EnemyPath = null


## Advances one tick and returns the desired horizontal velocity (x, z).
## targets maps the peer id of every player it may attack to their position.
func step(pos: Vector3, home: Vector3, targets: Dictionary, params: EnemyParams,
		delta: float, rng: RandomNumberGenerator) -> Vector2:
	arrived_home = false
	if params.stationary:
		return _stand()
	cooldown_ticks = maxi(0, cooldown_ticks - 1)
	if mode != Mode.RETURN:
		_update_threat(pos, targets, params)
	match mode:
		Mode.IDLE:
			if _retarget(params) != 0:
				_start_chase()
				return _chase(pos, home, targets, params, delta)
			return _wander(pos, home, params, delta, rng)
		Mode.CHASE:
			_retarget(params)
			return _chase(pos, home, targets, params, delta)
		Mode.ATTACK:
			return _attack(pos, targets, params, delta)
		Mode.STAGGERED:
			stagger_ticks -= 1
			if stagger_ticks <= 0:
				mode = Mode.CHASE if _retarget(params) != 0 else Mode.RETURN
			return Vector2.ZERO
		Mode.RETURN:
			return _return(pos, home, params, delta)
	return Vector2.ZERO


## Adds threat for a player (e.g. one who hit it). Ignored while walking home.
## An idle enemy starts chasing at once.
func add_threat(peer_id: int, amount: float, params: EnemyParams) -> void:
	if mode == Mode.RETURN or not threat.add(peer_id, amount):
		return
	if mode == Mode.IDLE and _retarget(params) != 0:
		_start_chase()


## A campmate started fighting peer_id: an idle enemy joins in (proximity
## threat on them, then it chases). Returns true if it joined.
func alert(peer_id: int, params: EnemyParams) -> bool:
	if mode != Mode.IDLE or peer_id <= 0:
		return false
	add_threat(peer_id, maxf(params.threat_proximity, 0.001), params)
	return mode == Mode.CHASE


## True once after it started fighting (then cleared).
func take_pulled() -> bool:
	var was := pulled
	pulled = false
	return was


## A taunt by peer_id: its threat goes to the top (ThreatTable.taunt). The
## forced target itself comes from forced_target. Ignored while walking home.
## Returns true if taken.
func taunt(peer_id: int, params: EnemyParams) -> bool:
	if mode == Mode.RETURN or not threat.taunt(peer_id, params.threat_switch_ratio):
		return false
	if mode == Mode.IDLE:
		_start_chase()
		_set_target(peer_id)
	return true


## Interrupts a swing and stops it acting for ticks.
func stagger(ticks: int) -> void:
	if ticks <= 0:
		return
	attack_tick = -1
	mode = Mode.STAGGERED
	stagger_ticks = maxi(stagger_ticks, ticks)


func is_attacking() -> bool:
	return attack_tick >= 0


## True when it isn't fighting attacker_id (idle, or targeting someone else),
## so a hit from them counts as a backstab where [backstab] unaware_enemies is
## on. Never for an always_aware enemy (training dummy): only hits from behind.
func is_unaware_of(attacker_id: int, params: EnemyParams) -> bool:
	return not params.always_aware and target_id != attacker_id


func is_attack_active(params: EnemyParams) -> bool:
	var a := params.attack
	return attack_tick >= a.windup_ticks and attack_tick < a.windup_ticks + a.active_ticks


## Decay, drop players who are gone (dead or left), and proximity threat for
## players newly within aggro_range, nearest first (so ties go to the nearest).
func _update_threat(pos: Vector3, targets: Dictionary, params: EnemyParams) -> void:
	threat.decay(params.threat_decay_factor)
	threat.keep_only(targets)
	var near: Array = []
	for id: int in targets:
		if threat.has(id):
			continue
		var distance := _flat(targets[id] - pos).length()
		if distance <= params.aggro_range:
			near.append([distance, id])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in near:
		threat.add(entry[1], params.threat_proximity)


## Picks the target from the threat table. Returns it (0 = nobody).
func _retarget(params: EnemyParams) -> int:
	_set_target(threat.pick_target(target_id, params.threat_switch_ratio, forced_target))
	return target_id


func _start_chase() -> void:
	mode = Mode.CHASE
	pulled = true


func _set_target(peer_id: int) -> void:
	if peer_id != target_id and peer_id != 0 and target_id != 0:
		target_switches += 1
	target_id = peer_id


## A stationary enemy's step: staggers count down, nothing else happens. It
## keeps no threat, so it never counts as fighting anyone (heals draw no aggro).
func _stand() -> Vector2:
	target_id = 0
	threat.clear()
	if mode == Mode.STAGGERED:
		stagger_ticks -= 1
		if stagger_ticks <= 0:
			mode = Mode.IDLE
	else:
		mode = Mode.IDLE
	return Vector2.ZERO


func _wander(pos: Vector3, home: Vector3, params: EnemyParams, delta: float,
		rng: RandomNumberGenerator) -> Vector2:
	if wander_wait > 0:
		wander_wait -= 1
		return Vector2.ZERO
	var route := _route(pos, wander_point)
	# A path used up counts as there (the point may be inside a crate).
	if _flat(wander_point - pos).length() < 0.3 or (path != null and path.arrived()):
		wander_wait = rng.randi_range(0, params.wander_pause_ticks)
		var angle := rng.randf() * TAU
		var radius := rng.randf() * params.wander_radius
		wander_point = home + Vector3(cos(angle), 0.0, sin(angle)) * radius
		if path != null:
			path.reset()
		return Vector2.ZERO
	return _walk(route, params.wander_speed, params, delta)


func _chase(pos: Vector3, home: Vector3, targets: Dictionary, params: EnemyParams,
		delta: float) -> Vector2:
	if not targets.has(target_id) or _flat(pos - home).length() > params.leash_range:
		mode = Mode.RETURN
		target_id = 0
		threat.clear()
		return _return(pos, home, params, delta)
	var to := _flat(targets[target_id] - pos)
	if cooldown_ticks > 0 and to.length() < params.keep_distance:
		return _back_away(to, params, delta)
	var route := _route(pos, targets[target_id])
	# In reach but something in between (a wall or crate corner): keep walking
	# around it instead of swinging through it.
	if to.length() > params.attack_range or (path != null and not path.is_direct()):
		return _walk(route, params.move_speed, params, delta)
	_turn_toward(to, params, delta)
	if cooldown_ticks == 0:
		mode = Mode.ATTACK
		attack_tick = 0
	return Vector2.ZERO


## Hit-and-run / casters between swings: backs straight away from the target
## (a wall behind it just stops it), still facing it.
func _back_away(to: Vector2, params: EnemyParams, delta: float) -> Vector2:
	_turn_toward(to, params, delta)
	if to.is_zero_approx():
		return Vector2.ZERO
	return -to.normalized() * params.retreat_speed


func _attack(pos: Vector3, targets: Dictionary, params: EnemyParams, delta: float) -> Vector2:
	attack_tick += 1
	if attack_tick >= params.attack.total_ticks():
		mode = Mode.CHASE
		attack_tick = -1
		cooldown_ticks = params.attack_cooldown_ticks
		return Vector2.ZERO
	if not targets.has(target_id):
		return Vector2.ZERO
	var to := _flat(targets[target_id] - pos)
	# Tracks the target while winding up; committed once the swing comes down.
	if attack_tick < params.attack.windup_ticks:
		_turn_toward(to, params, delta)
	if params.attack.move_multiplier <= 0.0 or to.length() < 0.5:
		return Vector2.ZERO
	return to.normalized() * params.move_speed * params.attack.move_multiplier


func _return(pos: Vector3, home: Vector3, params: EnemyParams, delta: float) -> Vector2:
	var to := _flat(home - pos)
	if to.length() < 0.5:
		mode = Mode.IDLE
		arrived_home = true
		wander_point = pos
		wander_wait = 0
		threat.clear()
		return Vector2.ZERO
	return _walk(_route(pos, home), params.return_speed, params, delta)


## The flat vector to walk along toward goal: around obstacles with a path,
## else straight at it.
func _route(pos: Vector3, goal: Vector3) -> Vector2:
	if path != null:
		return path.steer(pos, goal)
	return _flat(goal - pos)


func _walk(to: Vector2, speed: float, params: EnemyParams, delta: float) -> Vector2:
	_turn_toward(to, params, delta)
	return to.normalized() * speed


func _turn_toward(to: Vector2, params: EnemyParams, delta: float) -> void:
	if not to.is_zero_approx():
		yaw = rotate_toward(yaw, PlayerState.yaw_for_direction(to), params.turn_speed * delta)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
