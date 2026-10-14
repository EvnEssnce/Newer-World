class_name EnemyPath
extends RefCounted
## One enemy's route to where its brain wants to go (server): asks for a path
## around obstacles (crates, Shield Walls) and follows its corners. Pure logic:
## the path comes from `query` (EnemyNavigation.find_path on the server, a
## scripted one in tests/test_enemy_path.gd), so it never touches a scene.
##
## It asks again when the goal moved more than repath_distance from the goal of
## the current path, every repath_ticks, and when the navigation map changed
## (`version`: a Shield Wall went up or came down). With no path (navigation not
## ready yet, or no query) it steers straight at the goal, as before navigation.

## func(from: Vector3, to: Vector3) -> PackedVector3Array: corners from `from`
## to `to` (or as close as it can get). Empty = no path: go straight.
var query := Callable()
## The navigation map's version (EnemyNavigation.version, set every tick by
## Enemy); a change asks for a new path.
var version := 0
var repath_ticks := 30
var repath_distance := 1.0
var waypoint_reach := 0.3

## The corners still to walk to, without the start point; `index` is the next.
var points := PackedVector3Array()
var index := 0
## Paths asked for (server summary).
var queries := 0

var _goal := Vector3.ZERO
var _has_goal := false
var _version := 0
var _age := 0


func _init(p_query := Callable(), p_repath_ticks := 30, p_repath_distance := 1.0,
		p_waypoint_reach := 0.3) -> void:
	query = p_query
	repath_ticks = maxi(1, p_repath_ticks)
	repath_distance = p_repath_distance
	waypoint_reach = p_waypoint_reach


## One tick toward `goal` from `pos`: re-paths if needed, passes the corners it
## reached and returns the flat (x, z) vector to walk along: to the next corner,
## or straight to the goal once the path is used up (or there's none).
func steer(pos: Vector3, goal: Vector3) -> Vector2:
	_age += 1
	if _needs_path(goal):
		_repath(pos, goal)
	while index < points.size() and _flat(points[index] - pos).length() <= waypoint_reach:
		index += 1
	if index < points.size():
		return _flat(points[index] - pos)
	return _flat(goal - pos)


## True when nothing stands between it and the goal: at most the final corner
## is left (or there's no path). A swing waits for this, so a Husk walks around
## a Shield Wall instead of swinging at someone behind it.
func is_direct() -> bool:
	return points.size() - index <= 1


## True once it walked the whole path (the goal may be off the walkable area,
## e.g. a wander point inside a crate: as close as it gets).
func arrived() -> bool:
	return _has_goal and index >= points.size() and not points.is_empty()


## Forgets the path; the next steer asks for a new one.
func reset() -> void:
	points = PackedVector3Array()
	index = 0
	_has_goal = false


func _needs_path(goal: Vector3) -> bool:
	return (not _has_goal or _version != version or _age >= repath_ticks
			or _flat(goal - _goal).length() > repath_distance)


func _repath(pos: Vector3, goal: Vector3) -> void:
	_goal = goal
	_has_goal = true
	_version = version
	_age = 0
	index = 0
	points = PackedVector3Array()
	if not query.is_valid():
		return
	queries += 1
	var path: PackedVector3Array = query.call(pos, goal)
	# The first point is where it stands (snapped to the walkable area).
	if path.size() >= 2:
		points = path.slice(1)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
