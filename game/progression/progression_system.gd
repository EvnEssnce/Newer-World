class_name ProgressionSystem
extends Node
## World/Progression, on the server and every client (RPCs, when they come,
## match by node path).
##
## Server: each player's Progression (the character's saved one on join, see
## add_player), read by World/Saves on every save. Nothing grants XP or sends
## anything to clients yet (build order item 4: XP from kills and gathering,
## then tree points from the levels; XP gains will need a `save_changed`
## signal connected to World/Saves like the other systems').

var defs: ProgressionDefs

# Server
var _progress: Dictionary[int, Progression] = {}
var _players_tracked := 0


func _ready() -> void:
	defs = ProgressionDefs.current()
	if multiplayer.is_server():
		Net.peer_left.connect(_on_peer_left)


## A player joined: their saved progression (`save`; null or never saved =
## level 1 everywhere). Server.
func add_player(peer: int, save: CharacterSave = null) -> void:
	_progress[peer] = save.make_progression(defs) if save else Progression.new(defs)
	_players_tracked += 1


## A player's progression, or null (persistence). Server.
func progression_of(peer: int) -> Progression:
	return _progress.get(peer)


func _on_peer_left(peer: int) -> void:
	_progress.erase(peer)


func print_summary() -> void:
	var levels := 0
	for progress in _progress.values():
		levels += progress.level()
	print("SUMMARY progression players=%d tracked_now=%d levels_now=%d" % [
			_players_tracked, _progress.size(), levels])
