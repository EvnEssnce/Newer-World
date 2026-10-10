class_name PlayerMovement
## One fixed-length simulation step for a player, given one tick of input.
##
## The server runs this to move players for real, and the local client runs the
## exact same code to predict its own movement. Keep it deterministic: no
## randomness, no frame-time dependence, no reading of Input here.


## aim_pitch: the camera's pitch (radians, up = positive); see PlayerState.step.
static func step(body: CharacterBody3D, state: PlayerState, move: Vector2, buttons: int,
		aim_yaw: float, params: PlayerParams, delta: float, aim_pitch := 0.0) -> void:
	var on_floor := state.on_floor
	state.step(move, buttons, aim_yaw, on_floor, params, delta, aim_pitch)
	if not state.can_act():
		move = Vector2.ZERO  # staggered, stunned or dead: slide to a stop, can't jump
		buttons = 0
	var rooted := not state.can_move(params)
	if rooted:
		move = Vector2.ZERO  # rooted: stop, no jump or dash (attacks still work)
		buttons &= ~PlayerState.BUTTON_JUMP

	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
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
		var speed := params.move_speed * state.status_move_multiplier(params)
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


## An ability that launches its user (launch_height, Updraft) on its
## launch_tick: the upward speed that reaches that height; else 0.
static func _self_launch_speed(state: PlayerState, params: PlayerParams) -> float:
	var ability := state.current_ability(params)
	if ability == null or ability.launch_height <= 0.0 or state.attack_tick != ability.launch_tick:
		return 0.0
	return sqrt(2.0 * params.gravity * ability.launch_height)
