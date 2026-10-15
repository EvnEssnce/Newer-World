class_name SaveService
extends Node
## World/Saves, server only: loads a character's save when it joins and writes
## it back through Persistence (the only code that touches the database, opened
## by AccountService) from the main thread. Nothing here touches PlayerState or
## prediction.
##
## When (data/saving.cfg, the rules in SaveSchedule): a change to the build,
## bag, gear or tradeskills (the `save_changed` signals of World/Builds, Loot
## and Tradeskills) marks the character; it's written `after_change` s after
## its first unsaved change. Everyone online is written together every
## `interval` s, when they leave (Net.peer_leaving, before any system forgets
## them) and at shutdown (save_everyone, from Main).
##
## What a save holds is CharacterSave.capture of the live objects at that
## moment, so an action still under way isn't in it: a gear change being
## equipped (the item is still in the bag), a gather (nothing yielded yet) or a
## craft batch (inputs are only taken at the end). Leaving mid-craft keeps the
## inputs and loses the batch, finished pieces included.

## Set by World before it's added.
var persistence: Persistence
var players: Node
var loot: LootSystem
var tradeskills: TradeskillSystem

var schedule: SaveSchedule
## Seconds since this node started (the schedule's clock).
var _time := 0.0
## Peer -> the CharacterSave it joined with (id, account, name: what a capture
## needs that the live objects don't have).
var _online: Dictionary[int, CharacterSave] = {}
var _verbose := false
var _loads := 0
var _writes := 0
var _failed := 0
var _dropped_items := 0
var _refused_parts := 0
## Characters written, by reason.
var _saved_by: Dictionary[String, int] = {"periodic": 0, "change": 0, "leave": 0, "shutdown": 0}


func _ready() -> void:
	_verbose = LaunchArgs.has_flag("verbose")
	schedule = SaveSchedule.new(Tuning.get_value("saving", "save", "interval"),
			Tuning.get_value("saving", "save", "after_change"), 0.0)
	Net.peer_leaving.connect(_on_peer_leaving)


## The stored save of a character about to join, with items whose definition
## left data/items.cfg already removed (logged), or null if there's no
## database or it can't be read (the character then plays on defaults).
func load_character(character_id: int) -> CharacterSave:
	if persistence == null or not persistence.is_open():
		return null
	var save := persistence.load_character(character_id)
	if save == null:
		printerr("[server] couldn't load character %d: %s" % [character_id, persistence.last_error])
		return null
	var dropped := save.drop_unknown_items(ItemDatabase.current())
	if not dropped.is_empty():
		_dropped_items += dropped.size()
		print("[server] %s: dropped saved items no longer in data/items.cfg: %s" % [
				save.name, ", ".join(dropped)])
	_loads += 1
	return save


## Server (BuildService.setup_player): a saved build part the rules refused.
func note_refused(save: CharacterSave, problems: PackedStringArray) -> void:
	_refused_parts += problems.size()
	for problem in problems:
		print("[server] %s: saved build part refused, class default kept: %s" % [save.name, problem])


## A player is in the world with `save`'s objects: from now on its changes are
## saved. Logs what it came back with (the restart smoke check compares the
## fingerprint with the last save's).
func track(peer: int, save: CharacterSave) -> void:
	if save == null:
		return
	_online[peer] = save
	var now := capture(peer)
	if now:
		print("[server] loaded %s: %s fp=%s" % [save.name, now.summary_text(), now.fingerprint()])


## Something `peer`'s save holds changed (the systems' save_changed signals).
func mark_changed(peer: int) -> void:
	if _online.has(peer):
		schedule.mark_changed(peer, _time)


func _physics_process(delta: float) -> void:
	_time += delta
	if schedule.periodic_due(_time):
		_write(_online.keys(), "periodic")
		schedule.saved_everyone(_time)
		return
	var due := schedule.changes_due(_time)
	if not due.is_empty():
		_write(due, "change")
		schedule.saved(due)


func _on_peer_leaving(peer: int) -> void:
	if not _online.has(peer):
		return
	_write([peer], "leave")
	schedule.forget(peer)
	_online.erase(peer)


## Writes everyone online now (shutdown). Main calls it before quitting.
func save_everyone(reason: String = "shutdown") -> void:
	if not _online.is_empty():
		_write(_online.keys(), reason)
	schedule.saved_everyone(_time)


## The save of `peer`'s live objects now, or null if it has no player.
func capture(peer: int) -> CharacterSave:
	var joined: CharacterSave = _online.get(peer)
	var player := players.get_node_or_null(str(peer)) as Player if players else null
	if joined == null or player == null or player.build == null:
		return null
	var save := CharacterSave.capture(joined.name, player.build, loot.bag_of(peer),
			loot.equipment_of(peer), tradeskills.skills_of(peer))
	save.id = joined.id
	save.account_id = joined.account_id
	return save


## One transaction for every character in `peers`. A failure is logged and
## the marks are still cleared: the next periodic save tries again.
func _write(peers: Array, reason: String) -> void:
	var saves: Array[CharacterSave] = []
	for peer: int in peers:
		var save := capture(peer)
		if save:
			saves.append(save)
	if saves.is_empty() or persistence == null:
		return
	if not persistence.save_characters(saves):
		_failed += 1
		printerr("[server] saving %d character(s) (%s) failed: %s" % [saves.size(), reason,
				persistence.last_error])
		return
	_writes += 1
	_saved_by[reason] = _saved_by.get(reason, 0) + saves.size()
	if _verbose or reason == "leave" or reason == "shutdown":
		for save in saves:
			print("[server] saved %s (%s): %s fp=%s" % [save.name, reason, save.summary_text(),
					save.fingerprint()])


func print_summary() -> void:
	print("SUMMARY saves loads=%d writes=%d periodic=%d change=%d leave=%d shutdown=%d failed=%d dropped_items=%d refused_parts=%d" % [
			_loads, _writes, _saved_by["periodic"], _saved_by["change"], _saved_by["leave"],
			_saved_by["shutdown"], _failed, _dropped_items, _refused_parts])
