class_name ConnectMenu
extends CanvasLayer
## Client start screens, one at a time: the server address, then logging in
## (or making an account), the account's characters, and making a character
## with a class picker. Main drives it from the AccountService results; the
## server checks everything again, the rules here (AccountRules) only explain
## a refusal sooner. The last account name is remembered in
## user://client.cfg.

signal connect_requested(address: String)
signal login_requested(account_name: String, password: String, create: bool)
signal create_requested(character_name: String, class_id: String)
signal play_requested(character_id: int)
## Delete a character (after the second click on Delete).
signal delete_requested(character_id: int)
## Back from the login or character screen: disconnect.
signal logout_requested

const CLIENT_CFG := "user://client.cfg"
const PAGE_WIDTH := 380.0

@onready var _pages: VBoxContainer = %Pages
@onready var _status: Label = %Status

var _address: LineEdit
var _account: LineEdit
var _password: LineEdit
var _account_label: Label
var _characters: ItemList
var _empty_label: Label
var _play_button: Button
var _new_button: Button
## Delete: the first click arms it for the selected character, the second deletes.
var _delete_button: Button
var _delete_armed_id := 0
var _character_names: Array[String] = []
## The status line to show when the server accepts the last request.
var _success_text := ""
var _character_name: LineEdit
var _class_picker: OptionButton
var _class_ids := PackedStringArray()
var _character_ids: Array[int] = []
var _character_count := 0
## Every input and button of each page (disabled while waiting on the server).
var _controls: Dictionary[String, Array] = {}
var _page := ""


func _ready() -> void:
	_build_connect_page()
	_build_login_page()
	_build_characters_page()
	_build_create_page()
	_show_page("connect")


# --- Called by Main ---

func get_address() -> String:
	return _address.text.strip_edges()


func set_address(address: String) -> void:
	_address.text = address


func set_status(text: String, busy: bool = false) -> void:
	_status.text = text
	_status.visible = not text.is_empty()
	for control: Control in _controls.get(_page, []):
		if control is LineEdit:
			control.editable = not busy
		elif control is BaseButton:
			control.disabled = busy
		elif control is ItemList:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE if busy else Control.MOUSE_FILTER_STOP
	if not busy and _page == "characters":
		_update_character_buttons()


func show_connect(status: String = "") -> void:
	_show_page("connect")
	set_status(status)


func show_login(status: String = "") -> void:
	_show_page("login")
	if _account.text.is_empty():
		_account.text = _remembered_account()
	_password.text = ""
	set_status(status)
	(_password if not _account.text.is_empty() else _account).grab_focus()


func show_characters(account_name: String, characters: Array, status: String = "") -> void:
	if not account_name.is_empty():
		_account_label.text = "Account: %s" % account_name
		_remember_account(account_name)
	_characters.clear()
	_character_ids.clear()
	_character_names.clear()
	_delete_armed_id = 0
	for entry: Dictionary in characters:
		var class_def := ClassDef.for_id(str(entry["class_id"]))
		var class_name_text := class_def.display_name if class_def else str(entry["class_id"])
		_characters.add_item("%s   %s" % [entry["name"], class_name_text])
		_character_ids.append(int(entry["id"]))
		_character_names.append(str(entry["name"]))
	_character_count = characters.size()
	if _character_count > 0:
		_characters.select(_character_count - 1 if _page == "create" else 0)
	_empty_label.visible = _character_count == 0
	_characters.visible = _character_count > 0
	_show_page("characters")
	set_status(status)


func show_create(status: String = "") -> void:
	_show_page("create")
	_character_name.text = ""
	set_status(status)
	_character_name.grab_focus()


func is_on_create_page() -> bool:
	return _page == "create"


# --- Pages ---

func _build_connect_page() -> void:
	var page := _new_page("connect")
	page.add_child(_label("Server address"))
	_address = _line_edit("127.0.0.1 or host:port")
	_address.text_submitted.connect(func(_text: String) -> void: _request_connect())
	page.add_child(_address)
	var button := _button("Connect", _request_connect)
	page.add_child(button)
	# To compare with the host's when the server turns this build away.
	var version := _label("Game version %s" % CodeVersion.current())
	version.modulate = Color(1, 1, 1, 0.5)
	page.add_child(version)
	_controls["connect"] = [_address, button]


func _build_login_page() -> void:
	var page := _new_page("login")
	page.add_child(_label("Account name"))
	_account = _line_edit("")
	_account.text_submitted.connect(func(_text: String) -> void: _password.grab_focus())
	page.add_child(_account)
	page.add_child(_label("Password"))
	_password = _line_edit("")
	_password.secret = true
	_password.text_submitted.connect(func(_text: String) -> void: _request_login(false))
	page.add_child(_password)
	var log_in := _button("Log in", func() -> void: _request_login(false))
	var create := _button("Create account", func() -> void: _request_login(true))
	var back := _button("Disconnect", func() -> void: logout_requested.emit())
	page.add_child(_row([log_in, create]))
	page.add_child(back)
	_controls["login"] = [_account, _password, log_in, create, back]


