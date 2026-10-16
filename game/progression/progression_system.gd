class_name ProgressionSystem
extends Node
## World/Progression, on the server and every client (RPCs match by node path).
##
## Server: each player's Progression (the character's saved one on join, see
## add_player; save_changed marks it for saving after any gain). XP only comes
## from server code: kills (on_enemy_killed, from World._damage_enemy: every
## player in Enemy.damaged_by gets the enemy's kill_xp, and its mastery_xp
## split over the weapons that dealt their damage, Progression.mastery_split)
## and gathering (on_gathered, connected to World/Gathering's `gathered`).
## points_changed tells World/Builds when a level-up raised a tree's points.
## Clients send nothing here.
##
## Server -> owner, reliable: _receive_progress(Progression.to_dict()) on join
## and after every gain, _receive_xp(xp, mastery) for the "+50 XP" feed line,
## _receive_level_up(weapon_id, from, to) per level-up ("" = the character).
##
## Client: the local player's copy (`local`): the HUD's XP bar
## (Hud.setup_progression) and the feed lines (LootHud's feed).

## The "+50 XP" feed line's color, and a level-up's.
const XP_COLOR := Color(0.75, 0.9, 0.65)
const LEVEL_UP_COLOR := Color(1.0, 0.85, 0.35)

## Server: `peer` gained XP (World/Saves marks it for saving).
signal save_changed(peer: int)
## Server: `peer`'s tree points went up (a character or mastery level-up).
signal points_changed(peer: int)

var defs: ProgressionDefs
var _is_client := false

# Server
var _progress: Dictionary[int, Progression] = {}
var _players_tracked := 0
var _kills_credited := 0
var _gathers := 0
var _xp_granted := 0
var _mastery_xp_granted := 0
var _level_ups := 0
var _mastery_level_ups := 0
var _xp_lines := 0

# Client
## The local player's progression, as the server last sent it (level 1 before).
var local: Progression
var _updates_received := 0
var _xp_lines_seen := 0
var _level_ups_seen := 0


func _ready() -> void:
	defs = ProgressionDefs.current()
	if multiplayer.is_server():
		Net.peer_left.connect(_on_peer_left)
		return
	_is_client = true
	local = Progression.new(defs)


## Test switch (data/testing.cfg [progression] full_points): every tree gets
## its full points whatever the levels.
static func full_points() -> bool:
	return Tuning.get_optional("testing", "progression", "full_points", false)


# --- Server ---

## A player joined: their saved progression (`save`; null or never saved =
## level 1 everywhere), sent to them.
func add_player(peer: int, save: CharacterSave = null) -> void:
	_progress[peer] = save.make_progression(defs) if save else Progression.new(defs)
	_players_tracked += 1
	if _connected(peer):
		_send(peer)


## A player's progression, or null (persistence, tree points). Server.
func progression_of(peer: int) -> Progression:
	return _progress.get(peer)


## An enemy died: everyone who damaged it and is still here gets its kill XP
## and mastery XP. Server.
func on_enemy_killed(enemy: Enemy) -> void:
	if _is_client:
		return
	for peer: int in enemy.damaged_by:
		if not _progress.has(peer):
			continue
		_kills_credited += 1
		grant(peer, enemy.params.kill_xp,
				Progression.mastery_split(enemy.damaged_by[peer], enemy.params.mastery_xp))


## The gathering hook: `peer` finished a gather. Server.
func on_gathered(peer: int, _skill: String, _node_kind: String, _amount: int) -> void:
	if _is_client or not _progress.has(peer):
		return
	_gathers += 1
	grant(peer, defs.gather_xp, {})


