class_name GatherNode
extends RefCounted
## One placed gathering node: its gathers left and when a depleted one grows
## back (server state; clients only know whether it's available). Also the F
## key's rule (`interact_choice`) and which node F means (`pick`). Pure logic,
## unit tested (tests/test_gathering.gd).

## What F does (interact_choice).
enum Interact { PICKUP, GATHER, CRAFT }

## Its index under World/Map/GatherNodes (what the network sends).
var id := 0
## Its GatherNodeParams kind id.
var kind := ""
var position := Vector3.ZERO
var charges_left := 0
## Server tick it grows back on while depleted; -1 otherwise.
var respawn_tick := -1


func _init(node_id: int = 0, node_kind: String = "", at: Vector3 = Vector3.ZERO, charges: int = 0) -> void:
	id = node_id
	kind = node_kind
	position = at
	charges_left = charges


func is_available() -> bool:
	return charges_left > 0


## One gather taken from it; the last one depletes it until `tick` + respawn.
func take(tick: int, params: GatherNodeParams) -> void:
	if charges_left <= 0:
		return
	charges_left -= 1
	if charges_left == 0:
		respawn_tick = tick + params.respawn_ticks


## True on the tick a depleted node grows back (all charges again).
func step(tick: int, params: GatherNodeParams) -> bool:
	if charges_left > 0 or respawn_tick < 0 or tick < respawn_tick:
		return false
	charges_left = params.charges
	respawn_tick = -1
	return true


## Whether `from` (feet) is within `reach` m of it, horizontally.
func in_reach(from: Vector3, reach: float) -> bool:
	return Vector2(from.x - position.x, from.z - position.z).length() <= reach


## F: picks up your loot when some is in reach, else gathers the node it
## means (node_id >= 0), else opens the crafting station it means
## (station_id >= 0, CraftingStation.pick), else asks for a pickup (the server
## answers "nothing to pick up").
static func interact_choice(loot_in_reach: bool, node_id: int, station_id: int = -1) -> Interact:
	if loot_in_reach:
		return Interact.PICKUP
	if node_id >= 0:
		return Interact.GATHER
	if station_id >= 0:
		return Interact.CRAFT
	return Interact.PICKUP


## Which node F means: of the available nodes whose kind's reach covers `feet`,
## the one nearest the crosshair (smallest angle between `aim_direction` from
## `aim_origin` and the node's middle, ~0.6 m up). -1 if none. `reach_of`:
## kind id -> reach (m).
static func pick(nodes: Array[GatherNode], reach_of: Dictionary, feet: Vector3,
		aim_origin: Vector3, aim_direction: Vector3) -> int:
	var best := -1
	var best_angle := INF
	for node in nodes:
		if not node.is_available() or not node.in_reach(feet, reach_of.get(node.kind, 0.0)):
			continue
		var to := node.position + Vector3.UP * 0.6 - aim_origin
		var angle := aim_direction.angle_to(to) if to.length() > 0.001 else 0.0
		if angle < best_angle:
			best_angle = angle
			best = node.id
	return best
