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


func _init(p: ZoneParams, at: Vector3, facing: float, owner: int, extra_rearms := 0) -> void:
	params = p
	position = at
	yaw = facing
	owner_id = owner
	ticks_left = p.duration_ticks
	rearms_left = p.rearms + extra_rearms
	armed_at = p.arm_ticks


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
## within height above or below its center. A wall's box counts as its area.
func contains(point: Vector3) -> bool:
	if absf(point.y - position.y) > params.height:
		return false
	if params.wall:
		var local := _to_local(point)
		return absf(local.x) <= params.wall_width / 2.0 and absf(local.y) <= params.wall_depth / 2.0
	return Vector2(point.x - position.x, point.z - position.z).length() <= params.radius


## Walls: the fraction (0..1) along a -> b where a sphere of `radius` first
## meets the box (wall_width x wall_depth, from the ground to height), or -1 if
## it doesn't. Slab test in the wall's frame.
func blocks_segment(a: Vector3, b: Vector3, radius: float) -> float:
	if not params.wall:
		return -1.0
	var la := _to_local(a)
	var lb := _to_local(b)
	var lo := Vector3(-params.wall_width / 2.0 - radius, position.y - radius,
			-params.wall_depth / 2.0 - radius)
	var hi := Vector3(params.wall_width / 2.0 + radius, position.y + params.height + radius,
			params.wall_depth / 2.0 + radius)
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
