class_name EnemyBrain
extends RefCounted
## An enemy's decisions, one server tick at a time: wander around its camp,
## notice players, chase, swing, and walk home if pulled too far. Pure logic
## (positions in, desired velocity out), so it's unit tested
## (tests/test_enemy_brain.gd). Server only; death and health live in Enemy.

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


## Advances one tick and returns the desired horizontal velocity (x, z).
## targets maps the peer id of every player it may attack to their position.
func step(pos: Vector3, home: Vector3, targets: Dictionary, params: EnemyParams,
		delta: float, rng: RandomNumberGenerator) -> Vector2:
	arrived_home = false
	cooldown_ticks = maxi(0, cooldown_ticks - 1)
	match mode:
		Mode.IDLE:
			var nearest := _nearest_target(pos, targets, params.aggro_range)
			if nearest != 0:
				aggro(nearest)
				return _chase(pos, home, targets, params, delta)
			return _wander(pos, home, params, delta, rng)
		Mode.CHASE:
			return _chase(pos, home, targets, params, delta)
		Mode.ATTACK:
			return _attack(pos, targets, params, delta)
		Mode.STAGGERED:
			stagger_ticks -= 1
			if stagger_ticks <= 0:
				mode = Mode.CHASE if targets.has(target_id) else Mode.RETURN
			return Vector2.ZERO
		Mode.RETURN:
			return _return(pos, home, params, delta)
	return Vector2.ZERO


## Starts chasing a player (e.g. one who hit it) if it isn't busy with another.
func aggro(peer_id: int) -> void:
	if mode == Mode.IDLE:
		mode = Mode.CHASE
		target_id = peer_id


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
		return Vector2.ZERO
	return _walk(to, params.return_speed, params, delta)


func _walk(to: Vector2, speed: float, params: EnemyParams, delta: float) -> Vector2:
	_turn_toward(to, params, delta)
	return to.normalized() * speed


func _turn_toward(to: Vector2, params: EnemyParams, delta: float) -> void:
	if not to.is_zero_approx():
		yaw = rotate_toward(yaw, PlayerState.yaw_for_direction(to), params.turn_speed * delta)


static func _nearest_target(pos: Vector3, targets: Dictionary, max_range: float) -> int:
	var best_id := 0
	var best := max_range
	for id: int in targets:
		var distance := _flat(targets[id] - pos).length()
		if distance <= best:
			best = distance
			best_id = id
	return best_id


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
