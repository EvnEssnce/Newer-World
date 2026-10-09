class_name Inventory
extends RefCounted
## One player's bag of items (server-owned; the client gets a copy). A fixed
## number of slots; each item gets a uid when added, which requests (discard,
## and equip later) name it by. Pure logic, unit tested (tests/test_inventory.gd).

var capacity := 0
## In the order they were added.
var items: Array[Item] = []
var _next_uid := 1


func _init(slots: int = 0) -> void:
	capacity = slots


func is_full() -> bool:
	return items.size() >= capacity


func free_slots() -> int:
	return maxi(0, capacity - items.size())


## Adds the item and gives it a new uid. False (and unchanged) when full.
func add(item: Item) -> bool:
	if is_full():
		return false
	item.uid = _next_uid
	_next_uid += 1
	items.append(item)
	return true


func get_item(uid: int) -> Item:
	for item in items:
		if item.uid == uid:
			return item
	return null


## Takes the item out and returns it, or null if there's no such uid.
func remove(uid: int) -> Item:
	for i in items.size():
		if items[i].uid == uid:
			var item := items[i]
			items.remove_at(i)
			return item
	return null


## Item.to_dict() of each, in order: what the server sends its owner.
func to_array() -> Array:
	var data := []
	for item in items:
		data.append(item.to_dict())
	return data


static func items_from_array(data: Array) -> Array[Item]:
	var result: Array[Item] = []
	for entry: Dictionary in data:
		result.append(Item.from_dict(entry))
	return result
