class_name AimRay
extends RefCounted
## Where the crosshair points. The third-person camera (Player._setup_camera)
## orbits a point `pivot_height` above the player's feet and `shoulder_offset`
## to the right of its yaw, `distance` behind it along the pitch, looking
## through it; the crosshair is the screen centre, so the aim ray is the line
## from the camera through that orbit point (the "shoulder").
##
## The server rebuilds the same ray from the player's server position and the
## aim_yaw/aim_pitch of its last simulated input (it never takes an aim point
## from a client); the local client does the same for its cosmetic throws, so
## both agree. Pure math here, unit tested in tests/test_aim_ray.gd; `cast` is
## the physics query (World.aim_point uses it).
##
## Camera collision (the SpringArm pulling the camera in) is ignored on purpose:
## the arm slides the camera along this same line, so the crosshair's line never
## changes, and the cast starts at the shoulder (not the camera), so whatever is
## between the camera and the player doesn't count.

## Where the aim cast starts: the camera's orbit point (the shoulder).
var origin := Vector3.ZERO
## Unit vector the camera looks along (yaw: forward is -Z rotated by yaw, as
## everywhere else; pitch: up = positive).
var direction := Vector3.FORWARD
## Where the camera sits when nothing pulls it in.
var camera := Vector3.ZERO


## Camera and aim tuning (data/camera.cfg). Tests build their own.
class Params:
	## Meters above the feet of the orbit point.
	var pivot_height := 1.6
	## Meters to the right (of the yaw) of the orbit point.
	var shoulder_offset := 0.0
	## Meters from the orbit point back to the camera.
	var distance := 4.5
	## Meters the aim cast reaches from the shoulder.
	var max_distance := 100.0
	## Meters an aim point must lie ahead of a release point (along the aim) for
	## a throw to head at it; closer, it flies along the aim ray instead.
	var min_ahead := 1.0
	## Fraction of a melee hitbox's range (from the attacker) where its centre
	## line crosses the crosshair's line (attack_facing).
	var melee_reach_fraction := 0.75
	## Meters: the crossing is never closer than this (a short reach would turn
	## the facing far to the side).
	var melee_min_reach := 1.5
	## Where an aimed beam starts (beam_origin): meters above the feet, and
	## meters ahead along the facing (data/combat.cfg [beam]).
	var beam_height := 1.4
	var beam_forward := 0.5


static var _tuned: Params
static var _tuned_version := -1


## The real tuning from data/camera.cfg (read once, again when Tuning.version
## moves).
static func tuned() -> Params:
	if _tuned == null or _tuned_version != Tuning.version:
		_tuned_version = Tuning.version
		_tuned = Params.new()
		_tuned.pivot_height = Tuning.get_value("camera", "camera", "pivot_height")
		_tuned.shoulder_offset = Tuning.get_value("camera", "camera", "shoulder_offset")
		_tuned.distance = Tuning.get_value("camera", "camera", "distance")
		_tuned.max_distance = Tuning.get_value("camera", "aim", "max_distance")
		_tuned.min_ahead = Tuning.get_value("camera", "aim", "min_ahead")
		_tuned.melee_reach_fraction = Tuning.get_value("camera", "aim", "melee_reach_fraction")
		_tuned.melee_min_reach = Tuning.get_value("camera", "aim", "melee_min_reach")
		_tuned.beam_height = Tuning.get_value("combat", "beam", "origin_height")
		_tuned.beam_forward = Tuning.get_value("combat", "beam", "origin_forward")
	return _tuned


