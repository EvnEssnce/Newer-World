class_name PlayerNames
extends RefCounted
## Peer id → character name, for drawing players (nameplates, party frames,
## party notices). The server's holds every peer playing a character
## (AccountService); a client's holds what the server sent it. Never in
## snapshots, and independent of who is in view. Pure logic, unit tested.

var _names: Dictionary[int, String] = {}


## What to show for a player: its character's name, or "Player N" until the
## server has sent it.
func name_of(peer: int) -> String:
	return _names.get(peer, fallback(peer))


static func fallback(peer: int) -> String:
	return "Player %d" % (peer % 10000)


func has(peer: int) -> bool:
	return _names.has(peer)


## True if this changed the table. Empty names and server ids (≤ 0) are ignored.
func put(peer: int, character_name: String) -> bool:
	if peer <= 0 or character_name.is_empty() or _names.get(peer, "") == character_name:
		return false
	_names[peer] = character_name
	return true


## True if the peer had a name.
func forget(peer: int) -> bool:
	return _names.erase(peer)


## Every peer with a name (what the server sends a joiner).
func peers() -> Array[int]:
	var result: Array[int] = []
	for peer: int in _names:
		result.append(peer)
	return result


## {peer: name} for sending; put_all takes it back.
func to_dict() -> Dictionary:
	return _names.duplicate()


## Adds every entry of a to_dict(); returns the peers that changed. Entries
## of the wrong types are skipped.
func put_all(entries: Dictionary) -> Array[int]:
	var changed: Array[int] = []
	for peer: Variant in entries:
		var value: Variant = entries[peer]
		if peer is int and value is String and put(peer, value):
			changed.append(peer)
	return changed


func clear() -> void:
	_names.clear()
