@tool
class_name TerrainShape
extends RefCounted
## A map's ground: a square height grid built from rolling noise, hand-placed
## hills, mountains along the edge and flattened areas (town, camps, spawn
## points), plus the colours of its low-poly triangles. Pure maths (Terrain
## turns it into a mesh and a collision shape), the same on every machine:
## no sin/cos/exp (library functions can differ by platform), and every
## vertex height is rounded to 1/64 m, so a server and its clients build the
## same triangles and prediction stays exact.
##
## The grid covers x and z from -size/2 to size/2 in cells of `cell` meters.
## Each cell is two triangles split along its (x0, z0)-(x1, z1) diagonal;
## surface_height interpolates exactly the triangle the collision shape has.

## Vertex heights are multiples of this (meters).
const QUANTUM := 1.0 / 64.0

## Meters along each side.
var size := 400.0
## Meters per grid cell.
var cell := 4.0
var noise_seed := 1
## Meters: the rolling noise goes from -amplitude to +amplitude (about).
var noise_amplitude := 4.0
## Meters between noise hills (roughly).
var noise_wavelength := 90.0
## Meters from the centre (along x or z, whichever is farther) where the edge
## mountains start rising, and how high they get at the edge.
var edge_start := 170.0
var edge_height := 40.0
## Hills: [Vector2 centre, radius (m), height (m; negative = a hollow)].
var hills: Array = []
## Flat areas: [Vector2 centre, radius (m), blend (m of slope around it),
## height (m; NAN = the ground's own height at its centre, before any flat),
## ground ("grass", "dirt" or "stone": its colour)].
var flats: Array = []
## Roads (colour only): [PackedVector2Array points, width (m)].
var roads: Array = []

var _noise: FastNoiseLite
var _detail: FastNoiseLite
var _heights := PackedFloat32Array()
## Each flat's height (an automatic one worked out), by index.
var _levels := PackedFloat32Array()
var _count := 0


## Cells along each side.
func cells() -> int:
	return maxi(1, roundi(size / cell))


## Computes every vertex height. Call after setting the fields (again after
## changing them).
func build() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = noise_seed
	_noise.frequency = 1.0 / maxf(noise_wavelength, 1.0)
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_detail = FastNoiseLite.new()
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.seed = noise_seed + 7
	_detail.frequency = 1.0 / 23.0
	_count = cells() + 1
	_levels.clear()
	for flat: Array in flats:
		var level := float(flat[3])
		if is_nan(level):
			var centre: Vector2 = flat[0]
			level = _unflattened(centre.x, centre.y)
		_levels.append(quantize(level))
	_heights.resize(_count * _count)
	for iz in _count:
		for ix in _count:
			var p := vertex_xz(ix, iz)
			_heights[iz * _count + ix] = quantize(raw_height(p.x, p.y))


## The x/z of grid vertex (ix, iz).
func vertex_xz(ix: int, iz: int) -> Vector2:
	var half := size / 2.0
	return Vector2(-half + ix * cell, -half + iz * cell)


## Height of grid vertex (ix, iz) (after build()).
func vertex_height(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, _count - 1)
	iz = clampi(iz, 0, _count - 1)
	return _heights[iz * _count + ix]


static func quantize(h: float) -> float:
	return roundf(h / QUANTUM) * QUANTUM


static func smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## The height function before rounding: noise, hills, edge mountains, then
## the flats pulled level over it.
func raw_height(x: float, z: float) -> float:
	var h := _unflattened(x, z)
	# Last to first: an earlier flat is levelled last, so it wins an overlap.
	for i in range(flats.size() - 1, -1, -1):
		var flat: Array = flats[i]
		var d: float = (Vector2(x, z) - flat[0]).length()
		var w := 1.0 - smooth((d - float(flat[1])) / maxf(float(flat[2]), 0.01))
		h = lerpf(h, _levels[i], w)
	return h


## A flat's height (after build()).
func flat_height(index: int) -> float:
	return _levels[index]