## Gives `peer` character XP and mastery XP (weapon id -> XP); sends the owner
## its progression, one feed line and a line per level-up. XP past a cap is
## dropped (and not shown). Server.
func grant(peer: int, xp: int, mastery: Dictionary[String, int]) -> void:
	var progress: Progression = _progress.get(peer)
	if progress == null:
		return
	var before := progress.to_dict()
	var level_before := progress.level()
	var shown_xp := xp if xp > 0 and progress.xp_needed() > 0 else 0
	var gained := progress.add_xp(xp)
	var shown_mastery: Dictionary[String, int] = {}
	var mastery_ups: Array[Array] = []
	for weapon_id: String in mastery:
		var from := progress.mastery_level(weapon_id)
		if mastery[weapon_id] <= 0 or progress.mastery_xp_needed(weapon_id) == 0:
			continue
		shown_mastery[weapon_id] = mastery[weapon_id]
		_mastery_xp_granted += mastery[weapon_id]
		if progress.add_mastery_xp(weapon_id, mastery[weapon_id]) > 0:
			mastery_ups.append([weapon_id, from, progress.mastery_level(weapon_id)])
	if progress.to_dict() == before:
		return
	_xp_granted += shown_xp
	_level_ups += gained
	_mastery_level_ups += mastery_ups.size()
	save_changed.emit(peer)
	if gained > 0 or not mastery_ups.is_empty():
		points_changed.emit(peer)
	if not _connected(peer):
		return
	_send(peer)
	if shown_xp > 0 or not shown_mastery.is_empty():
		_xp_lines += 1
		_receive_xp.rpc_id(peer, shown_xp, shown_mastery)
	if gained > 0:
		_receive_level_up.rpc_id(peer, "", level_before, progress.level())
	for up in mastery_ups:
		_receive_level_up.rpc_id(peer, up[0], up[1], up[2])


func _send(peer: int) -> void:
	_receive_progress.rpc_id(peer, _progress[peer].to_dict())


func _connected(peer: int) -> bool:
	return Net.is_peer_connected(peer)


func _on_peer_left(peer: int) -> void:
	_progress.erase(peer)


func print_summary() -> void:
	var levels := 0
	for progress in _progress.values():
		levels += progress.level()
	print("SUMMARY progression players=%d tracked_now=%d levels_now=%d kills_credited=%d gathers=%d xp_granted=%d mastery_xp_granted=%d level_ups=%d mastery_level_ups=%d xp_lines=%d" % [
			_players_tracked, _progress.size(), levels, _kills_credited, _gathers, _xp_granted,
			_mastery_xp_granted, _level_ups, _mastery_level_ups, _xp_lines])


# --- Client ---

@rpc("authority", "call_remote", "reliable")
func _receive_progress(data: Dictionary) -> void:
	local = Progression.from_dict(data, defs)
	_updates_received += 1


@rpc("authority", "call_remote", "reliable")
func _receive_xp(xp: int, mastery: Dictionary) -> void:
	_xp_lines_seen += 1
	_show(xp_line(xp, mastery), XP_COLOR)


@rpc("authority", "call_remote", "reliable")
func _receive_level_up(weapon_id: String, from_level: int, to_level: int) -> void:
	_level_ups_seen += 1
	_show(level_up_line(weapon_id, from_level, to_level), LEVEL_UP_COLOR)


## "+50 XP  +25 Spear  +15 Broadsword" (mastery after the character XP, by weapon
## id order).
static func xp_line(xp: int, mastery: Dictionary) -> String:
	var parts := PackedStringArray()
	if xp > 0:
		parts.append("+%d XP" % xp)
	var ids := PackedStringArray(mastery.keys())
	ids.sort()
	for id in ids:
		parts.append("+%d %s" % [mastery[id], weapon_name(id)])
	return "  ".join(parts)


## "Level 3" / "Spear mastery 4"; the line says which trees got points.
static func level_up_line(weapon_id: String, _from_level: int, to_level: int) -> String:
	if weapon_id.is_empty():
		return "Level %d: Wing tree points (K)" % to_level
	return "%s mastery %d: tree points (K)" % [weapon_name(weapon_id), to_level]


static func weapon_name(weapon_id: String) -> String:
	var params := PlayerParams.current()
	if not params.weapons.has(weapon_id):
		return weapon_id
	return params.weapon(weapon_id).display_name


func _show(text: String, color: Color) -> void:
	var feed := _feed()
	if feed:
		feed.add_feed_line(text, color)
	elif LaunchArgs.has_flag("verbose"):
		print("[client] %s" % text)


## The loot feed (LootHud under World/Loot).
func _feed() -> LootHud:
	var loot := get_parent().get_node_or_null(^"Loot")
	if loot == null:
		return null
	for child in loot.get_children():
		if child is LootHud:
			return child
	return null


func print_client_summary() -> void:
	print("SUMMARY client=%d progression updates=%d level=%d xp_lines_seen=%d level_ups_seen=%d" % [
			multiplayer.get_unique_id(), _updates_received, local.level(), _xp_lines_seen,
			_level_ups_seen])
