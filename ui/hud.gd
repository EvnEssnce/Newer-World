class_name Hud
extends CanvasLayer
## In-game debug overlay: connection stats and controls.

@onready var _info: Label = %Info


func set_info(text: String) -> void:
	_info.text = text
