extends Node
## Entry point. Decides whether this process is the dedicated server or a client.
##
## The World scene is always added as /root/Main/World on both sides, because
## RPCs are matched by node path. /root/Main/Accounts (AccountService) exists
## from the start on both sides: a client logs in and chooses a character
## through it, and only then makes its World.

const WORLD_SCENE := preload("res://game/world/world.tscn")
const CONNECT_MENU_SCENE := preload("res://ui/connect_menu.tscn")
## The server's database file unless --db= says otherwise (":memory:" = a fresh
## one that's gone when the server stops: the smoke test).
const DEFAULT_DB := "user://newer_world.db"

## Frames slower than this are logged with --perf-log (ms).
const PERF_SPIKE_MS := 50.0

var _world: World
var _menu: ConnectMenu
var _accounts: AccountService
## Server: the shutdown save ran (_save_before_quitting).
var _saved_on_quit := false
## Client: connected to the server, and its tuning arrived (_enter_world needs both).
var _connected := false
var _server_tuning := false
var _perf_log := false
## --screenshot-dir: the start screens are saved too (menu_<N>.png; World saves
## the game's frames).
var _screenshot_dir := ""
var _last_menu_frame := -1
var _perf_spikes := 0
var _perf_worst_ms := 0.0
var _perf_worst_physics_ms := 0.0


func _ready() -> void:
	InputActions.register()
	_perf_log = LaunchArgs.has_flag("perf-log")
	_screenshot_dir = LaunchArgs.get_value("screenshot-dir")
	set_process(_perf_log or not _screenshot_dir.is_empty())
	var quit_after := float(LaunchArgs.get_value("quit-after", "0"))
	if quit_after > 0.0:
		_quit_after(quit_after)

	_accounts = AccountService.new()
	_accounts.name = "Accounts"
	add_child(_accounts)
	if LaunchArgs.has_flag("server") or OS.has_feature("dedicated_server"):
		_start_server()
	else:
		_start_client()


# --- Server ---

