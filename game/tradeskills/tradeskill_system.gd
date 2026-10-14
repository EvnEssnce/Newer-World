class_name TradeskillSystem
extends Node
## World/Tradeskills, on the server and every client (RPCs match by node path).
##
## Server: each player's Tradeskills (fresh on join; saved with the character
## once persistence exists). XP only ever comes from server code: gathering
## (on_gathered, connected to World/Gathering's `gathered` signal) and, later,
## crafting (add_xp). The gathering hooks read gather_time_multiplier and
## bonus_yield. Clients send nothing here.
##
## Server -> owner, reliable: _receive_skills(Tradeskills.to_dict()) on join and
## after every XP change, _receive_level_up(skill, from, to) for the feed line.
##
## Client: the local player's copy (`local`), the Tradeskills panel (P) and the
## "Mining 12 -> 13" feed line (LootHud's feed).

var defs: TradeskillDefs
var _is_client := false

# Server
var _skills: Dictionary[int, Tradeskills] = {}
var _rng := RandomNumberGenerator.new()
var _xp_granted := 0
var _level_ups := 0
var _gathers := 0
var _bonus_units := 0
var _players_tracked := 0

# Client
## The local player's tradeskills, as the server last sent them (empty before).
var local: Tradeskills
var _panel: TradeskillsPanel
var _layer: CanvasLayer
var _updates_received := 0
var _level_ups_seen := 0


func _ready() -> void:
	defs = TradeskillDefs.current()
	if multiplayer.is_server():
		_rng.randomize()
		Net.peer_left.connect(_on_peer_left)
		return
	_is_client = true
	local = Tradeskills.new(defs)
	_layer = CanvasLayer.new()
	_layer.layer = 2  # with the other panels, above the HUD
	add_child(_layer)
	_panel = TradeskillsPanel.new()
	_panel.setup(self)  # before _ready, which builds the rows from defs
	_layer.add_child(_panel)
	# For checking the panel from --screenshot-dir frames.
	if LaunchArgs.has_flag("tradeskills-panel"):
		_panel.toggle()


# --- Server ---

## A player joined: fresh tradeskills, sent to them.
func add_player(peer: int) -> void:
	_skills[peer] = Tradeskills.new(defs)
	_players_tracked += 1
	_send(peer)
	# Test-only (data/testing.cfg): a head start in every skill.
	var join_xp: int = Tuning.get_optional("testing", "tradeskills", "join_xp", 0)
	if join_xp > 0:
		for id in defs.order:
			add_xp(peer, id, join_xp)


## The gathering hook: `peer` gathered `amount` units (bonus included) of a
## `skill` node of kind `node_kind`. Grants the skill's gather XP. Server only.
func on_gathered(peer: int, skill: String, node_kind: String, amount: int) -> void:
	if _is_client or not _skills.has(peer) or not defs.is_gathering(skill):
		return
	_gathers += 1
	add_xp(peer, skill, defs.gather_xp(skill, node_kind, amount))


## Gives `peer` XP in a skill (gathering and, later, crafting); returns the
## levels gained. Sends the owner its skills, and a feed line per level-up.
## Server only.
func add_xp(peer: int, skill: String, xp: int) -> int:
	if _is_client or not _skills.has(peer) or not defs.has_skill(skill) or xp <= 0:
		return 0
	var skills := _skills[peer]
	if skills.is_capped(skill):
		return 0
	var before := skills.level(skill)
	var gained := skills.add_xp(skill, xp)
	_xp_granted += xp
	_level_ups += gained
	if _connected(peer):
		_send(peer)
		if gained > 0:
			_receive_level_up.rpc_id(peer, skill, before, skills.level(skill))
	return gained


## Fraction of a node's gather time for this player (1.0 if unknown). Server.
func gather_time_multiplier(peer: int, skill: String) -> float:
	return _skills[peer].gather_time_multiplier(skill) if _skills.has(peer) else 1.0


## Extra units for one gather by this player (rolled on the server's RNG; 0 if
## unknown). Count them in the amount passed to on_gathered. Server.
func bonus_yield(peer: int, skill: String) -> int:
	if not _skills.has(peer):
		return 0
	var bonus := _skills[peer].bonus_yield(skill, _rng)
	_bonus_units += bonus
	return bonus


## A player's level in a skill (recipes' requirements later). Server.
func level(peer: int, skill: String) -> int:
	return _skills[peer].level(skill) if _skills.has(peer) else Tradeskills.START_LEVEL


## A player's tradeskills, or null (persistence). Server.
func skills_of(peer: int) -> Tradeskills:
	return _skills.get(peer)


func _send(peer: int) -> void:
	_receive_skills.rpc_id(peer, _skills[peer].to_dict())


func _connected(peer: int) -> bool:
	return peer in multiplayer.get_peers()


func _on_peer_left(peer: int) -> void:
	_skills.erase(peer)


func print_summary() -> void:
	print("SUMMARY tradeskills players=%d tracked_now=%d gathers=%d xp_granted=%d level_ups=%d bonus_units=%d" % [
			_players_tracked, _skills.size(), _gathers, _xp_granted, _level_ups, _bonus_units])


# --- Client ---

@rpc("authority", "call_remote", "reliable")
func _receive_skills(data: Dictionary) -> void:
	local = Tradeskills.from_dict(data, defs)
	_updates_received += 1
	if _panel:
		_panel.refresh()


@rpc("authority", "call_remote", "reliable")
func _receive_level_up(skill: String, from_level: int, to_level: int) -> void:
	_level_ups_seen += 1
	var text := "%s %d → %d" % [defs.display_name(skill), from_level, to_level]
	var feed := _feed()
	if feed:
		feed.add_feed_line(text, TradeskillsPanel.LEVEL_UP_COLOR)
	else:
		print("[client] %s" % text)


## The loot feed (LootHud under World/Loot), which shows level-ups too.
func _feed() -> LootHud:
	var loot := get_parent().get_node_or_null(^"Loot")
	if loot == null:
		return null
	for child in loot.get_children():
		if child is LootHud:
			return child
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _is_client and _panel and not event.is_echo() and event.is_action_pressed(&"toggle_tradeskills"):
		_panel.toggle()


func print_client_summary() -> void:
	print("SUMMARY client=%d tradeskills updates=%d skills=%d level_ups_seen=%d" % [
			multiplayer.get_unique_id(), _updates_received, local.to_dict().size(), _level_ups_seen])
