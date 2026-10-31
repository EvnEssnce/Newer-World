class_name Interest
extends RefCounted
## Interest management: which players and enemies each client's snapshots
## carry. Only what's near the viewer (horizontal distance), so the snapshot
## stays one packet however many players and camps a map holds. Pure logic,
## unit tested (tests/test_interest.gd); World uses one on the server.
##
## Hysteresis: an entity comes into view within enter_radius and stays until
## it's past exit_radius, so nothing flickers at the edge. Entities in
## `always` (the viewer itself, its party members) are always in view.
##
## Ids are peer ids for players and enemy ids (< 0) for enemies: one id space.

var enter_radius := 0.0
var exit_radius := 0.0
## Viewer peer id -> {entity id: true} in view after the last update.
var _in_view: Dictionary[int, Dictionary] = {}


func _init(enter: float = 0.0, exit: float = 0.0) -> void:
	enter_radius = enter
	exit_radius = maxf(enter, exit)


## The ids of `entities` (id -> position) that `viewer` (a peer id, standing at
## viewer_pos) sees this snapshot, in the order given; remembers them for the
## next call. An enter_radius of 0 or less means everything (off).
func update(viewer: int, viewer_pos: Vector3, entities: Dictionary, always: Array = []) -> Array[int]:
	var before: Dictionary = _in_view.get(viewer, {})
	var now := {}
	var result: Array[int] = []
	for id: int in entities:
		if enter_radius <= 0.0 or id in always or _near(viewer_pos, entities[id],
				exit_radius if before.has(id) else enter_radius):
			now[id] = true
			result.append(id)
	_in_view[viewer] = now
	return result


## True if `id` was in viewer's last update.
func sees(viewer: int, id: int) -> bool:
	return _in_view.get(viewer, {}).has(id)


## A viewer left: forget what it saw.
func forget(viewer: int) -> void:
	_in_view.erase(viewer)


static func _near(a: Vector3, b: Vector3, radius: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= radius
