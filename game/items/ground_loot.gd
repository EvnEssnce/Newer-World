class_name GroundLoot
extends RefCounted
## Loot lying in the world, server side. Personal: every drop has one owner
## (the player whose roll it was) and only they can see or pick it up. Drops
## expire after a lifetime. Pure logic, unit tested (tests/test_inventory.gd);
## LootSystem does the networking and visuals.


class Drop:
	var id := 0
	## Peer id of the only player who can see and pick it up.
	var owner := 0
	var position := Vector3.ZERO
	var items: Array[Item] = []
	## Server tick it disappears at.
	var expires_tick := 0


## Drop id -> Drop.
var drops: Dictionary[int, Drop] = {}
var _next_id := 1


func add(owner: int, position: Vector3, items: Array[Item], tick: int, lifetime_ticks: int) -> Drop:
	var drop := Drop.new()
	drop.id = _next_id
	_next_id += 1
	drop.owner = owner
	drop.position = position
	drop.items = items
	drop.expires_tick = tick + lifetime_ticks
	drops[drop.id] = drop
	return drop


## Removes and returns every drop whose time is up at `tick`.
func expire(tick: int) -> Array[Drop]:
	var gone: Array[Drop] = []
	for drop: Drop in drops.values():
		if tick >= drop.expires_tick:
			gone.append(drop)
	for drop in gone:
		drops.erase(drop.id)
	return gone


## The owner's drops within `reach` meters of `position` (horizontal distance,
## so a drop on a slope or a jumping player still counts), nearest first.
func in_reach(owner: int, position: Vector3, reach: float) -> Array[Drop]:
	var found: Array[Drop] = []
	for drop: Drop in drops.values():
		if drop.owner == owner and _flat_distance(drop.position, position) <= reach:
			found.append(drop)
	found.sort_custom(func(a: Drop, b: Drop) -> bool:
			return _flat_distance(a.position, position) < _flat_distance(b.position, position))
	return found


## Moves as many of the drop's items into the inventory as fit, in order.
## Returns the items moved. An emptied drop is removed (check drops.has).
func take_into(drop: Drop, inventory: Inventory) -> Array[Item]:
	var moved: Array[Item] = []
	while not drop.items.is_empty() and inventory.add(drop.items[0]):
		moved.append(drop.items.pop_front())
	if drop.items.is_empty():
		drops.erase(drop.id)
	return moved


## Removes every drop the owner has (they left). Returns how many.
func remove_owner(owner: int) -> int:
	var ids: Array[int] = []
	for drop: Drop in drops.values():
		if drop.owner == owner:
			ids.append(drop.id)
	for id in ids:
		drops.erase(id)
	return ids.size()


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
