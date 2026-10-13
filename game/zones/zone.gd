class_name Zone
extends RefCounted
## One ground zone or summon in the world (the AREA and SUMMON tags): where it
## is, whose it is, how long it has left, and when its effect fires. Pure logic
## (tests/test_zones.gd); ZoneSystem applies the effects on the server and
## draws it on clients. Never part of the predicted simulation.

var id := 0
var params: ZoneParams
## Center on the ground, and the owner's facing when placed (walls).
var position := Vector3.ZERO
var yaw := 0.0
var owner_id := 0
var ticks_left := 0
## Ticks since it was placed.
var age := 0
## Traps: re-arms left, and the age it (re-)armed at.
var rearms_left := 0
var armed_at := 0
var ended := false
## Size multiplier on its radius and wall width (Conflagration grows it).
var scale := 1.0
## Walls: meters across the facing and along it, this placement's (the kind's
## width/depth, except a Fire Trail strip: as long as the roll, wider under
## Gust Roll; see strip_between).
var width := 0.0
var depth := 0.0

## Meters an aim point on a surface is pulled back toward the aimer before the
## ground snap (a point on a wall's face snaps down on the near side).
const AIM_BACKOFF := 0.1


func _init(p: ZoneParams, at: Vector3, facing: float, owner: int, extra_rearms := 0) -> void:
	params = p
	position = at
	yaw = facing
	owner_id = owner
	ticks_left = p.duration_ticks
	rearms_left = p.rearms + extra_rearms
	armed_at = p.arm_ticks
	width = p.wall_width
	depth = p.wall_depth


## Where an aimed ground ability (Meteor Fall, Arrow Rain...) lands, before the
## ground snap: the crosshair's aim point if the aim ray hit something (`hit`)
## within max_range m (horizontally) of the user's feet; else (the sky, or too
## far) the point max_range m from the feet on the crosshair's line over the
## ground (the aim ray's heading, `yaw`, through its shoulder origin), at the
## feet's height. Pure (tests/test_zones.gd).
static func aimed_target(feet: Vector3, ray: AimRay, aim_point: Vector3, hit: bool, yaw: float,
		max_range: float) -> Vector3:
	var flat := Vector2(aim_point.x - feet.x, aim_point.z - feet.z)
	if hit and flat.length() <= max_range:
		return aim_point - ray.direction * AIM_BACKOFF
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var origin := Vector2(ray.origin.x - feet.x, ray.origin.z - feet.z)
	var side := origin - forward * origin.dot(forward)
	var along := sqrt(maxf(0.0, max_range * max_range - side.length_squared()))
	var point := side + forward * along
	return Vector3(feet.x + point.x, feet.y, feet.z + point.y)


## A strip from `start` to `end` (a roll): [center (between them, at start's
## height), yaw (facing along start -> end; 0 if they're the same point),
## length (horizontal meters between them)]. Pure (tests/test_zones.gd).
static func strip_between(start: Vector3, end: Vector3) -> Array:
	var flat := Vector2(end.x - start.x, end.z - start.z)
	var facing := atan2(-flat.x, -flat.y) if not flat.is_zero_approx() else 0.0
	var center := Vector3((start.x + end.x) / 2.0, start.y, (start.z + end.z) / 2.0)
	return [center, facing, flat.length()]


## A strip's (width, depth) for a roll of `length` m at `roll_speed` × the
## normal roll speed (ZoneParams.strip). Pure (tests/test_zones.gd).
static func strip_size(p: ZoneParams, length: float, roll_speed: float) -> Vector2:
	var wider := 1.0 + p.fast_roll_widen * maxf(0.0, roll_speed - 1.0)
	return Vector2(p.wall_width * wider, maxf(p.wall_depth, length))


## Advances one tick. Returns true if a pulse zone's effect fires this tick.
## Ends it when its time runs out.
func step() -> bool:
	if ended:
		return false
	age += 1
	ticks_left -= 1
	if ticks_left <= 0:
		ended = true
	if params.trigger != ZoneParams.TRIGGER_PULSE:
		return false
	var since := age - 1 - params.first_pulse_ticks
	return since >= 0 and since % params.interval_ticks == 0


## A trap that can trigger now.
func is_armed() -> bool:
	return not ended and params.trigger == ZoneParams.TRIGGER_TRAP and age >= armed_at


## A trap fired: it re-arms after arm_ticks if it has re-arms left, else ends.
func trigger() -> void:
	if rearms_left > 0:
		rearms_left -= 1
		armed_at = age + maxi(1, params.arm_ticks)
	else:
		ended = true


## True if feet at `point` stand in the zone: within radius (horizontally) and
## within height above or below its center. A wall's box counts as its area,
## and there a body of `body_radius` counts as soon as it overlaps the box: a
## wall is an upright volume, and a thin one (Flame Wall: 1.2 m deep) tested
## at the feet alone missed bodies that stood visibly in it, and let walkers
## cross between two pulses. A disc is a ground marking: the feet decide.
func contains(point: Vector3, body_radius := 0.0) -> bool:
	if absf(point.y - position.y) > params.height:
		return false
	if params.wall:
		var local := _to_local(point)
		return (absf(local.x) <= width * scale / 2.0 + body_radius
				and absf(local.y) <= depth / 2.0 + body_radius)
	return Vector2(point.x - position.x, point.z - position.z).length() <= params.radius * scale


## Walls: the fraction (0..1) along a -> b where a sphere of `radius` first
## meets the box (wall_width x wall_depth, from the ground to height), or -1 if
## it doesn't. Slab test in the wall's frame.
func blocks_segment(a: Vector3, b: Vector3, radius: float) -> float:
	if not params.wall or not params.solid:
		return -1.0
	var la := _to_local(a)
	var lb := _to_local(b)
	var lo := Vector3(-width * scale / 2.0 - radius, position.y - radius, -depth / 2.0 - radius)
	var hi := Vector3(width * scale / 2.0 + radius, position.y + params.height + radius,
			depth / 2.0 + radius)
	var from := Vector3(la.x, a.y, la.y)
	var dir := Vector3(lb.x - la.x, b.y - a.y, lb.y - la.y)
	var t_min := 0.0
	var t_max := 1.0
	for axis in 3:
		if absf(dir[axis]) < 0.000001:
			if from[axis] < lo[axis] or from[axis] > hi[axis]:
				return -1.0
			continue
		var t1 := (lo[axis] - from[axis]) / dir[axis]
		var t2 := (hi[axis] - from[axis]) / dir[axis]
		t_min = maxf(t_min, minf(t1, t2))
		t_max = minf(t_max, maxf(t1, t2))
		if t_min > t_max:
			return -1.0
	return t_min


## (x across the facing, z along it) of a world point, in the zone's frame.
func _to_local(point: Vector3) -> Vector2:
	var offset := Vector2(point.x - position.x, point.z - position.z)
	# Same frame as MeleeHitbox: forward is -Z rotated by yaw.
	return Vector2(offset.x * cos(yaw) - offset.y * sin(yaw),
			offset.x * sin(yaw) + offset.y * cos(yaw))
