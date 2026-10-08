class_name HitFeedback
## Floating combat text ("-80", "Blocked", "Evaded", ...) over whoever was hit.
## Client only, placeholder look (to be replaced by real VFX).


static func spawn_label(parent: Node3D, height: float, damage: float, result: int) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 56
	label.outline_size = 10
	label.position = Vector3(randf_range(-0.3, 0.3), height, 0.0)
	match result:
		World.HIT_EVADED:
			label.text = "Evaded"
			label.modulate = Color(0.75, 0.9, 1.0)
		World.HIT_BLOCKED:
			label.text = "Blocked" if damage <= 0.0 else "Blocked -%d" % damage
			label.modulate = Color(0.8, 0.85, 0.9)
		World.HIT_GUARD_BROKEN:
			label.text = "Guard broken!" if damage <= 0.0 else "Guard broken! -%d" % damage
			label.modulate = Color(1.0, 0.55, 0.15)
		World.HIT_PARRIED:
			label.text = "Parried!"
			label.modulate = Color(0.55, 0.85, 1.0)
		World.HIT_DEFEATED:
			label.text = "-%d  Defeated!" % damage
			label.modulate = Color(1.0, 0.3, 0.2)
		_:
			label.text = "-%d" % damage
			label.modulate = Color(1.0, 0.85, 0.3)
	parent.add_child(label)
	var tween := label.create_tween()
	tween.set_parallel()
	tween.tween_property(label, "position:y", height + 0.8, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


## Whether a result should flash the target red.
static func flashes(result: int) -> bool:
	return result in [World.HIT_DAMAGED, World.HIT_DEFEATED, World.HIT_GUARD_BROKEN]
