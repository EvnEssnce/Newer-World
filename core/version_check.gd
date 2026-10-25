class_name VersionCheck
extends Node
## /root/Main/VersionCheck on the server and every client: a client on other
## code than the server's (CodeVersion) is turned away with a message, before
## anything else is sent, instead of failing oddly later.
##
## A client says _hello(version) as it connects. The server answers a match by
## emitting peer_verified (Main sends the tuning then, and login only works
## for a verified peer: AccountService) and a mismatch with
## _refused(server_version), then disconnects it. A connection that says
## nothing for [server] version_timeout s (data/network.cfg; a build from
## before this check) is disconnected.
##
## Never change this node's path, its RPCs or their arguments: every build,
## old or new, must still reach them for the check to work.

## Server: `peer` runs the server's code; send it the tuning.
signal peer_verified(peer: int)
## Client: the server runs other code (`server_version`); it disconnects next.
signal refused(server_version: String)

## Server: peers that haven't said hello yet, and when they must have (msec).
var _pending: Dictionary[int, int] = {}
var _verified: Dictionary[int, bool] = {}
var _accepted := 0
var _refused_count := 0
var _timed_out := 0


func _ready() -> void:
	set_process(false)


## Server: starts checking every peer that connects.
func server_start() -> void:
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	print("[server] code version %s" % CodeVersion.current())


## Server: whether `peer` said hello with the server's version.
func is_verified(peer: int) -> bool:
	return _verified.has(peer)


func print_summary() -> void:
	print("SUMMARY version code=%s accepted=%d refused=%d timed_out=%d" % [
			CodeVersion.current(), _accepted, _refused_count, _timed_out])


## Client: call once connected.
func client_connected() -> void:
	_hello.rpc_id(1, CodeVersion.current())


func _on_peer_joined(peer: int) -> void:
	var timeout: float = Tuning.get_value("network", "server", "version_timeout")
	_pending[peer] = Time.get_ticks_msec() + int(timeout * 1000.0)
	set_process(true)


func _on_peer_left(peer: int) -> void:
	_pending.erase(peer)
	_verified.erase(peer)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for peer: int in _pending.keys():
		if now >= _pending[peer]:
			_pending.erase(peer)
			_timed_out += 1
			print("[server] peer %d never said its code version (a build from before the check?): disconnected" % peer)
			_disconnect(peer)
	set_process(not _pending.is_empty())


## After what's queued for it (the refusal) has been sent.
func _disconnect(peer: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var packet_peer := enet.get_peer(peer) if enet else null
	if packet_peer:
		packet_peer.peer_disconnect_later()
	elif multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.disconnect_peer(peer)


@rpc("any_peer", "call_remote", "reliable")
func _hello(version: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _pending.has(peer):
		return
	_pending.erase(peer)
	if version == CodeVersion.current():
		_verified[peer] = true
		_accepted += 1
		peer_verified.emit(peer)
		return
	_refused_count += 1
	print("[server] peer %d runs code version %s, not %s: refused" % [
			peer, version.left(40), CodeVersion.current()])
	_refused.rpc_id(peer, CodeVersion.current())
	_disconnect(peer)


@rpc("authority", "call_remote", "reliable")
func _refused(server_version: String) -> void:
	refused.emit(server_version)
