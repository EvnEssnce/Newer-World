class_name ForcedMotion
extends RefCounted
## A push, pull or launch in progress: on a player (inside PlayerState, so it's
## predicted and reconciled like everything else) or on an enemy (server only).
## Started by the server (start), advanced one step at a time by whoever moves
## the body (PlayerMovement, Enemy). Pure logic, unit tested
## (tests/test_forced_movement.gd).
##
## The horizontal speed falls linearly to zero over the ticks, so a shove eases
## out instead of stopping dead; the upward launch speed is applied on the first
## step only, after which gravity takes over. Deterministic: no delta-time
## dependence after start.

## Horizontal velocity for the next step, m/s (world XZ).
var velocity := Vector2.ZERO
## Steps left. 0 = not being moved.
var ticks := 0
## Upward speed still to apply on the next step, m/s. 0 = none.
var launch := 0.0


## Moves `displacement` meters (world XZ) over `duration` steps of `delta`
## seconds, launching upward at launch_speed m/s on the first step.
func start(displacement: Vector2, duration: int, launch_speed: float, delta: float) -> void:
	ticks = maxi(1, duration)
	# Speeds v, v(n-1)/n, ..., v/n over n steps cover v * delta * (n + 1) / 2.
	velocity = displacement * 2.0 / ((ticks + 1) * delta)
	launch = maxf(0.0, launch_speed)


func is_active() -> bool:
	return ticks > 0


## This step's horizontal velocity (m/s); advances one step. Only while active.
func step_velocity() -> Vector2:
	if ticks <= 0:
		return Vector2.ZERO
	var current := velocity
	velocity -= velocity / ticks
	ticks -= 1
	if ticks == 0:
		velocity = Vector2.ZERO
	return current


## The launch speed for this step (m/s), once; 0 afterwards.
func take_launch() -> float:
	var speed := launch
	launch = 0.0
	return speed


func stop() -> void:
	velocity = Vector2.ZERO
	ticks = 0
	launch = 0.0


## True if a body being pushed along `push` (world XZ velocity) that touches a
## wall with `wall_normal` was driven into it: the wall faces back against the
## push (within 60 degrees) and is steep (not a slope or the floor). For the
## Tempest Wings capstone (stun on a wall hit). Pure math.
static func pushed_into_wall(push: Vector2, wall_normal: Vector3) -> bool:
	var flat := Vector2(wall_normal.x, wall_normal.z)
	if push.length() < 0.5 or flat.length() < 0.7:
		return false
	return flat.normalized().dot(push.normalized()) <= -0.5


func matches(other: ForcedMotion) -> bool:
	return (ticks == other.ticks and velocity.is_equal_approx(other.velocity)
			and is_equal_approx(launch, other.launch))