func _unflattened(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * noise_amplitude * 1.6
	for hill: Array in hills:
		var d: float = (Vector2(x, z) - hill[0]).length()
		h += float(hill[2]) * smooth(1.0 - d / maxf(float(hill[1]), 0.01))
	var edge := maxf(absf(x), absf(z))
	var rise := smooth((edge - edge_start) / maxf(size / 2.0 - edge_start, 0.01))
	h += edge_height * rise * (0.7 + 0.3 * (_detail.get_noise_2d(x, z) + 1.0))
	return h


## The ground height at (x, z): exactly the collision surface (the triangle
## the point is over). Outside the grid: the nearest edge vertex row.
func surface_height(x: float, z: float) -> float:
	var half := size / 2.0
	var gx := clampf((x + half) / cell, 0.0, float(_count - 1))
	var gz := clampf((z + half) / cell, 0.0, float(_count - 1))
	var ix := mini(int(gx), _count - 2)
	var iz := mini(int(gz), _count - 2)
	var fx := gx - ix
	var fz := gz - iz
	var h00 := vertex_height(ix, iz)
	var h11 := vertex_height(ix + 1, iz + 1)
	if fx >= fz:
		var h10 := vertex_height(ix + 1, iz)
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	var h01 := vertex_height(ix, iz + 1)
	return h00 + (h11 - h01) * fx + (h01 - h00) * fz


## The up-facing normal of the triangle under (x, z).
func surface_normal(x: float, z: float) -> Vector3:
	var e := 0.05
	var dx := surface_height(x + e, z) - surface_height(x - e, z)
	var dz := surface_height(x, z + e) - surface_height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## Every triangle, three vertices each, wound so the top faces up (Godot's
## front faces): for the collision shape and the mesh.
func faces() -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := cells()
	out.resize(n * n * 6)
	var i := 0
	for iz in n:
		for ix in n:
			var p00 := _vertex(ix, iz)
			var p10 := _vertex(ix + 1, iz)
			var p01 := _vertex(ix, iz + 1)
			var p11 := _vertex(ix + 1, iz + 1)
			out[i] = p00
			out[i + 1] = p10
			out[i + 2] = p11
			out[i + 3] = p00
			out[i + 4] = p11
			out[i + 5] = p01
			i += 6
	return out


func _vertex(ix: int, iz: int) -> Vector3:
	var p := vertex_xz(ix, iz)
	return Vector3(p.x, vertex_height(ix, iz), p.y)


## Which flat (index) covers (x, z) at its full height, or -1.
func flat_at(x: float, z: float) -> int:
	for i in flats.size():
		if (Vector2(x, z) - flats[i][0]).length() <= float(flats[i][1]):
			return i
	return -1


## Meters from (x, z) to the nearest road's centre line minus half its width
## (negative = on a road). INF without roads.
func road_distance(x: float, z: float) -> float:
	var best := INF
	var p := Vector2(x, z)
	for road: Array in roads:
		var points: PackedVector2Array = road[0]
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, (p - (a + ab * t)).length() - float(road[1]) / 2.0)
	return best


## The colour of a triangle centred on `c` with face normal `normal`: rock on
## steep slopes and high up, dirt on roads and dirt flats, paving on stone
## flats, else grass with a little variation.
func triangle_color(c: Vector3, normal: Vector3) -> Color:
	var flat := flat_at(c.x, c.z)
	if flat >= 0:
		match String(flats[flat][4]):
			"stone":
				return Color(0.47, 0.45, 0.42).lerp(Color(0.41, 0.39, 0.37), _variation(c))
			"dirt":
				return Color(0.5, 0.42, 0.3).lerp(Color(0.45, 0.38, 0.27), _variation(c))
	if road_distance(c.x, c.z) <= 0.0:
		return Color(0.52, 0.44, 0.32).lerp(Color(0.47, 0.4, 0.29), _variation(c))
	if normal.y < 0.78 or c.y > 18.0:
		return Color(0.4, 0.39, 0.37).lerp(Color(0.33, 0.32, 0.31), _variation(c))
	var grass := Color(0.36, 0.52, 0.3).lerp(Color(0.42, 0.56, 0.31), _variation(c))
	if normal.y < 0.9:
		grass = grass.lerp(Color(0.45, 0.44, 0.38), 0.4)
	return grass


func _variation(c: Vector3) -> float:
	return (_detail.get_noise_2d(c.x * 3.1, c.z * 3.1) + 1.0) / 2.0