func _build_characters_page() -> void:
	var page := _new_page("characters")
	_account_label = _label("")
	_account_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	page.add_child(_account_label)
	page.add_child(_label("Characters"))
	_characters = ItemList.new()
	_characters.custom_minimum_size = Vector2(PAGE_WIDTH, 160)
	_characters.item_activated.connect(func(_index: int) -> void: _request_play())
	_characters.item_selected.connect(func(_index: int) -> void:
		_delete_armed_id = 0
		_update_character_buttons())
	page.add_child(_characters)
	_empty_label = _label("No characters yet. Make one to play.")
	page.add_child(_empty_label)
	_play_button = _button("Play", _request_play)
	_new_button = _button("New character", func() -> void: show_create())
	_delete_button = _button("Delete", _request_delete)
	var log_out := _button("Log out", func() -> void: logout_requested.emit())
	page.add_child(_row([_play_button, _new_button]))
	page.add_child(_row([_delete_button, log_out]))
	_controls["characters"] = [_characters, _play_button, _new_button, _delete_button, log_out]


func _build_create_page() -> void:
	var page := _new_page("create")
	page.add_child(_label("Character name"))
	_character_name = _line_edit("")
	_character_name.text_submitted.connect(func(_text: String) -> void: _request_create())
	page.add_child(_character_name)
	page.add_child(_label("Class"))
	_class_picker = OptionButton.new()
	page.add_child(_class_picker)
	var create := _button("Create", _request_create)
	var back := _button("Back", _back_to_characters)
	page.add_child(_row([create, back]))
	_controls["create"] = [_character_name, _class_picker, create, back]


## Class names come from the tuning (the server's), so fill the picker on show.
func _fill_class_picker() -> void:
	var previous := _class_ids[_class_picker.selected] if _class_picker.selected >= 0 \
			and _class_picker.selected < _class_ids.size() else LaunchArgs.get_value("class", ClassDef.DEFAULT_CLASS)
	_class_picker.clear()
	_class_ids = ClassDef.all_ids()
	for class_id in _class_ids:
		var class_def := ClassDef.for_id(class_id)
		_class_picker.add_item(class_def.display_name if class_def else class_id)
	var index := _class_ids.find(previous)
	_class_picker.select(maxi(0, index))


func _back_to_characters() -> void:
	_show_page("characters")
	set_status("")


func _show_page(page_name: String) -> void:
	_page = page_name
	for page in _pages.get_children():
		page.visible = page.name == page_name
	if page_name == "create":
		_fill_class_picker()


func _update_character_buttons() -> void:
	_play_button.disabled = _characters.get_selected_items().is_empty()
	_delete_button.disabled = _play_button.disabled
	var selected := _characters.get_selected_items()
	var armed := _delete_armed_id != 0 and not selected.is_empty()
	_delete_button.text = "Delete %s for good?" % _character_names[selected[0]] if armed else "Delete"
	var rules := AccountRules.from_tuning()
	_new_button.disabled = not rules.character_count_error(_character_count).is_empty()


# --- Requests ---

func _request_connect() -> void:
	connect_requested.emit(get_address())


func _request_login(create: bool) -> void:
	var account_name := _account.text.strip_edges()
	var rules := AccountRules.from_tuning()
	var error := ""
	if account_name.is_empty() or _password.text.is_empty():
		error = "Enter an account name and a password."
	elif create:
		error = rules.account_name_error(account_name)
		if error.is_empty():
			error = rules.password_error(_password.text)
	if not error.is_empty():
		set_status(error)
		return
	set_status("Creating the account..." if create else "Logging in...", true)
	login_requested.emit(account_name, _password.text, create)


func _request_create() -> void:
	var character_name := _character_name.text.strip_edges()
	var error := AccountRules.from_tuning().character_name_error(character_name)
	if error.is_empty() and _class_ids.is_empty():
		error = "No classes to pick from."
	if not error.is_empty():
		set_status(error)
		return
	_success_text = "Character made."
	set_status("Making %s..." % character_name, true)
	create_requested.emit(character_name, _class_ids[_class_picker.selected])


## First click: asks again on the button. Second click on the same character:
## asks the server to delete it.
func _request_delete() -> void:
	var selected := _characters.get_selected_items()
	if selected.is_empty():
		return
	var id := _character_ids[selected[0]]
	if _delete_armed_id != id:
		_delete_armed_id = id
		_update_character_buttons()
		return
	_delete_armed_id = 0
	_success_text = "%s was deleted." % _character_names[selected[0]]
	set_status("Deleting %s..." % _character_names[selected[0]], true)
	delete_requested.emit(id)


## What to say when the server accepts the last create or delete request.
func success_text() -> String:
	return _success_text


func _request_play() -> void:
	var selected := _characters.get_selected_items()
	if selected.is_empty():
		return
	set_status("Entering the world...", true)
	play_requested.emit(_character_ids[selected[0]])


# --- Remembered account name ---

func _remembered_account() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CLIENT_CFG) != OK:
		return ""
	return str(cfg.get_value("login", "account", ""))


func _remember_account(account_name: String) -> void:
	if LaunchArgs.has_flag("bot"):
		return
	var cfg := ConfigFile.new()
	cfg.load(CLIENT_CFG)
	cfg.set_value("login", "account", account_name)
	cfg.save(CLIENT_CFG)


# --- Widgets ---

func _new_page(page_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = page_name
	page.add_theme_constant_override("separation", 8)
	page.custom_minimum_size.x = PAGE_WIDTH
	_pages.add_child(page)
	return page


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _line_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	return edit


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for button: Button in buttons:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	return row
