class_name ConnectMenu
extends CanvasLayer
## Client start screen: enter a server address and connect.

signal connect_requested(address: String)

@onready var _address: LineEdit = %Address
@onready var _connect_button: Button = %ConnectButton
@onready var _status: Label = %Status


func _ready() -> void:
	_connect_button.pressed.connect(_request_connect)
	_address.text_submitted.connect(func(_text: String) -> void: _request_connect())


func get_address() -> String:
	return _address.text.strip_edges()


func set_address(address: String) -> void:
	_address.text = address


func set_status(text: String, busy: bool = false) -> void:
	_status.text = text
	_status.visible = not text.is_empty()
	_connect_button.disabled = busy
	_address.editable = not busy


func _request_connect() -> void:
	connect_requested.emit(get_address())
