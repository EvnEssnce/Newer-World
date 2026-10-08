extends Node
## Autoload "Net": owns the ENet connection for both the server and clients.
##
## Gameplay code doesn't talk to ENet directly; it listens to these signals and
## sends RPCs through Godot's high-level multiplayer API. The server is always
## peer id 1.

signal connected_to_server
signal connection_failed(reason: String)
signal server_disconnected
## Server only.
signal peer_joined(peer_id: int)
## Server only.
signal peer_left(peer_id: int)

var is_server := false

var _connect_attempt := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_server(port: int, max_players: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	# Clients only ever talk to the server; they learn about each other from snapshots.
	(multiplayer as SceneMultiplayer).server_relay = false
	is_server = true
	return OK


func connect_to_server(host: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = false
	_connect_attempt += 1
	_start_connect_timeout(_connect_attempt)
	return OK


func disconnect_from_server() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## Round-trip time to the server in milliseconds. Client only.
func get_ping_ms() -> int:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or is_server:
		return 0
	var server := peer.get_peer(1)
	if server == null:
		return 0
	return int(server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func _start_connect_timeout(attempt: int) -> void:
	var timeout: float = Tuning.get_value("network", "client", "connect_timeout")
	await get_tree().create_timer(timeout).timeout
	var peer := multiplayer.multiplayer_peer
	if attempt != _connect_attempt or peer == null:
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		disconnect_from_server()
		connection_failed.emit("Timed out.")


## ENet's packet throttle drops unreliable packets (our inputs and snapshots)
## whenever round-trip times spike, e.g. while several clients start up at once,
## and takes seconds to recover. Lost inputs mean prediction corrections, which
## feel like lag. We send small packets at a fixed rate, so keep the throttle at
## its maximum (scale 32 = send everything): it rises at once, never falls.
func _disable_packet_throttle(packet_peer: ENetPacketPeer) -> void:
	if packet_peer:
		packet_peer.throttle_configure(5000, 32, 0)


func _on_peer_connected(peer_id: int) -> void:
	if is_server:
		var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if peer:
			_disable_packet_throttle(peer.get_peer(peer_id))
		peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if is_server:
		peer_left.emit(peer_id)


func _on_connected_to_server() -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer:
		_disable_packet_throttle(peer.get_peer(1))
	connected_to_server.emit()


func _on_connection_failed() -> void:
	disconnect_from_server()
	connection_failed.emit("No response from server.")


func _on_server_disconnected() -> void:
	disconnect_from_server()
	server_disconnected.emit()
