class_name CraftingStation
extends RefCounted
## One placed crafting station (a Marker3D under World/Map/Stations; its kind is a
## [station_<kind>] of data/stations.cfg). Stations have no state: every machine
## builds the same list from the level, so a station's id (its marker index) is
## all the network sends. Also which station F means (`pick`). Pure logic, unit
## tested (tests/test_crafting.gd).

## Its index under World/Map/Stations.
var id := 0
## Its RecipeDefs.StationDef kind id.
var kind := ""
var position := Vector3.ZERO


func _init(station_id: int = 0, station_kind: String = "", at: Vector3 = Vector3.ZERO) -> void:
	id = station_id
	kind = station_kind
	position = at


## Whether `from` (feet) is within `reach` m of it, horizontally.
func in_reach(from: Vector3, reach: float) -> bool:
	return Vector2(from.x - position.x, from.z - position.z).length() <= reach


## Which station F means: of the stations whose kind's reach covers `feet`, the
## one nearest the crosshair (smallest angle between `aim_direction` from
## `aim_origin` and the station's middle, ~0.8 m up). -1 if none. `reach_of`:
## kind id -> reach (m).
static func pick(stations: Array[CraftingStation], reach_of: Dictionary, feet: Vector3,
		aim_origin: Vector3, aim_direction: Vector3) -> int:
	var best := -1
	var best_angle := INF
	for station in stations:
		if not station.in_reach(feet, reach_of.get(station.kind, 0.0)):
			continue
		var to := station.position + Vector3.UP * 0.8 - aim_origin
		var angle := aim_direction.angle_to(to) if to.length() > 0.001 else 0.0
		if angle < best_angle:
			best_angle = angle
			best = station.id
	return best
