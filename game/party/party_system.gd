class_name PartySystem
extends Node
## Parties over the network. World adds one at World/Party on the server and on
## every client (RPCs are matched by node path). Parties are not part of the
## predicted sim: nothing here touches PlayerState or the inputs.
##
## Server: owns the PartyRules. Clients send reliable requests (invite a player,
## answer an invite, leave, kick); the server validates each one (the sender has
## a player, the target exists and is within invite_range by the server's own
## positions, plus every rule in PartyRules), expires invites, and sends each
## affected client its view (PartyRules.view_for) whenever it changes. Failed
## requests get a short notice back.
## Client: sends requests from the party keys, keeps the last view the server
## sent and draws it (PartyHud, party nameplate colour). With --bot --bot-party,
## the bot invites (lower peer id) or accepts the other player, and doesn't
## attack until it's in a party.

## Bot: milliseconds between party requests (answering, or re-inviting after an
## invite was declined, failed or expired).
const BOT_REQUEST_INTERVAL_MS := 500
const BOT_REINVITE_MS := 5000

var rules := PartyRules.new()
## World/Players. Set by World before adding this node.
var players: Node3D

var _is_client := false
var _invite_range := 20.0
# Server
var _tick := 0
# Client
var _view: Dictionary = PartyRules.new().view_for(0, 0)
var _invite_deadline_msec := 0
## Set when we decline, so the invite closing doesn't also say it expired.
var _declined_from := 0
var _hud: PartyHud
var _bot := false
var _bot_next_request_msec := 0


func _ready() -> void:
	_invite_range = Tuning.get_value("party", "party", "invite_range")
	if multiplayer.is_server():
		rules = PartyRules.from_tuning()
		Net.peer_left.connect(_on_peer_left)
	else:
		_is_client = true
		_bot = LaunchArgs.has_flag("bot") and LaunchArgs.has_flag("bot-party")
		_hud = PartyHud.new()
		add_child(_hud)


func _physics_process(_delta: float) -> void:
	if _is_client:
		return
	_tick += 1
	var expired := rules.expire_invites(_tick)
	if expired > 0:
		print("[server] party: %d invite(s) expired" % expired)
		_push_views()


func _process(_delta: float) -> void:
	if not _is_client:
		return
	var local := _local_player()
	if local == null:
		return
	if _bot:
		_bot_step(local)
	_update_hud(local)


## World.are_allies. Server: authoritative. Client: knows only its own party.
func are_allies(a: int, b: int) -> bool:
	if _is_client:
		return PartyRules.allied(a, b, _view["members"])
	return rules.are_allies(a, b)


func is_member(peer: int) -> bool:
	return peer in _view["members"]


## Client: players in our party, us included (0 when not in one).
func member_count() -> int:
	return _view["members"].size()


## Bot: with --bot-party, hold attacks until the party has formed, so the bots
## never damage each other before they're allies.
func bot_may_attack() -> bool:
	return not _bot or not _view["members"].is_empty()


# --- Server ---

@rpc("any_peer", "call_remote", "reliable")
func _request_invite(target_id: int) -> void:
	var from := _sender()
	if from == 0:
		return
	var target: Player = null
	if target_id > 0:
		target = players.get_node_or_null(str(target_id)) as Player
	if target == null:
		_receive_notice.rpc_id(from, "That player isn't here.")
		return
	var inviter := players.get_node(str(from)) as Player
	if inviter.global_position.distance_to(target.global_position) > _invite_range:
		_receive_notice.rpc_id(from, "That player is too far away to invite.")
		return
	_finish(from, rules.invite(from, target_id, _tick), "%d invited %d" % [from, target_id])


@rpc("any_peer", "call_remote", "reliable")
func _request_answer(accept: bool) -> void:
	var peer := _sender()
	if peer == 0:
		return
	var inviter: int = rules.invite_for(peer).get("from", 0)
	if accept:
		var result := rules.accept(peer, _tick)
		_finish(peer, result, "%d joined %d's party %s" % [peer, inviter, rules.members(peer)])
	else:
		_finish(peer, rules.decline(peer), "%d declined %d's invite" % [peer, inviter])


