class_name InputActions
## Gameplay key bindings, registered in code so they live in one readable place
## instead of the project.godot input map.

const KEY_BINDINGS: Dictionary[StringName, Array] = {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"jump": [KEY_SPACE],
	&"dodge": [KEY_SHIFT],
	&"toggle_hitboxes": [KEY_F3],
	# Party (PartySystem). Invite/kick target the player nearest the crosshair.
	&"party_invite": [KEY_T],
	&"party_accept": [KEY_Y],
	&"party_decline": [KEY_N],
	&"party_leave": [KEY_L],
	&"party_kick": [KEY_DELETE],
}

const MOUSE_BINDINGS: Dictionary[StringName, Array] = {
	# Tap for a light attack, hold for a heavy attack.
	&"attack": [MOUSE_BUTTON_LEFT],
	&"block": [MOUSE_BUTTON_RIGHT],
}


static func register() -> void:
	for action: StringName in KEY_BINDINGS:
		for key: Key in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			_add(action, event)
	for action: StringName in MOUSE_BINDINGS:
		for button: MouseButton in MOUSE_BINDINGS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			_add(action, event)


static func _add(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, event)
