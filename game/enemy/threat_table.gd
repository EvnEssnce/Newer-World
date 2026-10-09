class_name ThreatTable
extends RefCounted
## How much an enemy wants to fight each player (threat per peer id), and which
## one it targets. Pure logic (tests/test_threat_table.gd); EnemyBrain keeps one.
## Server only.
##
## Rules:
## - add() raises a player's threat (damage dealt to the enemy, healing someone
##   it's fighting, coming within its aggro range). Peer ids <= 0 (enemies,
##   unknown sources) are ignored.
## - pick_target() keeps the current target until a challenger's threat beats
##   it by switch_ratio (so aggro doesn't flicker between close values). A
##   forced target (a taunt) wins outright while it's in the table. Ties go to
##   whoever entered the table first.
## - remove() / keep_only() drop players (dead, left, the enemy leashed).
## - taunt() puts a player at the top: at least switch_ratio x the highest
##   threat, so the aggro sticks once the taunt ends.

## Peer id -> threat. Insertion order breaks ties.
var threat: Dictionary[int, float] = {}


## Adds threat for a player (created at 0 first). Returns false for ids <= 0.
func add(peer_id: int, amount: float) -> bool:
	if peer_id <= 0:
		return false
	threat[peer_id] = threat.get(peer_id, 0.0) + maxf(0.0, amount)
	return true


func get_threat(peer_id: int) -> float:
	return threat.get(peer_id, 0.0)


func has(peer_id: int) -> bool:
	return threat.has(peer_id)


func is_empty() -> bool:
	return threat.is_empty()


func remove(peer_id: int) -> void:
	threat.erase(peer_id)


## Drops everyone not in `peers` (a Dictionary keyed by peer id, e.g. the
## living players' positions).
func keep_only(peers: Dictionary) -> void:
	for id: int in threat.keys():
		if not peers.has(id):
			threat.erase(id)


func clear() -> void:
	threat.clear()


## Multiplies every threat by `factor` (0..1 per tick: a slow decay).
func decay(factor: float) -> void:
	if factor >= 1.0:
		return
	for id: int in threat:
		threat[id] *= maxf(0.0, factor)


## The highest threat in the table (0 if empty).
func top_threat() -> float:
	var best := 0.0
	for id: int in threat:
		best = maxf(best, threat[id])
	return best


## The player with the highest threat (the first one added on a tie), or 0.
func top_id() -> int:
	var best_id := 0
	var best := -1.0
	for id: int in threat:
		if threat[id] > best:
			best = threat[id]
			best_id = id
	return best_id


## The target given the current one: `forced` if it's in the table (a taunt);
## else the current target unless someone's threat is above switch_ratio x its
## threat; else (no current target, or it left the table) the top. 0 = nobody.
func pick_target(current: int, switch_ratio: float, forced: int = 0) -> int:
	if forced > 0 and threat.has(forced):
		return forced
	var best := top_id()
	if current <= 0 or not threat.has(current):
		return best
	if best != current and threat[best] > threat[current] * switch_ratio:
		return best
	return current


## A taunt: the player's threat becomes at least switch_ratio x the highest
## threat in the table, so it stays the target after the taunt ends.
func taunt(peer_id: int, switch_ratio: float) -> bool:
	if peer_id <= 0:
		return false
	threat[peer_id] = maxf(get_threat(peer_id), top_threat() * switch_ratio)
	return true