@rpc("any_peer", "call_remote", "reliable")
func _request_leave() -> void:
	var peer := _sender()
	if peer != 0:
		_finish(peer, rules.leave(peer), "%d left their party" % peer)


@rpc("any_peer", "call_remote", "reliable")
func _request_kick(target_id: int) -> void:
	var peer := _sender()
	if peer != 0:
		_finish(peer, rules.kick(peer, target_id), "%d kicked %d" % [peer, target_id])


## The peer that sent this request, if it has a player in the world; else 0.
func _sender() -> int:
	if _is_client:
		return 0
	var peer := multiplayer.get_remote_sender_id()
	return peer if players.has_node(str(peer)) else 0


## After a request: log it, or tell the requester why it failed. Then send the
## new views.
func _finish(requester: int, result: int, description: String) -> void:
	if result == PartyRules.DONE:
		print("[server] party: %s" % description)
	else:
		_receive_notice.rpc_id(requester, PartyRules.MESSAGES[result])
	_push_views()


func _on_peer_left(peer_id: int) -> void:
	if rules.is_in_party(peer_id) or not rules.invite_for(peer_id).is_empty() \
			or not rules.outgoing_invites(peer_id).is_empty():
		print("[server] party: %d disconnected" % peer_id)
	rules.remove_peer(peer_id)
	# Deferred: other peers dropping in the same network poll (e.g. everyone
	# quitting at once) are still listed but can't be sent to yet.
	_push_views.call_deferred()


## Sends every client whose view changed its new view.
func _push_views() -> void:
	for peer in rules.take_dirty():
		if _is_connected(peer) and players.has_node(str(peer)):
			_receive_view.rpc_id(peer, rules.view_for(peer, _tick))


## A peer can still be listed for a moment after its connection has dropped.
func _is_connected(peer: int) -> bool:
	if peer not in multiplayer.get_peers():
		return false
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return true
	var packet_peer := enet.get_peer(peer)
	return packet_peer != null and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED


# --- Client ---

@rpc("authority", "call_remote", "reliable")
func _receive_view(view: Dictionary) -> void:
	_announce_changes(_view, view)
	_view = view
	var seconds_left: float = view["invite_ticks_left"] / float(Engine.physics_ticks_per_second)
	_invite_deadline_msec = Time.get_ticks_msec() + roundi(seconds_left * 1000.0)


@rpc("authority", "call_remote", "reliable")
func _receive_notice(text: String) -> void:
	if _hud:
		_hud.show_notice(text)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_client or _local_player() == null or event.is_echo():
		return
	if event.is_action_pressed(&"party_invite"):
		var target := _player_at_crosshair(false)
		if target:
			_request_invite.rpc_id(1, target.peer_id)
		else:
			_hud.show_notice("No player within %d m at your crosshair." % roundi(_invite_range))
	elif event.is_action_pressed(&"party_accept") and _view["invite_from"] != 0:
		_request_answer.rpc_id(1, true)
	elif event.is_action_pressed(&"party_decline") and _view["invite_from"] != 0:
		_declined_from = _view["invite_from"]
		_request_answer.rpc_id(1, false)
	elif event.is_action_pressed(&"party_leave"):
		_request_leave.rpc_id(1)
	elif event.is_action_pressed(&"party_kick"):
		var target := _player_at_crosshair(true)
		if target:
			_request_kick.rpc_id(1, target.peer_id)
		else:
			_hud.show_notice("No party member at your crosshair.")


