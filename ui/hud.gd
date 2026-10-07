class_name Hud
extends CanvasLayer
## In-game overlay: stamina bar, connection stats and controls.

@onready var _info: Label = %Info
@onready var _stamina: ProgressBar = %Stamina


func set_info(text: String) -> void:
	_info.text = text


func set_stamina(value: float, max_value: float) -> void:
	_stamina.max_value = max_value
	_stamina.value = value