func _start_server() -> void:
	if not _accounts.server_open(LaunchArgs.get_value("db", DEFAULT_DB)):
		get_tree().quit(1)
		return
	var default_port: int = Tuning.get_value("network", "server", "port")
	var port := int(LaunchArgs.get_value("port", str(default_port)))
	var max_players: int = Tuning.get_value("network", "server", "max_players")
	var err := Net.start_server(port, max_players)
	if err != OK:
		printerr("[server] could not listen on port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	# Nothing to render, so don't spin the CPU between physics ticks.
	Engine.max_fps = Engine.physics_ticks_per_second
	print("[server] listening on UDP port %d (max %d players)" % [port, max_players])
	# Every client plays with the server's tuning (Tuning.send_to_peer).
	Net.peer_joined.connect(Tuning.send_to_peer)
	_spawn_world()


# --- Client ---

func _start_client() -> void:
	Net.connected_to_server.connect(_on_connected)
	Tuning.server_tuning_applied.connect(_on_server_tuning)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_disconnected.connect(_on_server_disconnected)
	_accounts.login_finished.connect(_on_login_finished)
	_accounts.characters_changed.connect(_on_characters_changed)
	_accounts.play_finished.connect(_on_play_finished)
	_show_menu("")
	var preview := LaunchArgs.get_value("menu-preview")
	if not preview.is_empty():
		_preview_menu(preview)
	elif LaunchArgs.has_flag("connect") or LaunchArgs.has_flag("bot"):
		_connect(_menu.get_address())


func _show_menu(status: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = CONNECT_MENU_SCENE.instantiate()
	add_child(_menu)
	var default_address: String = Tuning.get_value("network", "client", "default_address")
	_menu.set_address(LaunchArgs.get_value("address", default_address))
	_menu.set_status(status)
	_menu.connect_requested.connect(_connect)
	_menu.login_requested.connect(_accounts.login)
	_menu.create_requested.connect(_accounts.create_character)
	_menu.play_requested.connect(_accounts.play)
	_menu.logout_requested.connect(_log_out)


func _connect(address: String) -> void:
	var default_port: int = Tuning.get_value("network", "server", "port")
	var host := address
	var port := default_port
	# "host:port". More than one ":" means a bare IPv6 address with no port.
	if address.count(":") == 1:
		host = address.get_slice(":", 0)
		port = int(address.get_slice(":", 1))
	if host.is_empty() or port <= 0:
		_menu.set_status("Enter an address like 127.0.0.1 or 127.0.0.1:%d" % default_port)
		return
	_connected = false
	_server_tuning = false
	var err := Net.connect_to_server(host, port)
	if err != OK:
		_menu.set_status("Could not start connecting: %s" % error_string(err))
		return
	_menu.set_status("Connecting to %s:%d..." % [host, port], true)
	print("[client] connecting to %s:%d" % [host, port])


func _on_connected() -> void:
	print("[client] connected as peer %d" % multiplayer.get_unique_id())
	_connected = true
	if _server_tuning:
		_start_login()
	else:
		_menu.set_status("Loading the server's settings...", true)


## The server's tuning arrives right after connecting (usually just after
## _on_connected); logging in (and so the World) only starts once both have
## happened, so every params cache, and the name rules, use the server's values.
func _on_server_tuning() -> void:
	_server_tuning = true
	if _connected:
		_start_login()


## --bot logs in and picks its character by itself (AccountService.start_bot).
func _start_login() -> void:
	if _menu == null:
		return
	if LaunchArgs.has_flag("bot"):
		_menu.set_status("Logging in...", true)
		_accounts.start_bot()
	else:
		_menu.show_login()


func _on_login_finished(error: String, account_name: String, characters: Array) -> void:
	if _menu == null:
		return
	if error.is_empty():
		_menu.show_characters(account_name, characters)
	else:
		_menu.show_login(error)


func _on_characters_changed(error: String, characters: Array) -> void:
	if _menu == null:
		return
	if error.is_empty():
		_menu.show_characters("", characters, "Character made.")
	elif _menu.is_on_create_page():
		_menu.set_status(error)
	else:
		_menu.show_characters("", characters, error)


func _on_play_finished(error: String) -> void:
	if not error.is_empty():
		if _menu:
			_menu.set_status(error)
		return
	_enter_world()


## --menu-preview=login|characters|create: shows that start screen with sample
## data and never connects, to check it from --screenshot-dir frames.
func _preview_menu(page: String) -> void:
	var characters := [{"id": 1, "name": "Ashwyn", "class_id": "fighter"},
			{"id": 2, "name": "Corvane", "class_id": "mage"}]
	match page:
		"login":
			_menu.show_login()
		"characters":
			_menu.show_characters("preview", characters)
		"create":
			_menu.show_characters("preview", characters)
			_menu.show_create("Character name can't contain \"7\".")


## Back to the address screen (the server forgets the login with the connection).
func _log_out() -> void:
	Net.disconnect_from_server()
	_connected = false
	_server_tuning = false
	if _menu:
		_menu.show_connect("Logged out.")


func _enter_world() -> void:
	if _world or _menu == null:
		return
	_menu.queue_free()
	_menu = null
	_spawn_world()


func _on_connection_failed(reason: String) -> void:
	print("[client] connection failed: %s" % reason)
	_menu.set_status("Could not connect. %s" % reason)


func _on_server_disconnected() -> void:
	print("[client] disconnected from server")
	_connected = false
	_server_tuning = false
	if _menu:  # dropped while loading the server's settings
		_menu.queue_free()
		_menu = null
	if _world:
		# Remove now, not at end of frame, so a reconnect can reuse the name "World".
		remove_child(_world)
		_world.queue_free()
		_world = null
	_show_menu("Disconnected from server.")


# --- Shared ---

func _spawn_world() -> void:
	_world = WORLD_SCENE.instantiate()
	_world.name = "World"
	add_child(_world)


## --perf-log: prints every slow frame (a hitch the player would feel), with how
## long since launch, so startup lag can be told apart from steady-state lag.
func _process(delta: float) -> void:
	if not _screenshot_dir.is_empty() and _menu and Time.get_ticks_msec() / 250 != _last_menu_frame:
		_last_menu_frame = Time.get_ticks_msec() / 250
		get_viewport().get_texture().get_image().save_png(
				_screenshot_dir.path_join("menu_%04d.png" % _last_menu_frame))
	if not _perf_log:
		return
	# Time spent in the last physics step(s): the sim, hit checks, snapshots.
	_perf_worst_physics_ms = maxf(_perf_worst_physics_ms,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var ms := delta * 1000.0
	if ms < PERF_SPIKE_MS:
		return
	_perf_spikes += 1
	_perf_worst_ms = maxf(_perf_worst_ms, ms)
	print("[perf] t=%.2fs frame=%.0fms fps=%d world=%s" % [
			Time.get_ticks_msec() / 1000.0, ms, Engine.get_frames_per_second(), _world != null])


func _quit_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	_save_before_quitting()
	if _world:
		_world.print_summary()
	if multiplayer.is_server():
		_accounts.print_summary()
	if _perf_log:
		print("SUMMARY perf spikes=%d worst_ms=%.0f worst_physics_ms=%.1f" % [
				_perf_spikes, _perf_worst_ms, _perf_worst_physics_ms])
	_quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


## Disconnects cleanly first, so the server drops this player immediately.
func _quit() -> void:
	_save_before_quitting()
	Net.disconnect_from_server()
	get_tree().quit()


## Server: everyone online is written to the database before the process ends
## (--quit-after or closing the window; a killed process loses what changed
## since the last save, at most [save] interval in data/saving.cfg).
func _save_before_quitting() -> void:
	if _world and multiplayer.is_server() and not _saved_on_quit:
		_saved_on_quit = true
		_world.save_everyone()