## The other player drawn nearest the middle of the screen: within invite_range
## of us when inviting, or any party member when kicking.
func _player_at_crosshair(members_only: bool) -> Player:
	var camera := get_viewport().get_camera_3d()
	var local := _local_player()
	if camera == null or local == null:
		return null
	var center := get_viewport().get_visible_rect().size / 2.0
	var best_distance := INF
	var best: Player
	for player: Player in players.get_children():
		if player.is_local:
			continue
		if members_only and not is_member(player.peer_id):
			continue
		if not members_only and player.global_position.distance_to(local.global_position) > _invite_range:
			continue
		var chest := player.global_position + Vector3.UP
		if camera.is_position_behind(chest):
			continue
		var distance := camera.unproject_position(chest).distance_to(center)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _bot_step(local: Player) -> void:
	var now := Time.get_ticks_msec()
	if now < _bot_next_request_msec:
		return
	_bot_next_request_msec = now + BOT_REQUEST_INTERVAL_MS
	if _view["invite_from"] != 0:
		_request_answer.rpc_id(1, true)
		return
	if not _view["members"].is_empty() or not _view["outgoing"].is_empty():
		return
	var other: Player
	for player: Player in players.get_children():
		if not player.is_local and (other == null or player.global_position.distance_to(
				local.global_position) < other.global_position.distance_to(local.global_position)):
			other = player
	# Only the lower id invites, so two bots don't invite each other at once.
	if other and multiplayer.get_unique_id() < other.peer_id:
		_request_invite.rpc_id(1, other.peer_id)
		_bot_next_request_msec = now + BOT_REINVITE_MS


## Short notices for what changed between two views.
func _announce_changes(old: Dictionary, new: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	var old_members: Array = old["members"]
	var new_members: Array = new["members"]
	if old_members.is_empty() and not new_members.is_empty():
		if new["leader"] == me:
			_hud.show_notice("Party formed. You lead it.")
		else:
			_hud.show_notice("You joined %s's party." % _name(new["leader"]))
	elif not old_members.is_empty() and new_members.is_empty():
		_hud.show_notice("You are no longer in a party.")
	elif not new_members.is_empty():
		for peer: int in new_members:
			if peer not in old_members:
				_hud.show_notice("%s joined the party." % _name(peer))
		for peer: int in old_members:
			if peer not in new_members:
				_hud.show_notice("%s left the party." % _name(peer))
		if new["leader"] != old["leader"]:
			_hud.show_notice("You lead the party now." if new["leader"] == me
					else "%s leads the party now." % _name(new["leader"]))
	for peer: int in old["outgoing"]:
		if peer not in new["outgoing"] and peer not in new_members:
			_hud.show_notice("%s didn't join (declined or expired)." % _name(peer))
	var old_from: int = old["invite_from"]
	if old_from != 0 and new["invite_from"] != old_from and new_members.is_empty() \
			and old_from != _declined_from:
		_hud.show_notice("The invite from %s expired." % _name(old_from))
	if new["invite_from"] != old_from:
		_declined_from = 0


func _update_hud(local: Player) -> void:
	var members: Array = _view["members"]
	var leader: int = _view["leader"]
	var me := local.peer_id
	for player: Player in players.get_children():
		if not player.is_local:
			player.set_party_member(is_member(player.peer_id))
	var frames: Array[Dictionary] = []
	for peer: int in members:
		var member := players.get_node_or_null(str(peer)) as Player
		if peer == me or member == null:
			continue
		frames.append({"name": _name(peer), "health": member.health,
				"max_health": member.params.max_health, "leader": peer == leader})
	var title := "No party"
	var hint := "T  invite the player at your crosshair"
	if not members.is_empty():
		title = "Party  %d/%d%s" % [members.size(), _view["max_size"], "   (you lead)" if leader == me else ""]
		hint = "T invite   Del kick (crosshair)   L leave" if leader == me else "L  leave the party"
	for peer: int in _view["outgoing"]:
		title += "\nInvited %s..." % _name(peer)
	_hud.set_party(title, frames, hint)
	var invite_text := ""
	if _view["invite_from"] != 0:
		var seconds_left := maxi(0, ceili((_invite_deadline_msec - Time.get_ticks_msec()) / 1000.0))
		invite_text = "%s invites you to their party\n[Y] Join     [N] Decline     %d s" % [
				_name(_view["invite_from"]), seconds_left]
	_hud.set_invite(invite_text)


func _local_player() -> Player:
	if players == null:
		return null
	for player: Player in players.get_children():
		if player.is_local:
			return player
	return null


static func _name(peer: int) -> String:
	return "Player %d" % (peer % 10000)
