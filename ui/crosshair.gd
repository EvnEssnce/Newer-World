class_name Crosshair
extends Control
## The aim crosshair, drawn in code at the screen centre: the camera looks along
## the aim ray (AimRay), so that's always where the aim point is. Four short
## ticks around a dot, outlined so it reads on sky and ground. Hidden while a
## `modal_ui` panel (K, I) is open.

const COLOR := Color(1.0, 1.0, 1.0, 0.9)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.6)
## Pixels: tick length, gap from the centre, line width, centre dot radius.
const TICK := 7.0
const GAP := 4.0
const WIDTH := 2.0
const DOT := 1.5


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var hide_it := false
	for node in get_tree().get_nodes_in_group(&"modal_ui"):
		if node is CanvasItem and node.visible:
			hide_it = true
			break
	if visible == hide_it:
		visible = not hide_it


func _draw() -> void:
	var c := size / 2.0
	for pass_i in 2:
		var color := OUTLINE if pass_i == 0 else COLOR
		var w := WIDTH + 2.0 if pass_i == 0 else WIDTH
		var extra := 1.0 if pass_i == 0 else 0.0
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + dir * (GAP - extra), c + dir * (GAP + TICK + extra), color, w)
		draw_circle(c, DOT + extra, color)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
