class_name Hud
extends CanvasLayer
## In-game overlay: stamina bar, connection stats and controls.

@onready var _info: Label = %Info
@onready var _health: ProgressBar = %Health
@onready var _stamina: ProgressBar = %Stamina
@onready var _banner: Label = %Banner


func set_info(text: String) -> void:
	_info.text = text


func set_health(value: float, max_value: float) -> void:
	_health.max_value = max_value
	_health.value = value


## Big centered message (e.g. the respawn countdown); empty hides it.
func set_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = not text.is_empty()


func set_stamina(value: float, max_value: float) -> void:
	_stamina.max_value = max_value
	_stamina.value = value
