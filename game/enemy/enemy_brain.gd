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


## Advances one tick and returns the desired horizontal velocity (x, z).
## targets maps the peer id of every player it may attack to their position.
func step(pos: Vector3, home: Vector3, targets: Dictionary, params: EnemyParams,
		delta: float, rng: RandomNumberGenerator) -> Vector2:
	arrived_home = false
	cooldown_ticks = maxi(0, cooldown_ticks - 1)
	if mode != Mode.RETURN:
		_update_threat(pos, targets, params)
	match mode:
		Mode.IDLE:
			if _retarget(params) != 0:
				mode = Mode.CHASE
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
		mode = Mode.CHASE


## A taunt by peer_id: its threat goes to the top (ThreatTable.taunt). The
## forced target itself comes from forced_target. Ignored while walking home.
## Returns true if taken.
func taunt(peer_id: int, params: EnemyParams) -> bool:
	if mode == Mode.RETURN or not threat.taunt(peer_id, params.threat_switch_ratio):
		return false
	if mode == Mode.IDLE:
		mode = Mode.CHASE
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


func _set_target(peer_id: int) -> void:
	if peer_id != target_id and peer_id != 0 and target_id != 0:
		target_switches += 1
	target_id = peer_id


func _wander(pos: Vector3, home: Vector3, params: EnemyParams, delta: float,
		rng: RandomNumberGenerator) -> Vector2:
	if wander_wait > 0:
		wander_wait -= 1
		return Vector2.ZERO
	var to := _flat(wander_point - pos)
	if to.length() < 0.3:
		wander_wait = rng.randi_range(0, params.wander_pause_ticks)
		var angle := rng.randf() * TAU
		var radius := rng.randf() * params.wander_radius
		wander_point = home + Vector3(cos(angle), 0.0, sin(angle)) * radius
		return Vector2.ZERO
	return _walk(to, params.wander_speed, params, delta)


func _chase(pos: Vector3, home: Vector3, targets: Dictionary, params: EnemyParams,
		delta: float) -> Vector2:
	if not targets.has(target_id) or _flat(pos - home).length() > params.leash_range:
		mode = Mode.RETURN
		target_id = 0
		threat.clear()
		return _return(pos, home, params, delta)
	var to := _flat(targets[target_id] - pos)
	if to.length() > params.attack_range:
		return _walk(to, params.move_speed, params, delta)
	_turn_toward(to, params, delta)
	if cooldown_ticks == 0:
		mode = Mode.ATTACK
		attack_tick = 0
	return Vector2.ZERO


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
	return _walk(to, params.return_speed, params, delta)


func _walk(to: Vector2, speed: float, params: EnemyParams, delta: float) -> Vector2:
	_turn_toward(to, params, delta)
	return to.normalized() * speed


func _turn_toward(to: Vector2, params: EnemyParams, delta: float) -> void:
	if not to.is_zero_approx():
		yaw = rotate_toward(yaw, PlayerState.yaw_for_direction(to), params.turn_speed * delta)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