## The camera's look direction for yaw/pitch (radians, pitch up = positive).
static func look_direction(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## The orbit point (the shoulder) for a player standing at `feet` looking `yaw`.
static func shoulder(feet: Vector3, yaw: float, params: Params) -> Vector3:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return feet + Vector3.UP * params.pivot_height + right * params.shoulder_offset


## The aim ray of a player standing at `feet` with this aim.
static func create(feet: Vector3, yaw: float, pitch: float, params: Params) -> AimRay:
	var ray := AimRay.new()
	ray.origin = shoulder(feet, yaw, params)
	ray.direction = look_direction(yaw, pitch)
	ray.camera = ray.origin - ray.direction * params.distance
	return ray


## The point `meters` along the ray from its origin.
func point_at(meters: float) -> Vector3:
	return origin + direction * meters


## The yaw from the player toward the point on the crosshair's line `reach` m
## ahead (along aim_yaw). Seen from above, the line runs parallel to aim_yaw,
## shoulder_offset m to its right, at any pitch (the camera pitches about the
## shoulder), so that point is shoulder_offset right of the aim at that
## distance. reach is at least melee_min_reach; reach <= 0 = aim_yaw. Pure math
## (no ray cast), so the predicted sim uses it and stays deterministic.
static func facing_at_reach(aim_yaw: float, reach: float, params: Params) -> float:
	if reach <= 0.0 or params.shoulder_offset == 0.0:
		return aim_yaw
	return aim_yaw - atan2(params.shoulder_offset, maxf(reach, params.melee_min_reach))


## The yaw `attack` faces (PlayerState: at its start, then turning toward it):
## its hitbox (or dash) heads for the crosshair's line at its reach
## (AttackParams.aim_reach), so what's under the crosshair is what it hits.
static func attack_facing(aim_yaw: float, attack: AttackParams, params: Params) -> float:
	if attack == null:
		return aim_yaw
	return facing_at_reach(aim_yaw, attack.aim_reach(params.melee_reach_fraction), params)


## The unit direction a throw released at `from` takes to reach `aim_point`:
## straight at it, unless it lies less than `min_ahead` m ahead of `from` along
## the aim (behind or beside the hand, e.g. a wall right in front), then along
## the aim ray itself.
static func launch_direction(from: Vector3, aim_point: Vector3, aim_direction: Vector3,
		min_ahead: float) -> Vector3:
	var to := aim_point - from
	if to.dot(aim_direction) < min_ahead or to.is_zero_approx():
		return aim_direction
	return to.normalized()


## Where an aimed beam (AttackParams.aimed_beam) starts for a player standing at
## `feet` facing `yaw`: beam_forward ahead, beam_height up (the hands, where a
## projectile is released).
static func beam_origin(feet: Vector3, yaw: float, params: Params) -> Vector3:
	return feet + Vector3(-sin(yaw), 0.0, -cos(yaw)) * params.beam_forward + Vector3.UP * params.beam_height


## The unit direction of an aimed beam from `origin` toward `aim_point` (the
## crosshair's: World.aim_point), the same rule as a throw's launch_direction.
static func beam_direction(origin: Vector3, aim_point: Vector3, ray: AimRay, params: Params) -> Vector3:
	return launch_direction(origin, aim_point, ray.direction, params.min_ahead)


## The aim yaw that makes facing_at_reach(aim_yaw, reach) = `facing` (its
## inverse): a remote player's aim yaw from its drawn facing during a beam.
static func aim_yaw_for_facing(facing: float, reach: float, params: Params) -> float:
	if reach <= 0.0 or params.shoulder_offset == 0.0:
		return facing
	return facing + atan2(params.shoulder_offset, maxf(reach, params.melee_min_reach))


## The aim point: the first thing along `ray` within `max_distance` that
## `mask` collides with, skipping `exclude` and every collider `skip` returns
## true for (the shooter, allies, the dead); nothing = the point at
## max_distance. Needs a physics space (call it during a physics step).
static func cast(space: PhysicsDirectSpaceState3D, ray: AimRay, max_distance: float, mask: int,
		exclude: Array[RID], skip: Callable) -> Vector3:
	var end := ray.point_at(max_distance)
	var query := PhysicsRayQueryParameters3D.create(ray.origin, end, mask, exclude)
	for i in 16:  # at most this many skipped bodies along the line
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return end
		if not skip.call(hit.collider):
			return hit.position
		var skipped := query.exclude
		skipped.append(hit.rid)
		query.exclude = skipped
	return end
