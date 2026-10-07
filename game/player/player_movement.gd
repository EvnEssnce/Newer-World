class_name PlayerMovement
## One fixed-length simulation step for a player, given one tick of input.
##
## The server runs this to move players for real, and the local client runs the
## exact same code to predict its own movement. Keep it deterministic: no
## randomness, no frame-time dependence, no reading of Input here.


static func step(body: CharacterBody3D, state: PlayerState, move: Vector2, buttons: int,
		aim_yaw: float, params: PlayerParams, delta: float) -> void:
	var on_floor := body.is_on_floor()
	state.step(move, buttons, aim_yaw, on_floor, params, delta)

	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	# A dodge only sets horizontal velocity; vertical (jumps, gravity) carries on as
	# normal, so an air dodge keeps its arc.
	if state.is_dodging():
		horizontal = Vector3(state.dodge_dir.x, 0.0, state.dodge_dir.y) * params.dodge_speed
	else:
		var speed := params.move_speed
		var attack := state.current_attack(params)
		if attack:
			speed *= attack.move_multiplier
		var target := Vector3(move.x, 0.0, move.y) * speed
		var acceleration := params.air_acceleration
		if on_floor:
			acceleration = (params.ground_deceleration if move.is_zero_approx()
					else params.ground_acceleration)
		horizontal = horizontal.move_toward(target, acceleration * delta)

	var vertical := body.velocity.y
	var can_jump := not state.is_dodging() and not state.is_attacking()
	if on_floor and buttons & PlayerState.BUTTON_JUMP and can_jump:
		vertical = params.jump_velocity
	elif not on_floor:
		vertical -= params.gravity * delta

	body.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	body.move_and_slide()
