class_name PlayerMovement
## One fixed-length movement step for a player, given one tick of input.
##
## The server runs this to move players for real, and the local client runs the
## exact same code to predict its own movement. Keep it deterministic: no
## randomness, no frame-time dependence, no reading of Input here.


static func step(body: CharacterBody3D, move: Vector2, jump: bool, delta: float) -> void:
	var move_speed: float = Tuning.get_value("movement", "player", "move_speed")
	var ground_acceleration: float = Tuning.get_value("movement", "player", "ground_acceleration")
	var ground_deceleration: float = Tuning.get_value("movement", "player", "ground_deceleration")
	var air_acceleration: float = Tuning.get_value("movement", "player", "air_acceleration")
	var jump_velocity: float = Tuning.get_value("movement", "player", "jump_velocity")
	var gravity: float = Tuning.get_value("movement", "player", "gravity")

	var on_floor := body.is_on_floor()
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var target := Vector3(move.x, 0.0, move.y) * move_speed
	var acceleration := air_acceleration
	if on_floor:
		acceleration = ground_deceleration if move.is_zero_approx() else ground_acceleration
	horizontal = horizontal.move_toward(target, acceleration * delta)

	var vertical := body.velocity.y
	if on_floor and jump:
		vertical = jump_velocity
	elif not on_floor:
		vertical -= gravity * delta

	body.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	body.move_and_slide()


## The yaw (rotation around Y) that faces a world-space XZ direction.
static func yaw_for_direction(move: Vector2) -> float:
	# Godot models face -Z, so forward is (-sin(yaw), -cos(yaw)).
	return atan2(-move.x, -move.y)
