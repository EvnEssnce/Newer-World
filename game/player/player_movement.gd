class_name PlayerMovement
## One fixed-length simulation step for a player, given one tick of input.
##
## The server runs this to move players for real, and the local client runs the
## exact same code to predict its own movement. Keep it deterministic: no
## randomness, no frame-time dependence, no reading of Input here.

## A teleport follows at most this many slopes before it stops.
const TELEPORT_MAX_SLIDES := 4


## aim_pitch: the camera's pitch (radians, up = positive); see PlayerState.step.
static func step(body: CharacterBody3D, state: PlayerState, move: Vector2, buttons: int,
		aim_yaw: float, params: PlayerParams, delta: float, aim_pitch := 0.0) -> void:
	var on_floor := state.on_floor
	var was_dodging := state.is_dodging()
	state.step(move, buttons, aim_yaw, on_floor, params, delta, aim_pitch)
	if not state.can_act():
		move = Vector2.ZERO  # staggered, stunned or dead: slide to a stop, can't jump
		buttons = 0
	var rooted := not state.can_move(params)
	if rooted:
		move = Vector2.ZERO  # rooted: stop, no jump or dash (attacks still work)
		buttons &= ~PlayerState.BUTTON_JUMP
	# A teleport (Blink, Ashstep) moves the body at once on its tick; the rest
	# of the step carries on from the new spot. Root stops it like a dash.
	var ability := state.current_ability(params)
	if ability and ability.teleports_at(state.attack_tick) and state.can_act() and not rooted:
		teleport(body, state.ability_dir * ability.teleport_distance, on_floor)

	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if was_dodging and not state.is_dodging() and not on_floor:
		# An air dodge just ended: don't keep sailing at roll speed (Updraft).
		horizontal = after_air_dodge(horizontal,
				state.statuses.max_fall_speed(params.statuses) > 0.0, params)
	# Forced movement (knockback, pull) overrides everything horizontal; a
	# launch sets the vertical speed once, below. Starting it interrupts dodges
	# and dashes, so it never competes with them.
	if state.is_forced():
		var push := state.force.step_velocity()
		horizontal = Vector3(push.x, 0.0, push.y)
	# A dodge only sets horizontal velocity; vertical (jumps, gravity) carries on as
	# normal, so an air dodge keeps its arc.
	elif state.is_dodging():
		horizontal = (Vector3(state.dodge_dir.x, 0.0, state.dodge_dir.y) * params.dodge_speed
				* state.statuses.dodge_speed_multiplier(params.statuses))
	elif rooted:
		horizontal = horizontal.move_toward(Vector3.ZERO, params.ground_deceleration * delta)
	elif state.is_dashing(params):
		# An ability dash (e.g. Shield Charge) works like a dodge: horizontal only.
		# ability_dir's length is the fraction of the distance (Crashing Leap).
		var dash_speed := state.current_ability(params).dash_speed_at(state.attack_tick)
		horizontal = Vector3(state.ability_dir.x, 0.0, state.ability_dir.y) * dash_speed
	else:
		var speed := params.move_speed * state.status_move_multiplier(params) * state.bonus_move_multiplier()
		var attack := state.current_attack(params)
		if attack and not state.moves_freely():
			speed *= attack.move_multiplier
		elif state.blocking:
			speed *= params.block_move_multiplier
		var target := Vector3(move.x, 0.0, move.y) * speed
		var acceleration := params.air_acceleration
		if on_floor:
			acceleration = (params.ground_deceleration if move.is_zero_approx()
					else params.ground_acceleration)
		horizontal = horizontal.move_toward(target, acceleration * delta)

	var vertical := body.velocity.y
	var can_jump := not state.is_dodging() and not state.is_attacking()
	var launch := state.force.take_launch()
	var self_launch := _self_launch_speed(state, params)
	if launch > 0.0:
		vertical = launch
	elif self_launch > 0.0:
		vertical = self_launch
	elif on_floor and buttons & PlayerState.BUTTON_JUMP and can_jump:
		vertical = params.jump_velocity
	elif not on_floor:
		var gravity := params.gravity
		if vertical < 0.0:
			gravity *= state.statuses.fall_gravity_multiplier(params.statuses)
		vertical -= gravity * delta
		var hover := state.statuses.max_fall_speed(params.statuses)  # Updraft
		if hover > 0.0 and vertical < -hover:
			vertical = -hover

	body.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	body.move_and_slide()
	state.on_floor = body.is_on_floor()


## The horizontal velocity left when an air dodge ends: at most
## [dodge] air_exit_speed m/s, while hovering (an Updraft-like max_fall_speed
## status) or, with air_exit_hover_only false, any time in the air. Pure.
static func after_air_dodge(horizontal: Vector3, hovering: bool, params: PlayerParams) -> Vector3:
	if params.dodge_air_exit_speed <= 0.0 or (params.dodge_air_exit_hover_only and not hovering):
		return horizontal
	return horizontal.limit_length(params.dodge_air_exit_speed)


## Moves the body `offset` (world XZ, meters) at once: across the ground,
## climbing walkable slopes, stopping short of walls and anything else in the
## way (it can't end inside geometry or pass through it). If it was on the
## floor, it then settles onto the floor below, as far down as a walkable slope
## could drop over that distance; with no floor there it's left in the air to
## fall. Deterministic (only the static world is tested), so the server and
## prediction agree. Velocity is untouched.
static func teleport(body: CharacterBody3D, offset: Vector2, on_floor: bool) -> void:
	var up := body.up_direction
	var motion := Vector3(offset.x, 0.0, offset.y)
	var travelled := 0.0
	for i in TELEPORT_MAX_SLIDES:
		if motion.length_squared() < 0.000001:
			break
		var hit := body.move_and_collide(motion)
		if hit == null:
			travelled += _horizontal_length(motion, up)
			break
		travelled += _horizontal_length(hit.get_travel(), up)
		var normal := hit.get_normal()
		if normal.angle_to(up) > body.floor_max_angle:
			break  # a wall: stop short of it
		# A walkable slope: go on along it with the same horizontal heading,
		# rising (or sinking) as the slope needs.
		var rest := hit.get_remainder()
		rest -= up * rest.dot(up)
		motion = rest - up * (rest.dot(normal) / normal.dot(up))
	if not on_floor:
		return
	var drop := travelled * tan(body.floor_max_angle) + body.floor_snap_length
	var down := body.move_and_collide(-up * drop, true)
	if down and down.get_normal().angle_to(up) <= body.floor_max_angle:
		body.global_position += down.get_travel()


static func _horizontal_length(v: Vector3, up: Vector3) -> float:
	return (v - up * v.dot(up)).length()


## An ability that launches its user (launch_height, Updraft) on its
## launch_tick: the upward speed that reaches that height; else 0.
static func _self_launch_speed(state: PlayerState, params: PlayerParams) -> float:
	var ability := state.current_ability(params)
	if ability == null or ability.launch_height <= 0.0 or state.attack_tick != ability.launch_tick:
		return 0.0
	return sqrt(2.0 * params.gravity * ability.launch_height)
