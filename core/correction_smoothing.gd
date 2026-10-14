class_name CorrectionSmoothing
extends RefCounted
## The local player's drawn offset after a prediction correction: when the
## server disagrees and reconciliation moves the body, the model and camera
## stay where they were drawn and glide to the body over `time` seconds instead
## of snapping. Drawing only: the sim position moves at once. Jumps longer than
## `max_distance` (a respawn, a server teleport) snap. Pure, unit tested.

## Seconds a correction takes to blend out (95% gone by then); 0 = snap.
var time := 0.1
## Meters: a bigger jump (with what's still blending) snaps instead.
var max_distance := 1.0
## Where the model is drawn relative to the body now.
var offset := Vector3.ZERO


func _init(blend_time: float = 0.1, snap_distance: float = 1.0) -> void:
	time = blend_time
	max_distance = snap_distance


## The body just moved by `jump` (new position - old) from a correction: keep
## drawing it where it was.
func add_jump(jump: Vector3) -> void:
	var total := offset - jump
	offset = total if time > 0.0 and total.length() <= max_distance else Vector3.ZERO


## Advances the blend by `delta` seconds; returns the offset to draw with.
func step(delta: float) -> Vector3:
	if time <= 0.0:
		offset = Vector3.ZERO
		return offset
	# exp(-3) ≈ 0.05: 95% blended out after `time`.
	offset *= exp(-3.0 * delta / time)
	if offset.length() < 0.001:
		offset = Vector3.ZERO
	return offset
