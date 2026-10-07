extends Node
## Entry point. Decides whether this process is the dedicated server or a client.
##
## The World scene is always added as /root/Main/World on both sides, because
## RPCs are matched by node path.

const WORLD_SCENE := preload("res://game/world/world.tscn")
const CONNECT_MENU_SCENE := preload("res://ui/connect_menu.tscn")

var _world: World
var _menu: ConnectMenu


func _ready() -> void:
	InputActions.register()
	var quit_after := float(LaunchArgs.get_value("quit-after", "0"))
	if quit_after > 0.0:
		_quit_after(quit_after)

	if LaunchArgs.has_flag("server") or OS.has_feature("dedicated_server"):
		_start_server()
	else:
		_start_client()


# --- Server ---

func _start_server() -> void:
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
	_spawn_world()


# --- Client ---

func _start_client() -> void:
	Net.connected_to_server.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_disconnected.connect(_on_server_disconnected)
	_show_menu("")
	if LaunchArgs.has_flag("connect") or LaunchArgs.has_flag("bot"):
		_connect(_menu.get_address())


func _show_menu(status: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = CONNECT_MENU_SCENE.instantiate()
	add_child(_menu)
	var default_address: String = Tuning.get_value("network", "client", "default_address")
	_menu.set_address(LaunchArgs.get_value("address", default_address))
	_menu.set_status(status)
	_menu.connect_requested.connect(_connect)


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
	var err := Net.connect_to_server(host, port)
	if err != OK:
		_menu.set_status("Could not start connecting: %s" % error_string(err))
		return
	_menu.set_status("Connecting to %s:%d..." % [host, port], true)
	print("[client] connecting to %s:%d" % [host, port])


func _on_connected() -> void:
	print("[client] connected as peer %d" % multiplayer.get_unique_id())
	_menu.queue_free()
	_menu = null
	_spawn_world()


func _on_connection_failed(reason: String) -> void:
	print("[client] connection failed: %s" % reason)
	_menu.set_status("Could not connect. %s" % reason)


func _on_server_disconnected() -> void:
	print("[client] disconnected from server")
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


func _quit_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if _world:
		_world.print_summary()
	_quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


## Disconnects cleanly first, so the server drops this player immediately.
func _quit() -> void:
	Net.disconnect_from_server()
	get_tree().quit()
