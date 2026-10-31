@tool
class_name DecorScatter
extends RefCounted
## Where a map's trees and rocks stand: seeded, so every machine places the
## same ones (their trunks and rocks collide, so prediction needs them
## identical). Pure, unit tested. No trig: positions and sizes only (a model's
## turn around its trunk is cosmetic and left to the visual).
##
## Each result is a Vector4: x, y (the ground under it), z, scale.

## Meters: where a tree may grow, a noise above `threshold` makes forests;
## within `boost_radius` of a boost point (a wood node) the threshold drops by
## `boost`, so wood nodes stand in woods.
var forest_wavelength := 70.0
var threshold := 0.15
var boost_points := PackedVector2Array()
var boost_radius := 28.0
var boost := 0.5
## Keep-out circles: Vector3(x, z, radius) (camps, nodes, spawn points...).
var keep_out: Array[Vector3] = []
## Meters kept clear on each side of a road, beyond its edge.
var road_margin := 2.0
## Flats are kept clear out to radius + blend × this.
var flat_margin := 0.5
## Steepest ground (the surface normal's y must be at least this).
var min_normal_y := 0.8
## Meters between two placed things (times the larger one's scale).
var spacing := 3.0
## Meters from the map's edge kept clear.
var edge_margin := 6.0


## `count` trees (or as many as fit in count × 8 tries) on `shape`, seeded.
## With `use_forest` false, density is even (rocks).
func scatter(shape: TerrainShape, seed_value: int, count: int, min_scale: float,
		max_scale: float, use_forest := true) -> Array[Vector4]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var forest := FastNoiseLite.new()
	forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest.seed = seed_value
	forest.frequency = 1.0 / maxf(forest_wavelength, 1.0)
	var half := shape.size / 2.0 - edge_margin
	var out: Array[Vector4] = []
	var tries := count * 8
	while out.size() < count and tries > 0:
		tries -= 1
		var x := TerrainShape.quantize(rng.randf_range(-half, half))
		var z := TerrainShape.quantize(rng.randf_range(-half, half))
		var scale := TerrainShape.quantize(rng.randf_range(min_scale, max_scale))
		if use_forest and forest.get_noise_2d(x, z) < _threshold_at(x, z):
			continue
		if not allowed(shape, x, z, scale, out):
			continue
		out.append(Vector4(x, shape.surface_height(x, z), z, scale))
	return out


## Whether something of `scale` may stand at (x, z), given what's `placed`.
func allowed(shape: TerrainShape, x: float, z: float, scale: float,
		placed: Array[Vector4]) -> bool:
	if shape.surface_normal(x, z).y < min_normal_y:
		return false
	if shape.road_distance(x, z) < road_margin:
		return false
	var p := Vector2(x, z)
	for flat: Array in shape.flats:
		if (p - (flat[0] as Vector2)).length() < float(flat[1]) + float(flat[2]) * flat_margin:
			return false
	for circle in keep_out:
		if (p - Vector2(circle.x, circle.y)).length() < circle.z:
			return false
	for other in placed:
		if (p - Vector2(other.x, other.z)).length() < spacing * maxf(scale, other.w):
			return false
	return true


func _threshold_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	for point in boost_points:
		if (p - point).length() < boost_radius:
			return threshold - boost
	return threshold
